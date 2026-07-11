import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/map_widgets.dart';
import '../../shared/widgets.dart';
import 'executor_order_screen.dart';

/// Заказдар лентасы (басты бетке ендірілетін дене). Сервер орындаушының
/// КӨЛІК ТҮРІНЕ сай заказдарды ғана береді (executor_feed → exec_can_take).
/// Карточкалар ықшам (аз орын алады); басқанда ғана карта + «Келісу/Өз бағам»
/// ашылады.
class ExecutorFeedBody extends ConsumerStatefulWidget {
  const ExecutorFeedBody({super.key});

  @override
  ConsumerState<ExecutorFeedBody> createState() => _ExecutorFeedBodyState();
}

class _ExecutorFeedBodyState extends ConsumerState<ExecutorFeedBody> {
  Future<void> _manualRefresh() async {
    ref.invalidate(executorStatsStreamProvider);
    ref.invalidate(executorFeedStreamProvider);
    ref.invalidate(myExecutorProfileProvider);
    await Future.delayed(const Duration(milliseconds: 600));
  }

  @override
  Widget build(BuildContext context) {
    final statsAsync = ref.watch(executorStatsStreamProvider);
    final feedAsync = ref.watch(executorFeedStreamProvider);

    return statsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => EmptyState(icon: Icons.wifi_off, title: errText(e)),
      data: (stats) {
        if (!stats.hasTariff) {
          return _refreshable([
            const SizedBox(height: 120),
            EmptyState(
              icon: Icons.power_settings_new,
              title: t('Тарифіңіз жоқ'),
              subtitle: t('Заказдарды көру үшін жоғарыдан тариф сатып алыңыз '
                  '(1 ауысым, 10 заказға дейін).'),
            ),
          ]);
        }

        // Сервер көлік түрі мен қала фильтрін өзі жасайды — жаңалары бірінші.
        final eligible = [...feedAsync.value ?? const <Order>[]];
        eligible.sort((a, b) {
          final ca = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final cb = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return cb.compareTo(ca);
        });

        if (eligible.isEmpty) {
          return _refreshable([
            const SizedBox(height: 120),
            EmptyState(
              icon: Icons.hourglass_empty,
              title: t('Әзірге заказ жоқ'),
              subtitle: t('Жаңа заказдар осы жерде автоматты пайда болады.'),
            ),
          ]);
        }

        return RefreshIndicator(
          color: Gz.ink,
          onRefresh: _manualRefresh,
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(12),
            itemCount: eligible.length,
            separatorBuilder: (_, i) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _FeedCard(
              order: eligible[i],
              onTap: () => _openOrder(eligible[i]),
            ),
          ),
        );
      },
    );
  }

  Widget _refreshable(List<Widget> children) => RefreshIndicator(
        color: Gz.ink,
        onRefresh: _manualRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: children,
        ),
      );

  /// Заказ карточкасын басқанда — толық детальдар (карта, клиент, фото) +
  /// «Келісу / Өз бағам» батырмалары қалқымалы парақта ашылады.
  void _openOrder(Order o) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Gz.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _OrderSheet(
        order: o,
        onAgree: () => _offer(o, o.clientPrice!, ''),
        onCounter: () => _counterOffer(o),
      ),
    );
  }

  Future<void> _offer(Order o, int price, String message) async {
    try {
      await Repo.placeOffer(o.id, price, message);
      if (mounted) {
        Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ExecutorOrderScreen(orderId: o.id)));
      }
    } catch (e) {
      if (mounted) showSnack(context, errText(e), error: true);
    }
  }

  Future<void> _counterOffer(Order o) async {
    final result = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _PriceStepperSheet(order: o),
    );
    if (result == null || !mounted) return;
    await _offer(o, result, '');
  }
}

/// Ықшам заказ карточкасы: клиент (аватар+рейтинг), баға, маршрут, тегтер,
/// жүк (қысқа). Карта мен батырмалар ЖОҚ — олар басқанда парақта ашылады.
class _FeedCard extends StatelessWidget {
  final Order order;
  final VoidCallback onTap;
  const _FeedCard({required this.order, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Gz.surface,
      borderRadius: BorderRadius.circular(Gz.radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(Gz.radius),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Gz.radius),
            border: Border.all(color: Gz.border, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: _ClientMini(clientId: order.clientId)),
                  Text(
                    fmtT(order.displayPrice),
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.3,
                        color: Gz.ink),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _CompactRoute(from: order.fromDisplay, to: order.toDisplay),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _tag(Icons.local_shipping_outlined,
                      '${order.vehicleType.emoji} ${order.vehicleType.label}'),
                  if (order.fromCity != null && order.toCity != null)
                    _tag(
                      order.intercity
                          ? Icons.alt_route
                          : Icons.location_city_outlined,
                      order.intercity ? t('Межгород') : t('Қала ішінде'),
                    ),
                  if (order.distanceKm > 0)
                    _tag(Icons.route,
                        '≈ ${order.distanceKm.toStringAsFixed(1)} км'),
                  if (order.cargoDesc.isNotEmpty)
                    _tag(Icons.inventory_2_outlined,
                        order.cargoDesc, flexible: true),
                  if (order.createdAt != null)
                    _tag(Icons.schedule, fmtTime(order.createdAt)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tag(IconData icon, String text, {bool flexible = false}) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Gz.bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Gz.textSecondary),
          const SizedBox(width: 4),
          Flexible(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 11.5,
                    color: Gz.ink,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (!flexible) return chip;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 170),
      child: chip,
    );
  }
}

