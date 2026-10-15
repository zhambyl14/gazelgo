import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/geo.dart';
import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/phone.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/map_widgets.dart';
import '../../shared/widgets.dart';
import '../support/support_screen.dart';

/// Орындаушының белсенді заказ экраны: клиент, маршрут, статус ауыстыру.
///
/// Экран құрылымы (жоғарыдан төмен) — орындаушы «қазір не істеу керек?»
/// дегенге бір қарағанда жауап алуы үшін:
///   1. Баға + сапар кезеңдерінің ПРОГРЕСІ (қай қадамда тұрмын).
///   2. «Келесі әрекет» карточкасы — бір сөйлеммен нұсқау + негізгі батырма.
///   3. Клиент (қоңырау), карта, навигациясы бар маршрут, жүк/түсініктеме.
class ActiveOrderScreen extends StatefulWidget {
  final String orderId;
  const ActiveOrderScreen({super.key, required this.orderId});

  @override
  State<ActiveOrderScreen> createState() => _ActiveOrderScreenState();
}

class _ActiveOrderScreenState extends State<ActiveOrderScreen> {
  bool _reviewShown = false;

  /// Заказ ағыны БІР РЕТ құрылады: build ішінде құрылса, әр қайта салуда
  /// жаңа polling басталып, StreamBuilder қайта жазылып отыратын.
  late final Stream<Order?> _orderStream = Repo.orderStream(widget.orderId);

  /// Жақындық шегі (км): нақты нүктеде емес, жақын болса жеткілікті.
  static const _proximityKm = 1.5;

  /// Орындаушыны картада тірі көрсету (0060) — модератор баптауы қосулы
  /// болса, ағымдағы GPS нүктесі 20с сайын серверге жіберіледі. Соңғы
  /// белгілі статус осында сақталады (build ішінде жаңарады) — таймер
  /// оны шақырғанда белсенді статус па деп тексереді.
  Timer? _locTimer;
  String? _lastStatus;

  static const _trackableStatuses = {
    'accepted',
    'arrived',
    'loading',
    'in_transit',
  };

  @override
  void initState() {
    super.initState();
    _initLiveTracking();
  }

  Future<void> _initLiveTracking() async {
    try {
      final s = await Repo.settings();
      final live = s['live_tracking'];
      if (live is Map && live['enabled'] == true) {
        _locTimer = Timer.periodic(
          const Duration(seconds: 20),
          (_) => _pushLocationIfActive(),
        );
      }
    } catch (_) {}
  }

  Future<void> _pushLocationIfActive() async {
    if (!_trackableStatuses.contains(_lastStatus)) return;
    final pos = await Geo.currentPosition();
    if (pos == null) return;
    await Repo.updateExecutorLocation(pos.latitude, pos.longitude);
  }

  @override
  void dispose() {
    _locTimer?.cancel();
    super.dispose();
  }

  // «arrived → loading» әдейі ЖОҚ: тиеуді енді КЛИЕНТ растайды (0027).
  // Орындаушы «Келдім» дегеннен кейін клиенттің растауын күтеді, содан соң
  // ғана «Жолға шықтық» батырмасы (loading → in_transit) көрінеді.
  static (String, String, IconData)? _nextFor(String status) =>
      switch (status) {
        'accepted' => ('arrived', t('Келдім'), Icons.location_on),
        'loading' => ('in_transit', t('Жолға шықтық'), Icons.local_shipping),
        'in_transit' => ('completed', t('Заказды аяқтау'), Icons.check_circle),
        _ => null,
      };

