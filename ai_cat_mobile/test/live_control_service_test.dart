import 'dart:typed_data';

import 'package:ai_cat_mobile/services/live_control_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _frame(List<int> payload) {
  final builder = BytesBuilder();
  final header = ByteData(4)..setUint32(0, payload.length);
  builder.add(header.buffer.asUint8List());
  builder.add(payload);
  return builder.toBytes();
}

void main() {
  group('liveControlPortFor', () {
    test('REST sunucu portundan bir fazlasini doner', () {
      expect(liveControlPortFor(8765), 8766);
    });
  });

  group('extractLiveFrames', () {
    test('tek bir tam kareyi ayiklar', () {
      final buffer = _frame([1, 2, 3]);
      final result = extractLiveFrames(buffer);
      expect(result.frames, [
        [1, 2, 3],
      ]);
      expect(result.remaining, isEmpty);
    });

    test('ayni arabellekte birden fazla kareyi ayiklar', () {
      final buffer = Uint8List.fromList([
        ..._frame([1, 2]),
        ..._frame([3, 4, 5]),
      ]);
      final result = extractLiveFrames(buffer);
      expect(result.frames.length, 2);
      expect(result.frames[0], [1, 2]);
      expect(result.frames[1], [3, 4, 5]);
      expect(result.remaining, isEmpty);
    });

    test('eksik/yarim kareyi remaining olarak birakir', () {
      final complete = _frame([1, 2, 3]);
      final partialNext = _frame([9, 9, 9]).sublist(0, 5); // uzunluk + 1 bayt
      final buffer = Uint8List.fromList([...complete, ...partialNext]);
      final result = extractLiveFrames(buffer);
      expect(result.frames, [
        [1, 2, 3],
      ]);
      expect(result.remaining, partialNext);
    });

    test('4 bayttan az veri (uzunluk basligi bile tamamlanmamis) hepsini birakir', () {
      final buffer = Uint8List.fromList([0, 0]);
      final result = extractLiveFrames(buffer);
      expect(result.frames, isEmpty);
      expect(result.remaining, buffer);
    });

    test('bos arabellek bos sonuc doner', () {
      final result = extractLiveFrames(Uint8List(0));
      expect(result.frames, isEmpty);
      expect(result.remaining, isEmpty);
    });
  });

  group('diffTypedText', () {
    test('sona ekleme sadece insert olarak doner', () {
      final diff = diffTypedText('mera', 'merab');
      expect(diff.backspaces, 0);
      expect(diff.insert, 'b');
    });

    test('sondan silme sadece backspaces olarak doner', () {
      final diff = diffTypedText('merhaba', 'merha');
      expect(diff.backspaces, 2);
      expect(diff.insert, '');
    });

    test('ortadaki degisiklik ortak onek/sonek disini fark eder', () {
      // Ortak onek "kedi k" (6 karakter) korunur, sadece farklilasan
      // "öpek" -> "uş" kismi degisir (en az backspace/yazma ile sonuc
      // ayni: "kedi kuş").
      final diff = diffTypedText('kedi köpek', 'kedi kuş');
      expect(diff.backspaces, 4); // "öpek" silinir
      expect(diff.insert, 'uş');
    });

    test('ayni metinde fark yoktur', () {
      final diff = diffTypedText('ayni', 'ayni');
      expect(diff.backspaces, 0);
      expect(diff.insert, '');
    });

    test('tamamen farkli metinde eski tamamen silinir yenisi yazilir', () {
      final diff = diffTypedText('abc', 'xyz');
      expect(diff.backspaces, 3);
      expect(diff.insert, 'xyz');
    });
  });

  group('specialLiveKeyName', () {
    test('bilinen ozel tuslar dogru adlarla eslenir', () {
      expect(specialLiveKeyName(LogicalKeyboardKey.enter), 'enter');
      expect(specialLiveKeyName(LogicalKeyboardKey.backspace), 'backspace');
      expect(specialLiveKeyName(LogicalKeyboardKey.arrowUp), 'up');
    });

    test('taninmayan bir tus icin null doner', () {
      expect(specialLiveKeyName(LogicalKeyboardKey.keyA), isNull);
    });
  });

  group('mapTouchToNormalized', () {
    test('goruntu widget ile ayni oranda tam ortasindaki nokta 0.5,0.5 verir', () {
      final result = mapTouchToNormalized(
        const Offset(500, 250),
        const Size(1000, 500),
        const Size(1000, 500),
      );
      expect(result, isNotNull);
      expect(result!.dx, closeTo(0.5, 0.0001));
      expect(result.dy, closeTo(0.5, 0.0001));
    });

    test('daha genis widget icinde yatay letterbox dogru hesaba katilir', () {
      // 16:9 goruntu, 4:1 genis bir widget icinde - yukseklige gore
      // olceklenir, yanlarda bosluk kalir.
      const widgetSize = Size(1600, 200);
      const imageSize = Size(1280, 720);
      // Goruntu 200/720 orani ile olceklenir -> genislik ~355.5,
      // yatay bosluk (1600-355.5)/2 ~622.25 - tam ortadaki nokta
      // goruntunun ortasina denk gelmeli.
      final center = Offset(widgetSize.width / 2, widgetSize.height / 2);
      final result = mapTouchToNormalized(center, widgetSize, imageSize);
      expect(result, isNotNull);
      expect(result!.dx, closeTo(0.5, 0.01));
      expect(result.dy, closeTo(0.5, 0.01));
    });

    test('letterbox bosluguna dokunma null doner', () {
      const widgetSize = Size(1600, 200);
      const imageSize = Size(1280, 720);
      final result = mapTouchToNormalized(const Offset(5, 100), widgetSize, imageSize);
      expect(result, isNull);
    });

    test('sifir boyutlu widget/goruntude null doner', () {
      expect(
        mapTouchToNormalized(Offset.zero, Size.zero, const Size(100, 100)),
        isNull,
      );
    });
  });
}
