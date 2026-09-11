import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_cat_mobile/services/backup_service.dart';

void main() {
  group('BackupService.importBackup', () {
    test('gecerli bir yedegi ice aktarir ve tercihleri geri yukler', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final backupJson = jsonEncode({
        'backup_version': 1,
        'preferences': {
          'character_name': 'Fuff',
          'gemini_api_key': 'test-key',
          'theme_mode': 'dark',
          'onboarded': true,
          'reminder_minutes': 30,
        },
      });

      final count = await BackupService().importBackup(backupJson);

      expect(count, 5);
      expect(prefs.getString('character_name'), 'Fuff');
      expect(prefs.getString('gemini_api_key'), 'test-key');
      expect(prefs.getString('theme_mode'), 'dark');
      expect(prefs.getBool('onboarded'), true);
      expect(prefs.getInt('reminder_minutes'), 30);
    });

    test('gecersiz JSON FormatException firlatir', () async {
      SharedPreferences.setMockInitialValues({});
      await expectLater(
        () => BackupService().importBackup('bu gecerli bir json degil'),
        throwsA(isA<FormatException>()),
      );
    });

    test('preferences alani olmayan yedek FormatException firlatir', () async {
      SharedPreferences.setMockInitialValues({});
      await expectLater(
        () => BackupService().importBackup(jsonEncode({'foo': 'bar'})),
        throwsA(isA<FormatException>()),
      );
    });

    test('liste degerler stringlist olarak geri yuklenir', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final backupJson = jsonEncode({
        'backup_version': 1,
        'preferences': {
          'remote_profile_ids': ['a', 'b', 'c'],
        },
      });

      final count = await BackupService().importBackup(backupJson);

      expect(count, 1);
      expect(prefs.getStringList('remote_profile_ids'), ['a', 'b', 'c']);
    });
  });
}
