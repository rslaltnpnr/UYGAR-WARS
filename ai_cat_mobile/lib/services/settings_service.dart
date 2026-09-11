import 'package:flutter/material.dart' show ThemeMode;
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
  static const _keyDesktopIp = 'desktop_ip';
  static const _keyDesktopPort = 'desktop_port';
  static const _keyDesktopPin = 'desktop_pin';
  static const _keyDesktopCertFingerprint = 'desktop_cert_fingerprint';
  static const _keyThemeMode = 'theme_mode';

  final SharedPreferences _prefs;

  SettingsService(this._prefs);

  String get apiKey => _prefs.getString(_keyApiKey) ?? '';
  set apiKey(String value) => _prefs.setString(_keyApiKey, value);

  String get characterName => _prefs.getString(_keyCharacterName) ?? 'Fuff';
  set characterName(String value) => _prefs.setString(_keyCharacterName, value);

  String get modelName =>
      _prefs.getString(_keyModelName) ?? 'gemini-flash-latest';
  set modelName(String value) => _prefs.setString(_keyModelName, value);

  /// Masaustu uygulamasinin (ai_desktop_assistant) yerel ag IP adresi,
  /// port ve PIN'i - "Bilgisayari Kumanda Et" panelinden set edilir.
  String get desktopIp => _prefs.getString(_keyDesktopIp) ?? '';
  set desktopIp(String value) => _prefs.setString(_keyDesktopIp, value);

  int get desktopPort => _prefs.getInt(_keyDesktopPort) ?? 8765;
  set desktopPort(int value) => _prefs.setInt(_keyDesktopPort, value);

  String get desktopPin => _prefs.getString(_keyDesktopPin) ?? '';
  set desktopPin(String value) => _prefs.setString(_keyDesktopPin, value);

  /// Ilk baglantida (TOFU) kaydedilen sunucu TLS sertifikasinin SHA-256
  /// parmak izi. Sonraki baglantilarda bununla karsilastirilir; bos ise
  /// henuz eslestirme yapilmamis demektir.
  String get desktopCertFingerprint =>
      _prefs.getString(_keyDesktopCertFingerprint) ?? '';
  set desktopCertFingerprint(String value) =>
      _prefs.setString(_keyDesktopCertFingerprint, value);

  /// Varsayilan 'dark' - uygulamanin onceki (tek secenekli) koyu gorunumunu
  /// korur; kullanici acik moda ya da sistem temasina gecebilir.
  ThemeMode get themeMode {
    switch (_prefs.getString(_keyThemeMode)) {
      case 'light':
        return ThemeMode.light;
      case 'system':
        return ThemeMode.system;
      default:
        return ThemeMode.dark;
    }
  }

  set themeMode(ThemeMode mode) {
    final value = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.system => 'system',
      ThemeMode.dark => 'dark',
    };
    _prefs.setString(_keyThemeMode, value);
  }
}
