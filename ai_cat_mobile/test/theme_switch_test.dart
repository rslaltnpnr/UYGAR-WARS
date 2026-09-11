import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_cat_mobile/main.dart';
import 'package:ai_cat_mobile/theme/app_colors.dart';

void main() {
  testWidgets('Ayarlardan tema degistirilebiliyor ve kalici oluyor',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const AiCatApp());
    await tester.pumpAndSettle();

    // Baslangicta koyu tema (varsayilan).
    var materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.themeMode, ThemeMode.dark);

    // Ayarlar dialogunu ac.
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();
    expect(find.byType(SegmentedButton<ThemeMode>), findsOneWidget);

    // "Acik" segmentine bas, sonra Kaydet.
    await tester.tap(find.text('Açık'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();

    materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.themeMode, ThemeMode.light);

    // Tercih SharedPreferences'a yazilmis olmali.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('theme_mode'), 'light');

    // Acik temadaki AppColors gercekten farkli/dogru mu?
    final context = tester.element(find.byType(Scaffold).first);
    final colors = Theme.of(context).extension<AppColors>();
    expect(colors, isNotNull);
    expect(colors!.scaffoldBackground, AppColors.light.scaffoldBackground);
  });
}
