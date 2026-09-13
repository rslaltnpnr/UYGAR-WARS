import 'package:flutter/material.dart';

import '../models/command_history_entry.dart';
import '../services/command_history_service.dart';

/// Telefondan bilgisayara gonderilen uzaktan komutlarin (bkz.
/// CommandHistoryService) kalici gecmisini gosterir - "Bilgisayarda Ac",
/// medya kontrolu, guc eylemi, ekran goruntusu istegi ve pano gonderimi
/// dahil. Salt-okunur bir denetim izidir; komutlari yeniden calistirmaz.
class CommandHistoryScreen extends StatefulWidget {
  const CommandHistoryScreen({super.key});

  @override
  State<CommandHistoryScreen> createState() => _CommandHistoryScreenState();
}

class _CommandHistoryScreenState extends State<CommandHistoryScreen> {
  final _service = CommandHistoryService();
  List<CommandHistoryEntry> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await _service.load();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  Future<void> _clear() async {
    await _service.clear();
    if (!mounted) return;
    setState(() => _entries = []);
  }

  String _formatTime(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Uzaktan Komut Geçmişi'),
        actions: [
          if (_entries.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Geçmişi Temizle',
              onPressed: _clear,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
              ? const Center(child: Text('Henüz gönderilmiş bir komut yok.'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _entries.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    // en yeni en ustte
                    final entry = _entries[_entries.length - 1 - index];
                    final subtitleParts = [
                      _formatTime(entry.time),
                      if (entry.profileName.isNotEmpty) entry.profileName,
                      if (entry.detail.isNotEmpty) entry.detail,
                    ];
                    return ListTile(
                      title: Text(entry.action),
                      subtitle: Text(subtitleParts.join(' · ')),
                    );
                  },
                ),
    );
  }
}
