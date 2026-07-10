import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import 'executor_order_screen.dart';

/// Қарапайым тарифтегі заказдар лентасы (басты бетке ендірілетін дене —
/// өз Scaffold/AppBar-ы жоқ).
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
    // Лента стримі бөлек кэштелген провайдерден — статистика жаңарса да
    // қайта жазылмайды (автообновление үзілмейді).
    final feedAsync = ref.watch(executorFeedStreamProvider);

    return statsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) =>
            EmptyState(icon: Icons.wifi_off, title: errText(e)),
        data: (stats) {
          if (!stats.hasTariff) {
            return RefreshIndicator(
              color: Gz.ink,
              onRefresh: _manualRefresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  EmptyState(
                    icon: Icons.power_settings_new,
                    title: 'Тарифіңіз жоқ',
                    subtitle:
                        'Заказдарды көру үшін жоғарыдан тариф сатып алыңыз '
                        '(Простой немесе VIP — 1 ауысым, 10 заказға дейін).',
                  ),
                ],
              ),
            );
          }
          final all = feedAsync.value ?? const <Order>[];
          final simple = all
              .where((o) => o.tariff == 'simple')
              .toList()
              .reversed
              .toList();
          final vip = all
              .where((o) => o.tariff == 'vip')
              .toList()
              .reversed
              .toList();
          // §: Простой мен VIP лентасы бөлек табтарда
          return DefaultTabController(
            length: 2,
            child: Column(
              children: [
                const TabBar(
                  labelColor: Gz.ink,
                  unselectedLabelColor: Gz.textSecondary,
                  indicatorColor: Gz.yellowDark,
                  tabs: [
                    Tab(text: 'Простой'),
                    Tab(text: 'VIP'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _feedList(simple, stats.simpleActive, 'Простой'),
                      _feedList(vip, stats.vipActive, 'VIP'),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
  }

  Widget _feedList(List<Order> orders, bool kindActive, String kindLabel) {
    if (!kindActive) {
      return RefreshIndicator(
        color: Gz.ink,
        onRefresh: _manualRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 120),
            EmptyState(
              icon: Icons.lock_outline,
              title: '$kindLabel тарифі жоқ',
              subtitle:
                  '$kindLabel заказдарды көру үшін жоғарыдан $kindLabel тарифін '
                  'сатып алыңыз.',
            ),
          ],
        ),
      );
    }
    if (orders.isEmpty) {
      return RefreshIndicator(
        color: Gz.ink,
        onRefresh: _manualRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 120),
            EmptyState(
              icon: Icons.hourglass_empty,
              title: 'Әзірге заказ жоқ',
              subtitle: 'Жаңа заказдар осы жерде автоматты пайда болады.',
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: Gz.ink,
      onRefresh: _manualRefresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        itemCount: orders.length,
        separatorBuilder: (_, i) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final o = orders[i];
          return OrderCard(
            order: o,
            showMap: true,
            trailing: Text(
              fmtTime(o.createdAt),
              style: const TextStyle(color: Gz.textSecondary, fontSize: 12),
            ),
            footer: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Divider(height: 4),
                const SizedBox(height: 8),
                _ClientBrief(clientId: o.clientId),
                if (o.photos.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  OrderPhotosStrip(paths: o.photos),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: BusyButton(
                        label: 'Келісу · ${fmtT(o.clientPrice)}',
                        onPressed: () => _offer(context, o, o.clientPrice!, ''),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            side:
                                const BorderSide(color: Gz.ink, width: 1.6)),
                        onPressed: () => _counterOffer(context, o),
                        child: const Text('Өз бағам'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _offer(
      BuildContext context, Order o, int price, String message) async {
    try {
      await Repo.placeOffer(o.id, price, message);
      // Ұсыныстан кейін заказ ішіне кіреміз (лентада қалмаймыз)
      if (context.mounted) {
        Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ExecutorOrderScreen(orderId: o.id)));
      }
    } catch (e) {
      if (context.mounted) showSnack(context, errText(e), error: true);
    }
  }

  Future<void> _counterOffer(BuildContext context, Order o) async {
    final result = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _PriceStepperSheet(order: o),
    );
    if (result == null || !context.mounted) return;
    await _offer(context, o, result, '');
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
          const Text('Өз бағаңызды ұсыныңыз',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          const SizedBox(height: 4),
          if (base != null)
            Text('Клиенттің бағасы: ${fmtT(base)}',
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
                  const Text('±100 ₸ қадам',
                      style:
                          TextStyle(fontSize: 11.5, color: Gz.textSecondary)),
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
            child: Text('Ұсыну · ${fmtT(_price)}'),
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

/// Клиенттің қысқа профилі (аты, рейтинг, рейс саны, аватар).
class _ClientBrief extends StatelessWidget {
  final String clientId;
  const _ClientBrief({required this.clientId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Profile?>(
      future: Repo.profileOf(clientId),
      builder: (context, snap) => ProfileBrief(
        profile: snap.data,
        radius: 18,
        subtitle: 'Клиент',
      ),
    );
  }
}
