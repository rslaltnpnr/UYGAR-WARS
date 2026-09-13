import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/app_lock_screen.dart';
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
  SettingsService? _settings;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final settings = SettingsService(prefs);
    setState(() {
      _settings = settings;
      _themeMode = settings.themeMode;
    });
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
      home: _settings == null
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : _AppLockGate(
              settings: _settings!,
              child: HomeScreen(onThemeModeChanged: _onThemeModeChanged),
            ),
    );
  }
}

/// [settings].appLockEnabled acikken [child]'i bir PIN ekraninin
/// arkasina gizler - ilk acilista VE uygulama arka plana gidip geri
/// donduğunde (bkz. didChangeAppLifecycleState) tekrar kilitlenir, boylece
/// telefonu birakip donen biri kilidi atlayamaz. Kilit kapaliysa (varsayilan)
/// bu widget tamamen seffaftir, [child]'i dogrudan gosterir.
class _AppLockGate extends StatefulWidget {
  final SettingsService settings;
  final Widget child;

  const _AppLockGate({required this.settings, required this.child});

  @override
  State<_AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<_AppLockGate>
    with WidgetsBindingObserver {
  late bool _locked = widget.settings.appLockEnabled &&
      (widget.settings.appLockPin?.isNotEmpty ?? false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final pin = widget.settings.appLockPin;
    if (widget.settings.appLockEnabled &&
        (pin?.isNotEmpty ?? false) &&
        state == AppLifecycleState.paused) {
      setState(() => _locked = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pin = widget.settings.appLockPin;
    if (!_locked || !widget.settings.appLockEnabled || pin == null || pin.isEmpty) {
      return widget.child;
    }
    return AppLockScreen(
      expectedPin: pin,
      onUnlocked: () => setState(() => _locked = false),
    );
  }
}
