import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/secure_note.dart';

/// unlock() cagrisina girilen sifre, saklanan tuzla turetilen anahtarla
/// eslesmedigini (AES-GCM'in kimlik dogrulama etiketi tutmadigini)
/// belirtir - "bozuk veri" ile ayni sonuc, ama kullaniciya "yanlis sifre"
/// olarak gosterilir.
class WrongPasswordException implements Exception {}

/// unlock()'un basarili sonucu: cozulen notlar ve sonraki save()
/// cagrilari icin tekrar sifre girmeden kullanilabilecek turetilmis
/// anahtar. Anahtar yalnizca bellekte tutulur, hicbir yerde saklanmaz -
/// defter kilitlenince (bkz. SecureNotepadSheet._lock) atilir.
class SecureNotepadUnlockResult {
  final SecretKey key;
  final List<SecureNote> notes;

  const SecureNotepadUnlockResult({required this.key, required this.notes});
}

/// Notlari, kullanicinin belirledigi bir sifreden turetilen bir anahtarla
/// AES-256-GCM ile sifreleyip cihazda saklayan servis. Butun not listesi
/// TEK bir sifreli blok olarak tutulur (not basina degil) - hem daha
/// basit hem de not sayisi/boyutu gibi meta veriyi ayri ayri sizdirmaz.
///
/// Sifre hicbir zaman diskte saklanmaz; her kilit acmada PBKDF2-HMAC-SHA256
/// ile saklanan tuzdan yeniden turetilir ve doğruluğu AES-GCM'in kendi
/// kimlik dogrulama etiketiyle sinanir (decrypt yanlis anahtarda
/// SecretBoxAuthenticationError firlatir - ayrica bir "dogrulama" degeri
/// saklamaya gerek yok). Sifre unutulursa notlar KURTARILAMAZ - bu,
/// gercekten sifreli olmanin kasitli bedelidir (bkz. reset()).
class SecureNotepadService {
  SecureNotepadService({this.pbkdf2Iterations = _defaultPbkdf2Iterations});

  // OWASP PBKDF2-HMAC-SHA256 onerisi 600k+ ama bu saf Dart'ta (yerel
  // hizlandirma olmadan) dusuk uclu telefonlarda kilit acmayi rahatsiz
  // edici derecede yavaslatabilir; 200k, telefonlarda ~yarim saniye
  // civarinda kalirken yine de kaba kuvveti pahali kilan bir denge.
  static const _defaultPbkdf2Iterations = 200000;
  static const _saltKey = 'secure_notepad_salt';
  static const _blobKey = 'secure_notepad_blob';
  // AesGcm.with256bits()'in belgelenmis varsayilanlari.
  static const _nonceLength = 12;
  static const _macLength = 16;

  final int pbkdf2Iterations;
  final _algorithm = AesGcm.with256bits();
  late final _kdf = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: pbkdf2Iterations,
    bits: 256,
  );

  Future<bool> isSetUp() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_saltKey) && prefs.containsKey(_blobKey);
  }

  Future<SecretKey> _deriveKey(String password, List<int> salt) {
    return _kdf.deriveKeyFromPassword(password: password, nonce: salt);
  }

  List<int> _randomSalt() {
    final random = Random.secure();
    return List<int>.generate(16, (_) => random.nextInt(256));
  }

  /// Ilk kurulum: yeni bir tuz uretir, [password]'dan bir anahtar turetir
  /// ve bos bir not listesini sifreleyip kaydeder. Dondurulen anahtar,
  /// oturum boyunca save() cagrilarinda sifreyi tekrar girmeden
  /// kullanilabilir.
  Future<SecretKey> setUp(String password) async {
    final salt = _randomSalt();
    final key = await _deriveKey(password, salt);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_saltKey, base64Encode(salt));
    await _writeNotes(prefs, key, const []);
    return key;
  }

  /// [password] dogruysa notlari cozup [SecureNotepadUnlockResult] olarak
  /// dondurur; yanlissa [WrongPasswordException] firlatir. Defter henuz
  /// kurulmadiysa (bkz. isSetUp()) [StateError] firlatir.
  Future<SecureNotepadUnlockResult> unlock(String password) async {
    final prefs = await SharedPreferences.getInstance();
    final saltB64 = prefs.getString(_saltKey);
    final blobB64 = prefs.getString(_blobKey);
    if (saltB64 == null || blobB64 == null) {
      throw StateError('Not defteri henuz kurulmadi.');
    }
    final salt = base64Decode(saltB64);
    final key = await _deriveKey(password, salt);
    final box = SecretBox.fromConcatenation(
      base64Decode(blobB64),
      nonceLength: _nonceLength,
      macLength: _macLength,
    );
    final List<int> plainBytes;
    try {
      plainBytes = await _algorithm.decrypt(box, secretKey: key);
    } on SecretBoxAuthenticationError {
      throw WrongPasswordException();
    }
    final list = jsonDecode(utf8.decode(plainBytes)) as List<dynamic>;
    final notes = list
        .map((e) => SecureNote.fromJson(e as Map<String, dynamic>))
        .toList();
    return SecureNotepadUnlockResult(key: key, notes: notes);
  }

  /// [notes]'u onceden turetilmis [key] ile yeniden sifreleyip kaydeder -
  /// her cagrida YENI bir rastgele nonce kullanilir (AES-GCM'de ayni
  /// anahtarla nonce tekrari kritik bir guvenlik zafiyetidir), bu yuzden
  /// encrypt() her seferinde otomatik olarak taze bir nonce uretir.
  Future<void> save(SecretKey key, List<SecureNote> notes) async {
    final prefs = await SharedPreferences.getInstance();
    await _writeNotes(prefs, key, notes);
  }

  Future<void> _writeNotes(
    SharedPreferences prefs,
    SecretKey key,
    List<SecureNote> notes,
  ) async {
    final plainBytes =
        utf8.encode(jsonEncode(notes.map((n) => n.toJson()).toList()));
    final box = await _algorithm.encrypt(plainBytes, secretKey: key);
    await prefs.setString(_blobKey, base64Encode(box.concatenation()));
  }

  /// Not defterini ve tum notlari kalici olarak siler. Sifre unutulduysa
  /// tek secenek budur: anahtar yalnizca sifreden turetilir ve hicbir
  /// yerde saklanmaz, bu yuzden "sifremi unuttum" akisi kriptografik
  /// olarak imkansizdir.
  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_saltKey);
    await prefs.remove(_blobKey);
  }
}
