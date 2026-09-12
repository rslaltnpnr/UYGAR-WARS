import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_cat_mobile/models/chat_entry.dart';
import 'package:ai_cat_mobile/models/remote_profile.dart';
import 'package:ai_cat_mobile/services/history_service.dart';
import 'package:ai_cat_mobile/services/settings_service.dart';
import 'package:ai_cat_mobile/theme/app_colors.dart';
import 'package:ai_cat_mobile/widgets/usage_stats_sheet.dart';

void main() {
  testWidgets(
    'mevcut sohbet gecmisi ve eslesik bilgisayarlardan dogru sayilari '
    'gosterir',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settings = SettingsService(prefs);
      settings.remoteProfiles = const [
        RemoteProfile(
          id: '1',
          name: 'Ev',
          ip: '10.0.0.5',
          port: 8765,
          pin: '111111',
          certFingerprint: '',
        ),
      ];
      final history = HistoryService(prefs);
      history.add(
        ChatEntry(
          time: DateTime.now(),
          question: 'Merhaba',
          answer: 'Selam!',
          isError: false,
        ),
      );
      history.add(
        ChatEntry(
          time: DateTime.now(),
          question: 'İkinci soru',
          answer: 'hata oldu',
          isError: true,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [AppColors.dark]),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) =>
                      UsageStatsSheet(settings: settings, history: history),
                ),
                child: const Text('Aç'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Aç'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Toplam soru'), findsOneWidget);
      expect(find.text('2'), findsWidgets); // toplam soru = 2
      expect(find.text('Hatalı yanıt'), findsOneWidget);
      expect(find.text('1'), findsWidgets); // hatali yanit = 1
      expect(find.text('Eşleşik bilgisayar'), findsOneWidget);
    },
  );
}
