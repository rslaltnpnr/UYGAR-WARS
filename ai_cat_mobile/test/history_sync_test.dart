import 'package:flutter_test/flutter_test.dart';

import 'package:ai_cat_mobile/services/history_sync.dart';

void main() {
  group('formatDesktopTime', () {
    test('sifir doldurur (tek haneli ay/gun/saat/dakika)', () {
      final time = DateTime(2026, 1, 2, 3, 4);
      expect(formatDesktopTime(time), '2026-01-02 03:04');
    });

    test('cift haneli degerlerde de dogru bicimlenir', () {
      final time = DateTime(2026, 11, 22, 13, 45);
      expect(formatDesktopTime(time), '2026-11-22 13:45');
    });

    test('saniye/milisaniye bilgisini yok sayar', () {
      final time = DateTime(2026, 1, 2, 3, 4, 59, 999);
      expect(formatDesktopTime(time), '2026-01-02 03:04');
    });

    test(
      'DUZ SENKRON ROUND-TRIP: bilgisayarin gonderdigi bicim ayristirilip '
      'tekrar formatlandiginda BAYT BAYT AYNI dizeyi verir - aksi halde '
      'bilgisayara geri gonderilen bir kayit kendi orijinaliyle '
      'eslesmez ve yinelenir',
      () {
        const desktopTimeString = '2026-03-07 09:05';
        final parsed = DateTime.parse(desktopTimeString);
        expect(formatDesktopTime(parsed), desktopTimeString);
      },
    );
  });

  group('historySyncKey', () {
    test('zaman, soru ve cevabi | ile birlestirir', () {
      final key = historySyncKey(
        time: DateTime(2026, 1, 2, 3, 4),
        question: 'soru',
        answer: 'cevap',
      );
      expect(key, '2026-01-02 03:04|soru|cevap');
    });

    test('ayni mantiksal kayit iki farkli kaynaktan gelse de ayni anahtari uretir', () {
      // Senaryo: bilgisayardan cekilen bir kayit (time string'i ayristirilip
      // DateTime'a cevrilir) ile telefonda hicbir zaman degismemis o
      // kaydin kendisi (round-trip sonrasi) ayni anahtari uretmeli.
      final fromDesktop = DateTime.tryParse('2026-05-05 20:00')!;
      final key1 = historySyncKey(
        time: fromDesktop,
        question: 'q',
        answer: 'a',
      );
      final key2 = historySyncKey(
        time: DateTime(2026, 5, 5, 20, 0),
        question: 'q',
        answer: 'a',
      );
      expect(key1, key2);
    });

    test('farkli soru ya da cevap farkli anahtar uretir', () {
      final time = DateTime(2026, 1, 1, 0, 0);
      final key1 = historySyncKey(time: time, question: 'q1', answer: 'a');
      final key2 = historySyncKey(time: time, question: 'q2', answer: 'a');
      expect(key1, isNot(key2));
    });
  });
}
