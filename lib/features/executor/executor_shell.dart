import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/geo.dart';
import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/notify.dart';
import '../../core/prefs.dart';
import '../../core/push.dart';
import '../../core/repo.dart';
import '../../shared/widgets.dart';
import 'active_order_screen.dart';
import 'executor_home_screen.dart';

class ExecutorShell extends ConsumerStatefulWidget {
  const ExecutorShell({super.key});

  @override
  ConsumerState<ExecutorShell> createState() => _ExecutorShellState();
}

class _ExecutorShellState extends ConsumerState<ExecutorShell> {
  final Set<String> _notifiedOrders = {};
  Timer? _feedWatch;
  bool _feedPrimed = false;

  /// Соңғы белгілі статистика — ортақ polling-циклден
  /// ([executorStatsStreamProvider], басты бет те соны тыңдайды — қосымша
  /// сұрау жоқ). Орын жіберу жиілігін таңдау үшін.
  ExecutorStats? _stats;
  ProviderSubscription<AsyncValue<ExecutorStats>>? _statsSub;

  /// ОРЫН ЖІБЕРУ (0075): белсенді заказда — 15с сайын (клиент картада
  /// көліктің қалай келе жатқанын көреді), бос әрі тарифте болса — 60с
  /// сайын (клиенттердің картасында «жақын маңдағы көліктер»). Бұрын орын
  /// тек «Белсенді заказ» экраны АШЫҚ тұрғанда жіберілетін — орындаушы
  /// лентаға не басқа бетке шыққан бойда клиенттің картасы «қатып» қалатын.
  /// Қосымша фонда (телефон құлыпта, веб-қойынды жасырын) — жіберілмейді.
  Timer? _locTimer;
  int _locTick = 0;
  bool _foreground = true;
  AppLifecycleListener? _life;

  @override
  void initState() {
    super.initState();
    _life = AppLifecycleListener(
      onShow: () => _foreground = true,
      onResume: () {
        _foreground = true;
        _publishLocation(force: true);
      },
      onHide: () => _foreground = false,
      onPause: () => _foreground = false,
    );
    _statsSub = ref.listenManual<AsyncValue<ExecutorStats>>(
      executorStatsStreamProvider,
      (prev, next) {
        final s = next.value;
        if (s != null) _onStats(s);
      },
      fireImmediately: true,
    );
    _locTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _publishLocation(),
    );
    // Линиядағы орындаушыға жаңа заказ туралы хабарлау (әр 25с)
    _feedWatch = Timer.periodic(
      const Duration(seconds: 25),
      (_) => _checkNewOrders(),
    );
    _checkNewOrders();
  }

  @override
  void dispose() {
    _feedWatch?.cancel();
    _locTimer?.cancel();
    _statsSub?.close();
    _life?.dispose();
    super.dispose();
  }

  bool _settingOn(String key) {
    final v = ref.read(appSettingsProvider).value?[key];
    // Кілт жоқ болса — әдепкі ҚОСУЛЫ (0075/0082 миграцияларындағыдай).
    return v is! Map || v['enabled'] != false;
  }

  Future<void> _publishLocation({bool force = false}) async {
    if (!_foreground || !mounted) return;
    _locTick++;
    final s = _stats;
    if (s == null) return;
    final active = s.busyOrderId != null;
    if (active) {
      if (!_settingOn('live_tracking')) return;
    } else {
      // Бос кезде — минутына бір рет, тек тарифте әрі линияда болса.
      if (!s.hasTariff || !s.onLine || !_settingOn('nearby_map')) return;
      if (!force && _locTick % 4 != 0) return;
    }
    final pos = await Geo.quietPosition();
    if (pos == null) return;
    await Repo.updateExecutorLocation(
      pos.latitude,
      pos.longitude,
      heading: pos.heading >= 0 ? pos.heading : null,
      speed: pos.speed >= 0 ? pos.speed : null,
    );
  }

  /// Экранда — ортақ циклдің соңғы мәні (қосымша сұраусыз). Фонда ортақ
  /// цикл тоқтап тұрады, сол себепті мұнда тікелей сұраймыз.
  Future<ExecutorStats> _currentStats() async {
    final s = _stats;
    if (_foreground && s != null) return s;
    final fresh = await Repo.executorStats();
    _onStats(fresh);
    return fresh;
  }

  void _onStats(ExecutorStats s) {
    final old = _stats;
    _stats = s;
    // Алғашқы дерек не жаңа заказ қабылданған сәт — орынды бірден
    // жібереміз (клиент картасы 15с күтпей-ақ көлікті көреді).
    if (old == null || (old.busyOrderId == null && s.busyOrderId != null)) {
      unawaited(_publishLocation(force: true));
    }
  }

  Future<void> _checkNewOrders() async {
    try {
      final stats = await _currentStats();
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
      final fresh = ids.where((id) => !_notifiedOrders.contains(id)).toList();
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
        Notify.show(
          t('Жаңа заказ бар! 🚚'),
          '${t('Лентада')} ${fresh.length} ${t('жаңа заказ күтіп тұр — қараңыз.')}',
          id: 2,
        );
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    // Төменгі навбар ЖОЙЫЛДЫ: профиль енді «☰» мәзір батырмасынан ашылатын
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
///
/// Дерек — [myActiveExecutorOrdersProvider] (мәзір белгісімен ОРТАҚ бір
/// polling-цикл; build сайын жаңа стрим ашылмайды).
class _BusyOrderBanner extends ConsumerWidget {
  const _BusyOrderBanner();

  void _open(BuildContext context, List<Order> active) {
    if (active.length == 1) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ActiveOrderScreen(orderId: active.first.id),
        ),
      );
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
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ActiveOrderScreen(orderId: o.id),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active =
        ref.watch(myActiveExecutorOrdersProvider).value ?? const <Order>[];
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
  }
}
