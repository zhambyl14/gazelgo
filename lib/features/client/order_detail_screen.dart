import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/env.dart';
import '../../core/geo.dart';
import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/phone.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/map_widgets.dart';
import '../../shared/widgets.dart';
import '../support/support_screen.dart';
import 'address_picker.dart';
import 'create_order_screen.dart';
import 'searching_view.dart';

/// Клиенттің заказ экраны: ұсыныстар, барыс, пікір.
class OrderDetailScreen extends StatefulWidget {
  final String orderId;
  const OrderDetailScreen({super.key, required this.orderId});

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  bool _photosCleaned = false;
  bool _reviewShown = false;

  /// Жаңа клиент фичалары (0060) қосулы ма — модератор баптауынан бір рет
  /// оқылады (ауыстырса, экранды қайта ашқанда көрінеді).
  bool _liveTrackingEnabled = false;
  bool _shareTripEnabled = false;
  bool _repeatOrderEnabled = true;

  static const _liveStatuses = ['accepted', 'arrived', 'loading', 'in_transit'];

  @override
  void initState() {
    super.initState();
    _loadFeatureFlags();
  }

  Future<void> _loadFeatureFlags() async {
    try {
      final s = await Repo.settings();
      final live = s['live_tracking'];
      final share = s['share_trip'];
      final repeat = s['repeat_order'];
      if (!mounted) return;
      setState(() {
        _liveTrackingEnabled = live is Map && live['enabled'] == true;
        _shareTripEnabled = share is Map && share['enabled'] == true;
        // Кілт жоқ болса ӘДЕПКІ ҚОСУЛЫ (0060 миграциясында солай жазылған).
        _repeatOrderEnabled = repeat is! Map || repeat['enabled'] != false;
      });
    } catch (_) {
      // Желі қатесінде — екеуі де өшулі қалады, экран сынбайды.
    }
  }

  Future<void> _shareTrip(Order o) async {
    try {
      final token = await Repo.getOrderShareToken(o.id);
      final url = '${Env.webBaseUrl}/track/$token';
      await SharePlus.instance.share(
        ShareParams(
          text:
              '${t('Менің тапсырысымның барысын осы сілтемеден қадағалауға болады')}: $url',
        ),
      );
    } catch (e) {
      if (mounted) showSnack(context, errText(e), error: true);
    }
  }

