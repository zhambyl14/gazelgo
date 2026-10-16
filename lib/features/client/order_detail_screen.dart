import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/env.dart';
import '../../core/geo.dart';
import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/map_widgets.dart';
import '../../shared/order_live.dart';
import '../../shared/widgets.dart';
import '../chat/order_chat_screen.dart';
import '../support/support_screen.dart';
import 'address_picker.dart';
import 'create_order_screen.dart';
import 'executor_sheet.dart';
import 'order_extras_editor.dart';
import 'recipient_card.dart';

/// Клиенттің заказ экраны: ұсыныстар → көліктің тірі картасы мен келу
/// уақыты → барыс → пікір.
class OrderDetailScreen extends StatefulWidget {
  final String orderId;
  const OrderDetailScreen({super.key, required this.orderId});

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  late final Stream<Order?> _orderStream = Repo.orderStream(widget.orderId);

  /// Көліктің тірі орны — тек белсенді кезеңде, БІР РЕТ құрылады.
  Stream<Map<String, dynamic>?>? _locStream;

  bool _photosCleaned = false;
  bool _reviewShown = false;

  /// Модератор баптаулары (0060) — бір рет оқылады.
  bool _liveTrackingEnabled = false;
  bool _shareTripEnabled = false;
  bool _repeatOrderEnabled = true;

  /// Таңдаулы/бұғатталған орындаушылар (0077).
  ExecutorPrefs _prefs = const ExecutorPrefs();

  static const _liveStatuses = {'accepted', 'arrived', 'loading', 'in_transit'};

