import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/remote_profile.dart';
import '../services/active_profile.dart';
import '../services/gemini_service.dart';
import '../services/remote_control_service.dart';
import '../services/screen_watch_overlay_service.dart';
import '../services/settings_service.dart';

/// "Ekranda Gez" balonunun kendi Flutter motoruyla calisan ayri uygulamasi
/// - main.dart'taki overlayMain() bunu calistirir. Ana uygulamadan TAMAMEN
/// ayri bir isolate/engine oldugu icin widget state'i paylasamaz; bu yuzden
/// kendi SharedPreferences okumasini yapar (ayni native depolamaya erisir,
/// sadece bellekte paylasilmaz) ve RemoteControlService/GeminiService'i
/// (ikisi de saf Dart soket/HTTP kodu, platform kanali gerektirmez)
/// dogrudan kendi icinde ornekler.
class ScreenWatchOverlayApp extends StatelessWidget {
  const ScreenWatchOverlayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const _ScreenWatchOverlay(),
    );
  }
}

class _ScreenWatchOverlay extends StatefulWidget {
  const _ScreenWatchOverlay();

  @override
  State<_ScreenWatchOverlay> createState() => _ScreenWatchOverlayState();
}

class _ScreenWatchOverlayState extends State<_ScreenWatchOverlay> {
  final _remoteService = RemoteControlService();
  final _geminiService = GeminiService();
  final _questionController = TextEditingController();

  bool _expanded = false;
  Timer? _pollTimer;
  bool _fetchingScreenshot = false;

  SettingsService? _settings;
  RemoteProfile? _profile;
  Uint8List? _screenshotBytes;
  String? _screenshotError;

  bool _asking = false;
  String? _answer;
  String? _answerError;

  @override
  void dispose() {
    _pollTimer?.cancel();
    _questionController.dispose();
    super.dispose();
  }

  Future<void> _expand() async {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final screenHeightPx = MediaQuery.of(context).size.height * dpr;
    await FlutterOverlayWindow.updateFlag(OverlayFlag.focusPointer);
    await FlutterOverlayWindow.resizeOverlay(
      WindowSize.matchParent,
      ScreenWatchOverlaySizes.panelHeightPx(dpr, screenHeightPx),
      false,
    );
    if (!mounted) return;
    setState(() => _expanded = true);
    await _loadProfile();
    _startPolling();
  }

  Future<void> _collapse() async {
    _stopPolling();
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final size = ScreenWatchOverlaySizes.bubbleDiameterPx(dpr);
    await FlutterOverlayWindow.updateFlag(OverlayFlag.defaultFlag);
    await FlutterOverlayWindow.resizeOverlay(size, size, true);
    if (!mounted) return;
    setState(() => _expanded = false);
  }

  Future<void> _dismiss() async {
    _stopPolling();
    await FlutterOverlayWindow.closeOverlay();
  }

  void _startPolling() {
    _fetchScreenshot();
    _pollTimer = Timer.periodic(
      const Duration(milliseconds: 1500),
      (_) => _fetchScreenshot(),
    );
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsService(prefs);
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _profile = resolveActiveProfile(
        settings.remoteProfiles,
        settings.activeProfileId,
      );
    });
  }

  Future<void> _fetchScreenshot() async {
    final profile = _profile;
    if (profile == null || _fetchingScreenshot) return;
    _fetchingScreenshot = true;
    try {
      final result = await _remoteService.fetchScreenshot(
        ip: profile.ip,
        port: profile.port,
        pin: profile.pin,
        pinnedFingerprint: profile.certFingerprint,
      );
      _persistFingerprintIfChanged(profile, result.fingerprint);
      if (!mounted) return;
      setState(() {
        _screenshotBytes = result.imageBytes;
        _screenshotError = null;
      });
    } catch (exc) {
      if (!mounted) return;
      setState(() => _screenshotError = exc.toString());
    } finally {
      _fetchingScreenshot = false;
    }
  }

  /// Ilk baglantida guven (TOFU): bilgisayarin sertifika parmak izi
  /// degistiyse (ilk kez goruluyorsa) kalici olarak kaydeder - diger
  /// uzaktan komut ekranlarindaki ayni davranis (bkz.
  /// RemoteControlSheet._updateFingerprintFor).
  void _persistFingerprintIfChanged(RemoteProfile profile, String fingerprint) {
    final settings = _settings;
    if (settings == null || fingerprint == profile.certFingerprint) return;
    final updated = profile.copyWith(certFingerprint: fingerprint);
    settings.remoteProfiles = settings.remoteProfiles
        .map((p) => p.id == updated.id ? updated : p)
        .toList();
    if (mounted) setState(() => _profile = updated);
  }

  Future<void> _ask() async {
    final settings = _settings;
    final question = _questionController.text.trim();
    if (settings == null || question.isEmpty || _asking) return;
    setState(() {
      _asking = true;
      _answerError = null;
    });
    try {
      final answer = await _geminiService.ask(
        apiKey: settings.apiKey,
        modelName: settings.modelName,
        characterName: settings.characterName,
        question: question,
        imageBytes: _screenshotBytes,
      );
      if (!mounted) return;
      setState(() {
        _answer = answer;
        _questionController.clear();
      });
    } catch (exc) {
      if (!mounted) return;
      setState(() => _answerError = exc.toString());
    } finally {
      if (mounted) setState(() => _asking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: _expanded ? _buildPanel() : _buildBubble(),
    );
  }

  Widget _buildBubble() {
    return GestureDetector(
      onTap: _expand,
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF7C4DFF),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.remove_red_eye, color: Colors.white),
      ),
    );
  }

  Widget _buildPanel() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1B1B24),
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Bilgisayar Ekranı',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.remove, size: 20),
                tooltip: 'Küçült',
                onPressed: _collapse,
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                tooltip: 'Kapat',
                onPressed: _dismiss,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(child: _buildScreenshotArea()),
          const SizedBox(height: 8),
          if (_answer != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(8),
              ),
              constraints: const BoxConstraints(maxHeight: 100),
              child: SingleChildScrollView(child: Text(_answer!)),
            ),
          if (_answerError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _answerError!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _questionController,
                  enabled: !_asking,
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Ekran hakkında bir şey sor...',
                  ),
                  onSubmitted: (_) => _ask(),
                ),
              ),
              IconButton(
                icon: _asking
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                onPressed: _asking ? null : _ask,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScreenshotArea() {
    if (_profile == null) {
      return const Center(
        child: Text(
          'Önce uygulamada bir bilgisayarla eşleşin.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12),
        ),
      );
    }
    if (_screenshotError != null && _screenshotBytes == null) {
      return Center(
        child: Text(
          _screenshotError!,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.redAccent, fontSize: 12),
        ),
      );
    }
    if (_screenshotBytes == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.memory(
        _screenshotBytes!,
        fit: BoxFit.contain,
        gaplessPlayback: true,
      ),
    );
  }
}
