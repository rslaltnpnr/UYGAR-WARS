import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/queued_command.dart';
import '../models/remote_profile.dart';
import 'remote_control_service.dart';

/// [RemoteControlService.openUrl]'in imzasiyla ayni - flushFor() bunu
/// dogrudan bir RemoteControlService'e degil, bu tip uzerinden alarak
/// gercek ag cagrisi yapmadan (sahte bir gonderici ile) test edilebilir
/// kalmasini saglar.
typedef OpenUrlSender = Future<RemoteControlResult> Function({
  required String ip,
  required int port,
  required String pin,
  required String url,
  required String pinnedFingerprint,
});

/// Baglanti kurulamadigi icin bekletilen "bilgisayarda ac" komutlarini
/// cihazda saklar - HistoryService/NotificationHistoryService ile ayni
/// JSON-dump deseni. Kendi SharedPreferences ornegini alir (constructor'a
/// enjekte edilmez), boylece cagiran her yerden (remote_control_sheet.dart,
/// home_screen.dart) tek satirla kullanilabilir.
class CommandQueueService {
  static const _key = 'queued_open_commands';
  static const maxQueueSize = 20;

  Future<List<QueuedCommand>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => QueuedCommand.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _save(List<QueuedCommand> entries) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = entries.length > maxQueueSize
        ? entries.sublist(entries.length - maxQueueSize)
        : entries;
    await prefs.setString(
      _key,
      jsonEncode(trimmed.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> enqueue(QueuedCommand command) async {
    final entries = await load()..add(command);
    await _save(entries);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  /// [profile] icin kuyrukta bekleyen komutlari, en eskiden baslayarak
  /// sirayla gondermeyi dener. Bir komut basarili olursa kuyruktan
  /// kalici olarak cikarilir (hemen kaydedilir, boylece yari yolda kesilse
  /// bile zaten gonderilenler tekrar denenmez); bir komut basarisiz
  /// olursa (hala baglanti yoksa) orada durur, kalanlar kuyrukta kalir.
  /// Basariyla gonderilen komut sayisini dondurur.
  Future<int> flushFor({
    required RemoteProfile profile,
    required OpenUrlSender sendOpenUrl,
    required void Function(String fingerprint) onFingerprintUpdate,
  }) async {
    final all = await load();
    final remaining = all.where((c) => c.profileId != profile.id).toList();
    final pending = all.where((c) => c.profileId == profile.id).toList();

    var sentCount = 0;
    var fingerprint = profile.certFingerprint;
    for (final command in pending) {
      try {
        final result = await sendOpenUrl(
          ip: profile.ip,
          port: profile.port,
          pin: profile.pin,
          url: command.url,
          pinnedFingerprint: fingerprint,
        );
        fingerprint = result.fingerprint;
        onFingerprintUpdate(fingerprint);
        sentCount++;
      } catch (_) {
        // Bu ve kalan tum komutlar kuyrukta kalir - siradaki basarili
        // pollda tekrar denenir.
        remaining.addAll(pending.skip(sentCount));
        break;
      }
    }
    await _save(remaining);
    return sentCount;
  }
}
