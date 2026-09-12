import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'settings_service.dart';

const autoBackupPrefix = 'otomatik-yedek-';
const autoBackupIntervalDays = 1;
const autoBackupMaxCount = 7;

/// [lastBackupIso] (SettingsService.autoBackupLast) bos/gecersizse hemen
/// true doner (hic otomatik yedek alinmamis demektir). [now] - [last]
/// farki [intervalDays] gun ya da daha fazlaysa true doner. Masaustu
/// suruumundeki should_run_auto_backup() ile ayni mantik.
bool shouldRunAutoBackup(
  String? lastBackupIso,
  DateTime now, {
  int intervalDays = autoBackupIntervalDays,
}) {
  if (lastBackupIso == null || lastBackupIso.isEmpty) return true;
  final last = DateTime.tryParse(lastBackupIso);
  if (last == null) return true;
  return now.difference(last) >= Duration(days: intervalDays);
}

/// [filenames] icinden (yalnizca autoBackupPrefix ile baslayanlar dikkate
/// alinir; isme gore siralanir, bu da zaman damgasi sirasi demektir) en
/// eski olanlarin adlarini, en fazla [keepCount] tanesi kalacak sekilde
/// dondurur - gercek dosya G/C'sinden (_pruneOldBackups) ayri, saf bir
/// fonksiyon oldugu icin dogrudan test edilebilir.
List<String> autoBackupFilesToDelete(
  List<String> filenames, {
  int keepCount = autoBackupMaxCount,
}) {
  final matching = filenames.where((f) => f.startsWith(autoBackupPrefix)).toList()
    ..sort();
  if (matching.length <= keepCount) return [];
  return matching.sublist(0, matching.length - keepCount);
}

/// Ayarlari, uzaktan kumanda profillerini ve sohbet gecmisini tek bir JSON
/// dosyasina yedekler / geri yukler. Butun SharedPreferences anahtarlarinin
/// ham bir anlik goruntusunu alir - masaustu suruumundeki "Yedek Al" ile
/// ayni felsefe (her sey dahil, API anahtari ve PIN'ler dahil).
///
/// Disari aktarma icin sistem paylasim sayfasini (share_plus) kullanir -
/// kullanici dosyayi Dosyalar/Drive/e-posta vb. herhangi bir yere
/// kaydedebilir. Ice aktarma icin ozel bir dosya secici eklemek yerine
/// mevcut "Paylas" (receive_sharing_intent) entegrasyonu yeniden
/// kullanilir: kullanici yedek dosyasini bir dosya yoneticisinden bu
/// uygulamaya "Paylas" ile gonderir.
class BackupService {
  static const backupFileName = 'ai-kedi-asistani-yedek.json';

  Future<void> shareBackup() async {
    final prefs = await SharedPreferences.getInstance();
    final snapshot = <String, dynamic>{};
    for (final key in prefs.getKeys()) {
      snapshot[key] = prefs.get(key);
    }
    final backup = {
      'backup_version': 1,
      'preferences': snapshot,
    };
    final jsonStr = const JsonEncoder.withIndent('  ').convert(backup);

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$backupFileName');
    await file.writeAsString(jsonStr);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        text: 'AI Kedi Asistanı yedeği - API anahtarınızı ve PIN\'lerinizi '
            'içerir, güvenli saklayın.',
      ),
    );
  }

  /// [settings.autoBackupEnabled] kapaliysa ya da son yedekten bu yana
  /// yeterli sure gecmediyse (bkz. shouldRunAutoBackup) sessizce hicbir
  /// sey yapmaz. Aksi halde ayni "tum SharedPreferences'i dump et"
  /// mantigiyla ama share sayfasini acmadan, uygulamanin kendi belge
  /// klasorundeki backups/ altina yazar ve en fazla [autoBackupMaxCount]
  /// dosya tutar (daha eskileri siler). Hata durumunda (izin, disk vb.)
  /// sessizce basarisiz olur - bu arka planda, kullaniciyi rahatsiz
  /// etmeden calisan bir kolayliktir.
  Future<void> maybeAutoBackup(SettingsService settings) async {
    if (!settings.autoBackupEnabled) return;
    final now = DateTime.now();
    if (!shouldRunAutoBackup(settings.autoBackupLast, now)) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final snapshot = <String, dynamic>{};
      for (final key in prefs.getKeys()) {
        snapshot[key] = prefs.get(key);
      }
      final backup = {'backup_version': 1, 'preferences': snapshot};
      final jsonStr = const JsonEncoder.withIndent('  ').convert(backup);

      final docsDir = await getApplicationDocumentsDirectory();
      final backupsDir = Directory('${docsDir.path}/backups');
      await backupsDir.create(recursive: true);
      final file = File(
        '${backupsDir.path}/$autoBackupPrefix${_timestamp(now)}.json',
      );
      await file.writeAsString(jsonStr);
      await _pruneOldBackups(backupsDir);

      settings.autoBackupLast = now.toIso8601String();
    } catch (_) {
      // sessizce basarisiz ol
    }
  }

  Future<void> _pruneOldBackups(Directory backupsDir) async {
    final entries = backupsDir.listSync().whereType<File>().toList();
    final nameToFile = {
      for (final f in entries) f.path.split(Platform.pathSeparator).last: f,
    };
    final toDelete = autoBackupFilesToDelete(nameToFile.keys.toList());
    for (final name in toDelete) {
      try {
        await nameToFile[name]!.delete();
      } catch (_) {}
    }
  }

  String _timestamp(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year.toString().padLeft(4, '0')}-${two(t.month)}-'
        '${two(t.day)}-${two(t.hour)}${two(t.minute)}${two(t.second)}';
  }

  /// [jsonContent] gecerli bir yedek degilse [FormatException] firlatir.
  /// Basariyla geri yuklenen tercih (key) sayisini dondurur.
  Future<int> importBackup(String jsonContent) async {
    final dynamic data;
    try {
      data = jsonDecode(jsonContent);
    } on FormatException {
      throw const FormatException('Geçersiz yedek dosyası (JSON okunamadı).');
    }
    if (data is! Map || data['preferences'] is! Map) {
      throw const FormatException('Geçersiz yedek dosyası.');
    }

    final prefs = await SharedPreferences.getInstance();
    final snapshot = Map<String, dynamic>.from(data['preferences'] as Map);
    var count = 0;
    for (final entry in snapshot.entries) {
      final value = entry.value;
      bool ok;
      if (value is String) {
        ok = await prefs.setString(entry.key, value);
      } else if (value is bool) {
        ok = await prefs.setBool(entry.key, value);
      } else if (value is int) {
        ok = await prefs.setInt(entry.key, value);
      } else if (value is double) {
        ok = await prefs.setDouble(entry.key, value);
      } else if (value is List) {
        ok = await prefs.setStringList(
          entry.key,
          value.map((e) => e.toString()).toList(),
        );
      } else {
        continue;
      }
      if (ok) count++;
    }
    return count;
  }
}
