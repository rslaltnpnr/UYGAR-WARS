import 'package:flutter_test/flutter_test.dart';

import 'package:ai_cat_mobile/services/widget_service.dart';

void main() {
  group('WidgetService.actionFromUri', () {
    test('sohbet URI\'si dogru eylemi doner', () {
      expect(
        WidgetService.actionFromUri(Uri.parse('catwidget://open?screen=chat')),
        WidgetLaunchAction.chat,
      );
    });

    test('kumanda URI\'si dogru eylemi doner', () {
      expect(
        WidgetService.actionFromUri(
          Uri.parse('catwidget://open?screen=remote'),
        ),
        WidgetLaunchAction.remoteControl,
      );
    });

    test('null URI null doner', () {
      expect(WidgetService.actionFromUri(null), isNull);
    });

    test('farkli bir scheme null doner', () {
      expect(
        WidgetService.actionFromUri(Uri.parse('https://example.com')),
        isNull,
      );
    });

    test('bilinmeyen ekran degeri null doner', () {
      expect(
        WidgetService.actionFromUri(
          Uri.parse('catwidget://open?screen=unknown'),
        ),
        isNull,
      );
    });

    test('screen parametresi olmayan URI null doner', () {
      expect(
        WidgetService.actionFromUri(Uri.parse('catwidget://open')),
        isNull,
      );
    });
  });
}
