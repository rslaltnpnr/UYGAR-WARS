import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_cat_mobile/services/settings_service.dart';
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

    test('hatirlatici URI\'si dogru eylemi doner', () {
      expect(
        WidgetService.actionFromUri(
          Uri.parse('catwidget://open?screen=reminder'),
        ),
        WidgetLaunchAction.reminder,
      );
    });
  });

  group('WidgetLaunchAction.fromUriValue', () {
    test('her deger kendi uriValue\'suyla eslesir (round-trip)', () {
      for (final action in WidgetLaunchAction.values) {
        expect(WidgetLaunchAction.fromUriValue(action.uriValue), action);
      }
    });

    test('bilinmeyen deger null doner', () {
      expect(WidgetLaunchAction.fromUriValue('bilinmeyen'), isNull);
      expect(WidgetLaunchAction.fromUriValue(null), isNull);
    });
  });

  group('SettingsService widget slot eylemleri', () {
    test('varsayilan 1. buton sohbet, 2. buton kumandadir', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsService(await SharedPreferences.getInstance());
      expect(settings.widgetSlot1Action, WidgetLaunchAction.chat);
      expect(settings.widgetSlot2Action, WidgetLaunchAction.remoteControl);
    });

    test('atanan eylem kalici olur', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsService(await SharedPreferences.getInstance());
      settings.widgetSlot1Action = WidgetLaunchAction.reminder;
      settings.widgetSlot2Action = WidgetLaunchAction.chat;
      expect(settings.widgetSlot1Action, WidgetLaunchAction.reminder);
      expect(settings.widgetSlot2Action, WidgetLaunchAction.chat);
    });
  });
}
