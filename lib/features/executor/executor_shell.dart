import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/notify.dart';
import '../../core/prefs.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import '../profile/profile_screen.dart';
import 'active_order_screen.dart';
import 'executor_home_screen.dart';
import 'vip_dispatch_dialog.dart';

class ExecutorShell extends StatefulWidget {
  const ExecutorShell({super.key});

  @override
  State<ExecutorShell> createState() => _ExecutorShellState();
}

class _ExecutorShellState extends State<ExecutorShell> {
  int _index = 0;
  final Set<String> _shownDispatches = {};
  final Set<String> _notifiedOrders = {};
  final Set<String> _notifiedAutoAccepts = {};
  bool _autoAcceptPrimed = false;
  Timer? _feedWatch;
  bool _feedPrimed = false;

  @override
  void initState() {
    super.initState();
    // Линиядағы орындаушыға жаңа заказ туралы хабарлау (әр 25с)
    _feedWatch = Timer.periodic(
        const Duration(seconds: 25), (_) => _checkNewOrders());
    _checkNewOrders();
  }

  @override
  void dispose() {
    _feedWatch?.cancel();
    super.dispose();
  }

  Future<void> _checkNewOrders() async {
    try {
      final stats = await Repo.executorStats();
      if (!stats.hasTariff || !stats.onLine || stats.busyOrderId != null) {
        return;
      }
      final ep = await Repo.myExecutorProfile();
      if (ep == null) return;
      final rows = await Repo.c
          .from('orders')
          .select('id')
          .eq('status', 'searching')
          .eq('type', 'bidding')
          .eq('vehicle_type', ep.vehicleType.db)
          .order('created_at', ascending: false)
          .limit(10);
      final ids = (rows as List).map((m) => m['id'] as String).toList();
      final fresh =
          ids.where((id) => !_notifiedOrders.contains(id)).toList();
      _notifiedOrders.addAll(ids);
      // алғашқы жүктеуде ескілерге хабарламай, тек белгілеп қоямыз
      if (!_feedPrimed) {
        _feedPrimed = true;
        return;
      }
      if (fresh.isNotEmpty && await Prefs.orderNotify()) {
        Notify.show(t('Жаңа заказ бар! 🚚'),
            '${t('Лентада')} ${fresh.length} ${t('жаңа заказ күтіп тұр — қараңыз.')}',
            id: 2);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<VipDispatch>>(
      stream: Repo.myDispatchesStream(),
      builder: (context, snap) {
        // жаңа VIP заказ түскенде диалог + уведомление
        final live = (snap.data ?? []).where((d) => d.isLive).toList();
        for (final d in live) {
          if (!_shownDispatches.contains(d.id)) {
            _shownDispatches.add(d.id);
            Notify.show(t('VIP заказ! ⚡'), t('Жауапқа 25 секунд — ашыңыз!'), id: 1);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) showVipDispatchDialog(context, d);
            });
          }
        }
        // "автоматты қабылдау" арқылы терезесіз тағайындалған VIP заказдар
        final all = snap.data ?? [];
        if (!_autoAcceptPrimed) {
          if (snap.hasData) {
            for (final d in all) {
              _notifiedAutoAccepts.add(d.id);
            }
            _autoAcceptPrimed = true;
          }
        } else {
          for (final d in all.where((d) => d.status == 'accepted')) {
            if (!_notifiedAutoAccepts.contains(d.id)) {
              _notifiedAutoAccepts.add(d.id);
              Notify.show(t('VIP заказ автоматты тағайындалды! ⚡'),
                  t('Жолға шығуға дайындалыңыз — заказ ашылды.'),
                  id: 1);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => ActiveOrderScreen(orderId: d.orderId)));
                }
              });
            }
          }
        }
        return Scaffold(
          body: Column(
            children: [
              Expanded(
                child: IndexedStack(
                  index: _index,
                  children: const [
                    ExecutorHomeScreen(),
                    ProfileScreen(),
                  ],
                ),
              ),
              const _BusyOrderBanner(),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: [
              NavigationDestination(
                  icon: const Icon(Icons.home_outlined),
                  selectedIcon: const Icon(Icons.home),
                  label: t('Басты')),
              NavigationDestination(
                  icon: const Icon(Icons.person_outline),
                  selectedIcon: const Icon(Icons.person),
                  label: t('Профиль')),
            ],
          ),
        );
      },
    );
  }
}

/// Белсенді заказ(дар) бар кезде көрінетін баннер.
///
/// §5 межгород маршрут-стектеу арқылы орындаушыда бір мезгілде 2 белсенді
/// заказ болуы мүмкін (`executor_profiles.busy_order_id` тек біреуін ғана
/// сақтайды) — сол себепті тікелей `orders` тізімін қолданамыз: біреу
/// болса дереу ашамыз, екеу болса таңдау терезесін көрсетеміз.
class _BusyOrderBanner extends StatelessWidget {
  const _BusyOrderBanner();

  void _open(BuildContext context, List<Order> active) {
    if (active.length == 1) {
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ActiveOrderScreen(orderId: active.first.id)));
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      // Карточкалар (маршрут+тегтер) экранға сыймай қалса — тізім өзі
      // скроллданады, тек Column-ды толтырмайды (2+ белсенді заказ §5
      // межгород маршрут-стектеу арқылы болады).
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.85),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(t('Белсенді заказдар'),
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 18)),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: active.length,
                    separatorBuilder: (_, i) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final o = active[i];
                      return OrderCard(
                        order: o,
                        onTap: () {
                          Navigator.pop(ctx);
                          Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) =>
                                  ActiveOrderScreen(orderId: o.id)));
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Order>>(
      stream: Repo.myActiveExecutorOrdersStream(),
      builder: (context, snap) {
        final active = snap.data ?? const <Order>[];
        if (active.isEmpty) return const SizedBox.shrink();
        return GestureDetector(
          onTap: () => _open(context, active),
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Gz.green, Color(0xFF0E8A3E)],
              ),
            ),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: SafeArea(
              top: false,
              bottom: false,
              child: Row(
                children: [
                  const Icon(Icons.local_shipping,
                      color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      active.length > 1
                          ? '${active.length} ${t('белсенді заказ бар — ашу үшін басыңыз')}'
                          : t('Белсенді заказ бар — ашу үшін басыңыз'),
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14),
                    ),
                  ),
                  if (active.length > 1)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('+${active.length - 1}',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12)),
                    ),
                  const Icon(Icons.chevron_right, color: Colors.white),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
