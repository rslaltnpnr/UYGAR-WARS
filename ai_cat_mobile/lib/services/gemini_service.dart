import 'dart:typed_data';

import 'package:google_generative_ai/google_generative_ai.dart';

/// Google Gemini'ye ekran/galeri goruntusu + soru gonderir.
///
/// Masaustu surumundeki gibi: gecici asiri yuklenme (503) hatalarinda
/// kisa bir bekleme ile tekrar dener; ana model kaldirilmis/bulunamiyorsa
/// (404) veya tum denemelerde asiri yukluyse otomatik olarak yedek modele
/// gecer.
class GeminiService {
  static const fallbackModel = 'gemini-3.6-flash';
  static const _overloadRetryDelays = [
    Duration(seconds: 2),
    Duration(seconds: 4),
  ];
  static const _fallbackRetryDelays = [Duration(seconds: 2)];

  Future<String> ask({
    required String apiKey,
    required String modelName,
    required String characterName,
    required String question,
    Uint8List? imageBytes,
  }) async {
    final persona = Content.system(
      "Senin adin '$characterName'. Kullanicinin telefonunda yasayan, "
      "gonderdigi gorselleri gorebilen sevimli bir kedi yapay zeka "
      "asistanisin. Kendini her zaman bu isimle tanit; Google tarafindan "
      "gelistirilmis bir dil modeli oldugunu veya hangi sirkete/modele ait "
      "oldugunu asla soyleme. Kisa, samimi ve yardimsever konus.",
    );

    final parts = <Part>[TextPart(question)];
    if (imageBytes != null) {
      parts.add(DataPart('image/jpeg', imageBytes));
    }
    final content = [Content.multi(parts)];

    try {
      final response = await _generateWithRetry(
        apiKey: apiKey,
        modelName: modelName,
        systemInstruction: persona,
        content: content,
        retryDelays: _overloadRetryDelays,
      );
      return _extractText(response);
    } catch (primaryError) {
      final shouldFallback = modelName != fallbackModel &&
          (_isOverloadError(primaryError) ||
              _isModelRetiredError(primaryError));
      if (!shouldFallback) rethrow;
      try {
        final response = await _generateWithRetry(
          apiKey: apiKey,
          modelName: fallbackModel,
          systemInstruction: persona,
          content: content,
          retryDelays: _fallbackRetryDelays,
        );
        return _extractText(response);
      } catch (_) {
        // Yedek model de basarisiz oldu; kullaniciya orijinal hatayi goster.
        rethrow;
      }
    }
  }

  String _extractText(GenerateContentResponse response) {
    final text = response.text?.trim();
    return (text == null || text.isEmpty) ? '(Bos yanit dondu)' : text;
  }

  Future<GenerateContentResponse> _generateWithRetry({
    required String apiKey,
    required String modelName,
    required Content systemInstruction,
    required List<Content> content,
    required List<Duration> retryDelays,
  }) async {
    final model = GenerativeModel(
      model: modelName,
      apiKey: apiKey,
      systemInstruction: systemInstruction,
    );

    final attempts = retryDelays.length + 1;
    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        return await model.generateContent(content);
      } catch (exc) {
        final isLastAttempt = attempt == attempts - 1;
        if (isLastAttempt || !_isOverloadError(exc)) rethrow;
        await Future.delayed(retryDelays[attempt]);
      }
    }
    throw StateError('generateContent hicbir deneme yapmadan basarisiz oldu.');
  }

  bool _isOverloadError(Object exc) {
    final text = exc.toString().toLowerCase();
    return text.contains('503') ||
        text.contains('unavailable') ||
        text.contains('overloaded');
  }

  bool _isModelRetiredError(Object exc) {
    final text = exc.toString().toLowerCase();
    return text.contains('404') ||
        text.contains('not_found') ||
        text.contains('no longer available');
  }
}
