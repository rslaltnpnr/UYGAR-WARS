import 'package:flutter_test/flutter_test.dart';

import 'package:ai_cat_mobile/services/pairing_uri.dart';

void main() {
  group('parsePairingUri', () {
    test('geçerli URI doğru ayrıştırılır', () {
      final info = parsePairingUri(
        'aikedi://pair?ip=192.168.1.5&port=8765&pin=123456&fp=AA%3ABB',
      );
      expect(info, isNotNull);
      expect(info!.ip, '192.168.1.5');
      expect(info.port, 8765);
      expect(info.pin, '123456');
      expect(info.certFingerprint, 'AA:BB');
    });

    test('fp eksikse boş dize ile kabul edilir', () {
      final info = parsePairingUri(
        'aikedi://pair?ip=10.0.0.1&port=8765&pin=111111',
      );
      expect(info, isNotNull);
      expect(info!.certFingerprint, '');
    });

    test('yanlış şema reddedilir', () {
      expect(
        parsePairingUri('https://pair?ip=10.0.0.1&port=8765&pin=111111'),
        isNull,
      );
    });

    test('yanlış host reddedilir', () {
      expect(
        parsePairingUri('aikedi://other?ip=10.0.0.1&port=8765&pin=111111'),
        isNull,
      );
    });

    test('ip eksikse reddedilir', () {
      expect(parsePairingUri('aikedi://pair?port=8765&pin=111111'), isNull);
    });

    test('port sayı değilse reddedilir', () {
      expect(
        parsePairingUri('aikedi://pair?ip=10.0.0.1&port=abc&pin=111111'),
        isNull,
      );
    });

    test('pin eksikse reddedilir', () {
      expect(parsePairingUri('aikedi://pair?ip=10.0.0.1&port=8765'), isNull);
    });

    test('bozuk URI reddedilir', () {
      expect(parsePairingUri('not a uri at all ::'), isNull);
    });
  });
}