  /// Заказ аяқталғанда бағалау терезесін бір рет қалқымалы етіп ашамыз.
  void _maybeShowReview(Order o) {
    if (!_reviewShown && o.status == 'completed') {
      _reviewShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          maybeShowReviewDialog(
            context,
            orderId: o.id,
            title: t('Орындаушыны бағалаңыз'),
          );
        }
      });
    }
  }

  /// Заказ аяқталса/бас тартылса — тіркелген фотоларды өшіру (жадты үнемдеу).
  void _maybeCleanupPhotos(Order o) {
    const terminal = ['completed', 'cancelled', 'expired'];
    if (!_photosCleaned && terminal.contains(o.status) && o.photos.isNotEmpty) {
      _photosCleaned = true;
      Repo.deleteOrderPhotos(o.photos);
    }
  }

  /// Дәл осы маршрутпен ЖАҢА заказ ашады (Yandex Go/InDrive-тегі «Тағы да
  /// тапсырыс беру»). Клиент адрестерді қайта іздемейді — «қайдан»/«қайда»/
  /// аралық аялдамалар мен көлік түрі дайын күйде Заказ құру экранына
  /// беріледі, тек бағаны мен жүк сипаттамасын өзі растайды.
  void _reorder(Order o) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CreateOrderScreen(
          from: PickedAddress(
            o.fromAddress,
            LatLng(o.fromLat, o.fromLng),
            o.fromCity,
          ),
          to: PickedAddress(o.toAddress, LatLng(o.toLat, o.toLng), o.toCity),
          stops: [
            for (final s in o.stops)
              PickedAddress(s.address, LatLng(s.lat, s.lng), s.city),
          ],
          vehicleType: o.vehicleType,
        ),
      ),
    );
  }

  static const _clientCancelReasons = [
    'Ойымды өзгерттім',
    'Бағаны қымбат көрдім',
    'Орындаушы тым баяу жауап берді',
    'Қате адрес/жүк енгіздім',
    'Басқа орындаушы таптым',
  ];

  Future<void> _cancel() async {
    final reason = await pickCancelReason(
      context,
      title: t('Заказды тоқтату'),
      presets: [for (final r in _clientCancelReasons) t(r)],
    );
    if (reason == null || !mounted) return;
    try {
      await Repo.cancelOrder(widget.orderId, reason);
      // Экранда қалдырмаймыз — басты бетке қайтамыз (адрестер сол жерде сақталған)
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
        showSnack(context, t('Заказ тоқтатылды'));
      }
    } catch (e) {
      if (mounted) showSnack(context, errText(e), error: true);
    }
  }

  /// Заказ стримі БІР рет құрылады: экран қайта салынғанда (мыс. баптау
  /// жүктелгенде) жаңа сұрау тізбегі басталып кетпеуі үшін.
  late final Stream<Order?> _orderStream = Repo.orderStream(widget.orderId);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Order?>(
      stream: _orderStream,
      builder: (context, snap) {
        final o = snap.data;
        if (o == null) {
          return Scaffold(
            appBar: AppBar(title: Text(t('Заказ'))),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        _maybeCleanupPhotos(o);
        _maybeShowReview(o);
        // Іздеу кезінде — толық экранды карта + сүйретілетін панель
        // (Yandex Go үлгісі). Орындаушы табылған сәтте стрим жаңа статус
        // әкеледі де, экран өзі төмендегі әдеттегі түрге ауысады.
        if (o.status == 'searching') {
          return _SearchingScreen(
            order: o,
            onCancel: _cancel,
            onShare: _shareTripEnabled ? () => _shareTrip(o) : null,
          );
        }
        return Scaffold(
          appBar: AppBar(title: Text(t('Заказ'))),
          body: _details(o),
        );
      },
    );
  }

  /// Іздеуден КЕЙІНГІ барлық статустың (accepted … expired) экраны.
  Widget _details(Order o) {
    final live = _liveStatuses.contains(o.status);
    final info = <Widget>[
      if (_liveTrackingEnabled && _liveStatuses.contains(o.status))
        StreamBuilder<Map<String, dynamic>?>(
          stream: Repo.orderExecutorLocationStream(o.id),
          builder: (context, locSnap) {
            final loc = locSnap.data;
            final extra = <Marker>[
              if (loc != null && loc['lat'] != null)
                executorLiveMarker(
                  LatLng(
                    (loc['lat'] as num).toDouble(),
                    (loc['lng'] as num).toDouble(),
                  ),
                ),
            ];
            return RouteMap(
              from: LatLng(o.fromLat, o.fromLng),
              to: LatLng(o.toLat, o.toLng),
              stops: o.stops.map((s) => LatLng(s.lat, s.lng)).toList(),
              height: 175,
              extraMarkers: extra,
              fromLabel: o.fromDisplay,
              toLabel: o.toDisplay,
              stopLabels: o.stops.map((s) => s.display).toList(),
              distanceKm: o.distanceKm,
            );
          },
        )
      else
        RouteMap(
          from: LatLng(o.fromLat, o.fromLng),
          to: LatLng(o.toLat, o.toLng),
          stops: o.stops.map((s) => LatLng(s.lat, s.lng)).toList(),
          height: 175,
          fromLabel: o.fromDisplay,
          toLabel: o.toDisplay,
          stopLabels: o.stops.map((s) => s.display).toList(),
          distanceKm: o.distanceKm,
        ),
      const SizedBox(height: 10),
      SectionCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RouteLine(
              from: o.fromDisplay,
              to: o.toDisplay,
              stops: o.stops.map((s) => s.display).toList(),
            ),
            const Divider(height: 20),
            InfoRow(t('Жүк'), o.cargoDesc),
            if (o.comment.isNotEmpty) InfoRow(t('Түсініктеме'), o.comment),
            InfoRow(t('Көлік'), o.vehicleType.label),
            if (o.distanceKm > 0)
              InfoRow(t('Қашықтық'), Geo.formatDistance(o.distanceKm)),
            InfoRow(
              t('Бағыты'),
              o.intercity ? t('Қалааралық (межгород)') : t('Қала ішінде'),
            ),
            if (o.createdAt != null)
              InfoRow(t('Құрылды'), fmtDate(o.createdAt)),
          ],
        ),
      ),
      if (o.photos.isNotEmpty &&
          !['completed', 'cancelled', 'expired'].contains(o.status)) ...[
        const SizedBox(height: 10),
        OrderPhotosStrip(paths: o.photos),
      ],
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  fmtT(o.displayPrice),
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              if (_shareTripEnabled &&
                  !['cancelled', 'expired'].contains(o.status))
                IconButton(
                  tooltip: t('Бөлісу'),
                  icon: const Icon(Icons.ios_share),
                  onPressed: () => _shareTrip(o),
                ),
              StatusChip(o.status, vehicleType: o.vehicleType),
            ],
          ),
          const SizedBox(height: 12),
          // Сапар жүріп жатқанда (орындаушы жолда/келді/тиеу/жолда) ЕҢ
          // маңыздысы — кім келе жатыр, қоңырау, «Тиеу басталды» растауы:
          // олар картадан ЖОҒАРЫ тұрады (бұрын экранның төменінде қалатын).
          if (live) ...[
            ..._statusSection(o),
            const SizedBox(height: 14),
            ...info,
          ] else ...[
            ...info,
            const SizedBox(height: 14),
            ..._statusSection(o),
          ],
          const SizedBox(height: 14),
          // Бас тарту: accepted/arrived — процесте болмаса (іздеу кезінде
          // «Заказды тоқтату» — [_SearchingScreen] ішінде).
          if (['accepted', 'arrived'].contains(o.status))
            OutlinedButton.icon(
              onPressed: _cancel,
              style: OutlinedButton.styleFrom(
                foregroundColor: Gz.red,
                side: const BorderSide(color: Gz.red),
              ),
              icon: const Icon(Icons.close),
              label: Text(t('Заказды тоқтату')),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  List<Widget> _statusSection(Order o) {
    switch (o.status) {
      // Іздеу күйінің өз экраны бар — [_SearchingScreen].
      case 'searching':
        return const [];
      case 'accepted':
      case 'arrived':
      case 'loading':
      case 'in_transit':
        return [
          _ExecutorCard(executorId: o.executorId!),
          const SizedBox(height: 10),
          // Орындаушы «Келдім» дегенде — клиент тиеуді растайды (0027).
          // Расталмайынша орындаушы «Жолға шықтық» дей алмайды.
          if (o.status == 'arrived') ...[
            _ConfirmLoadingCard(orderId: o.id, vehicleType: o.vehicleType),
            const SizedBox(height: 10),
          ],
          _Timeline(status: o.status, vehicleType: o.vehicleType),
          const SizedBox(height: 10),
          SupportOrderButton(orderId: o.id),
          const SizedBox(height: 10),
          ReportSuspiciousButton(orderId: o.id),
        ];
      case 'completed':
        return [
          // Аяқталған заказда орындаушының телефоны көрсетілмейді
          // (хабарласу батырмасы жоқ) — тарихта байланыс сақталмайды.
          _ExecutorCard(executorId: o.executorId!, showCall: false),
          const SizedBox(height: 10),
          ReviewPrompt(orderId: o.id, title: t('Орындаушыны бағалаңыз')),
          const SizedBox(height: 10),
          if (_repeatOrderEnabled) _ReorderButton(onPressed: () => _reorder(o)),
        ];
      case 'cancelled':
        return [
          SectionCard(
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Gz.red),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    (o.cancelReason?.isNotEmpty ?? false)
                        ? '${t('Себебі:')} ${o.cancelReason}'
                        : t('Заказ тоқтатылды'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (_repeatOrderEnabled) _ReorderButton(onPressed: () => _reorder(o)),
        ];
      default:
        return [
          SectionCard(
            child: Row(
              children: [
                const Icon(Icons.schedule, color: Gz.textSecondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(t('Заказдың мерзімі өтті — ешкім қабылдамады.')),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (_repeatOrderEnabled) _ReorderButton(onPressed: () => _reorder(o)),
        ];
    }
  }
}

/// «Тағы да тапсырыс беру» — дәл осы маршрутпен жаңа заказ ашады
/// (Yandex Go/InDrive-тегі «Заказать снова»). Аяқталған, тоқтатылған және
/// мерзімі өткен заказдарда көрсетіледі — адрестерді қайта іздеудің
/// қажеті жоқ.
class _ReorderButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _ReorderButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: Gz.ink,
        side: const BorderSide(color: Gz.yellowDark, width: 1.6),
      ),
      icon: const Icon(Icons.replay_rounded),
      label: Text(t('Тағы да тапсырыс беру')),
    );
  }
}

/// Орындаушы келгенін клиент растайды: «Тиеу басталды» → status=loading.
/// Осыдан кейін ғана орындаушы «Жолға шықтық» дей алады (0027). Такси
/// заказында (жолаушы тасымалы) «тиеу» орнына «отыру» сөздігі қолданылады —
/// жолаушы жүк емес.
class _ConfirmLoadingCard extends StatelessWidget {
  final String orderId;
  final VehicleType vehicleType;
  const _ConfirmLoadingCard({required this.orderId, required this.vehicleType});

  @override
  Widget build(BuildContext context) {
    final isTaxi = vehicleType == VehicleType.taxi;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Gz.green.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(Gz.radius),
        border: Border.all(color: Gz.green.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                isTaxi ? Icons.person : Icons.local_shipping,
                color: Gz.green,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  t('Орындаушы жеткен жоқ па?'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            isTaxi
                ? t(
                    'Орындаушы келіп, сіз отырсаңыз — растаңыз. Растамайынша '
                    'орындаушы жолға шыға алмайды.',
                  )
                : t(
                    'Орындаушы келіп, тиеу басталса — растаңыз. Растамайынша '
                    'орындаушы жолға шыға алмайды.',
                  ),
            style: const TextStyle(color: Gz.textSecondary, fontSize: 12.5),
          ),
          const SizedBox(height: 12),
          BusyButton(
            label: t(isTaxi ? 'Отырғызу басталды' : 'Тиеу басталды'),
            icon: Icons.check_circle,
            color: Gz.green,
            onPressed: () async {
              try {
                await Repo.orderAdvance(orderId, 'loading');
              } catch (e) {
                if (context.mounted) {
                  showSnack(context, errText(e), error: true);
                }
              }
            },
          ),
        ],
      ),
    );
  }
}

