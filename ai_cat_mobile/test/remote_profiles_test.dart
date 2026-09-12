import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_cat_mobile/models/remote_profile.dart';
import 'package:ai_cat_mobile/screens/home_screen.dart';
import 'package:ai_cat_mobile/services/settings_service.dart';
import 'package:ai_cat_mobile/theme/app_colors.dart';
import 'package:ai_cat_mobile/widgets/remote_control_sheet.dart';

void main() {
  group('SettingsService remote profiles', () {
    test('eski tek-bilgisayar alanlari ilk okumada tek profile gocturulur',
        () async {
      SharedPreferences.setMockInitialValues({
        'desktop_ip': '192.168.1.50',
        'desktop_port': 9999,
        'desktop_pin': '123123',
        'desktop_cert_fingerprint': 'AA:BB:CC',
      });
      final prefs = await SharedPreferences.getInstance();
      final settings = SettingsService(prefs);

      final profiles = settings.remoteProfiles;
      expect(profiles.length, 1);
      expect(profiles.first.ip, '192.168.1.50');
      expect(profiles.first.port, 9999);
      expect(profiles.first.pin, '123123');
      expect(profiles.first.certFingerprint, 'AA:BB:CC');
      expect(settings.activeProfileId, profiles.first.id);
    });

    test('profil listesi ekle/sil/guncelle ile kalici oluyor', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settings = SettingsService(prefs);

      expect(settings.remoteProfiles, isEmpty);

      const p1 = RemoteProfile(
        id: '1',
        name: 'Ev',
        ip: '10.0.0.5',
        port: 8765,
        pin: '111111',
        certFingerprint: '',
      );
      const p2 = RemoteProfile(
        id: '2',
        name: 'İş',
        ip: '10.0.0.6',
        port: 8765,
        pin: '222222',
        certFingerprint: '',
      );
      settings.remoteProfiles = [p1, p2];
      settings.activeProfileId = '2';

      // Yeni bir SettingsService orneginin (yeniden acilan uygulama gibi)
      // ayni veriyi gormesi gerekir.
      final reloaded = SettingsService(prefs);
      expect(reloaded.remoteProfiles.map((p) => p.name), ['Ev', 'İş']);
      expect(reloaded.activeProfileId, '2');
    });
  });

  group('RemoteControlSheet profile UI', () {
    testWidgets('bos durumda ekleme istemi gosterilir, profil eklenebilir',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settings = SettingsService(prefs);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [AppColors.dark]),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => RemoteControlSheet(settings: settings),
                ),
                child: const Text('Aç'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Aç'));
      // DraggableScrollableSheet ic gozlemcileri surekli rebuild
      // tetikleyebildigi icin pumpAndSettle yerine sabit sayida pump.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Henüz bir bilgisayar eklenmedi.'), findsOneWidget);

      // Yeni bilgisayar ekle.
      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Yeni Bilgisayar Ekle'), findsOneWidget);
      await tester.tap(find.text('Ekle'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Artik bos-durum mesaji yerine IP/Port/PIN alanlari gorunmeli.
      expect(find.text('Henüz bir bilgisayar eklenmedi.'), findsNothing);
      expect(find.text('Bilgisayar IP (örn. 192.168.1.20)'), findsOneWidget);

      // Profil kaydedilmis olmali.
      expect(settings.remoteProfiles.length, 1);
      expect(settings.activeProfileId, settings.remoteProfiles.first.id);
    });
  });

  group('Ana ekran profil gostergesi', () {
    testWidgets(
      'gostergeye dokunup menuden secince aktif profil degisir',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final settings = SettingsService(prefs);
        // ip/pin kasitli olarak bos - _pollForDesktopAlerts bu durumda
        // hicbir ag istegi yapmadan erken doner, bu yuzden test gercek
        // bir baglanti denemesi beklemeden hizli ve guvenilir kalir.
        settings.remoteProfiles = const [
          RemoteProfile(
            id: '1',
            name: 'Ev',
            ip: '',
            port: 8765,
            pin: '',
            certFingerprint: '',
          ),
          RemoteProfile(
            id: '2',
            name: 'İş',
            ip: '',
            port: 8765,
            pin: '',
            certFingerprint: '',
          ),
        ];
        settings.activeProfileId = '1';

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(extensions: const [AppColors.dark]),
            home: HomeScreen(onThemeModeChanged: (_) {}),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('Ev'), findsOneWidget);

        await tester.tap(find.text('Ev'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('İş'), findsWidgets);
        await tester.tap(find.text('İş').last);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        final reloaded = SettingsService(prefs);
        expect(reloaded.activeProfileId, '2');
      },
    );
  });

  group('Çoklu-cihaz yayın modu', () {
    testWidgets(
      '2+ profille "Tüm Bilgisayarlara Gönder" butonu görünür ve '
      'sonucu özetler',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final settings = SettingsService(prefs);
        // ip/pin kasitli olarak bos - _sendToAllProfiles her profil icin
        // gercek bir ag istegi denemeden "Once bilgisayarin IP adresini ve
        // PIN kodunu gir." hatasiyla hemen basarisiz olur, bu yuzden test
        // gercek baglanti beklemeden hizli ve guvenilir kalir.
        settings.remoteProfiles = const [
          RemoteProfile(
            id: '1',
            name: 'Ev',
            ip: '',
            port: 8765,
            pin: '',
            certFingerprint: '',
          ),
          RemoteProfile(
            id: '2',
            name: 'İş',
            ip: '',
            port: 8765,
            pin: '',
            certFingerprint: '',
          ),
        ];
        settings.activeProfileId = '1';

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(extensions: const [AppColors.dark]),
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => RemoteControlSheet(settings: settings),
                  ),
                  child: const Text('Aç'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Aç'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('Tüm Bilgisayarlara Gönder (2)'), findsOneWidget);

        await tester.enterText(
          find.widgetWithText(TextField, 'Açılacak bağlantı (https://...)'),
          'https://example.com',
        );
        await tester.pump();

        final sendToAllButton =
            find.text('Tüm Bilgisayarlara Gönder (2)');
        await tester.ensureVisible(sendToAllButton);
        await tester.pump();
        await tester.tap(sendToAllButton);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('2 bilgisayardan: 2 başarısız.'), findsOneWidget);
      },
    );
  });
}
