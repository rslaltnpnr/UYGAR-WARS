import 'dart:convert';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/remote_profile.dart';

/// Ayarlari (API anahtari, kedi ismi, model adi) cihazda saklar.
///
/// Not: shared_preferences duz metin olarak saklar (masaustu suruminin
/// config.json'u gibi) - sifrelenmis bir kasa degildir. Cihaz paylasiliyorsa
/// bunu goz onunde bulundurun.
class SettingsService {
  static const _keyApiKey = 'gemini_api_key';
  static const _keyCharacterName = 'character_name';
  static const _keyModelName = 'model_name';
  // Eski (tek bilgisayarli) uzaktan kumanda alanlari - artik dogrudan
  // kullanilmiyor, yalnizca ilk kez birden fazla bilgisayar profiline
  // gecerken tek seferlik gocu (migration) icin okunuyor.
  static const _keyDesktopIp = 'desktop_ip';
  static const _keyDesktopPort = 'desktop_port';
  static const _keyDesktopPin = 'desktop_pin';
  static const _keyDesktopCertFingerprint = 'desktop_cert_fingerprint';
  static const _keyRemoteProfiles = 'remote_profiles';
  static const _keyActiveProfileId = 'active_profile_id';
  static const _keyThemeMode = 'theme_mode';
  static const _keyAutoBackupEnabled = 'auto_backup_enabled';
  static const _keyAutoBackupLast = 'auto_backup_last';

  final SharedPreferences _prefs;

  SettingsService(this._prefs);

  String get apiKey => _prefs.getString(_keyApiKey) ?? '';
  set apiKey(String value) => _prefs.setString(_keyApiKey, value);

  String get characterName => _prefs.getString(_keyCharacterName) ?? 'Fuff';
  set characterName(String value) => _prefs.setString(_keyCharacterName, value);

  String get modelName =>
      _prefs.getString(_keyModelName) ?? 'gemini-flash-latest';
  set modelName(String value) => _prefs.setString(_keyModelName, value);

  /// Eslestirilmis bilgisayarlarin listesi (ev/is gibi birden fazla
  /// bilgisayarla eslesip aralarinda gecis yapilabilir). Ilk okumada,
  /// eski tek-bilgisayarli kurulumdan kalma alanlar varsa bunlari otomatik
  /// olarak tek bir profile donusturur.
  List<RemoteProfile> get remoteProfiles {
    final raw = _prefs.getString(_keyRemoteProfiles);
    if (raw == null) return _migrateLegacyProfile();
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => RemoteProfile.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  set remoteProfiles(List<RemoteProfile> profiles) {
    _prefs.setString(
      _keyRemoteProfiles,
      jsonEncode(profiles.map((p) => p.toJson()).toList()),
    );
  }

  String? get activeProfileId => _prefs.getString(_keyActiveProfileId);

  set activeProfileId(String? id) {
    if (id == null) {
      _prefs.remove(_keyActiveProfileId);
    } else {
      _prefs.setString(_keyActiveProfileId, id);
    }
  }

  List<RemoteProfile> _migrateLegacyProfile() {
    final legacyIp = _prefs.getString(_keyDesktopIp) ?? '';
    if (legacyIp.isEmpty) return [];
    final profile = RemoteProfile(
      id: 'legacy',
      name: 'Bilgisayar',
      ip: legacyIp,
      port: _prefs.getInt(_keyDesktopPort) ?? 8765,
      pin: _prefs.getString(_keyDesktopPin) ?? '',
      certFingerprint: _prefs.getString(_keyDesktopCertFingerprint) ?? '',
    );
    final profiles = [profile];
    remoteProfiles = profiles;
    activeProfileId = profile.id;
    return profiles;
  }

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

  /// Varsayilan true - masaustu suruumundeki ayni varsayilanla tutarli.
  bool get autoBackupEnabled => _prefs.getBool(_keyAutoBackupEnabled) ?? true;
  set autoBackupEnabled(bool value) =>
      _prefs.setBool(_keyAutoBackupEnabled, value);

  /// En son otomatik yedek alinan zaman (ISO 8601) - hic alinmadiysa null.
  String? get autoBackupLast => _prefs.getString(_keyAutoBackupLast);
  set autoBackupLast(String? value) {
    if (value == null) {
      _prefs.remove(_keyAutoBackupLast);
    } else {
      _prefs.setString(_keyAutoBackupLast, value);
    }
  }
}
