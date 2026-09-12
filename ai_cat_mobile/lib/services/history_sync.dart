import '../models/chat_entry.dart';

/// Bilgisayarin (main.py - ChatHistoryManager) "time" alaniyla AYNI
/// bicimde (yyyy-MM-dd HH:mm, sifir dolgulu, saniyesiz) formatlar. Iki
/// yonlu senkronizasyonda (bkz. ChatSheet._syncWithDesktop) dedup
/// anahtarinin her iki tarafta da tutarli olmasi icin kritik: bilgisayardan
/// cekilen bir kaydin zamani zaten bu bicimde gelir, bu yuzden
/// DateTime.tryParse(...) ile ayristirilip tekrar bu fonksiyondan
/// gecirildiginde BAYT BAYT AYNI dizeyi verir - boylece bilgisayara geri
/// gonderilen bir kayit, bilgisayarin kendi kayitlariyla dogru eslesir ve
/// yinelenmez.
String formatDesktopTime(DateTime time) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${time.year.toString().padLeft(4, '0')}-${two(time.month)}-'
      '${two(time.day)} ${two(time.hour)}:${two(time.minute)}';
}

/// Bir sohbet kaydi icin (zaman, soru, cevap) uclusune dayanan dedup
/// anahtari - iki yonlu senkronizasyonda hem telefondaki hem
/// bilgisayardan gelen kayitlari karsilastirmak icin kullanilir.
String historySyncKey({
  required DateTime time,
  required String question,
  required String answer,
}) => '${formatDesktopTime(time)}|$question|$answer';

/// [entries] listesini (verildigi sirayla) okunabilir duz metne cevirir -
/// masaustu uygulamasindaki format_history_entries() ile ayni bicimi
/// kullanir, boylece iki taraftan disa aktarilan dosyalar tutarli gorunur.
String formatHistoryEntriesText(List<ChatEntry> entries) {
  final lines = <String>[];
  for (final entry in entries) {
    final marker = entry.isError ? '⚠' : '\u{1F431}';
    lines.add('[${formatDesktopTime(entry.time)}]');
    lines.add('Sen: ${entry.question}');
    lines.add('$marker ${entry.answer}');
    lines.add('');
  }
  return lines.join('\n');
}
