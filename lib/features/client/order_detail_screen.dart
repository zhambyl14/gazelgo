import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' show Marker;
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/env.dart';
import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/map_widgets.dart';
import '../../shared/widgets.dart';
import '../support/support_screen.dart';
import 'address_picker.dart';
import 'create_order_screen.dart';

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
      await SharePlus.instance.share(ShareParams(
        text:
            '${t('Менің тапсырысымның барысын осы сілтемеден қадағалауға болады')}: $url',
      ));
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
          maybeShowReviewDialog(context,
              orderId: o.id, title: t('Орындаушыны бағалаңыз'));
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
    final reason = await pickCancelReason(context,
        title: t('Заказды тоқтату'),
        presets: [for (final r in _clientCancelReasons) t(r)]);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t('Заказ'))),
      body: StreamBuilder<Order?>(
        stream: Repo.orderStream(widget.orderId),
        builder: (context, snap) {
          final o = snap.data;
          if (o == null) {
            return const Center(child: CircularProgressIndicator());
          }
          _maybeCleanupPhotos(o);
          _maybeShowReview(o);
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(fmtT(o.displayPrice),
                          style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5)),
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
                if (_liveTrackingEnabled && _liveStatuses.contains(o.status))
                  StreamBuilder<Map<String, dynamic>?>(
                    stream: Repo.orderExecutorLocationStream(o.id),
                    builder: (context, locSnap) {
                      final loc = locSnap.data;
                      final extra = <Marker>[
                        if (loc != null && loc['lat'] != null)
                          executorLiveMarker(LatLng(
                            (loc['lat'] as num).toDouble(),
                            (loc['lng'] as num).toDouble(),
                          )),
                      ];
                      return RouteMap(
                        from: LatLng(o.fromLat, o.fromLng),
                        to: LatLng(o.toLat, o.toLng),
                        stops:
                            o.stops.map((s) => LatLng(s.lat, s.lng)).toList(),
                        height: 160,
                        extraMarkers: extra,
                      );
                    },
                  )
                else
                  RouteMap(
                    from: LatLng(o.fromLat, o.fromLng),
                    to: LatLng(o.toLat, o.toLng),
                    stops: o.stops.map((s) => LatLng(s.lat, s.lng)).toList(),
                    height: 160,
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
                      if (o.comment.isNotEmpty)
                          InfoRow(t('Түсініктеме'), o.comment),
                      InfoRow(t('Көлік'), o.vehicleType.label),
                      if (o.distanceKm > 0)
                        InfoRow(t('Қашықтық'),
                            '${o.distanceKm.toStringAsFixed(1)} км'),
                      InfoRow(t('Бағыты'),
                          o.intercity ? t('Қалааралық (межгород)') : t('Қала ішінде')),
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
                const SizedBox(height: 14),
                ..._statusSection(o),
                const SizedBox(height: 14),
                // Бас тарту: searching/accepted/arrived — процесте болмаса
                if (['searching', 'accepted', 'arrived'].contains(o.status))
                  OutlinedButton.icon(
                    onPressed: _cancel,
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Gz.red,
                        side: const BorderSide(color: Gz.red)),
                    icon: const Icon(Icons.close),
                    label: Text(t('Заказды тоқтату')),
                  ),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }

  List<Widget> _statusSection(Order o) {
    switch (o.status) {
      case 'searching':
        return [
          if (o.isScheduledPending) ...[
            _ScheduledBadge(scheduledAt: o.scheduledAt!),
            const SizedBox(height: 10),
          ],
          _OffersSection(order: o),
        ];
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
            child: Row(children: [
              const Icon(Icons.info_outline, color: Gz.red),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  (o.cancelReason?.isNotEmpty ?? false)
                      ? '${t('Себебі:')} ${o.cancelReason}'
                      : t('Заказ тоқтатылды'),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 10),
          if (_repeatOrderEnabled) _ReorderButton(onPressed: () => _reorder(o)),
        ];
      default:
        return [
          SectionCard(
            child: Row(children: [
              const Icon(Icons.schedule, color: Gz.textSecondary),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(t('Заказдың мерзімі өтті — ешкім қабылдамады.'))),
            ]),
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

/// Алдын ала тапсырыс (0060) — белгіленген уақыты әлі келмегенде
/// «Іздеуде» орнына көрсетіледі: орындаушыларға ол уақытқа дейін көрінбейді.
class _ScheduledBadge extends StatelessWidget {
  final DateTime scheduledAt;
  const _ScheduledBadge({required this.scheduledAt});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Gz.violet.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(Gz.radius),
        border: Border.all(color: Gz.violet.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.schedule_outlined, color: Gz.violet),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t('Жоспарланған тапсырыс'),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 14)),
                const SizedBox(height: 2),
                Text(
                  t('Орындаушыларға көрінбейді'),
                  style: const TextStyle(color: Gz.textSecondary, fontSize: 12.5),
                ),
                const SizedBox(height: 2),
                Text(
                  fmtDate(scheduledAt),
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5,
                      color: Gz.violet),
                ),
              ],
            ),
          ),
        ],
      ),
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
              Icon(isTaxi ? Icons.person : Icons.local_shipping,
                  color: Gz.green),
              const SizedBox(width: 10),
              Expanded(
                child: Text(t('Орындаушы жеткен жоқ па?'),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 15)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            isTaxi
                ? t('Орындаушы келіп, сіз отырсаңыз — растаңыз. Растамайынша '
                    'орындаушы жолға шыға алмайды.')
                : t('Орындаушы келіп, тиеу басталса — растаңыз. Растамайынша '
                    'орындаушы жолға шыға алмайды.'),
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
                if (context.mounted) showSnack(context, errText(e), error: true);
              }
            },
          ),
        ],
      ),
    );
  }
}

