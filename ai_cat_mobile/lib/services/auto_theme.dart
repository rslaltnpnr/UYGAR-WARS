import 'package:flutter/material.dart' show ThemeMode;

/// "SS:DD" bicimindeki bir saat dizesini dogrular ve normallestirir
/// ("9:5" -> "09:05"); gecersizse null doner. Masaustu suruumundeki
/// parse_hh_mm ile ayni kural.
String? parseHhMm(String text) {
  final parts = text.trim().split(':');
  if (parts.length != 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return null;
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
  return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

/// [now] icin ThemeMode.light mi dark mi kullanilmasi gerektigini dondurur
/// - [dayStart]'ta acik temaya, [nightStart]'ta koyu temaya gecilir.
/// Masaustu suruumundeki resolve_auto_theme_mode ile ayni mantik (gunduz
/// araliginin gece yarisini gecmesi durumu dahil); gecersiz saatler
/// varsayilana (07:00/19:00) duser.
ThemeMode resolveAutoThemeMode(
  DateTime now, {
  String dayStart = '07:00',
  String nightStart = '19:00',
}) {
  final normalizedDayStart = parseHhMm(dayStart) ?? '07:00';
  final normalizedNightStart = parseHhMm(nightStart) ?? '19:00';
  final current =
      '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

  bool inDayRange() {
    if (normalizedDayStart.compareTo(normalizedNightStart) <= 0) {
      return current.compareTo(normalizedDayStart) >= 0 &&
          current.compareTo(normalizedNightStart) < 0;
    }
    return current.compareTo(normalizedDayStart) >= 0 ||
        current.compareTo(normalizedNightStart) < 0;
  }

  return inDayRange() ? ThemeMode.light : ThemeMode.dark;
}
