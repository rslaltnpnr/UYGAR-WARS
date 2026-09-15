import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../models/remote_profile.dart';
import '../services/live_control_service.dart';
import '../services/remote_control_service.dart';
import '../services/settings_service.dart';
import '../services/voice_agent_service.dart';

enum _AgentPhase {
  idle,
  listeningGoal,
  connecting,
  running,
  awaitingConfirmation,
  listeningAnswer,
  done,
  error,
}

/// "Sesli Ajan": kullanicinin sozlu olarak verdigi bir gorevi, bilgisayarin
/// ekranini gorerek ve fare/klavyeyi DOGRUDAN kullanarak kendi kendine
/// tamamlamaya calisan bir yapay zeka ajani. Canli Kontrol ile AYNI
/// alt yapiyi (LiveControlSession - ayni TLS soket, ayni PIN/parmak izi)
/// kullanir, ama burada kullanici dokunmaz/gormez sadece izler - ajan
/// ReAct dongusuyle (gozlemle -> TEK adim karar ver -> uygula -> yeniden
/// gozlemle) calisir (bkz. VoiceAgentService).
///
/// GUVENLIK: "riskli" (gonderme, silme, satin alma, odeme, paylasma gibi
/// GERI DONDURULEMEZ) olarak isaretlenen adimlardan once kullanicidan
/// acik onay ister (sesli "evet"/"onayla" ya da dokunarak); normal
/// adimlar (tiklama, yazma, kaydirma) kendiliginden, aninda uygulanir.
/// Ayrica olasi bir sonsuz donguyu onlemek icin en fazla [_maxSteps] adim
/// atar ve her an ekrandaki "DURDUR" dugmesiyle kesilebilir.
class VoiceAgentScreen extends StatefulWidget {
  final RemoteProfile profile;
  final SettingsService settings;
  final void Function(String fingerprint) onFingerprintUpdated;

  const VoiceAgentScreen({
    super.key,
    required this.profile,
    required this.settings,
    required this.onFingerprintUpdated,
  });

  @override
  State<VoiceAgentScreen> createState() => _VoiceAgentScreenState();
}

class _VoiceAgentScreenState extends State<VoiceAgentScreen> {
  static const _maxSteps = 20;

  final _session = LiveControlSession();
  final _agentService = VoiceAgentService();
  final _speech = SpeechToText();
  final _tts = FlutterTts();
  final _logs = <String>[];
  final _scrollController = ScrollController();

