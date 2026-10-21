import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'lang.dart';
import 'repo.dart';
import 'theme.dart';

/// Белсенді заказ кезінде орындаушының орнын ТҮЗ жіберу — клиент көлікті
/// картада Yandex Go-дағыдай жылжып келе жатқан күйде көреді.
///
/// НЕГЕ ЖЕКЕ ҚЫЗМЕТ: орындаушы A/B батырмасымен 2GIS/Яндекс навигаторды
/// ашады — сол сәтте Tasu фонға кетеді. Бұрынғы таймер +
/// getCurrentPosition фонда тоқтайтын (Android 10+ пен iOS фондағы
/// локацияны бұғаттайды) — клиенттің картасында көлік «қатып» қалатын.
/// Енді белсенді заказ бар кезде:
///  • Android — орын foreground-service арқылы алынады (хабарландыру
///    тақтасында «Tasu · белсенді заказ» тұрады), Tasu фонда тұрса да
///    орын жіберіле береді;
///  • iOS — фондағы локация режимі (жоғарыда көк белгі);
///  • Web — тек бет ашық тұрғанда.
/// Заказ аяқталғанда/тоқтатылғанда [stop] — қызмет бірден тоқтайды.
/// Бос орындаушының орны фонда ЕШҚАШАН жиналмайды.
class TripTracker {
  TripTracker._();

  static StreamSubscription<Position>? _sub;
  static Timer? _heartbeat;
  static String? _orderId;
  static Position? _last;
  static Position? _lastSent;
  static DateTime? _lastSentAt;
  static bool _sending = false;

  /// Қай заказ үшін жұмыс істеп тұр (жоқ болса null).
  static String? get orderId => _orderId;

  /// Орындаушының ӨЗ соңғы GPS нүктесі (әр жаңа нүктеде жаңарады) —
  /// белсенді заказ экраны картада өз орны мен A-ға дейінгі жолды тірі
  /// көрсету үшін тыңдайды. Ағын тоқтаса — null.
  static final ValueNotifier<Position?> position = ValueNotifier(null);

  /// Белсенді заказ басталды/жалғасып тұр — орын ағынын қосады. Бірдей
  /// заказ үшін қайта шақыру қауіпсіз (ештеңе өзгермейді).
  static Future<void> start(String orderId) async {
    if (_orderId == orderId && _sub != null) return;
    await stop();
    final perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return; // рұқсатты экран өзі сұрайды (түсіндірмесімен)
    }
    if (!await Geolocator.isLocationServiceEnabled()) return;
    _orderId = orderId;
    _sub = Geolocator.getPositionStream(
      locationSettings: _settings(),
    ).listen(_onPosition, onError: (_) {});
    // Тұрып тұрғанда (клиентті күтіп) ағын үнсіз — клиент «байланыс үзілді»
    // деп ойламауы үшін соңғы орынды мезгіл-мезгіл қайталап жібереміз.
    _heartbeat = Timer.periodic(const Duration(seconds: 25), (_) {
      final p = _last;
      if (p != null) _send(p, force: true);
    });
  }

  /// Заказ жоқ — ағын мен foreground-service тоқтайды.
  static Future<void> stop() async {
    _heartbeat?.cancel();
    _heartbeat = null;
    final s = _sub;
    _sub = null;
    _orderId = null;
    _last = null;
    position.value = null;
    _lastSent = null;
    _lastSentAt = null;
    await s?.cancel();
  }

  static LocationSettings _settings() {
    if (kIsWeb) {
      return const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
          intervalDuration: const Duration(seconds: 5),
          foregroundNotificationConfig: ForegroundNotificationConfig(
            notificationTitle: t('Tasu · белсенді заказ'),
            notificationText: t('Орныңыз клиентке картада көрініп тұр'),
            notificationChannelName: t('Белсенді заказ'),
            notificationIcon: const AndroidResource(name: 'ic_stat_notify'),
            setOngoing: true,
            enableWakeLock: true,
            color: Gz.yellow,
          ),
        );
      case TargetPlatform.iOS:
        return AppleSettings(
          accuracy: LocationAccuracy.high,
          activityType: ActivityType.automotiveNavigation,
          distanceFilter: 10,
          pauseLocationUpdatesAutomatically: false,
          showBackgroundLocationIndicator: true,
          allowBackgroundLocationUpdates: true,
        );
      default:
        return const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        );
    }
  }

  static void _onPosition(Position p) {
    _last = p;
    position.value = p;
    _send(p);
  }

  /// Серверге жіберу жиілігі: кемінде 5 с аралықпен, 15 м жылжығанда не
  /// 25 с өткенде (трафик пен батареяны үнемдеу үшін).
  static Future<void> _send(Position p, {bool force = false}) async {
    if (_sending || _orderId == null) return;
    final now = DateTime.now();
    final at = _lastSentAt;
    final prev = _lastSent;
    if (!force && at != null && prev != null) {
      final secs = now.difference(at).inSeconds;
      if (secs < 5) return;
      final moved = Geolocator.distanceBetween(
        prev.latitude,
        prev.longitude,
        p.latitude,
        p.longitude,
      );
      if (moved < 15 && secs < 25) return;
    }
    _sending = true;
    try {
      await Repo.updateExecutorLocation(
        p.latitude,
        p.longitude,
        heading: p.heading >= 0 ? p.heading : null,
        speed: p.speed >= 0 ? p.speed : null,
      );
      _lastSent = p;
      _lastSentAt = now;
    } catch (_) {
      // желі уақытша жоқ — келесі нүктеде қайталанады
    } finally {
      _sending = false;
    }
  }
}
