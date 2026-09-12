import 'package:flutter/material.dart';

import '../models/notification_entry.dart';
import '../services/notification_history_service.dart';
import '../theme/app_colors.dart';

/// Uygulamanin simdiye kadar gosterdigi bildirimlerin (masaustu
/// uyarilari, kurulan hatirlaticilar) salt-okunur bir listesi -
/// masaustundeki "Bildirim Gecmisi" penceresinin mobil karsiligi.
class NotificationHistorySheet extends StatefulWidget {
  const NotificationHistorySheet({super.key});

  @override
  State<NotificationHistorySheet> createState() =>
      _NotificationHistorySheetState();
}

class _NotificationHistorySheetState extends State<NotificationHistorySheet> {
  final _service = NotificationHistoryService();
  List<NotificationEntry>? _entries;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await _service.load();
    if (!mounted) return;
    setState(() {
      // en yeni en ustte
      _entries = entries.reversed.toList();
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
    final colors = context.colors;
    final entries = _entries;
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: colors.panelTranslucent,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '\u{1F514} Bildirim Geçmişi',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.delete_outline,
                      color: colors.textSecondary,
                    ),
                    tooltip: 'Geçmişi Temizle',
                    onPressed: (entries == null || entries.isEmpty)
                        ? null
                        : _clear,
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: colors.textSecondary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              Divider(color: colors.divider, height: 1),
              Expanded(
                child: entries == null
                    ? const Center(child: CircularProgressIndicator())
                    : entries.isEmpty
                        ? Center(
                            child: Text(
                              'Henüz bir bildirim yok.',
                              style: TextStyle(color: colors.textMuted),
                            ),
                          )
                        : ListView.builder(
                            controller: scrollController,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemCount: entries.length,
                            itemBuilder: (context, index) {
                              final entry = entries[index];
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${_formatTime(entry.time)} · ${entry.title}',
                                      style: TextStyle(
                                        color: colors.textMuted,
                                        fontSize: 11,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      entry.message,
                                      style: TextStyle(
                                        color: colors.textPrimary,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        );
      },
    );
  }
}
