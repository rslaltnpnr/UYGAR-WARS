import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_cat_mobile/models/secure_note.dart';
import 'package:ai_cat_mobile/services/secure_notepad_service.dart';

/// PBKDF2 gercek anahtar turetmesi yapar - varsayilan 200k iterasyon test
/// suitini gereksiz yavaslatir, bu yuzden testler dusuk bir iterasyon
/// sayisiyla calisir (ayni kod yolunu sinar, sadece daha hizli).
SecureNotepadService _service() => SecureNotepadService(pbkdf2Iterations: 100);

void main() {
  group('SecureNotepadService', () {
    test('kurulmadan once isSetUp false doner', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await _service().isSetUp(), isFalse);
    });

    test('setUp sonrasi isSetUp true doner', () async {
      SharedPreferences.setMockInitialValues({});
      final service = _service();
      await service.setUp('dogru-sifre');
      expect(await service.isSetUp(), isTrue);
    });

    test('setUp sonrasi dogru sifreyle bos not listesi acilir', () async {
      SharedPreferences.setMockInitialValues({});
      final service = _service();
      await service.setUp('dogru-sifre');
      final result = await service.unlock('dogru-sifre');
      expect(result.notes, isEmpty);
    });

    test('yanlis sifreyle WrongPasswordException firlatilir', () async {
      SharedPreferences.setMockInitialValues({});
      final service = _service();
      await service.setUp('dogru-sifre');
      expect(
        () => service.unlock('yanlis-sifre'),
        throwsA(isA<WrongPasswordException>()),
      );
    });

    test('kurulmadan unlock cagirmak StateError firlatir', () async {
      SharedPreferences.setMockInitialValues({});
      expect(() => _service().unlock('herhangi'), throwsA(isA<StateError>()));
    });

    test('save edilen notlar dogru sifreyle geri yuklenir', () async {
      SharedPreferences.setMockInitialValues({});
      final service = _service();
      final key = await service.setUp('dogru-sifre');
      final notes = [
        SecureNote(
          id: '1',
          title: 'Banka PIN',
          body: 'gizli-bilgi',
          updatedAt: DateTime(2026, 1, 1),
        ),
      ];
      await service.save(key, notes);

      final result = await service.unlock('dogru-sifre');
      expect(result.notes.length, 1);
      expect(result.notes.first.title, 'Banka PIN');
      expect(result.notes.first.body, 'gizli-bilgi');
    });

    test('kaydedilen veri SharedPreferences icinde duz metin olarak '
        'gorunmez', () async {
      SharedPreferences.setMockInitialValues({});
      final service = _service();
      final key = await service.setUp('dogru-sifre');
      await service.save(key, [
        SecureNote(
          id: '1',
          title: 'gizli-baslik-xyz',
          body: 'gizli-govde-abc',
          updatedAt: DateTime(2026, 1, 1),
        ),
      ]);

      final prefs = await SharedPreferences.getInstance();
      final blob = prefs.getString('secure_notepad_blob') ?? '';
      expect(blob.contains('gizli-baslik-xyz'), isFalse);
      expect(blob.contains('gizli-govde-abc'), isFalse);
    });

    test('reset sonrasi isSetUp tekrar false doner ve yeniden kurulabilir',
        () async {
      SharedPreferences.setMockInitialValues({});
      final service = _service();
      await service.setUp('eski-sifre');
      await service.reset();
      expect(await service.isSetUp(), isFalse);

      await service.setUp('yeni-sifre');
      final result = await service.unlock('yeni-sifre');
      expect(result.notes, isEmpty);
    });

    test('ayni anahtarla iki ardisik save() farkli sifreli metin uretir '
        '(nonce tekrar etmiyor)', () async {
      SharedPreferences.setMockInitialValues({});
      final service = _service();
      final key = await service.setUp('dogru-sifre');
      final prefs = await SharedPreferences.getInstance();

      await service.save(key, const []);
      final first = prefs.getString('secure_notepad_blob');

      await service.save(key, const []);
      final second = prefs.getString('secure_notepad_blob');

      expect(first, isNot(equals(second)));
    });
  });
}
