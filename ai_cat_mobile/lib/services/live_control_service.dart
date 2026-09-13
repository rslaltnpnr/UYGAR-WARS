import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;

import 'remote_control_service.dart' show RemoteControlException;

/// Bilgisayardaki ai_desktop_assistant'in "Canlı Kontrol" soket sunucusu
/// (bkz. main.py - RemoteLiveControlServer), REST komut sunucusundan
/// (RemoteControlService, port) AYRI bir portta calisir - telefon tarafi
/// bu portu ayrica eslestirmez, sabit `port + 1` kuralini kullanir (aynen
/// masaustu tarafindaki REMOTE_LIVE_PORT = REMOTE_SERVER_PORT + 1 gibi).
int liveControlPortFor(int remoteServerPort) => remoteServerPort + 1;

/// Alinan bir video karesi arabellegindeki TAMAMLANMIS kareleri (4 bayt
/// buyuk-endian uzunluk + o kadar JPEG bayti, art arda) ayiklar; henuz
/// tamamlanmamis kalan baytlari [remaining] olarak dondurur (bir sonraki
/// veri parcasiyla birlestirilip tekrar denenir). Saf bir fonksiyondur -
/// soket olmadan test edilebilir.
({List<Uint8List> frames, Uint8List remaining}) extractLiveFrames(
  Uint8List buffer,
) {
  final frames = <Uint8List>[];
  var offset = 0;
  while (buffer.length - offset >= 4) {
    final length = ByteData.sublistView(buffer, offset, offset + 4).getUint32(0);
    if (buffer.length - offset < 4 + length) break;
    frames.add(buffer.sublist(offset + 4, offset + 4 + length));
    offset += 4 + length;
  }
  return (frames: frames, remaining: buffer.sublist(offset));
}

/// [oldText] -> [newText] icin en kucuk "sondan sil, sonra ekle" farkini
/// hesaplar (ortak onek/sonek yontemiyle) - telefondaki metin kutusuna
/// yazilanlari gercek zamanli olarak bilgisayara ("backspaces" kadar
/// Backspace + "insert" metnini yaz) uygulamak icin kullanilir. Sadece
/// sona ekleme/silme degil, metnin ortasindaki degisiklikleri (orn.
/// otomatik tamamlamanin son kelimeyi degistirmesi) de makul sekilde
/// isler.
({int backspaces, String insert}) diffTypedText(String oldText, String newText) {
  final minLen = oldText.length < newText.length ? oldText.length : newText.length;
  var prefixLen = 0;
  while (prefixLen < minLen && oldText[prefixLen] == newText[prefixLen]) {
    prefixLen++;
  }
  var oldEnd = oldText.length;
  var newEnd = newText.length;
  while (oldEnd > prefixLen && newEnd > prefixLen && oldText[oldEnd - 1] == newText[newEnd - 1]) {
    oldEnd--;
    newEnd--;
  }
  return (backspaces: oldEnd - prefixLen, insert: newText.substring(prefixLen, newEnd));
}

/// [LogicalKeyboardKey] icin bilgisayar tarafinin ("kd"/"ku" komutlarinda
/// "k" alani) bekledigi ozel tus adini dondurur - eslesme yoksa null
/// (bu tus, TextField'in kendi metin degisikligi olarak zaten ele alinir,
/// bkz. diffTypedText, ya da desteklenmez).
String? specialLiveKeyName(LogicalKeyboardKey key) {
  final map = {
    LogicalKeyboardKey.enter: 'enter',
    LogicalKeyboardKey.numpadEnter: 'enter',
    LogicalKeyboardKey.backspace: 'backspace',
    LogicalKeyboardKey.delete: 'delete',
    LogicalKeyboardKey.tab: 'tab',
    LogicalKeyboardKey.escape: 'esc',
    LogicalKeyboardKey.space: 'space',
    LogicalKeyboardKey.arrowUp: 'up',
    LogicalKeyboardKey.arrowDown: 'down',
    LogicalKeyboardKey.arrowLeft: 'left',
    LogicalKeyboardKey.arrowRight: 'right',
    LogicalKeyboardKey.home: 'home',
    LogicalKeyboardKey.end: 'end',
  };
  return map[key];
}

/// Bir dokunma noktasinin (widget'in yerel koordinatlarinda,
/// [localPosition]) video karesindeki ([imageSize]) karsiligini,
/// goruntunun [widgetSize] icinde `BoxFit.contain` ile (siyah seritlerle,
/// en/boy orani korunarak) nasil gosterildigini hesaba katarak 0..1
/// arasi normallestirilmis bir konuma cevirir. Dokunma, goruntunun
/// disindaki (harf kutusu/letterbox) bosluga denk geliyorsa null doner -
/// cagiran taraf bu durumda komut gondermemeli.
Offset? mapTouchToNormalized(
  Offset localPosition,
  Size widgetSize,
  Size imageSize,
) {
  if (widgetSize.width <= 0 ||
      widgetSize.height <= 0 ||
      imageSize.width <= 0 ||
      imageSize.height <= 0) {
    return null;
  }
  final scale = (widgetSize.width / imageSize.width < widgetSize.height / imageSize.height)
      ? widgetSize.width / imageSize.width
      : widgetSize.height / imageSize.height;
  final displayedWidth = imageSize.width * scale;
  final displayedHeight = imageSize.height * scale;
  final offsetX = (widgetSize.width - displayedWidth) / 2;
  final offsetY = (widgetSize.height - displayedHeight) / 2;
  final x = localPosition.dx - offsetX;
  final y = localPosition.dy - offsetY;
  if (x < 0 || y < 0 || x > displayedWidth || y > displayedHeight) {
    return null;
  }
  return Offset(x / displayedWidth, y / displayedHeight);
}

