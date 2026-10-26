import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/geo.dart';
import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../core/trip_tracker.dart';
import '../../shared/map_widgets.dart';
import '../../shared/nav_apps.dart';
import '../../shared/order_live.dart';
import '../../shared/widgets.dart';
import '../chat/order_chat_screen.dart';
import '../support/support_screen.dart';
import 'delivery_code_sheet.dart';

/// Орындаушының белсенді заказ экраны: клиент, маршрут, статус ауыстыру.
///
/// Экран құрылымы (жоғарыдан төмен) — орындаушы «қазір не істеу керек?»
/// дегенге бір қарағанда жауап алуы үшін:
///   1. Көлік түрі, қашықтық + сапар кезеңдерінің ПРОГРЕСІ (жалғыз
///      кезең көрсеткіші — қай қадамда тұрмын).
///   2. «Қазір не істеу керек» карточкасы — бір сөйлеммен нұсқау (келгеннен
///      бергі күту таймері де осында); клиентке жету уақытының кері санағы.
///   3. Клиент (чат + қоңырау), алушы, карта, навигациясы бар маршрут,
///      заказ құны, жүк/түсініктеме.
///
/// Негізгі әрекет батырмасы ТӨМЕНДЕ БЕКІТІЛГЕН — жүргізуші бетті айналдырып
/// іздемейді. Орынды серверге жіберу бұл экранда ЕМЕС, орындаушы қабығында
/// (лентада не басқа бетте тұрса да клиенттің картасы тірі қалады).
class ActiveOrderScreen extends StatefulWidget {
  final String orderId;
  const ActiveOrderScreen({super.key, required this.orderId});

  @override
  State<ActiveOrderScreen> createState() => _ActiveOrderScreenState();
}

class _ActiveOrderScreenState extends State<ActiveOrderScreen> {
  bool _reviewShown = false;

  /// Заказ чаты (0078) қолжетімді ме — «кешігемін» батырмасы үшін.
  bool _chatAvailable = false;

  /// Заказ ағыны БІР РЕТ құрылады: build ішінде құрылса, әр қайта салуда
  /// жаңа polling басталып, StreamBuilder қайта жазылып отыратын.
  late final Stream<Order?> _orderStream = Repo.orderStream(widget.orderId);

  /// Алушы (0076) — статус ауысқан сайын қайта сұралады (клиент алушыны
  /// жолда қосуы не кодты өзі растауы мүмкін).
  OrderRecipient? _recipient;
  String? _recipientFor;

  /// Жақындық шегі (км): нақты нүктеде емес, жақын болса жеткілікті.
  static const _proximityKm = 1.5;

  /// Тірі трекер ([TripTracker.position]) әлі нүкте бермесе — бір рет
  /// тыныш алынған орын (картада өз орны мен A-ға дейінгі жол үшін).
  Position? _quietPos;

