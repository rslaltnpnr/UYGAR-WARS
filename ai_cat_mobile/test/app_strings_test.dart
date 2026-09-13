import 'package:ai_cat_mobile/l10n/app_strings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveSupportedLanguageCode', () {
    test('en icin en doner', () {
      expect(resolveSupportedLanguageCode('en'), 'en');
    });

    test('bilinmeyen ya da null icin tr doner', () {
      expect(resolveSupportedLanguageCode('tr'), 'tr');
      expect(resolveSupportedLanguageCode('de'), 'tr');
      expect(resolveSupportedLanguageCode(null), 'tr');
    });
  });

  group('AppStrings', () {
    test('tr ve en icin farkli metinler doner', () {
      const tr = AppStrings('tr');
      const en = AppStrings('en');
      expect(tr.t('settings_title'), 'Ayarlar');
      expect(en.t('settings_title'), 'Settings');
      expect(tr.t('settings_title'), isNot(en.t('settings_title')));
    });

    test('bilinmeyen anahtar oldugu gibi geri doner', () {
      const strings = AppStrings('tr');
      expect(strings.t('olmayan_anahtar'), 'olmayan_anahtar');
    });

    test('desteklenmeyen dil kodu turkce metne duser', () {
      const strings = AppStrings('de');
      expect(strings.t('settings_title'), 'Ayarlar');
    });
  });
}
