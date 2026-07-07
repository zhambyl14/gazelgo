import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/notify.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../profile/profile_screen.dart';
import 'active_order_screen.dart';
import 'dashboard_screen.dart';
import 'earnings_screen.dart';
import 'feed_screen.dart';
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
      if (!stats.simpleActive || !stats.onLine || stats.busyOrderId != null) {
        return;
      }
      final ep = await Repo.myExecutorProfile();
      if (ep == null) return;
      final rows = await Repo.c
          .from('orders')
          .select('id')
          .eq('status', 'searching')
          .eq('type', 'bidding')
          .eq('size', ep.vehicleSize.db)
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
      if (fresh.isNotEmpty) {
        Notify.show('Жаңа заказ бар! 🚚',
            'Лентада ${fresh.length} жаңа заказ күтіп тұр — қараңыз.',
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
            Notify.show('VIP заказ! ⚡', 'Жауапқа 20 секунд — ашыңыз!', id: 1);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) showVipDispatchDialog(context, d);
            });
          }
        }
        return Scaffold(
          body: Column(
            children: [
              Expanded(
                child: IndexedStack(
                  index: _index,
                  children: const [
                    ExecutorDashboardScreen(),
                    ExecutorFeedScreen(),
                    EarningsScreen(),
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
            destinations: const [
              NavigationDestination(
                  icon: Icon(Icons.dashboard_outlined),
                  selectedIcon: Icon(Icons.dashboard),
                  label: 'Басты'),
              NavigationDestination(
                  icon: Icon(Icons.list_alt_outlined),
                  selectedIcon: Icon(Icons.list_alt),
                  label: 'Заказдар'),
              NavigationDestination(
                  icon: Icon(Icons.payments_outlined),
                  selectedIcon: Icon(Icons.payments),
                  label: 'Табыс'),
              NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: 'Профиль'),
            ],
          ),
        );
      },
    );
  }
}

/// Белсенді заказ бар кезде көрінетін баннер.
class _BusyOrderBanner extends StatelessWidget {
  const _BusyOrderBanner();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ExecutorProfile?>(
      stream: Repo.myExecutorProfileStream(),
      builder: (context, snap) {
        final busyId = snap.data?.busyOrderId;
        if (busyId == null) return const SizedBox.shrink();
        return GestureDetector(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ActiveOrderScreen(orderId: busyId))),
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Gz.green, Color(0xFF0E8A3E)],
              ),
            ),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: const SafeArea(
              top: false,
              bottom: false,
              child: Row(
                children: [
                  Icon(Icons.local_shipping, color: Colors.white, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Белсенді заказ бар — ашу үшін басыңыз',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14),
                    ),
                  ),
                  Icon(Icons.chevron_right, color: Colors.white),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