  @override
  void initState() {
    super.initState();
    Repo.orderChatAvailable().then((v) {
      if (mounted) setState(() => _chatAvailable = v);
    });
    _refreshQuietPos();
    // Тірі трекер жұмыс істемесе (live_tracking өшік, т.б.) — орын 15 с
    // сайын тыныш жаңарады, картадағы өз орны «қатып» қалмайды.
    _quietTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (TripTracker.position.value == null) _refreshQuietPos();
    });
  }

  Timer? _quietTimer;

  void _refreshQuietPos() {
    Geo.quietPosition().then((p) {
      if (mounted && p != null) setState(() => _quietPos = p);
    });
  }

  @override
  void dispose() {
    _quietTimer?.cancel();
    super.dispose();
  }

  void _syncRecipient(Order o) {
    if (_recipientFor == o.status) return;
    _recipientFor = o.status;
    if (!o.isActive && o.status != 'completed') return;
    Repo.orderRecipient(o.id).then((r) {
      if (mounted) setState(() => _recipient = r);
    }, onError: (_) {});
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
    if (_reviewShown || o.status != 'completed') return;
    _reviewShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      maybeShowReviewDialog(
        context,
        orderId: o.id,
        title: 'Клиентті бағалаңыз', // t() ReviewPrompt ішінде
        tags: kClientReviewTags,
      );
    });
  }

  /// Геолокация + жақындықты тексереді. Қажет болмаса — true.
  Future<bool> _checkProximity(String nextStatus, Order o) async {
    // «Келдім» → A нүктесіне жақын; «Аяқтау» → B нүктесіне жақын
    LatLng? target;
    var farErr = '';
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
      if (mounted) await _showLocationNeeded();
      return false;
    }
    final dist = Geo.haversineKm(LatLng(pos.latitude, pos.longitude), target);
    if (dist > _proximityKm) {
      if (mounted) {
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
  Future<void> _showLocationNeeded() async {
    final serviceOn = await Geolocator.isLocationServiceEnabled();
    if (!mounted) return;
    await gzInfoDialog(
      context,
      icon: Icons.location_off_outlined,
      color: Gz.warning,
      title: t('Геолокация керек'),
      message: t(
        '«Келдім» және «Аяқтау» түймелері үшін орналасуыңызды растау қажет '
        '— жүйе нүктеге жеткеніңізді тексереді. Параметрлерден геолокацияны '
        'қосыңыз.',
      ),
      actionLabel: t('Параметрлерді ашу'),
      onAction: () {
        if (serviceOn) {
          Geolocator.openAppSettings();
        } else {
          Geolocator.openLocationSettings();
        }
      },
    );
  }

  /// Алушы қосылған заказда жеткізу кодын сұрайды. Код керек емес болса
  /// не дұрыс енгізілсе — true.
  Future<bool> _ensureCode(Order o, {bool refresh = false}) async {
    var r = _recipient;
    if (r == null || refresh) {
      try {
        r = await Repo.orderRecipient(o.id);
      } catch (_) {}
    }
    if (r == null || !r.hasCode || r.verified) return true;
    if (!mounted) return false;
    final ok = await showDeliveryCodeSheet(
      context,
      orderId: o.id,
      recipientName: r.name,
      recipientPhone: r.phone,
    );
    if (ok) _recipientFor = null; // «код расталды» күйін қайта сұрау
    return ok;
  }

  /// Келесі статусқа өту: A/B нүктесіне жақындықты (аяқтауда — жеткізу
  /// кодын да) тексеріп, серверге жібереді. Аяқталса — фотолар тазаланып,
  /// табыс туралы хабар шығады.
  Future<void> _advance(Order o, String next) async {
    if (!await _checkProximity(next, o)) return;
    if (next == 'completed' && !await _ensureCode(o)) return;
    try {
      await Repo.orderAdvance(o.id, next);
    } catch (e) {
      // Клиент алушыны дәл қазір қосқан болса — кодты сұрап, қайталаймыз.
      if (!e.toString().contains('CODE_REQUIRED')) {
        if (mounted) showSnack(context, errText(e), error: true);
        return;
      }
      if (!await _ensureCode(o, refresh: true)) return;
      try {
        await Repo.orderAdvance(o.id, next);
      } catch (e2) {
        if (mounted) showSnack(context, errText(e2), error: true);
        return;
      }
    }
    // Жаңа статус бірден көрінсін (polling-тің келесі айналымын күтпей).
    Repo.orderStream(o.id, fresh: true);
    if (next == 'completed') {
      if (o.photos.isNotEmpty) Repo.deleteOrderPhotos(o.photos);
      if (mounted) {
        showSnack(
          context,
          '${t('Заказ аяқталды! Табысыңызға')} ${fmtT(o.finalPrice)} ${t('қосылды')} 🎉',
        );
      }
    }
  }

  /// Кешігіп жатса — клиентке чатқа бір басумен «кешігемін».
  Future<void> _sendLate(Order o) async {
    try {
      await Repo.orderChatSend(o.id, t('Кептеліс, сәл кешігемін'));
      Repo.orderMessagesStream(o.id, fresh: true);
      if (mounted) showSnack(context, t('Клиентке хабар жіберілді'));
    } catch (e) {
      if (mounted) showSnack(context, errText(e), error: true);
    }
  }

  /// Нүктеге жол салу: сақталған навигатормен; бірінші рет басқанда
  /// навигатор (2GIS / Яндекс / Google) сұралады да, таңдау есте қалады —
  /// кейін «⋯ Навигация» мәзірінен ауыстыруға болады (nav_apps.dart).
  Future<void> _navigate(double lat, double lng) =>
      NavApps.open(context, lat, lng);

  /// «⋯ Навигация» — навигаторды ауыстыру, мекенжайды көшіру.
  void _navMenu(Order o) {
    showGzSheet<void>(
      context,
      builder: (ctx) => GzSheetBody(
        title: t('Навигация'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GzListRow(
              icon: Icons.swap_horiz_rounded,
              color: Gz.info,
              title: t('Навигаторды ауыстыру'),
              onTap: () {
                Navigator.pop(ctx);
                NavApps.pick(context);
              },
            ),
            GzListRow(
              icon: Icons.copy_rounded,
              color: Gz.green,
              title: t('A мекенжайын көшіру'),
              subtitle: o.fromDisplay,
              onTap: () {
                Navigator.pop(ctx);
                copyAddress(context, o.fromAddress);
              },
            ),
            for (var i = 0; i < o.stops.length; i++)
              GzListRow(
                icon: Icons.copy_rounded,
                color: Gz.violet,
                title: '${t('Аялдама')} ${i + 1}',
                subtitle: o.stops[i].display,
                onTap: () {
                  Navigator.pop(ctx);
                  copyAddress(context, o.stops[i].address);
                },
              ),
            GzListRow(
              icon: Icons.copy_rounded,
              color: Gz.red,
              title: t('B мекенжайын көшіру'),
              subtitle: o.toDisplay,
              onTap: () {
                Navigator.pop(ctx);
                copyAddress(context, o.toAddress);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Order?>(
      stream: _orderStream,
      builder: (context, snap) {
        final o = snap.data;
        if (o == null) {
          return Scaffold(
            appBar: AppBar(title: Text(t('Белсенді заказ'))),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        _maybeShowReview(o);
        _syncRecipient(o);
        final next = _nextFor(o.status);
        final r = _recipient;
        final needsCode =
            o.status == 'in_transit' && r != null && r.hasCode && !r.verified;
        return Scaffold(
          appBar: AppBar(title: Text(t('Белсенді заказ'))),
          // Негізгі әрекет — төменде бекітілген (жалғыз батырма; «Қазір не
          // істеу керек» карточкасы тек нұсқау береді).
          bottomNavigationBar: next == null
              ? null
              : SafeArea(
                  top: false,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                    decoration: BoxDecoration(
                      color: Gz.surface,
                      boxShadow: Gz.cardShadow,
                    ),
                    child: BusyButton(
                      label: needsCode ? t('Кодты енгізіп аяқтау') : next.$2,
                      icon: needsCode ? Icons.pin_rounded : next.$3,
                      color: o.status == 'in_transit' ? Gz.green : null,
                      onPressed: () => _advance(o, next.$1),
                    ),
                  ),
                ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TripHero(order: o),
                const SizedBox(height: 12),
                _NextStepCard(order: o, needsCode: needsCode),
                // Клиентке жету уақытының кері санағы (0075; уәде еткен ETA
                // жоқ болса — көрінбейді). Кешіксе — сары/қызыл және чатқа
                // «кешігемін» деп бір басумен жазу.
                if (o.status == 'accepted' && o.arriveBy != null) ...[
                  const SizedBox(height: 10),
                  // «Кешігемін» жарлығы чат батырмасымен БІР шартпен көрінеді
                  // (модератор чатты өшірсе — екеуі де жоқ).
                  Consumer(
                    builder: (context, ref, _) => EtaCountdownCard(
                      order: o,
                      forExecutor: true,
                      lateAction:
                          _chatAvailable &&
                              o.chatOpen &&
                              orderChatEnabled(
                                ref.watch(appSettingsProvider).value,
                              )
                          ? OutlinedButton.icon(
                              onPressed: () => _sendLate(o),
                              icon: const Icon(Icons.chat_outlined, size: 18),
                              label: Text(t('Клиентке «кешігемін» деп жазу')),
                            )
                          : null,
                    ),
                  ),
                ],
                if (o.status == 'completed') ...[
                  const SizedBox(height: 10),
                  ReviewPrompt(
                    orderId: o.id,
                    title: 'Клиентті бағалаңыз', // t() ReviewPrompt ішінде
                    tags: kClientReviewTags,
                  ),
                ],
                const SizedBox(height: 12),
                // Заказ тоқтатылса — клиенттің нөмірі/хабарласу батырмалары
                // көрсетілмейді (байланыс тоқтатылған заказда сақталмайды).
                _ClientCard(order: o, showContacts: o.status != 'cancelled'),
                if (r != null && o.status != 'cancelled') ...[
                  const SizedBox(height: 10),
                  _RecipientCard(
                    recipient: r,
                    showContacts: o.isActive,
                    // Жолда кезінде кодты сұрау «Қазір не істеу керек»
                    // карточкасында айтылады — мұнда қайталанбайды.
                    showCodeHint: !needsCode,
                  ),
                ],
                const SizedBox(height: 12),
                // A-ға келе жатқанда — өз орны (тірі) мен A-ға дейінгі сұр
                // жол. OSRM-ді әр GPS нүктесінде сұрамайды (RouteMap өзі
                // сирек сұрайды, арада жолды кеседі).
                ValueListenableBuilder<Position?>(
                  valueListenable: TripTracker.position,
                  builder: (context, live, _) {
                    final me = o.status == 'accepted'
                        ? (live ?? _quietPos)
                        : null;
                    return RouteMap(
                      from: LatLng(o.fromLat, o.fromLng),
                      to: LatLng(o.toLat, o.toLng),
                      stops: o.stops.map((s) => LatLng(s.lat, s.lng)).toList(),
                      height: 180,
                      fromLabel: o.fromDisplay,
                      toLabel: o.toDisplay,
                      stopLabels: o.stops.map((s) => s.display).toList(),
                      distanceKm: o.distanceKm,
                      approachFrom: me == null
                          ? null
                          : LatLng(me.latitude, me.longitude),
                      approachVehicle: o.vehicleType,
                      approachHeading: me == null || me.heading < 0
                          ? null
                          : me.heading,
                    );
                  },
                ),
                const SizedBox(height: 10),
                // Маршрут тізімі: әр нүктенің жанында «Жол салу» батырмасы —
                // қай мекенжайға жол салатыны шатаспайды. Төменде «⋯
                // Навигация»: навигаторды ауыстыру, мекенжайды көшіру.
                SectionCard(
                  padding: EdgeInsets.fromLTRB(14, 14, 12, o.isActive ? 4 : 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ExecRouteTimeline(
                        order: o,
                        onNavigate: o.isActive ? _navigate : null,
                      ),
                      if (o.isActive)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () => _navMenu(o),
                            icon: const Icon(
                              Icons.more_horiz_rounded,
                              size: 18,
                            ),
                            label: Text(t('Навигация')),
                          ),
                        ),
                    ],
                  ),
                ),
                // Заказ құны — маршрут пен навигация батырмаларынан КЕЙІН:
                // жолда орындаушыға ең алдымен «қазір не істеймін / қайда
                // барамын» керек, ақы — есеп айырысқанда ғана.
                const SizedBox(height: 10),
                _TripPriceCard(order: o),
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
                      side: BorderSide(color: Gz.red),
                    ),
                    onPressed: () => _cancel(o.id),
                    icon: const Icon(Icons.close),
                    label: Text(t('Бас тарту')),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  static const _execCancelReasons = [
    'Көлігім бос емес',
    'Қашықтық тым алыс',
    'Клиентпен байланыса алмадым',
    'Баға тым төмен',
    'Жүк сипаттамаға сай емес',
  ];

  Future<void> _cancel(String orderId) async {
    final reason = await pickCancelReason(
      context,
      title: t('Заказдан бас тарту'),
      presets: [for (final r in _execCancelReasons) t(r)],
    );
    if (reason == null || !mounted) return;
    try {
      await Repo.cancelOrder(orderId, reason);
      if (mounted) Navigator.of(context).maybePop();
    } catch (e) {
      if (mounted) showSnack(context, errText(e), error: true);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  САПАР ПРОГРЕСІ + ЗАКАЗ ҚҰНЫ
// ═══════════════════════════════════════════════════════════════════════

/// Экранның басындағы қою «hero» карточка: көлік түрі, қашықтық және
/// сапардың кезеңдер жолағы ([_TripStepper]). Заказ құны мұнда ЕМЕС —
/// ол маршрут пен навигациядан кейін, [_TripPriceCard]-та тұрады.
///
/// Статус чипі әдейі ЖОҚ: кезеңдер жолағы қай қадамда тұрғанын әлдеқайда
/// айқын көрсетеді — екеуі қатар тұрса, бір ақпарат екі рет қайталанар еді.
class _TripHero extends StatelessWidget {
  final Order order;
  const _TripHero({required this.order});

  @override
  Widget build(BuildContext context) {
    final o = order;
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
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              // Ұмай заказы — көлік чипінің өзі қызғылт (атау екі рет
              // жазылмайды).
              _HeroChip(
                icon: o.vehicleType.isUmay
                    ? Icons.favorite_rounded
                    : o.vehicleType.isPassenger
                    ? Icons.local_taxi_rounded
                    : Icons.local_shipping_rounded,
                text: o.vehicleType.label,
                strong: true,
                color: o.vehicleType.isUmay ? kUmayPinkLight : null,
              ),
              for (final m in _tripMeta(o)) _HeroChip(icon: m.$1, text: m.$2),
            ],
          ),
          if (o.status != 'cancelled') ...[
            const SizedBox(height: 18),
            _TripStepper(status: o.status, taxi: o.vehicleType.isPassenger),
          ],
        ],
      ),
    );
  }
}

/// Сапардың қысқа сипаттамасы (қашықтық, қалааралық) — hero чиптері үшін.
List<(IconData, String)> _tripMeta(Order o) => [
  if (o.distanceKm > 0)
    (Icons.straighten_rounded, Geo.formatDistance(o.distanceKm)),
  if (o.intercity) (Icons.alt_route_rounded, t('Қалааралық')),
];

/// Заказ құны — маршрут пен навигация батырмаларының АСТЫНДА.
class _TripPriceCard extends StatelessWidget {
  final Order order;
  const _TripPriceCard({required this.order});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Gz.yellow.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.payments_rounded, color: Gz.yellowDeep, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              t('Заказ құны'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Gz.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                fmtT(order.displayPrice),
                maxLines: 1,
                style: TextStyle(
                  color: Gz.ink,
                  fontSize: 24,
                  height: 1.1,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
            ),
          ),
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

  /// Берілсе — белгі осы түспен (мыс. Ұмай үшін қызғылт).
  final Color? color;
  const _HeroChip({
    required this.icon,
    required this.text,
    this.strong = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
      decoration: BoxDecoration(
        color: color != null
            ? color!.withValues(alpha: 0.16)
            : strong
            ? Gz.yellow.withValues(alpha: 0.16)
            : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(Gz.rLg),
        border: Border.all(
          color: color != null
              ? color!.withValues(alpha: 0.4)
              : strong
              ? Gz.yellow.withValues(alpha: 0.35)
              : Colors.white.withValues(alpha: 0.12),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: color ?? (strong ? Gz.yellow : Colors.white70),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color ?? (strong ? Gz.yellow : Colors.white70),
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
          ? (t('Отырды'), Icons.airline_seat_recline_normal_rounded)
          : (t('Тиеу'), Icons.inventory_2_rounded),
      (
        t(widget.taxi ? 'Сапарда' : 'Жолда'),
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
                      fontSize: 11,
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
        decoration: BoxDecoration(color: Gz.green, shape: BoxShape.circle),
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
        child: Icon(icon, size: 15, color: Gz.onBrand),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  «ҚАЗІР НЕ ІСТЕУ КЕРЕК» КАРТОЧКАСЫ
// ═══════════════════════════════════════════════════════════════════════

/// Ағымдағы кезеңге сай ЖАЛҒЫЗ нұсқау: түсті белгі, тақырып, бір сөйлем
/// түсініктеме; «Келдім»-нен кейін — оң жақта күту таймері. Негізгі әрекет
/// батырмасы мұнда ЕМЕС — экранның төменінде бекітілген.
class _NextStepCard extends StatelessWidget {
  final Order order;

  /// Аяқтау алдында алушының жеткізу коды керек (0076).
  final bool needsCode;
  const _NextStepCard({required this.order, this.needsCode = false});

  @override
  Widget build(BuildContext context) {
    final o = order;
    final taxi = o.vehicleType.isPassenger;
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
        needsCode
            ? t(
                'Жеткен соң алушыдан 4 таңбалы кодты сұрап, «Кодты енгізіп '
                'аяқтау» батырмасын басыңыз.',
              )
            : t(
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
    final waitSince = o.status == 'arrived' ? o.arrivedAt : null;

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
                        fontSize: 18,
                        height: 1.25,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      body,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.45,
                        color: Gz.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (waitSince != null) ...[
                const SizedBox(width: 8),
                WaitClock(since: waitSince),
              ],
            ],
          ),
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
/// шығады (белсенді заказда таңдалған навигатор, әдепкісі 2GIS).
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
                            fontSize: 15,
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
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
    }
    if (number != null) {
      return Container(
        width: 20,
        height: 20,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: Gz.violet, shape: BoxShape.circle),
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
                Icon(Icons.navigation_rounded, size: 15, color: Gz.blue),
                if (!compact) ...[
                  const SizedBox(width: 5),
                  Text(
                    t('Жол салу'),
                    style: TextStyle(
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

/// Жүк (таксиде — жолаушылар), қосымша талаптар (тиеуші/қабат/лифт, 0077),
/// түсініктеме және фотолар — тақырыбы мен белгісі бар бөлімдер, бір
/// карточкада.
class ExecOrderNotes extends StatelessWidget {
  final Order order;
  const ExecOrderNotes({super.key, required this.order});

  /// Көрсететін ештеңе болмаса — карточка мүлдем салынбайды.
  static bool hasContent(Order o) =>
      o.cargoDesc.trim().isNotEmpty ||
      o.hasExtras ||
      o.comment.trim().isNotEmpty ||
      o.photos.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final o = order;
    final taxi = o.vehicleType.isPassenger;
    final blocks = <Widget>[
      if (o.cargoDesc.trim().isNotEmpty)
        _NoteBlock(
          icon: taxi ? Icons.groups_rounded : Icons.inventory_2_rounded,
          color: Gz.yellowDeep,
          title: taxi ? t('Жолаушылар') : t('Жүк'),
          text: o.cargoDesc.trim(),
        ),
      if (o.hasExtras) OrderExtrasChips(order: o),
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
                borderRadius: BorderRadius.circular(Gz.rXs),
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
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        Text(text, style: TextStyle(fontSize: 15, height: 1.45, color: Gz.ink)),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  КЛИЕНТ КАРТОЧКАСЫ
// ═══════════════════════════════════════════════════════════════════════

/// Клиент: аты, клиенттік рейтингі, чат (0078) + қоңырау.
class _ClientCard extends StatefulWidget {
  final Order order;
  final bool showContacts;
  const _ClientCard({required this.order, this.showContacts = true});

  @override
  State<_ClientCard> createState() => _ClientCardState();
}

class _ClientCardState extends State<_ClientCard> {
  /// Профиль БІР РЕТ сұралады — бұрын заказ ағыны жаңарған сайын (3с)
  /// қайта сұралып, карточка «жыпылықтайтын».
  late Future<Profile?> _profile = Repo.profileOf(widget.order.clientId);

  @override
  void didUpdateWidget(covariant _ClientCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.order.clientId != widget.order.clientId) {
      _profile = Repo.profileOf(widget.order.clientId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Profile?>(
      future: _profile,
      builder: (context, snap) {
        final p = snap.data;
        final canCall = widget.showContacts && p != null && p.phone.isNotEmpty;
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
                                style: TextStyle(
                                  fontSize: 12,
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
              // Чат батырмасы өзі жасырынады (сервер 0078-сыз, чат
              // өшірулі не заказ жабық болса).
              if (widget.showContacts) ...[
                const SizedBox(width: 8),
                OrderChatButton(
                  order: widget.order,
                  title: p?.fullName ?? t('Клиент'),
                  myRole: 'executor',
                ),
              ],
              if (canCall) ...[
                const SizedBox(width: 6),
                PressScale(
                  child: IconButton.filled(
                    tooltip: t('Қоңырау'),
                    iconSize: 22,
                    style: IconButton.styleFrom(
                      backgroundColor: Gz.green,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed: () => callPhone(context, p.phone),
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

/// Жүкті қабылдайтын адам (0076): аты, телефоны, код керек пе.
class _RecipientCard extends StatelessWidget {
  final OrderRecipient recipient;
  final bool showContacts;

  /// «Кодты сұраңыз» ескертуі (жолда кезінде ол «Қазір не істеу керек»
  /// карточкасында тұрады).
  final bool showCodeHint;
  const _RecipientCard({
    required this.recipient,
    this.showContacts = true,
    this.showCodeHint = true,
  });

  @override
  Widget build(BuildContext context) {
    final r = recipient;
    return SectionCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Gz.tint(Gz.violet, 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.person_pin_circle_rounded, color: Gz.violet),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t('Жүкті қабылдайтын адам'), style: Gz.caption),
                    Text(
                      r.name.isEmpty ? t('Алушы') : r.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Gz.h3,
                    ),
                  ],
                ),
              ),
              if (r.verified)
                InfoChip(
                  icon: Icons.verified_rounded,
                  color: Gz.success,
                  text: t('Код расталды'),
                )
              else if (r.hasCode)
                InfoChip(
                  icon: Icons.pin_rounded,
                  color: Gz.warning,
                  text: t('Код керек'),
                ),
            ],
          ),
          if (showCodeHint && !r.verified && r.hasCode) ...[
            const SizedBox(height: 10),
            GzNotice(
              tone: NoticeTone.warning,
              dense: true,
              message: t(
                'Жүкті тапсырғанда алушыдан 4 таңбалы кодты '
                'сұраңыз — кодсыз заказ аяқталмайды.',
              ),
            ),
          ],
          if (showContacts && r.phone.isNotEmpty) ...[
            const SizedBox(height: 10),
            ContactButtons(
              phone: r.phone,
              whatsappText: t(
                'Сәлеметсіз бе! Мен Tasu жүргізушісімін, '
                'сізге жүк әкеле жатырмын.',
              ),
            ),
          ],
        ],
      ),
    );
  }
}
