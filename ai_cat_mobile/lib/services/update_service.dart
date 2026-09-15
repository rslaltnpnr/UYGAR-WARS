import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// GitHub Releases'ten daha yeni bir surum bulunduysa tasidigi bilgi.
class MobileUpdateInfo {
  final String tag;
  final String htmlUrl;

  /// APK dosyasinin dogrudan indirme linki - release'te bu isimde bir
  /// dosya yoksa null (kullanici sadece release sayfasina yonlendirilir).
  final String? apkDownloadUrl;

  const MobileUpdateInfo({
    required this.tag,
    required this.htmlUrl,
    this.apkDownloadUrl,
  });
}

/// GitHub Releases API'sinden en son surumu sorar. Henuz hic release
/// yayinlanmamissa (404) ya da ag erisimi yoksa null doner - bu, mevcut
/// kurulumu bozmayan, tamamen opsiyonel bir kontrol (masaustu suruumundeki
/// UpdateCheckWorker ile ayni mantik).
class UpdateService {
  static const _repo = 'rslaltnpnr/ai-cat-assistant';
  static const _apkAssetName = 'ai-kedi-asistani.apk';
  static const _timeout = Duration(seconds: 5);

  Future<MobileUpdateInfo?> checkForUpdate() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version;

    // /releases/latest bu depodaki EN SON yayinlanan release'i doner - ama
    // bu depoda masaustu ve mobil uygulamalar release'leri paylasir, bu
    // yuzden "en son" bazen diger uygulamaninki olabilir. Bunun yerine
    // listeyi (en yeniden eskiye) tarayip icinde bizim APK'mizin oldugu
    // ilk release'i buluyoruz.
    final uri = Uri.parse(
      'https://api.github.com/repos/$_repo/releases?per_page=10',
    );
    final http.Response response;
    try {
      response = await http
          .get(uri, headers: const {'Accept': 'application/vnd.github+json'})
          .timeout(_timeout);
    } catch (_) {
      return null; // ag erisimi yok - sessizce yok say
    }
    if (response.statusCode == 404) return null; // henuz release yok
    if (response.statusCode != 200) return null;

    final List<dynamic> releases;
    try {
      releases = jsonDecode(response.body) as List<dynamic>;
    } catch (_) {
      return null;
    }

    final data = findReleaseWithAsset(releases, _apkAssetName);
    if (data == null) return null; // bu uygulamaya ait release yok

    final tag = (data['tag_name'] as String? ?? '').trim();
    final htmlUrl = (data['html_url'] as String? ?? '').trim();
    if (tag.isEmpty || !isNewerVersion(tag, currentVersion)) return null;

    String? apkUrl;
    for (final asset in (data['assets'] as List? ?? const [])) {
      if (asset is Map && asset['name'] == _apkAssetName) {
        apkUrl = asset['browser_download_url'] as String?;
      }
    }
    return MobileUpdateInfo(tag: tag, htmlUrl: htmlUrl, apkDownloadUrl: apkUrl);
  }
}

/// [releases] listesinde (GitHub Releases API'sinin dondugu sirayla, en
/// yeniden eskiye) taslak/on-surum olmayan ve icinde [assetName] adinda bir
/// dosya olan ilk release'i doner - yoksa null. Bu depoda masaustu ve
/// mobil uygulamalarin release'leri ayni listede karistigi icin gerekli
/// (bkz. checkForUpdate).
Map<String, dynamic>? findReleaseWithAsset(
  List<dynamic> releases,
  String assetName,
) {
  for (final release in releases) {
    if (release is! Map) continue;
    final map = release.cast<String, dynamic>();
    if (map['draft'] == true || map['prerelease'] == true) continue;
    final assets = map['assets'] as List? ?? const [];
    final hasAsset = assets.any(
      (asset) => asset is Map && asset['name'] == assetName,
    );
    if (hasAsset) return map;
  }
  return null;
}

/// [remote] surumu [local] surumden daha yeniyse true doner. Onde "v"
/// harfi ve sayisal olmayan parcalar yok sayilir (orn. "v1.2.0" > "1.10").
/// Masaustu suruumundeki `is_newer_version`/`_parse_version` ile ayni
/// mantik (parity icin).
bool isNewerVersion(String remote, String local) {
  final r = _parseVersion(remote);
  final l = _parseVersion(local);
  final length = r.length > l.length ? r.length : l.length;
  for (var i = 0; i < length; i++) {
    final rv = i < r.length ? r[i] : 0;
    final lv = i < l.length ? l[i] : 0;
    if (rv != lv) return rv > lv;
  }
  return false;
}

List<int> _parseVersion(String v) {
  v = v.trim();
  if (v.toLowerCase().startsWith('v')) v = v.substring(1);
  return v.split('.').map((piece) {
    final digits = piece.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.isEmpty ? 0 : int.parse(digits);
  }).toList();
}
