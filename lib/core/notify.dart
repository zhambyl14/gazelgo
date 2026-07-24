import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Локал уведомлениелер: жаңа заказ, заказ статусы.
/// Қосымша ашық/минимизацияда тұрғанда жұмыс істейді (Android foreground-та
/// FCM жүйелік баннер шығармайтындықтан, [Push] осы арқылы көрсетеді).
/// (Қосымша толық жабық кезде push үшін FCM қажет — README қараңыз.)
class Notify {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  /// Локал уведомлениені басқанда шақырылады (навигация үшін). Payload —
  /// FCM `data` картасының JSON жолы. Қосымша (main.dart) орнатады, себебі
  /// core қабаты features экрандарына тәуелді болмауы керек.
  static void Function(String? payload)? onSelect;

  /// Жоғары маңыздылықтағы канал — экранға ҚАЛҚЫП ШЫҒАТЫН (heads-up), дыбысты
  /// уведомлениелер. FCM push та (қосымша жабық кезде) осы каналды қолданады
  /// (AndroidManifest-те default_notification_channel_id = осы id). Каналды
  /// қосымша алғаш іске қосылғанда МІНДЕТТІ ТҮРДЕ жоғары маңыздылықпен құрамыз
  /// (әйтпесе FCM өзі әдепкі маңыздылықпен құрып, heads-up болмай қалады).
  static const _channelId = 'gazelgo_high';
  static const _channel = AndroidNotificationChannel(
    _channelId,
    'Tasu хабарламалары',
    description: 'Жаңа заказдар, өтінімдер, статус өзгерістері',
    importance: Importance.high,
  );

  static Future<void> init() async {
    if (kIsWeb || _ready) return;
    try {
      const android = AndroidInitializationSettings('ic_stat_notify');
      const ios = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      await _plugin.initialize(
        const InitializationSettings(android: android, iOS: ios),
        onDidReceiveNotificationResponse: (resp) =>
            onSelect?.call(resp.payload),
      );
      final androidImpl = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await androidImpl?.createNotificationChannel(_channel);
      await androidImpl?.requestNotificationsPermission();
      _ready = true;
    } catch (_) {
      // уведомление қолжетімсіз болса да, қосымша жұмысын жалғастырады
    }
  }

  static Future<void> show(
    String title,
    String body, {
    int id = 0,
    String? payload,
  }) async {
    if (kIsWeb || !_ready) return;
    try {
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Tasu хабарламалары',
          channelDescription: 'Жаңа заказдар, өтінімдер, статус өзгерістері',
          importance: Importance.high,
          priority: Priority.high,
          icon: 'ic_stat_notify',
          color: Color(0xFFFFC400),
        ),
        // iOS-та presentSound анық true болмаса, локал хабарлама
        // дыбыссыз (тек баннер) көрсетіледі — flutter_local_notifications-тың
        // белгілі мінезі, null әдепкі мән дыбысты өшіріп тастайды.
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          sound: 'default',
        ),
      );
      await _plugin.show(id, title, body, details, payload: payload);
    } catch (_) {}
  }
}
