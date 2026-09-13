import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_cat_mobile/services/command_history_service.dart';

void main() {
  group('CommandHistoryService', () {
    test('kayit yoksa bos liste doner', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await CommandHistoryService().load(), isEmpty);
    });

    test('eklenen kayit geri yuklenir', () async {
      SharedPreferences.setMockInitialValues({});
      final service = CommandHistoryService();
      await service.add(action: 'Bağlantı Aç', detail: 'https://x.com', profileName: 'Ev');
      final entries = await service.load();
      expect(entries.length, 1);
      expect(entries.first.action, 'Bağlantı Aç');
      expect(entries.first.detail, 'https://x.com');
      expect(entries.first.profileName, 'Ev');
    });

    test('maksimum kayit sayisini asmaz', () async {
      SharedPreferences.setMockInitialValues({});
      final service = CommandHistoryService();
      for (var i = 0; i < 60; i++) {
        await service.add(action: 'Medya', detail: '$i', profileName: 'Ev');
      }
      final entries = await service.load();
      expect(entries.length, CommandHistoryService.maxEntries);
      expect(entries.last.detail, '59');
    });

    test('clear tum kayitlari siler', () async {
      SharedPreferences.setMockInitialValues({});
      final service = CommandHistoryService();
      await service.add(action: 'Güç', detail: 'kilitle', profileName: 'Ev');
      await service.clear();
      expect(await service.load(), isEmpty);
    });
  });
}
