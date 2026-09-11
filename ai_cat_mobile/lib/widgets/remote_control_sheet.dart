import 'package:flutter/material.dart';

import '../services/remote_control_service.dart';
import '../services/settings_service.dart';
import '../theme/app_colors.dart';

/// "Bilgisayari Kumanda Et" paneli: masaustundeki kedi uygulamasina
/// (ayni Wi-Fi agindan, PIN ile) bir baglanti gonderip acilmasini
/// saglar - orn. bir YouTube linki gonderirseniz bilgisayarda muzik/
/// video calar.
class RemoteControlSheet extends StatefulWidget {
  final SettingsService settings;

  const RemoteControlSheet({super.key, required this.settings});

  @override
  State<RemoteControlSheet> createState() => _RemoteControlSheetState();
}

class _RemoteControlSheetState extends State<RemoteControlSheet> {
  static const _presets = <String, String>{
    'YouTube': 'https://youtube.com',
    'YouTube Music': 'https://music.youtube.com',
    'Spotify': 'https://open.spotify.com',
    'Google': 'https://google.com',
  };

  late final TextEditingController _ipController;
  late final TextEditingController _portController;
  late final TextEditingController _pinController;
  final _urlController = TextEditingController();
  final _service = RemoteControlService();

  bool _busy = false;
  String? _status;
  bool _statusIsError = false;

  @override
  void initState() {
    super.initState();
    _ipController = TextEditingController(text: widget.settings.desktopIp);
    _portController = TextEditingController(
      text: widget.settings.desktopPort.toString(),
    );
    _pinController = TextEditingController(text: widget.settings.desktopPin);
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    _pinController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  void _saveConnectionInfo() {
    widget.settings.desktopIp = _ipController.text.trim();
    widget.settings.desktopPort =
        int.tryParse(_portController.text.trim()) ?? 8765;
    widget.settings.desktopPin = _pinController.text.trim();
  }

  void _resetCertificatePairing() {
    widget.settings.desktopCertFingerprint = '';
    setState(() {
      _status = 'Sertifika eşleştirmesi sıfırlandı. Bir sonraki bağlantıda '
          'yeniden kaydedilecek.';
      _statusIsError = false;
    });
  }

  Future<void> _send() async {
    if (_busy) return;
    _saveConnectionInfo();
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final result = await _service.openUrl(
        ip: widget.settings.desktopIp,
        port: widget.settings.desktopPort,
        pin: widget.settings.desktopPin,
        url: _urlController.text,
        pinnedFingerprint: widget.settings.desktopCertFingerprint,
      );
      widget.settings.desktopCertFingerprint = result.fingerprint;
      if (!mounted) return;
      setState(() {
        _status = 'Gönderildi! Bilgisayarda açılması lazım.';
        _statusIsError = false;
      });
    } catch (exc) {
      if (!mounted) return;
      setState(() {
        _status = exc.toString();
        _statusIsError = true;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: colors.panelTranslucent,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.fromLTRB(
            16,
            12,
            16,
            MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: SingleChildScrollView(
            controller: scrollController,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '\u{1F4BB} Bilgisayarı Kumanda Et',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: colors.textSecondary),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Bilgisayardaki kedi uygulamasında sağ tık menüsünden '
                  '"Uzaktan Kumanda Bilgisi"ni açıp buradaki IP, port ve '
                  'PIN\'i bir kez girin. İkisi de aynı Wi-Fi ağına bağlı '
                  'olmalı.',
                  style: TextStyle(color: colors.textMuted, fontSize: 12),
                ),
                const SizedBox(height: 16),
                _field(_ipController, 'Bilgisayar IP (örn. 192.168.1.20)'),
                const SizedBox(height: 10),
                _field(
                  _portController,
                  'Port',
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 10),
                _field(_pinController, 'PIN'),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _resetCertificatePairing,
                    icon: Icon(Icons.lock_reset,
                        size: 16, color: colors.textMuted),
                    label: Text(
                      'Sertifika eşleştirmesini sıfırla',
                      style: TextStyle(color: colors.textMuted, fontSize: 12),
                    ),
                  ),
                ),
                Divider(color: colors.divider, height: 32),
                _field(_urlController, 'Açılacak bağlantı (https://...)'),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _presets.entries
                      .map(
                        (preset) => ActionChip(
                          label: Text(preset.key),
                          labelStyle: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 12,
                          ),
                          backgroundColor: colors.textPrimary.withValues(alpha: 0.1),
                          side: BorderSide(color: colors.divider),
                          onPressed: () => setState(
                              () => _urlController.text = preset.value),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 14),
                ElevatedButton.icon(
                  onPressed: _busy ? null : _send,
                  icon: _busy
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colors.textPrimary,
                          ),
                        )
                      : const Icon(Icons.send),
                  label: const Text('Bilgisayarda Aç'),
                ),
                if (_status != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _status!,
                    style: TextStyle(
                      color: _statusIsError ? colors.error : colors.success,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    TextInputType? keyboardType,
  }) {
    final colors = context.colors;
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: TextStyle(color: colors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: colors.textMuted),
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: colors.divider),
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: colors.accent),
        ),
      ),
    );
  }
}
