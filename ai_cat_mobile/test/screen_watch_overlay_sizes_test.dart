import 'package:ai_cat_mobile/services/screen_watch_overlay_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ScreenWatchOverlaySizes', () {
    test('bubbleDiameterPx cihaz piksel oranina gore olceklenir', () {
      expect(ScreenWatchOverlaySizes.bubbleDiameterPx(1), 56);
      expect(ScreenWatchOverlaySizes.bubbleDiameterPx(2), 112);
      expect(ScreenWatchOverlaySizes.bubbleDiameterPx(2.5), 140);
    });

    test('panelHeightPx ekran yuksekliginin yuzde 55ini kullanir', () {
      // 2000px yukseklikte %55 = 1100, asgarin (320 * dpr) uzerinde.
      expect(ScreenWatchOverlaySizes.panelHeightPx(1, 2000), 1100);
    });

    test('panelHeightPx kucuk ekranlarda asgar yuksekligin altina inmez', () {
      // 400px yukseklikte %55 = 220, asgar (320 * 1) = 320'nin altinda
      // kaliyor, bu yuzden asgara yukselir.
      expect(ScreenWatchOverlaySizes.panelHeightPx(1, 400), 320);
    });

    test('panelHeightPx asgar hesabinda da dpr kullanir', () {
      // 400px yukseklikte %55 = 220, asgar (320 * 2) = 640'in altinda
      // kaliyor, bu yuzden asgara (640) yukselir.
      expect(ScreenWatchOverlaySizes.panelHeightPx(2, 400), 640);
    });
  });
}
