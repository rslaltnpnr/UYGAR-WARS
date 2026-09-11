import 'dart:convert';

import 'package:http/http.dart' as http;

/// Bilgisayardaki ai_desktop_assistant uygulamasina yerel ag uzerinden
/// gonderilen bir istegin basarisiz olma nedenini kullanici dostu bir
/// mesajla tasir.
class RemoteControlException implements Exception {
  final String message;

  RemoteControlException(this.message);

  @override
  String toString() => message;
}

/// Bilgisayardaki kedi uygulamasinin sag tik menusunde acilan yerel
/// HTTP sunucusuna (bkz. ai_desktop_assistant/main.py - RemoteCommandServer)
/// "su baglantiyi ac" komutu gonderir. Ikisi de ayni Wi-Fi agina bagli
/// olmalidir; kimlik dogrulama basit bir PIN ile yapilir.
class RemoteControlService {
  Future<void> openUrl({
    required String ip,
    required int port,
    required String pin,
    required String url,
  }) async {
    if (ip.trim().isEmpty) {
      throw RemoteControlException(
        'Once bilgisayarin IP adresini ve PIN kodunu gir.',
      );
    }
    if (url.trim().isEmpty) {
      throw RemoteControlException('Acilacak bir baglanti yaz.');
    }

    final Uri uri;
    try {
      uri = Uri.parse('http://${ip.trim()}:$port/open');
    } catch (_) {
      throw RemoteControlException('IP adresi veya port gecersiz.');
    }

    http.Response response;
    try {
      response = await http
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'pin': pin, 'url': url.trim()}),
          )
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      throw RemoteControlException(
        'Bilgisayara ulasilamadi. Ayni Wi-Fi agina bagli oldugunuzdan ve '
        'IP/portun dogru oldugundan emin olun.',
      );
    }

    if (response.statusCode == 401) {
      throw RemoteControlException('PIN yanlis.');
    }
    if (response.statusCode != 200) {
      throw RemoteControlException(
        'Bilgisayar istegi reddetti (kod ${response.statusCode}).',
      );
    }
  }
}