// ===================== ІЗДЕУ (Tasu стилі) =====================

/// Заказ «Іздеуде» тұрғанда: толық экранды карта (алу нүктесінде Tasu
/// логотип-пині мен сары толқындар, маршрут жолмен салынған) және
/// сүйретілетін ақ панель — сары күй карточкасы (өткен уақыт, жол бойымен
/// жүріп келе жатқан көлік), ұсыныстар, баға карточкасы, маршрут,
/// «Заказды тоқтату».
///
/// Логика: ұсынысты қабылдау/қабылдамау — [_OfferCard], бағаны көтеру —
/// [_RaisePriceHint] (автоматты кеңес те, баға карточкасындағы батырма да),
/// бас тарту — ата-экранның себеп таңдайтын `_cancel` ағыны. Орындаушы
/// табылған сәтте заказ стримі жаңа статус әкеледі де, бұл виджет алынып,
/// әдеттегі экран көрінеді (таймер, ұсыныстар жазылымы `dispose`-та
/// жабылады).
class _SearchingScreen extends StatefulWidget {
  final Order order;
  final VoidCallback onCancel;

  /// `null` — «Бөлісу» фичасы өшулі (модератор баптауы).
  final VoidCallback? onShare;

  const _SearchingScreen({
    required this.order,
    required this.onCancel,
    this.onShare,
  });