/// Bilgisayarin "Canlı Kontrol" soket sunucusuna baglanip video karelerini
/// alan ve fare/klavye komutlarini gonderen oturum. Protokol (main.py -
/// RemoteLiveControlServer):
///   1) Baglaninca ilk satir olarak PIN (\n ile bitmis) gonderilir.
///   2) Sunucu "OK\n" (basarili) ya da "ERR\n" (PIN yanlis/kilitli) yazar.
///   3) "OK"dan sonra sunucu surekli video karesi yazar (4 bayt
///      buyuk-endian uzunluk + JPEG), biz de surekli JSON komut satirlari
///      yollariz (fare/klavye) - iki yon birbirinden bagimsizdir.
class LiveControlSession {
  Socket? _socket;
  final BytesBuilder _pending = BytesBuilder(copy: false);

  /// Baglanir ve kimlik dogrulamasini bekler; basarili olursa gozlemlenen
  /// sertifika parmak izini dondurur (cagiran taraf TOFU icin kaydeder).
  /// [onFrame] her tamamlanan video karesinde (JPEG baytlari) cagirilir,
  /// [onDisconnected] baglanti (herhangi bir nedenle) kapandiginda.
  Future<String> connect({
    required String ip,
    required int port,
    required String pin,
    required String pinnedFingerprint,
    required void Function(Uint8List jpeg) onFrame,
    required void Function() onDisconnected,
  }) async {
    String? observedFingerprint;
    var fingerprintMismatch = false;

    final SecureSocket socket;
    try {
      socket = await SecureSocket.connect(
        ip.trim(),
        port,
        timeout: const Duration(seconds: 6),
        onBadCertificate: (cert) {
          final fingerprint = sha256.convert(cert.der).toString();
          observedFingerprint = fingerprint;
          if (pinnedFingerprint.isEmpty || fingerprint == pinnedFingerprint) {
            return true;
          }
          fingerprintMismatch = true;
          return false;
        },
      );
    } catch (_) {
      if (fingerprintMismatch) {
        throw RemoteControlException(
          'DIKKAT: Bilgisayarin guvenlik sertifikasi kayitli olandan '
          'farkli! Bu bir araya girme (MITM) saldirisi belirtisi olabilir '
          '- ya da bilgisayar uygulamasi yeniden kuruldu. Emin degilseniz '
          'baglanmayin; eminseniz eslestirmeyi sifirlayip tekrar deneyin.',
        );
      }
      throw RemoteControlException(
        'Bilgisayara ulasilamadi. Ayni Wi-Fi agina bagli oldugunuzdan ve '
        'IP/portun dogru oldugundan emin olun.',
        isNetworkError: true,
      );
    }

    _socket = socket;
    var authDone = false;
    final authCompleter = Completer<bool>();
    Uint8List authBuffer = Uint8List(0);

    socket.listen(
      (chunk) {
        if (!authDone) {
          final combined = Uint8List.fromList([...authBuffer, ...chunk]);
          final newlineIndex = combined.indexOf(0x0A);
          if (newlineIndex == -1) {
            authBuffer = combined;
            return;
          }
          authDone = true;
          final line = utf8.decode(combined.sublist(0, newlineIndex)).trim();
          _pending.add(combined.sublist(newlineIndex + 1));
          if (!authCompleter.isCompleted) authCompleter.complete(line == 'OK');
          return;
        }
        _pending.add(chunk);
        final extracted = extractLiveFrames(_pending.toBytes());
        _pending.clear();
        _pending.add(extracted.remaining);
        for (final frame in extracted.frames) {
          onFrame(frame);
        }
      },
      onDone: () {
        if (!authCompleter.isCompleted) authCompleter.complete(false);
        onDisconnected();
      },
      onError: (_) {
        if (!authCompleter.isCompleted) authCompleter.complete(false);
        onDisconnected();
      },
      cancelOnError: true,
    );

    socket.write('${pin.trim()}\n');

    final ok = await authCompleter.future.timeout(
      const Duration(seconds: 6),
      onTimeout: () => false,
    );
    if (!ok) {
      await close();
      throw RemoteControlException(
        'Bilgisayar bağlantıyı reddetti (yanlış PIN ya da çok fazla '
        'yanlış deneme).',
      );
    }
    return observedFingerprint ?? pinnedFingerprint;
  }

  void sendCommand(Map<String, dynamic> cmd) {
    final socket = _socket;
    if (socket == null) return;
    try {
      socket.write('${jsonEncode(cmd)}\n');
    } catch (_) {
      // Baglanti tam bu sirada koptuyse sessizce yoksay - onDisconnected
      // zaten cagrilacak/cagrildi.
    }
  }

  void sendMove(double normalizedX, double normalizedY) =>
      sendCommand({'t': 'mv', 'x': normalizedX, 'y': normalizedY});

  void sendMouseDown({String button = 'left'}) => sendCommand({'t': 'down', 'b': button});

  void sendMouseUp({String button = 'left'}) => sendCommand({'t': 'up', 'b': button});

  void sendClick({String button = 'left'}) => sendCommand({'t': 'click', 'b': button});

  void sendScroll(double dy) => sendCommand({'t': 'scroll', 'dy': dy});

  void sendKeyTap(String keyName) {
    sendCommand({'t': 'kd', 'k': keyName});
    sendCommand({'t': 'ku', 'k': keyName});
  }

  void sendText(String text) {
    if (text.isEmpty) return;
    sendCommand({'t': 'text', 's': text});
  }

  Future<void> close() async {
    final socket = _socket;
    _socket = null;
    if (socket != null) {
      try {
        await socket.close();
      } catch (_) {}
    }
  }
}