  /// Заказ аяқталғанда клиентті бағалау терезесін бір рет қалқымалы ашамыз.
  void _maybeShowReview(Order o) {
    if (!_reviewShown && o.status == 'completed') {
      _reviewShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          maybeShowReviewDialog(
            context,
            orderId: o.id,
            title: 'Клиентті бағалаңыз',
          ); // t() ReviewPrompt ішінде
        }
      });
    }
  }

  /// Геолокация + жақындықты тексереді. Қажет болмаса — true.
  Future<bool> _checkProximity(
    BuildContext context,
    String nextStatus,
    Order o,
  ) async {
    // «Келдім» → A нүктесіне жақын; «Аяқтау» → B нүктесіне жақын
    LatLng? target;
    String farErr = '';
    if (nextStatus == 'arrived') {
      target = LatLng(o.fromLat, o.fromLng);
      farErr = 'TOO_FAR_FROM_A';
    } else if (nextStatus == 'completed') {
      target = LatLng(o.toLat, o.toLng);
      farErr = 'TOO_FAR_FROM_B';
    }
    if (target == null) return true; // басқа қадамдар — тексеріссіз

    final pos = await Geo.currentPosition();
    if (pos == null) {
      if (context.mounted) await _showLocationNeeded(context);
      return false;
    }
    final dist = Geo.haversineKm(LatLng(pos.latitude, pos.longitude), target);
    if (dist > _proximityKm) {
      if (context.mounted) {
        showSnack(
          context,
          '${errText(farErr)} (${dist.toStringAsFixed(1)} ${t('км қашықтық')})',
          error: true,
        );
      }
      return false;
    }
    return true;
  }

  /// Геолокация өшірулі не рұқсат берілмеген кезде — түсіндірме терезесі.
  /// Тек орындаушы «Келдім/Аяқтау» түймесін өзі басқанда шығады (локацияға
  /// тәуелді нақты әрекет), сол себепті параметрлерге өту өз еркімен — мұны
  /// App Store ережесі (5.1.1) осындай жағдайда рұқсат етеді.
  Future<void> _showLocationNeeded(BuildContext context) async {
    final serviceOn = await Geolocator.isLocationServiceEnabled();
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Геолокация керек')),
        content: Text(
          t(
            '«Келдім» және «Аяқтау» түймелері үшін орналасуыңызды растау қажет '
            '— жүйе нүктеге жеткеніңізді тексереді. Параметрлерден геолокацияны '
            'қосыңыз.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t('Жабу')),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (serviceOn) {
                Geolocator.openAppSettings();
              } else {
                Geolocator.openLocationSettings();
              }
            },
            child: Text(t('Параметрлерді ашу')),
          ),
        ],
      ),
    );
  }

  /// Келесі статусқа өту: A/B нүктесіне жақындықты тексеріп, серверге
  /// жібереді. Аяқталса — фотолар тазаланып, табыс туралы хабар шығады.
  Future<void> _advance(
    BuildContext context,
    Order o,
    String nextStatus,
  ) async {
    // A/B нүктесіне жақындықты тексеру
    final ok = await _checkProximity(context, nextStatus, o);
    if (!ok) return;
    try {
      await Repo.orderAdvance(o.id, nextStatus);
      if (nextStatus == 'completed') {
        if (o.photos.isNotEmpty) {
          Repo.deleteOrderPhotos(o.photos);
        }
        if (context.mounted) {
          showSnack(
            context,
            '${t('Заказ аяқталды! Табысыңызға')} ${fmtT(o.finalPrice)} ${t('қосылды')} 🎉',
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        showSnack(context, errText(e), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t('Белсенді заказ'))),
      body: StreamBuilder<Order?>(
        stream: _orderStream,
        builder: (context, snap) {
          final o = snap.data;
          if (o == null) {
            return const Center(child: CircularProgressIndicator());
          }
          _maybeShowReview(o);
          _lastStatus = o.status;
          final next = _nextFor(o.status);
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TripHero(order: o),
                const SizedBox(height: 12),
                _NextStepCard(
                  order: o,
                  action: next == null
                      ? null
                      : BusyButton(
                          label: next.$2,
                          icon: next.$3,
                          color: o.status == 'in_transit' ? Gz.green : null,
                          onPressed: () => _advance(context, o, next.$1),
                        ),
                ),
                if (o.status == 'completed') ...[
                  const SizedBox(height: 10),
                  ReviewPrompt(
                    orderId: o.id,
                    title: 'Клиентті бағалаңыз',
                  ), // t() ReviewPrompt ішінде
                ],
                const SizedBox(height: 12),
                // Заказ тоқтатылса — клиенттің нөмірі/хабарласу батырмасы
                // көрсетілмейді (байланыс тоқтатылған заказда сақталмайды).
                _ClientCard(
                  clientId: o.clientId,
                  showCall: o.status != 'cancelled',
                ),
                const SizedBox(height: 12),
                RouteMap(
                  from: LatLng(o.fromLat, o.fromLng),
                  to: LatLng(o.toLat, o.toLng),
                  stops: o.stops.map((s) => LatLng(s.lat, s.lng)).toList(),
                  height: 180,
                  fromLabel: o.fromDisplay,
                  toLabel: o.toDisplay,
                  stopLabels: o.stops.map((s) => s.display).toList(),
                  distanceKm: o.distanceKm,
                ),
                const SizedBox(height: 10),
                // Маршрут тізімі: әр нүктенің жанында 2GIS навигация
                // батырмасы (бұрынғы A / 1 / B қосқышының орнында) — қай
                // мекенжайға жол салатыны енді шатаспайды.
                SectionCard(
                  padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
                  child: ExecRouteTimeline(
                    order: o,
                    onNavigate: o.isActive ? _navigate : null,
                  ),
                ),
                if (ExecOrderNotes.hasContent(o)) ...[
                  const SizedBox(height: 10),
                  ExecOrderNotes(order: o),
                ],
                if (o.isActive) ...[
                  const SizedBox(height: 16),
                  SupportOrderButton(orderId: o.id),
                  const SizedBox(height: 10),
                  ReportSuspiciousButton(orderId: o.id),
                ],
                // Орындаушы тек «қабылданды» кезеңінде (келмей тұрып) бас тарта алады
                if (o.status == 'accepted') ...[
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Gz.red,
                      side: const BorderSide(color: Gz.red),
                    ),
                    onPressed: () => _cancel(context, o.id),
                    icon: const Icon(Icons.close),
                    label: Text(t('Бас тарту')),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  /// 2GIS қосымшасын тікелей турлы-баурай («routeSearch») режимінде ашуға
  /// тырысады (ҚР/ТМД-да ең көп қолданылатын навигация — сол себепті Google
  /// Maps орнына нақ осы таңдалды); орнатылмаса не платформа қолдамаса —
  /// 2GIS веб-бағыттар бетіне (кез келген құрылғыда жұмыс істейді) қайтады.
  Future<void> _navigate(double lat, double lng) async {
    if (!kIsWeb) {
      try {
        final dgis = Uri.parse(
          'dgis://2gis.ru/routeSearch/rsType/car/to/$lng,$lat',
        );
        if (await canLaunchUrl(dgis)) {
          await launchUrl(dgis);
          return;
        }
      } catch (_) {
        // белгісіз платформа/рұқсат қатесі — веб-нұсқаға түсеміз
      }
    }
    launchUrl(
      Uri.parse('https://2gis.kz/routeSearch/rsType/car/to/$lng,$lat'),
      mode: LaunchMode.externalApplication,
    );
  }

  static const _execCancelReasons = [
    'Көлігім бос емес',
    'Қашықтық тым алыс',
    'Клиентпен байланыса алмадым',
    'Баға тым төмен',
    'Жүк сипаттамаға сай емес',
  ];

  Future<void> _cancel(BuildContext context, String orderId) async {
    final reason = await pickCancelReason(
      context,
      title: t('Заказдан бас тарту'),
      presets: [for (final r in _execCancelReasons) t(r)],
    );
    if (reason == null || !context.mounted) return;
    try {
      await Repo.cancelOrder(orderId, reason);
      if (context.mounted) Navigator.of(context).maybePop();
    } catch (e) {
      if (context.mounted) showSnack(context, errText(e), error: true);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  BAҒА + САПАР ПРОГРЕСІ
// ═══════════════════════════════════════════════════════════════════════

/// Экранның басындағы қою «hero» карточка: заказ құны, көлік түрі,
/// қашықтық және сапардың кезеңдер жолағы ([_TripStepper]).
///
/// Статус чипі әдейі ЖОҚ: кезеңдер жолағы қай қадамда тұрғанын әлдеқайда
/// айқын көрсетеді — екеуі қатар тұрса, бір ақпарат екі рет қайталанар еді.
class _TripHero extends StatelessWidget {
  final Order order;
  const _TripHero({required this.order});

  @override
  Widget build(BuildContext context) {
    final o = order;
    final meta = <(IconData, String)>[
      if (o.distanceKm > 0)
        (Icons.straighten_rounded, '${o.distanceKm.toStringAsFixed(1)} км'),
      if (o.intercity) (Icons.alt_route_rounded, t('Қалааралық')),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        gradient: Gz.heroGradient,
        borderRadius: BorderRadius.circular(Gz.radius),
        boxShadow: Gz.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t('Заказ құны'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.62),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        fmtT(o.displayPrice),
                        maxLines: 1,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          height: 1.15,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.6,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Ені шектеулі: баға (Expanded) қалған кеңістікті толық алады.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: _HeroChip(
                  icon: o.vehicleType == VehicleType.taxi
                      ? Icons.local_taxi_rounded
                      : Icons.local_shipping_rounded,
                  text: o.vehicleType.label,
                  strong: true,
                ),
              ),
            ],
          ),
          if (meta.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final m in meta) _HeroChip(icon: m.$1, text: m.$2),
              ],
            ),
          ],
          if (o.status != 'cancelled') ...[
            const SizedBox(height: 18),
            _TripStepper(
              status: o.status,
              taxi: o.vehicleType == VehicleType.taxi,
            ),
          ],
        ],
      ),
    );
  }
}

