/// Baglanti kurulamadigi icin bekletilen, "bilgisayarda ac" turunde bir
/// komut. Yalnizca /open (URL acma) kuyruklanir - medya/guc komutlari
/// dogasi geregi "simdi" anlamina gelir, dakikalar/saatler sonra baglanti
/// kurulunca gec gelen bir "kilitle" ya da "duraklat" komutu sasirtici
/// olur; bir baglanti ise gec de olsa acilmasi hala anlamlidir.
class QueuedCommand {
  final String profileId;
  final String url;
  final DateTime queuedAt;

  const QueuedCommand({
    required this.profileId,
    required this.url,
    required this.queuedAt,
  });

  Map<String, dynamic> toJson() => {
        'profile_id': profileId,
        'url': url,
        'queued_at': queuedAt.toIso8601String(),
      };

  factory QueuedCommand.fromJson(Map<String, dynamic> json) => QueuedCommand(
        profileId: json['profile_id'] as String? ?? '',
        url: json['url'] as String? ?? '',
        queuedAt:
            DateTime.tryParse(json['queued_at'] as String? ?? '') ??
                DateTime.now(),
      );
}