// ===================== ҰСЫНЫСТАР (bidding) =====================
class _OffersSection extends StatelessWidget {
  final Order order;
  const _OffersSection({required this.order});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Offer>>(
      stream: Repo.offersStream(order.id),
      builder: (context, snap) {
        final all = snap.data ?? [];
        final offers = all.where((of) => of.status == 'pending').toList()
          ..sort((a, b) => a.price.compareTo(b.price));
        final rejectedCount =
            all.where((of) => of.status == 'rejected').length;
        final ageMin = order.createdAt == null
            ? 0
            : DateTime.now().difference(order.createdAt!).inMinutes;
        // Кеңес: 5+ бас тарту немесе 15+ мин жауапсыз → бағаны көтеру
        final suggestRaise = rejectedCount >= 5 || (offers.isEmpty && ageMin >= 15);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(t('Ұсыныстар'),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(width: 8),
                if (offers.isNotEmpty)
                  CircleAvatar(
                    radius: 11,
                    backgroundColor: Gz.yellow,
                    child: Text('${offers.length}',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Gz.ink)),
                  ),
                const Spacer(),
                const _PulsingDot(),
                const SizedBox(width: 6),
                Text(t('Іздеуде…'),
                    style: const TextStyle(color: Gz.blue, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 8),
            if (suggestRaise) _RaisePriceHint(order: order),
            if (offers.isEmpty && !suggestRaise)
              SectionCard(
                child: Text(
                  t('Орындаушылардың ұсыныстары осында шығады. '
                      'Әдетте бірнеше минут ішінде жауап келеді.'),
                  style: const TextStyle(color: Gz.textSecondary, fontSize: 13.5),
                ),
              ),
            for (final offer in offers) ...[
              _OfferCard(offer: offer, clientPrice: order.clientPrice),
              const SizedBox(height: 8),
            ],
          ],
        );
      },
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
  const _RaisePriceHint({required this.order});

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