/// Hero ішіндегі жартылай мөлдір шағын белгі.
class _HeroChip extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool strong;
  const _HeroChip({
    required this.icon,
    required this.text,
    this.strong = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
      decoration: BoxDecoration(
        color: strong
            ? Gz.yellow.withValues(alpha: 0.16)
            : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: strong
              ? Gz.yellow.withValues(alpha: 0.35)
              : Colors.white.withValues(alpha: 0.12),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: strong ? Gz.yellow : Colors.white70),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: strong ? Gz.yellow : Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Сапар кезеңдері: Қабылданды → Орнында → Тиеу/Отырғызу → Жолда →
/// Аяқталды. Өткен қадамдар — жасыл белгі, ағымдағысы — сары әрі баяу
/// «тыныстайды» (бір AnimationController, тек сол нүкте қайта салынады).
class _TripStepper extends StatefulWidget {
  final String status;
  final bool taxi;
  const _TripStepper({required this.status, required this.taxi});

  @override
  State<_TripStepper> createState() => _TripStepperState();
}

class _TripStepperState extends State<_TripStepper>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  /// Ағымдағы қадам индексі; 5 — бәрі өтті (аяқталды).
  int get _current => switch (widget.status) {
    'accepted' => 0,
    'arrived' => 1,
    'loading' => 2,
    'in_transit' => 3,
    'completed' => 5,
    _ => 0,
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant _TripStepper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status) _syncPulse();
  }

  /// Аяқталған заказда не «анимацияны азайту» қосулы болса — тоқтатамыз.
  void _syncPulse() {
    final still = _current > 4 || MediaQuery.disableAnimationsOf(context);
    if (still) {
      _pulse.stop();
      _pulse.value = 0;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cur = _current;
    final steps = <(String, IconData)>[
      (t('Қабылданды'), Icons.thumb_up_alt_rounded),
      (t('Орнында'), Icons.location_on_rounded),
      widget.taxi
          ? (t('Отырғызу'), Icons.airline_seat_recline_normal_rounded)
          : (t('Тиеу'), Icons.inventory_2_rounded),
      (
        t('Жолда'),
        widget.taxi ? Icons.local_taxi_rounded : Icons.local_shipping_rounded,
      ),
      (t('Аяқталды'), Icons.flag_rounded),
    ];
    const line = 2.5;
    final off = Colors.white.withValues(alpha: 0.16);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < steps.length; i++)
          Expanded(
            child: Column(
              children: [
                SizedBox(
                  height: 30,
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: line,
                          color: i == 0
                              ? Colors.transparent
                              : (i <= cur ? Gz.greenBright : off),
                        ),
                      ),
                      _dot(i, cur, steps[i].$2),
                      Expanded(
                        child: Container(
                          height: line,
                          color: i == steps.length - 1
                              ? Colors.transparent
                              : (i < cur ? Gz.greenBright : off),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 7),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: BtnLabel(
                    steps[i].$1,
                    style: TextStyle(
                      fontSize: 10.5,
                      height: 1.1,
                      fontWeight: i == cur ? FontWeight.w800 : FontWeight.w600,
                      color: i == cur
                          ? Gz.yellow
                          : (i < cur
                                ? Colors.white.withValues(alpha: 0.78)
                                : Colors.white.withValues(alpha: 0.4)),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _dot(int i, int cur, IconData icon) {
    const size = 28.0;
    if (i < cur) {
      return Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          color: Gz.green,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.check_rounded, size: 16, color: Colors.white),
      );
    }
    if (i > cur) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
        ),
        child: Icon(icon, size: 14, color: Colors.white.withValues(alpha: 0.4)),
      );
    }
    // Ағымдағы қадам — сары нүкте, айналасынан баяу тарайтын сақина.
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) {
          final v = Curves.easeOut.transform(_pulse.value);
          return Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: Gz.yellow,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Gz.yellow.withValues(alpha: 0.5 * (1 - v)),
                  spreadRadius: 7 * v,
                ),
              ],
            ),
            child: child,
          );
        },
        child: Icon(icon, size: 15, color: Gz.ink),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  «ҚАЗІР НЕ ІСТЕУ КЕРЕК» КАРТОЧКАСЫ
