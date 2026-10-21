import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart'
    show AppLifecycleState, WidgetsBinding, WidgetsBindingObserver;

import 'firebase_options.dart';
import 'notify.dart';
import 'order_alert.dart';
import 'repo.dart';
import 'web_notify.dart';

/// Web-те push-ты қосу үшін пайдаланушыдан не керек (баннер көрсетеді).
enum WebPushPrompt {
  /// Браузер рұқсат сұрауға дайын — «Хабарламаларды қосу» батырмасы.
  permission,

  /// iPhone/iPad Safari: web push тек «Басты экранға қосылған» (PWA)
  /// қосымшада жұмыс істейді — соны үйрететін нұсқау.
  install,
}

/// Қосымша толық жабық болса да жеткізілетін push-хабарландырулар (FCM).
///
/// [Notify] (flutter_local_notifications) тек қосымша тірі/фонда тұрғанда
/// жұмыс істейді — модератор газелист өтінімін дереу көруі маңызды болғандықтан
/// (телефон құлыпты, қосымша жабық болса да), нағыз push қажет.
///
/// Web (gazelgo.pages.dev, PWA) те қолдайды: токен `firebase-messaging-sw.js`
/// service worker арқылы алынады, рұқсатты пайдаланушы батырманы басып
/// береді ([requestWebPermission] — iOS рұқсатты тек басу арқылы сұратады).
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
  static bool _firebaseReady = false;
  static Future<void>? _initFuture;
  static bool _ready = false;
  static int _fgId = 100; // foreground локал уведомлениелердің өспелі id-і

  /// Токен ҚАЙ пайдаланушыға тіркелгені. Бір телефонда аккаунт ауысса
  /// (мыс. орындаушыдан клиентке), токен ЖАҢА иесіне қайта тіркелуі керек —
  /// әйтпесе сервер оны әлі ескі иесі деп санап, клиентке орындаушының
  /// «Жаңа заказ» push-ы келеді (нақты табылған ақау).
  static String? _syncedUid;

  /// Web-те push қосу үшін пайдаланушыдан қажет әрекет (null — ештеңе
  /// керек емес: қосулы, бас тартылған не браузер қолдамайды). Баннер
  /// ([WebPushBanner]) осыны тыңдайды.
  static final webPrompt = ValueNotifier<WebPushPrompt?>(null);

  /// Нағыз push (FCM) жұмыс істеп тұр ма? Қосымша ішіндегі қосарланған локал
  /// уведомлениелер осыны тексереді: push бар болса — оқиға туралы сервер
  /// БІР РЕТ, пайдаланушының тілінде хабарлайды.
  static bool get isActive => _ready;

  /// Хабарламаны басып қосымшаны ашқанда шақырылады (навигация үшін). FCM
  /// `data` картасын береді. Қосымша (main.dart) орнатады — core қабаты
  /// features экрандарына тәуелді болмауы үшін.
  static void Function(Map<String, dynamic> data)? onOpen;

  static Future<void> init() async {
    if (!FirebaseOpts.isConfigured) return;
    // Бастапқы баптау бір рет қана, ал ТОКЕН СИНХРОНЫ әр кіруде қайталанады
    // (төменде) — сол себепті ерте `return` жасамаймыз.
    if (_firebaseReady) {
      await syncToken();
      return;
    }

    final running = _initFuture;
    if (running != null) {
      await running;
      return;
    }

    final future = _initInternal();
    _initFuture = future;
    try {
      await future;
    } finally {
      if (identical(_initFuture, future)) _initFuture = null;
    }
  }

  static Future<void> _initInternal() async {
    try {
      await Firebase.initializeApp(options: FirebaseOpts.currentPlatform);
    } catch (e) {
      debugPrint('Push: Firebase initialization failed: $e');
      // Firebase жобасы толық бапталмаған/платформа қолдамайды — өшірулі
      // қалады, қосымша бұзылмайды.
      return;
    }

    if (!_lifecycleAttached) {
      _lifecycleAttached = true;
      WidgetsBinding.instance.addObserver(_PushLifecycle());
    }

    final messaging = FirebaseMessaging.instance;

    if (kIsWeb) {
      await _initWeb(messaging);
      return;
    }

    _initStarted = true;
    _firebaseReady = true;
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Навигация мен foreground баннер листенерлерін БАСҚА ҚАДАМДАРДАН БҰРЫН
    // тіркейміз: permission сұрау не getToken() желі/құрылғы себебімен
    // сәтсіз аяқталса да (бөлек try-catch төменде), осы екеуі әрқашан
    // жұмыс істеуі керек.
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
    } catch (_) {}
    await syncToken();
  }

  /// Web: браузер push-ты қолдаса ғана іске қосылады. Рұқсат БҰРЫН берілген
  /// болса — бірден токен тіркейміз; әлі сұралмаса — баннер көрсетеміз
  /// (iOS Safari рұқсатты тек пайдаланушы батырманы басқанда сұратады).
  static Future<void> _initWeb(FirebaseMessaging messaging) async {
    bool supported = false;
    try {
      supported = await messaging.isSupported();
    } catch (_) {}
    if (!supported) {
      // iPhone Safari-де push тек «Басты экранға қосылған» қосымшада бар.
      if (defaultTargetPlatform == TargetPlatform.iOS && !webIsStandalone()) {
        webPrompt.value = WebPushPrompt.install;
      }
      return;
    }

    _initStarted = true;
    _firebaseReady = true;
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen((m) => onOpen?.call(m.data));
    await _refreshWebPermission();
  }

  static Future<void> _refreshWebPermission() async {
    AuthorizationStatus status;
    try {
      status = (await FirebaseMessaging.instance.getNotificationSettings())
          .authorizationStatus;
    } catch (_) {
      return;
    }
    switch (status) {
      case AuthorizationStatus.authorized:
      case AuthorizationStatus.provisional:
        webPrompt.value = null;
        await syncToken();
      case AuthorizationStatus.notDetermined:
        webPrompt.value = WebPushPrompt.permission;
      case AuthorizationStatus.denied:
        webPrompt.value = null;
    }
  }

  /// Web баннеріндегі «Қосу» батырмасы. Пайдаланушы басқан сәтте ғана
  /// шақырылуы керек (Safari рұқсат терезесін тек осылай көрсетеді).
  static Future<void> requestWebPermission() async {
    if (!kIsWeb || !_initStarted) return;
    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (e) {
      debugPrint('Push: web permission request failed: $e');
    }
    _syncedUid = null;
    await _refreshWebPermission();
  }

  /// FCM токенін АҒЫМДАҒЫ пайдаланушыға тіркеу. Кірген сайын шақырылады:
  /// бір телефонда аккаунт ауысса, токен жаңа иесіне көшеді (`save_push_token`
  /// сервер жағында `on conflict (token)` арқылы иесін ауыстырады).
  static Future<void> syncToken() async {
    if (!_initStarted) return;
    final uid = Repo.uid;
    if (uid == null || uid == _syncedUid) return;
    try {
      if (kIsWeb) {
        final s = await FirebaseMessaging.instance.getNotificationSettings();
        if (s.authorizationStatus != AuthorizationStatus.authorized &&
            s.authorizationStatus != AuthorizationStatus.provisional) {
          return;
        }
      }
      final token = await _fetchToken();
      if (token == null) throw StateError('FCM token is null');
      // `_saveToken` қатені жұтады — мұнда тікелей шақырамыз, сәтсіз болса
      // төмендегі `_ready` орнатылмай, резерв уведомлениелер қосулы қалады.
      await Repo.savePushToken(token, _platformName);
      _syncedUid = uid;
      _retryAttempt = 0;
      // Токен нақты сақталған соң ғана «push жұмыс істейді» деп есептейміз:
      // әйтпесе (Play Services жоқ, желі жоқ т.б.) сервер бұл құрылғыға
      // жете алмайды, ал қосымша ішіндегі резерв уведомлениелер де
      // өшірулі тұрып, пайдаланушы ЕШТЕҢЕ алмай қалатын еді.
      _ready = true;
    } catch (e) {
      debugPrint('Push: token sync failed: $e');
      _scheduleRetry();
    }
  }

  /// iOS-та FCM токенін APNs токенінсіз алу мүмкін емес, ал APNs токені
  /// қосымша ашылғаннан кейін бірнеше секундта ғана келеді — `getToken()`
  /// содан бұрын шақырылса `apns-token-not-set` қатесімен құлайды. Бұрын
  /// осы қате жұтылып, қайталанбайтын: iPhone-да токен серверге мүлдем
  /// тіркелмей, push келмей қалатын (нақты табылған ақау). Сондықтан
  /// APNs токенін 20 секундқа дейін күтеміз.
  static Future<String?> _fetchToken() async {
    final messaging = FirebaseMessaging.instance;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      for (var i = 0; i < 20; i++) {
        String? apns;
        try {
          apns = await messaging.getAPNSToken();
        } catch (_) {}
        if (apns != null) break;
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
    return messaging.getToken();
  }

  static bool _lifecycleAttached = false;
  static int _retryAttempt = 0;
  static Timer? _retryTimer;

  /// Токенді тіркеу сәтсіз болса (желі жоқ, APNs кешікті) — қайта
  /// байқаймыз: 10 с, 30 с, 90 с, 5 мин, 15 мин.
  static void _scheduleRetry() {
    const delays = [10, 30, 90, 300, 900];
    if (_retryAttempt >= delays.length) return;
    _retryTimer?.cancel();
    final wait = Duration(seconds: delays[_retryAttempt++]);
    _retryTimer = Timer(wait, () => unawaited(syncToken()));
  }

  static DateTime? _lastResume;

  /// Қосымша фоннан оралғанда токенді серверге қайта бекітеді (кемінде
  /// 10 минут сайын): сервер ескірген токенді өшірсе не желі үзілсе де,
  /// келесі ашылғанда push қайта қалпына келеді.
  static void onAppResumed() {
    if (!_initStarted) return;
    final now = DateTime.now();
    final last = _lastResume;
    if (last != null && now.difference(last) < const Duration(minutes: 10)) {
      return;
    }
    _lastResume = now;
    _syncedUid = null;
    unawaited(syncToken());
  }

  /// Аккаунттан шыққанда токенді серверден өшіру: әйтпесе бұл құрылғыға
  /// шыққан пайдаланушының push-ы келе береді (жаңа иесі кірмей тұрып та).
  static Future<void> clearToken() async {
    _syncedUid = null;
    _ready = false;
    if (!_initStarted) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await Repo.deletePushToken(token);
    } catch (_) {}
  }

  static String get _platformName =>
      kIsWeb ? 'web' : defaultTargetPlatform.name;

  /// Foreground хабарды көрсету. iOS-та жүйе баннерді өзі шығарады
  /// (жоғарыдағы presentation options), сол себепті notification payload
  /// бар хабарды iOS-та ҚАЙТА көрсетпейміз (қосарланбау үшін). Android-та
  /// FCM foreground-та баннер шығармайды — Notify (local) арқылы көрсетеміз.
  /// Web-те қосымша ашық тұрғанда браузер де өзі көрсетпейді —
  /// service worker арқылы жүйелік хабарландыру шығарамыз.
  static void _onForegroundMessage(RemoteMessage m) {
    final n = m.notification;
    final title = n?.title ?? m.data['title'] as String?;
    final body = n?.body ?? m.data['body'] as String? ?? '';
    if (title == null || title.isEmpty) return;
    // Лента экранда тұрса, жаңа заказды ол өзі көрсетеді (дыбыс, жарқыл) —
    // хабарламаны қайта шығарсақ, дыбыс екі рет естілер еді.
    if (m.data['type'] == 'new_order' && OrderAlert.feedVisible) return;

    if (kIsWeb) {
      showWebNotification(title, body);
      return;
    }
    final payload = jsonEncode(m.data);
    if (n == null || defaultTargetPlatform == TargetPlatform.android) {
      Notify.show(title, body, id: _fgId++, payload: payload);
    }
  }

  static Future<void> _saveToken(String token) async {
    if (Repo.uid == null) return;
    try {
      await Repo.savePushToken(token, _platformName);
    } catch (e) {
      debugPrint('Push: refreshed token RPC failed: $e');
    }
  }
}

/// Қосымша фоннан оралғанда токенді қайта бекітеді ([Push.onAppResumed]).
class _PushLifecycle with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) Push.onAppResumed();
  }
}