  @override
  void initState() {
    super.initState();
    _loadFeatureFlags();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final p = await ExecutorPrefs.load();
    if (mounted) setState(() => _prefs = p);
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
      // Желі қатесінде — бәрі өшулі қалады, экран сынбайды.
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

  /// Аяқталған заказдың қысқаша «чегі» — бөлісуге (бухгалтерия, есеп).
  Future<void> _shareReceipt(Order o) async {
    String executor = '';
    if (o.executorId != null) {
      final p = await Repo.profileOf(o.executorId!);
      executor = p?.fullName ?? '';
    }
    final lines = [
      'Tasu · ${t('Заказ')} #${o.id.substring(0, 8).toUpperCase()}',
      '${t('Күні')}: ${fmtDate(o.completedAt ?? o.createdAt)}',
      '${t('Қайдан')}: ${o.fromDisplay}',
      for (var i = 0; i < o.stops.length; i++)
        '${t('Аялдама')} ${i + 1}: ${o.stops[i].display}',
      '${t('Қайда')}: ${o.toDisplay}',
      if (o.distanceKm > 0) '${t('Қашықтық')}: ${Geo.formatDistance(o.distanceKm)}',
      '${t('Көлік')}: ${o.vehicleType.label}',
      if (executor.isNotEmpty) '${t('Орындаушы')}: $executor',
      '${t('Баға')}: ${fmtT(o.displayPrice)}',
    ];
    try {
      await SharePlus.instance.share(ShareParams(text: lines.join('\n')));
    } catch (_) {}
  }

  void _maybeShowReview(Order o) {
    if (_reviewShown || o.status != 'completed') return;
    _reviewShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      maybeShowReviewDialog(
        context,
        orderId: o.id,
        title: t('Орындаушыны бағалаңыз'),
        tags: kExecutorReviewTags,
      );
    });
  }

  /// Заказ аяқталса/бас тартылса — тіркелген фотоларды өшіру.
  void _maybeCleanupPhotos(Order o) {
    const terminal = ['completed', 'cancelled', 'expired'];
    if (!_photosCleaned && terminal.contains(o.status) && o.photos.isNotEmpty) {
      _photosCleaned = true;
      Repo.deleteOrderPhotos(o.photos);
    }
  }

  /// Дәл осы маршрутпен ЖАҢА заказ ашады («Тағы да тапсырыс беру»).
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

  Future<void> _edit(Order o) async {
    final res = await showEditOrderSheet(context, o);
    if (res == null || !mounted) return;
    final (cargo, comment, extras) = res;
    final isTaxi = o.vehicleType == VehicleType.taxi;
    try {
      await Repo.updateOrderDetails(
        o.id,
        cargo: cargo,
        comment: comment,
        loaders: isTaxi ? null : extras.loaders,
        floorFrom: isTaxi ? null : extras.floorFrom,
        floorTo: isTaxi ? null : extras.floorTo,
        elevator: isTaxi ? null : extras.elevator,
      );
      if (mounted) showSnack(context, t('Заказ жаңартылды'));
    } catch (e) {
      if (mounted) showSnack(context, errText(e), error: true);
    }
  }

  Future<void> _openExecutor(String executorId) async {
    final kind = await showExecutorSheet(
      context,
      executorId: executorId,
      prefs: _prefs,
    );
    if (kind != null) _loadPrefs();
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
      // Экранда қалдырмаймыз — басты бетке қайтамыз.
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
    return StreamBuilder<Order?>(
      stream: _orderStream,
      builder: (context, snap) {
        final o = snap.data;
        return Scaffold(
          appBar: AppBar(
            title: Text(t('Заказ')),
            actions: [
              if (o != null &&
                  _shareTripEnabled &&
                  !['cancelled', 'expired'].contains(o.status))
                IconButton(
                  tooltip: t('Сапарды бөлісу'),
                  icon: const Icon(Icons.ios_share_rounded),
                  onPressed: () => _shareTrip(o),
                ),
            ],
          ),
          body: o == null
              ? const Center(child: CircularProgressIndicator())
              : _body(o),
        );
      },
    );
  }

  Widget _body(Order o) {
    _maybeCleanupPhotos(o);
    _maybeShowReview(o);
    final live = _liveStatuses.contains(o.status);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        Row(
          children: [
            Expanded(child: Text(fmtT(o.displayPrice), style: Gz.moneyXl)),
            StatusChip(o.status, vehicleType: o.vehicleType),
          ],
        ),
        const SizedBox(height: 12),
        if (live) ..._liveSection(o) else _staticMap(o),
        const SizedBox(height: 10),
        _detailsCard(o),
        if (o.photos.isNotEmpty &&
            !['completed', 'cancelled', 'expired'].contains(o.status)) ...[
          const SizedBox(height: 10),
          OrderPhotosStrip(paths: o.photos),
        ],
        const SizedBox(height: 14),
        ..._statusSection(o),
        if (['searching', 'accepted', 'arrived'].contains(o.status)) ...[
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _cancel,
            style: OutlinedButton.styleFrom(
              foregroundColor: Gz.red,
              side: const BorderSide(color: Gz.red),
            ),
            icon: const Icon(Icons.close),
            label: Text(t('Заказды тоқтату')),
          ),
        ],
      ],
    );
  }

  Widget _staticMap(Order o) => RouteMap(
    from: LatLng(o.fromLat, o.fromLng),
    to: LatLng(o.toLat, o.toLng),
    stops: o.stops.map((s) => LatLng(s.lat, s.lng)).toList(),
    height: 175,
    fromLabel: o.fromDisplay,
    toLabel: o.toDisplay,
    stopLabels: o.stops.map((s) => s.display).toList(),
    distanceKm: o.distanceKm,
  );

  /// Белсенді кезең: көліктің ТІРІ картасы + келу уақыты / күту таймері.
  List<Widget> _liveSection(Order o) {
    Widget cards(LatLng? vehicle) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (o.status == 'accepted' && o.arriveBy != null) ...[
          const SizedBox(height: 10),
          EtaCountdownCard(
            order: o,
            kmLeft: vehicle == null
                ? null
                : Geo.haversineKm(vehicle, LatLng(o.fromLat, o.fromLng)),
          ),
        ],
        if (o.status == 'arrived') ...[
          const SizedBox(height: 10),
          WaitingTimerCard(
            order: o,
            child: _ConfirmLoadingButton(
              orderId: o.id,
              vehicleType: o.vehicleType,
            ),
          ),
        ],
      ],
    );

    if (!_liveTrackingEnabled) return [_staticMap(o), cards(null)];
    _locStream ??= Repo.orderExecutorLocationStream(o.id);
    return [
      StreamBuilder<Map<String, dynamic>?>(
        stream: _locStream,
        builder: (context, snap) {
          final loc = snap.data;
          final lat = (loc?['lat'] as num?)?.toDouble();
          final lng = (loc?['lng'] as num?)?.toDouble();
          final vehicle = lat == null || lng == null ? null : LatLng(lat, lng);
          final at = DateTime.tryParse(loc?['updated_at'] as String? ?? '');
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LiveTrackMap(
                order: o,
                vehicle: vehicle,
                heading: (loc?['heading'] as num?)?.toDouble(),
                ageSec: at == null
                    ? null
                    : DateTime.now().difference(at.toLocal()).inSeconds,
              ),
              cards(vehicle),
            ],
          );
        },
      ),
    ];
  }

  Widget _detailsCard(Order o) {
    final editable = o.status == 'searching';
    return SectionCard(
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
            InfoRow(t('Қашықтық'), '${o.distanceKm.toStringAsFixed(1)} км'),
          InfoRow(
            t('Бағыты'),
            o.intercity ? t('Қалааралық (межгород)') : t('Қала ішінде'),
          ),
          if (o.createdAt != null) InfoRow(t('Құрылды'), fmtDate(o.createdAt)),
          if (o.hasExtras) ...[
            const SizedBox(height: 6),
            OrderExtrasChips(order: o),
          ],
          if (editable) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _edit(o),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: Text(t('Заказды өңдеу')),
              ),
            ),
          ],
        ],
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
          RecipientSection(order: o),
          const SizedBox(height: 10),
          _OffersSection(
            order: o,
            prefs: _prefs,
            onOpenExecutor: _openExecutor,
          ),
        ];
      case 'accepted':
      case 'arrived':
      case 'loading':
      case 'in_transit':
        return [
          _ExecutorCard(
            order: o,
            prefs: _prefs,
            onOpen: () => _openExecutor(o.executorId!),
          ),
          const SizedBox(height: 10),
          RecipientSection(order: o),
          const SizedBox(height: 10),
          _Timeline(status: o.status, vehicleType: o.vehicleType),
          const SizedBox(height: 10),
          SupportOrderButton(orderId: o.id),
          const SizedBox(height: 10),
          ReportSuspiciousButton(orderId: o.id),
        ];
      case 'completed':
        final favorite = _prefs.favorites.contains(o.executorId);
        return [
          // Аяқталған заказда орындаушының телефоны көрсетілмейді.
          _ExecutorCard(
            order: o,
            prefs: _prefs,
            showCall: false,
            onOpen: () => _openExecutor(o.executorId!),
          ),
          const SizedBox(height: 10),
          RecipientSection(order: o),
          ReviewPrompt(
            orderId: o.id,
            title: t('Орындаушыны бағалаңыз'),
            tags: kExecutorReviewTags,
          ),
          if (_prefs.available && !favorite) ...[
            const SizedBox(height: 10),
            GzNotice(
              tone: NoticeTone.accent,
              icon: Icons.favorite_border_rounded,
              title: t('Орындаушы ұнады ма?'),
              message: t('Таңдаулыға қосыңыз — келесі заказыңыз туралы оған '
                  'бірінші болып хабар барады.'),
              actionLabel: t('Таңдаулыға қосу'),
              onAction: () async {
                try {
                  await Repo.setExecutorPref(o.executorId!, 'favorite');
                  await _loadPrefs();
                  if (mounted) showSnack(context, t('Таңдаулыларға қосылды ❤'));
                } catch (e) {
                  if (mounted) showSnack(context, errText(e), error: true);
                }
              },
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              if (_repeatOrderEnabled)
                Expanded(child: _ReorderButton(onPressed: () => _reorder(o))),
              if (_repeatOrderEnabled) const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _shareReceipt(o),
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: Text(t('Чек')),
                ),
              ),
            ],
          ),
        ];
      case 'cancelled':
        return [
          GzNotice(
            tone: NoticeTone.danger,
            message: (o.cancelReason?.isNotEmpty ?? false)
                ? '${t('Себебі:')} ${o.cancelReason}'
                : t('Заказ тоқтатылды'),
          ),
          const SizedBox(height: 10),
          if (_repeatOrderEnabled) _ReorderButton(onPressed: () => _reorder(o)),
        ];
      default:
        return [
          GzNotice(
            tone: NoticeTone.neutral,
            icon: Icons.schedule,
            message: t('Заказдың мерзімі өтті — ешкім қабылдамады.'),
          ),
          const SizedBox(height: 10),
          if (_repeatOrderEnabled) _ReorderButton(onPressed: () => _reorder(o)),
        ];
    }
  }
}

