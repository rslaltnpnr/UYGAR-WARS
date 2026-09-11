import 'package:flutter/material.dart';

import '../services/reminder_service.dart';

/// "N dakika sonra hatırlat" seklinde tekil bir hatirlatici kurmak icin
/// basit bir dialog.
class ReminderDialog extends StatefulWidget {
  const ReminderDialog({super.key});

  @override
  State<ReminderDialog> createState() => _ReminderDialogState();
}

class _ReminderDialogState extends State<ReminderDialog> {
  final _minutesController = TextEditingController(text: '5');
  final _messageController = TextEditingController();
  final _service = ReminderService();

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _minutesController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _schedule() async {
    final minutes = int.tryParse(_minutesController.text.trim());
    if (minutes == null || minutes <= 0) {
      setState(() => _error = 'Geçerli bir dakika sayısı girin.');
      return;
    }
    final message = _messageController.text.trim().isEmpty
        ? 'Hatırlatma zamanı!'
        : _messageController.text.trim();

    setState(() {
      _busy = true;
      _error = null;
    });

    final granted = await _service.requestPermission();
    if (!granted) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Bildirim izni verilmedi - hatırlatıcı kurulamıyor.';
      });
      return;
    }

    await _service.scheduleReminder(
      delay: Duration(minutes: minutes),
      message: message,
    );

    if (!mounted) return;
    Navigator.of(context).pop(minutes);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E28),
      title: const Text('Hatırlatıcı Kur', style: TextStyle(color: Colors.white)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _minutesController,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Kaç dakika sonra?',
              labelStyle: TextStyle(color: Colors.white54),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _messageController,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Hatırlatma mesajı (opsiyonel)',
              labelStyle: TextStyle(color: Colors.white54),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: Color(0xFFFF8080), fontSize: 12)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('İptal'),
        ),
        ElevatedButton(
          onPressed: _busy ? null : _schedule,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Kur'),
        ),
      ],
    );
  }
}
