import 'package:flutter_test/flutter_test.dart';

import 'package:ai_cat_mobile/services/update_service.dart';

void main() {
  group('isNewerVersion', () {
    test('daha yuksek patch surumu daha yeni sayilir', () {
      expect(isNewerVersion('v1.1.1', '1.1.0'), isTrue);
    });

    test('daha yuksek minor surumu daha yeni sayilir', () {
      expect(isNewerVersion('v1.2.0', '1.1.9'), isTrue);
    });

    test('ayni surum daha yeni sayilmaz', () {
      expect(isNewerVersion('v1.1.1', '1.1.1'), isFalse);
    });

    test('daha eski surum daha yeni sayilmaz', () {
      expect(isNewerVersion('v1.0.0', '1.1.0'), isFalse);
    });

    test('cift haneli parcalar dogru karsilastirilir (sozluksel degil)', () {
      expect(isNewerVersion('v1.10.0', '1.9.0'), isTrue);
    });

    test('eksik parcalar 0 olarak varsayilir', () {
      expect(isNewerVersion('v1.2', '1.1.9'), isTrue);
      expect(isNewerVersion('v1.1', '1.1.0'), isFalse);
    });

    test('bas harfi v olmayan surumler de calisir', () {
      expect(isNewerVersion('1.2.0', '1.1.0'), isTrue);
    });
  });
}
