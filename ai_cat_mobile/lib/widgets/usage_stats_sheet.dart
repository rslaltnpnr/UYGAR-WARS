import 'package:flutter/material.dart';

import '../models/usage_stats.dart';
import '../services/command_queue_service.dart';
import '../services/history_service.dart';
import '../services/macro_service.dart';
import '../services/notification_history_service.dart';
import '../services/settings_service.dart';
import '../services/usage_stats_service.dart';
import '../theme/app_colors.dart';

/// Uygulamanin cihazdaki mevcut verilerinden (sohbet gecmisi, bildirimler,
/// makrolar, eslesik bilgisayarlar, kuyruklu komutlar) salt-okunur bir
/// "Kullanım İstatistikleri" ozeti gosterir - butun veri zaten baska
/// servislerde tutuldugu icin kendi basina hicbir sey saklamaz, her
/// acilista UsageStatsService.compute() ile yeniden hesaplar.
class UsageStatsSheet extends StatefulWidget {
  final SettingsService settings;
  final HistoryService history;

  const UsageStatsSheet({
    super.key,
    required this.settings,
    required this.history,
  });

  @override
  State<UsageStatsSheet> createState() => _UsageStatsSheetState();
}

class _UsageStatsSheetState extends State<UsageStatsSheet> {
  final _notificationService = NotificationHistoryService();
  final _macroService = MacroService();
  final _queueService = CommandQueueService();

  UsageStats? _stats;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final notifications = await _notificationService.load();
    final macros = await _macroService.load();
    final queuedCommands = await _queueService.load();
    if (!mounted) return;
    final stats = UsageStatsService().compute(
      history: widget.history.load(),
      notifications: notifications,
      macros: macros,
      queuedCommands: queuedCommands,
      profiles: widget.settings.remoteProfiles,
      now: DateTime.now(),
    );
    setState(() => _stats = stats);
  }

  String _formatDate(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
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
                      '📊 Kullanım İstatistikleri',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: colors.textSecondary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              Divider(color: colors.divider, height: 1),
              Expanded(child: _buildBody(colors, scrollController)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBody(AppColors colors, ScrollController scrollController) {
    final stats = _stats;
    if (stats == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final rows = <(String, String, String)>[
      ('💬', 'Toplam soru', '${stats.totalQuestions}'),
      ('📅', 'Bugün sorulan', '${stats.questionsToday}'),
      ('🗓️', 'Bu hafta sorulan', '${stats.questionsThisWeek}'),
      ('⭐', 'Favori kayıt', '${stats.favoriteCount}'),
      ('⚠️', 'Hatalı yanıt', '${stats.errorCount}'),
      ('🔔', 'Bildirim', '${stats.notificationCount}'),
      ('🖥️', 'Eşleşik bilgisayar', '${stats.pairedComputerCount}'),
      ('⚡', 'Makro', '${stats.macroCount}'),
      ('⏳', 'Kuyrukta bekleyen komut', '${stats.queuedCommandCount}'),
      if (stats.firstQuestionAt != null)
        ('🎉', 'İlk soru', _formatDate(stats.firstQuestionAt!)),
    ];
    return ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: rows.length,
      separatorBuilder: (_, __) => Divider(color: colors.divider, height: 1),
      itemBuilder: (context, index) {
        final (emoji, label, value) = rows[index];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(color: colors.textPrimary, fontSize: 14),
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  color: colors.textMuted,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
