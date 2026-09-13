import 'package:flutter_overlay_window/flutter_overlay_window.dart';

/// "Ekranda Gez" kayan balonunun (bkz. lib/overlay/screen_watch_overlay_app.dart)
/// boyut hesaplari - saf fonksiyonlar, cihaz piksel oranindan/ekran
/// yuksekliginden bagimsiz olarak test edilebilir. showOverlay/resizeOverlay
/// piksel (dp degil) bekledigi icin devicePixelRatio ile carpma burada
/// yapilir.
class ScreenWatchOverlaySizes {
  /// Toplanmis haldeki balonun capi - 56dp, standart bir dokunma hedefi
  /// icin yeterince buyuk ama ekranin cogunu kapatmayacak kadar kucuk.
  static int bubbleDiameterPx(double devicePixelRatio) =>
      (56 * devicePixelRatio).round();

  /// Genisletilmis panelin yuksekligi - ekran yuksekliginin bir orani
  /// (ekranin tamamini kapatip altindaki uygulamayi tamamen gizlemesin
  /// diye 0.55 ile sinirlanir), en az 320dp.
  static int panelHeightPx(double devicePixelRatio, double screenHeightPx) {
    final desired = screenHeightPx * 0.55;
    final minHeight = 320 * devicePixelRatio;
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
