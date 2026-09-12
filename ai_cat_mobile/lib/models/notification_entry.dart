/// Kullaniciya gosterilmis (flutter_local_notifications araciligiyla) bir
/// bildirimin kalici kaydi - masaustu suruumundeki NotificationLog ile
/// ayni fikirde: uygulama yeniden acilsa da (ya da telefonun kendi
/// bildirim gecmisinden silinse de) burada kalir.
class NotificationEntry {
  final DateTime time;
  final String title;
  final String message;

  const NotificationEntry({
    required this.time,
    required this.title,
    required this.message,
  });

  Map<String, dynamic> toJson() => {
        'time': time.toIso8601String(),
        'title': title,
        'message': message,
      };

  factory NotificationEntry.fromJson(Map<String, dynamic> json) =>
      NotificationEntry(
        time:
            DateTime.tryParse(json['time'] as String? ?? '') ?? DateTime.now(),
        title: json['title'] as String? ?? '',
        message: json['message'] as String? ?? '',
      );
}
