import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/remote_profile.dart';
import '../services/live_control_service.dart';
import '../services/remote_control_service.dart';

/// "Canlı Kontrol" sekmesi: bilgisayarin ekranini GERCEK ZAMANLI (surekli
/// video karesi) gosterir, dokunarak tiklama/surukleme ve klavyeyle yazma
/// ile bilgisayari uzaktan, sanki onun basindaymis gibi kullanmayi saglar
/// (bkz. LiveControlSession, main.py - RemoteLiveControlServer). Acilinca
/// ekrani yatay kilitler (bilgisayar ekrani genelde genis oldugu icin) -
/// kapaninca dikey/yatay serbest kalir.
class LiveControlScreen extends StatefulWidget {
  final RemoteProfile profile;
  final void Function(String fingerprint) onFingerprintUpdated;

  const LiveControlScreen({
    super.key,
    required this.profile,
    required this.onFingerprintUpdated,
  });

  @override
  State<LiveControlScreen> createState() => _LiveControlScreenState();
}

enum _ConnectionState { connecting, connected, failed }

class _LiveControlScreenState extends State<LiveControlScreen> {
  final _session = LiveControlSession();
  final _textController = TextEditingController();
  final _textFocusNode = FocusNode();

  _ConnectionState _state = _ConnectionState.connecting;
  String? _error;

  ui.Image? _currentImage;
  Uint8List? _pendingFrame;
  bool _decoding = false;

