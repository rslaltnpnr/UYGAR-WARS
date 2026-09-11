import 'package:flutter/material.dart';

import '../services/settings_service.dart';
import '../theme/app_colors.dart';

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
  bool _obscureKey = true;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.settings.characterName,
    );
    _apiKeyController = TextEditingController(text: widget.settings.apiKey);
    _themeMode = widget.settings.themeMode;
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
    widget.onThemeModeChanged(_themeMode);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AlertDialog(
      backgroundColor: colors.panel,
      title: Text('Ayarlar', style: TextStyle(color: colors.textPrimary)),
      content: Column(
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
            child: Text('Tema', style: TextStyle(color: colors.textSecondary, fontSize: 12)),
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
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Iptal'),
        ),
        ElevatedButton(onPressed: _save, child: const Text('Kaydet')),
      ],
    );
  }
}