/// «Тағы да тапсырыс беру» — дәл осы маршрутпен жаңа заказ.
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

/// Алдын ала тапсырыс (0060) — белгіленген уақыты әлі келмегенде.
class _ScheduledBadge extends StatelessWidget {
  final DateTime scheduledAt;
  const _ScheduledBadge({required this.scheduledAt});

  @override
  Widget build(BuildContext context) {
    return GzNotice(
      tone: NoticeTone.accent,
      icon: Icons.schedule_outlined,
      title: t('Жоспарланған тапсырыс'),
      message: '${t('Орындаушыларға көрінбейді')} · ${fmtDate(scheduledAt)}',
    );
  }
}

/// Орындаушы келгенін клиент растайды: «Тиеу басталды» → status=loading.
/// Осыдан кейін ғана орындаушы «Жолға шықтық» дей алады (0027).
class _ConfirmLoadingButton extends StatelessWidget {
  final String orderId;
  final VehicleType vehicleType;
  const _ConfirmLoadingButton({
    required this.orderId,
    required this.vehicleType,
  });

  @override
  Widget build(BuildContext context) {
    final isTaxi = vehicleType == VehicleType.taxi;
    return BusyButton(
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
    );
  }
}

// ===================== ҰСЫНЫСТАР (bidding) =====================

