import 'package:flutter/material.dart';

import '../../core/models.dart';
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

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<VipDispatch>>(
      stream: Repo.myDispatchesStream(),
      builder: (context, snap) {
        // жаңа VIP заказ түскенде диалог көрсету
        final live = (snap.data ?? []).where((d) => d.isLive).toList();
        for (final d in live) {
          if (!_shownDispatches.contains(d.id)) {
            _shownDispatches.add(d.id);
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
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _index,
            onTap: (i) => setState(() => _index = i),
            items: const [
              BottomNavigationBarItem(
                  icon: Icon(Icons.dashboard_outlined),
                  activeIcon: Icon(Icons.dashboard),
                  label: 'Басты'),
              BottomNavigationBarItem(
                  icon: Icon(Icons.list_alt_outlined),
                  activeIcon: Icon(Icons.list_alt),
                  label: 'Заказдар'),
              BottomNavigationBarItem(
                  icon: Icon(Icons.payments_outlined),
                  activeIcon: Icon(Icons.payments),
                  label: 'Табыс'),
              BottomNavigationBarItem(
                  icon: Icon(Icons.person_outline),
                  activeIcon: Icon(Icons.person),
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
            color: Gz.green,
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
