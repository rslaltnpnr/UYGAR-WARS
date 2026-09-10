import 'package:flutter/material.dart';

import '../services/settings_service.dart';

/// Kediyi uzun basinca acilan ayarlar penceresi (masaustu surumundeki
/// sag tik menusunun "Kediye Isim Ver" + "Gemini API Key Ayarlari"
/// karsiligi).
class SettingsDialog extends StatefulWidget {
  final SettingsService settings;

  const SettingsDialog({super.key, required this.settings});

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _apiKeyController;
  bool _obscureKey = true;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.settings.characterName,
    );
    _apiKeyController = TextEditingController(text: widget.settings.apiKey);
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
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E28),
      title: const Text('Ayarlar', style: TextStyle(color: Colors.white)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Kedi ismi',
              labelStyle: TextStyle(color: Colors.white70),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _apiKeyController,
            obscureText: _obscureKey,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Gemini API Key',
              labelStyle: const TextStyle(color: Colors.white70),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureKey ? Icons.visibility : Icons.visibility_off,
                  color: Colors.white70,
                ),
                onPressed: () => setState(() => _obscureKey = !_obscureKey),
              ),
            ),
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
