/// Şifreli not defterindeki tek bir not. Kendisi hiçbir zaman düz metin
/// olarak diskte durmaz - tüm liste (bkz. SecureNotepadService) tek bir
/// şifreli blok olarak saklanır, bu sınıf yalnızca o blok çözüldükten
/// sonra bellekte var olur.
class SecureNote {
  final String id;
  final String title;
  final String body;
  final DateTime updatedAt;

  const SecureNote({
    required this.id,
    required this.title,
    required this.body,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'updated_at': updatedAt.toIso8601String(),
      };

  factory SecureNote.fromJson(Map<String, dynamic> json) => SecureNote(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
        updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ??
            DateTime.now(),
      );
}
