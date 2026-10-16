import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' hide Path;

import '../../core/geo.dart';
import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/prefs.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/map_widgets.dart';
import '../../shared/vehicle_picker.dart';
import '../../shared/widgets.dart';
import '../auth/executor_apply_screen.dart';
import 'bonus_widgets.dart';
import 'dashboard_screen.dart';
import 'executor_order_screen.dart';
import 'offer_sheet.dart';

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

/// Лентаның реті: ұсынылған (жаңа+жақын+қымбат балы), ең жақын, ең
/// қымбат, ең жаңа.
enum _FeedSort { best, near, price, fresh }

/// Қай заказдар: барлығы / қала ішінде / межгород.
enum _FeedScope { all, city, intercity }

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

  /// Сұрыптау мен сүзгі (есте қалады), тізім/карта, жасырылған заказдар.
  _FeedSort _sort = _FeedSort.best;
  _FeedScope _scope = _FeedScope.all;
  bool _mapView = false;
  Set<String> _hidden = {};

  @override
  void initState() {
    super.initState();
    // Тыныш сұрайды — бас тартса да лента жұмыс істей береді (fallback).
    Geo.currentPosition().then((p) {
      if (mounted) setState(() => _pos = p);
    });
    _restoreView();
  }

  Future<void> _restoreView() async {
    final (sort, scope) = await Prefs.feedView();
    final hidden = await Prefs.hiddenOrders();
    if (!mounted) return;
    setState(() {
      _sort = _FeedSort.values.firstWhere(
        (v) => v.name == sort,
        orElse: () => _FeedSort.best,
      );
      _scope = _FeedScope.values.firstWhere(
        (v) => v.name == scope,
        orElse: () => _FeedScope.all,
      );
      _hidden = hidden;
    });
  }

  void _setView({_FeedSort? sort, _FeedScope? scope}) {
    setState(() {
      _sort = sort ?? _sort;
      _scope = scope ?? _scope;
    });
    Prefs.setFeedView(_sort.name, _scope.name);
  }

  /// Ұзақ басқанда — «Бұл заказ маған қызық емес» (лентадан жасыру).
  Future<void> _hide(Order o) async {
    final ok = await confirmDialog(
      context,
      title: t('Заказды жасыру керек пе?'),
      message: t('Бұл заказ лентаңызда енді көрінбейді. Барлығын қайта '
          'көрсету — лента сүзгісінің астында.'),
      confirmLabel: t('Жасыру'),
      icon: Icons.visibility_off_outlined,
    );
    if (!ok || !mounted) return;
    setState(() => _hidden = {..._hidden, o.id});
    await Prefs.hideOrder(o.id);
  }

  Future<void> _unhideAll() async {
    await Prefs.unhideAllOrders();
    if (mounted) setState(() => _hidden = {});
  }

  double? _kmTo(Order o) {
    final p = _pos;
    if (p == null) return null;
    return Geo.haversineKm(
      LatLng(p.latitude, p.longitude),
      LatLng(o.fromLat, o.fromLng),
    );
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
        final all = feedAsync.value ?? const <Order>[];
        final hiddenCount = all.where((o) => _hidden.contains(o.id)).length;
        final eligible = [
          for (final o in all)
            if (!_hidden.contains(o.id) &&
                switch (_scope) {
                  _FeedScope.all => true,
                  _FeedScope.city => !o.intercity,
                  _FeedScope.intercity => o.intercity,
                })
              o,
        ];
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

        switch (_sort) {
          case _FeedSort.best:
            eligible.sort((a, b) => scoreOf(b).compareTo(scoreOf(a)));
          case _FeedSort.near:
            eligible.sort(
              (a, b) => (_kmTo(a) ?? a.distanceKm).compareTo(
                _kmTo(b) ?? b.distanceKm,
              ),
            );
          case _FeedSort.price:
            eligible.sort(
              (a, b) => (b.displayPrice ?? 0).compareTo(a.displayPrice ?? 0),
            );
          case _FeedSort.fresh:
            eligible.sort(
              (a, b) => (b.createdAt ?? DateTime(2000)).compareTo(
                a.createdAt ?? DateTime(2000),
              ),
            );
        }

        final toolbar = _FeedToolbar(
          sort: _sort,
          scope: _scope,
          mapView: _mapView,
          hasGps: _pos != null,
          hiddenCount: hiddenCount,
          onSort: (s) => _setView(sort: s),
          onScope: (s) => _setView(scope: s),
          onMapView: (v) => setState(() => _mapView = v),
          onUnhide: _unhideAll,
        );

        if (eligible.isEmpty) {
          return Column(
            children: [
              toolbar,
              Expanded(
                child: _refreshable([
                  const Padding(
                    padding: EdgeInsets.fromLTRB(12, 12, 12, 0),
                    child: BonusStrip(),
                  ),
                  const SizedBox(height: 80),
                  EmptyState(
                    icon: Icons.hourglass_empty,
                    title: t('Әзірге заказ жоқ'),
                    subtitle: _scope == _FeedScope.all
                        ? t('Жаңа заказдар осы жерде автоматты пайда болады.')
                        : t('Сүзгіні «Барлығы» деп ауыстырып көріңіз.'),
                  ),
                ]),
              ),
            ],
          );
        }

        return Column(
          children: [
            toolbar,
            Expanded(
              child: _mapView
                  ? _FeedMap(
                      orders: eligible,
                      myPos: _pos,
                      onTap: _openOrder,
                    )
                  : RefreshIndicator(
                      color: Gz.ink,
                      onRefresh: _manualRefresh,
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                        // 0-элемент — бонус жолағы (0059). Бағдарлама өшірулі
                        // болса ол `SizedBox.shrink` қайтарады.
                        itemCount: eligible.length + 1,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (_, i) => i == 0
                            ? const BonusStrip()
                            : _FeedCard(
                                order: eligible[i - 1],
                                myPos: _pos,
                                onTap: () => _openOrder(eligible[i - 1]),
                                onLongPress: () => _hide(eligible[i - 1]),
                              ),
                      ),
                    ),
            ),
          ],
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
    showGzSheet(
      context,
      builder: (_) => _OrderSheet(
        order: o,
        myPos: _pos,
        onAgree: () => _makeOffer(o, counter: false),
        onCounter: () => _makeOffer(o, counter: true),
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
    gzInfoDialog(
      context,
      icon: icon,
      color: color,
      title: title,
      message: text,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  /// Ұсыныс: баға (келісу не өз бағам) + келу уақыты + қысқа хабар —
  /// бір терезеде ([showOfferSheet]).
  Future<void> _makeOffer(Order o, {required bool counter}) async {
    final p = _pos;
    final km = p == null
        ? null
        : Geo.haversineKm(
            LatLng(p.latitude, p.longitude),
            LatLng(o.fromLat, o.fromLng),
          );
    final d = await showOfferSheet(
      context,
      order: o,
      counter: counter,
      kmToPickup: km,
    );
    if (d == null || !mounted) return;
    try {
      await Repo.placeOffer(o.id, d.price, d.message, etaMin: d.etaMin);
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ExecutorOrderScreen(orderId: o.id)),
        );
      }
    } catch (e) {
      if (mounted) showSnack(context, errText(e), error: true);
    }
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

  /// Ұзақ басу — заказды лентадан жасыру.
  final VoidCallback? onLongPress;

  const _FeedCard({
    required this.order,
    required this.onTap,
    this.myPos,
    this.onLongPress,
  });

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
        onLongPress: onLongPress,
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
                  // Қосымша талаптар (0075): тиеуші, қабат, лифт.
                  if (order.loaders > 0)
                    _tag(
                      Icons.groups_rounded,
                      '${order.loaders} ${t('тиеуші')}',
                      color: Gz.violet,
                    ),
                  if (order.floorFrom != null || order.floorTo != null)
                    _tag(
                      Icons.stairs_rounded,
                      '${order.floorFrom ?? '—'} → ${order.floorTo ?? '—'} '
                      '${t('қабат')}'
                      '${order.hasElevator == true ? ' · ${t('лифт')}' : ''}',
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
        borderRadius: BorderRadius.circular(8),
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
                fontSize: 12,
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
                      fontSize: 14,
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
              fontSize: 14,
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
                borderRadius: BorderRadius.circular(4),
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
                    fontSize: 24,
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
        borderRadius: BorderRadius.circular(20),
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
              fontSize: 13,
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

/// Лентаның үстіңгі жолағы: Тізім/Карта, сұрыптау, қала ішінде/межгород.
/// Таңдау есте қалады (келесі ашылуда сол күйде).
class _FeedToolbar extends StatelessWidget {
  final _FeedSort sort;
  final _FeedScope scope;
  final bool mapView;
  final bool hasGps;
  final int hiddenCount;
  final ValueChanged<_FeedSort> onSort;
  final ValueChanged<_FeedScope> onScope;
  final ValueChanged<bool> onMapView;
  final VoidCallback onUnhide;

  const _FeedToolbar({
    required this.sort,
    required this.scope,
    required this.mapView,
    required this.hasGps,
    required this.hiddenCount,
    required this.onSort,
    required this.onScope,
    required this.onMapView,
    required this.onUnhide,
  });

  String _sortLabel(_FeedSort s) => switch (s) {
    _FeedSort.best => t('Ұсынылған'),
    _FeedSort.near => t('Жақын'),
    _FeedSort.price => t('Қымбат'),
    _FeedSort.fresh => t('Жаңа'),
  };

  String _scopeLabel(_FeedScope s) => switch (s) {
    _FeedScope.all => t('Барлығы'),
    _FeedScope.city => t('Қала ішінде'),
    _FeedScope.intercity => t('Межгород'),
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // Тізім / Карта
              SegmentedButton<bool>(
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  selectedBackgroundColor: Gz.ink,
                  selectedForegroundColor: Gz.yellow,
                ),
                segments: [
                  ButtonSegment(
                    value: false,
                    icon: const Icon(Icons.view_agenda_outlined, size: 18),
                    tooltip: t('Тізім'),
                  ),
                  ButtonSegment(
                    value: true,
                    icon: const Icon(Icons.map_outlined, size: 18),
                    tooltip: t('Карта'),
                  ),
                ],
                selected: {mapView},
                onSelectionChanged: (v) => onMapView(v.first),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final s in _FeedScope.values)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(_scopeLabel(s)),
                            selected: scope == s,
                            visualDensity: VisualDensity.compact,
                            onSelected: (_) => onScope(s),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              PopupMenuButton<_FeedSort>(
                tooltip: t('Сұрыптау'),
                initialValue: sort,
                onSelected: onSort,
                itemBuilder: (_) => [
                  for (final s in _FeedSort.values)
                    if (s != _FeedSort.near || hasGps)
                      PopupMenuItem(value: s, child: Text(_sortLabel(s))),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.swap_vert_rounded, size: 20),
                      const SizedBox(width: 2),
                      Text(
                        _sortLabel(sort),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (hiddenCount > 0)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: Gz.textSecondary,
                ),
                onPressed: onUnhide,
                icon: const Icon(Icons.visibility_outlined, size: 16),
                label: Text('${t('Жасырылған заказдар')}: $hiddenCount · '
                    '${t('көрсету')}'),
              ),
            ),
        ],
      ),
    );
  }
}

