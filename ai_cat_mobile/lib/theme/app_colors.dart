import 'package:flutter/material.dart';

/// Uygulamanin acik/koyu tema arasinda degisen, Material'in standart
/// ColorScheme'inin karsilamadigi semantik renkleri (panel arka plani,
/// yari saydam panel, farkli tonlarda metin vb.) tasiyan ThemeExtension.
/// Widget'lar `Theme.of(context).extension<AppColors>()!` ile erisir.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  final Color scaffoldBackground;
  final Color panel;
  final Color panelTranslucent;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color divider;
  final Color accent;
  final Color error;
  final Color success;

  const AppColors({
    required this.scaffoldBackground,
    required this.panel,
    required this.panelTranslucent,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.divider,
    required this.accent,
    required this.error,
    required this.success,
  });

  static const dark = AppColors(
    scaffoldBackground: Color(0xFF14141C),
    panel: Color(0xFF1E1E28),
    panelTranslucent: Color(0xE61E1E28),
    textPrimary: Colors.white,
    textSecondary: Colors.white70,
    textMuted: Colors.white54,
    divider: Colors.white24,
    accent: Color(0xFF5AAAFF),
    error: Color(0xFFFF8080),
    success: Color(0xFF8CFF8C),
  );

  static const light = AppColors(
    scaffoldBackground: Color(0xFFF2F2F7),
    panel: Colors.white,
    panelTranslucent: Color(0xF2FFFFFF),
    textPrimary: Color(0xFF1E1E28),
    textSecondary: Color(0xFF4A4A55),
    textMuted: Color(0xFF8A8A95),
    divider: Color(0x331E1E28),
    accent: Color(0xFF2F6FE0),
    error: Color(0xFFD1453A),
    success: Color(0xFF2E9E4F),
  );

  @override
  AppColors copyWith({
    Color? scaffoldBackground,
    Color? panel,
    Color? panelTranslucent,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? divider,
    Color? accent,
    Color? error,
    Color? success,
  }) {
    return AppColors(
      scaffoldBackground: scaffoldBackground ?? this.scaffoldBackground,
      panel: panel ?? this.panel,
      panelTranslucent: panelTranslucent ?? this.panelTranslucent,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      divider: divider ?? this.divider,
      accent: accent ?? this.accent,
      error: error ?? this.error,
      success: success ?? this.success,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      scaffoldBackground:
          Color.lerp(scaffoldBackground, other.scaffoldBackground, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      panelTranslucent:
          Color.lerp(panelTranslucent, other.panelTranslucent, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      error: Color.lerp(error, other.error, t)!,
      success: Color.lerp(success, other.success, t)!,
    );
  }
}

extension AppColorsX on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}
