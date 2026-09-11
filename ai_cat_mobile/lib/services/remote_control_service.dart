import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

/// [fetchScreenshot] sonucu: parmak izinin yani sira indirilen goruntu
/// (JPEG) baytlarini da tasir.
class ScreenshotResult {
  final String fingerprint;
  final Uint8List imageBytes;

  const ScreenshotResult(this.fingerprint, this.imageBytes);
}

class _RawResponse {
  final int statusCode;
  final String body;
  final String fingerprint;

  const _RawResponse(this.statusCode, this.body, this.fingerprint);
}

/// Bilgisayardaki kedi uygulamasinin sag tik menusunde acilan yerel HTTPS
/// sunucusuna (bkz. ai_desktop_assistant/main.py - RemoteCommandServer)
/// komut gonderir: /open (baglanti ac), /media (medya tuslari), /power
/// (kilit/uyku), /screenshot (ekran goruntusu). Ikisi de ayni Wi-Fi agina
/// bagli olmalidir; kimlik dogrulama bir PIN ile yapilir.
///
/// Sunucu kendinden imzali bir TLS sertifikasi kullandigi icin isletim
/// sisteminin guvenilir sertifika zincirinde bulunmaz. Bunun yerine SSH
/// host key'lerine benzer bir "ilk baglantida guven" (TOFU) modeli
/// uygulanir: ilk baglantida sertifikanin SHA-256 parmak izi kaydedilir
/// (kullanicinin bilgisayardaki "Uzaktan Kumanda Bilgisi" penceresinden
/// gorup dogrulayabilecegi degerle ayni olmalidir); sonraki baglantilarda
/// parmak izi degismisse istek reddedilir (olasi araya girme/MITM saldirisi).
class RemoteControlService {
  Future<_RawResponse> _post({
    required String ip,
    required int port,
    required String path,
    required Map<String, dynamic> body,
    required String pinnedFingerprint,
  }) async {
    final Uri uri;
    try {
      uri = Uri.parse('https://${ip.trim()}:$port$path');
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
      final encodedBody = utf8.encode(jsonEncode(body));
      final request = await client.postUrl(uri).timeout(
            const Duration(seconds: 5),
          );
      request.headers.set('Content-Type', 'application/json');
      request.headers.set('Content-Length', encodedBody.length.toString());
      request.add(encodedBody);
      final response = await request.close().timeout(
            const Duration(seconds: 8),
          );
      final responseBody = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 8));

      return _RawResponse(
        response.statusCode,
        responseBody,
        observedFingerprint ?? pinnedFingerprint,
      );
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

  void _throwForCommonErrors(_RawResponse response) {
    if (response.statusCode == 200) return;
    if (response.statusCode == 401) {
      throw RemoteControlException('PIN yanlis.');
    }
    if (response.statusCode == 429) {
      throw RemoteControlException(
        '${_serverErrorMessage(response.body) ?? 'Cok fazla yanlis deneme yapildi'}. '
        'Biraz bekleyip tekrar dene.',
      );
    }
    final detail = _serverErrorMessage(response.body);
    throw RemoteControlException(
      detail != null
          ? 'Bilgisayar istegi reddetti: $detail'
          : 'Bilgisayar istegi reddetti (kod ${response.statusCode}).',
    );
  }

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
    final response = await _post(
      ip: ip,
      port: port,
      path: '/open',
      body: {'pin': pin, 'url': url.trim()},
      pinnedFingerprint: pinnedFingerprint,
    );
    _throwForCommonErrors(response);
    return RemoteControlResult(response.fingerprint);
  }

  Future<RemoteControlResult> sendMedia({
    required String ip,
    required int port,
    required String pin,
    required String action,
    required String pinnedFingerprint,
  }) async {
    if (ip.trim().isEmpty) {
      throw RemoteControlException(
        'Once bilgisayarin IP adresini ve PIN kodunu gir.',
      );
    }
    final response = await _post(
      ip: ip,
      port: port,
      path: '/media',
      body: {'pin': pin, 'action': action},
      pinnedFingerprint: pinnedFingerprint,
    );
    _throwForCommonErrors(response);
    return RemoteControlResult(response.fingerprint);
  }

  Future<RemoteControlResult> sendPower({
    required String ip,
    required int port,
    required String pin,
    required String action,
    required String pinnedFingerprint,
  }) async {
    if (ip.trim().isEmpty) {
      throw RemoteControlException(
        'Once bilgisayarin IP adresini ve PIN kodunu gir.',
      );
    }
    final response = await _post(
      ip: ip,
      port: port,
      path: '/power',
      body: {'pin': pin, 'action': action},
      pinnedFingerprint: pinnedFingerprint,
    );
    _throwForCommonErrors(response);
    return RemoteControlResult(response.fingerprint);
  }

  Future<ScreenshotResult> fetchScreenshot({
    required String ip,
    required int port,
    required String pin,
    required String pinnedFingerprint,
  }) async {
    if (ip.trim().isEmpty) {
      throw RemoteControlException(
        'Once bilgisayarin IP adresini ve PIN kodunu gir.',
      );
    }
    final response = await _post(
      ip: ip,
      port: port,
      path: '/screenshot',
      body: {'pin': pin},
      pinnedFingerprint: pinnedFingerprint,
    );
    _throwForCommonErrors(response);
    try {
      final data = jsonDecode(response.body);
      final imageBytes = base64Decode(data['image_base64'] as String);
      return ScreenshotResult(response.fingerprint, imageBytes);
    } catch (_) {
      throw RemoteControlException('Ekran goruntusu okunamadi.');
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
