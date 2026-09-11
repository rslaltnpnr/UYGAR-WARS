import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_entry.dart';
import '../services/gemini_service.dart';
import '../services/history_service.dart';
import '../services/settings_service.dart';
import '../theme/app_colors.dart';
import '../widgets/cat_sprite.dart';
import '../widgets/chat_sheet.dart';
import '../widgets/reminder_dialog.dart';
import '../widgets/remote_control_sheet.dart';
import '../widgets/roaming_cat.dart';
import '../widgets/settings_dialog.dart';

class HomeScreen extends StatefulWidget {
  final ValueChanged<ThemeMode> onThemeModeChanged;

  const HomeScreen({super.key, required this.onThemeModeChanged});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _sleepAfter = Duration(minutes: 3);
  static const _revertAfter = Duration(seconds: 4);
  static const _catSize = 96.0;

  final _gemini = GeminiService();

  SettingsService? _settings;
  HistoryService? _history;

  CatState _catState = CatState.norm;
  DateTime _lastActivity = DateTime.now();
  Timer? _sleepCheckTimer;
  Timer? _revertTimer;
  StreamSubscription<List<SharedMediaFile>>? _shareSub;
  String? _pendingSharedUrl;

  @override
  void initState() {
    super.initState();
    _init();
    _sleepCheckTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _checkSleep(),
    );
    _initShareIntent();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _settings = SettingsService(prefs);
      _history = HistoryService(prefs);
    });
    final pendingUrl = _pendingSharedUrl;
    if (pendingUrl != null) {
      _pendingSharedUrl = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openRemoteControl(initialUrl: pendingUrl);
      });
    }
  }

  /// Baska bir uygulamadan (orn. YouTube) "Paylas" ile bir link
  /// gonderildiginde "Bilgisayarda Ac" panelini linkle dolu acar.
  void _initShareIntent() {
    _shareSub = ReceiveSharingIntent.instance.getMediaStream().listen(
      _handleSharedFiles,
      onError: (_) {},
    );
    ReceiveSharingIntent.instance.getInitialMedia().then((files) {
      _handleSharedFiles(files);
      ReceiveSharingIntent.instance.reset();
    });
  }

  void _handleSharedFiles(List<SharedMediaFile> files) {
    if (files.isEmpty) return;
    final shared = files.firstWhere(
      (f) => f.type == SharedMediaType.text || f.type == SharedMediaType.url,
      orElse: () => files.first,
    );
    final text = shared.path.trim();
    if (text.isEmpty) return;
    final match = RegExp(r'https?://\S+').firstMatch(text);
    final url = match?.group(0) ?? text;
    if (_settings != null && mounted) {
      _openRemoteControl(initialUrl: url);
    } else {
      _pendingSharedUrl = url;
    }
  }

  @override
  void dispose() {
    _sleepCheckTimer?.cancel();
    _revertTimer?.cancel();
    _shareSub?.cancel();
    super.dispose();
  }

  void _registerActivity() {
    _lastActivity = DateTime.now();
    if (_catState == CatState.zzz) {
      setState(() => _catState = CatState.norm);
    }
  }

  void _checkSleep() {
    if (_catState == CatState.stern || _catState == CatState.zzz) return;
    if (DateTime.now().difference(_lastActivity) >= _sleepAfter) {
      setState(() => _catState = CatState.zzz);
    }
  }

  void _scheduleRevert() {
    _revertTimer?.cancel();
    _revertTimer = Timer(_revertAfter, () {
      if (mounted) setState(() => _catState = CatState.norm);
    });
  }

  void _openChat() {
    _registerActivity();
    final settings = _settings;
    final history = _history;
    if (settings == null || history == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ChatSheet(
        settings: settings,
        history: history,
        onAsk: _handleQuestion,
      ),
    );
  }

  void _openSettings() {
    _registerActivity();
    final settings = _settings;
    if (settings == null) return;
    showDialog(
      context: context,
      builder: (_) => SettingsDialog(
        settings: settings,
        onThemeModeChanged: widget.onThemeModeChanged,
      ),
    ).then(
      (_) => setState(() {}),
    ); // isim degismis olabilir, baslik guncellensin
  }

  void _openRemoteControl({String? initialUrl}) {
    _registerActivity();
    final settings = _settings;
    if (settings == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          RemoteControlSheet(settings: settings, initialUrl: initialUrl),
    );
  }

  Future<void> _openReminderDialog() async {
    _registerActivity();
    final minutes = await showDialog<int>(
      context: context,
      builder: (_) => const ReminderDialog(),
    );
    if (minutes != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$minutes dakika sonra hatırlatılacak.')),
      );
    }
  }

  Future<String> _handleQuestion(String question, Uint8List? imageBytes) async {
    final settings = _settings!;
    final history = _history!;
    final apiKey = settings.apiKey;
    if (apiKey.isEmpty) {
      throw Exception(
        'Once ayarlardan Gemini API Key girin (kediyi uzun basip acabilirsiniz).',
      );
    }

    _registerActivity();
    _revertTimer?.cancel();
    setState(() => _catState = CatState.stern);

    try {
      final answer = await _gemini.ask(
        apiKey: apiKey,
        modelName: settings.modelName,
        characterName: settings.characterName,
        question: question,
        imageBytes: imageBytes,
      );
      history.add(
        ChatEntry(
          time: DateTime.now(),
          question: question,
          answer: answer,
          isError: false,
        ),
      );
      if (mounted) setState(() => _catState = CatState.smile);
      _scheduleRevert();
      return answer;
    } catch (exc) {
      final message = exc.toString();
      history.add(
        ChatEntry(
          time: DateTime.now(),
          question: question,
          answer: message,
          isError: true,
        ),
      );
      if (mounted) setState(() => _catState = CatState.fear);
      _scheduleRevert();
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_settings == null || _history == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _registerActivity,
                  ),
                ),
                RoamingCat(
                  bounds: Size(constraints.maxWidth, constraints.maxHeight),
                  state: _catState,
                  size: _catSize,
                  onTap: _openChat,
                  onLongPress: _openSettings,
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                    icon: Icon(Icons.settings, color: context.colors.textMuted),
                    onPressed: _openSettings,
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 48,
                  child: IconButton(
                    icon: Icon(
                      Icons.desktop_windows,
                      color: context.colors.textMuted,
                    ),
                    tooltip: 'Bilgisayarı Kumanda Et',
                    onPressed: _openRemoteControl,
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 88,
                  child: IconButton(
                    icon: Icon(
                      Icons.alarm_add,
                      color: context.colors.textMuted,
                    ),
                    tooltip: 'Hatırlatıcı Kur',
                    onPressed: _openReminderDialog,
                  ),
                ),
                Positioned(
                  top: 12,
                  left: 16,
                  child: Text(
                    _settings!.characterName,
                    style: TextStyle(color: context.colors.textMuted, fontSize: 13),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
