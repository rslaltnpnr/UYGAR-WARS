import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../models/remote_profile.dart';
import '../services/remote_control_service.dart';
import '../services/settings_service.dart';
import '../theme/app_colors.dart';

/// "Bilgisayari Kumanda Et" paneli: masaustundeki kedi uygulamasina
/// (ayni Wi-Fi agindan, PIN ile) bir baglanti gonderip acilmasini
/// saglar - orn. bir YouTube linki gonderirseniz bilgisayarda muzik/
/// video calar. Birden fazla bilgisayarla (ev/is gibi) eslesip
/// aralarinda gecis yapabilirsiniz.
class RemoteControlSheet extends StatefulWidget {
  final SettingsService settings;

  /// Baska bir uygulamadan "Paylas" ile gelen bir link varsa, "Acilacak
  /// baglanti" alanini onceden doldurmak icin kullanilir.
  final String? initialUrl;

  const RemoteControlSheet({super.key, required this.settings, this.initialUrl});

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

  late List<RemoteProfile> _profiles;
  String? _activeProfileId;

  final _nameController = TextEditingController();
  final _ipController = TextEditingController();
  final _portController = TextEditingController();
  final _pinController = TextEditingController();
  final _urlController = TextEditingController();
  final _service = RemoteControlService();

  bool _busy = false;
  String? _status;
  bool _statusIsError = false;

