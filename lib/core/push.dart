import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'firebase_options.dart';
import 'notify.dart';
import 'repo.dart';

/// Қосымша толық жабық болса да жеткізілетін push-хабарландырулар (FCM).
///
/// [Notify] (flutter_local_notifications) тек қосымша тірі/фонда тұрғанда
/// жұмыс істейді — модератор газелист өтінімін дереу көруі маңызды болғандықтан
/// (телефон құлыпты, қосымша жабық болса да), нағыз push қажет.
///
/// Firebase әлі бапталмаса ([FirebaseOpts.isConfigured] false) — үнсіз
/// өшірулі күйде қалады, қосымша жұмысын жалғастырады.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Notification payload-ы бар хабарды жүйенің өзі (Android/iOS) автоматты
  // көрсетеді — қосымша фонда/жабық тұрғанда бөлек әрекет қажет емес.
}

class Push {
  static bool _initStarted = false;

  static Future<void> init() async {
    if (kIsWeb || _initStarted || !FirebaseOpts.isConfigured) return;
    _initStarted = true;
    try {
      await Firebase.initializeApp(options: FirebaseOpts.currentPlatform);
      FirebaseMessaging.onBackgroundMessage(
          firebaseMessagingBackgroundHandler);

      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);

      final token = await messaging.getToken();
      if (token != null) await _saveToken(token);
      messaging.onTokenRefresh.listen(_saveToken);

      // Қосымша алдыңғы планда (ашық) тұрғанда FCM жүйелік баннер
      // көрсетпейді — сол сәтте бар Notify арқылы көрсетеміз.
      FirebaseMessaging.onMessage.listen((m) {
        final n = m.notification;
        if (n != null) {
          Notify.show(n.title ?? 'GazelGo', n.body ?? '', id: 3);
        }
      });
    } catch (_) {
      // Firebase жобасы толық бапталмаған/платформа қолдамайды — өшірулі
      // қалады, қосымша бұзылмайды.
    }
  }

  static Future<void> _saveToken(String token) async {
    try {
      await Repo.savePushToken(token, defaultTargetPlatform.name);
    } catch (_) {}
  }
}
