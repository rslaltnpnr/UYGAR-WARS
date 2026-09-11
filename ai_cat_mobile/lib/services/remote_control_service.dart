import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Bilgisayardaki ai_desktop_assistant uygulamasina yerel ag uzerinden
/// gonderilen bir istegin basarisiz olma nedenini kullanici dostu bir
/// mesajla tasir.
class RemoteControlException implements Exception {
  final String message;

  RemoteControlException(this.message);

  @override
  String toString() => message;
}

/// Bir uzaktan komut isteginin basarili sonucu. `fingerprint`, sunucunun
/// TLS sertifikasinin bu istekte gorulen SHA-256 parmak izidir - cagiran
/// taraf bunu (ilk baglantida guven / TOFU) kaydedip sonraki isteklerde
/// tekrar gonderir.
class RemoteControlResult {
  final String fingerprint;

  const RemoteControlResult(this.fingerprint);
}

/// Bilgisayardaki kedi uygulamasinin sag tik menusunde acilan yerel HTTPS
/// sunucusuna (bkz. ai_desktop_assistant/main.py - RemoteCommandServer)
/// "su baglantiyi ac" komutu gonderir. Ikisi de ayni Wi-Fi agina bagli
/// olmalidir; kimlik dogrulama bir PIN ile yapilir.
///
/// Sunucu kendinden imzali bir TLS sertifikasi kullandigi icin isletim
/// sisteminin guvenilir sertifika zincirinde bulunmaz. Bunun yerine SSH
/// host key'lerine benzer bir "ilk baglantida guven" (TOFU) modeli
/// uygulanir: ilk baglantida sertifikanin SHA-256 parmak izi kaydedilir
/// (kullanicinin bilgisayardaki "Uzaktan Kumanda Bilgisi" penceresinden
/// gorup dogrulayabilecegi degerle ayni olmalidir); sonraki baglantilarda
/// parmak izi degismisse istek reddedilir (olasi araya girme/MITM saldirisi).
class RemoteControlService {
  Future<RemoteControlResult> openUrl({
    required String ip,
    required int port,
    required String pin,
    required String url,
    required String pinnedFingerprint,
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
      uri = Uri.parse('https://${ip.trim()}:$port/open');
    } catch (_) {
      throw RemoteControlException('IP adresi veya port gecersiz.');
    }

    String? observedFingerprint;
    var fingerprintMismatch = false;

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);
    client.badCertificateCallback = (cert, host, certPort) {
      final fingerprint = sha256.convert(cert.der).toString();
      observedFingerprint = fingerprint;
      if (pinnedFingerprint.isEmpty || fingerprint == pinnedFingerprint) {
        return true;
      }
      fingerprintMismatch = true;
      return false;
    };

    try {
      final body = utf8.encode(jsonEncode({'pin': pin, 'url': url.trim()}));
      final request = await client.postUrl(uri).timeout(
            const Duration(seconds: 5),
          );
      request.headers.set('Content-Type', 'application/json');
      request.headers.set('Content-Length', body.length.toString());
      request.add(body);
      final response = await request.close().timeout(
            const Duration(seconds: 5),
          );
      final responseBody = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 401) {
        throw RemoteControlException('PIN yanlis.');
      }
      if (response.statusCode == 429) {
        throw RemoteControlException(
          '${_serverErrorMessage(responseBody) ?? 'Cok fazla yanlis deneme yapildi'}. '
          'Biraz bekleyip tekrar dene.',
        );
      }
      if (response.statusCode != 200) {
        final detail = _serverErrorMessage(responseBody);
        throw RemoteControlException(
          detail != null
              ? 'Bilgisayar istegi reddetti: $detail'
              : 'Bilgisayar istegi reddetti (kod ${response.statusCode}).',
        );
      }

      return RemoteControlResult(observedFingerprint ?? pinnedFingerprint);
    } on RemoteControlException {
      rethrow;
    } catch (_) {
      if (fingerprintMismatch) {
        throw RemoteControlException(
          'DIKKAT: Bilgisayarin guvenlik sertifikasi kayitli olandan '
          'farkli! Bu bir araya girme (MITM) saldirisi belirtisi olabilir '
          '- ya da bilgisayar uygulamasi yeniden kuruldu. Emin degilseniz '
          'baglanmayin; eminseniz eslestirmeyi sifirlayip tekrar deneyin.',
        );
      }
      throw RemoteControlException(
        'Bilgisayara ulasilamadi. Ayni Wi-Fi agina bagli oldugunuzdan ve '
        'IP/portun dogru oldugundan emin olun.',
      );
    } finally {
      client.close(force: true);
    }
  }

  String? _serverErrorMessage(String body) {
    try {
      final data = jsonDecode(body);
      if (data is Map && data['error'] is String) {
        return data['error'] as String;
      }
    } catch (_) {
      // govde JSON degilse yok say, jenerik mesaj kullanilir
    }
    return null;
  }
}