/// Лентаның КАРТА көрінісі: әр заказ алу нүктесінде бағасымен; басса —
/// заказ терезесі. Орындаушы «қай жақта заказ көп» дегенді бір қарағанда
/// көреді.
class _FeedMap extends StatelessWidget {
  final List<Order> orders;
  final Position? myPos;
  final ValueChanged<Order> onTap;

  const _FeedMap({
    required this.orders,
    required this.myPos,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final me = myPos == null
        ? null
        : LatLng(myPos!.latitude, myPos!.longitude);
    final points = [
      for (final o in orders) LatLng(o.fromLat, o.fromLng),
      ?me,
    ];
    final single = points.length < 2;
    return FlutterMap(
      options: MapOptions(
        initialCenter: single
            ? (points.isEmpty ? Geo.almaty : points.first)
            : points.first,
        initialZoom: 13,
        backgroundColor: Gz.bg,
        initialCameraFit: single
            ? null
            : CameraFit.bounds(
                bounds: LatLngBounds.fromPoints(points),
                padding: const EdgeInsets.all(56),
                maxZoom: 15,
              ),
      ),
      children: [
        osmTileLayer(),
        MarkerLayer(
          markers: [
            if (me != null)
              Marker(
                point: me,
                width: 22,
                height: 22,
                child: Container(
                  decoration: BoxDecoration(
                    color: Gz.blue,
                    shape: BoxShape.circle,
                    border: Border.all(color: Gz.surface, width: 3),
                    boxShadow: Gz.cardShadow,
                  ),
                ),
              ),
            for (final o in orders)
              Marker(
                point: LatLng(o.fromLat, o.fromLng),
                width: 96,
                height: 40,
                alignment: Alignment.topCenter,
                child: GestureDetector(
                  onTap: () => onTap(o),
                  child: _PricePin(order: o),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Картадағы заказ белгісі: баға жазылған «тамшы».
class _PricePin extends StatelessWidget {
  final Order order;
  const _PricePin({required this.order});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(6, 4, 8, 4),
          decoration: BoxDecoration(
            color: Gz.ink,
            borderRadius: BorderRadius.circular(Gz.rSm),
            boxShadow: Gz.cardShadow,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              vehicleIcon(order.vehicleType, size: 16),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  fmtT(order.displayPrice),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Gz.yellow,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
        CustomPaint(
          size: const Size(10, 6),
          painter: _PinTailPainter(),
        ),
      ],
    );
  }
}

class _PinTailPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = Gz.ink);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
