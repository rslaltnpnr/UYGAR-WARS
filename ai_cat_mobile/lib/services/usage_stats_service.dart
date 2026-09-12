import '../models/chat_entry.dart';
import '../models/command_macro.dart';
import '../models/notification_entry.dart';
import '../models/queued_command.dart';
import '../models/remote_profile.dart';
import '../models/usage_stats.dart';

/// Zaten baska servislerin (HistoryService, NotificationHistoryService,
/// MacroService, CommandQueueService, SettingsService) yukledigi verileri
/// tek bir UsageStats anlik goruntusune donusturur - kendi baslarina G/C
/// yapmaz, bu yuzden gercek SharedPreferences'a dokunmadan saf birim
/// testleriyle sinanabilir.
class UsageStatsService {
  UsageStats compute({
    required List<ChatEntry> history,
    required List<NotificationEntry> notifications,
    required List<CommandMacro> macros,
    required List<QueuedCommand> queuedCommands,
    required List<RemoteProfile> profiles,
    required DateTime now,
  }) {
    final weekAgo = now.subtract(const Duration(days: 7));
    var questionsToday = 0;
    var questionsThisWeek = 0;
    var errorCount = 0;
    var favoriteCount = 0;
    DateTime? firstQuestionAt;

    for (final entry in history) {
      if (_isSameDay(entry.time, now)) questionsToday++;
      if (entry.time.isAfter(weekAgo)) questionsThisWeek++;
      if (entry.isError) errorCount++;
      if (entry.isFavorite) favoriteCount++;
      if (firstQuestionAt == null || entry.time.isBefore(firstQuestionAt)) {
        firstQuestionAt = entry.time;
      }
    }

    return UsageStats(
      totalQuestions: history.length,
      questionsToday: questionsToday,
      questionsThisWeek: questionsThisWeek,
      errorCount: errorCount,
      favoriteCount: favoriteCount,
      notificationCount: notifications.length,
      macroCount: macros.length,
      pairedComputerCount: profiles.length,
      queuedCommandCount: queuedCommands.length,
      firstQuestionAt: firstQuestionAt,
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
