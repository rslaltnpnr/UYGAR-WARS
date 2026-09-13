import 'package:flutter_test/flutter_test.dart';

import 'package:ai_cat_mobile/models/secure_note.dart';

void main() {
  group('parseTagsInput', () {
    test('virgulle ayrilmis etiketleri ayristirir', () {
      expect(parseTagsInput('iş, önemli'), ['iş', 'önemli']);
    });

    test('bosluklari kirpar ve bos girisleri atlar', () {
      expect(parseTagsInput('  iş ,, önemli  ,'), ['iş', 'önemli']);
    });

    test('tekrar eden etiketleri kaldirir', () {
      expect(parseTagsInput('iş, iş, önemli'), ['iş', 'önemli']);
    });

    test('bos girdi bos liste dondurur', () {
      expect(parseTagsInput(''), isEmpty);
      expect(parseTagsInput('   '), isEmpty);
    });
  });

  group('SecureNote json', () {
    test('tags alani json roundtrip yapar', () {
      final note = SecureNote(
        id: '1',
        title: 'Başlık',
        body: 'Gövde',
        updatedAt: DateTime(2026, 1, 1),
        tags: const ['iş', 'önemli'],
      );
      final restored = SecureNote.fromJson(note.toJson());
      expect(restored.tags, ['iş', 'önemli']);
    });

    test('tags alani olmayan eski kayitlar bos liste ile acilir', () {
      final restored = SecureNote.fromJson({
        'id': '1',
        'title': 'Başlık',
        'body': 'Gövde',
        'updated_at': DateTime(2026, 1, 1).toIso8601String(),
      });
      expect(restored.tags, isEmpty);
    });

    test('copyWith yalnizca verilen alanlari degistirir', () {
      final note = SecureNote(
        id: '1',
        title: 'Başlık',
        body: 'Gövde',
        updatedAt: DateTime(2026, 1, 1),
        tags: const ['iş'],
      );
      final updated = note.copyWith(tags: const ['ev']);
      expect(updated.title, 'Başlık');
      expect(updated.tags, ['ev']);
    });
  });
}
