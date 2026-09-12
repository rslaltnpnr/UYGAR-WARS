import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_cat_mobile/models/queued_command.dart';
import 'package:ai_cat_mobile/models/remote_profile.dart';
import 'package:ai_cat_mobile/services/command_queue_service.dart';
import 'package:ai_cat_mobile/services/remote_control_service.dart';

/// Gercek ag cagrisi yapmadan basari/basarisizlik senaryolarini test
/// etmek icin sahte bir OpenUrlSender.
Future<RemoteControlResult> Function({
  required String ip,
  required int port,
  required String pin,
  required String url,
  required String pinnedFingerprint,
}) _fakeSender({required bool succeeds, List<String>? sentUrls}) {
  return ({
    required ip,
    required port,
    required pin,
    required url,
    required pinnedFingerprint,
  }) async {
    if (!succeeds) {
      throw RemoteControlException('Bilgisayara ulasilamadi.', isNetworkError: true);
    }
    sentUrls?.add(url);
    return const RemoteControlResult('fp-1');
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
  group('CommandQueueService load/enqueue/clear', () {
    test('bos durumda bos liste doner', () async {
      SharedPreferences.setMockInitialValues({});
      final service = CommandQueueService();
      expect(await service.load(), isEmpty);
    });

    test('kuyruklanan komut kalici olur', () async {
      SharedPreferences.setMockInitialValues({});
      final service = CommandQueueService();
      await service.enqueue(
        QueuedCommand(
          profileId: 'p1',
          url: 'https://example.com',
          queuedAt: DateTime(2026, 1, 1),
        ),
      );
      final entries = await service.load();
      expect(entries.length, 1);
      expect(entries.first.url, 'https://example.com');
      expect(entries.first.profileId, 'p1');
    });

    test('clear tum kayitlari siler', () async {
      SharedPreferences.setMockInitialValues({});
      final service = CommandQueueService();
      await service.enqueue(
        QueuedCommand(profileId: 'p1', url: 'https://a.com', queuedAt: DateTime.now()),
      );
      await service.clear();
      expect(await service.load(), isEmpty);
    });

    test('kapasite asilinca en eskiler atilir', () async {
      SharedPreferences.setMockInitialValues({});
      final service = CommandQueueService();
      for (var i = 0; i < CommandQueueService.maxQueueSize + 3; i++) {
        await service.enqueue(
          QueuedCommand(
            profileId: 'p1',
            url: 'https://example.com/$i',
            queuedAt: DateTime(2026, 1, 1).add(Duration(minutes: i)),
          ),
        );
      }
      final entries = await service.load();
      expect(entries.length, CommandQueueService.maxQueueSize);
      expect(entries.first.url, 'https://example.com/3');
    });
  });

  group('CommandQueueService.flushFor', () {
    test('baglanti hala yoksa komutlar kuyrukta kalir', () async {
      SharedPreferences.setMockInitialValues({});
      final service = CommandQueueService();
      await service.enqueue(
        QueuedCommand(profileId: 'p1', url: 'https://a.com', queuedAt: DateTime.now()),
      );

      final sent = await service.flushFor(
        profile: _profile,
        sendOpenUrl: _fakeSender(succeeds: false),
        onFingerprintUpdate: (_) {},
      );

      expect(sent, 0);
      final remaining = await service.load();
      expect(remaining.length, 1);
    });

    test('baglanti kurulunca kuyruktaki komutlar sirayla gonderilir', () async {
      SharedPreferences.setMockInitialValues({});
      final service = CommandQueueService();
      await service.enqueue(
        QueuedCommand(profileId: 'p1', url: 'https://a.com', queuedAt: DateTime.now()),
      );
      await service.enqueue(
        QueuedCommand(profileId: 'p1', url: 'https://b.com', queuedAt: DateTime.now()),
      );

      final sentUrls = <String>[];
      final sent = await service.flushFor(
        profile: _profile,
        sendOpenUrl: _fakeSender(succeeds: true, sentUrls: sentUrls),
        onFingerprintUpdate: (_) {},
      );

      expect(sent, 2);
      expect(sentUrls, ['https://a.com', 'https://b.com']);
      expect(await service.load(), isEmpty);
    });

    test('baska profilin kuyruklu komutlarina dokunmaz', () async {
      SharedPreferences.setMockInitialValues({});
      final service = CommandQueueService();
      await service.enqueue(
        QueuedCommand(profileId: 'baska-profil', url: 'https://b.com', queuedAt: DateTime.now()),
      );

      await service.flushFor(
        profile: _profile,
        sendOpenUrl: _fakeSender(succeeds: true),
        onFingerprintUpdate: (_) {},
      );

      final remaining = await service.load();
      expect(remaining.length, 1);
      expect(remaining.first.profileId, 'baska-profil');
    });
  });
}
