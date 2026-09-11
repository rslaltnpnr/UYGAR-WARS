import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/home_screen.dart';
import 'services/settings_service.dart';
import 'theme/app_colors.dart';

void main() {
  runApp(const AiCatApp());
}

class AiCatApp extends StatefulWidget {
  const AiCatApp({super.key});

  @override
  State<AiCatApp> createState() => _AiCatAppState();
}

class _AiCatAppState extends State<AiCatApp> {
  ThemeMode _themeMode = ThemeMode.dark; // ilk yuklenene kadarki varsayilan

  @override
  void initState() {
    super.initState();
    _loadThemeMode();
  }

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _themeMode = SettingsService(prefs).themeMode);
  }

  void _onThemeModeChanged(ThemeMode mode) {
    setState(() => _themeMode = mode);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Kedi Asistani',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        brightness: Brightness.light,
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.light.scaffoldBackground,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.light.accent,
          brightness: Brightness.light,
        ),
        extensions: const [AppColors.light],
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.dark.scaffoldBackground,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.dark.accent,
          brightness: Brightness.dark,
        ),
        extensions: const [AppColors.dark],
      ),
      home: HomeScreen(onThemeModeChanged: _onThemeModeChanged),
    );
  }
}
