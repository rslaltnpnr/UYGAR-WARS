/// Uygulamanin cihazdaki mevcut verilerinden (sohbet gecmisi, bildirimler,
/// makrolar, eslesik bilgisayarlar, kuyruklu komutlar) hesaplanan bir
/// anlik goruntu - "Kullanım İstatistikleri" panelinde gosterilir. Kendisi
/// hicbir sey saklamaz, UsageStatsService.compute() ile her acilista
/// yeniden hesaplanir.
class UsageStats {
  final int totalQuestions;
  final int questionsToday;
  final int questionsThisWeek;
  final int errorCount;
  final int favoriteCount;
  final int notificationCount;
  final int macroCount;
  final int pairedComputerCount;
  final int queuedCommandCount;
  final DateTime? firstQuestionAt;

  const UsageStats({
    required this.totalQuestions,
    required this.questionsToday,
    required this.questionsThisWeek,
    required this.errorCount,
    required this.favoriteCount,
    required this.notificationCount,
    required this.macroCount,
    required this.pairedComputerCount,
    required this.queuedCommandCount,
    required this.firstQuestionAt,
  });
}
