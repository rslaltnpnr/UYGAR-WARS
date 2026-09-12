import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/command_macro.dart';
import '../models/queued_command.dart';
import '../models/remote_profile.dart';
import 'command_queue_service.dart' show OpenUrlSender;
import 'remote_control_service.dart';

/// [RemoteControlService.sendMedia] ve [RemoteControlService.sendPower]
/// ile ayni imza - MacroService bunlari dogrudan bir RemoteControlService'e
/// degil, bu tip uzerinden alarak gercek ag cagrisi yapmadan test
/// edilebilir kalir (bkz. CommandQueueService'teki OpenUrlSender).
typedef ActionSender = Future<RemoteControlResult> Function({
  required String ip,
  required int port,
  required String pin,
  required String action,
  required String pinnedFingerprint,
});

/// Bir makro calistirmasinin sonucu: kac adim basarili oldu, kac tanesi
/// (yalnizca open_url adimlari icin) baglanti olmadigi icin kuyruga
/// alindi, kac tanesi basarisiz oldu.
class MacroRunResult {
  final int succeeded;
  final int queued;
  final int failed;

  const MacroRunResult({
    required this.succeeded,
    required this.queued,
    required this.failed,
  });
}

/// Kullanicinin tanimladigi makrolari (CommandMacro) saklar ve calistirir -
/// HistoryService/CommandQueueService ile ayni JSON-dump deseni. Kendi
/// SharedPreferences ornegini alir, boylece cagiran her yerden tek
/// satirla kullanilabilir.
class MacroService {
  static const _key = 'command_macros';

  Future<List<CommandMacro>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => CommandMacro.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _save(List<CommandMacro> macros) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(macros.map((m) => m.toJson()).toList()),
    );
  }

  Future<void> add(CommandMacro macro) async {
    final macros = await load()..add(macro);
    await _save(macros);
  }

  Future<void> delete(String id) async {
    final macros = await load()..removeWhere((m) => m.id == id);
    await _save(macros);
  }

  /// [macro]'nun adimlarini [profile] uzerinde sirayla calistirir. Bir
  /// adim baglanti hatasi yuzunden basarisiz olursa ve turu open_url ise
  /// (bkz. CommandQueueService/QueuedCommand'teki gerekce - medya/guc
  /// komutlari "simdi" anlamina gelir) cihazda kuyruga alinir; diger
  /// hatalar (ya da medya/guc adimlarindaki baglanti hatalari) o adimi
  /// basarisiz sayar ve kalan adimlar yine de denenir - tek bir adimin
  /// basarisiz olmasi makronun geri kalanini durdurmaz.
  Future<MacroRunResult> run({
    required CommandMacro macro,
    required RemoteProfile profile,
    required OpenUrlSender sendOpenUrl,
    required ActionSender sendMedia,
    required ActionSender sendPower,
    required void Function(String fingerprint) onFingerprintUpdate,
    required Future<void> Function(QueuedCommand) enqueueOpenUrl,
  }) async {
    var succeeded = 0;
    var queued = 0;
    var failed = 0;
    var fingerprint = profile.certFingerprint;

    for (final step in macro.steps) {
      try {
        final RemoteControlResult result;
        switch (step.type) {
          case 'open_url':
            result = await sendOpenUrl(
              ip: profile.ip,
              port: profile.port,
              pin: profile.pin,
              url: step.value,
              pinnedFingerprint: fingerprint,
            );
            break;
          case 'media':
            result = await sendMedia(
              ip: profile.ip,
              port: profile.port,
              pin: profile.pin,
              action: step.value,
              pinnedFingerprint: fingerprint,
            );
            break;
          case 'power':
            result = await sendPower(
              ip: profile.ip,
              port: profile.port,
              pin: profile.pin,
              action: step.value,
              pinnedFingerprint: fingerprint,
            );
            break;
          default:
            continue;
        }
        fingerprint = result.fingerprint;
        onFingerprintUpdate(fingerprint);
        succeeded++;
      } catch (exc) {
        if (step.type == 'open_url' &&
            exc is RemoteControlException &&
            exc.isNetworkError) {
          await enqueueOpenUrl(
            QueuedCommand(
              profileId: profile.id,
              url: step.value,
              queuedAt: DateTime.now(),
            ),
          );
          queued++;
        } else {
          failed++;
        }
      }
    }

    return MacroRunResult(succeeded: succeeded, queued: queued, failed: failed);
  }
}
