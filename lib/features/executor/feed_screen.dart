import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/geo.dart';
import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/map_widgets.dart';
import '../../shared/vehicle_picker.dart';
import '../../shared/widgets.dart';
import '../auth/executor_apply_screen.dart';
import 'bonus_widgets.dart';
import 'dashboard_screen.dart';
import 'executor_order_screen.dart';

/// Орындаушының заказға ұсыныс беруіне кедергі себебі (feed гейті).
enum _Gate {
  notApplied,
  noTariff,
  underReview,
  rejected,
  docsUpdate,
  docsReview,
  wrongCity,
}

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
  /// Орындаушының ағымдағы орны — рұқсат берілсе «жақын заказ»
  /// сұрыптауын НАҚТЫ қашықтықпен есептейміз. Рұқсат жоқ/өшірулі болса
  /// `null` қалады, сол кезде маршрут ұзындығына (`distanceKm`) қарай —
  /// қысқа маршрутты заказдар жақынырақ деп есептейміз.
  Position? _pos;

  @override
  void initState() {
    super.initState();
    // Тыныш сұрайды — бас тартса да лента жұмыс істей береді (fallback).
    Geo.currentPosition().then((p) {
      if (mounted) setState(() => _pos = p);
    });
  }

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
      data: (_) {
        // Лента БАРЛЫҚ орындаушыға көрінеді (тарифсіз/расталмаған да) —
        // сервер `executor_feed` көлік түрі мен қала фильтрін жасайды
        // (0053). Ұсыныс беру құқығы (тариф/мақұлдау) заказды басқанда
        // `_openOrder` ішінде тексеріледі.
        //
        // РЕТІ (үш өлшем қосынды балл ретінде, басымдығы: жаңа → жақын →
        // қымбат): ескі заказ бәрібір алынып қойылған болуы мүмкін,
        // сондықтан ЖАҢАЛЫҒЫ ең салмақты. Одан кейін ЖАҚЫНДЫҒЫ (GPS
        // рұқсаты болса — нақты қашықтық, болмаса — маршрут ұзындығы:
        // қысқа сапарлар «жақынырақ» болып есептеледі). Соңында БАҒАСЫ.
        final eligible = [...feedAsync.value ?? const <Order>[]];
        final maxPrice = eligible.isEmpty
            ? 1
            : eligible
                .map((o) => o.displayPrice ?? 0)
                .reduce((a, b) => a > b ? a : b)
                .clamp(1, 1 << 30);
        double scoreOf(Order o) {
          final ageMin = o.createdAt == null
              ? 999.0
              : DateTime.now().difference(o.createdAt!).inSeconds / 60.0;
          final freshness = (1 - ageMin / 180).clamp(0.0, 1.0);

          final double proximity;
          if (_pos != null) {
            final km = Geo.haversineKm(
              LatLng(_pos!.latitude, _pos!.longitude),
              LatLng(o.fromLat, o.fromLng),
            );
            proximity = (1 - km / 50).clamp(0.0, 1.0);
          } else {
            proximity = (1 - o.distanceKm / 50).clamp(0.0, 1.0);
          }

          final price = ((o.displayPrice ?? 0) / maxPrice).clamp(0.0, 1.0);

          return freshness * 0.5 + proximity * 0.3 + price * 0.2;
        }

        eligible.sort((a, b) => scoreOf(b).compareTo(scoreOf(a)));

        if (eligible.isEmpty) {
          return _refreshable([
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: BonusStrip(),
            ),
            const SizedBox(height: 100),
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
            // 0-элемент — бонус жолағы (0059). Бағдарлама өшірулі болса ол
            // `SizedBox.shrink` қайтарады, сол себепті лента баяғы қалпында.
            itemCount: eligible.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) => i == 0
                ? const BonusStrip()
                : _FeedCard(
                    order: eligible[i - 1],
                    myPos: _pos,
                    onTap: () => _openOrder(eligible[i - 1]),
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

  /// Заказ карточкасын басқанда — алдымен ұсыныс беру құқығын тексереміз.
  /// Тарифсіз/расталмаған/құжаты жаңартылуы керек орындаушыға заказ беті
  /// ашылмайды, оған не істеу керегі айтылады (тариф сатып алу / күту /
  /// қайта толтыру). Құқығы болса — толық детальдар парағы ашылады.
  void _openOrder(Order o) {
    final gate = _actionGate(o);
    if (gate != null) {
      _showGate(gate);
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Gz.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _OrderSheet(
        order: o,
        myPos: _pos,
        onAgree: () => _offer(o, o.clientPrice!, ''),
        onCounter: () => _counterOffer(o),
      ),
    );
  }

  /// Орындаушы осы заказға қазір ұсыныс бере ала ма? null — рұқсат; әйтпесе
  /// бөгеу себебі. Сервер де осыны қайта тексереді (exec_can_take ішінде,
  /// place_offer/accept_offer арқылы) — бұл тек ыңғайлы алдын ала ескерту.
  _Gate? _actionGate(Order o) {
    final epAsync = ref.read(myExecutorProfileProvider);
    final ep = epAsync.value;
    final stats = ref.read(executorStatsStreamProvider).value;
    // Өтінім МҮЛДЕМ жоқ (0063 «танысу режимі») — лентаны көреді, бірақ
    // ұсыныс бере алмайды; өтінім толтыруға шақырамыз. Профиль әлі
    // жүктеліп жатса (`!hasValue`) — «тексеруде» деп ұстай тұрамыз.
    if (epAsync.hasValue && ep == null) return _Gate.notApplied;
    if (ep == null) return _Gate.underReview;
    if (ep.status == 'rejected') return _Gate.rejected;
    if (ep.status != 'approved') return _Gate.underReview;
    if (ep.docsUpdateRequested) return _Gate.docsUpdate;
    if (ep.docsReviewPending) return _Gate.docsReview;
    if (stats == null || !stats.hasTariff) return _Gate.noTariff;
    // ҚАЛА ЕРЕЖЕСІ: жергілікті (межгород ЕМЕС) заказды тек сол қаладағы
    // орындаушы алады; межгород заказды кез келген қаладағы орындаушы алады.
    if (!o.intercity &&
        ep.city != null &&
        o.fromCity != null &&
        !Geo.sameCity(o.fromCity, ep.city)) {
      return _Gate.wrongCity;
    }
    return null;
  }

  void _showGate(_Gate gate) {
    final ep = ref.read(myExecutorProfileProvider).value;
    switch (gate) {
      case _Gate.notApplied:
        _gateDialog(
          icon: Icons.assignment_outlined,
          color: Gz.blue,
          title: t('Алдымен өтінім толтырыңыз'),
          text: t('Заказдарды қарау ашық, ал ұсыныс беру үшін көлігіңіз бен '
              'құжаттарыңызды жіберу керек. Модератор растаған соң заказ '
              'қабылдай бастайсыз.'),
          actionLabel: t('Өтінім толтыру'),
          onAction: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ExecutorApplyScreen()),
          ),
        );
      case _Gate.noTariff:
        _gateDialog(
          icon: Icons.bolt,
          color: Gz.yellowDark,
          title: t('Тарифіңіз жоқ'),
          text: '${t('Заказ алу үшін тариф сатып алыңыз (1 ауысым,')} '
              '${tariffOrdersLabel(ref.read(appConfigProvider).value ?? AppConfig())}).',
          actionLabel: t('Тарифке кіру'),
          onAction: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ExecutorDashboardScreen()),
          ),
        );
      case _Gate.underReview:
        _gateDialog(
          icon: Icons.hourglass_top,
          color: Gz.blue,
          title: t('Аккаунтыңыз тексеруде'),
          text: t('Расталған соң тариф алып, заказ қабылдай аласыз.'),
        );
      case _Gate.rejected:
        _gateDialog(
          icon: Icons.cancel_outlined,
          color: Gz.red,
          title: t('Өтінім қабылданбады'),
          text: ep?.moderationComment?.isNotEmpty == true
              ? '${t('Себебі:')} ${ep!.moderationComment}'
              : t('Деректерді түзетіп, қайта жіберіңіз.'),
          actionLabel: t('Қайта толтыру'),
          onAction: ep == null
              ? null
              : () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ExecutorApplyScreen(existing: ep),
                  ),
                ),
        );
      case _Gate.docsUpdate:
        _gateDialog(
          icon: Icons.assignment_late,
          color: Gz.red,
          title: t('Құжаттарды жаңарту қажет'),
          text: ep?.docsUpdateComment?.isNotEmpty == true
              ? ep!.docsUpdateComment!
              : t('Модератор құжаттарды жаңартуды сұрады.'),
          actionLabel: t('Жаңарту'),
          onAction: ep == null
              ? null
              : () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ExecutorApplyScreen(existing: ep),
                  ),
                ),
        );
      case _Gate.docsReview:
        _gateDialog(
          icon: Icons.hourglass_top,
          color: Gz.blue,
          title: t('Құжаттар тексеруде'),
          text: t('Расталған соң заказ қабылдай аласыз.'),
        );
      case _Gate.wrongCity:
        _gateDialog(
          icon: Icons.location_off_outlined,
          color: Gz.textSecondary,
          title: t('Бұл сіздің қалаңызда емес'),
          text: t('Қала ішіндегі заказды тек сол қаладағы орындаушы алады. '
              'Сізге — қалааралық заказдар.'),
        );
    }
  }

  void _gateDialog({
    required IconData icon,
    required Color color,
    required String title,
    required String text,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(icon, color: color, size: 34),
        title: Text(title, textAlign: TextAlign.center),
        content: Text(text, textAlign: TextAlign.center),
        actions: [
          if (actionLabel != null && onAction != null)
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                onAction();
              },
              child: Text(actionLabel),
            )
          else
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(t('Түсінікті')),
            ),
        ],
      ),
    );
  }

  Future<void> _offer(Order o, int price, String message) async {
    try {
      await Repo.placeOffer(o.id, price, message);
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ExecutorOrderScreen(orderId: o.id)),
        );
      }
    } catch (e) {
      if (mounted) showSnack(context, errText(e), error: true);
    }
  }

  Future<void> _counterOffer(Order o) async {
    final result = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => PriceStepperSheet(order: o),
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

  /// Орындаушының ағымдағы орны — «алу нүктесі МЕНЕН қанша алыс?» деген
  /// сұраққа жауап беру үшін. GPS рұқсаты жоқ болса null (тег көрінбейді).
  final Position? myPos;

  const _FeedCard({required this.order, required this.onTap, this.myPos});

  /// Орындаушыдан алу нүктесіне дейінгі тік қашықтық (км).
  double? get _toPickupKm {
    final p = myPos;
    if (p == null) return null;
    return Geo.haversineKm(
      LatLng(p.latitude, p.longitude),
      LatLng(order.fromLat, order.fromLng),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Gz.surface,
      borderRadius: BorderRadius.circular(Gz.radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(Gz.radius),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Gz.radius),
            border: Border.all(color: Gz.border, width: 1),
            // Лентадағы карточкалар фоннан «көтеріліп» тұрады — тізім
            // жалғасқан жалпақ жолақ емес, бөлек-бөлек карта болып оқылады.
            boxShadow: Gz.cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: _ClientMini(clientId: order.clientId)),
                  const SizedBox(width: 8),
                  // Баға — орындаушы лентаны ЕҢ АЛДЫМЕН сол сан бойынша
                  // шолады, сол себепті ең салмақты элемент.
                  Text(fmtT(order.displayPrice), style: Gz.money),
                ],
              ),
              const SizedBox(height: 11),
              _CompactRoute(from: order.fromDisplay, to: order.toDisplay),
              const SizedBox(height: 11),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  // «Алу нүктесі МЕНЕН қанша алыс?» — орындаушы заказды алар
                  // алдында алдымен осыны сұрайды (бекер жол жүрмеу үшін).
                  // 5 км-ге дейін ЖАСЫЛ: «жақын, тиімді» деген белгі.
                  if (_toPickupKm case final km?)
                    _tag(
                      Icons.near_me_rounded,
                      '${t('Сізден')} ${km < 10 ? km.toStringAsFixed(1) : km.round()} ${t('км')}',
                      color: km <= 5 ? Gz.green : null,
                    ),
                  _tag(
                    Icons.local_shipping,
                    order.vehicleType.label,
                    leading: vehicleIcon(
                      order.vehicleType,
                      size: 14,
                      color: Gz.textSecondary,
                    ),
                  ),
                  // Аралық аялдама бар заказ (0047) — лентада БІРДЕН көрінеді.
                  if (order.hasStops)
                    _tag(
                      Icons.adjust,
                      '+${order.stops.length} ${t('аялдама')}',
                    ),
                  if (order.fromCity != null && order.toCity != null)
                    _tag(
                      order.intercity
                          ? Icons.alt_route
                          : Icons.location_city_outlined,
                      order.intercity ? t('Межгород') : t('Қала ішінде'),
                    ),
                  if (order.distanceKm > 0)
                    _tag(
                      Icons.route,
                      '≈ ${order.distanceKm.toStringAsFixed(1)} км',
                    ),
                  if (order.cargoDesc.isNotEmpty)
                    _tag(
                      Icons.inventory_2_outlined,
                      order.cargoDesc,
                      flexible: true,
                    ),
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

  Widget _tag(
    IconData icon,
    String text, {
    bool flexible = false,
    Widget? leading,

    /// Ерекшелегіміз келсе — тегтің өз түсі (мыс. «жақын» = жасыл).
    Color? color,
  }) {
    final chip = Container(
      padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
      decoration: BoxDecoration(
        color: color == null ? Gz.surfaceAlt : Gz.tint(color, 0.11),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
            color: color == null ? Gz.border : Gz.tint(color, 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          leading ?? Icon(icon, size: 13, color: color ?? Gz.textSecondary),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                color: color ?? Gz.ink,
                letterSpacing: -0.05,
                fontWeight: FontWeight.w700,
              ),
            ),
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
            InitialsAvatar(
              p?.fullName ?? '?',
              radius: 15,
              imageUrl: p?.avatarUrl,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p?.fullName ?? '…',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                    ),
                  ),
                  // Лентада ОРЫНДАУШЫ клиентті көреді → клиенттік рейтинг
                  // (адам қазір орындаушы режиміне ауысып кеткен болса да).
                  RatingStars(
                    p?.ratingAs('client') ?? 0,
                    count: p?.ratingCountAs('client') ?? 0,
                    size: 11,
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
        // Екі нүктені жалғайтын нүктелі сызық — «маршрут» екені көзге
        // бірден түседі (бұрын екі жол жай ғана қатар тұратын).
        Padding(
          padding: const EdgeInsets.only(left: 6.5),
          child: Container(
            width: 1.6,
            height: 10,
            color: Gz.border,
          ),
        ),
        _line(Icons.location_on, Gz.red, to),
      ],
    );
  }

  Widget _line(IconData icon, Color color, String text) => Row(
    children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 7),
      Expanded(
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              height: 1.3,
              letterSpacing: -0.1),
        ),
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

  /// Орындаушының ағымдағы орны — алу нүктесіне дейінгі қашықтықты
  /// көрсету үшін (GPS рұқсаты жоқ болса null).
  final Position? myPos;

  const _OrderSheet({
    required this.order,
    required this.onAgree,
    required this.onCounter,
    this.myPos,
  });

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
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: Gz.disabledBg,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          const SizedBox(height: 14),
          // ---- 1) БАҒА: орындаушы ЕҢ АЛДЫМЕН осыны көреді ----
          Row(
            children: [
              Expanded(
                child: Text(
                  fmtT(o.displayPrice),
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                    letterSpacing: -1,
                    color: Gz.ink,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              vehicleIcon(o.vehicleType, size: 20, color: Gz.textSecondary),
              const SizedBox(width: 6),
              Flexible(
                child: BtnLabel(
                  o.vehicleType.label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: Gz.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // ---- 2) БАҒЫТ: «қайдан → қайда» БІР ҚАРАҒАНДА ----
          // Орындаушының екінші сұрағы — «бұл маған жол ма?». Қала атаулары
          // мен қашықтық бір жолда ірі әрі қою тұрса, ол жауапты мекенжай
          // жолдарын оқымай-ақ алады.
          _DirectionStrip(order: o, myPos: myPos),
          const SizedBox(height: 12),
          // ---- 3) КАРТА: түртсе толық экранда ашылады ----
          RouteMap(
            from: LatLng(o.fromLat, o.fromLng),
            to: LatLng(o.toLat, o.toLng),
            stops: o.stops.map((s) => LatLng(s.lat, s.lng)).toList(),
            height: 200,
            fromLabel: o.fromDisplay,
            toLabel: o.toDisplay,
            stopLabels: o.stops.map((s) => s.display).toList(),
            distanceKm: o.distanceKm > 0 ? o.distanceKm : null,
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
                if (o.comment.isNotEmpty) InfoRow(t('Түсініктеме'), o.comment),
                // «Бағыты» мен «Қашықтық» ӘДЕЙІ ЖОҚ: екеуі де жоғарыдағы
                // бағыт жолағында ірі әрі айқын тұр — мұнда қайталанса,
                // парақ ұзарып, маңыздысы төмен ысырылар еді.
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
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    side: const BorderSide(color: Gz.ink, width: 1.6),
                  ),
                  onPressed: () {
                    Navigator.of(context).pop();
                    onCounter();
                  },
                  child: BtnLabel(t('Өз бағам')),
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

/// «ҚАЙДАН → ҚАЙДА» жолағы — орындаушының шешім қабылдауына керек ЕКІНШІ
/// ақпарат (біріншісі — баға).
///
/// Мекенжайдың толық жолын («Абая 15, 3-подъезд») оқу уақыт алады, ал
/// орындаушыға алдымен МАСШТАБ керек: қала ішінде ме, әлде басқа қалаға
/// ма, қанша шақырым. Сол себепті мұнда тек қала атаулары ірі әрі қою
/// жазылады, астында — қашықтық пен бағыт түрі. Толық мекенжайлар
/// төмендегі маршрут тізімінде қалады.
class _DirectionStrip extends StatelessWidget {
  final Order order;
  final Position? myPos;
  const _DirectionStrip({required this.order, this.myPos});

  /// Қала белгісіз болса — мекенжай жолының БІРІНШІ бөлігі (әдетте елді
  /// мекеннің аты сонда тұрады).
  static String _place(String? city, String fallback) {
    if (city != null && city.trim().isNotEmpty) return city.trim();
    final head = fallback.split(',').first.trim();
    return head.isEmpty ? '—' : head;
  }

  @override
  Widget build(BuildContext context) {
    final o = order;
    final accent = o.intercity ? Gz.violet : Gz.blue;
    final from = _place(o.fromCity, o.fromDisplay);
    final to = _place(o.toCity, o.toDisplay);

    final p = myPos;
    final toPickup = p == null
        ? null
        : Geo.haversineKm(
            LatLng(p.latitude, p.longitude),
            LatLng(o.fromLat, o.fromLng),
          );

    final facts = <String>[
      if (o.distanceKm > 0) '${o.distanceKm.toStringAsFixed(1)} ${t('км')}',
      o.intercity ? t('Қалааралық') : t('Қала ішінде'),
      if (o.hasStops) '+${o.stops.length} ${t('аялдама')}',
      // Алу нүктесіне дейінгі жол — «бекер бармаймын ба?» деген сұрақтың
      // жауабы. Ол маршрут ұзындығынан БӨЛЕК: заказ қысқа болса да, алуға
      // 30 км жүру керек болуы мүмкін.
      if (toPickup != null)
        '${t('Сізден')} ${toPickup < 10 ? toPickup.toStringAsFixed(1) : toPickup.round()} ${t('км')}',
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Gz.tint(accent, 0.10), Gz.surfaceAlt],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Gz.tint(accent, 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Қала атаулары ұзын болуы мүмкін («Петропавл» / «Усть-Каменогорск»)
          // — екеуі де Flexible + BtnLabel, сол себепті ЕШҚАШАН екінші жолға
          // түспейді де, қиылмайды: сыймаса сәл кішірейеді.
          Row(
            children: [
              const MapPin.origin(size: 15),
              const SizedBox(width: 8),
              Flexible(
                child: BtnLabel(
                  from,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    height: 1.15,
                    letterSpacing: -0.4,
                    color: Gz.ink,
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Icon(Icons.arrow_forward_rounded, size: 17, color: accent),
              const SizedBox(width: 9),
              Flexible(
                child: BtnLabel(
                  to,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    height: 1.15,
                    letterSpacing: -0.4,
                    color: Gz.ink,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const MapPin.destination(size: 15),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            facts.join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.2,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.1,
              color: accent,
            ),
          ),
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
        child: ProfileBrief(
          profile: snap.data,
          subtitle: t('Клиент'),
          asRole: 'client',
        ),
      ),
    );
  }
}

/// −/+ батырмаларымен баға ұсыну терезесі (100 ₸ қадаммен).
///
/// Лентадан да, хабарландыруды басып ашылған заказ бетінен де
/// ([ExecutorOrderScreen]) қолданылады — сол себепті ашық (public).
class PriceStepperSheet extends StatefulWidget {
  final Order order;
  const PriceStepperSheet({super.key, required this.order});

  @override
  State<PriceStepperSheet> createState() => _PriceStepperSheetState();
}

class _PriceStepperSheetState extends State<PriceStepperSheet> {
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
          Text(
            t('Өз бағаңызды ұсыныңыз'),
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 4),
          if (base != null)
            Text(
              '${t('Клиенттің бағасы:')} ${fmtT(base)}',
              style: const TextStyle(color: Gz.textSecondary, fontSize: 13),
            ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _StepBtn(
                icon: Icons.remove,
                onTap: () => _bump(-_step),
                onLong: () => _bump(-1000),
              ),
              Column(
                children: [
                  Text(
                    fmtT(_price),
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    t('±100 ₸ қадам'),
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Gz.textSecondary,
                    ),
                  ),
                ],
              ),
              _StepBtn(
                icon: Icons.add,
                onTap: () => _bump(_step),
                onLong: () => _bump(1000),
              ),
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
  const _StepBtn({
    required this.icon,
    required this.onTap,
    required this.onLong,
  });

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
