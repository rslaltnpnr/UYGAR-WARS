import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_cat_mobile/main.dart';

void main() {
  testWidgets('Uygulama ana ekrani hata vermeden aciliyor',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const AiCatApp());
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
