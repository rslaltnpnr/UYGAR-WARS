import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
