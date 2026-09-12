import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_cat_mobile/models/chat_entry.dart';
import 'package:ai_cat_mobile/services/history_service.dart';

void main() {
  group('ChatEntry favori', () {
    test('varsayilan olarak favori degil', () {
      final entry = ChatEntry(
        time: DateTime(2026, 1, 1),
        question: 'q',
        answer: 'a',
        isError: false,
      );
      expect(entry.isFavorite, isFalse);
    });

    test('copyWith sadece isFavorite alanini degistirir', () {
      final entry = ChatEntry(
        time: DateTime(2026, 1, 1),
        question: 'q',
        answer: 'a',
        isError: false,
      );
      final favorited = entry.copyWith(isFavorite: true);
      expect(favorited.isFavorite, isTrue);
      expect(favorited.question, entry.question);
      expect(favorited.answer, entry.answer);
      expect(favorited.time, entry.time);
    });

    test('toJson/fromJson round-trip favori durumunu korur', () {
      final entry = ChatEntry(
        time: DateTime(2026, 1, 1),
        question: 'q',
        answer: 'a',
        isError: false,
        isFavorite: true,
      );
      final restored = ChatEntry.fromJson(entry.toJson());
      expect(restored.isFavorite, isTrue);
    });

    test('eski (is_favorite alani olmayan) kayitlar favori olmayan sayilir', () {
      final restored = ChatEntry.fromJson({
        'time': '2026-01-01T00:00:00.000',
        'question': 'q',
        'answer': 'a',
        'is_error': false,
      });
      expect(restored.isFavorite, isFalse);
    });
  });

  group('HistoryService.saveAll', () {
    test('mevcut listeyi tamamen degistirir, add() gibi eklemez', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = HistoryService(prefs);

      service.add(
        ChatEntry(
          time: DateTime(2026, 1, 1),
          question: 'q1',
          answer: 'a1',
          isError: false,
        ),
      );
      final loaded = service.load();
      final favorited = [loaded[0].copyWith(isFavorite: true)];
      service.saveAll(favorited);

      final reloaded = service.load();
      expect(reloaded.length, 1);
      expect(reloaded[0].isFavorite, isTrue);
    });

    test('maxEntries sinirini asarsa en eskileri atar', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = HistoryService(prefs);

      final many = List.generate(
        HistoryService.maxEntries + 5,
        (i) => ChatEntry(
          time: DateTime(2026, 1, 1).add(Duration(minutes: i)),
          question: 'q$i',
          answer: 'a$i',
          isError: false,
        ),
      );
      service.saveAll(many);

      final reloaded = service.load();
      expect(reloaded.length, HistoryService.maxEntries);
      expect(reloaded.first.question, 'q5');
    });
  });
}
