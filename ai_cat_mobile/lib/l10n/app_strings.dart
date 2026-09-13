import 'package:flutter/material.dart';

/// Hafif, elle yazilmis bir cok-dil (TR/EN) altyapisi - Flutter'in
/// gen-l10n/intl araci yerine, cevrilecek anahtarlarin kucuk ve sabit bir
/// kumesi (ayarlar penceresi) icin yeterli. [SettingsService.languageCode]
/// ('system'/'tr'/'en') dogrultusunda cozumlenen dil, MaterialApp'in
/// [locale] parametresine VE bu InheritedWidget'a ayni anda uygulanir.
///
/// Kapsam: su an yalnizca Ayarlar penceresi tam olarak iki dilli - ilk
/// eklenen, kendi basina eksiksiz bir dilim. Diger ekranlar hala sabit
/// Turkce metin kullanir; genisletmek istenirse ayni [_strings] tablosuna
/// yeni anahtarlar eklemek yeterli.
const Map<String, Map<String, String>> _strings = {
  'tr': {
    'settings_title': 'Ayarlar',
    'settings_character_name': 'Karakter Adı',
    'settings_api_key': 'Gemini API Anahtarı',
    'settings_theme': 'Tema',
    'settings_theme_system': 'Sistem',
    'settings_theme_light': 'Açık',
    'settings_theme_dark': 'Koyu',
    'settings_language': 'Dil',
    'settings_language_system': 'Sistem',
    'settings_language_tr': 'Türkçe',
    'settings_language_en': 'İngilizce',
    'settings_save': 'Kaydet',
    'settings_cancel': 'İptal',
    'settings_about': 'Hakkında',
  },
  'en': {
    'settings_title': 'Settings',
    'settings_character_name': 'Character Name',
    'settings_api_key': 'Gemini API Key',
    'settings_theme': 'Theme',
    'settings_theme_system': 'System',
    'settings_theme_light': 'Light',
    'settings_theme_dark': 'Dark',
    'settings_language': 'Language',
    'settings_language_system': 'System',
    'settings_language_tr': 'Turkish',
    'settings_language_en': 'English',
    'settings_save': 'Save',
    'settings_cancel': 'Cancel',
    'settings_about': 'About',
  },
};

/// Desteklenen bir dil kodu degilse (ya da 'system' cozumlenemiyorsa)
/// 'tr'ye duser - uygulama Turkce oncelikli tasarlandigi icin.
String resolveSupportedLanguageCode(String? languageCode) {
  if (languageCode == 'en') return 'en';
  return 'tr';
}

class AppStrings {
  final String languageCode;

  const AppStrings(this.languageCode);

  String t(String key) =>
      _strings[languageCode]?[key] ?? _strings['tr']![key] ?? key;
}

class AppStringsScope extends InheritedWidget {
  final AppStrings strings;

  const AppStringsScope({
    super.key,
    required this.strings,
    required super.child,
  });

  static AppStrings of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppStringsScope>();
    return scope?.strings ?? const AppStrings('tr');
  }

  @override
  bool updateShouldNotify(AppStringsScope oldWidget) =>
      oldWidget.strings.languageCode != strings.languageCode;
}