  @override
  State<_SearchingScreen> createState() => _SearchingScreenState();
}

class _SearchingScreenState extends State<_SearchingScreen> {
  static const _minSize = 0.38;
  static const _initialSize = 0.47;

  /// Алғашқы ұсыныс келгенде панель осы биіктікке дейін өзі көтеріледі.
  static const _offersSize = 0.64;

  final _sheet = DraggableScrollableController();
  final _map = MapController();

  /// Панельдің ағымдағы биіктігі (үлесі) — OSM жазуын панельдің дәл
  /// үстінде ұстау үшін.
  final _extent = ValueNotifier<double>(_initialSize);

  /// Іздеу басталғаннан бергі секунд. Секунд сайын тек таймер мәтіні
  /// қайта салынады — бүкіл экран емес.
  final _elapsed = ValueNotifier<int>(0);

  /// Заказдың БАРЛЫҚ ұсынысы (pending + rejected) — бас тарту санын
  /// «бағаны көтеріңіз» кеңесі үшін де білу керек.
  final _allOffers = ValueNotifier<List<Offer>>(const []);

  /// Маршруттың нақты жол геометриясы (бос — әзірге доға).
  List<LatLng> _road = const [];

  /// Клиент картаны өзі жылжытты ма — жылжытса, жол келгенде камераны
  /// қайта кадрлап, оның қарап тұрған жерін «тартып» әкетпейміз.
  bool _userMoved = false;
  bool _mapReady = false;
  double _screenH = 0;

  final DateTime _openedAt = DateTime.now();
  Timer? _ticker;
  StreamSubscription<List<Offer>>? _offersSub;

  List<LatLng> get _waypoints {
    final o = widget.order;
    return [
      LatLng(o.fromLat, o.fromLng),
      for (final st in o.stops) LatLng(st.lat, st.lng),
      LatLng(o.toLat, o.toLng),
    ];
  }

