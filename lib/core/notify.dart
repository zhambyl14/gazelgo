import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Локал уведомлениелер: жаңа заказ, VIP тарату, заказ статусы.
/// Қосымша ашық/минимизацияда тұрғанда жұмыс істейді.
/// (Қосымша толық жабық кезде push үшін FCM қажет — README қараңыз.)
class Notify {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static Future<void> init() async {
    if (kIsWeb || _ready) return;
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const ios = DarwinInitializationSettings();
      await _plugin.initialize(
        const InitializationSettings(android: android, iOS: ios),
      );
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      _ready = true;
    } catch (_) {
      // уведомление қолжетімсіз болса да, қосымша жұмысын жалғастырады
    }
  }

  static Future<void> show(String title, String body, {int id = 0}) async {
    if (kIsWeb || !_ready) return;
    try {
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          'gazelgo_main',
          'GazelGo хабарламалары',
          channelDescription: 'Жаңа заказдар мен статус өзгерістері',
          importance: Importance.high,
          priority: Priority.high,
          color: Color(0xFFFFC400),
        ),
        iOS: DarwinNotificationDetails(),
      );
      await _plugin.show(id, title, body, details);
    } catch (_) {}
  }
}
