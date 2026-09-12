import 'package:flutter_test/flutter_test.dart';

import 'package:ai_cat_mobile/models/chat_entry.dart';
import 'package:ai_cat_mobile/models/command_macro.dart';
import 'package:ai_cat_mobile/models/notification_entry.dart';
import 'package:ai_cat_mobile/models/queued_command.dart';
import 'package:ai_cat_mobile/models/remote_profile.dart';
import 'package:ai_cat_mobile/services/usage_stats_service.dart';

void main() {
  final now = DateTime(2026, 1, 10, 12, 0);

  group('UsageStatsService.compute', () {
    test('bos verilerle tum sayaclar sifir doner', () {
      final stats = UsageStatsService().compute(
        history: const [],
        notifications: const [],
        macros: const [],
        queuedCommands: const [],
        profiles: const [],
        now: now,
      );
      expect(stats.totalQuestions, 0);
      expect(stats.questionsToday, 0);
      expect(stats.questionsThisWeek, 0);
      expect(stats.errorCount, 0);
      expect(stats.favoriteCount, 0);
      expect(stats.notificationCount, 0);
      expect(stats.macroCount, 0);
      expect(stats.pairedComputerCount, 0);
      expect(stats.queuedCommandCount, 0);
      expect(stats.firstQuestionAt, isNull);
    });

    test('toplam soru sayisi tum gecmisi sayar (hatalilar dahil)', () {
      final history = [
        ChatEntry(time: now, question: 'q1', answer: 'a1', isError: false),
        ChatEntry(time: now, question: 'q2', answer: 'hata', isError: true),
      ];
      final stats = UsageStatsService().compute(
        history: history,
        notifications: const [],
        macros: const [],
        queuedCommands: const [],
        profiles: const [],
        now: now,
      );
      expect(stats.totalQuestions, 2);
      expect(stats.errorCount, 1);
    });

    test('bugun ve bu hafta sayaclari dogru tarih araligina gore ayrilir',
        () {
      final history = [
        ChatEntry(time: now, question: 'bugun', answer: 'a', isError: false),
        ChatEntry(
          time: now.subtract(const Duration(days: 3)),
          question: 'bu-hafta-ici',
          answer: 'a',
          isError: false,
        ),
        ChatEntry(
          time: now.subtract(const Duration(days: 30)),
          question: 'cok-eski',
          answer: 'a',
          isError: false,
        ),
      ];
      final stats = UsageStatsService().compute(
        history: history,
        notifications: const [],
        macros: const [],
        queuedCommands: const [],
        profiles: const [],
        now: now,
      );
      expect(stats.questionsToday, 1);
      expect(stats.questionsThisWeek, 2); // bugun + 3 gun once
      expect(stats.totalQuestions, 3);
    });

    test('favori sayisi dogru sayilir', () {
      final history = [
        ChatEntry(
          time: now,
          question: 'q1',
          answer: 'a1',
          isError: false,
          isFavorite: true,
        ),
        ChatEntry(time: now, question: 'q2', answer: 'a2', isError: false),
      ];
      final stats = UsageStatsService().compute(
        history: history,
        notifications: const [],
        macros: const [],
        queuedCommands: const [],
        profiles: const [],
        now: now,
      );
      expect(stats.favoriteCount, 1);
    });

    test('en eski kayit firstQuestionAt olarak donduruluyor', () {
      final oldest = now.subtract(const Duration(days: 100));
      final history = [
        ChatEntry(time: now, question: 'yeni', answer: 'a', isError: false),
        ChatEntry(time: oldest, question: 'eski', answer: 'a', isError: false),
        ChatEntry(
          time: now.subtract(const Duration(days: 5)),
          question: 'orta',
          answer: 'a',
          isError: false,
        ),
      ];
      final stats = UsageStatsService().compute(
        history: history,
        notifications: const [],
        macros: const [],
        queuedCommands: const [],
        profiles: const [],
        now: now,
      );
      expect(stats.firstQuestionAt, oldest);
    });

    test('diger listelerin uzunluklari dogrudan sayilir', () {
      final stats = UsageStatsService().compute(
        history: const [],
        notifications: [
          NotificationEntry(time: now, title: 't1', message: 'm1'),
          NotificationEntry(time: now, title: 't2', message: 'm2'),
        ],
        macros: const [
          CommandMacro(id: 'm1', name: 'M1', steps: []),
        ],
        queuedCommands: [
          QueuedCommand(profileId: 'p1', url: 'https://a.com', queuedAt: now),
        ],
        profiles: const [
          RemoteProfile(
            id: '1',
            name: 'Ev',
            ip: '10.0.0.5',
            port: 8765,
            pin: '111111',
            certFingerprint: '',
          ),
          RemoteProfile(
            id: '2',
            name: 'İş',
            ip: '10.0.0.6',
            port: 8765,
            pin: '222222',
            certFingerprint: '',
          ),
        ],
        now: now,
      );
      expect(stats.notificationCount, 2);
      expect(stats.macroCount, 1);
      expect(stats.queuedCommandCount, 1);
      expect(stats.pairedComputerCount, 2);
    });
  });
}