  bool _keyboardBarVisible = false;
  String _lastSentText = '';
  Offset? _lastNormalizedPosition;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _connect();
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([]);
    _session.close();
    _currentImage?.dispose();
    _textController.dispose();
    _textFocusNode.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final profile = widget.profile;
    try {
      final fingerprint = await _session.connect(
        ip: profile.ip,
        port: liveControlPortFor(profile.port),
        pin: profile.pin,
        pinnedFingerprint: profile.certFingerprint,
        onFrame: _onFrame,
        onDisconnected: _onDisconnected,
      );
      if (fingerprint != profile.certFingerprint) {
        widget.onFingerprintUpdated(fingerprint);
      }
      if (!mounted) return;
      setState(() => _state = _ConnectionState.connected);
    } on RemoteControlException catch (exc) {
      if (!mounted) return;
      setState(() {
        _state = _ConnectionState.failed;
        _error = exc.message;
      });
    } catch (exc) {
      if (!mounted) return;
      setState(() {
        _state = _ConnectionState.failed;
        _error = 'Bağlanılamadı: $exc';
      });
    }
  }

  void _onDisconnected() {
    if (!mounted) return;
    setState(() {
      _state = _ConnectionState.failed;
      _error ??= 'Bağlantı kesildi.';
    });
  }

  void _onFrame(Uint8List jpeg) {
    _pendingFrame = jpeg;
    unawaited(_maybeDecodeNext());
  }

  /// Kareler ~12/sn geliyor ama kod cozme (decode) bazen daha yavas
  /// kalabilir - bu yuzden ayni anda tek bir kod cozme calisir, arada
  /// biriken kareler atlanip her zaman EN SON gelen kare islenir (boylece
  /// gecikme birikip "geriden" gitmek yerine sabit kalir).
  Future<void> _maybeDecodeNext() async {
    if (_decoding) return;
    final frame = _pendingFrame;
    if (frame == null) return;
    _pendingFrame = null;
    _decoding = true;
    try {
      final image = await ui.instantiateImageCodec(frame).then((codec) async {
        final frameInfo = await codec.getNextFrame();
        codec.dispose();
        return frameInfo.image;
      });
      if (!mounted) {
        image.dispose();
        return;
      }
      final old = _currentImage;
      setState(() => _currentImage = image);
      old?.dispose();
    } catch (_) {
      // Bozuk/eksik bir kare - yoksay, bir sonrakini bekle.
    } finally {
      _decoding = false;
      if (_pendingFrame != null) {
        unawaited(_maybeDecodeNext());
      }
    }
  }

  void _handlePanDown(DragDownDetails details, Size widgetSize) {
    final image = _currentImage;
    if (image == null) return;
    final normalized = mapTouchToNormalized(
      details.localPosition,
      widgetSize,
      Size(image.width.toDouble(), image.height.toDouble()),
    );
    if (normalized == null) return;
    _lastNormalizedPosition = normalized;
    _session.sendMove(normalized.dx, normalized.dy);
    _session.sendMouseDown();
  }

  void _handlePanUpdate(DragUpdateDetails details, Size widgetSize) {
    final image = _currentImage;
    if (image == null) return;
    final normalized = mapTouchToNormalized(
      details.localPosition,
      widgetSize,
      Size(image.width.toDouble(), image.height.toDouble()),
    );
    if (normalized == null) return;
    _lastNormalizedPosition = normalized;
    _session.sendMove(normalized.dx, normalized.dy);
  }

  void _handlePanEnd(DragEndDetails details) {
    _session.sendMouseUp();
  }

  void _sendRightClick() {
    final position = _lastNormalizedPosition;
    if (position != null) {
      _session.sendMove(position.dx, position.dy);
    }
    _session.sendClick(button: 'right');
  }

  void _toggleKeyboardBar() {
    setState(() => _keyboardBarVisible = !_keyboardBarVisible);
    if (_keyboardBarVisible) {
      _textFocusNode.requestFocus();
    } else {
      _textFocusNode.unfocus();
    }
  }

  void _onTypedTextChanged(String newText) {
    final diff = diffTypedText(_lastSentText, newText);
    for (var i = 0; i < diff.backspaces; i++) {
      _session.sendKeyTap('backspace');
    }
    _session.sendText(diff.insert);
    _lastSentText = newText;
  }

  void _sendSpecialKeyAndResetBuffer(String keyName) {
    _session.sendKeyTap(keyName);
    _textController.clear();
    _lastSentText = '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: _buildVideoArea()),
            Positioned(
              top: 8,
              left: 8,
              child: _RoundIconButton(
                icon: Icons.arrow_back,
                tooltip: 'Kapat',
                onTap: () => Navigator.of(context).pop(),
              ),
            ),
            if (_state == _ConnectionState.connected) ...[
              Positioned(
                top: 8,
                right: 8,
                child: _RoundIconButton(
                  icon: _keyboardBarVisible ? Icons.keyboard_hide : Icons.keyboard,
                  tooltip: 'Klavye',
                  onTap: _toggleKeyboardBar,
                ),
              ),
              Positioned(
                bottom: _keyboardBarVisible ? 76 : 8,
                right: 8,
                child: Column(
                  children: [
                    _RoundIconButton(
                      icon: Icons.expand_less,
                      tooltip: 'Yukarı kaydır',
                      onTap: () => _session.sendScroll(-3),
                    ),
                    const SizedBox(height: 8),
                    _RoundIconButton(
                      icon: Icons.expand_more,
                      tooltip: 'Aşağı kaydır',
                      onTap: () => _session.sendScroll(3),
                    ),
                    const SizedBox(height: 8),
                    _RoundIconButton(
                      icon: Icons.mouse,
                      tooltip: 'Sağ tık',
                      onTap: _sendRightClick,
                    ),
                  ],
                ),
              ),
              if (_keyboardBarVisible)
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 8,
                  child: _buildKeyboardBar(),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildVideoArea() {
    if (_state == _ConnectionState.failed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 40),
              const SizedBox(height: 12),
              Text(
                _error ?? 'Bağlantı kesildi.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () {
                  setState(() {
                    _state = _ConnectionState.connecting;
                    _error = null;
                  });
                  _connect();
                },
                child: const Text('Tekrar Dene'),
              ),
            ],
          ),
        ),
      );
    }
    if (_currentImage == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white70),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final widgetSize = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          onPanDown: (details) => _handlePanDown(details, widgetSize),
          onPanUpdate: (details) => _handlePanUpdate(details, widgetSize),
          onPanEnd: _handlePanEnd,
          onPanCancel: () => _session.sendMouseUp(),
          child: RawImage(image: _currentImage, fit: BoxFit.contain),
        );
      },
    );
  }

  Widget _buildKeyboardBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              focusNode: _textFocusNode,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Yazmak için dokun...',
                hintStyle: TextStyle(color: Colors.white54),
              ),
              onChanged: _onTypedTextChanged,
              onSubmitted: (_) => _sendSpecialKeyAndResetBuffer('enter'),
            ),
          ),
          IconButton(
            tooltip: 'Enter',
            icon: const Icon(Icons.keyboard_return, color: Colors.white),
            onPressed: () => _sendSpecialKeyAndResetBuffer('enter'),
          ),
          IconButton(
            tooltip: 'Esc',
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => _session.sendKeyTap('esc'),
          ),
          IconButton(
            tooltip: 'Tab',
            icon: const Icon(Icons.keyboard_tab, color: Colors.white),
            onPressed: () => _session.sendKeyTap('tab'),
          ),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _RoundIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black54,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }
}
