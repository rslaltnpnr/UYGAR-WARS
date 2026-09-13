import 'dart:typed_data';

/// Bildirimlerde (hatirlatici + masaustu uyarilari) kullanilacak titresim
/// paterni - ayarlar penceresinden secilir, SettingsService.
/// notificationVibrationPattern'da saklanir. [pattern] null oldugunda
/// AndroidNotificationDetails sistemin varsayilan tek titresimini kullanir;
/// [off] disinda hepsinde [enableVibration] true'dur.
enum VibrationPatternOption {
  system('system'),
  short('short'),
  long('long'),
  doublePulse('double'),
  off('off');

  const VibrationPatternOption(this.value);

  final String value;

  static VibrationPatternOption fromValue(String? value) {
    for (final option in VibrationPatternOption.values) {
      if (option.value == value) return option;
    }
    return VibrationPatternOption.system;
  }

  String get label => switch (this) {
        VibrationPatternOption.system => 'Sistem Varsayılanı',
        VibrationPatternOption.short => 'Kısa',
        VibrationPatternOption.long => 'Uzun',
        VibrationPatternOption.doublePulse => 'Çift Vuruş',
        VibrationPatternOption.off => 'Kapalı',
      };

  bool get enableVibration => this != VibrationPatternOption.off;

  /// Milisaniye cinsinden [bekle, titre, bekle, titre, ...] dizisi -
  /// Android'in Vibrator API'siyle ayni bicim. null ise ozel bir paternin
  /// olmadigini (sistem varsayilanini kullan) belirtir.
  Int64List? get pattern => switch (this) {
        VibrationPatternOption.short => Int64List.fromList([0, 150]),
        VibrationPatternOption.long => Int64List.fromList([0, 800]),
        VibrationPatternOption.doublePulse =>
          Int64List.fromList([0, 150, 100, 150]),
        VibrationPatternOption.system => null,
        VibrationPatternOption.off => null,
      };
}
