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
  static bool _ready = false;
  static int _fgId = 100; // foreground локал уведомлениелердің өспелі id-і

  /// Токен ҚАЙ пайдаланушыға тіркелгені. Бір телефонда аккаунт ауысса
  /// (мыс. орындаушыдан клиентке), токен ЖАҢА иесіне қайта тіркелуі керек —
  /// әйтпесе сервер оны әлі ескі иесі деп санап, клиентке орындаушының
  /// «Жаңа заказ» push-ы келеді (нақты табылған ақау).
  static String? _syncedUid;

  /// Нағыз push (FCM) жұмыс істеп тұр ма? Қосымша ішіндегі қосарланған локал
  /// уведомлениелер осыны тексереді: push бар болса — оқиға туралы сервер
  /// БІР РЕТ, пайдаланушының тілінде хабарлайды.
  static bool get isActive => _ready;

  /// Хабарламаны басып қосымшаны ашқанда шақырылады (навигация үшін). FCM
  /// `data` картасын береді. Қосымша (main.dart) орнатады — core қабаты
  /// features экрандарына тәуелді болмауы үшін.
  static void Function(Map<String, dynamic> data)? onOpen;

  static Future<void> init() async {
    if (kIsWeb || !FirebaseOpts.isConfigured) return;
    // Бастапқы баптау бір рет қана, ал ТОКЕН СИНХРОНЫ әр кіруде қайталанады
    // (төменде) — сол себепті ерте `return` жасамаймыз.
    if (_initStarted) {
      await syncToken();
      return;
    }
    _initStarted = true;
    try {
      await Firebase.initializeApp(options: FirebaseOpts.currentPlatform);
    } catch (_) {
      // Firebase жобасы толық бапталмаған/платформа қолдамайды — өшірулі
      // қалады, қосымша бұзылмайды.
      return;
    }

    final messaging = FirebaseMessaging.instance;
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Навигация мен foreground баннер листенерлерін БАСҚА ҚАДАМДАРДАН БҰРЫН
    // тіркейміз: permission сұрау не getToken() желі/құрылғы себебімен
    // сәтсіз аяқталса да (бөлек try-catch төменде), осы екеуі әрқашан
    // жұмыс істеуі керек — әйтпесе пуш жүйелік tray арқылы келгенімен,
    // басқанда навигация болмай қалады (бір try-блокта бәрі бірге тұрғанда
    // осы дәл осылай сынған еді).
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen((m) => onOpen?.call(m.data));
    try {
      final initial = await messaging.getInitialMessage();
      if (initial != null) onOpen?.call(initial.data);
    } catch (_) {}

    try {
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      // iOS: қосымша АШЫҚ (foreground) тұрғанда да жүйелік баннер + дыбыс +
      // белгіше көрсетілсін. Бұл болмаса, iOS foreground push-ты мүлдем
      // көрсетпейді (firebase_messaging делегаты хабарды жасырады).
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (_) {}

    try {
      messaging.onTokenRefresh.listen((t) {
        _syncedUid = null; // жаңа токен — қайта тіркеу қажет
        _saveToken(t);
      });
      await syncToken();
    } catch (_) {}
  }

  /// FCM токенін АҒЫМДАҒЫ пайдаланушыға тіркеу. Кірген сайын шақырылады:
  /// бір телефонда аккаунт ауысса, токен жаңа иесіне көшеді (`save_push_token`
  /// сервер жағында `on conflict (token)` арқылы иесін ауыстырады).
  static Future<void> syncToken() async {
    if (kIsWeb || !_initStarted) return;
    final uid = Repo.uid;
    if (uid == null || uid == _syncedUid) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      // `_saveToken` қатені жұтады — мұнда тікелей шақырамыз, сәтсіз болса
      // төмендегі `_ready` орнатылмай, резерв уведомлениелер қосулы қалады.
      await Repo.savePushToken(token, defaultTargetPlatform.name);
      _syncedUid = uid;
      // Токен нақты сақталған соң ғана «push жұмыс істейді» деп есептейміз:
      // әйтпесе (Play Services жоқ, желі жоқ т.б.) сервер бұл құрылғыға
      // жете алмайды, ал қосымша ішіндегі резерв уведомлениелер де
      // өшірулі тұрып, пайдаланушы ЕШТЕҢЕ алмай қалатын еді.
      _ready = true;
    } catch (_) {}
  }

  /// Аккаунттан шыққанда токенді серверден өшіру: әйтпесе бұл құрылғыға
  /// шыққан пайдаланушының push-ы келе береді (жаңа иесі кірмей тұрып та).
  static Future<void> clearToken() async {
    _syncedUid = null;
    if (kIsWeb || !_initStarted) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await Repo.deletePushToken(token);
    } catch (_) {}
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
