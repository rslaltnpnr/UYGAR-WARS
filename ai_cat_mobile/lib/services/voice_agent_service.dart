import 'dart:convert';
import 'dart:typed_data';

import 'package:google_generative_ai/google_generative_ai.dart';

import 'gemini_service.dart';

/// Ajanin bir sonraki adiminin tipi - Gemini'nin JSON yanitindaki "type"
/// alaniyla birebir eslesir.
const agentActionTypes = {
  'click',
  'type',
  'key',
  'scroll',
  'wait',
  'ask_user',
  'done',
};

/// Adimi GERI DONDURULEMEZ/onemli bir sonuc doguruyor sayan anahtar
/// kelimeler - modelin kendi "risky" isaretlemesine EK olarak, adimin
/// "text"/"thought"/"question" alanlarinda bu kelimelerden biri gecerse
/// model unutsa/kacirsa bile yine de onay istenir (savunma katmani,
/// modelin kendi degerlendirmesine tek basina guvenilmez).
const _riskyKeywords = [
  'sil', 'delete', 'kaldır', 'remove', 'format',
  'satın al', 'satin al', 'buy', 'purchase', 'ödeme', 'odeme', 'pay',
  'gönder', 'gonder', 'send', 'paylaş', 'paylas', 'share',
  'onayla', 'confirm', 'kalıcı', 'kalici', 'permanent', 'irreversible',
  'sıfırla', 'sifirla', 'factory reset', 'çıkış yap', 'cikis yap', 'logout',
  'hesabı kapat', 'hesabi kapat', 'deactivate',
];

/// Gemini'nin dondurdugu ham JSON metnini ayristirip dogrular; gecerli
/// bir eylem degilse (bozuk JSON, taninmayan "type", vb.) null doner -
/// cagiran taraf bunu "bir sorun oldu, dur" olarak ele almali. Saf bir
/// fonksiyondur, Gemini'ye baglanmadan test edilebilir.
Map<String, dynamic>? parseAgentAction(String rawText) {
  String cleaned = rawText.trim();
  // Bazen model JSON'u ```json ... ``` bloguna sarar - responseMimeType
  // 'application/json' istense de bir guvenlik agi olarak temizlenir.
  if (cleaned.startsWith('```')) {
    cleaned = cleaned.replaceFirst(RegExp(r'^```[a-zA-Z]*\n?'), '');
    cleaned = cleaned.replaceFirst(RegExp(r'```\s*$'), '');
  }
  Object? decoded;
  try {
    decoded = jsonDecode(cleaned);
  } catch (_) {
    return null;
  }
  if (decoded is! Map<String, dynamic>) return null;
  final type = decoded['type'];
  if (type is! String || !agentActionTypes.contains(type)) return null;
  return decoded;
}

/// Bir eylemin, kullanicidan onay ISTENMEDEN otomatik uygulanamayacak
/// kadar riskli olup olmadigini belirler - modelin kendi "risky" alani
/// TRUE ise ya da eylemin metninde/aciklamasinda bilinen riskli bir
/// kelime geciyorsa true doner. Iki bagimsiz kontrolden biri yeterlidir
/// (savunma derinligi - modelin kendi degerlendirmesi tek basina
/// guvenilir kabul edilmez).
bool isRiskyAction(Map<String, dynamic> action) {
  if (action['risky'] == true) return true;
  final haystack = [
    action['text'],
    action['thought'],
    action['question'],
    action['risk_reason'],
  ].whereType<String>().join(' ').toLowerCase();
  return _riskyKeywords.any(haystack.contains);
}

/// Bir eylemi, gecmis olarak bir sonraki Gemini cagrisina eklenecek
/// kisa, insan-okunabilir tek satira cevirir.
String describeAgentAction(Map<String, dynamic> action) {
  final thought = action['thought'] as String?;
  switch (action['type']) {
    case 'click':
      return thought ?? 'Ekranda bir noktaya tıklandı.';
    case 'type':
      return thought ?? '"${action['text']}" yazıldı.';
    case 'key':
      return thought ?? '"${action['key']}" tuşuna basıldı.';
    case 'scroll':
      return thought ?? '${action['scroll_direction']} yönünde kaydırıldı.';
    case 'wait':
      return thought ?? 'Kısa bir süre beklendi.';
    default:
      return thought ?? '';
  }
}