  @override
  void initState() {
    super.initState();
    _tick();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    // Стрим БІР рет тыңдалады (build ішінде құрылса, әр 3 секундтағы
    // заказ жаңартуында сұрау тізбегі қайта басталатын еді).
    _offersSub = Repo.offersStream(
      widget.order.id,
    ).listen(_onOffers, onError: (_) {});
    Geo.routeVia(_waypoints).then((r) {
      if (!mounted || !r.onRoad) return;
      setState(() => _road = r.points);
      if (!_userMoved) _fit();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _offersSub?.cancel();
    _sheet.dispose();
    _extent.dispose();
    _elapsed.dispose();
    _allOffers.dispose();
    super.dispose();
  }

  void _tick() {
    final start = widget.order.createdAt ?? _openedAt;
    final sec = DateTime.now().difference(start).inSeconds;
    // Құрылғы сағаты сервердікінен артта қалса — теріс сан шықпасын.
    _elapsed.value = sec < 0 ? 0 : sec;
  }

  static List<Offer> _pendingOf(List<Offer> all) =>
      all.where((of) => of.status == 'pending').toList()
        ..sort((a, b) => a.price.compareTo(b.price));

  void _onOffers(List<Offer> all) {
    if (!mounted) return;
    final before = _pendingOf(_allOffers.value).length;
    _allOffers.value = all;
    final now = _pendingOf(all).length;
    // Алғашқы ұсыныс келгенде панель өзі ашылады — ұсыныс көзден тыс
    // (панельдің төменгі жағында) қалып қоймасын.
    if (before == 0 &&
        now > 0 &&
        _sheet.isAttached &&
        _sheet.size < _offersSize - 0.02) {
      _sheet.animateTo(
        _offersSize,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    }
  }

  /// Картаның төменгі шегінісі: панельдің бастапқы биіктігі картаның
  /// астыңғы жиегінен қаншалық жоғары шығатыны + аздаған ауа.
  EdgeInsets _fitPadding() {
    final top = MediaQuery.paddingOf(context).top + 84;
    final bottom = _screenH * (_initialSize - _minSize) + 28 + 36;
    return EdgeInsets.fromLTRB(56, top, 56, bottom);
  }

  List<LatLng> get _framePoints => [..._waypoints, ..._road];

  void _fit() {
    if (!_mapReady || !mounted) return;
    final pts = _framePoints;
    if (_isPoint(pts)) {
      _map.move(pts.first, 15.5);
      return;
    }
    _map.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(pts),
        padding: _fitPadding(),
        maxZoom: 16.5,
      ),
    );
  }

  static bool _isPoint(List<LatLng> pts) {
    final b = LatLngBounds.fromPoints(pts);
    return (b.north - b.south).abs() < 1e-6 && (b.east - b.west).abs() < 1e-6;
  }

  Future<void> _openRaise(Order o) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Gz.surface,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.viewInsetsOf(ctx).bottom,
        ),
        child: SafeArea(
          top: false,
          child: _RaisePriceHint(
            order: o,
            manual: true,
            onRaised: () => Navigator.of(ctx).maybePop(),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final scheduled = o.isScheduledPending;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: Gz.bg,
        body: LayoutBuilder(
          builder: (context, box) {
            final h = box.maxHeight;
            _screenH = h;
            final topPad = MediaQuery.paddingOf(context).top;
            // Панель ең жоғары көтерілгенде де «Артқа» батырмасын жаппауы
            // керек — шегі экран биіктігінен есептеледі.
            final maxSize = ((h - topPad - 68) / h).clamp(0.6, 0.9);
            // Карта панельдің ең төменгі күйінің астына сәл кіреді (панельдің
            // дөңгелек бұрыштарының артында бос фон көрінбеуі үшін).
            final mapBottom = h * _minSize - 28;
            return Stack(
              children: [
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  bottom: mapBottom,
                  child: _mapView(o, scheduled),
                ),
                // Жоғарғы перде — батырмалар ашық тайлда да анық көрінеді.
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Container(
                      height: topPad + 64,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Gz.bg.withValues(alpha: 0.85),
                            Gz.bg.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // OSM тайлдарының дерек көзі (OSMF талабы) — панельдің үстінде.
                ValueListenableBuilder<double>(
                  valueListenable: _extent,
                  builder: (_, ext, child) => ext > 0.7
                      ? const SizedBox.shrink()
                      : Positioned(
                          left: 12,
                          bottom: h * ext + 10,
                          child: child!,
                        ),
                  child: const _OsmAttribution(),
                ),
                NotificationListener<DraggableScrollableNotification>(
                  onNotification: (n) {
                    _extent.value = n.extent;
                    return false;
                  },
                  child: DraggableScrollableSheet(
                    controller: _sheet,
                    initialChildSize: _initialSize,
                    minChildSize: _minSize,
                    maxChildSize: maxSize,
                    builder: (context, scroll) =>
                        _sheetBody(o, scroll, scheduled),
                  ),
                ),
                // Батырмалар ЕҢ ҮСТІНДЕ: панель ешқашан оларды жаппайды.
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: Row(
                        children: [
                          SearchMapButton(
                            icon: Icons.arrow_back_rounded,
                            tooltip: MaterialLocalizations.of(
                              context,
                            ).backButtonTooltip,
                            onTap: () => Navigator.of(context).maybePop(),
                          ),
                          const Spacer(),
                          if (widget.onShare != null)
                            SearchMapButton(
                              icon: Icons.ios_share,
                              tooltip: t('Бөлісу'),
                              onTap: widget.onShare!,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Толық экранды карта: маршрут (жолмен), аялдамалар мен соңғы нүкте
  /// (қосымшаның бірыңғай белгілері), алу нүктесінде — Tasu маягы.
  Widget _mapView(Order o, bool scheduled) {
    final pickup = LatLng(o.fromLat, o.fromLng);
    final waypoints = _waypoints;
    final single = _isPoint(waypoints);
    return FlutterMap(
      mapController: _map,
      options: MapOptions(
        onMapReady: () {
          _mapReady = true;
          if (_road.isNotEmpty && !_userMoved) _fit();
        },
        onPositionChanged: (_, hasGesture) {
          if (hasGesture) _userMoved = true;
        },
        initialCenter: pickup,
        initialZoom: 15.5,
        initialCameraFit: single
            ? null
            : CameraFit.bounds(
                bounds: LatLngBounds.fromPoints(waypoints),
                padding: _fitPadding(),
                maxZoom: 16.5,
              ),
        backgroundColor: Gz.bg,
        // Бұру өшірулі — кездейсоқ қисайып қалған карта ең жиі шағым.
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: [
        osmTileLayer(),
        if (!single)
          PolylineLayer(
            polylines: routePolylines(
              _road.isNotEmpty ? _road : waypoints,
              onRoad: _road.isNotEmpty,
            ),
          ),
        MarkerLayer(
          markers: [
            for (var i = 0; i < o.stops.length; i++)
              pointMarker(
                LatLng(o.stops[i].lat, o.stops[i].lng),
                color: Gz.violet,
                number: i + 1,
                size: 27,
              ),
            pointMarker(LatLng(o.toLat, o.toLng), color: Gz.red, size: 32),
            // Жоспарланған тапсырыс әлі ІЗДЕЛМЕЙДІ (орындаушыларға
            // көрінбейді) — толқындар оны адастырар еді, тек тыныш пин.
            Marker(
              point: pickup,
              width: TasuPickupBeacon.width,
              height: TasuPickupBeacon.height,
              alignment: Alignment.center,
              child: TasuPickupBeacon(active: !scheduled),
            ),
          ],
        ),
      ],
    );
  }

  Widget _sheetBody(Order o, ScrollController scroll, bool scheduled) {
    return Container(
      decoration: const BoxDecoration(
        color: Gz.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        boxShadow: [
          BoxShadow(
            color: Color(0x24101828),
            blurRadius: 24,
            offset: Offset(0, -4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      // SingleChildScrollView (ListView емес): ішіндегі күйлі виджеттер
      // (бағаны көтеру снузы, батырмалардың «жүктелуде» күйі) панель
      // айналдырылғанда жойылып кетпейді.
      child: SingleChildScrollView(
        controller: scroll,
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.paddingOf(context).bottom,
        ),
        child: ValueListenableBuilder<List<Offer>>(
          valueListenable: _allOffers,
          builder: (context, all, _) => _sheetContent(o, all, scheduled),
        ),
      ),
    );
  }

  Widget _sheetContent(Order o, List<Offer> all, bool scheduled) {
    final offers = _pendingOf(all);
    final rejectedCount = all.where((of) => of.status == 'rejected').length;
    final ageMin = o.createdAt == null
        ? 0
        : DateTime.now().difference(o.createdAt!).inMinutes;
    // Кеңес: 5+ бас тарту немесе 15+ мин жауапсыз → бағаны көтеру
    final suggestRaise =
        !scheduled && (rejectedCount >= 5 || (offers.isEmpty && ageMin >= 15));

    final meta = [
      if (o.distanceKm > 0) Geo.formatDistance(o.distanceKm),
      o.intercity ? t('Қалааралық') : t('Қала ішінде'),
    ].join(' · ');
    final details = <Widget>[
      if (o.cargoDesc.isNotEmpty) InfoRow(t('Жүк'), o.cargoDesc),
      if (o.comment.isNotEmpty) InfoRow(t('Түсініктеме'), o.comment),
    ];

    final status = scheduled
        ? SearchStatusCard(
            color: Gz.violet.withValues(alpha: 0.14),
            title: t('Жоспарланған тапсырыс'),
            subtitle: t('Орындаушыларға көрінбейді'),
            bottom: Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: Row(
                children: [
                  const Icon(Icons.event_rounded, size: 18, color: Gz.violet),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      fmtDate(o.scheduledAt),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: Gz.violet,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
        : SearchStatusCard(
            badge: offers.isEmpty ? null : SearchCountBadge(offers.length),
            title: offers.isEmpty
                ? t('Орындаушы іздеп жатырмыз')
                : t('Ұсыныстар келді'),
            subtitle: offers.isEmpty
                ? t(
                    'Заказыңыз сәйкес орындаушыларға жіберілді — '
                    'ұсыныстары осында шығады.',
                  )
                : t('Ең қолайлы ұсынысты таңдаңыз'),
            trailing: SearchTimerChip(seconds: _elapsed),
            bottom: SearchRoadStrip(vehicle: o.vehicleType),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SearchSheetHandle(),
        status,
        const SizedBox(height: 12),
        // ── Ұсыныстар ────────────────────────────────────────────────
        // Кілттер: тізім өзгергенде кеңестің (снуз) және батырмалардың
        // күйі басқа карточкаға «ауысып» кетпеуі үшін.
        if (suggestRaise)
          _RaisePriceHint(key: const ValueKey('raise-hint'), order: o),
        for (final offer in offers) ...[
          _OfferCard(
            key: ValueKey('offer-${offer.id}'),
            offer: offer,
            clientPrice: o.clientPrice,
          ),
          const SizedBox(height: 8),
        ],
        if (offers.isNotEmpty) const SizedBox(height: 4),
        // ── Баға, маршрут, жүк ───────────────────────────────────────
        SearchPriceCard(
          vehicle: o.vehicleType,
          meta: meta,
          price: fmtT(o.clientPrice ?? o.displayPrice),
          onRaise: () => _openRaise(o),
        ),
        const SizedBox(height: 10),
        SectionCard(
          padding: const EdgeInsets.all(14),
          child: RouteLine(
            from: o.fromDisplay,
            to: o.toDisplay,
            stops: o.stops.map((st) => st.display).toList(),
          ),
        ),
        if (details.isNotEmpty) ...[
          const SizedBox(height: 10),
          SectionCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Column(children: details),
          ),
        ],
        if (o.photos.isNotEmpty) ...[
          const SizedBox(height: 12),
          OrderPhotosStrip(paths: o.photos),
        ],
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: widget.onCancel,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            foregroundColor: Gz.red,
            side: const BorderSide(color: Gz.red),
          ),
          icon: const Icon(Icons.close_rounded),
          label: Text(t('Заказды тоқтату')),
        ),
      ],
    );
  }
}

/// «© OpenStreetMap» — тайлдарды пайдаланғанда сілтеме міндетті.
class _OsmAttribution extends StatelessWidget {
  const _OsmAttribution();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Gz.surface.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(9),
        ),
        child: const Text(
          '© OpenStreetMap',
          style: TextStyle(
            fontSize: 9.5,
            height: 1.1,
            fontWeight: FontWeight.w700,
            color: Gz.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// «Бағаны сәл көтеріңіз» кеңесі + жылдам көтеру.
///
/// Дайын қадамдар КІШІ (100–500) — клиентке 1000/2000 деген секірістер тым
/// үлкен. Оның үстіне клиент өз қалауынша, 100-ден қадаммен, кез келген
/// сомаға көтере алады. Бір рет көтерген соң кеңес БІРАЗ УАҚЫТҚА жасырылады
/// (жаңа ұсыныс күтуге мүмкіндік беру үшін) — тек `order.createdAt`-қа
/// қарасақ, баға көтерілсе де «ескі» деп қала беретін, сол себепті жасыру
/// мерзімін осы виджеттің ӨЗІ (жергілікті `_snoozedUntil`) есептейді.
class _RaisePriceHint extends StatefulWidget {
  final Order order;

  /// `true` — клиент «Бағаны көтеру» батырмасын өзі басты (төменгі
  /// парақта ашылады): тақырып пен түсініктеме «кеңес» емес, әрекет.
  final bool manual;

  /// Баға сәтті көтерілгенде (мыс. парақты жабу үшін).
  final VoidCallback? onRaised;
  const _RaisePriceHint({
    super.key,
    required this.order,
    this.manual = false,
    this.onRaised,
  });

  @override
  State<_RaisePriceHint> createState() => _RaisePriceHintState();
}

class _RaisePriceHintState extends State<_RaisePriceHint> {
  static const _presets = [100, 200, 300, 500];
  static const _snoozeDuration = Duration(minutes: 15);

  DateTime? _snoozedUntil;
  final _customCtrl = TextEditingController(text: '100');
  bool _busy = false;

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  bool get _snoozed =>
      _snoozedUntil != null && DateTime.now().isBefore(_snoozedUntil!);

  void _stepCustom(int delta) {
    final v = (int.tryParse(_customCtrl.text.trim()) ?? 100) + delta;
    setState(() => _customCtrl.text = '${v < 100 ? 100 : v}');
  }

  /// Соңғы сәтті көтерілген баға. Заказ стримі жаңа бағаны бірнеше
  /// секундтан кейін ғана әкеледі — сол аралықта қайта басса, ескі бағаға
  /// емес, ЖАҢАСЫНА қосылуы үшін.
  int? _lastPrice;

  Future<void> _raise(int add) async {
    // Негіз — клиенттің ағымдағы бағасы. Бұрын `clientPrice ?? 0` еді:
    // баға бос болса «+100» бағаны 100 ₸-ге ТҮСІРІП жіберетін.
    final cur =
        _lastPrice ?? widget.order.clientPrice ?? widget.order.displayPrice;
    if (cur == null || cur <= 0) return;
    setState(() => _busy = true);
    try {
      await Repo.updateOrderPrice(widget.order.id, cur + add);
      _lastPrice = cur + add;
      if (mounted) {
        setState(() => _snoozedUntil = DateTime.now().add(_snoozeDuration));
        showSnack(context, '${t('Жаңа баға:')} ${fmtT(cur + add)}');
        widget.onRaised?.call();
      }
    } catch (e) {
      if (mounted) showSnack(context, errText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Тек виджетті «алып тастамай» тұрамыз — StreamBuilder бірнеше секунд
    // сайын қайта саламын дегендіктен, снуз мерзімі біткенде өзі қайта
    // пайда болады (бөлек Timer қажет емес).
    if (_snoozed && !widget.manual) return const SizedBox.shrink();
    final custom = int.tryParse(_customCtrl.text.trim()) ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E0),
        borderRadius: BorderRadius.circular(Gz.radius),
        border: Border.all(color: Gz.yellowDark.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                widget.manual ? Icons.trending_up_rounded : Icons.lightbulb,
                color: Gz.yellowDark,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.manual
                      ? t('Бағаны көтеру')
                      : t('Бағаны сәл көтеріп көріңіз'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            widget.manual
                ? t('Баға жоғары болса, орындаушылар тезірек жауап береді.')
                : t(
                    'Ұзақ уақыт жауап жоқ немесе орындаушылар келіспей жатыр. '
                    'Бағаны көтерсеңіз, тезірек табыласыз.',
                  ),
            style: const TextStyle(color: Gz.textSecondary, fontSize: 12.5),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final add in _presets)
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  onPressed: _busy ? null : () => _raise(add),
                  child: Text('+${fmtT(add)}'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            t('Немесе өзіңіз көтеріңіз'),
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
              color: Gz.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _StepBtn(
                icon: Icons.remove_rounded,
                onTap: _busy ? null : () => _stepCustom(-100),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _customCtrl,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 8,
                    ),
                    suffixText: '₸',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _StepBtn(
                icon: Icons.add_rounded,
                onTap: _busy ? null : () => _stepCustom(100),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: (_busy || custom < 100)
                    ? null
                    : () => _raise(custom),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                child: Text(t('Қолдану')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Баптау степперіндегі дөңгелек +/- батырмасы.
class _StepBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _StepBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Gz.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Gz.yellowDark.withValues(alpha: 0.4)),
        ),
        child: Icon(icon, size: 20, color: Gz.yellowDark),
      ),
    );
  }
}

class _OfferCard extends StatelessWidget {
  final Offer offer;
  final int? clientPrice;
  const _OfferCard({super.key, required this.offer, this.clientPrice});

  @override
  Widget build(BuildContext context) {
    final samePrice = clientPrice != null && offer.price == clientPrice;
    return SectionCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _ExecutorBrief(executorId: offer.executorId)),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    fmtT(offer.price),
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: samePrice ? Gz.green : Gz.ink,
                    ),
                  ),
                  Text(
                    samePrice ? t('Бағаңызға келісті') : t('Қарсы ұсыныс'),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: samePrice ? Gz.green : Gz.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (offer.message.isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '«${offer.message}»',
                style: const TextStyle(
                  color: Gz.textSecondary,
                  fontStyle: FontStyle.italic,
                  fontSize: 13,
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    // Ұзын мәтін («Отклонить») тар батырмада сынбауы үшін
                    // көлденең padding кішірейтілген.
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    foregroundColor: Gz.red,
                    side: const BorderSide(color: Gz.border),
                  ),
                  onPressed: () async {
                    try {
                      await Repo.rejectOffer(offer.id);
                    } catch (e) {
                      if (context.mounted) {
                        showSnack(context, errText(e), error: true);
                      }
                    }
                  },
                  child: BtnLabel(t('Қабылдамау')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: BusyButton(
                  label: '${t('Қабылдау')} · ${fmtT(offer.price)}',
                  onPressed: () async {
                    try {
                      await Repo.acceptOffer(offer.id);
                    } catch (e) {
                      if (context.mounted) {
                        showSnack(context, errText(e), error: true);
                      }
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Орындаушының қысқа профилі (аты, рейтинг, көлігі).
///
/// Профиль БІР рет жүктеледі: ұсыныстар/заказ стримі әр 4 секунд сайын
/// панельді қайта салады — әр жолы желіге қайта сұрау жібермеуі үшін.
class _ExecutorBrief extends StatefulWidget {
  final String executorId;
  const _ExecutorBrief({required this.executorId});

  @override
  State<_ExecutorBrief> createState() => _ExecutorBriefState();
}

class _ExecutorBriefState extends State<_ExecutorBrief> {
  late Future<List<Object?>> _future = _load();

  Future<List<Object?>> _load() => Future.wait<Object?>([
    Repo.profileOf(widget.executorId),
    Repo.executorProfileOf(widget.executorId),
  ]);

  @override
  void didUpdateWidget(_ExecutorBrief old) {
    super.didUpdateWidget(old);
    if (old.executorId != widget.executorId) _future = _load();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Object?>>(
      future: _future,
      builder: (context, snap) {
        final p = snap.data?[0] as Profile?;
        final ep = snap.data?[1] as ExecutorProfile?;
        return Row(
          children: [
            InitialsAvatar(
              p?.fullName ?? '?',
              radius: 20,
              imageUrl: p?.avatarUrl,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p?.fullName ?? '…',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14.5,
                    ),
                  ),
                  // Клиент ОРЫНДАУШЫНЫ көреді → орындаушылық рейтинг/рейс
                  // (қос рөл, 0046: адамның клиенттік бағасы бөлек жүреді).
                  Row(
                    children: [
                      RatingStars(
                        p?.ratingAs('executor') ?? 0,
                        count: p?.ratingCountAs('executor') ?? 0,
                        size: 13,
                      ),
                      if ((p?.tripsAs('executor') ?? 0) > 0)
                        Text(
                          '  · ${p!.tripsAs('executor')} ${t('рейс')}',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: Gz.textSecondary,
                          ),
                        ),
                    ],
                  ),
                  // Ұсыныс кезінде газель нөмірі көрсетілмейді (тек маркасы)
                  if (ep != null)
                    Text(
                      ep.vehicleTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Gz.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ===================== ОРЫНДАУШЫ КАРТАСЫ =====================
class _ExecutorCard extends StatelessWidget {
  final String executorId;
  final bool showCall;
  const _ExecutorCard({required this.executorId, this.showCall = true});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: Future.wait([
        Repo.profileOf(executorId),
        Repo.executorProfileOf(executorId),
      ]),
      builder: (context, snap) {
        final p = snap.data?[0] as Profile?;
        final ep = snap.data?[1] as ExecutorProfile?;
        return SectionCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Row(
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
                        Text(
                          p?.fullName ?? t('Орындаушы'),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        // Орындаушының РӨЛДІК рейтингі (қос рөл, 0046).
                        Row(
                          children: [
                            RatingStars(
                              p?.ratingAs('executor') ?? 0,
                              count: p?.ratingCountAs('executor') ?? 0,
                              size: 14,
                            ),
                            if ((p?.tripsAs('executor') ?? 0) > 0)
                              Text(
                                '  · ${p!.tripsAs('executor')} ${t('рейс')}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Gz.textSecondary,
                                ),
                              ),
                          ],
                        ),
                        if (ep != null)
                          Text(
                            '${ep.vehicleTitle} · ${ep.vehiclePlate}',
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: Gz.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (showCall && p != null && p.phone.isNotEmpty)
                    IconButton.filled(
                      style: IconButton.styleFrom(
                        backgroundColor: Gz.green,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => launchUrl(
                        Uri(scheme: 'tel', path: Phone.dial(p.phone)),
                      ),
                      icon: const Icon(Icons.call),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

// ===================== БАРЫС (timeline) =====================
class _Timeline extends StatelessWidget {
  final String status;
  final VehicleType vehicleType;
  const _Timeline({required this.status, required this.vehicleType});

  static const _steps = [
    ('accepted', 'Орындаушы жолда'),
    ('arrived', 'Келді'),
    ('loading', 'Тиеу'),
    ('in_transit', 'Тасымалдауда'),
    ('completed', 'Аяқталды'),
  ];

  @override
  Widget build(BuildContext context) {
    final isTaxi = vehicleType == VehicleType.taxi;
    final steps = [
      for (final s in _steps)
        (s.$1, t(s.$1 == 'loading' && isTaxi ? 'Отырғызу' : s.$2)),
    ];
    final idx = steps.indexWhere((s) => s.$1 == status);
    return SectionCard(
      child: Column(
        children: [
          for (var i = 0; i < steps.length; i++)
            Row(
              children: [
                Column(
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: i <= idx ? Gz.green : Gz.bg,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: i <= idx ? Gz.green : Gz.border,
                        ),
                      ),
                      child: i < idx
                          ? const Icon(
                              Icons.check,
                              size: 14,
                              color: Colors.white,
                            )
                          : i == idx
                          ? const Icon(
                              Icons.radio_button_checked,
                              size: 14,
                              color: Colors.white,
                            )
                          : null,
                    ),
                    if (i < steps.length - 1)
                      Container(
                        width: 2,
                        height: 18,
                        color: i < idx ? Gz.green : Gz.border,
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Text(
                    steps[i].$2,
                    style: TextStyle(
                      fontWeight: i == idx ? FontWeight.w800 : FontWeight.w500,
                      color: i <= idx ? Gz.ink : Gz.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
