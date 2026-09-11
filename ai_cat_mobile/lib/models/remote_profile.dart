/// Eslestirilmis bir bilgisayarin baglanti bilgileri (birden fazla
/// bilgisayarla - ev/is gibi - eslesip aralarinda gecis yapabilmek icin).
class RemoteProfile {
  final String id;
  final String name;
  final String ip;
  final int port;
  final String pin;
  final String certFingerprint;

  const RemoteProfile({
    required this.id,
    required this.name,
    required this.ip,
    required this.port,
    required this.pin,
    required this.certFingerprint,
  });

  RemoteProfile copyWith({
    String? name,
    String? ip,
    int? port,
    String? pin,
    String? certFingerprint,
  }) {
    return RemoteProfile(
      id: id,
      name: name ?? this.name,
      ip: ip ?? this.ip,
      port: port ?? this.port,
      pin: pin ?? this.pin,
      certFingerprint: certFingerprint ?? this.certFingerprint,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'ip': ip,
        'port': port,
        'pin': pin,
        'certFingerprint': certFingerprint,
      };

  factory RemoteProfile.fromJson(Map<String, dynamic> json) => RemoteProfile(
        id: json['id'] as String,
        name: json['name'] as String,
        ip: json['ip'] as String? ?? '',
        port: json['port'] as int? ?? 8765,
        pin: json['pin'] as String? ?? '',
        certFingerprint: json['certFingerprint'] as String? ?? '',
      );
}
