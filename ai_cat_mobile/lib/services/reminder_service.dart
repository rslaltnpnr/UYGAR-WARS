import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Kullanicinin "N dakika sonra hatirlat" seklinde kurdugu tekil
/// hatirlaticilari yerel bildirim (flutter_local_notifications) olarak
/// zamanlar. Bulut/Firebase gerektirmez - tamamen cihaz uzerinde calisir.
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

  Future<void> scheduleReminder({
    required Duration delay,
    required String message,
  }) async {
    await _ensureInitialized();
    final id = _nextId++;
    final fireTime = tz.TZDateTime.now(tz.UTC).add(delay);
    const androidDetails = AndroidNotificationDetails(
      'reminders',
      'Hatırlatıcılar',
      channelDescription: 'Kurduğunuz hatırlatıcılar burada görünür.',
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: androidDetails);
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
}
