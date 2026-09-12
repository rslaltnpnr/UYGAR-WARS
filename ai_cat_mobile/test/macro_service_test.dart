import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_cat_mobile/models/command_macro.dart';
import 'package:ai_cat_mobile/models/remote_profile.dart';
import 'package:ai_cat_mobile/services/macro_service.dart';
import 'package:ai_cat_mobile/services/remote_control_service.dart';

/// Gercek ag cagrisi yapmadan basari/basarisizlik senaryolarini test etmek
/// icin sahte gonderi fonksiyonlari (CommandQueueService testindeki
/// _fakeSender ile ayni yaklasim).
Future<RemoteControlResult> Function({
  required String ip,
  required int port,
  required String pin,
  required String url,
  required String pinnedFingerprint,
}) _fakeOpenUrl({required bool succeeds, List<String>? calls}) {
  return ({
    required ip,
    required port,
    required pin,
    required url,
    required pinnedFingerprint,
  }) async {
    calls?.add(url);
    if (!succeeds) {
      throw RemoteControlException('Bilgisayara ulasilamadi.', isNetworkError: true);
    }
    return const RemoteControlResult('fp-open');
  };
}

Future<RemoteControlResult> Function({
  required String ip,
  required int port,
  required String pin,
  required String action,
  required String pinnedFingerprint,
}) _fakeAction({required bool succeeds, List<String>? calls}) {
  return ({
    required ip,
    required port,
    required pin,
    required action,
    required pinnedFingerprint,
  }) async {
    calls?.add(action);
    if (!succeeds) {
      throw RemoteControlException('Reddedildi.');
    }
    return const RemoteControlResult('fp-action');
  };
}

const _profile = RemoteProfile(
  id: 'p1',
  name: 'Ev',
  ip: '10.0.0.5',
  port: 8765,
  pin: '111111',
  certFingerprint: 'AA:BB',
);

void main() {
  group('MacroService load/add/delete', () {
    test('bos durumda bos liste doner', () async {
      SharedPreferences.setMockInitialValues({});
      final service = MacroService();
      expect(await service.load(), isEmpty);
    });

    test('eklenen makro kalici olur', () async {
      SharedPreferences.setMockInitialValues({});
      final service = MacroService();
      await service.add(
        const CommandMacro(
          id: 'm1',
          name: 'Çalışma Modu',
          steps: [
            MacroStep(type: 'open_url', value: 'https://example.com'),
            MacroStep(type: 'media', value: 'vol_down'),
          ],
        ),
      );
      final macros = await service.load();
      expect(macros.length, 1);
      expect(macros.first.name, 'Çalışma Modu');
      expect(macros.first.steps.length, 2);
      expect(macros.first.steps.first.type, 'open_url');
    });

    test('silinen makro listeden kaybolur', () async {
      SharedPreferences.setMockInitialValues({});
      final service = MacroService();
      await service.add(
        const CommandMacro(id: 'm1', name: 'A', steps: [
          MacroStep(type: 'power', value: 'lock'),
        ]),
      );
      await service.add(
        const CommandMacro(id: 'm2', name: 'B', steps: [
          MacroStep(type: 'power', value: 'sleep'),
        ]),
      );
      await service.delete('m1');
      final macros = await service.load();
      expect(macros.length, 1);
      expect(macros.first.id, 'm2');
    });
  });

  group('MacroService.run', () {
    test('tum adimlar basarili olursa hepsi tamamlanir', () async {
      final service = MacroService();
      final openCalls = <String>[];
      final actionCalls = <String>[];
      const macro = CommandMacro(
        id: 'm1',
        name: 'Çalışma Modu',
        steps: [
          MacroStep(type: 'open_url', value: 'https://example.com'),
          MacroStep(type: 'media', value: 'vol_down'),
          MacroStep(type: 'power', value: 'lock'),
        ],
      );

      final result = await service.run(
        macro: macro,
        profile: _profile,
        sendOpenUrl: _fakeOpenUrl(succeeds: true, calls: openCalls),
        sendMedia: _fakeAction(succeeds: true, calls: actionCalls),
        sendPower: _fakeAction(succeeds: true, calls: actionCalls),
        onFingerprintUpdate: (_) {},
        enqueueOpenUrl: (_) async {},
      );

      expect(result.succeeded, 3);
      expect(result.queued, 0);
      expect(result.failed, 0);
      expect(openCalls, ['https://example.com']);
      expect(actionCalls, ['vol_down', 'lock']);
    });

    test('baglanti hatasindaki open_url adimi kuyruga eklenir, digerleri '
        'yine de denenir', () async {
      SharedPreferences.setMockInitialValues({});
      final service = MacroService();
      final queued = <String>[];
      const macro = CommandMacro(
        id: 'm1',
        name: 'Çalışma Modu',
        steps: [
          MacroStep(type: 'open_url', value: 'https://example.com'),
          MacroStep(type: 'media', value: 'mute'),
        ],
      );

      final result = await service.run(
        macro: macro,
        profile: _profile,
        sendOpenUrl: _fakeOpenUrl(succeeds: false),
        sendMedia: _fakeAction(succeeds: true),
        sendPower: _fakeAction(succeeds: true),
        onFingerprintUpdate: (_) {},
        enqueueOpenUrl: (cmd) async => queued.add(cmd.url),
      );

      expect(result.succeeded, 1);
      expect(result.queued, 1);
      expect(result.failed, 0);
      expect(queued, ['https://example.com']);
    });

    test('baglanti hatasindaki media/power adimi kuyruklanmaz, basarisiz '
        'sayilir', () async {
      final service = MacroService();
      const macro = CommandMacro(
        id: 'm1',
        name: 'Uyku',
        steps: [MacroStep(type: 'power', value: 'sleep')],
      );

      final result = await service.run(
        macro: macro,
        profile: _profile,
        sendOpenUrl: _fakeOpenUrl(succeeds: true),
        sendMedia: _fakeAction(succeeds: true),
        sendPower: ({
          required ip,
          required port,
          required pin,
          required action,
          required pinnedFingerprint,
        }) async {
          throw RemoteControlException('Baglanti yok.', isNetworkError: true);
        },
        onFingerprintUpdate: (_) {},
        enqueueOpenUrl: (_) async {},
      );

      expect(result.succeeded, 0);
      expect(result.queued, 0);
      expect(result.failed, 1);
    });
  });
}
