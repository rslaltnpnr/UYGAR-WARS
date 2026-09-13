import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'settings_service.dart';
import 'vibration_pattern.dart';

/// Yerel bildirimleri (flutter_local_notifications) yonetir: kullanicinin
/// "N dakika sonra hatirlat" seklinde kurdugu tekil hatirlaticilari
/// zamanlar, ve eslesik bilgisayarda bir hata/uyari olustugunda anlik
/// bildirim gosterir (bkz. showAlert). Bulut/Firebase gerektirmez -
/// tamamen cihaz uzerinde calisir.
///
/// Zamanlama gercek gecen sureye (Duration) gore yapildigi icin cihazin
/// yerel saat dilimini tam olarak bilmeye gerek yok; TZDateTime hesabi
/// UTC uzerinden yapilir (N dakika sonra = N dakika sonra, dilimden
/// bagimsiz).
class ReminderService {
  static final ReminderService _instance = ReminderService._internal();

  factory ReminderService() => _instance;

  ReminderService._internal();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  int _nextId = 0;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _plugin.initialize(initSettings);
    _initialized = true;
  }

  /// Android 13+ icin bildirim izni ister. Eski surumlerde izin gerekmez
  /// (true doner). Kullanici reddederse hatirlatici kurulamaz.
  Future<bool> requestPermission() async {
    await _ensureInitialized();
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl == null) return true;
    final granted = await androidImpl.requestNotificationsPermission();
    return granted ?? true;
  }

  Future<VibrationPatternOption> _vibrationOption() async {
    final prefs = await SharedPreferences.getInstance();
    return SettingsService(prefs).notificationVibrationPattern;
  }

  Future<void> scheduleReminder({
    required Duration delay,
    required String message,
  }) async {
    await _ensureInitialized();
    final id = _nextId++;
    final fireTime = tz.TZDateTime.now(tz.UTC).add(delay);
    final vibration = await _vibrationOption();
    // Android 8+'ta bir kanalin titresim ayari, ilk olusturuldugunda
    // kilitlenir - ayni kanal id'sine sonradan farkli bir
    // AndroidNotificationDetails gonderilmesi hicbir sey degistirmez.
    // Bu yuzden kanal id'sine secilen paterni ekliyoruz: kullanici
    // paterni degistirdiginde yeni (ve gercekten farkli davranan) bir
    // kanal olusur, eski kanal kullanilmaz kalir ama zararsizdir.
    final androidDetails = AndroidNotificationDetails(
      'reminders_${vibration.value}',
      'Hatırlatıcılar',
      channelDescription: 'Kurduğunuz hatırlatıcılar burada görünür.',
      importance: Importance.high,
      priority: Priority.high,
      enableVibration: vibration.enableVibration,
      vibrationPattern: vibration.pattern,
    );
    final details = NotificationDetails(android: androidDetails);
    await _plugin.zonedSchedule(
      id,
      'Hatırlatıcı',
      message,
      fireTime,
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      // Yalnizca eski iOS surumleri icin gerekli (Android'de kullanilmaz);
      // paket bu parametreyi platform bagimsiz olarak zorunlu kiliyor.
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  /// Eslesik bilgisayarda olusan bir hata/uyariyi hemen bildirim olarak
  /// gosterir (bkz. HomeScreen'in periyodik /alerts yoklamasi).
  Future<void> showAlert({required String title, required String message}) async {
    await _ensureInitialized();
    final vibration = await _vibrationOption();
    final androidDetails = AndroidNotificationDetails(
      'desktop_alerts_${vibration.value}',
      'Masaüstü Uyarıları',
      channelDescription:
          'Eşleşen bilgisayarda oluşan hata/uyarılar burada görünür.',
      importance: Importance.high,
      priority: Priority.high,
      enableVibration: vibration.enableVibration,
      vibrationPattern: vibration.pattern,
    );
    final details = NotificationDetails(android: androidDetails);
    await _plugin.show(_nextId++, title, message, details);
  }
}