const _agentSystemInstruction = '''
Sen bilgisayar ekranını görebilen ve fare/klavyeyi DOĞRUDAN kontrol
edebilen bir yapay zeka ajanısın. Kullanıcının sözlü olarak verdiği bir
görevi, sana gösterilen ekran görüntüsüne bakarak tamamlarsın.

Her çağrıda sana: kullanıcının hedefi, şimdiye kadar yapılan adımların
kısa geçmişi ve bilgisayarın O ANKİ ekran görüntüsü verilir. Sen SADECE
bir sonraki TEK adımı belirtirsin - asla birden fazla adımı aynı anda
planlama, çünkü her adımdan sonra ekran değişebilir ve yeniden
değerlendirmen gerekir.

SADECE aşağıdaki alanları içeren, başka HİÇBİR metin/açıklama İÇERMEYEN
bir JSON nesnesi döndür:
{
  "thought": "<kullanıcıya sesli okunacak, ne yaptığını açıklayan KISA (1 cümle) Türkçe metin>",
  "type": "click" | "type" | "key" | "scroll" | "wait" | "ask_user" | "done",
  "x": <0.0-1.0 arası normalleştirilmiş yatay konum - SADECE type=click>,
  "y": <0.0-1.0 arası normalleştirilmiş dikey konum - SADECE type=click>,
  "text": "<yazılacak metin - SADECE type=type>",
  "key": "enter"|"backspace"|"tab"|"esc"|"up"|"down"|"left"|"right" (SADECE type=key),
  "scroll_direction": "up"|"down" (SADECE type=scroll),
  "question": "<kullanıcıya sorulacak soru - SADECE type=ask_user>",
  "risky": <true/false - GERİ DÖNDÜRÜLEMEZ ya da önemli bir sonuç doğurabilir mi?>,
  "risk_reason": "<risky=true ise nedenini kısaca açıklayan, kullanıcıya sesli okunacak bir cümle>"
}

Kurallar:
- type=done: görev tamamlandığında; "thought" alanına kısa bir özet yaz.
- type=ask_user: görev belirsizse, ekranda beklenmedik bir şey varsa ya da
  emin değilsen - TAHMİN YÜRÜTME, sor.
- risky=true işaretlemekten ÇEKİNME: bir mesaj/e-posta gönderme, bir
  satın alma/ödemeyi onaylama, bir dosya/hesap silme, geri alınamaz bir
  ayarı değiştirme, paylaşma gibi HERHANGİ bir adımı risky=true yap.
- Yalnızca JSON döndür, önce/sonra açıklama, markdown bloğu ya da başka
  metin EKLEME.
''';

/// "Sesli Ajan" ekraninin (bkz. VoiceAgentScreen) her adiminda Gemini'den
/// TEK bir sonraki eylemi ister - ReAct dongusu (gozlemle -> tek adim
/// karar ver -> uygula -> yeniden gozlemle) mantigiyla calisir, GeminiService
/// (sohbet paneli icin kullanilan, kedi kisiligiyle konusan) sinifindan
/// AYRIDIR cunku tamamen farkli bir sistem talimati ve JSON-modu yaniti
/// gerektirir.
class VoiceAgentService {
  Future<Map<String, dynamic>?> nextStep({
    required String apiKey,
    required String modelName,
    required String goal,
    required List<String> history,
    required Uint8List screenshotJpeg,
    String? userAnswer,
  }) async {
    final systemInstruction = Content.system(_agentSystemInstruction);
    final generationConfig =
        GenerationConfig(responseMimeType: 'application/json');

    final buffer = StringBuffer()
      ..writeln('Kullanıcının hedefi: $goal')
      ..writeln();
    if (history.isNotEmpty) {
      buffer.writeln('Şimdiye kadar yapılan adımlar:');
      for (final line in history) {
        buffer.writeln('- $line');
      }
      buffer.writeln();
    }
    if (userAnswer != null && userAnswer.isNotEmpty) {
      buffer.writeln('Kullanıcının son soruna cevabı: $userAnswer');
      buffer.writeln();
    }
    buffer.write('Ekte bilgisayarın o anki ekran görüntüsü var. Sıradaki TEK adımı belirt.');

    final content = [
      Content.multi([
        TextPart(buffer.toString()),
        DataPart('image/jpeg', screenshotJpeg),
      ]),
    ];

    Object finalError;
    try {
      final response = await generateGeminiContentWithRetry(
        apiKey: apiKey,
        modelName: modelName,
        systemInstruction: systemInstruction,
        generationConfig: generationConfig,
        content: content,
        maxAttempts: 3,
      );
      final text = response.text;
      if (text == null || text.isEmpty) return null;
      return parseAgentAction(text);
    } catch (primaryError) {
      finalError = primaryError;
      final shouldFallback = modelName != geminiFallbackModel &&
          (isGeminiOverloadError(primaryError) ||
              isGeminiModelRetiredError(primaryError) ||
              isGeminiQuotaError(primaryError));
      if (shouldFallback) {
        try {
          final response = await generateGeminiContentWithRetry(
            apiKey: apiKey,
            modelName: geminiFallbackModel,
            systemInstruction: systemInstruction,
            generationConfig: generationConfig,
            content: content,
            maxAttempts: 2,
          );
          final text = response.text;
          if (text == null || text.isEmpty) return null;
          return parseAgentAction(text);
        } catch (fallbackError) {
          finalError = fallbackError;
        }
      }
    }
    throw GeminiRequestException(_friendlyMessage(finalError));
  }

  String _friendlyMessage(Object exc) {
    if (isGeminiQuotaError(exc)) {
      return 'Ücretsiz kullanım kotası doldu, biraz bekleyip tekrar dene.';
    }
    if (isGeminiOverloadError(exc)) {
      return 'Google\'ın sunucuları şu an yoğun, birazdan tekrar dener misin?';
    }
    if (isGeminiModelRetiredError(exc)) {
      return 'Kullanılan yapay zeka modeli güncellenmiş görünüyor. '
          'Lütfen tekrar dener misin?';
    }
    if (isGeminiNetworkError(exc)) {
      return 'İnternet bağlantısı kurulamadı.';
    }
    return 'Ajan bir adım belirlerken bir sorun oluştu.';
  }
}
