import 'dart:convert';

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
  static int _fgId = 100; // foreground локал уведомлениелердің өспелі id-і

  /// Хабарламаны басып қосымшаны ашқанда шақырылады (навигация үшін). FCM
  /// `data` картасын береді. Қосымша (main.dart) орнатады — core қабаты
  /// features экрандарына тәуелді болмауы үшін.
  static void Function(Map<String, dynamic> data)? onOpen;

  static Future<void> init() async {
    if (kIsWeb || _initStarted || !FirebaseOpts.isConfigured) return;
    _initStarted = true;
    try {
      await Firebase.initializeApp(options: FirebaseOpts.currentPlatform);
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);

      // iOS: қосымша АШЫҚ (foreground) тұрғанда да жүйелік баннер + дыбыс +
      // белгіше көрсетілсін. Бұл болмаса, iOS foreground push-ты мүлдем
      // көрсетпейді (firebase_messaging делегаты хабарды жасырады).
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      final token = await messaging.getToken();
      if (token != null) await _saveToken(token);
      messaging.onTokenRefresh.listen(_saveToken);

      // 1) Қосымша АШЫҚ тұрғанда келген хабар.
      FirebaseMessaging.onMessage.listen(_onForegroundMessage);

      // 2) Хабарламаны басып қосымша фоннан ашылды.
      FirebaseMessaging.onMessageOpenedApp.listen((m) => onOpen?.call(m.data));

      // 3) Қосымша ТОЛЫҚ ЖАБЫҚ болғанда хабарламадан ашылды.
      final initial = await messaging.getInitialMessage();
      if (initial != null) onOpen?.call(initial.data);
    } catch (_) {
      // Firebase жобасы толық бапталмаған/платформа қолдамайды — өшірулі
      // қалады, қосымша бұзылмайды.
    }
  }

  /// Foreground хабарды көрсету. iOS-та жүйе баннерді өзі шығарады
  /// (жоғарыдағы presentation options), сол себепті notification payload
  /// бар хабарды iOS-та ҚАЙТА көрсетпейміз (қосарланбау үшін). Android-та
  /// FCM foreground-та баннер шығармайды — Notify (local) арқылы көрсетеміз.
  static void _onForegroundMessage(RemoteMessage m) {
    final n = m.notification;
    final payload = jsonEncode(m.data);
    if (n == null) {
      // Деректі ғана (data-only) хабар — жүйе ешбір платформада өзі
      // көрсетпейді, сол себепті екеуінде де local арқылы шығарамыз.
      final title = m.data['title'] as String?;
      final body = m.data['body'] as String? ?? '';
      if (title != null && title.isNotEmpty) {
        Notify.show(title, body, id: _fgId++, payload: payload);
      }
      return;
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      Notify.show(
        n.title ?? 'Tasu',
        n.body ?? '',
        id: _fgId++,
        payload: payload,
      );
    }
  }

  static Future<void> _saveToken(String token) async {
    try {
      await Repo.savePushToken(token, defaultTargetPlatform.name);
    } catch (_) {}
  }
}
