import 'package:home_widget/home_widget.dart';

/// Ana ekran widget'indaki iki hizli erisim dugmesinin (bkz.
/// `CatWidgetProvider.kt`) acabilecegi ekranlar. Her biri hem bir
/// catwidget:// URI parcasi ("screen" degeri) hem de kullanicinin ayarlar
/// panelinde hangi widget butonuna atayacagini secebilecegi bir secenek.
enum WidgetLaunchAction {
  chat('chat'),
  remoteControl('remote'),
  reminder('reminder'),
  secureNotepad('notepad');

  const WidgetLaunchAction(this.uriValue);

  /// catwidget://open?screen=<uriValue> ve widget'a kaydedilen
  /// widget_slotN_action tercihinde kullanilan sabit dize.
  final String uriValue;

  static WidgetLaunchAction? fromUriValue(String? value) {
    for (final action in WidgetLaunchAction.values) {
      if (action.uriValue == value) return action;
    }
    return null;
  }

  /// Ayarlar panelindeki widget buton secicisinde gosterilen ad.
  String get label => switch (this) {
    WidgetLaunchAction.chat => 'Sohbet',
    WidgetLaunchAction.remoteControl => 'Kumanda',
    WidgetLaunchAction.reminder => 'Hatırlatıcı',
    WidgetLaunchAction.secureNotepad => 'Not Defteri',
  };
}

/// Widget dugmelerine basildiginda uygulamayi acan `catwidget://open?screen=...`
/// URI'lerini cozumler; widget disindan (normal simge) acilislarda [uri] null
/// olur.
class WidgetService {
  static const _androidProviderName = 'CatWidgetProvider';

  static WidgetLaunchAction? actionFromUri(Uri? uri) {
    if (uri == null || uri.scheme != 'catwidget') return null;
    return WidgetLaunchAction.fromUriValue(uri.queryParameters['screen']);
  }

  /// Kullaniciya widget'i ana ekrana eklemesi icin sistem istemini gosterir
  /// (Android 8+, destekleyen launcher'larda). Doner: istem gosterildiyse
  /// true, cihaz/baslatici desteklemiyorsa false.
  static Future<bool> requestPinWidget() async {
    final supported = await HomeWidget.isRequestPinWidgetSupported();
    if (supported != true) return false;
    await HomeWidget.requestPinWidget(androidName: _androidProviderName);
    return true;
  }
}
