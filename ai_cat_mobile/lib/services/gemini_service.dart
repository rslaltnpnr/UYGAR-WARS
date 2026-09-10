import 'dart:typed_data';

import 'package:google_generative_ai/google_generative_ai.dart';

/// Google Gemini'ye ekran/galeri goruntusu + soru gonderir.
///
/// Masaustu surumundeki gibi: gecici asiri yuklenme (503) hatalarinda
/// kisa bir bekleme ile tekrar dener; ana model kaldirilmis/bulunamiyorsa
/// (404) veya ucretsiz kota (429) doluysa otomatik olarak yedek modele
/// gecer. Kota hatasinda Gemini'nin "Please retry in Ns" mesajindaki
/// bekleme suresi kullanilir.
class GeminiService {
  static const fallbackModel = 'gemini-3.6-flash';
  static const _defaultQuotaWait = Duration(seconds: 5);
  static const _maxQuotaWait = Duration(seconds: 20);

  static final RegExp _retryAfterPattern = RegExp(
    r'retry in ([\d.]+)\s*s',
    caseSensitive: false,
  );

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
        maxAttempts: 3,
      );
      return _extractText(response);
    } catch (primaryError) {
      final shouldFallback = modelName != fallbackModel &&
          (_isOverloadError(primaryError) ||
              _isModelRetiredError(primaryError) ||
              _isQuotaError(primaryError));
      if (!shouldFallback) rethrow;
      try {
        final response = await _generateWithRetry(
          apiKey: apiKey,
          modelName: fallbackModel,
          systemInstruction: persona,
          content: content,
          maxAttempts: 2,
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
    required int maxAttempts,
  }) async {
    final model = GenerativeModel(
      model: modelName,
      apiKey: apiKey,
      systemInstruction: systemInstruction,
    );

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        return await model.generateContent(content);
      } catch (exc) {
        final isLastAttempt = attempt == maxAttempts - 1;
        if (isLastAttempt) rethrow;

        if (_isOverloadError(exc)) {
          await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
          continue;
        }
        if (_isQuotaError(exc)) {
          await Future.delayed(_parseRetryAfter(exc) ?? _defaultQuotaWait);
          continue;
        }
        rethrow;
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

  bool _isQuotaError(Object exc) {
    final text = exc.toString().toLowerCase();
    return text.contains('429') ||
        text.contains('quota') ||
        text.contains('resource_exhausted');
  }

  Duration? _parseRetryAfter(Object exc) {
    final match = _retryAfterPattern.firstMatch(exc.toString());
    if (match == null) return null;
    final seconds = double.tryParse(match.group(1)!);
    if (seconds == null) return null;
    final capped = seconds.clamp(1.0, _maxQuotaWait.inSeconds.toDouble());
    return Duration(milliseconds: (capped * 1000).round());
  }
}
