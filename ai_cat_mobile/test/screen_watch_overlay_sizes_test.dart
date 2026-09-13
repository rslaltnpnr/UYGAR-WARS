import 'package:ai_cat_mobile/services/screen_watch_overlay_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ScreenWatchOverlaySizes', () {
    test('bubbleDiameterPx cihaz piksel oranina gore olceklenir', () {
      expect(ScreenWatchOverlaySizes.bubbleDiameterPx(1), 56);
      expect(ScreenWatchOverlaySizes.bubbleDiameterPx(2), 112);
      expect(ScreenWatchOverlaySizes.bubbleDiameterPx(2.5), 140);
    });

    test('bubbleDiameterDp cihaz yogunlugundan bagimsizdir', () {
      // resizeOverlay() dp bekler (bkz. sinif dokumani) - cihaz piksel
      // oranindan etkilenmemeli.
      expect(ScreenWatchOverlaySizes.bubbleDiameterDp, 56);
    });

    test('panelHeightDp ekran yuksekliginin yuzde 55ini kullanir', () {
      // 2000dp yukseklikte %55 = 1100, asgarin (320dp) uzerinde.
      expect(ScreenWatchOverlaySizes.panelHeightDp(2000), 1100);
    });

    test('panelHeightDp kucuk ekranlarda asgar yuksekligin altina inmez', () {
      // 400dp yukseklikte %55 = 220, asgar olan 320dp'nin altinda
      // kaliyor, bu yuzden asgara (320) yukselir.
      expect(ScreenWatchOverlaySizes.panelHeightDp(400), 320);
    });

    test('panelHeightDp cihaz yogunlugundan bagimsizdir', () {
      // dp cinsinden calistigi icin (resizeOverlay() zaten kendi
      // icinde yogunlukla carpiyor - bkz. sinif dokumani) burada ikinci
      // bir yogunluk carpimi OLMAMALI.
      expect(ScreenWatchOverlaySizes.panelHeightDp(890), 490);
    });
  });
}
