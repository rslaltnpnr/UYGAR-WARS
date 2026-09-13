import 'package:ai_cat_mobile/services/automation_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('describeAutomationRule', () {
    test('gunluk saat tetikleyicisini bildirim eylemiyle birlestirir', () {
      final rule = {
        'name': 'Sabah bildirimi',
        'trigger_type': 'time_daily',
        'trigger_value': '09:00',
        'action_type': 'notify',
        'action_value': 'Gunaydin!',
        'enabled': true,
      };
      final text = describeAutomationRule(rule);
      expect(text, contains('Sabah bildirimi'));
      expect(text, contains('Her gun belirli bir saatte (09:00)'));
      expect(text, contains('Bildirim goster: Gunaydin!'));
      expect(text, isNot(contains('devre disi')));
    });

    test('devre disi kural etiketlenir', () {
      final rule = {
        'name': 'Kilitle',
        'trigger_type': 'idle_minutes',
        'trigger_value': 30,
        'action_type': 'lock',
        'enabled': false,
      };
      expect(describeAutomationRule(rule), contains('[devre disi]'));
    });

    test('deger olmayan eylem icin sadece etiketi gosterir', () {
      final rule = {
        'name': 'Uyku',
        'trigger_type': 'idle_minutes',
        'trigger_value': 15,
        'action_type': 'sleep',
        'enabled': true,
      };
      final text = describeAutomationRule(rule);
      expect(text, contains('Uyku moduna al'));
      expect(text, isNot(contains('Uyku moduna al:')));
    });

    test('bilinmeyen tur/eylem oldugu gibi gosterilir', () {
      final rule = {
        'name': 'X',
        'trigger_type': 'bilinmeyen',
        'action_type': 'bilinmeyen_eylem',
        'enabled': true,
      };
      final text = describeAutomationRule(rule);
      expect(text, contains('bilinmeyen'));
      expect(text, contains('bilinmeyen_eylem'));
    });
  });
}
