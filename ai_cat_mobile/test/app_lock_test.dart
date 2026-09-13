import 'package:ai_cat_mobile/services/app_lock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isValidAppLockPin', () {
    test('4-6 haneli rakam gecerlidir', () {
      expect(isValidAppLockPin('1234'), isTrue);
      expect(isValidAppLockPin('123456'), isTrue);
      expect(isValidAppLockPin('12345'), isTrue);
    });

    test('3 haneli ya da daha kisa reddedilir', () {
      expect(isValidAppLockPin('123'), isFalse);
      expect(isValidAppLockPin(''), isFalse);
    });

    test('7 haneli ya da daha uzun reddedilir', () {
      expect(isValidAppLockPin('1234567'), isFalse);
    });

    test('rakam olmayan karakterler reddedilir', () {
      expect(isValidAppLockPin('12a4'), isFalse);
      expect(isValidAppLockPin('12 4'), isFalse);
    });
  });
}
