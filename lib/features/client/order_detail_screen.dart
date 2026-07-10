import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/map_widgets.dart';
import '../../shared/widgets.dart';
import '../support/support_screen.dart';

/// Клиенттің заказ экраны: ұсыныстар, VIP іздеу, барыс, пікір.
class OrderDetailScreen extends StatefulWidget {
  final String orderId;
  const OrderDetailScreen({super.key, required this.orderId});

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  Timer? _vipTimer;
  bool _photosCleaned = false;

  @override
  void dispose() {
    _vipTimer?.cancel();
    super.dispose();
  }

  /// Заказ аяқталса/бас тартылса — тіркелген фотоларды өшіру (жадты үнемдеу).
  void _maybeCleanupPhotos(Order o) {
    const terminal = ['completed', 'cancelled', 'expired'];
    if (!_photosCleaned && terminal.contains(o.status) && o.photos.isNotEmpty) {
      _photosCleaned = true;
      Repo.deleteOrderPhotos(o.photos);
    }
  }

  void _ensureVipTimer(Order o) {
    final need = o.type == 'instant' && o.status == 'searching';
    if (need && _vipTimer == null) {
      _vipTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        Repo.advanceVip(widget.orderId).catchError((_) {});
      });
    } else if (!need && _vipTimer != null) {
      _vipTimer!.cancel();
      _vipTimer = null;
    }
  }

  Future<void> _cancel() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = TextEditingController();
        return AlertDialog(
          title: const Text('Заказды тоқтату'),
          content: TextField(
            controller: c,
            decoration: const InputDecoration(hintText: 'Себебі (міндетті емес)'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Жоқ')),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: Gz.red,
                  foregroundColor: Colors.white,
                  shadowColor: const Color(0x59DC2626)),
              onPressed: () => Navigator.pop(ctx, c.text),
              child: const Text('Тоқтату'),
            ),
          ],
        );
      },
    );
    if (reason == null || !mounted) return;
    try {
      await Repo.cancelOrder(widget.orderId, reason);
      // Экранда қалдырмаймыз — басты бетке қайтамыз (адрестер сол жерде сақталған)
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
        showSnack(context, 'Заказ тоқтатылды');
      }
    } catch (e) {
      if (mounted) showSnack(context, errText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Заказ')),
      body: StreamBuilder<Order?>(
        stream: Repo.orderStream(widget.orderId),
        builder: (context, snap) {
          final o = snap.data;
          if (o == null) {
            return const Center(child: CircularProgressIndicator());
          }
          _ensureVipTimer(o);
          _maybeCleanupPhotos(o);
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
                    StatusChip(o.status),
                  ],
                ),
                const SizedBox(height: 12),
                RouteMap(
                  from: LatLng(o.fromLat, o.fromLng),
                  to: LatLng(o.toLat, o.toLng),
                  height: 160,
                ),
                const SizedBox(height: 10),
                SectionCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RouteLine(from: o.fromDisplay, to: o.toDisplay),
                      const Divider(height: 20),
                      InfoRow('Жүк', o.cargoDesc),
                      if (o.comment.isNotEmpty)
                          InfoRow('Түсініктеме', o.comment),
                      InfoRow('Түрі', o.isVip ? 'VIP' : 'Простой'),
                      if (o.distanceKm > 0)
                        InfoRow('Қашықтық',
                            '${o.distanceKm.toStringAsFixed(1)} км'),
                      InfoRow('Бағыты',
                          o.intercity ? 'Қалааралық (межгород)' : 'Қала ішінде'),
                      if (o.createdAt != null)
                        InfoRow('Құрылды', fmtDate(o.createdAt)),
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
                    label: const Text('Заказды тоқтату'),
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
        return o.type == 'bidding'
            ? [_OffersSection(order: o)]
            : [_VipSearchSection(order: o)];
      case 'accepted':
      case 'arrived':
      case 'loading':
      case 'in_transit':
        return [
          _ExecutorCard(executorId: o.executorId!),
          const SizedBox(height: 10),
          _Timeline(status: o.status),
          const SizedBox(height: 10),
          SupportOrderButton(orderId: o.id),
          const SizedBox(height: 10),
          ReportSuspiciousButton(orderId: o.id),
        ];
      case 'completed':
        return [
          _ExecutorCard(executorId: o.executorId!),
          const SizedBox(height: 10),
          ReviewPrompt(orderId: o.id, title: 'Орындаушыны бағалаңыз'),
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
                      ? 'Себебі: ${o.cancelReason}'
                      : 'Заказ тоқтатылды',
                ),
              ),
            ]),
          ),
        ];
      default:
        return [
          const SectionCard(
            child: Row(children: [
              Icon(Icons.schedule, color: Gz.textSecondary),
              SizedBox(width: 10),
              Expanded(
                  child: Text('Заказдың мерзімі өтті — ешкім қабылдамады.')),
            ]),
          ),
        ];
    }
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
                const Text('Ұсыныстар',
                    style:
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
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
                const Text('Іздеуде…',
                    style: TextStyle(color: Gz.blue, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 8),
            if (suggestRaise) _RaisePriceHint(order: order),
            if (offers.isEmpty && !suggestRaise)
              const SectionCard(
                child: Text(
                  'Орындаушылардың ұсыныстары осында шығады. '
                  'Әдетте бірнеше минут ішінде жауап келеді.',
                  style: TextStyle(color: Gz.textSecondary, fontSize: 13.5),
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
class _RaisePriceHint extends StatelessWidget {
  final Order order;
  const _RaisePriceHint({required this.order});

  @override
  Widget build(BuildContext context) {
    final cur = order.clientPrice ?? 0;
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
          const Row(
            children: [
              Icon(Icons.lightbulb, color: Gz.yellowDark, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text('Бағаны сәл көтеріп көріңіз',
                    style: TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 14.5)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Ұзақ уақыт жауап жоқ немесе орындаушылар келіспей жатыр. '
            'Бағаны көтерсеңіз, тезірек табыласыз.',
            style: TextStyle(color: Gz.textSecondary, fontSize: 12.5),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final add in [500, 1000, 2000])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 40),
                        padding:
                            const EdgeInsets.symmetric(horizontal: 12)),
                    onPressed: () async {
                      try {
                        await Repo.updateOrderPrice(order.id, cur + add);
                        if (context.mounted) {
                          showSnack(context,
                              'Жаңа баға: ${fmtT(cur + add)}');
                        }
                      } catch (e) {
                        if (context.mounted) {
                          showSnack(context, errText(e), error: true);
                        }
                      }
                    },
                    child: Text('+${fmtT(add)}'),
                  ),
                ),
            ],
          ),
        ],
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
                  Text(samePrice ? 'Бағаңызға келісті' : 'Қарсы ұсыныс',
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
                  child: const Text('Қабылдамау'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: BusyButton(
                  label: 'Қабылдау · ${fmtT(offer.price)}',
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
                  Row(
                    children: [
                      RatingStars(p?.rating ?? 0,
                          count: p?.ratingCount ?? 0, size: 13),
                      if ((p?.trips ?? 0) > 0)
                        Text('  · ${p!.trips} рейс',
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

// ===================== VIP ІЗДЕУ (instant) =====================
class _VipSearchSection extends StatelessWidget {
  final Order order;
  const _VipSearchSection({required this.order});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        children: [
          const SizedBox(height: 6),
          const SizedBox(
            width: 44,
            height: 44,
            child: CircularProgressIndicator(strokeWidth: 3, color: Gz.violet),
          ),
          const SizedBox(height: 14),
          const Text('VIP орындаушы ізделуде…',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 6),
          Text(
            'Баға: ${fmtT(order.systemPrice)}',
            style: const TextStyle(color: Gz.textSecondary, fontSize: 13.5),
          ),
          const SizedBox(height: 10),
          StreamBuilder<List<VipDispatch>>(
            stream: Repo.orderDispatchesStream(order.id),
            builder: (context, snap) {
              final live =
                  (snap.data ?? []).where((d) => d.isLive).toList();
              if (live.isEmpty) {
                return const Text(
                  'Бос орындаушы қарастырылуда…',
                  style: TextStyle(color: Gz.textSecondary, fontSize: 12.5),
                );
              }
              return _DispatchCountdown(expiresAt: live.first.expiresAt);
            },
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

class _DispatchCountdown extends StatefulWidget {
  final DateTime expiresAt;
  const _DispatchCountdown({required this.expiresAt});

  @override
  State<_DispatchCountdown> createState() => _DispatchCountdownState();
}

class _DispatchCountdownState extends State<_DispatchCountdown> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(
        const Duration(seconds: 1), (_) => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = widget.expiresAt.difference(DateTime.now()).inSeconds;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Gz.violet.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        left > 0
            ? 'Орындаушыға жіберілді · жауап: $left с'
            : 'Келесі орындаушыға өтуде…',
        style: const TextStyle(
            color: Gz.violet, fontWeight: FontWeight.w700, fontSize: 13),
      ),
    );
  }
}

// ===================== ОРЫНДАУШЫ КАРТАСЫ =====================
class _ExecutorCard extends StatelessWidget {
  final String executorId;
  const _ExecutorCard({required this.executorId});

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
                        Text(p?.fullName ?? 'Орындаушы',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 16)),
                        Row(children: [
                          RatingStars(p?.rating ?? 0,
                              count: p?.ratingCount ?? 0, size: 14),
                          if ((p?.trips ?? 0) > 0)
                            Text('  · ${p!.trips} рейс',
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
                  if (p != null && p.phone.isNotEmpty)
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
  const _Timeline({required this.status});

  static const _steps = [
    ('accepted', 'Орындаушы жолда'),
    ('arrived', 'Келді'),
    ('loading', 'Тиеу'),
    ('in_transit', 'Тасымалдауда'),
    ('completed', 'Аяқталды'),
  ];

  @override
  Widget build(BuildContext context) {
    final idx = _steps.indexWhere((s) => s.$1 == status);
    return SectionCard(
      child: Column(
        children: [
          for (var i = 0; i < _steps.length; i++)
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
                    if (i < _steps.length - 1)
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
                    _steps[i].$2,
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
