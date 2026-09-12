import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_cat_mobile/services/secure_notepad_service.dart';
import 'package:ai_cat_mobile/theme/app_colors.dart';
import 'package:ai_cat_mobile/widgets/secure_notepad_sheet.dart';

/// PBKDF2 gercek anahtar turetmesi yapar - varsayilan 200k iterasyon
/// widget testlerini gereksiz yavaslatir, bu yuzden testler dusuk bir
/// iterasyon sayisiyla calisir (ayni kod yolunu sinar, sadece daha hizli).
Future<void> _pumpSheet(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(extensions: const [AppColors.dark]),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (_) => SecureNotepadSheet(
                service: SecureNotepadService(pbkdf2Iterations: 100),
              ),
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
}

void main() {
  testWidgets(
    'ilk acilista kurulum formu gorunur, sifre kurulunca not eklenip '
    'silinebilir, kilitlenip dogru sifreyle tekrar acilir',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await _pumpSheet(tester);

      // Ilk acilista kurulum formu.
      expect(find.text('Yeni şifre'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Yeni şifre'), '1234');
      await tester.enterText(
        find.widgetWithText(TextField, 'Şifreyi tekrar yaz'),
        '1234',
      );
      await tester.tap(find.text('Not Defterini Kur'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Kurulum sonrasi bos not listesi.
      expect(find.text('Henüz bir not yok. Eklemek için + simgesine dokunun.'),
          findsOneWidget);

      // Yeni not ekle.
      await tester.tap(find.byTooltip('Yeni Not'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(find.widgetWithText(TextField, 'Başlık'), 'Test Notu');
      await tester.enterText(find.widgetWithText(TextField, 'Not'), 'İçerik burada');
      await tester.tap(find.text('Kaydet'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Test Notu'), findsOneWidget);

      // Kilitle - not listesi artik gorunmemeli, sifre formu gelmeli.
      await tester.tap(find.byTooltip('Kilitle'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Test Notu'), findsNothing);
      expect(find.widgetWithText(TextField, 'Şifre'), findsOneWidget);

      // Yanlis sifreyle acilmamali.
      await tester.enterText(find.widgetWithText(TextField, 'Şifre'), 'yanlis');
      await tester.tap(find.text('Kilidi Aç'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Yanlış şifre.'), findsOneWidget);

      // Dogru sifreyle acilinca not geri gelmeli.
      await tester.enterText(find.widgetWithText(TextField, 'Şifre'), '1234');
      await tester.tap(find.text('Kilidi Aç'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Test Notu'), findsOneWidget);

      // Notu sil.
      await tester.tap(find.byTooltip('Notu Sil'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Test Notu'), findsNothing);
    },
  );
}
