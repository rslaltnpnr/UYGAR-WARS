/// Masaüstü uygulamasının "Uzaktan Kumanda" penceresinde gösterdiği QR
/// kodun içeriği - bkz. Python tarafındaki build_pairing_uri(). Kamerayla
/// tarandıktan sonra IP/Port/PIN/sertifika parmak izi alanlarını elle
/// yazmadan doldurmak için kullanılır.
class PairingInfo {
  final String ip;
  final int port;
  final String pin;
  final String certFingerprint;

  const PairingInfo({
    required this.ip,
    required this.port,
    required this.pin,
    required this.certFingerprint,
  });
}

/// [raw]'ı ("aikedi://pair?ip=...&port=...&pin=...&fp=...") ayrıştırır.
/// Şema/host uymuyorsa ya da zorunlu alanlar (ip, port, pin) eksik veya
/// geçersizse null döner - fp (sertifika parmak izi) opsiyoneldir, boş
/// dize olarak kalır (ilk bağlantıda TOFU ile yine kaydedilir).
PairingInfo? parsePairingUri(String raw) {
  final Uri uri;
  try {
    uri = Uri.parse(raw);
  } catch (_) {
    return null;
  }
  if (uri.scheme != 'aikedi' || uri.host != 'pair') return null;

  final ip = uri.queryParameters['ip'];
  final portText = uri.queryParameters['port'];
  final pin = uri.queryParameters['pin'];
  if (ip == null || ip.isEmpty || portText == null || pin == null || pin.isEmpty) {
    return null;
  }
  final port = int.tryParse(portText);
  if (port == null) return null;

  return PairingInfo(
    ip: ip,
    port: port,
    pin: pin,
    certFingerprint: uri.queryParameters['fp'] ?? '',
  );
}
