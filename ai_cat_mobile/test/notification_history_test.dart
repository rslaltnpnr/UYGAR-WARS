import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_cat_mobile/services/notification_history_service.dart';

void main() {
  group('NotificationHistoryService', () {
    test('bos durumda bos liste doner', () async {
      SharedPreferences.setMockInitialValues({});
      final service = NotificationHistoryService();
      expect(await service.load(), isEmpty);
    });

    test('eklenen kayit kalici olur', () async {
      SharedPreferences.setMockInitialValues({});
      final service = NotificationHistoryService();
      await service.add(title: 'Başlık', message: 'Mesaj');

      final entries = await service.load();
      expect(entries.length, 1);
      expect(entries.first.title, 'Başlık');
      expect(entries.first.message, 'Mesaj');
    });

    test('birden fazla kayit eklenme sirasiyla saklanir', () async {
      SharedPreferences.setMockInitialValues({});
      final service = NotificationHistoryService();
      await service.add(title: 'A', message: '1');
      await service.add(title: 'B', message: '2');

      final entries = await service.load();
      expect(entries.map((e) => e.title), ['A', 'B']);
    });

    test('maxEntries sinirini asarsa en eskileri atar', () async {
      SharedPreferences.setMockInitialValues({});
      final service = NotificationHistoryService();
      for (var i = 0; i < NotificationHistoryService.maxEntries + 5; i++) {
        await service.add(title: 'T$i', message: 'M$i');
      }

      final entries = await service.load();
      expect(entries.length, NotificationHistoryService.maxEntries);
      expect(entries.first.title, 'T5');
    });

    test('clear tum kayitlari siler', () async {
      SharedPreferences.setMockInitialValues({});
      final service = NotificationHistoryService();
      await service.add(title: 'A', message: '1');
      await service.clear();

      expect(await service.load(), isEmpty);
    });
  });
}
