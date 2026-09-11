import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_cat_mobile/services/settings_service.dart';
import 'package:ai_cat_mobile/theme/app_colors.dart';
import 'package:ai_cat_mobile/widgets/remote_control_sheet.dart';

/// home_screen.dart._handleSharedFiles ile ayni URL cikarma mantigi -
/// paylasilan metinden ilk http(s) baglantisini bulur, yoksa metnin
/// tamamini kullanir.
String? extractUrl(String sharedText) {
  final text = sharedText.trim();
  if (text.isEmpty) return null;
  final match = RegExp(r'https?://\S+').firstMatch(text);
  return match?.group(0) ?? text;
}

void main() {
  group('paylasilan metinden URL cikarma', () {
    test('duz bir link oldugu gibi donuyor', () {
      expect(extractUrl('https://youtube.com/watch?v=abc'), 'https://youtube.com/watch?v=abc');
    });

    test('etrafinda metin olan bir link ayikliyor', () {
      expect(
        extractUrl('Bu videoyu izle: https://youtu.be/xyz123 harika!'),
        'https://youtu.be/xyz123',
      );
    });

    test('link yoksa metnin tamami donuyor (asagida SSRF guard reddeder)', () {
      expect(extractUrl('sadece duz metin'), 'sadece duz metin');
    });

    test('bos metin null donuyor', () {
      expect(extractUrl('   '), null);
    });
  });

  group('RemoteControlSheet initialUrl', () {
    testWidgets('paylasilan link URL alanini onceden dolduruyor', (tester) async {
      // URL alani yalnizca en az bir bilgisayar profili varsa gosterildigi
      // icin (aksi halde bos-durum istemi cikar) onceden bir profil ekli
      // gibi baslatiyoruz.
      SharedPreferences.setMockInitialValues({
        'desktop_ip': '192.168.1.20',
        'desktop_port': 8765,
        'desktop_pin': '123456',
      });
      final prefs = await SharedPreferences.getInstance();
      final settings = SettingsService(prefs);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [AppColors.dark]),
          home: Scaffold(
            body: RemoteControlSheet(
              settings: settings,
              initialUrl: 'https://music.youtube.com/shared',
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final matches = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.controller?.text == 'https://music.youtube.com/shared',
      );
      expect(matches, findsOneWidget);
    });
  });
}
