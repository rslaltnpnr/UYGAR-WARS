import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../models/command_macro.dart';
import '../models/queued_command.dart';
import '../models/remote_profile.dart';
import '../screens/automation_rules_screen.dart';
import '../screens/command_history_screen.dart';
import '../screens/live_control_screen.dart';
import '../screens/qr_pairing_scanner_screen.dart';
import '../screens/voice_agent_screen.dart';
import '../services/command_history_service.dart';
import '../services/command_queue_service.dart';
import '../services/macro_service.dart';
import '../services/pairing_uri.dart';
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

  /// Makro olusturma dialogunda secilebilen, URL disindaki hazir adimlar -
  /// anahtar "tur:aksiyon" seklinde, RemoteControlService'in media/power
  /// endpoint'lerinin bekledigi aksiyon adiyla birebir eslesir.
  static const _macroStepChoices = <String, String>{
    'media:play_pause': 'Oynat/Duraklat',
    'media:prev': 'Önceki',
    'media:next': 'Sonraki',
    'media:vol_up': 'Sesi Aç',
    'media:vol_down': 'Sesi Kıs',
    'media:mute': 'Sessize Al',
    'power:lock': 'Kilitle',
    'power:sleep': 'Uyku Moduna Al',
  };

  late List<RemoteProfile> _profiles;
  String? _activeProfileId;

  final _nameController = TextEditingController();
  final _ipController = TextEditingController();
  final _portController = TextEditingController();
  final _pinController = TextEditingController();
  final _urlController = TextEditingController();
  final _service = RemoteControlService();
  final _queueService = CommandQueueService();
  final _macroService = MacroService();
  final _commandHistory = CommandHistoryService();

  bool _busy = false;
  String? _status;
  bool _statusIsError = false;
  int _queuedCount = 0;
  List<CommandMacro> _macros = [];

  @override
  void initState() {
    super.initState();
    _profiles = widget.settings.remoteProfiles;
    _activeProfileId = widget.settings.activeProfileId ??
        (_profiles.isNotEmpty ? _profiles.first.id : null);
    _loadActiveProfileIntoFields();
    _refreshQueuedCount();
    _refreshMacros();
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
    _updateFingerprintFor(current.id, fingerprint);
  }

  void _updateFingerprintFor(String profileId, String fingerprint) {
    setState(() {
      _profiles = _profiles
          .map(
            (p) =>
                p.id == profileId ? p.copyWith(certFingerprint: fingerprint) : p,
          )
          .toList();
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
    _refreshQueuedCount();
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

  /// Masaustu uygulamasindaki "Uzaktan Kumanda" penceresindeki QR kodu
  /// tarayip IP/Port/PIN/sertifika parmak izini elle yazmadan yeni bir
  /// profil olusturur - _addProfile()'in ayni akisi, sadece bos alanlar
  /// yerine taranan degerlerle doldurulmus olarak.
  Future<void> _addProfileFromQr() async {
    final result = await Navigator.of(context).push<PairingInfo>(
      MaterialPageRoute(builder: (_) => const QrPairingScannerScreen()),
    );
    if (result == null || !mounted) return;

    final controller = TextEditingController(
      text: 'Bilgisayar ${_profiles.length + 1}',
    );
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Taranan Bilgisayarı Ekle'),
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
      ip: result.ip,
      port: result.port,
      pin: result.pin,
      certFingerprint: result.certFingerprint,
    );
    setState(() {
      _profiles = [..._profiles, profile];
      _activeProfileId = profile.id;
      _status = 'QR koddan okundu: "$name" eklendi.';
      _statusIsError = false;
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
    final profile = _activeProfile;
    if (_busy || profile == null) return;
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
        pinnedFingerprint: profile.certFingerprint,
      );
      _updateActiveFingerprint(result.fingerprint);
      await _commandHistory.add(
        action: 'Bağlantı Aç',
        detail: _urlController.text.trim(),
        profileName: profile.name,
      );
      if (!mounted) return;
      setState(() {
        _status = 'Gönderildi! Bilgisayarda açılması lazım.';
        _statusIsError = false;
      });
    } catch (exc) {
      if (exc is RemoteControlException && exc.isNetworkError) {
        await _queueService.enqueue(
          QueuedCommand(
            profileId: profile.id,
            url: _urlController.text.trim(),
            queuedAt: DateTime.now(),
          ),
        );
        await _refreshQueuedCount();
        if (!mounted) return;
        setState(() {
          _status = 'Bağlantı yok - komut kuyruğa eklendi, bilgisayara '
              'ulaşılınca otomatik gönderilecek.';
          _statusIsError = false;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _status = exc.toString();
          _statusIsError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Ayni baglantiyi eslesik TUM bilgisayarlara (yalnizca birine degil)
  /// sirayla gonderir - orn. hem ev hem is bilgisayarinda ayni muzigi
  /// baslatmak icin. Her biri kendi basina degerlendirilir: birine
  /// ulasilamazsa o profil icin komut kuyruga alinir (bkz. _send), digerleri
  /// yine de denenir - tek bir bilgisayarin ag disinda olmasi digerlerine
  /// gonderimi engellemez.
  Future<void> _sendToAllProfiles() async {
    if (_busy || _profiles.isEmpty) return;
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() {
        _status = 'Açılacak bir bağlantı yaz.';
        _statusIsError = true;
      });
      return;
    }
    _saveConnectionInfo();
    setState(() {
      _busy = true;
      _status = null;
    });

    var sentCount = 0;
    var queuedCount = 0;
    var failedCount = 0;
    for (final profile in _profiles) {
      try {
        final result = await _service.openUrl(
          ip: profile.ip,
          port: profile.port,
          pin: profile.pin,
          url: url,
          pinnedFingerprint: profile.certFingerprint,
        );
        _updateFingerprintFor(profile.id, result.fingerprint);
        sentCount++;
      } catch (exc) {
        if (exc is RemoteControlException && exc.isNetworkError) {
          await _queueService.enqueue(
            QueuedCommand(
              profileId: profile.id,
              url: url,
              queuedAt: DateTime.now(),
            ),
          );
          queuedCount++;
        } else {
          failedCount++;
        }
      }
    }

    await _refreshQueuedCount();
    if (!mounted) return;
    setState(() {
      _busy = false;
      final parts = <String>[
        if (sentCount > 0) '$sentCount gönderildi',
        if (queuedCount > 0) '$queuedCount kuyruğa eklendi',
        if (failedCount > 0) '$failedCount başarısız',
      ];
      _status = '${_profiles.length} bilgisayardan: ${parts.join(', ')}.';
      _statusIsError = sentCount == 0 && queuedCount == 0;
    });
  }

  Future<void> _refreshQueuedCount() async {
    final all = await _queueService.load();
    if (!mounted) return;
    setState(() {
      _queuedCount =
          all.where((c) => c.profileId == _activeProfileId).length;
    });
  }

  Future<void> _flushQueueNow() async {
    final profile = _activeProfile;
    if (profile == null || _busy) return;
    setState(() => _busy = true);
    try {
      final sent = await _queueService.flushFor(
        profile: profile,
        sendOpenUrl: _service.openUrl,
        onFingerprintUpdate: _updateActiveFingerprint,
      );
      await _refreshQueuedCount();
      if (!mounted) return;
      setState(() {
        _status = sent > 0
            ? '$sent kuyruklu komut gönderildi.'
            : 'Hala bağlanılamıyor - komutlar kuyrukta bekliyor.';
        _statusIsError = sent == 0;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshMacros() async {
    final macros = await _macroService.load();
    if (!mounted) return;
    setState(() => _macros = macros);
  }

  String _macroStepLabel(MacroStep step) {
    if (step.type == 'open_url') return 'Bağlantı Aç: ${step.value}';
    return _macroStepChoices['${step.type}:${step.value}'] ?? step.value;
  }

  /// [macro]'nun adimlarini aktif profilde sirayla calistirir ve sonucu
  /// (kac adim tamamlandi/kuyruklandi/basarisiz oldu) tek bir ozet olarak
  /// gosterir - calistirma mantiginin kendisi MacroService.run() icinde.
  Future<void> _runMacro(CommandMacro macro) async {
    final profile = _activeProfile;
    if (_busy || profile == null) return;
    setState(() {
      _busy = true;
      _status = null;
    });
    final result = await _macroService.run(
      macro: macro,
      profile: profile,
      sendOpenUrl: _service.openUrl,
      sendMedia: _service.sendMedia,
      sendPower: _service.sendPower,
      onFingerprintUpdate: (fingerprint) =>
          _updateFingerprintFor(profile.id, fingerprint),
      enqueueOpenUrl: _queueService.enqueue,
    );
    await _refreshQueuedCount();
    if (!mounted) return;
    setState(() {
      _busy = false;
      final parts = <String>[
        if (result.succeeded > 0) '${result.succeeded} tamamlandı',
        if (result.queued > 0) '${result.queued} kuyruğa eklendi',
        if (result.failed > 0) '${result.failed} başarısız',
      ];
      _status = '"${macro.name}" makrosu: ${parts.join(', ')}.';
      _statusIsError = result.succeeded == 0 && result.queued == 0;
    });
  }

  Future<void> _showCreateMacroDialog() async {
    final colors = context.colors;
    final nameController = TextEditingController();
    final urlController = TextEditingController();
    final steps = <MacroStep>[];
    String? error;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Yeni Makro'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Makro adı (örn. Çalışma Modu)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: urlController,
                          decoration: const InputDecoration(
                            labelText: 'Açılacak bağlantı (opsiyonel)',
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        tooltip: 'Bağlantı adımı ekle',
                        onPressed: () {
                          final url = urlController.text.trim();
                          if (url.isEmpty) return;
                          setDialogState(() {
                            steps.add(MacroStep(type: 'open_url', value: url));
                            urlController.clear();
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _macroStepChoices.entries.map((entry) {
                      final parts = entry.key.split(':');
                      return ActionChip(
                        label: Text(entry.value),
                        onPressed: () => setDialogState(() {
                          steps.add(MacroStep(type: parts[0], value: parts[1]));
                        }),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  if (steps.isEmpty)
                    Text(
                      'Henüz adım eklenmedi.',
                      style: TextStyle(color: colors.textMuted, fontSize: 12),
                    )
                  else
                    ...List.generate(
                      steps.length,
                      (i) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text('${i + 1}. ${_macroStepLabel(steps[i])}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () =>
                              setDialogState(() => steps.removeAt(i)),
                        ),
                      ),
                    ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      error!,
                      style: TextStyle(color: colors.error, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () {
                if (nameController.text.trim().isEmpty) {
                  setDialogState(() => error = 'Bir isim yaz.');
                  return;
                }
                if (steps.isEmpty) {
                  setDialogState(() => error = 'En az bir adım ekle.');
                  return;
                }
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );

    if (saved != true) return;
    await _macroService.add(
      CommandMacro(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: nameController.text.trim(),
        steps: steps,
      ),
    );
    await _refreshMacros();
  }

  Future<void> _deleteMacro(CommandMacro macro) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Makroyu Sil'),
        content: Text('"${macro.name}" makrosu silinsin mi?'),
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
    await _macroService.delete(macro.id);
    await _refreshMacros();
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
      await _commandHistory.add(
        action: 'Medya',
        detail: action,
        profileName: _activeProfile?.name ?? '',
      );
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
      await _commandHistory.add(
        action: 'Güç',
        detail: label,
        profileName: _activeProfile?.name ?? '',
      );
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
      await _commandHistory.add(
        action: 'Ekran Görüntüsü',
        detail: '',
        profileName: _activeProfile?.name ?? '',
      );
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

  Future<void> _openLiveControl() async {
    final profile = _activeProfile;
    if (_busy || profile == null) return;
    _saveConnectionInfo();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LiveControlScreen(
          profile: profile,
          onFingerprintUpdated: _updateActiveFingerprint,
        ),
      ),
    );
  }

  Future<void> _openVoiceAgent() async {
    final profile = _activeProfile;
    if (_busy || profile == null) return;
    _saveConnectionInfo();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VoiceAgentScreen(
          profile: profile,
          settings: widget.settings,
          onFingerprintUpdated: _updateActiveFingerprint,
        ),
      ),
    );
  }

  Future<void> _openAutomationRules() async {
    final profile = _activeProfile;
    if (_busy || profile == null) return;
    _saveConnectionInfo();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AutomationRulesScreen(
          remoteService: _service,
          profile: profile,
          onFingerprintUpdated: _updateActiveFingerprint,
        ),
      ),
    );
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
      await _commandHistory.add(
        action: 'Pano Gönder',
        detail: text.length > 40 ? '${text.substring(0, 40)}…' : text,
        profileName: _activeProfile?.name ?? '',
      );
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
                    IconButton(
                      icon: Icon(Icons.qr_code_scanner, color: colors.accent),
                      tooltip: 'QR ile Ekle',
                      onPressed: _addProfileFromQr,
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
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 4),
                    child: Text(
                      'Aynı Wi-Fi ağında değilseniz: bilgisayara ve telefona '
                      'Tailscale kurup buraya bilgisayarın Tailscale IP\'sini '
                      '(100.x.x.x) girin.',
                      style: TextStyle(color: colors.textMuted, fontSize: 11),
                    ),
                  ),
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
                  if (_profiles.length > 1) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _sendToAllProfiles,
                      icon: const Icon(Icons.groups_outlined, size: 18),
                      label: Text('Tüm Bilgisayarlara Gönder (${_profiles.length})'),
                    ),
                  ],
                  if (_queuedCount > 0) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.schedule, size: 16, color: colors.textMuted),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Kuyrukta $_queuedCount bağlantı bekliyor',
                            style: TextStyle(color: colors.textMuted, fontSize: 12),
                          ),
                        ),
                        TextButton(
                          onPressed: _busy ? null : _flushQueueNow,
                          child: const Text('Şimdi Dene'),
                        ),
                      ],
                    ),
                  ],
                  Divider(color: colors.divider, height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Makrolar',
                        style: TextStyle(color: colors.textMuted, fontSize: 12),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.add_circle_outline,
                          size: 20,
                          color: colors.textPrimary,
                        ),
                        tooltip: 'Yeni makro',
                        onPressed: _showCreateMacroDialog,
                      ),
                    ],
                  ),
                  if (_macros.isEmpty)
                    Text(
                      'Birden fazla komutu tek dokunuşla çalıştırmak için bir '
                      'makro oluşturun (örn. bir bağlantı açıp sesi kısan).',
                      style: TextStyle(color: colors.textMuted, fontSize: 12),
                    )
                  else
                    ..._macros.map(
                      (macro) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _busy || _activeProfile == null
                                    ? null
                                    : () => _runMacro(macro),
                                icon: const Icon(Icons.play_arrow, size: 18),
                                label: Text(
                                  '${macro.name} (${macro.steps.length})',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.delete_outline,
                                size: 20,
                                color: colors.textMuted,
                              ),
                              tooltip: 'Makroyu sil',
                              onPressed:
                                  _busy ? null : () => _deleteMacro(macro),
                            ),
                          ],
                        ),
                      ),
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
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed:
                        _busy || _activeProfile == null ? null : _openLiveControl,
                    icon: const Icon(Icons.videocam_outlined),
                    label: const Text('Canlı Kontrol'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed:
                        _busy || _activeProfile == null ? null : _openVoiceAgent,
                    icon: const Icon(Icons.mic_outlined),
                    label: const Text('Sesli Ajan'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed:
                        _busy || _activeProfile == null ? null : _openAutomationRules,
                    icon: const Icon(Icons.rule),
                    label: const Text('Otomasyon Kuralları'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const CommandHistoryScreen(),
                      ),
                    ),
                    icon: const Icon(Icons.history),
                    label: const Text('Uzaktan Komut Geçmişi'),
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
