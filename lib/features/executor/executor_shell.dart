import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/notify.dart';
import '../../core/prefs.dart';
import '../../core/push.dart';
import '../../core/repo.dart';
import '../../shared/widgets.dart';
import 'active_order_screen.dart';
import 'executor_home_screen.dart';

class ExecutorShell extends StatefulWidget {
  const ExecutorShell({super.key});

  @override
  State<ExecutorShell> createState() => _ExecutorShellState();
}

class _ExecutorShellState extends State<ExecutorShell> {
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
      // FCM қосулы болса — жаңа заказ туралы СЕРВЕР хабарлайды (0028/0045):
      // қосымша жабық тұрса да жетеді әрі пайдаланушының тілінде БІР РЕТ
      // келеді. Мұнда қайта көрсетсек, орындаушыға сол заказ туралы ЕКІ
      // хабарландыру (сервердікі қазақша + мынау аударылған) түсетін —
      // нақты табылған ақау. Сол себепті локал нұсқасы тек push мүлдем
      // жоқ жағдайда (Firebase бапталмаған) резерв ретінде қалады.
      if (fresh.isNotEmpty && !Push.isActive && await Prefs.orderNotify()) {
        Notify.show(t('Жаңа заказ бар! 🚚'),
            '${t('Лентада')} ${fresh.length} ${t('жаңа заказ күтіп тұр — қараңыз.')}',
            id: 2);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    // Төменгі навбар ЖОЙЫЛДЫ: профиль енді логотип батырмасынан ашылатын
    // sidebar-дың ішінде (клиенттегідей бір экранды дизайн).
    return const Scaffold(
      body: Column(
        children: [
          Expanded(child: ExecutorHomeScreen()),
          _BusyOrderBanner(),
        ],
      ),
    );
  }
}

/// Белсенді заказ(дар) бар кезде көрінетін баннер.
///
/// §5 межгород маршрут-стектеу арқылы орындаушыда бір мезгілде 2 белсенді
/// заказ болуы мүмкін (`executor_profiles.busy_order_id` тек біреуін ғана
/// сақтайды) — сол себепті тікелей `orders` тізімін қолданамыз: біреу
/// болса дереу ашамыз, екеу болса таңдау терезесін көрсетеміз.
class _BusyOrderBanner extends StatefulWidget {
  const _BusyOrderBanner();

  @override
  State<_BusyOrderBanner> createState() => _BusyOrderBannerState();
}

class _BusyOrderBannerState extends State<_BusyOrderBanner> {
  /// Стрим БІР РЕТ құрылады — build сайын жаңа polling-цикл ашылмауы үшін.
  final Stream<List<Order>> _stream = Repo.myActiveExecutorOrdersStream();

  void _open(BuildContext context, List<Order> active) {
    if (active.length == 1) {
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ActiveOrderScreen(orderId: active.first.id)));
      return;
    }
    // 2+ белсенді заказ (§5 межгород маршрут-стектеу) — таңдау терезесі.
    // Карточкалар экранға сыймаса тізім өзі айналады.
    showGzSheet(
      context,
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.85,
        ),
        child: GzSheetBody(
          title: t('Белсенді заказдар'),
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
                      builder: (_) => ActiveOrderScreen(orderId: o.id)));
                },
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Order>>(
      stream: _stream,
      builder: (context, snap) {
        final active = snap.data ?? const <Order>[];
        if (active.isEmpty) return const SizedBox.shrink();
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
            child: ActiveOrderBanner(
              orders: active,
              title: active.length > 1
                  ? '${active.length} ${t('белсенді заказ бар — ашу үшін басыңыз')}'
                  : null,
              onTap: () => _open(context, active),
            ),
          ),
        );
      },
    );
  }
}
