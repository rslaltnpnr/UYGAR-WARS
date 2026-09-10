import 'package:shared_preferences/shared_preferences.dart';

/// Ayarlari (API anahtari, kedi ismi, model adi) cihazda saklar.
///
/// Not: shared_preferences duz metin olarak saklar (masaustu suruminin
/// config.json'u gibi) - sifrelenmis bir kasa degildir. Cihaz paylasiliyorsa
/// bunu goz onunde bulundurun.
class SettingsService {
  static const _keyApiKey = 'gemini_api_key';
  static const _keyCharacterName = 'character_name';
  static const _keyModelName = 'model_name';

  final SharedPreferences _prefs;

  SettingsService(this._prefs);

  String get apiKey => _prefs.getString(_keyApiKey) ?? '';
  set apiKey(String value) => _prefs.setString(_keyApiKey, value);

  String get characterName => _prefs.getString(_keyCharacterName) ?? 'Fuff';
  set characterName(String value) => _prefs.setString(_keyCharacterName, value);

  String get modelName =>
      _prefs.getString(_keyModelName) ?? 'gemini-flash-latest';
  set modelName(String value) => _prefs.setString(_keyModelName, value);
}