/// Клиенттің шағын жолы (аватар + аты + рейтинг) — карточкаға сыятын ықшам.
class _ClientMini extends StatelessWidget {
  final String clientId;
  const _ClientMini({required this.clientId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Profile?>(
      future: Repo.profileOf(clientId),
      builder: (context, snap) {
        final p = snap.data;
        return Row(
          children: [
            InitialsAvatar(p?.fullName ?? '?', radius: 15, imageUrl: p?.avatarUrl),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p?.fullName ?? '…',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 13.5)),
                  RatingStars(p?.rating ?? 0,
                      count: p?.ratingCount ?? 0, size: 11),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Маршруттың ықшам көрінісі (қайдан → қайда), әр жол бір қатар.
class _CompactRoute extends StatelessWidget {
  final String from;
  final String to;
  const _CompactRoute({required this.from, required this.to});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _line(Icons.trip_origin, Gz.green, from),
        const SizedBox(height: 3),
        _line(Icons.location_on, Gz.red, to),
      ],
    );
  }

  Widget _line(IconData icon, Color color, String text) => Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      );
}

/// Заказ детальдары парағы: карта, толық маршрут, клиент, фото, жүк +
/// «Келісу / Өз бағам» батырмалары.
class _OrderSheet extends StatelessWidget {
  final Order order;
  final VoidCallback onAgree;
  final VoidCallback onCounter;
  const _OrderSheet(
      {required this.order, required this.onAgree, required this.onCounter});

  @override
  Widget build(BuildContext context) {
    final o = order;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Gz.border, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(fmtT(o.displayPrice),
                    style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: Gz.ink)),
              ),
              Text('${o.vehicleType.emoji} ${o.vehicleType.label}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Gz.textSecondary)),
            ],
          ),
          const SizedBox(height: 12),
          RouteMap(
            from: LatLng(o.fromLat, o.fromLng),
            to: LatLng(o.toLat, o.toLng),
            height: 150,
          ),
          const SizedBox(height: 10),
          SectionCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RouteLine(from: o.fromDisplay, to: o.toDisplay),
                const Divider(height: 20),
                InfoRow(t('Жүк'), o.cargoDesc),
                if (o.comment.isNotEmpty) InfoRow(t('Түсініктеме'), o.comment),
                InfoRow(t('Бағыты'),
                    o.intercity ? t('Қалааралық (межгород)') : t('Қала ішінде')),
                if (o.distanceKm > 0)
                  InfoRow(t('Қашықтық'), '≈ ${o.distanceKm.toStringAsFixed(1)} км'),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _SheetClient(clientId: o.clientId),
          if (o.photos.isNotEmpty) ...[
            const SizedBox(height: 10),
            SectionCard(child: OrderPhotosStrip(paths: o.photos)),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: BusyButton(
                  label: '${t('Келісу')} · ${fmtT(o.clientPrice)}',
                  onPressed: () async {
                    Navigator.of(context).pop();
                    onAgree();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      side: const BorderSide(color: Gz.ink, width: 1.6)),
                  onPressed: () {
                    Navigator.of(context).pop();
                    onCounter();
                  },
                  child: Text(t('Өз бағам')),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _SheetClient extends StatelessWidget {
  final String clientId;
  const _SheetClient({required this.clientId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Profile?>(
      future: Repo.profileOf(clientId),
      builder: (context, snap) => SectionCard(
        padding: const EdgeInsets.all(12),
        child: ProfileBrief(profile: snap.data, subtitle: t('Клиент')),
      ),
    );
  }
}

/// −/+ батырмаларымен баға ұсыну терезесі (100 ₸ қадаммен).
class _PriceStepperSheet extends StatefulWidget {
  final Order order;
  const _PriceStepperSheet({required this.order});

  @override
  State<_PriceStepperSheet> createState() => _PriceStepperSheetState();
}

class _PriceStepperSheetState extends State<_PriceStepperSheet> {
  late int _price = widget.order.clientPrice ?? 1000;
  static const _step = 100;

  void _bump(int delta) {
    setState(() => _price = (_price + delta).clamp(100, 100000000));
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.order.clientPrice;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t('Өз бағаңызды ұсыныңыз'),
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          const SizedBox(height: 4),
          if (base != null)
            Text('${t('Клиенттің бағасы:')} ${fmtT(base)}',
                style: const TextStyle(color: Gz.textSecondary, fontSize: 13)),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _StepBtn(
                  icon: Icons.remove,
                  onTap: () => _bump(-_step),
                  onLong: () => _bump(-1000)),
              Column(
                children: [
                  Text(fmtT(_price),
                      style: const TextStyle(
                          fontSize: 30, fontWeight: FontWeight.w900)),
                  Text(t('±100 ₸ қадам'),
                      style: const TextStyle(
                          fontSize: 11.5, color: Gz.textSecondary)),
                ],
              ),
              _StepBtn(
                  icon: Icons.add,
                  onTap: () => _bump(_step),
                  onLong: () => _bump(1000)),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => Navigator.pop(context, _price),
            child: Text('${t('Ұсыну')} · ${fmtT(_price)}'),
          ),
        ],
      ),
    );
  }
}

class _StepBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback onLong;
  const _StepBtn(
      {required this.icon, required this.onTap, required this.onLong});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLong,
      child: Container(
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          color: Gz.bg,
          shape: BoxShape.circle,
          border: Border.all(color: Gz.border, width: 1.4),
        ),
        child: Icon(icon, size: 28, color: Gz.ink),
      ),
    );
  }
}
