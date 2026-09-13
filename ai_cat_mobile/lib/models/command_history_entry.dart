/// Telefondan bilgisayara gonderilen bir uzaktan komutun kalici kaydi
/// (bkz. CommandHistoryService) - "Bilgisayarda Ac", medya kontrolu,
/// guc eylemi, ekran goruntusu istegi ya da pano gonderimi gibi.
/// [profileName] hangi eslesik bilgisayara gonderildigini gosterir (birden
/// fazla profil kullaniliyorsa ayirt etmek icin).
class CommandHistoryEntry {
  final DateTime time;
  final String action;
  final String detail;
  final String profileName;

  const CommandHistoryEntry({
    required this.time,
    required this.action,
    required this.detail,
    required this.profileName,
  });

  Map<String, dynamic> toJson() => {
        'time': time.toIso8601String(),
        'action': action,
        'detail': detail,
        'profile_name': profileName,
      };

  factory CommandHistoryEntry.fromJson(Map<String, dynamic> json) =>
      CommandHistoryEntry(
        time:
            DateTime.tryParse(json['time'] as String? ?? '') ?? DateTime.now(),
        action: json['action'] as String? ?? '',
        detail: json['detail'] as String? ?? '',
        profileName: json['profile_name'] as String? ?? '',
      );
}
