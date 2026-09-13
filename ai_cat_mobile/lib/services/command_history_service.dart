import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/command_history_entry.dart';

/// Telefondan bilgisayara gonderilen uzaktan komutlarin kalici bir
/// gecmisini cihazda saklar - NotificationHistoryService ile ayni
/// JSON-dump deseni. RemoteControlSheet, her basarili komut sonrasi
/// add() cagirir; komutun kendisi zaten aninda calistigi icin bu yalnizca
/// bir denetim izidir (audit trail), yeniden oynatma ozelligi degildir.
class CommandHistoryService {
  static const _key = 'command_history';
  static const maxEntries = 50;

  Future<List<CommandHistoryEntry>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => CommandHistoryEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> add({
    required String action,
    required String detail,
    required String profileName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final entries = await load()
      ..add(
        CommandHistoryEntry(
          time: DateTime.now(),
          action: action,
          detail: detail,
          profileName: profileName,
        ),
      );
    final trimmed = entries.length > maxEntries
        ? entries.sublist(entries.length - maxEntries)
        : entries;
    await prefs.setString(
      _key,
      jsonEncode(trimmed.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