enum _OfferSort { best, cheap, fast, rating }

class _OffersSection extends StatefulWidget {
  final Order order;
  final ExecutorPrefs prefs;
  final ValueChanged<String> onOpenExecutor;
  const _OffersSection({
    required this.order,
    required this.prefs,
    required this.onOpenExecutor,
  });

  @override
  State<_OffersSection> createState() => _OffersSectionState();
}

class _OffersSectionState extends State<_OffersSection> {
  /// Стрим БІР РЕТ құрылады — бұрын заказ жаңарған сайын (3–4с) жаңа
  /// polling-цикл ашылатын.
  late final Stream<List<Offer>> _stream = Repo.offersStream(widget.order.id);
  _OfferSort _sort = _OfferSort.best;

  /// Ұсыныс иелерінің профильдері (рейтинг бойынша сұрыптау үшін).
  final Map<String, Profile> _profiles = {};
  final Set<String> _requested = {};

  void _ensureProfiles(List<Offer> offers) {
    final missing = [
      for (final of in offers)
        if (!_requested.contains(of.executorId)) of.executorId,
    ];
    if (missing.isEmpty) return;
    _requested.addAll(missing);
    Repo.profilesByIds(missing).then((m) {
      if (mounted) setState(() => _profiles.addAll(m));
    }, onError: (_) {});
  }

