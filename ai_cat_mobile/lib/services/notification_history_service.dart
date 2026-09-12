import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/notification_entry.dart';

/// Uygulamanin gosterdigi bildirimlerin (masaustu uyarilari, kurulan
/// hatirlaticilar) kalici bir gecmisini cihazda saklar - HistoryService'in
/// sohbet gecmisi icin yaptigi ile ayni JSON-dump deseni. Diger
/// servislerden farkli olarak SharedPreferences ornegini kendisi alir
/// (constructor'a enjekte edilmez) - showAlert/scheduleReminder cagiran
/// her yerden (home_screen.dart, reminder_dialog.dart) tek satirla
/// kullanilabilsin diye.
class NotificationHistoryService {
  static const _key = 'notification_history';
  static const maxEntries = 50;

  Future<List<NotificationEntry>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => NotificationEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> add({required String title, required String message}) async {
    final prefs = await SharedPreferences.getInstance();
    final entries = await load()
      ..add(NotificationEntry(time: DateTime.now(), title: title, message: message));
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
