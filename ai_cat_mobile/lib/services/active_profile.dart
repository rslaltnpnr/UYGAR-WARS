import '../models/remote_profile.dart';

/// [profiles] icindeki, [activeId]'ye eslesen profili dondurur; eslesme
/// yoksa (orn. eslesik bilgisayar silinmis) ilk profile duser; liste
/// bomsa null doner. RemoteControlSheet._activeProfile ile ayni kural -
/// ekran izleme overlay'i (ayri bir isolate'ta calisir, widget state'ine
/// erisemez) kendi SharedPreferences okumasindan bu fonksiyonla aktif
/// profili cozumler.
RemoteProfile? resolveActiveProfile(
  List<RemoteProfile> profiles,
  String? activeId,
) {
  if (profiles.isEmpty) return null;
  return profiles.firstWhere(
    (p) => p.id == activeId,
    orElse: () => profiles.first,
  );
}