  List<Offer> _sorted(List<Offer> list) {
    final fav = widget.prefs.favorites;
    int byPrice(Offer a, Offer b) => a.price.compareTo(b.price);
    int byEta(Offer a, Offer b) =>
        (a.etaMin ?? 999).compareTo(b.etaMin ?? 999);
    double rating(Offer o) =>
        _profiles[o.executorId]?.ratingAs('executor') ?? 0;
    final out = List.of(list);
    switch (_sort) {
      case _OfferSort.best:
        out.sort((a, b) {
          final fa = fav.contains(a.executorId) ? 0 : 1;
          final fb = fav.contains(b.executorId) ? 0 : 1;
          return fa != fb ? fa.compareTo(fb) : byPrice(a, b);
        });
      case _OfferSort.cheap:
        out.sort(byPrice);
      case _OfferSort.fast:
        out.sort((a, b) {
          final c = byEta(a, b);
          return c != 0 ? c : byPrice(a, b);
        });
      case _OfferSort.rating:
        out.sort((a, b) {
          final c = rating(b).compareTo(rating(a));
          return c != 0 ? c : byPrice(a, b);
        });
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    return StreamBuilder<List<Offer>>(
      stream: _stream,
      builder: (context, snap) {
        final all = snap.data ?? [];
        // Бұғатталған орындаушының ұсынысы көрсетілмейді (ол бұғатқа
        // дейін жіберілген болуы мүмкін).
        final pending = [
          for (final of in all)
            if (of.status == 'pending' &&
                !widget.prefs.blocks.contains(of.executorId))
              of,
        ];
        _ensureProfiles(pending);
        final offers = _sorted(pending);
        final rejectedCount = all.where((of) => of.status == 'rejected').length;
        final ageMin = order.createdAt == null
            ? 0
            : DateTime.now().difference(order.createdAt!).inMinutes;
        // Кеңес: 5+ бас тарту немесе 15+ мин жауапсыз → бағаны көтеру
        final suggestRaise =
            rejectedCount >= 5 || (offers.isEmpty && ageMin >= 15);
        final hasEta = offers.any((of) => of.etaMin != null);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(t('Ұсыныстар'), style: Gz.h3),
                const SizedBox(width: 8),
                CountBadge(offers.length),
                const Spacer(),
                const _PulsingDot(),
                const SizedBox(width: 6),
                Text(
                  t('Іздеуде…'),
                  style: const TextStyle(color: Gz.blue, fontSize: 13),
                ),
              ],
            ),
            if (offers.length > 1) ...[
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final s in _OfferSort.values)
                      if (s != _OfferSort.fast || hasEta)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(switch (s) {
                              _OfferSort.best => t('Ұсынылған'),
                              _OfferSort.cheap => t('Арзанырақ'),
                              _OfferSort.fast => t('Тез келеді'),
                              _OfferSort.rating => t('Рейтинг'),
                            }),
                            selected: _sort == s,
                            onSelected: (_) => setState(() => _sort = s),
                          ),
                        ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            if (suggestRaise) _RaisePriceHint(order: order),
            if (offers.isEmpty && !suggestRaise)
              SectionCard(
                child: Text(
                  t(
                    'Орындаушылардың ұсыныстары осында шығады. '
                    'Әдетте бірнеше минут ішінде жауап келеді.',
                  ),
                  style: Gz.bodyMuted,
                ),
              ),
            for (final offer in offers) ...[
              _OfferCard(
                offer: offer,
                clientPrice: order.clientPrice,
                favorite: widget.prefs.favorites.contains(offer.executorId),
                onOpenExecutor: () => widget.onOpenExecutor(offer.executorId),
              ),
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
/// Дайын қадамдар КІШІ (100–500). Бір рет көтерген соң кеңес 15 минутқа
/// жасырылады (жаңа ұсыныс күтуге мүмкіндік беру үшін).
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
    if (_snoozed) return const SizedBox.shrink();
    final custom = int.tryParse(_customCtrl.text.trim()) ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GzNotice(
        tone: NoticeTone.warning,
        title: t('Бағаны сәл көтеріп көріңіз'),
        message: t(
          'Ұзақ уақыт жауап жоқ немесе орындаушылар келіспей жатыр. '
          'Бағаны көтерсеңіз, тезірек табыласыз.',
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                fontSize: 13,
                color: Gz.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                GzStepButton(
                  icon: Icons.remove_rounded,
                  size: 40,
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
                GzStepButton(
                  icon: Icons.add_rounded,
                  size: 40,
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
      ),
    );
  }
}

class _OfferCard extends StatelessWidget {
  final Offer offer;
  final int? clientPrice;
  final bool favorite;
  final VoidCallback onOpenExecutor;
  const _OfferCard({
    required this.offer,
    this.clientPrice,
    this.favorite = false,
    required this.onOpenExecutor,
  });

  @override
  Widget build(BuildContext context) {
    final samePrice = clientPrice != null && offer.price == clientPrice;
    final note = offer.note.trim();
    return SectionCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(Gz.rSm),
                  onTap: onOpenExecutor,
                  child: _ExecutorBrief(
                    executorId: offer.executorId,
                    favorite: favorite,
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    fmtT(offer.price),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: samePrice ? Gz.green : Gz.ink,
                    ),
                  ),
                  Text(
                    samePrice ? t('Бағаңызға келісті') : t('Қарсы ұсыныс'),
                    style: TextStyle(
                      fontSize: 12,
                      color: samePrice ? Gz.green : Gz.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (offer.etaMin != null || note.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (offer.etaMin != null)
                  InfoChip(
                    icon: Icons.timer_outlined,
                    color: Gz.blue,
                    text: '~${offer.etaMin} ${t('мин')}',
                  ),
                if (note.isNotEmpty)
                  Text(
                    '«$note»',
                    style: const TextStyle(
                      color: Gz.textSecondary,
                      fontStyle: FontStyle.italic,
                      fontSize: 13,
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
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

/// Орындаушының қысқа профилі (аты, рейтинг, көлігі). Басса — толық
/// профиль терезесі (пікірлер, тегтер, ❤).
class _ExecutorBrief extends StatelessWidget {
  final String executorId;
  final bool favorite;
  const _ExecutorBrief({required this.executorId, this.favorite = false});

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
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          p?.fullName ?? '…',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      if (favorite) ...[
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.favorite_rounded,
                          size: 15,
                          color: Gz.red,
                        ),
                      ],
                      const SizedBox(width: 2),
                      const Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: Gz.textSecondary,
                      ),
                    ],
                  ),
                  // Клиент ОРЫНДАУШЫНЫ көреді → орындаушылық рейтинг/рейс
                  // (қос рөл, 0046).
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
                          style: Gz.caption,
                        ),
                    ],
                  ),
                  // Ұсыныс кезінде көлік нөмірі көрсетілмейді (тек маркасы)
                  if (ep != null)
                    Text(
                      ep.vehicleTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Gz.caption,
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
  final Order order;
  final ExecutorPrefs prefs;
  final bool showCall;
  final VoidCallback onOpen;
  const _ExecutorCard({
    required this.order,
    required this.prefs,
    required this.onOpen,
    this.showCall = true,
  });

  @override
  Widget build(BuildContext context) {
    final executorId = order.executorId!;
    return FutureBuilder(
      future: Future.wait([
        Repo.profileOf(executorId),
        Repo.executorProfileOf(executorId),
      ]),
      builder: (context, snap) {
        final p = snap.data?[0] as Profile?;
        final ep = snap.data?[1] as ExecutorProfile?;
        final favorite = prefs.favorites.contains(executorId);
        return SectionCard(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(Gz.rSm),
                  onTap: onOpen,
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
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    p?.fullName ?? t('Орындаушы'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Gz.h3,
                                  ),
                                ),
                                if (favorite) ...[
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.favorite_rounded,
                                    size: 15,
                                    color: Gz.red,
                                  ),
                                ],
                              ],
                            ),
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
                                    style: Gz.caption,
                                  ),
                              ],
                            ),
                            if (ep != null)
                              Text(
                                '${ep.vehicleTitle} · ${ep.vehiclePlate}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Gz.caption,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              OrderChatButton(
                order: order,
                title: p?.fullName ?? t('Орындаушы'),
                myRole: 'client',
              ),
              if (showCall && p != null && p.phone.isNotEmpty) ...[
                const SizedBox(width: 6),
                IconButton.filled(
                  tooltip: t('Қоңырау'),
                  style: IconButton.styleFrom(
                    backgroundColor: Gz.green,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => callPhone(context, p.phone),
                  icon: const Icon(Icons.call),
                ),
              ],
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

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

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
        decoration: const BoxDecoration(color: Gz.blue, shape: BoxShape.circle),
      ),
    );
  }
}