  Future<void> _raise(int add) async {
    final cur = widget.order.clientPrice ?? 0;
    setState(() => _busy = true);
    try {
      await Repo.updateOrderPrice(widget.order.id, cur + add);
      if (mounted) {
        setState(() => _snoozedUntil = DateTime.now().add(_snoozeDuration));
        showSnack(context, '${t('Жаңа баға:')} ${fmtT(cur + add)}');
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
    if (_snoozed) return const SizedBox.shrink();
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
              const Icon(Icons.lightbulb, color: Gz.yellowDark, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(t('Бағаны сәл көтеріп көріңіз'),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 14.5)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            t('Ұзақ уақыт жауап жоқ немесе орындаушылар келіспей жатыр. '
                'Бағаны көтерсеңіз, тезірек табыласыз.'),
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
                      padding: const EdgeInsets.symmetric(horizontal: 12)),
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
                color: Gz.textSecondary),
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
                      fontWeight: FontWeight.w800, fontSize: 15),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(vertical: 10, horizontal: 8),
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
                onPressed: (_busy || custom < 100) ? null : () => _raise(custom),
                style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 14)),
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
  const _OfferCard({required this.offer, this.clientPrice});

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
                  Text(fmtT(offer.price),
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: samePrice ? Gz.green : Gz.ink)),
                  Text(samePrice ? t('Бағаңызға келісті') : t('Қарсы ұсыныс'),
                      style: TextStyle(
                          fontSize: 11.5,
                          color: samePrice ? Gz.green : Gz.textSecondary)),
                ],
              ),
            ],
          ),
          if (offer.message.isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('«${offer.message}»',
                  style: const TextStyle(
                      color: Gz.textSecondary,
                      fontStyle: FontStyle.italic,
                      fontSize: 13)),
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
                      side: const BorderSide(color: Gz.border)),
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
class _ExecutorBrief extends StatelessWidget {
  final String executorId;
  const _ExecutorBrief({required this.executorId});

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
        return Row(
          children: [
            InitialsAvatar(p?.fullName ?? '?', radius: 20, imageUrl: p?.avatarUrl),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p?.fullName ?? '…',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 14.5)),
                  // Клиент ОРЫНДАУШЫНЫ көреді → орындаушылық рейтинг/рейс
                  // (қос рөл, 0046: адамның клиенттік бағасы бөлек жүреді).
                  Row(
                    children: [
                      RatingStars(p?.ratingAs('executor') ?? 0,
                          count: p?.ratingCountAs('executor') ?? 0, size: 13),
                      if ((p?.tripsAs('executor') ?? 0) > 0)
                        Text('  · ${p!.tripsAs('executor')} ${t('рейс')}',
                            style: const TextStyle(
                                fontSize: 11.5, color: Gz.textSecondary)),
                    ],
                  ),
                  // Ұсыныс кезінде газель нөмірі көрсетілмейді (тек маркасы)
                  if (ep != null)
                    Text(
                      ep.vehicleTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, color: Gz.textSecondary),
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
                  InitialsAvatar(p?.fullName ?? '?',
                      radius: 24, imageUrl: p?.avatarUrl),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p?.fullName ?? t('Орындаушы'),
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 16)),
                        // Орындаушының РӨЛДІК рейтингі (қос рөл, 0046).
                        Row(children: [
                          RatingStars(p?.ratingAs('executor') ?? 0,
                              count: p?.ratingCountAs('executor') ?? 0,
                              size: 14),
                          if ((p?.tripsAs('executor') ?? 0) > 0)
                            Text('  · ${p!.tripsAs('executor')} ${t('рейс')}',
                                style: const TextStyle(
                                    fontSize: 12, color: Gz.textSecondary)),
                        ]),
                        if (ep != null)
                          Text(
                            '${ep.vehicleTitle} · ${ep.vehiclePlate}',
                            style: const TextStyle(
                                fontSize: 12.5, color: Gz.textSecondary),
                          ),
                      ],
                    ),
                  ),
                  if (showCall && p != null && p.phone.isNotEmpty)
                    IconButton.filled(
                      style: IconButton.styleFrom(
                          backgroundColor: Gz.green,
                          foregroundColor: Colors.white),
                      onPressed: () => launchUrl(
                          Uri(scheme: 'tel', path: p.phone)),
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
        (s.$1, t(s.$1 == 'loading' && isTaxi ? 'Отырғызу' : s.$2))
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
                            color: i <= idx ? Gz.green : Gz.border),
                      ),
                      child: i < idx
                          ? const Icon(Icons.check,
                              size: 14, color: Colors.white)
                          : i == idx
                              ? const Icon(Icons.radio_button_checked,
                                  size: 14, color: Colors.white)
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
                      fontWeight:
                          i == idx ? FontWeight.w800 : FontWeight.w500,
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

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _c,
      child: Container(
        width: 9,
        height: 9,
        decoration:
            const BoxDecoration(color: Gz.blue, shape: BoxShape.circle),
      ),
    );
  }
}
