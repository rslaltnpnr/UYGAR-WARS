import 'package:ai_cat_mobile/services/auto_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseHhMm', () {
    test('gecerli saati normallestirir', () {
      expect(parseHhMm('9:5'), '09:05');
      expect(parseHhMm(' 18:30 '), '18:30');
    });

    test('gecersiz bicim null doner', () {
      expect(parseHhMm('1830'), isNull);
      expect(parseHhMm('ab:cd'), isNull);
      expect(parseHhMm('24:00'), isNull);
      expect(parseHhMm('12:60'), isNull);
    });
  });

  group('resolveAutoThemeMode', () {
    test('gunduz araliginda light doner', () {
      final now = DateTime(2024, 1, 1, 12, 0);
      expect(
        resolveAutoThemeMode(now, dayStart: '07:00', nightStart: '19:00'),
        ThemeMode.light,
      );
    });

    test('gece araliginda dark doner', () {
      final now = DateTime(2024, 1, 1, 22, 0);
      expect(
        resolveAutoThemeMode(now, dayStart: '07:00', nightStart: '19:00'),
        ThemeMode.dark,
      );
    });

    test('gecersiz saatler varsayilana duser', () {
      final now = DateTime(2024, 1, 1, 12, 0);
      expect(
        resolveAutoThemeMode(now, dayStart: 'x', nightStart: 'y'),
        ThemeMode.light,
      );
    });

    test('gunduz araligi gece yarisini geciyorsa', () {
      expect(
        resolveAutoThemeMode(
          DateTime(2024, 1, 1, 23, 0),
          dayStart: '20:00',
          nightStart: '06:00',
        ),
        ThemeMode.light,
      );
      expect(
        resolveAutoThemeMode(
          DateTime(2024, 1, 1, 10, 0),
          dayStart: '20:00',
          nightStart: '06:00',
        ),
        ThemeMode.dark,
      );
    });
  });
}
