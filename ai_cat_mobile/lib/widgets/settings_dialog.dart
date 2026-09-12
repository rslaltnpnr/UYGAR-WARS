import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/backup_service.dart';
import '../services/settings_service.dart';
import '../services/update_service.dart';
import '../services/widget_service.dart';
import '../theme/app_colors.dart';
import 'about_dialog.dart';

/// Kediyi uzun basinca acilan ayarlar penceresi (masaustu surumundeki
/// sag tik menusunun "Kediye Isim Ver" + "Gemini API Key Ayarlari"
/// karsiligi).
class SettingsDialog extends StatefulWidget {
  final SettingsService settings;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  const SettingsDialog({
    super.key,
    required this.settings,
    required this.onThemeModeChanged,
  });

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _apiKeyController;
  late ThemeMode _themeMode;
  late bool _autoBackupEnabled;
  bool _obscureKey = true;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.settings.characterName,
    );
    _apiKeyController = TextEditingController(text: widget.settings.apiKey);
    _themeMode = widget.settings.themeMode;
    _autoBackupEnabled = widget.settings.autoBackupEnabled;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isNotEmpty) {
      widget.settings.characterName = name;
    }
    widget.settings.apiKey = _apiKeyController.text.trim();
    widget.settings.themeMode = _themeMode;
    widget.settings.autoBackupEnabled = _autoBackupEnabled;
    widget.onThemeModeChanged(_themeMode);
    Navigator.of(context).pop();
  }

  Future<void> _shareBackup() async {
    try {
      await BackupService().shareBackup();
    } catch (exc) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Yedek oluşturulamadı: $exc')),
      );
    }
  }

  Future<void> _checkForUpdate() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Güncellemeler kontrol ediliyor...')),
    );
    final info = await UpdateService().checkForUpdate();
    if (!mounted) return;
    if (info == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Güncel sürümü kullanıyorsunuz.')),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Yeni Sürüm Var'),
        content: Text('${info.tag} sürümü yayınlandı.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Kapat'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              launchUrl(
                Uri.parse(info.apkDownloadUrl ?? info.htmlUrl),
                mode: LaunchMode.externalApplication,
              );
            },
            child: const Text('İndir'),
          ),
        ],
      ),
    );
  }

  Future<void> _addHomeWidget() async {
    final messenger = ScaffoldMessenger.of(context);
    final requested = await WidgetService.requestPinWidget();
    if (!mounted) return;
    if (!requested) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Cihazınız/başlatıcınız widget eklemeyi desteklemiyor. Ana '
            'ekranda boş bir alana uzun basıp "Widget\'lar" menüsünden '
            'elle ekleyebilirsiniz.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AlertDialog(
      backgroundColor: colors.panel,
      title: Text('Ayarlar', style: TextStyle(color: colors.textPrimary)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              style: TextStyle(color: colors.textPrimary),
              decoration: InputDecoration(
                labelText: 'Kedi ismi',
                labelStyle: TextStyle(color: colors.textSecondary),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _apiKeyController,
              obscureText: _obscureKey,
              style: TextStyle(color: colors.textPrimary),
              decoration: InputDecoration(
                labelText: 'Gemini API Key',
                labelStyle: TextStyle(color: colors.textSecondary),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureKey ? Icons.visibility : Icons.visibility_off,
                    color: colors.textSecondary,
                  ),
                  onPressed: () => setState(() => _obscureKey = !_obscureKey),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Tema',
                  style: TextStyle(color: colors.textSecondary, fontSize: 12)),
            ),
            const SizedBox(height: 6),
            SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  label: Text('Sistem'),
                  icon: Icon(Icons.brightness_auto),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  label: Text('Açık'),
                  icon: Icon(Icons.light_mode),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  label: Text('Koyu'),
                  icon: Icon(Icons.dark_mode),
                ),
              ],
              selected: {_themeMode},
              onSelectionChanged: (selection) =>
                  setState(() => _themeMode = selection.first),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Yedekleme',
                style: TextStyle(color: colors.textSecondary, fontSize: 12),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _shareBackup,
                    icon: const Icon(Icons.upload_file, size: 18),
                    label: const Text('Yedek Al'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _checkForUpdate,
                    icon: const Icon(Icons.system_update, size: 18),
                    label: const Text('Güncelleme Kontrol'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Geri yüklemek için yedek dosyasını bir dosya yöneticisinden '
                'bu uygulamaya "Paylaş" ile gönderin.',
                style: TextStyle(color: colors.textMuted, fontSize: 11),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(
                'Otomatik Yedekleme (Günlük)',
                style: TextStyle(color: colors.textPrimary, fontSize: 13),
              ),
              subtitle: Text(
                'Uygulama açıldığında, günde en fazla bir kez sessizce '
                'cihaza kaydedilir (paylaşım gerekmez).',
                style: TextStyle(color: colors.textMuted, fontSize: 11),
              ),
              value: _autoBackupEnabled,
              onChanged: (value) => setState(() => _autoBackupEnabled = value),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Ana Ekran Widget\'ı',
                style: TextStyle(color: colors.textSecondary, fontSize: 12),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _addHomeWidget,
                icon: const Icon(Icons.widgets_outlined, size: 18),
                label: const Text('Ana Ekrana Widget Ekle'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => showDialog(
            context: context,
            builder: (_) => const AboutAppDialog(),
          ),
          child: const Text('Hakkında'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Iptal'),
        ),
        ElevatedButton(onPressed: _save, child: const Text('Kaydet')),
      ],
    );
  }
}
