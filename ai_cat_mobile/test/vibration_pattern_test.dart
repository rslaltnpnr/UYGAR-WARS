import 'package:ai_cat_mobile/services/vibration_pattern.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VibrationPatternOption', () {
    test('fromValue bilinen degerleri geri cozer', () {
      expect(VibrationPatternOption.fromValue('short'), VibrationPatternOption.short);
      expect(VibrationPatternOption.fromValue('long'), VibrationPatternOption.long);
      expect(
        VibrationPatternOption.fromValue('double'),
        VibrationPatternOption.doublePulse,
      );
      expect(VibrationPatternOption.fromValue('off'), VibrationPatternOption.off);
    });

    test('bilinmeyen ya da null deger system varsayilanina duser', () {
      expect(VibrationPatternOption.fromValue(null), VibrationPatternOption.system);
      expect(
        VibrationPatternOption.fromValue('gecersiz'),
        VibrationPatternOption.system,
      );
    });

    test('off disinda hepsinde titresim etkin', () {
      expect(VibrationPatternOption.system.enableVibration, isTrue);
      expect(VibrationPatternOption.short.enableVibration, isTrue);
      expect(VibrationPatternOption.long.enableVibration, isTrue);
      expect(VibrationPatternOption.doublePulse.enableVibration, isTrue);
      expect(VibrationPatternOption.off.enableVibration, isFalse);
    });

    test('ozel paternler farkli uzunluklarda', () {
      expect(VibrationPatternOption.system.pattern, isNull);
      expect(VibrationPatternOption.short.pattern, [0, 150]);
      expect(VibrationPatternOption.long.pattern, [0, 800]);
      expect(VibrationPatternOption.doublePulse.pattern, [0, 150, 100, 150]);
    });
  });
}
