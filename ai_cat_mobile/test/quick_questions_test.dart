import 'package:ai_cat_mobile/services/quick_questions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('defaultQuickQuestions', () {
    test('bos degil', () {
      expect(defaultQuickQuestions, isNotEmpty);
    });

    test('tum ogeler bos olmayan metin', () {
      for (final question in defaultQuickQuestions) {
        expect(question.trim(), isNotEmpty);
      }
    });

    test('tekrar eden soru yok', () {
      expect(defaultQuickQuestions.toSet().length, defaultQuickQuestions.length);
    });
  });
}