  @override
  void initState() {
    super.initState();
    _profiles = widget.settings.remoteProfiles;
    _activeProfileId = widget.settings.activeProfileId ??
        (_profiles.isNotEmpty ? _profiles.first.id : null);
    _loadActiveProfileIntoFields();
    if (widget.initialUrl != null && widget.initialUrl!.isNotEmpty) {
      _urlController.text = widget.initialUrl!;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ipController.dispose();
    _portController.dispose();
    _pinController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  RemoteProfile? get _activeProfile {
    if (_profiles.isEmpty) return null;
    for (final p in _profiles) {
      if (p.id == _activeProfileId) return p;
    }
    return _profiles.first;
  }

  void _loadActiveProfileIntoFields() {
    final p = _activeProfile;
    _nameController.text = p?.name ?? '';
    _ipController.text = p?.ip ?? '';
    _portController.text = (p?.port ?? 8765).toString();
    _pinController.text = p?.pin ?? '';
  }

  void _persistProfiles() {
    widget.settings.remoteProfiles = _profiles;
    widget.settings.activeProfileId = _activeProfileId;
  }

  void _saveConnectionInfo() {
    final current = _activeProfile;
    if (current == null) return;
    final updated = current.copyWith(
      name: _nameController.text.trim().isEmpty
          ? current.name
          : _nameController.text.trim(),
      ip: _ipController.text.trim(),
      port: int.tryParse(_portController.text.trim()) ?? 8765,
      pin: _pinController.text.trim(),
    );
    setState(() {
      _profiles = _profiles.map((p) => p.id == updated.id ? updated : p).toList();
    });
    _persistProfiles();
  }

  void _updateActiveFingerprint(String fingerprint) {
    final current = _activeProfile;
    if (current == null) return;
    final updated = current.copyWith(certFingerprint: fingerprint);
    setState(() {
      _profiles = _profiles.map((p) => p.id == updated.id ? updated : p).toList();
    });
    _persistProfiles();
  }

  void _resetCertificatePairing() {
    _updateActiveFingerprint('');
    setState(() {
      _status = 'Sertifika eşleştirmesi sıfırlandı. Bir sonraki bağlantıda '
          'yeniden kaydedilecek.';
      _statusIsError = false;
    });
  }

  Future<void> _switchProfile(String? id) async {
    if (id == null || id == _activeProfileId) return;
    _saveConnectionInfo();
    setState(() {
      _activeProfileId = id;
      _status = null;
    });
    widget.settings.activeProfileId = id;
    _loadActiveProfileIntoFields();
  }

  Future<void> _addProfile() async {
    final controller = TextEditingController(
      text: 'Bilgisayar ${_profiles.length + 1}',
    );
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Yeni Bilgisayar Ekle'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'İsim (örn. Ev, İş)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Ekle'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final profile = RemoteProfile(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      ip: '',
      port: 8765,
      pin: '',
      certFingerprint: '',
    );
    setState(() {
      _profiles = [..._profiles, profile];
      _activeProfileId = profile.id;
      _status = null;
    });
    _persistProfiles();
    _loadActiveProfileIntoFields();
  }

  Future<void> _deleteActiveProfile() async {
    final current = _activeProfile;
    if (current == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Bilgisayarı Sil'),
        content: Text('"${current.name}" profili silinsin mi?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _profiles = _profiles.where((p) => p.id != current.id).toList();
      _activeProfileId = _profiles.isNotEmpty ? _profiles.first.id : null;
      _status = null;
    });
    _persistProfiles();
    _loadActiveProfileIntoFields();
  }

  Future<void> _send() async {
    if (_busy || _activeProfile == null) return;
    _saveConnectionInfo();
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final result = await _service.openUrl(
        ip: _ipController.text.trim(),
        port: int.tryParse(_portController.text.trim()) ?? 8765,
        pin: _pinController.text.trim(),
        url: _urlController.text,
        pinnedFingerprint: _activeProfile?.certFingerprint ?? '',
      );
      _updateActiveFingerprint(result.fingerprint);
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

  Future<void> _sendMedia(String action) async {
    if (_busy || _activeProfile == null) return;
    _saveConnectionInfo();
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final result = await _service.sendMedia(
        ip: _ipController.text.trim(),
        port: int.tryParse(_portController.text.trim()) ?? 8765,
        pin: _pinController.text.trim(),
        action: action,
        pinnedFingerprint: _activeProfile?.certFingerprint ?? '',
      );
      _updateActiveFingerprint(result.fingerprint);
      if (!mounted) return;
      setState(() {
        _status = 'Gönderildi.';
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

  Future<void> _confirmAndSendPower(String action, String label) async {
    if (_busy || _activeProfile == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('$label onayı'),
        content: Text('Bilgisayarı $label istiyor musunuz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Evet'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    _saveConnectionInfo();
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final result = await _service.sendPower(
        ip: _ipController.text.trim(),
        port: int.tryParse(_portController.text.trim()) ?? 8765,
        pin: _pinController.text.trim(),
        action: action,
        pinnedFingerprint: _activeProfile?.certFingerprint ?? '',
      );
      _updateActiveFingerprint(result.fingerprint);
      if (!mounted) return;
      setState(() {
        _status = 'Gönderildi.';
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

  Future<void> _takeScreenshot() async {
    if (_busy || _activeProfile == null) return;
    _saveConnectionInfo();
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final result = await _service.fetchScreenshot(
        ip: _ipController.text.trim(),
        port: int.tryParse(_portController.text.trim()) ?? 8765,
        pin: _pinController.text.trim(),
        pinnedFingerprint: _activeProfile?.certFingerprint ?? '',
      );
      _updateActiveFingerprint(result.fingerprint);
      if (!mounted) return;
      setState(() => _busy = false);
      showDialog(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: Colors.black,
          insetPadding: const EdgeInsets.all(12),
          child: InteractiveViewer(
            child: Image.memory(result.imageBytes),
          ),
        ),
      );
    } catch (exc) {
      if (!mounted) return;
      setState(() {
        _status = exc.toString();
        _statusIsError = true;
        _busy = false;
      });
    }
  }

  Future<void> _pushClipboard() async {
    if (_busy || _activeProfile == null) return;
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    final text = clipboardData?.text ?? '';
    if (text.isEmpty) {
      setState(() {
        _status = 'Panonda gönderilecek metin yok.';
        _statusIsError = true;
      });
      return;
    }
    _saveConnectionInfo();
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final result = await _service.pushClipboard(
        ip: _ipController.text.trim(),
        port: int.tryParse(_portController.text.trim()) ?? 8765,
        pin: _pinController.text.trim(),
        text: text,
        pinnedFingerprint: _activeProfile?.certFingerprint ?? '',
      );
      _updateActiveFingerprint(result.fingerprint);
      if (!mounted) return;
      setState(() {
        _status = 'Pano bilgisayara gönderildi.';
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

  Future<void> _pullClipboard() async {
    if (_busy || _activeProfile == null) return;
    _saveConnectionInfo();
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final result = await _service.pullClipboard(
        ip: _ipController.text.trim(),
        port: int.tryParse(_portController.text.trim()) ?? 8765,
        pin: _pinController.text.trim(),
        pinnedFingerprint: _activeProfile?.certFingerprint ?? '',
      );
      _updateActiveFingerprint(result.fingerprint);
      if (result.text.isEmpty) {
        if (!mounted) return;
        setState(() {
          _status = 'Bilgisayarın panosu boş.';
          _statusIsError = false;
        });
        return;
      }
      await Clipboard.setData(ClipboardData(text: result.text));
      if (!mounted) return;
      setState(() {
        _status = 'Bilgisayarın panosu telefonuna kopyalandı.';
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
    final hasProfile = _activeProfile != null;
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.92,
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
                  'olmalı. Birden fazla bilgisayarla eşleşip aralarında '
                  'geçiş yapabilirsiniz.',
                  style: TextStyle(color: colors.textMuted, fontSize: 12),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _profiles.isEmpty
                          ? Text(
                              'Henüz bir bilgisayar eklenmedi.',
                              style: TextStyle(color: colors.textMuted, fontSize: 13),
                            )
                          : DropdownButtonFormField<String>(
                              initialValue: _activeProfileId,
                              isExpanded: true,
                              dropdownColor: colors.panel,
                              style: TextStyle(color: colors.textPrimary),
                              decoration: InputDecoration(
                                labelText: 'Bilgisayar',
                                labelStyle: TextStyle(color: colors.textMuted),
                              ),
                              items: _profiles
                                  .map(
                                    (p) => DropdownMenuItem(
                                      value: p.id,
                                      child: Text(p.name),
                                    ),
                                  )
                                  .toList(),
                              onChanged: _switchProfile,
                            ),
                    ),
                    IconButton(
                      icon: Icon(Icons.add_circle_outline, color: colors.accent),
                      tooltip: 'Yeni Bilgisayar Ekle',
                      onPressed: _addProfile,
                    ),
                    if (hasProfile)
                      IconButton(
                        icon: Icon(Icons.delete_outline, color: colors.textMuted),
                        tooltip: 'Bilgisayarı Sil',
                        onPressed: _deleteActiveProfile,
                      ),
                  ],
                ),
                if (hasProfile) ...[
                  const SizedBox(height: 6),
                  _field(_nameController, 'İsim'),
                  const SizedBox(height: 10),
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
                  Divider(color: colors.divider, height: 32),
                  Text(
                    'Medya Kontrolü',
                    style: TextStyle(color: colors.textMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        icon: Icon(Icons.skip_previous, color: colors.textPrimary),
                        onPressed: _busy ? null : () => _sendMedia('prev'),
                      ),
                      IconButton(
                        icon: Icon(Icons.play_arrow, color: colors.textPrimary),
                        onPressed: _busy ? null : () => _sendMedia('play_pause'),
                      ),
                      IconButton(
                        icon: Icon(Icons.skip_next, color: colors.textPrimary),
                        onPressed: _busy ? null : () => _sendMedia('next'),
                      ),
                      IconButton(
                        icon: Icon(Icons.volume_down, color: colors.textPrimary),
                        onPressed: _busy ? null : () => _sendMedia('vol_down'),
                      ),
                      IconButton(
                        icon: Icon(Icons.volume_up, color: colors.textPrimary),
                        onPressed: _busy ? null : () => _sendMedia('vol_up'),
                      ),
                      IconButton(
                        icon: Icon(Icons.volume_off, color: colors.textPrimary),
                        onPressed: _busy ? null : () => _sendMedia('mute'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy
                              ? null
                              : () => _confirmAndSendPower('lock', 'kilitlemek'),
                          icon: const Icon(Icons.lock_outline),
                          label: const Text('Kilitle'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy
                              ? null
                              : () => _confirmAndSendPower(
                                  'sleep', 'uyku moduna almak'),
                          icon: const Icon(Icons.bedtime_outlined),
                          label: const Text('Uyku'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _takeScreenshot,
                    icon: const Icon(Icons.screenshot_monitor),
                    label: const Text('Ekran Görüntüsü Al'),
                  ),
                  Divider(color: colors.divider, height: 32),
                  Text(
                    'Pano Senkronizasyonu',
                    style: TextStyle(color: colors.textMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : _pushClipboard,
                          icon: const Icon(Icons.upload_outlined),
                          label: const Text('Panomu Gönder'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : _pullClipboard,
                          icon: const Icon(Icons.download_outlined),
                          label: const Text('Panosunu Al'),
                        ),
                      ),
                    ],
                  ),
                ],
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
