import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_entry.dart';

/// Sohbet gecmisini cihazda JSON olarak saklar (masaustu suruminde
/// chat_history.json ile ayni mantik), en fazla [maxEntries] kayit tutar.
class HistoryService {
  static const _key = 'chat_history';
  static const maxEntries = 200;

  final SharedPreferences _prefs;

  HistoryService(this._prefs);

  List<ChatEntry> load() {
    final raw = _prefs.getString(_key);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => ChatEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  void add(ChatEntry entry) {
    final entries = load()..add(entry);
    final trimmed = entries.length > maxEntries
        ? entries.sublist(entries.length - maxEntries)
        : entries;
    _prefs.setString(_key, jsonEncode(trimmed.map((e) => e.toJson()).toList()));
  }

  /// [entries] listesinin tamamiyla saklanan gecmisi degistirir (en eski en
  /// basta olacak sekilde) - favori isaretleme gibi mevcut kayitlari yerinde
  /// guncelleyen islemler icin, add()'in tersine yeni bir kayit eklemez.
  void saveAll(List<ChatEntry> entries) {
    final trimmed = entries.length > maxEntries
        ? entries.sublist(entries.length - maxEntries)
        : entries;
    _prefs.setString(_key, jsonEncode(trimmed.map((e) => e.toJson()).toList()));
  }

  void clear() => _prefs.remove(_key);
}