// ═══════════════════════════════════════════════════════════════════════

/// Ағымдағы кезеңге сай ЖАЛҒЫЗ нұсқау: түсті белгі, тақырып, бір сөйлем
/// түсініктеме және (болса) негізгі әрекет батырмасы.
class _NextStepCard extends StatelessWidget {
  final Order order;
  final Widget? action;
  const _NextStepCard({required this.order, this.action});

  @override
  Widget build(BuildContext context) {
    final o = order;
    final taxi = o.vehicleType == VehicleType.taxi;
    final reason = o.cancelReason?.trim() ?? '';
    final (Color color, IconData icon, String title, String body)?
    spec = switch (o.status) {
      'accepted' => (
        Gz.yellowDark,
        Icons.near_me_rounded,
        t('Алу нүктесіне барыңыз'),
        t('Клиент сізді күтіп отыр. Жеткен соң «Келдім» батырмасын басыңыз.'),
      ),
      // «Келдім» дегеннен кейін — клиенттің тиеуді растауын күтеміз
      'arrived' => (
        Gz.blue,
        Icons.hourglass_top_rounded,
        t('Клиенттің растауын күтіңіз'),
        taxi
            ? t(
                'Клиенттің «Отырғызу басталды» деп '
                'растауын күтіңіз. Растаған соң «Жолға '
                'шықтық» батырмасы шығады.',
              )
            : t(
                'Клиенттің «Тиеу басталды» деп растауын '
                'күтіңіз. Растаған соң «Жолға шықтық» '
                'батырмасы шығады.',
              ),
      ),
      'loading' => (
        Gz.violet,
        taxi
            ? Icons.airline_seat_recline_normal_rounded
            : Icons.inventory_2_rounded,
        taxi ? t('Жолаушы отырып жатыр') : t('Жүк тиеліп жатыр'),
        taxi
            ? t('Жолаушы отырған соң «Жолға шықтық» батырмасын басыңыз.')
            : t('Жүк тиелген соң «Жолға шықтық» батырмасын басыңыз.'),
      ),
      'in_transit' => (
        Gz.green,
        taxi ? Icons.local_taxi_rounded : Icons.local_shipping_rounded,
        t('Межелі нүктеге барыңыз'),
        t(
          'Жеткен соң «Заказды аяқтау» батырмасын басыңыз — жүйе нүктеге '
          'жеткеніңізді тексереді.',
        ),
      ),
      'completed' => (
        Gz.green,
        Icons.check_circle_rounded,
        t('Заказ сәтті аяқталды'),
        // Бағалау туралы мұнда АЙТЫЛМАЙДЫ — төмендегі ReviewPrompt-тың
        // өзі соны сұрайды (не «Пікіріңіз үшін рахмет!» дейді).
        t('Рахмет! Заказ ақысы табысыңызға қосылды.'),
      ),
      'cancelled' => (
        Gz.red,
        Icons.cancel_rounded,
        t('Заказ тоқтатылды'),
        reason.isNotEmpty
            ? '${t('Себебі:')} $reason'
            : t('Бұл заказ енді белсенді емес.'),
      ),
      _ => null,
    };
    if (spec == null) return const SizedBox.shrink();
    final (color, icon, title, body) = spec;

    return Container(
      decoration: BoxDecoration(
        color: Gz.surface,
        borderRadius: BorderRadius.circular(Gz.radius),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1.4),
        boxShadow: Gz.cardShadow,
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Gz.tint(color, 0.13),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t('Қазір не істеу керек').toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Gz.label.copyWith(color: color),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        height: 1.25,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      body,
                      style: const TextStyle(
                        fontSize: 13.5,
                        height: 1.45,
                        color: Gz.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (action != null) ...[const SizedBox(height: 14), action!],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  ОРЫНДАУШЫ ЭКРАНДАРЫНА ОРТАҚ БЛОКТАР
//  (ExecutorOrderScreen де осыларды қолданады — бір дизайн, бір код)
// ═══════════════════════════════════════════════════════════════════════

/// Маршруттың ТІК тізімі: алу нүктесі — жасыл САҚИНА, аялдамалар —
/// нөмірлі күлгін дөңгелек, ақырғы нүкте — қызыл ШАРШЫ; араларын ПУНКТИР
/// сызық жалғайды. Мекенжай 2 жолға дейін толық көрінеді.
///
/// [onNavigate] берілсе — әр нүктенің жанында «Жол салу» батырмасы
/// шығады (белсенді заказда 2GIS навигация).
class ExecRouteTimeline extends StatelessWidget {
  final Order order;
  final void Function(double lat, double lng)? onNavigate;
  const ExecRouteTimeline({super.key, required this.order, this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final o = order;
    final points = <(Widget, String, String, double, double)>[
      (
        const _RouteMark.origin(),
        t('Қайдан'),
        o.fromDisplay,
        o.fromLat,
        o.fromLng,
      ),
      for (var i = 0; i < o.stops.length; i++)
        (
          _RouteMark.stop(i + 1),
          '${t('Аялдама')} ${i + 1}',
          o.stops[i].display,
          o.stops[i].lat,
          o.stops[i].lng,
        ),
      (
        const _RouteMark.finish(),
        o.stops.isEmpty ? t('Қайда') : t('Соңғы нүкте'),
        o.toDisplay,
        o.toLat,
        o.toLng,
      ),
    ];
    // Тар экранда (≈320px) навигация батырмасы тек белгі болып қалады —
    // мекенжайға орын жетсін.
    return LayoutBuilder(
      builder: (context, box) => _rows(points, compactNav: box.maxWidth < 290),
    );
  }

  Widget _rows(
    List<(Widget, String, String, double, double)> points, {
    required bool compactNav,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < points.length; i++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 22,
                  child: Column(
                    children: [
                      SizedBox(height: 22, child: Center(child: points[i].$1)),
                      if (i < points.length - 1)
                        const Expanded(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 3),
                            child: CustomPaint(
                              painter: _DashPainter(),
                              child: SizedBox(width: 2),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      top: 2,
                      bottom: i < points.length - 1 ? 16 : 0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          points[i].$2.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Gz.label,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          points[i].$3,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14.5,
                            height: 1.3,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (onNavigate != null) ...[
                  const SizedBox(width: 8),
                  Align(
                    alignment: Alignment.topCenter,
                    child: _NavPill(
                      compact: compactNav,
                      onTap: () => onNavigate!(points[i].$4, points[i].$5),
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// Маршрут тізіміндегі нүкте белгісі (сақина / нөмір / шаршы).
class _RouteMark extends StatelessWidget {
  final int? number;
  final bool finish;
  const _RouteMark.origin() : number = null, finish = false;
  const _RouteMark.finish() : number = null, finish = true;
  const _RouteMark.stop(this.number) : finish = false;

  @override
  Widget build(BuildContext context) {
    if (finish) {
      return Container(
        width: 15,
        height: 15,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Gz.red,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(1.5),
          ),
        ),
      );
    }
    if (number != null) {
      return Container(
        width: 20,
        height: 20,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: Gz.violet,
          shape: BoxShape.circle,
        ),
        child: Text(
          '$number',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            height: 1,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: Gz.surface,
        shape: BoxShape.circle,
        border: Border.all(color: Gz.green, width: 4.5),
      ),
    );
  }
}

/// Тік пунктир сызық (маршрут нүктелерін жалғайды).
class _DashPainter extends CustomPainter {
  const _DashPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Gz.textTertiary.withValues(alpha: 0.7)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final x = size.width / 2;
    const dash = 4.0, gap = 4.0;
    for (var y = 1.0; y < size.height - 1; y += dash + gap) {
      final end = (y + dash).clamp(0.0, size.height - 1);
      canvas.drawLine(Offset(x, y), Offset(x, end), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DashPainter oldDelegate) => false;
}

/// «Жол салу» — нүктеге навигация ашатын ықшам пилюля.
///
/// [compact] — тек белгі (тар экранда мекенжайға орын қалдыру үшін).
class _NavPill extends StatelessWidget {
  final VoidCallback onTap;
  final bool compact;
  const _NavPill({required this.onTap, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return PressScale(
      child: Material(
        color: Gz.tint(Gz.blue, 0.1),
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: compact
                ? const EdgeInsets.all(8)
                : const EdgeInsets.fromLTRB(9, 7, 11, 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.navigation_rounded, size: 15, color: Gz.blue),
                if (!compact) ...[
                  const SizedBox(width: 5),
                  Text(
                    t('Жол салу'),
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.1,
                      fontWeight: FontWeight.w800,
                      color: Gz.blue,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Жүк (таксиде — жолаушылар), түсініктеме және фотолар — тақырыбы мен
/// белгісі бар бөлімдер, бір карточкада.
class ExecOrderNotes extends StatelessWidget {
  final Order order;
  const ExecOrderNotes({super.key, required this.order});

  /// Көрсететін ештеңе болмаса — карточка мүлдем салынбайды.
  static bool hasContent(Order o) =>
      o.cargoDesc.trim().isNotEmpty ||
      o.comment.trim().isNotEmpty ||
      o.photos.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final o = order;
    final taxi = o.vehicleType == VehicleType.taxi;
    final blocks = <Widget>[
      if (o.cargoDesc.trim().isNotEmpty)
        _NoteBlock(
          icon: taxi ? Icons.groups_rounded : Icons.inventory_2_rounded,
          color: Gz.yellowDeep,
          title: taxi ? t('Жолаушылар') : t('Жүк'),
          text: o.cargoDesc.trim(),
        ),
      if (o.comment.trim().isNotEmpty)
        _NoteBlock(
          icon: Icons.chat_bubble_outline_rounded,
          color: Gz.blue,
          title: t('Түсініктеме'),
          text: o.comment.trim(),
        ),
      if (o.photos.isNotEmpty) OrderPhotosStrip(paths: o.photos),
    ];
    if (blocks.isEmpty) return const SizedBox.shrink();
    return SectionCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < blocks.length; i++) ...[
            if (i > 0) const Divider(height: 22),
            blocks[i],
          ],
        ],
      ),
    );
  }
}

class _NoteBlock extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String text;
  const _NoteBlock({
    required this.icon,
    required this.color,
    required this.title,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Gz.tint(color, 0.13),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 16, color: color),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        Text(
          text,
          style: const TextStyle(fontSize: 14.5, height: 1.45, color: Gz.ink),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  КЛИЕНТ КАРТОЧКАСЫ
// ═══════════════════════════════════════════════════════════════════════

class _ClientCard extends StatefulWidget {
  final String clientId;
  final bool showCall;
  const _ClientCard({required this.clientId, this.showCall = true});

  @override
  State<_ClientCard> createState() => _ClientCardState();
}

class _ClientCardState extends State<_ClientCard> {
  /// Профиль БІР РЕТ сұралады — бұрын заказ ағыны жаңарған сайын (3с)
  /// қайта сұралып, карточка «жыпылықтайтын».
  late Future<Profile?> _profile = Repo.profileOf(widget.clientId);

  @override
  void didUpdateWidget(covariant _ClientCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clientId != widget.clientId) {
      _profile = Repo.profileOf(widget.clientId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Profile?>(
      future: _profile,
      builder: (context, snap) {
        final p = snap.data;
        final canCall = widget.showCall && p != null && p.phone.isNotEmpty;
        return SectionCard(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              InitialsAvatar(
                p?.fullName ?? '?',
                radius: 24,
                imageUrl: p?.avatarUrl,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t('Клиент').toUpperCase(), style: Gz.label),
                    const SizedBox(height: 2),
                    Text(
                      p?.fullName ?? '…',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    // Орындаушы КЛИЕНТТІ көреді → клиенттік рейтинг/рейс
                    // (қос рөл, 0046: ол адамның орындаушылық бағасы бөлек).
                    if (p != null) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          RatingStars(
                            p.ratingAs('client'),
                            count: p.ratingCountAs('client'),
                            size: 12,
                          ),
                          if (p.tripsAs('client') > 0)
                            Flexible(
                              child: Text(
                                '  · ${p.tripsAs('client')} ${t('рейс')}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: Gz.textSecondary,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (canCall) ...[
                const SizedBox(width: 8),
                PressScale(
                  child: IconButton.filled(
                    iconSize: 22,
                    style: IconButton.styleFrom(
                      backgroundColor: Gz.green,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed: () => launchUrl(
                      Uri(scheme: 'tel', path: Phone.dial(p.phone)),
                    ),
                    icon: const Icon(Icons.call_rounded),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
