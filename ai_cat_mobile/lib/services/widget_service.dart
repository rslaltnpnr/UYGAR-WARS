import 'package:home_widget/home_widget.dart';

/// Ana ekran widget'indaki iki hizli erisim dugmesinin (bkz.
/// `CatWidgetProvider.kt`) acabilecegi ekranlar.
enum WidgetLaunchAction { chat, remoteControl }

/// Widget dugmelerine basildiginda uygulamayi acan `catwidget://open?screen=...`
/// URI'lerini cozumler; widget disindan (normal simge) acilislarda [uri] null
/// olur.
class WidgetService {
  static const _androidProviderName = 'CatWidgetProvider';

  static WidgetLaunchAction? actionFromUri(Uri? uri) {
    if (uri == null || uri.scheme != 'catwidget') return null;
    switch (uri.queryParameters['screen']) {
      case 'chat':
        return WidgetLaunchAction.chat;
      case 'remote':
        return WidgetLaunchAction.remoteControl;
      default:
        return null;
    }
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
