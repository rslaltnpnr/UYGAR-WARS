import 'package:flutter_overlay_window/flutter_overlay_window.dart';

/// "Ekranda Gez" kayan balonunun (bkz. lib/overlay/screen_watch_overlay_app.dart)
/// boyut hesaplari - saf fonksiyonlar, cihaz piksel oranindan/ekran
/// yuksekliginden bagimsiz olarak test edilebilir.
///
/// ONEMLI: flutter_overlay_window 0.5.0'da showOverlay ile resizeOverlay
/// TUTARSIZ birim bekler - showOverlay verilen height/width'i oldugu gibi
/// HAM PIKSEL olarak kullanirken (bkz. FlutterOverlayWindowPlugin.java,
/// WindowSetup.width/height dogrudan LayoutParams'a geciyor), resizeOverlay
/// AYNI degerleri DP sanip cihaz yogunlugu ile TEKRAR carpiyor (bkz.
/// OverlayService.resizeOverlay -> dpToPx). Bu yuzden showOverlay icin
/// [bubbleDiameterPx] (piksel), resizeOverlay icin [bubbleDiameterDp]/
/// [panelHeightDp] (dp) kullanilmali - ikisini karistirmak (once yasandigi
/// gibi) panelin/balonun yogunluk kati kadar yanlis boyutlanmasina yol acar.
class ScreenWatchOverlaySizes {
  /// Balonun/panelin dp cinsinden capi - resizeOverlay() ile balona
  /// donulurken kullanilir (bkz. yukaridaki birim notu).
  static const int bubbleDiameterDp = 56;

  static const double _panelHeightFraction = 0.55;
  static const int _panelMinHeightDp = 320;

  /// Ilk balonu olustururken showOverlay() icin HAM PIKSEL cap - 56dp,
  /// standart bir dokunma hedefi icin yeterince buyuk ama ekranin cogunu
  /// kapatmayacak kadar kucuk.
  static int bubbleDiameterPx(double devicePixelRatio) =>
      (bubbleDiameterDp * devicePixelRatio).round();

  /// Panele genislerken resizeOverlay() icin DP yukseklik. [screenHeightDp]
  /// GERCEK ekranin mantiksal yuksekligi olmali (bkz.
  /// View.of(context).display) - balonun o anki pencere boyutundan
  /// (MediaQuery, o an sadece kucuk balon kadardir) DEGIL. Ekranin
  /// tamamini kapatip altindaki uygulamayi tamamen gizlemesin diye 0.55
  /// ile sinirlanir, en az 320dp.
  static int panelHeightDp(double screenHeightDp) {
    final desired = screenHeightDp * _panelHeightFraction;
    final minHeight = _panelMinHeightDp.toDouble();
    return (desired < minHeight ? minHeight : desired).round();
  }
}

/// [FlutterOverlayWindow] etrafinda ince bir sarmalayici - overlay
/// yasam donguyusunu (izin, goster/kapat, boyutlandir) tek bir yerden
/// yonetir, boylece hem ayarlar penceresi hem main.dart'taki otomatik
/// yeniden-gosterme ayni kodu kullanir.
class ScreenWatchOverlayService {
  Future<bool> isPermissionGranted() =>
      FlutterOverlayWindow.isPermissionGranted();

  Future<bool> requestPermission() async {
    final granted = await FlutterOverlayWindow.requestPermission();
    return granted ?? false;
  }

  Future<bool> isActive() => FlutterOverlayWindow.isActive();

  Future<void> showBubble({
    required double devicePixelRatio,
  }) async {
    final size = ScreenWatchOverlaySizes.bubbleDiameterPx(devicePixelRatio);
    await FlutterOverlayWindow.showOverlay(
      height: size,
      width: size,
      enableDrag: true,
      flag: OverlayFlag.defaultFlag,
      visibility: NotificationVisibility.visibilitySecret,
      positionGravity: PositionGravity.auto,
      overlayTitle: 'Ekranda Gez',
      overlayContent: 'Bilgisayar ekranını izlemek için dokunun.',
    );
  }

  Future<void> close() => FlutterOverlayWindow.closeOverlay();
}