  _AgentPhase _phase = _AgentPhase.idle;
  String _liveTranscript = '';
  String? _goal;
  String? _pendingRiskReason;
  Map<String, dynamic>? _pendingAction;
  Uint8List? _latestFrame;
  int _stepCount = 0;
  bool _stopRequested = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _tts.setLanguage('tr-TR');
  }

  @override
  void dispose() {
    _stopRequested = true;
    _speech.stop();
    _tts.stop();
    _session.close();
    _scrollController.dispose();
    super.dispose();
  }

  void _log(String line) {
    setState(() => _logs.add(line));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _speak(String text) async {
    if (text.isEmpty) return;
    _log(text);
    try {
      await _tts.speak(text);
    } catch (_) {
      // Cihazda TTS motoru yoksa/basarisiz olursa sessizce yoksay -
      // ekrandaki yazili log zaten yeterli, sesli anlatim bir eklentidir.
    }
  }

  /// Mikrofon iznini kontrol eder, gerekiyorsa (sistem dialogu ile) ister.
  /// speech_to_text paketinin kendi ic izin istegine GUVENILMEZ - bazi
  /// cihazlarda/Android surumlerinde initialize() sistem dialogunu hic
  /// gostermeden sessizce false donebiliyor, kullaniciya "izin verilmedi"
  /// dedirtip hicbir cikis yolu birakmiyor. Kalici olarak reddedilmisse
  /// (kullanici "bir daha sorma" secmis) sistem dialogu ARTIK
  /// gosterilemez - bu durumda kullaniciyi acikca Ayarlar'a yonlendiririz.
  Future<bool> _ensureMicPermission() async {
    var status = await Permission.microphone.status;
    if (status.isGranted) return true;

    if (status.isPermanentlyDenied) {
      if (!mounted) return false;
      final openSettings = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Mikrofon izni gerekli'),
          content: const Text(
            'Sesli Ajan\'ı kullanmak için mikrofon iznini vermen gerekiyor. '
            'Daha önce reddettiğin için sistem artık izin sormuyor - '
            'Ayarlar\'dan elle açman gerekiyor.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Vazgeç'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Ayarları Aç'),
            ),
          ],
        ),
      );
      if (openSettings == true) await openAppSettings();
      return false;
    }

    status = await Permission.microphone.request();
    if (status.isGranted) return true;

    if (!mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Sesli Ajan için mikrofon izni gerekiyor.'),
      ),
    );
    return false;
  }

  Future<void> _startListeningForGoal() async {
    if (!await _ensureMicPermission()) return;
    final available = await _speech.initialize(
      onError: (_) => setState(() => _phase = _AgentPhase.idle),
    );
    if (!available) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Bu cihazda ses tanıma servisi kullanılamıyor (mikrofon izni '
            'tamam, ama ör. Google uygulaması/ses tanıma motoru eksik '
            'olabilir).',
          ),
        ),
      );
      return;
    }
    setState(() {
      _phase = _AgentPhase.listeningGoal;
      _liveTranscript = '';
    });
    await _speech.listen(
      onResult: (result) {
        setState(() => _liveTranscript = result.recognizedWords);
        if (result.finalResult && result.recognizedWords.trim().isNotEmpty) {
          _onGoalCaptured(result.recognizedWords.trim());
        }
      },
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.dictation,
        localeId: 'tr_TR',
        listenFor: const Duration(seconds: 20),
        pauseFor: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _onGoalCaptured(String goal) async {
    await _speech.stop();
    if (!mounted) return;
    setState(() {
      _goal = goal;
      _phase = _AgentPhase.connecting;
    });
    _log('Hedef: "$goal"');
    await _connectAndRun();
  }

  Future<void> _connectAndRun() async {
    final profile = widget.profile;
    try {
      final fingerprint = await _session.connect(
        ip: profile.ip,
        port: liveControlPortFor(profile.port),
        pin: profile.pin,
        pinnedFingerprint: profile.certFingerprint,
        onFrame: (jpeg) {
          if (!mounted) return;
          setState(() => _latestFrame = jpeg);
        },
        onDisconnected: () {
          if (!mounted || _phase == _AgentPhase.done) return;
          setState(() {
            _phase = _AgentPhase.error;
            _errorMessage = 'Bağlantı kesildi.';
          });
        },
      );
      if (fingerprint != profile.certFingerprint) {
        widget.onFingerprintUpdated(fingerprint);
      }
    } on RemoteControlException catch (exc) {
      if (!mounted) return;
      setState(() {
        _phase = _AgentPhase.error;
        _errorMessage = exc.message;
      });
      return;
    } catch (exc) {
      if (!mounted) return;
      setState(() {
        _phase = _AgentPhase.error;
        _errorMessage = 'Bağlanılamadı: $exc';
      });
      return;
    }

    // Ilk kareyi bekle - ekran goruntusu olmadan ajan hicbir sey goremez.
    var waited = 0;
    while (_latestFrame == null && waited < 50 && !_stopRequested) {
      await Future.delayed(const Duration(milliseconds: 100));
      waited++;
    }
    if (!mounted) return;
    if (_latestFrame == null) {
      setState(() {
        _phase = _AgentPhase.error;
        _errorMessage = 'Bilgisayar ekranı alınamadı.';
      });
      return;
    }

    setState(() => _phase = _AgentPhase.running);
    await _speak('Tamam, başlıyorum.');
    unawaited(_runLoop());
  }

  Future<void> _runLoop() async {
    while (!_stopRequested && _stepCount < _maxSteps && mounted) {
      final frame = _latestFrame;
      if (frame == null) break;

      Map<String, dynamic>? action;
      try {
        action = await _agentService.nextStep(
          apiKey: widget.settings.apiKey,
          modelName: widget.settings.modelName,
          goal: _goal ?? '',
          history: _logs.length > 12 ? _logs.sublist(_logs.length - 12) : _logs,
          screenshotJpeg: frame,
        );
      } catch (exc) {
        await _speak(exc.toString());
        break;
      }
      if (_stopRequested || !mounted) break;

      if (action == null) {
        await _speak('Bir sonraki adımı belirleyemedim, duruyorum.');
        break;
      }
      // action'i final bir kopyaya al: mutable bir yerel degisken,
      // asagidaki setState kapatmasi (closure) icinde okundugu icin
      // Dart'in null-yukseltmesi (promotion) bunun icin gecerli olmaz -
      // final bir kopya bu sorunu ortadan kaldirir.
      final resolvedAction = action;

      if (resolvedAction['type'] == 'done') {
        await _speak(resolvedAction['thought'] as String? ?? 'Görevi tamamladım.');
        if (mounted) setState(() => _phase = _AgentPhase.done);
        return;
      }

      if (resolvedAction['type'] == 'ask_user') {
        final question =
            resolvedAction['question'] as String? ?? 'Devam etmek için bir bilgiye ihtiyacım var.';
        await _speak(question);
        if (!mounted) return;
        _pendingAction = null;
        unawaited(_startListeningForAnswer());
        return; // kullanicinin cevabi _onAnswerCaptured ile dongueyu devam ettirir
      }

      if (isRiskyAction(resolvedAction)) {
        if (!mounted) return;
        setState(() {
          _phase = _AgentPhase.awaitingConfirmation;
          _pendingAction = resolvedAction;
          _pendingRiskReason = resolvedAction['risk_reason'] as String? ??
              'Bu adım önemli/geri döndürülemez bir değişiklik yapabilir.';
        });
        await _speak('${_pendingRiskReason!} Onaylıyor musun?');
        return; // kullanicinin onayi _onConfirm ile dongueyu devam ettirir
      }

      final thought = resolvedAction['thought'] as String?;
      if (thought != null && thought.isNotEmpty) _log(thought);
      _logs.add(describeAgentAction(resolvedAction));
      await _executeAction(resolvedAction);
      _stepCount++;
      await _waitForFrameSettle(frame);
    }

    if (!_stopRequested && _stepCount >= _maxSteps && mounted) {
      await _speak('Adım sınırına ulaştım, duruyorum.');
      setState(() => _phase = _AgentPhase.done);
    } else if (_stopRequested && mounted) {
      setState(() => _phase = _AgentPhase.done);
    }
  }

  /// Bir aksiyondan sonra bir sonraki Gemini adimini istemeden once, ekranin
  /// GERCEKTEN degistigini dogrulamaya calisir - sabit kisa bir bekleme
  /// (cogu tiklama/yazma aninda gorsel etki yaratir) sonrasinda, kare hala
  /// aksiyon ONCESIYLE birebir ayniysa (orn. bir uygulama/sekme henuz
  /// acilmadi), sinirli bir sure daha kisa araliklarla bekler. Bu olmadan
  /// model, henuz gerceklesmemis bir degisikligi "olmadi" saniyor ve ayni
  /// adimi tekrar tekrar veriyordu - gozlenen yavasligin/gereksiz tekrarin
  /// ana nedeni buydu.
  Future<void> _waitForFrameSettle(Uint8List? referenceFrame) async {
    await Future.delayed(const Duration(milliseconds: 900));
    if (referenceFrame == null) return;
    const pollInterval = Duration(milliseconds: 250);
    const maxExtraWait = Duration(milliseconds: 2500);
    var waited = Duration.zero;
    while (waited < maxExtraWait) {
      final current = _latestFrame;
      if (current == null || !_framesIdentical(referenceFrame, current)) return;
      await Future.delayed(pollInterval);
      waited += pollInterval;
    }
  }

  bool _framesIdentical(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> _executeAction(Map<String, dynamic> action) async {
    switch (action['type']) {
      case 'click':
        final x = (action['x'] as num?)?.toDouble();
        final y = (action['y'] as num?)?.toDouble();
        if (x != null && y != null) {
          _session.sendMove(x, y);
          await Future.delayed(const Duration(milliseconds: 80));
        }
        _session.sendClick();
        break;
      case 'type':
        _session.sendText(action['text'] as String? ?? '');
        break;
      case 'key':
        _session.sendKeyTap(action['key'] as String? ?? 'enter');
        break;
      case 'scroll':
        // "Yukarı"/"aşağı" gorsel yonu ile pynput'un mouse.scroll dy yonu
        // ters (bkz. LiveControlScreen'deki ayni duzeltme).
        final dy = action['scroll_direction'] == 'down' ? -3.0 : 3.0;
        _session.sendScroll(dy);
        break;
      case 'wait':
        await Future.delayed(const Duration(milliseconds: 900));
        break;
    }
  }

  Future<void> _onConfirm(bool confirmed) async {
    final action = _pendingAction;
    _pendingAction = null;
    setState(() => _phase = _AgentPhase.running);
    if (!confirmed || action == null) {
      await _speak('Tamam, bu adımı atlıyorum ve görevi durduruyorum.');
      setState(() => _phase = _AgentPhase.done);
      return;
    }
    final thought = action['thought'] as String?;
    if (thought != null && thought.isNotEmpty) _log(thought);
    _logs.add(describeAgentAction(action));
    final referenceFrame = _latestFrame;
    await _executeAction(action);
    _stepCount++;
    await _waitForFrameSettle(referenceFrame);
    unawaited(_runLoop());
  }

  Future<void> _startListeningForAnswer() async {
    if (!await _ensureMicPermission()) return;
    if (!mounted) return;
    setState(() {
      _phase = _AgentPhase.listeningAnswer;
      _liveTranscript = '';
    });
    final available = await _speech.initialize();
    if (!available) return;
    await _speech.listen(
      onResult: (result) {
        setState(() => _liveTranscript = result.recognizedWords);
        if (result.finalResult && result.recognizedWords.trim().isNotEmpty) {
          _onAnswerCaptured(result.recognizedWords.trim());
        }
      },
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.dictation,
        localeId: 'tr_TR',
        listenFor: const Duration(seconds: 20),
        pauseFor: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _onAnswerCaptured(String answer) async {
    await _speech.stop();
    _log('Cevap: "$answer"');
    setState(() => _phase = _AgentPhase.running);
    await _runLoopWithAnswer(answer);
  }

  Future<void> _runLoopWithAnswer(String answer) async {
    if (_stopRequested || !mounted) return;
    final frame = _latestFrame;
    if (frame == null) return;
    Map<String, dynamic>? action;
    try {
      action = await _agentService.nextStep(
        apiKey: widget.settings.apiKey,
        modelName: widget.settings.modelName,
        goal: _goal ?? '',
        history: _logs.length > 12 ? _logs.sublist(_logs.length - 12) : _logs,
        screenshotJpeg: frame,
        userAnswer: answer,
      );
    } catch (exc) {
      await _speak(exc.toString());
      return;
    }
    if (action == null) {
      await _speak('Bir sonraki adımı belirleyemedim, duruyorum.');
      return;
    }
    // Ayni dongueyu (done/ask_user/risky/normal) tekrar etmemek icin
    // gecici bir gecmis girisi ekleyip ana donguyu tekrar tetikliyoruz.
    _logs.add('(devam) $answer');
    unawaited(_continueAfterAnswer(action));
  }

  Future<void> _continueAfterAnswer(Map<String, dynamic> action) async {
    if (action['type'] == 'done') {
      await _speak(action['thought'] as String? ?? 'Görevi tamamladım.');
      if (mounted) setState(() => _phase = _AgentPhase.done);
      return;
    }
    if (action['type'] == 'ask_user') {
      final question = action['question'] as String? ?? 'Devam etmek için bir bilgiye ihtiyacım var.';
      await _speak(question);
      if (!mounted) return;
      unawaited(_startListeningForAnswer());
      return;
    }
    if (isRiskyAction(action)) {
      if (!mounted) return;
      setState(() {
        _phase = _AgentPhase.awaitingConfirmation;
        _pendingAction = action;
        _pendingRiskReason = action['risk_reason'] as String? ??
            'Bu adım önemli/geri döndürülemez bir değişiklik yapabilir.';
      });
      await _speak('${_pendingRiskReason!} Onaylıyor musun?');
      return;
    }
    final thought = action['thought'] as String?;
    if (thought != null && thought.isNotEmpty) _log(thought);
    _logs.add(describeAgentAction(action));
    final referenceFrame = _latestFrame;
    await _executeAction(action);
    _stepCount++;
    await _waitForFrameSettle(referenceFrame);
    unawaited(_runLoop());
  }

  void _stop() {
    _stopRequested = true;
    _speech.stop();
    setState(() => _phase = _AgentPhase.done);
    _speak('Durduruldu.');
  }

  void _reset() {
    setState(() {
      _phase = _AgentPhase.idle;
      _goal = null;
      _logs.clear();
      _stepCount = 0;
      _stopRequested = false;
      _errorMessage = null;
      _pendingAction = null;
    });
    _session.close();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sesli Ajan')),
      body: Column(
        children: [
          if (_latestFrame != null)
            Container(
              height: 160,
              width: double.infinity,
              color: Colors.black,
              child: Image.memory(_latestFrame!, fit: BoxFit.contain, gaplessPlayback: true),
            ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: _logs.length,
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(_logs[index]),
              ),
            ),
          ),
          SafeArea(top: false, child: _buildBottomArea()),
        ],
      ),
    );
  }

  Widget _buildBottomArea() {
    switch (_phase) {
      case _AgentPhase.idle:
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Ne yapmamı istersin? Mikrofona basıp söyle.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FloatingActionButton.large(
                onPressed: _startListeningForGoal,
                child: const Icon(Icons.mic),
              ),
            ],
          ),
        );
      case _AgentPhase.listeningGoal:
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_liveTranscript.isEmpty ? 'Dinliyorum...' : _liveTranscript),
              const SizedBox(height: 12),
              const CircularProgressIndicator(),
            ],
          ),
        );
      case _AgentPhase.connecting:
        return const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        );
      case _AgentPhase.running:
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Adım $_stepCount/$_maxSteps'),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                onPressed: _stop,
                icon: const Icon(Icons.stop),
                label: const Text('DURDUR'),
              ),
            ],
          ),
        );
      case _AgentPhase.awaitingConfirmation:
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _pendingRiskReason ?? '',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton(
                    onPressed: () => _onConfirm(false),
                    child: const Text('İptal'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () => _onConfirm(true),
                    child: const Text('Onayla'),
                  ),
                ],
              ),
            ],
          ),
        );
      case _AgentPhase.listeningAnswer:
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_liveTranscript.isEmpty ? 'Cevabını dinliyorum...' : _liveTranscript),
              const SizedBox(height: 12),
              FloatingActionButton(
                onPressed: _startListeningForAnswer,
                child: const Icon(Icons.mic),
              ),
            ],
          ),
        );
      case _AgentPhase.done:
        return Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton.icon(
            onPressed: _reset,
            icon: const Icon(Icons.refresh),
            label: const Text('Yeni Görev'),
          ),
        );
      case _AgentPhase.error:
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _errorMessage ?? 'Bir hata oluştu.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.redAccent),
              ),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _reset, child: const Text('Tekrar Dene')),
            ],
          ),
        );
    }
  }
}
