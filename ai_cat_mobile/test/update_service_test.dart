import 'package:flutter_test/flutter_test.dart';

import 'package:ai_cat_mobile/services/update_service.dart';

void main() {
  group('isNewerVersion', () {
    test('daha yuksek patch surumu daha yeni sayilir', () {
      expect(isNewerVersion('v1.1.1', '1.1.0'), isTrue);
    });

    test('daha yuksek minor surumu daha yeni sayilir', () {
      expect(isNewerVersion('v1.2.0', '1.1.9'), isTrue);
    });

    test('ayni surum daha yeni sayilmaz', () {
      expect(isNewerVersion('v1.1.1', '1.1.1'), isFalse);
    });

    test('daha eski surum daha yeni sayilmaz', () {
      expect(isNewerVersion('v1.0.0', '1.1.0'), isFalse);
    });

    test('cift haneli parcalar dogru karsilastirilir (sozluksel degil)', () {
      expect(isNewerVersion('v1.10.0', '1.9.0'), isTrue);
    });

    test('eksik parcalar 0 olarak varsayilir', () {
      expect(isNewerVersion('v1.2', '1.1.9'), isTrue);
      expect(isNewerVersion('v1.1', '1.1.0'), isFalse);
    });

    test('bas harfi v olmayan surumler de calisir', () {
      expect(isNewerVersion('1.2.0', '1.1.0'), isTrue);
    });
  });

  group('findReleaseWithAsset', () {
    Map<String, dynamic> release({
      required String tag,
      required List<String> assetNames,
      bool draft = false,
      bool prerelease = false,
    }) {
      return {
        'tag_name': tag,
        'draft': draft,
        'prerelease': prerelease,
        'assets': assetNames.map((name) => {'name': name}).toList(),
      };
    }

    test(
      'depo release listesini masaustu ve mobil karisikken dogru ayikliyor',
      () {
        // Gercek senaryo: masaustu daha yeni bir release yayinladi
        // (v1.2.0, sadece .exe), mobilin kendi surumu (v1.0.0, .apk)
        // listede daha asagida. /releases/latest kullansaydik yanlislikla
        // masaustu release'ini bulurduk.
        final releases = [
          release(tag: 'v1.2.0', assetNames: ['AI-Kedi-Asistani.exe']),
          release(tag: 'v1.0.0', assetNames: ['ai-kedi-asistani.apk']),
        ];

        final found = findReleaseWithAsset(releases, 'ai-kedi-asistani.apk');

        expect(found, isNotNull);
        expect(found!['tag_name'], 'v1.0.0');
      },
    );

    test('taslak (draft) release atlanir', () {
      final releases = [
        release(
          tag: 'v2.0.0',
          assetNames: ['ai-kedi-asistani.apk'],
          draft: true,
        ),
        release(tag: 'v1.0.0', assetNames: ['ai-kedi-asistani.apk']),
      ];

      final found = findReleaseWithAsset(releases, 'ai-kedi-asistani.apk');

      expect(found!['tag_name'], 'v1.0.0');
    });

    test('on-surum (prerelease) atlanir', () {
      final releases = [
        release(
          tag: 'v2.0.0-beta',
          assetNames: ['ai-kedi-asistani.apk'],
          prerelease: true,
        ),
        release(tag: 'v1.0.0', assetNames: ['ai-kedi-asistani.apk']),
      ];

      final found = findReleaseWithAsset(releases, 'ai-kedi-asistani.apk');

      expect(found!['tag_name'], 'v1.0.0');
    });

    test('eslesen asset olan release yoksa null doner', () {
      final releases = [
        release(tag: 'v1.2.0', assetNames: ['AI-Kedi-Asistani.exe']),
      ];

      expect(findReleaseWithAsset(releases, 'ai-kedi-asistani.apk'), isNull);
    });

    test('bos liste null doner', () {
      expect(findReleaseWithAsset(const [], 'ai-kedi-asistani.apk'), isNull);
    });
  });
}
