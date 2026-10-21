import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' hide Path;

import '../../core/geo.dart';
import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/order_alert.dart';
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

/// Карточкалардың бұрыш радиусы (лента мен парақ ішіндегі блоктар).
const double _cardRadius = Gz.rLg;

/// Заказдың «жаңалығы»: осы уақыттан жас заказ «ЖАҢА» белгісімен
/// (жыпылықтаған нүктемен) көрсетіледі.
const Duration _freshWindow = Duration(minutes: 1);

/// «2 мин бұрын», «3 сағ бұрын», «2 күн бұрын» — заказдың қанша бұрын
/// жарияланғаны. Минуттан аз болса бос жол (оның орнына «ЖАҢА» белгісі).
String _ago(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff < _freshWindow) return '';
  if (diff.inMinutes < 60) return '${diff.inMinutes} ${t('мин бұрын')}';
  if (diff.inHours < 24) return '${diff.inHours} ${t('сағ бұрын')}';
  return '${diff.inDays} ${t('күн бұрын')}';
}

/// Уақыт бүгін болса — тек «14:30», басқа күн болса — толық күн.
String _when(DateTime d) {
  final l = d.toLocal();
  final now = DateTime.now();
  final today = l.year == now.year && l.month == now.month && l.day == now.day;
  return today ? fmtTime(l) : fmtDate(l);
}

/// Қашықтықты қысқа жазу: 10 км-ге дейін бір ондық таңбамен.
String _km(double km) =>
    '${km < 10 ? km.toStringAsFixed(1) : km.round()} ${t('км')}';

/// Сапардың ШАМАЛАС ұзақтығы (минут): қала ішінде ~28 км/сағ (кептеліс,
/// бағдаршам) + 3 мин тоқтау, қалааралықта ~70 км/сағ. Нақты есеп емес —
/// карточкада әрқашан «≈» белгісімен көрсетіледі.
int _tripMinutes(Order o) {
  final speed = o.intercity ? 70.0 : 28.0;
  return (o.distanceKm / speed * 60).round() + (o.intercity ? 0 : 3);
}

/// «≈ 25 мин», «≈ 2 сағ 10 мин».
String _duration(int min) {
  if (min < 60) return '≈ $min ${t('мин')}';
  final h = min ~/ 60, m = min % 60;
  return m == 0 ? '≈ $h ${t('сағ')}' : '≈ $h ${t('сағ')} $m ${t('мин')}';
}

/// Лента сүзгісі (қойындылар) — лентадағы ЖАЛҒЫЗ сүзгі.
enum _FeedFilter { all, city, intercity }

/// Лентаның реті: ұсынылған (жаңа әрі жақын — қараңыз: `rankOf`), ең
/// жақын, ең қымбат, ең жаңа. Таңдау есте қалады.
enum _FeedSort { best, near, price, fresh }

/// Орындаушыдан алу нүктесіне дейінгі тік қашықтық (км). GPS жоқ — null.
double? _pickupKm(Position? p, Order o) => p == null
    ? null
    : Geo.haversineKm(
        LatLng(p.latitude, p.longitude),
        LatLng(o.fromLat, o.fromLng),
      );

/// Заказдар лентасы (басты бетке ендірілетін дене). Сервер орындаушының
/// КӨЛІК ТҮРІНЕ сай заказдарды ғана береді (executor_feed → exec_can_take).
/// Карточкалар ықшам әрі бір қарағанда оқылады; басқанда ғана карта +
/// «Келісу/Өз бағам» ашылады.
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

  /// Ашық тұрған заказ парағына берілетін орын (парақ жеке бет — лентаның
  /// setState-і оны қайта салмайды).
  final _posLive = ValueNotifier<Position?>(null);

  /// Кіру анимациясы БІР рет қана ойналған заказдар. Тізімді айналдырып
  /// қайта оралғанда карточка қайта «ұшып кірмеуі» үшін.
  final Set<String> _introduced = <String>{};

  /// Алдыңғы снапшоттағы заказ id-лері. Анимация тек ЖАҢАДАН келген
  /// заказға (және алғашқы жүктелудегі алғашқы карточкаларға) ойналады —
  /// тізімді төмен айналдырғанда кейінірек құрылатын ескі карточкалар
  /// кешігіп «бос» тұрмауы үшін.
  Set<String>? _known;

  /// Таңдалған қойынды: барлығы / қала ішінде / қалааралық.
  _FeedFilter _filter = _FeedFilter.all;

  /// Сұрыптау (есте қалады), тізім/карта көрінісі, жасырылған заказдар.
  _FeedSort _sort = _FeedSort.best;
  bool _mapView = false;
  Set<String> _hidden = {};

  /// ДЫБЫС үшін: осы экран ашылғалы көрген БАРЛЫҚ заказ (қойынды сүзгісіне
  /// қарамай). null — алғашқы жүктелу әлі келмеді (онда дыбыс жоқ).
  Set<String>? _seenAll;

  /// [_seenAll] қай қала үшін жиналды (қала ауысса — негіз қайта құрылады).
  String? _seenCity;

  /// Жаңа келген, әлі ашылмаған заказдар — карточкасы жарқырап тұрады.
  final Set<String> _glow = {};
  final Map<String, Timer> _glowTimers = {};

  /// Тізім төмен айналдырылып тұрса — жоғарыдағы «Жаңа заказ» жолағы.
  final _scroll = ScrollController();
  int _bannerCount = 0;
  Timer? _bannerTimer;

  @override
  void initState() {
    super.initState();
    // Тыныш сұрайды — бас тартса да лента жұмыс істей береді (fallback).
    Geo.currentPosition().then((p) {
      if (mounted) setState(() => _pos = p);
    });
    _restoreView();
    OrderAlert.load();
    OrderAlert.feedProbe = _willAlert;
  }

  @override
  void dispose() {
    if (OrderAlert.feedProbe == _willAlert) OrderAlert.feedProbe = null;
    for (final t in _glowTimers.values) {
      t.cancel();
    }
    _bannerTimer?.cancel();
    _scroll.dispose();
    _posLive.dispose();
    super.dispose();
  }

  /// Лента ШЫНЫМЕН көрініп тұр ма: қосымша алдыңғы планда, үстінде басқа
  /// бет (заказ, чат) ашылмаған.
  bool _visible() =>
      mounted &&
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed &&
      (ModalRoute.of(context)?.isCurrent ?? true);

  /// Лентаның әр жаңа снапшоты. Алғашқы жүктелуде, қойынды ауысқанда,
  /// жасырылған заказда дыбыс ОЙНАМАЙДЫ — тек шынымен жаңа заказ келгенде.
  void _onFeed(List<Order>? list) {
    if (list == null) return;
    // Негізгі жиынға ЖАСЫРЫЛҒАНДАР да кіреді: оларды кейін қайта көрсеткенде
    // ескі заказ «жаңа» болып дыбыстамауы керек.
    final ids = {for (final o in list) o.id};
    // Қала ауысса (басқа қаланың лентасы) — жаңа қаланың заказдары ескі
    // заказдар болып саналады, үнсіз негіз болады.
    final city = ref.read(myExecutorProfileProvider).value?.city;
    final seen = _seenAll;
    if (seen == null || city != _seenCity) {
      _seenAll = ids;
      _seenCity = city;
      return;
    }
    final fresh = [
      for (final o in list)
        if (!seen.contains(o.id) && !_hidden.contains(o.id)) o,
    ];
    seen.addAll(ids);
    // Ұзақ жұмыста жиын шексіз өспесін.
    if (seen.length > 600) _seenAll = ids;
    if (fresh.isEmpty) return;
    // Жарқыл мен жоғарғы жолақ — тек АШЫҚ тұрған қойындыдағы заказдарға
    // (басқа қойындыдағы заказ үшін «жаңа заказ шықты» деп алдамаймыз).
    // Дыбыс — кез келген жаңа заказға.
    final inTab = [
      for (final o in fresh)
        if (_inFilter(o)) o.id,
    ];
    if (inTab.isNotEmpty) {
      setState(() {
        _glow.addAll(inTab);
        if (_scroll.hasClients && _scroll.offset > 120) {
          _bannerCount += inTab.length;
        }
      });
      for (final id in inTab) {
        _glowTimers[id]?.cancel();
        _glowTimers[id] = Timer(_freshWindow, () {
          _glowTimers.remove(id);
          if (mounted) setState(() => _glow.remove(id));
        });
      }
    }
    if (_bannerCount > 0) {
      _bannerTimer?.cancel();
      _bannerTimer = Timer(const Duration(seconds: 10), () {
        if (mounted) setState(() => _bannerCount = 0);
      });
    }
    if (_visible()) OrderAlert.play();
  }

  bool _inFilter(Order o) => switch (_filter) {
    _FeedFilter.all => true,
    _FeedFilter.city => !o.intercity,
    _FeedFilter.intercity => o.intercity,
  };

  /// Push келген заказ туралы лента ӨЗІ дабыл бере ме (экранда, негіз
  /// жүктелген, заказ әлі көрілмеген әрі жасырылмаған). Тек сонда push
  /// хабарламасы қосымша ішінде қайталанбайды; қайта ескерту (escalation)
  /// сияқты бұрыннан көрген заказдың push-ы әдеттегідей шығады.
  bool _willAlert(String orderId) {
    final seen = _seenAll;
    return _visible() &&
        seen != null &&
        !seen.contains(orderId) &&
        !_hidden.contains(orderId);
  }

  void _scrollToTop() {
    _bannerTimer?.cancel();
    setState(() => _bannerCount = 0);
    if (_scroll.hasClients) {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    }
  }

  /// Соңғы таңдалған қойынды мен рет (Prefs-тегі «scope» ұяшығы —
  /// қойындының атауы: all / city / intercity) және жасырылғандар.
  Future<void> _restoreView() async {
    final (sort, scope) = await Prefs.feedView();
    final hidden = await Prefs.hiddenOrders();
    if (!mounted) return;
    setState(() {
      _sort = _FeedSort.values.firstWhere(
        (v) => v.name == sort,
        orElse: () => _FeedSort.best,
      );
      _filter = _FeedFilter.values.firstWhere(
        (v) => v.name == scope,
        orElse: () => _FeedFilter.all,
      );
      _hidden = hidden;
    });
  }

  void _setView({_FeedSort? sort, _FeedFilter? filter}) {
    setState(() {
      _sort = sort ?? _sort;
      _filter = filter ?? _filter;
    });
    Prefs.setFeedView(_sort.name, _filter.name);
  }

  /// Ұзақ басқанда — «Бұл заказ маған қызық емес» (лентадан жасыру).
  Future<void> _hide(Order o) async {
    final ok = await confirmDialog(
      context,
      title: t('Заказды жасыру керек пе?'),
      message: t(
        'Бұл заказ лентаңызда енді көрінбейді. Барлығын қайта '
        'көрсету — лента сүзгісінің астында.',
      ),
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

  Future<void> _manualRefresh() async {
    // Орындаушы қозғалып кеткен болуы мүмкін — «жақын» реті жаңа орынмен.
    Geo.currentPosition().then((p) {
      if (mounted && p != null) setState(() => _pos = p);
    });
    ref.invalidate(executorStatsStreamProvider);
    ref.invalidate(executorFeedStreamProvider);
    ref.invalidate(myExecutorProfileProvider);
    await Future.delayed(const Duration(milliseconds: 600));
  }

  @override
  Widget build(BuildContext context) {
    final statsAsync = ref.watch(executorStatsStreamProvider);
    final feedAsync = ref.watch(executorFeedStreamProvider);
    ref.listen<AsyncValue<List<Order>>>(
      executorFeedStreamProvider,
      (_, next) => _onFeed(next.value),
    );

    return statsAsync.when(
      loading: () => const _FeedSkeleton(),
      error: (e, st) => EmptyState(icon: Icons.wifi_off, title: errText(e)),
      data: (_) {
        // Лента әлі БІРІНШІ рет жүктеліп жатыр — «заказ жоқ» деп
        // алдамаймыз, карточка қаңқасын көрсетеміз.
        if (!feedAsync.hasValue && feedAsync.isLoading) {
          return const _FeedSkeleton();
        }
        if (!feedAsync.hasValue && feedAsync.hasError) {
          return _refreshable([
            const SizedBox(height: 100),
            EmptyState(icon: Icons.wifi_off, title: errText(feedAsync.error!)),
            _refreshButton(),
          ]);
        }

        // Лента БАРЛЫҚ орындаушыға көрінеді (тарифсіз/расталмаған да) —
        // сервер `executor_feed` көлік түрі мен қала фильтрін жасайды
        // (0053). Ұсыныс беру құқығы (тариф/мақұлдау) заказды басқанда
        // `_openOrder` ішінде тексеріледі.
        //
        // РЕТІ: ЖАҢА әрі ЖАҚЫН заказ ең жоғарыда. Әр заказға «ескілік»
        // балы: жарияланғаннан бергі минут + алу нүктесіне дейінгі әр км үшін
        // 3 минут (GPS рұқсаты болса). Яғни 2 км жердегі 1 минуттық заказ
        // (1 + 6 = 7) 10 км жердегі жаңа ғана шыққан заказдан (0 + 30)
        // жоғары тұрады, ал жарты сағат бұрынғы заказ — жақын болса да
        // төмен түседі (оны бәрібір біреу алып қойған болуы мүмкін). GPS жоқ
        // болса — тек жаңалығы бойынша. Бұл — «Ұсынылған» рет; орындаушы
        // сұрыптау мәзірінен «Жақын / Қымбат / Жаңа» ретін таңдай алады.
        final raw = feedAsync.value ?? const <Order>[];
        // Ұзақ басып жасырылған заказдар («маған қызық емес») — лентада да,
        // қойынды сандарында да есептелмейді.
        final all = [
          for (final o in raw)
            if (!_hidden.contains(o.id)) o,
        ];
        final hiddenCount = raw.length - all.length;
        double rankOf(Order o) {
          final ageMin = o.createdAt == null
              ? 9999.0
              : DateTime.now().difference(o.createdAt!).inSeconds / 60.0;
          final km = _pickupKm(_pos, o);
          return ageMin + (km == null ? 0 : km * 3);
        }

        switch (_sort) {
          case _FeedSort.best:
            all.sort((a, b) => rankOf(a).compareTo(rankOf(b)));
          case _FeedSort.near:
            all.sort(
              (a, b) => (_pickupKm(_pos, a) ?? a.distanceKm).compareTo(
                _pickupKm(_pos, b) ?? b.distanceKm,
              ),
            );
          case _FeedSort.price:
            all.sort(
              (a, b) => (b.displayPrice ?? 0).compareTo(a.displayPrice ?? 0),
            );
          case _FeedSort.fresh:
            all.sort(
              (a, b) => (b.createdAt ?? DateTime(2000)).compareTo(
                a.createdAt ?? DateTime(2000),
              ),
            );
        }
        final cityCount = all.where((o) => !o.intercity).length;
        final interCount = all.length - cityCount;
        final eligible = switch (_filter) {
          _FeedFilter.all => all,
          _FeedFilter.city => all.where((o) => !o.intercity).toList(),
          _FeedFilter.intercity => all.where((o) => o.intercity).toList(),
        };

        final ids = {for (final o in eligible) o.id};
        final firstLoad = _known == null;
        final fresh = firstLoad ? ids : ids.difference(_known!);
        _known = ids;

        // Лентаның үстіңгі жолағы: қойындылар (сандарымен) + Тізім/Карта +
        // сұрыптау, астында — «жасырылғандарды қайта көрсету».
        final tabs = _FeedToolbar(
          filter: _filter,
          all: all.length,
          city: cityCount,
          intercity: interCount,
          onFilter: (f) => _setView(filter: f),
          sort: _sort,
          hasGps: _pos != null,
          onSort: (s) => _setView(sort: s),
          mapView: _mapView,
          onMapView: (v) => setState(() => _mapView = v),
          hiddenCount: hiddenCount,
          onUnhide: _unhideAll,
        );

        if (raw.isEmpty) {
          return _refreshable([
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: BonusStrip(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 24, 12, 0),
              child: _FeedEmpty(
                title: t('Әзірге заказ жоқ'),
                subtitle: t('Жаңа заказдар осы жерде автоматты пайда болады.'),
                onRefresh: _manualRefresh,
              ),
            ),
          ]);
        }

        if (eligible.isEmpty) {
          return Column(
            children: [
              tabs,
              Expanded(
                child: _refreshable([
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
                    child: _FeedEmpty(
                      title: t('Бұл бөлімде заказ жоқ'),
                      subtitle: t(
                        'Басқа қойындыны ашыңыз немесе жаңа заказдарды '
                        'күтіңіз.',
                      ),
                      onRefresh: _manualRefresh,
                    ),
                  ),
                ]),
              ),
            ],
          );
        }

        // КАРТА көрінісі — «қай жақта заказ көп» бір қарағанда.
        if (_mapView) {
          return Column(
            children: [
              tabs,
              Expanded(
                child: _FeedMap(
                  orders: eligible,
                  myPos: _pos,
                  onTap: _openOrder,
                ),
              ),
            ],
          );
        }

        final list = RefreshIndicator(
          color: Gz.ink,
          onRefresh: _manualRefresh,
          child: ListView.separated(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            // 0-элемент — бонус жолағы (0059). Бағдарлама өшірулі болса ол
            // `SizedBox.shrink` қайтарады, сол себепті лента баяғы қалпында.
            itemCount: eligible.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (_, i) {
              if (i == 0) return const BonusStrip();
              final o = eligible[i - 1];
              // Кілт — заказ id: жаңа заказ тізімнің басына қосылғанда
              // ТЕК сол карточка жаңадан құрылып, анимацияланады.
              return _Entrance(
                key: ValueKey(o.id),
                id: o.id,
                index: i - 1,
                animate: fresh.contains(o.id) && (!firstLoad || i - 1 < 6),
                played: _introduced,
                child: _NewGlow(
                  active: _glow.contains(o.id),
                  child: _FeedCard(
                    order: o,
                    myPos: _pos,
                    onTap: () => _openOrder(o),
                    onLongPress: () => _hide(o),
                  ),
                ),
              );
            },
          ),
        );
        return Column(
          children: [
            tabs,
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(child: list),
                  Positioned(
                    top: 10,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: _NewOrdersBanner(
                        count: _bannerCount,
                        onTap: _scrollToTop,
                      ),
                    ),
                  ),
                ],
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

  /// Бос/қате күйдегі «Жаңарту» батырмасы — тартып жаңартуды білмейтін
  /// қолданушыға да анық әрекет.
  Widget _refreshButton() => Center(
    child: OutlinedButton.icon(
      onPressed: _manualRefresh,
      icon: const Icon(Icons.refresh_rounded, size: 19),
      label: Text(t('Жаңарту')),
    ),
  );

  /// Заказ карточкасын басқанда — алдымен ұсыныс беру құқығын тексереміз.
  /// Тарифсіз/расталмаған/құжаты жаңартылуы керек орындаушыға заказ беті
  /// ашылмайды, оған не істеу керегі айтылады (тариф сатып алу / күту /
  /// қайта толтыру). Құқығы болса — толық детальдар парағы ашылады.
  void _openOrder(Order o) {
    // Ашылған заказ енді «жаңа» болып жарқырамайды.
    if (_glow.remove(o.id)) setState(() {});
    final gate = _actionGate(o);
    if (gate != null) {
      _showGate(gate);
      return;
    }
    // Орындаушы лента ашылғаннан бері жылжып кеткен болуы мүмкін — парақ
    // ашылғанда орынды тыныш жаңартамыз; жаңа нүкте келсе картадағы
    // орындаушы мен A-ға дейінгі сұр жол сол мезетте жаңарады.
    _posLive.value = _pos;
    Geo.quietPosition().then((p) {
      if (!mounted || p == null) return;
      _posLive.value = p;
      setState(() => _pos = p);
    });
    showGzSheet(
      context,
      builder: (_) => ValueListenableBuilder<Position?>(
        valueListenable: _posLive,
        builder: (_, pos, _) => _OrderSheet(
          order: o,
          myPos: pos,
          myVehicle: ref.read(myExecutorProfileProvider).value?.vehicleType,
          // Клиент бағасы жоқ заказда «Келісу» мүмкін емес — тек өз баға.
          onAgree: o.clientPrice == null
              ? null
              : () => _makeOffer(o, counter: false),
          onCounter: () => _makeOffer(o, counter: true),
        ),
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
          text: t(
            'Заказдарды қарау ашық, ал ұсыныс беру үшін көлігіңіз бен '
            'құжаттарыңызды жіберу керек. Модератор растаған соң заказ '
            'қабылдай бастайсыз.',
          ),
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
          text:
              '${t('Заказ алу үшін тариф сатып алыңыз (1 ауысым,')} '
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
          text: t(
            'Қала ішіндегі заказды тек сол қаладағы орындаушы алады. '
            'Сізге — қалааралық заказдар.',
          ),
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
    final d = await showOfferSheet(
      context,
      order: o,
      counter: counter,
      kmToPickup: _pickupKm(_pos, o),
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

/// Лентаның үстіңгі жолағы — лентадағы ЖАЛҒЫЗ сүзгі: «Барлығы / Қала /
/// Қалааралық» қойындылары (әрқайсысында заказ саны), оның қасында
/// Тізім/Карта ауыстырғышы мен сұрыптау мәзірі. Тізімнің ҮСТІНДЕ бекітулі
/// тұрады (айналдырғанда кетпейді). Жасырылған заказ болса — астында
/// «қайта көрсету» сілтемесі.
class _FeedToolbar extends StatelessWidget {
  final _FeedFilter filter;
  final int all;
  final int city;
  final int intercity;
  final ValueChanged<_FeedFilter> onFilter;
  final _FeedSort sort;
  final bool hasGps;
  final ValueChanged<_FeedSort> onSort;
  final bool mapView;
  final ValueChanged<bool> onMapView;
  final int hiddenCount;
  final VoidCallback onUnhide;

  const _FeedToolbar({
    required this.filter,
    required this.all,
    required this.city,
    required this.intercity,
    required this.onFilter,
    required this.sort,
    required this.hasGps,
    required this.onSort,
    required this.mapView,
    required this.onMapView,
    required this.hiddenCount,
    required this.onUnhide,
  });

  /// Жолақ элементтерінің ортақ биіктігі (қойынды 38 + ішкі шегініс 2×4).
  static const double _h = 46;

  static String _sortLabel(_FeedSort s) => switch (s) {
    _FeedSort.best => t('Ұсынылған'),
    _FeedSort.near => t('Жақын'),
    _FeedSort.price => t('Қымбат'),
    _FeedSort.fresh => t('Жаңа'),
  };

  @override
  Widget build(BuildContext context) {
    Widget tab(_FeedFilter f, String label, int n) {
      final on = filter == f;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onFilter(f),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? Gz.inkFill : Colors.transparent,
              borderRadius: BorderRadius.circular(Gz.rSm),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  '$label · $n',
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: on ? Colors.white : Gz.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final tabs = Container(
      height: _h,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Gz.surface,
        borderRadius: BorderRadius.circular(Gz.rMd),
        border: Border.all(color: Gz.border),
      ),
      child: Row(
        children: [
          tab(_FeedFilter.all, t('Барлығы'), all),
          tab(_FeedFilter.city, t('Қала'), city),
          tab(_FeedFilter.intercity, t('Қалааралық'), intercity),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: tabs),
              const SizedBox(width: 6),
              // Тізім ⇄ Карта. Иконка — АУЫСАТЫН көрініс; карта ашық
              // кезде батырма қараяды (қай режимде тұрғаны көрінеді).
              _ToolButton(
                icon: mapView ? Icons.view_agenda_outlined : Icons.map_outlined,
                tooltip: mapView ? t('Тізім') : t('Карта'),
                active: mapView,
                size: _h,
                onTap: () => onMapView(!mapView),
              ),
              const SizedBox(width: 6),
              // Жаңа заказ ДЫБЫСЫ: өшірулі болса батырма қараяды. Қосқанда
              // дыбыс бір рет үлгі ретінде ойнайды.
              ValueListenableBuilder<bool>(
                valueListenable: OrderAlert.soundOn,
                builder: (_, on, _) => _ToolButton(
                  icon: on ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                  tooltip: t('Жаңа заказ дыбысы'),
                  active: !on,
                  size: _h,
                  onTap: () => OrderAlert.setSound(!on),
                ),
              ),
              const SizedBox(width: 6),
              // Сұрыптау: әдепкі «Ұсынылған» емес рет таңдалса — батырма
              // қараяды (лента басқа ретпен тұрғаны бірден көрінеді).
              PopupMenuButton<_FeedSort>(
                tooltip: '${t('Сұрыптау')}: ${_sortLabel(sort)}',
                initialValue: sort,
                onSelected: onSort,
                position: PopupMenuPosition.under,
                itemBuilder: (_) => [
                  for (final s in _FeedSort.values)
                    if (s != _FeedSort.near || hasGps)
                      PopupMenuItem(
                        value: s,
                        child: Row(
                          children: [
                            SizedBox(
                              width: 22,
                              child: s == sort
                                  ? Icon(
                                      Icons.check_rounded,
                                      size: 18,
                                      color: Gz.green,
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 6),
                            Text(_sortLabel(s)),
                          ],
                        ),
                      ),
                ],
                child: _ToolButton(
                  icon: Icons.swap_vert_rounded,
                  active: sort != _FeedSort.best,
                  size: _h,
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
                label: Text(
                  '${t('Жасырылған заказдар')}: $hiddenCount · '
                  '${t('көрсету')}',
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Жолақтағы шаршы батырма (қойындылармен бірдей биіктікте).
/// [onTap] null болса — тек көрініс (мыс. [PopupMenuButton]-ның ішінде,
/// басуды мәзір өзі ұстайды).
class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String? tooltip;
  final bool active;
  final double size;
  final VoidCallback? onTap;
  const _ToolButton({
    required this.icon,
    required this.size,
    this.tooltip,
    this.active = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(Gz.rMd);
    Widget box = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active ? Gz.inkFill : Gz.surface,
        borderRadius: radius,
        border: Border.all(color: active ? Gz.inkFill : Gz.border),
      ),
      child: Icon(icon, size: 20, color: active ? Gz.yellow : Gz.ink),
    );
    final tap = onTap;
    if (tap != null) {
      box = Material(
        type: MaterialType.transparency,
        child: InkWell(borderRadius: radius, onTap: tap, child: box),
      );
    }
    final tip = tooltip;
    return tip == null ? box : Tooltip(message: tip, child: box);
  }
}

/// Бос күй — бір блокта: иллюстрация (сары дөңгелектегі радар), түсінікті
/// мәтін және «Жаңарту» батырмасы. Заказ карточкаларымен бірдей ақ
/// карточка — екі күй бір-біріне үйлеседі.
class _FeedEmpty extends StatelessWidget {
  final String title;
  final String subtitle;
  final Future<void> Function() onRefresh;
  const _FeedEmpty({
    required this.title,
    required this.subtitle,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 20),
      decoration: BoxDecoration(
        color: Gz.surface,
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(color: Gz.border),
        boxShadow: Gz.cardShadow,
      ),
      child: Column(
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: Gz.tint(Gz.yellow, 0.22),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.radar_rounded, size: 38, color: Gz.ink),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Gz.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.4,
              color: Gz.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded, size: 19),
              label: Text(t('Жаңарту')),
            ),
          ),
        ],
      ),
    );
  }
}

/// Карточканың лентаға «қалқып кіруі» (fade + сәл жоғары жылжу).
///
/// Әр заказ үшін БІР-АҚ рет ойналады ([played] жиыны): тізімді айналдырып
/// қайта оралғанда немесе стрим жаңарғанда карточкалар қайта секірмейді.
/// Алғашқы жүктелуде алғашқы бірнеше карточка сатылап (stagger) кіреді.
/// Жаңа ғана келген заказдың карточкасы — брендтік сары жиек пен жұмсақ
/// жарқыл. Бір минуттан кейін не заказды ашқанда біртіндеп сөнеді. «ЖАҢА»
/// жазуы карточканың өзінде ([_Freshness]) — мұнда қайталанбайды.
class _NewGlow extends StatelessWidget {
  final bool active;
  final Widget child;
  const _NewGlow({required this.active, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_cardRadius),
        boxShadow: active ? Gz.glow(Gz.yellow, alpha: 0.5, blur: 16) : null,
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(
          color: active ? Gz.yellow : Colors.transparent,
          width: 2,
        ),
      ),
      child: child,
    );
  }
}

/// Тізім төмен айналдырылып тұрғанда жоғарыда шығатын «Жаңа заказ шықты»
/// жолағы — түртсе, тізім басына оралады. [count] = 0 болса жасырын.
class _NewOrdersBanner extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  const _NewOrdersBanner({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final show = count > 0;
    return IgnorePointer(
      ignoring: !show,
      child: AnimatedSlide(
        offset: show ? Offset.zero : const Offset(0, -1.6),
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutBack,
        child: AnimatedOpacity(
          opacity: show ? 1 : 0,
          duration: const Duration(milliseconds: 220),
          child: Material(
            color: Gz.inkDeep,
            shape: const StadiumBorder(),
            elevation: 6,
            shadowColor: Gz.shadowWide,
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.arrow_upward_rounded,
                      size: 17,
                      color: Gz.yellow,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      count <= 1
                          ? t('Жаңа заказ шықты')
                          : '${t('Жаңа заказдар')}: $count',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Entrance extends StatefulWidget {
  final String id;
  final int index;

  /// false — карточка бірден толық көрінеді (ескі заказ, айналдырып жеткен).
  final bool animate;
  final Set<String> played;
  final Widget child;

  const _Entrance({
    super.key,
    required this.id,
    required this.index,
    required this.animate,
    required this.played,
    required this.child,
  });

  @override
  State<_Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<_Entrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    final play = widget.played.add(widget.id) && widget.animate;
    // Сатылау: әр келесі карточка 50 мс кешігеді (ең көбі 5 карточка).
    final delayMs = play ? (widget.index.clamp(0, 5) * 50) : 0;
    const runMs = 340;
    final total = delayMs + runMs;
    _c = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: total),
      value: play ? 0 : 1,
    );
    final curve = CurvedAnimation(
      parent: _c,
      curve: Interval(delayMs / total, 1, curve: Curves.easeOutCubic),
    );
    _fade = curve;
    _slide = Tween(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(curve);
    if (play) _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _fade,
    child: SlideTransition(position: _slide, child: widget.child),
  );
}

/// Лентадағы заказ карточкасы — орындаушы бір қарағанда шешім қабылдай
/// алатындай: көлік + жаңалығы, ІРІ баға, маршрут (A ⋮ B), негізгі
/// көрсеткіштер (чиптер), жүк, клиент және «Ұсыныс беру» әрекеті.
/// Карта мен баға батырмалары ЖОҚ — олар басқанда парақта ашылады.
class _FeedCard extends StatelessWidget {
  final Order order;
  final VoidCallback onTap;

  /// Орындаушының ағымдағы орны — «алу нүктесі МЕНЕН қанша алыс?» деген
  /// сұраққа жауап беру үшін. GPS рұқсаты жоқ болса null (тег көрінбейді).
  final Position? myPos;

  /// Ұзақ басу — заказды лентадан жасыру («маған қызық емес»).
  final VoidCallback? onLongPress;

  const _FeedCard({
    required this.order,
    required this.onTap,
    this.myPos,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final o = order;
    final toPickup = _pickupKm(myPos, o);
    final isTaxi = o.vehicleType.isPassenger;
    // Баға клиенттікі ме — орындаушы «келісемін» десе дәл осы сома.
    final isClientPrice =
        o.clientPrice != null && o.displayPrice == o.clientPrice;

    final chips = <Widget>[
      // «Алу нүктесі МЕНЕН қанша алыс?» — орындаушы заказды алар алдында
      // алдымен осыны сұрайды (бекер жол жүрмеу үшін). 5 км-ге дейін
      // ЖАСЫЛ: «жақын, тиімді» деген белгі.
      if (toPickup != null)
        _Pill(
          icon: Icons.near_me_rounded,
          text: '${t('Сізден')} ${_km(toPickup)}',
          color: toPickup <= 5 ? Gz.green : null,
        ),
      if (o.distanceKm > 0)
        _Pill(icon: Icons.route_rounded, text: _km(o.distanceKm)),
      if (o.distanceKm > 0)
        _Pill(icon: Icons.timer_outlined, text: _duration(_tripMinutes(o))),
      if (o.fromCity != null && o.toCity != null)
        _Pill(
          icon: o.intercity ? Icons.alt_route : Icons.location_city_outlined,
          text: o.intercity ? t('Межгород') : t('Қала ішінде'),
          color: o.intercity ? Gz.violet : null,
        ),
      if (o.scheduledAt != null)
        _Pill(
          icon: Icons.event_rounded,
          text: _when(o.scheduledAt!),
          color: Gz.blue,
        ),
      // Қосымша талаптар (0077): тиеуші, қабат, лифт.
      if (o.loaders > 0)
        _Pill(
          icon: Icons.groups_rounded,
          text: '${o.loaders} ${t('тиеуші')}',
          color: Gz.violet,
        ),
      if (o.floorFrom != null || o.floorTo != null)
        _Pill(
          icon: Icons.stairs_rounded,
          text:
              '${o.floorFrom ?? '—'} → ${o.floorTo ?? '—'} ${t('қабат')}'
              '${o.hasElevator == true ? ' · ${t('лифт')}' : ''}',
        ),
      if (o.photos.isNotEmpty)
        _Pill(icon: Icons.photo_camera_outlined, text: '${o.photos.length}'),
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Gz.surface,
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(color: Gz.border),
        // Лентадағы карточкалар фоннан «көтеріліп» тұрады — тізім
        // жалғасқан жалпақ жолақ емес, бөлек-бөлек карта болып оқылады.
        boxShadow: Gz.cardShadow,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(_cardRadius),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ---- 1) Көлік + жаңалығы | БАҒА ----
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _VehicleBadge(type: o.vehicleType),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            o.vehicleType.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              height: 1.25,
                              letterSpacing: -0.1,
                              // Ұмай заказы — атауы қызғылт: жеке чипсіз де
                              // бірден көзге түседі (атау қайталанбайды).
                              color: o.vehicleType.isUmay ? kUmayPink : Gz.ink,
                            ),
                          ),
                          const SizedBox(height: 3),
                          _Freshness(createdAt: o.createdAt),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Баға — орындаушы лентаны ЕҢ АЛДЫМЕН сол сан бойынша
                    // шолады, сол себепті ең ірі әрі салмақты элемент.
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 160),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          BtnLabel(
                            fmtT(o.displayPrice),
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              height: 1.1,
                              letterSpacing: -0.8,
                              color: Gz.ink,
                            ),
                          ),
                          if (isClientPrice) ...[
                            const SizedBox(height: 2),
                            BtnLabel(
                              t('Клиент бағасы'),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Gz.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // ---- 2) МАРШРУТ: A ⋮ (+N аялдама) ⋮ B ----
                _CompactRoute(
                  from: o.fromDisplay,
                  to: o.toDisplay,
                  stops: o.stops.length,
                ),
                // ---- 3) Көрсеткіштер ----
                if (chips.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(spacing: 6, runSpacing: 6, children: chips),
                ],
                // ---- 4) Жүк (такси — жолаушы саны) ----
                if (o.cargoDesc.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(
                        isTaxi
                            ? Icons.person_outline_rounded
                            : Icons.inventory_2_outlined,
                        size: 15,
                        color: Gz.textSecondary,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          o.cargoDesc,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.3,
                            color: Gz.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 11),
                  child: Divider(height: 1, thickness: 1, color: Gz.border),
                ),
                // ---- 5) Клиент | әрекет ----
                Row(
                  children: [
                    Expanded(child: _ClientMini(clientId: o.clientId)),
                    const SizedBox(width: 10),
                    // Батырма тек КӨРІНІС: басу бүкіл карточканың InkWell-іне
                    // түседі (бір әрекет — бір басу орны, шатастырмайды).
                    const _CardCta(),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Көлік түрінің иконкасы — жұмсақ сары шаршы ішінде.
class _VehicleBadge extends StatelessWidget {
  final VehicleType type;
  const _VehicleBadge({required this.type});

  @override
  Widget build(BuildContext context) => Container(
    width: 40,
    height: 40,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: Gz.tint(Gz.yellow, 0.16),
      borderRadius: BorderRadius.circular(12),
    ),
    child: vehicleIcon(type, size: 26, color: Gz.ink),
  );
}

/// Карточканың төменгі оң жағындағы «Ұсыныс беру →» белгісі.
class _CardCta extends StatelessWidget {
  const _CardCta();

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 160),
    child: Container(
      height: 38,
      padding: const EdgeInsets.fromLTRB(14, 0, 10, 0),
      decoration: BoxDecoration(
        gradient: Gz.brandGradient,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: BtnLabel(
              t('Қабылдау'),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Gz.onBrand,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.arrow_forward_rounded, size: 17, color: Gz.ink),
        ],
      ),
    ),
  );
}

/// Ықшам көрсеткіш чипі (иконка + қысқа мәтін).
class _Pill extends StatelessWidget {
  final IconData icon;
  final String text;

  /// Ерекшелегіміз келсе — чиптің өз түсі (мыс. «жақын» = жасыл).
  final Color? color;

  const _Pill({required this.icon, required this.text, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
      decoration: BoxDecoration(
        color: c == null ? Gz.surfaceAlt : Gz.tint(c, 0.10),
        borderRadius: BorderRadius.circular(Gz.rXs),
        border: Border.all(color: c == null ? Gz.border : Gz.tint(c, 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: c ?? Gz.textSecondary),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                height: 1.2,
                color: c ?? Gz.ink,
                letterSpacing: -0.05,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Заказдың жаңалығы: минуттан жас болса — жыпылықтаған «ЖАҢА» белгісі,
/// әйтпесе «5 мин бұрын». Өзі ғана жаңарады (20 с сайын) — бүкіл лента
/// қайта құрылмайды.
class _Freshness extends StatefulWidget {
  final DateTime? createdAt;
  const _Freshness({required this.createdAt});

  @override
  State<_Freshness> createState() => _FreshnessState();
}

class _FreshnessState extends State<_Freshness>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  Timer? _tick;

  bool get _isNew {
    final d = widget.createdAt;
    return d != null && DateTime.now().difference(d) < _freshWindow;
  }

  @override
  void initState() {
    super.initState();
    _syncPulse();
    _tick = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted) return;
      setState(_syncPulse);
    });
  }

  @override
  void didUpdateWidget(covariant _Freshness old) {
    super.didUpdateWidget(old);
    if (old.createdAt != widget.createdAt) _syncPulse();
  }

  /// Жаңа заказда ғана анимация жүреді; ескіргенде тоқтайды (батарея).
  void _syncPulse() {
    if (_isNew) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else if (_pulse.isAnimating) {
      _pulse.stop();
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.createdAt;
    if (d == null) return const SizedBox.shrink();
    if (!_isNew) {
      return Row(
        children: [
          Icon(Icons.schedule_rounded, size: 13, color: Gz.textTertiary),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              _ago(d),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                height: 1.2,
                fontWeight: FontWeight.w600,
                color: Gz.textSecondary,
              ),
            ),
          ),
        ],
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.fromLTRB(7, 3, 8, 3),
        decoration: BoxDecoration(
          color: Gz.tint(Gz.green, 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            RepaintBoundary(
              child: FadeTransition(
                opacity: Tween(begin: 0.35, end: 1.0).animate(_pulse),
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: Gz.green,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 5),
            Text(
              t('ЖАҢА'),
              style: TextStyle(
                fontSize: 11,
                height: 1.2,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.6,
                color: Gz.green,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Клиенттің шағын жолы (аватар + аты + рейтинг) — карточкаға сыятын ықшам.
///
/// Профиль сұрауы `initState`-те БІР рет жасалады: карточка қайта
/// құрылған сайын серверге қайта бармайды.
class _ClientMini extends StatefulWidget {
  final String clientId;
  const _ClientMini({required this.clientId});

  @override
  State<_ClientMini> createState() => _ClientMiniState();
}

class _ClientMiniState extends State<_ClientMini> {
  late Future<Profile?> _future = Repo.profileOf(widget.clientId);

  @override
  void didUpdateWidget(covariant _ClientMini old) {
    super.didUpdateWidget(old);
    if (old.clientId != widget.clientId) {
      _future = Repo.profileOf(widget.clientId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Profile?>(
      future: _future,
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
                      fontSize: 13,
                      height: 1.25,
                    ),
                  ),
                  // Лентада ОРЫНДАУШЫ клиентті көреді → клиенттік рейтинг
                  // (адам қазір орындаушы режиміне ауысып кеткен болса да).
                  // Тар жерде (360 px, ірі қаріп) жұлдыздар қатары сыймаса —
                  // сәл кішірейеді, RenderFlex асып кетпейді.
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: RatingStars(
                      p?.ratingAs('client') ?? 0,
                      count: p?.ratingCountAs('client') ?? 0,
                      size: 11,
                    ),
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

/// Маршруттың ықшам көрінісі: жасыл сақина (алу) ⋮ қара шаршы (жеткізу).
/// Аралығындағы үзік сызық — «маршрут» екені бірден көрінеді; аялдамалар
/// болса, сызықтың қасында «+N аялдама» жазылады.
class _CompactRoute extends StatelessWidget {
  final String from;
  final String to;
  final int stops;
  const _CompactRoute({required this.from, required this.to, this.stops = 0});

  static const double _rail = 16;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _point(const _RouteDot.pickup(), from),
        SizedBox(
          height: stops > 0 ? 24 : 14,
          child: Row(
            children: [
              const SizedBox(
                width: _rail,
                height: double.infinity,
                child: RepaintBoundary(
                  child: CustomPaint(painter: _DashPainter()),
                ),
              ),
              if (stops > 0) ...[
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Gz.tint(Gz.violet, 0.10),
                    borderRadius: BorderRadius.circular(Gz.rXs),
                  ),
                  child: Text(
                    '+$stops ${t('аялдама')}',
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.2,
                      fontWeight: FontWeight.w800,
                      color: Gz.violet,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        _point(const _RouteDot.dropoff(), to),
      ],
    );
  }

  Widget _point(Widget dot, String text) => Row(
    children: [
      SizedBox(
        width: _rail,
        child: Center(child: dot),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            height: 1.3,
            letterSpacing: -0.15,
            color: Gz.ink,
          ),
        ),
      ),
    ],
  );
}

/// Маршрут нүктесі: алу — жасыл сақина, жеткізу — қара шаршы.
class _RouteDot extends StatelessWidget {
  final bool pickup;
  const _RouteDot.pickup() : pickup = true;
  const _RouteDot.dropoff() : pickup = false;

  @override
  Widget build(BuildContext context) => pickup
      ? Container(
          width: 13,
          height: 13,
          decoration: BoxDecoration(
            color: Gz.surface,
            shape: BoxShape.circle,
            border: Border.all(color: Gz.green, width: 3.6),
          ),
        )
      : Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: Gz.ink,
            borderRadius: BorderRadius.circular(4),
          ),
        );
}

/// Тік үзік сызық (маршрут нүктелерін жалғайды).
class _DashPainter extends CustomPainter {
  const _DashPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Gz.textTertiary
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final x = size.width / 2;
    const dash = 3.0, gap = 3.5;
    var y = 2.0;
    while (y < size.height - 2) {
      final end = (y + dash).clamp(0.0, size.height - 2);
      canvas.drawLine(Offset(x, y), Offset(x, end), paint);
      y += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashPainter oldDelegate) => false;
}

/// Лента жүктеліп жатқанда — карточка «қаңқалары» (жұмсақ жыпылықтаумен).
/// Бос айналатын spinner-ден гөрі тыныш әрі «қазір пайда болады» деп оқылады.
class _FeedSkeleton extends StatefulWidget {
  const _FeedSkeleton();

  @override
  State<_FeedSkeleton> createState() => _FeedSkeletonState();
}

class _FeedSkeletonState extends State<_FeedSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget bar(double w, double h, {double r = 8}) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: Gz.disabledBg,
        borderRadius: BorderRadius.circular(r),
      ),
    );

    final card = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Gz.surface,
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(color: Gz.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              bar(40, 40, r: 12),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    bar(90, 12),
                    const SizedBox(height: 7),
                    bar(60, 10),
                  ],
                ),
              ),
              bar(84, 22),
            ],
          ),
          const SizedBox(height: 16),
          bar(220, 12),
          const SizedBox(height: 14),
          bar(180, 12),
          const SizedBox(height: 14),
          Row(
            children: [
              bar(64, 22, r: 8),
              const SizedBox(width: 6),
              bar(56, 22, r: 8),
              const SizedBox(width: 6),
              bar(72, 22, r: 8),
            ],
          ),
        ],
      ),
    );

    return FadeTransition(
      opacity: Tween(begin: 0.55, end: 1.0).animate(_c),
      child: ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        itemCount: 3,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, _) => card,
      ),
    );
  }
}

/// Заказ детальдары парағы.
///
/// Реті орындаушының сұрақтарына сай: «қайдан → қайда?» (бағыт жолағы) →
/// карта → маршрут қадамдары → негізгі деректер торы → жүк/түсініктеме/
/// фото → клиент. Баға мен батырмалар төменде БЕКІТІЛГЕН: парақты қанша
/// айналдырса да, шешім қабылдау әрекеті көз алдында тұрады.
class _OrderSheet extends StatelessWidget {
  final Order order;

  /// null — клиент бағасы жоқ (тек «Өз бағам» ұсынылады).
  final VoidCallback? onAgree;
  final VoidCallback onCounter;

  /// Орындаушының ағымдағы орны — алу нүктесіне дейінгі қашықтықты
  /// көрсету үшін (GPS рұқсаты жоқ болса null). Картада орындаушы мен
  /// одан A-ға дейінгі СҰР жол да осыдан салынады.
  final Position? myPos;

  /// Орындаушының өз көлік түрі — картадағы белгісі үшін.
  final VehicleType? myVehicle;

  const _OrderSheet({
    required this.order,
    required this.onAgree,
    required this.onCounter,
    this.myPos,
    this.myVehicle,
  });

  @override
  Widget build(BuildContext context) {
    final o = order;
    final isTaxi = o.vehicleType.isPassenger;
    final me = myPos;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.86,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      // Парақтың фоны — сұр (Gz.bg): ақ блоктар одан бөлек оқылады.
      builder: (context, scroll) => ColoredBox(
        color: Gz.bg,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
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
                  // ---- 1) БАҒЫТ: «қайдан → қайда» БІР ҚАРАҒАНДА ----
                  _DirectionStrip(order: o),
                  const SizedBox(height: 10),
                  // ---- 2) КАРТА: түртсе толық экранда ашылады ----
                  ClipRRect(
                    borderRadius: BorderRadius.circular(Gz.rLg),
                    child: RouteMap(
                      from: LatLng(o.fromLat, o.fromLng),
                      to: LatLng(o.toLat, o.toLng),
                      stops: o.stops.map((s) => LatLng(s.lat, s.lng)).toList(),
                      height: 190,
                      fromLabel: o.fromDisplay,
                      toLabel: o.toDisplay,
                      stopLabels: o.stops.map((s) => s.display).toList(),
                      distanceKm: o.distanceKm > 0 ? o.distanceKm : null,
                      approachFrom: me == null
                          ? null
                          : LatLng(me.latitude, me.longitude),
                      approachVehicle: myVehicle,
                      approachHeading: me == null || me.heading < 0
                          ? null
                          : me.heading,
                    ),
                  ),
                  const SizedBox(height: 10),
                  // ---- 3) МАРШРУТ ҚАДАМДАРЫ (толық мекенжайлар) ----
                  _SheetSection(
                    icon: Icons.route_rounded,
                    title: t('Маршрут'),
                    child: RouteLine(
                      from: o.fromDisplay,
                      to: o.toDisplay,
                      stops: o.stops.map((s) => s.display).toList(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // ---- 4) НЕГІЗГІ ДЕРЕКТЕР ТОРЫ ----
                  _FactsGrid(order: o, myPos: myPos),
                  // ---- 5) ЖҮК + ФОТО ----
                  if (o.cargoDesc.isNotEmpty || o.photos.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _SheetSection(
                      icon: isTaxi
                          ? Icons.person_outline_rounded
                          : Icons.inventory_2_outlined,
                      title: isTaxi ? t('Жолаушылар') : t('Жүк'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (o.cargoDesc.isNotEmpty)
                            Text(
                              o.cargoDesc,
                              style: TextStyle(
                                fontSize: 15,
                                height: 1.45,
                                fontWeight: FontWeight.w600,
                                color: Gz.ink,
                              ),
                            ),
                          if (o.cargoDesc.isNotEmpty && o.photos.isNotEmpty)
                            const SizedBox(height: 12),
                          if (o.photos.isNotEmpty)
                            OrderPhotosStrip(paths: o.photos),
                        ],
                      ),
                    ),
                  ],
                  // ---- 6) ТҮСІНІКТЕМЕ ----
                  if (o.comment.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _SheetSection(
                      icon: Icons.chat_bubble_outline_rounded,
                      title: t('Түсініктеме'),
                      child: Text(
                        o.comment,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.45,
                          color: Gz.ink,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  // ---- 7) КЛИЕНТ ----
                  _SheetClient(clientId: o.clientId),
                ],
              ),
            ),
            // ---- 8) БАҒА + ӘРЕКЕТ (бекітілген) ----
            _SheetActions(order: o, onAgree: onAgree, onCounter: onCounter),
          ],
        ),
      ),
    );
  }
}

/// Парақтағы атаулы блок: иконка + БАС ӘРІППЕН микро-тақырып + мазмұн.
class _SheetSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;
  const _SheetSection({
    required this.icon,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
    decoration: BoxDecoration(
      color: Gz.surface,
      borderRadius: BorderRadius.circular(Gz.rLg),
      border: Border.all(color: Gz.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 15, color: Gz.textSecondary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                title.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Gz.label,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        child,
      ],
    ),
  );
}

/// Негізгі деректер торы (2 баған): көлік, қашықтық, бағыт, алу нүктесіне
/// дейінгі жол, жарияланған және (бар болса) белгіленген уақыт.
class _FactsGrid extends StatelessWidget {
  final Order order;
  final Position? myPos;
  const _FactsGrid({required this.order, this.myPos});

  @override
  Widget build(BuildContext context) {
    final o = order;
    final toPickup = _pickupKm(myPos, o);
    final created = o.createdAt;
    final ago = created == null ? '' : _ago(created);

    final tiles = <Widget>[
      _FactTile(
        lead: vehicleIcon(o.vehicleType, size: 20, color: Gz.ink),
        color: Gz.yellowDark,
        label: t('Көлік'),
        value: o.vehicleType.label,
      ),
      if (o.distanceKm > 0)
        _FactTile(
          lead: Icon(Icons.route_rounded, size: 18, color: Gz.blue),
          color: Gz.blue,
          label: t('Қашықтық'),
          value: _km(o.distanceKm),
        ),
      _FactTile(
        lead: Icon(
          o.intercity ? Icons.alt_route : Icons.location_city_outlined,
          size: 18,
          color: o.intercity ? Gz.violet : Gz.blue,
        ),
        color: o.intercity ? Gz.violet : Gz.blue,
        label: t('Бағыты'),
        value: o.intercity ? t('Қалааралық') : t('Қала ішінде'),
      ),
      // Алу нүктесіне дейінгі жол — «бекер бармаймын ба?» деген сұрақтың
      // жауабы. Ол маршрут ұзындығынан БӨЛЕК: заказ қысқа болса да, алуға
      // 30 км жүру керек болуы мүмкін.
      if (toPickup != null)
        _FactTile(
          lead: Icon(
            Icons.near_me_rounded,
            size: 18,
            color: toPickup <= 5 ? Gz.green : Gz.textSecondary,
          ),
          color: toPickup <= 5 ? Gz.green : Gz.textSecondary,
          label: t('Сізден'),
          value: _km(toPickup),
        ),
      if (created != null)
        _FactTile(
          lead: Icon(Icons.schedule_rounded, size: 18, color: Gz.textSecondary),
          color: Gz.textSecondary,
          label: t('Жарияланды'),
          value: ago.isEmpty
              ? '${_when(created)} · ${t('ЖАҢА')}'
              : '${_when(created)} · $ago',
        ),
      if (o.scheduledAt != null)
        _FactTile(
          lead: Icon(Icons.event_rounded, size: 18, color: Gz.blue),
          color: Gz.blue,
          label: t('Алдын ала'),
          value: _when(o.scheduledAt!),
        ),
    ];

    return LayoutBuilder(
      builder: (context, c) {
        const gap = 8.0;
        final w = (c.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final tile in tiles) SizedBox(width: w, child: tile)],
        );
      },
    );
  }
}

/// Тордың бір ұяшығы: түсті дөңгелектегі иконка + атау + мәні.
class _FactTile extends StatelessWidget {
  final Widget lead;
  final Color color;
  final String label;
  final String value;
  const _FactTile({
    required this.lead,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
    decoration: BoxDecoration(
      color: Gz.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Gz.border),
    ),
    child: Row(
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Gz.tint(color, 0.12),
            shape: BoxShape.circle,
          ),
          child: lead,
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Gz.label.copyWith(fontSize: 10, letterSpacing: 0.5),
              ),
              const SizedBox(height: 3),
              BtnLabel(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                  letterSpacing: -0.2,
                  color: Gz.ink,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Парақтың төменгі БЕКІТІЛГЕН бөлігі: ірі баға + «Келісу / Өз бағам».
class _SheetActions extends StatelessWidget {
  final Order order;
  final VoidCallback? onAgree;
  final VoidCallback onCounter;
  const _SheetActions({
    required this.order,
    required this.onAgree,
    required this.onCounter,
  });

  @override
  Widget build(BuildContext context) {
    final o = order;
    final isClientPrice =
        o.clientPrice != null && o.displayPrice == o.clientPrice;
    // Келісу сомасы жоғарыдағы бағадан ӨЗГЕ болса ғана батырмада жазылады
    // (бірдей болса — бір санды екі рет көрсетпейміз).
    final agreeLabel = isClientPrice || o.clientPrice == null
        ? t('Келісу')
        : '${t('Келісу')} · ${fmtT(o.clientPrice)}';
    final agree = onAgree;

    final counter = OutlinedButton(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(50),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        side: BorderSide(color: Gz.ink, width: 1.6),
      ),
      onPressed: () {
        Navigator.of(context).pop();
        onCounter();
      },
      child: BtnLabel(t('Өз бағам')),
    );

    return Container(
      decoration: BoxDecoration(
        color: Gz.surface,
        border: Border(top: BorderSide(color: Gz.border)),
        boxShadow: [
          BoxShadow(
            color: Gz.shadowSoft,
            blurRadius: 18,
            offset: Offset(0, -6),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isClientPrice) ...[
            Text(t('Клиент бағасы').toUpperCase(), style: Gz.label),
            const SizedBox(height: 2),
          ],
          BtnLabel(
            fmtT(o.displayPrice),
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              height: 1.1,
              letterSpacing: -1,
              color: Gz.ink,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (agree != null) ...[
                Expanded(
                  flex: 3,
                  child: BusyButton(
                    label: agreeLabel,
                    icon: Icons.check_rounded,
                    onPressed: () async {
                      Navigator.of(context).pop();
                      agree();
                    },
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(flex: 2, child: counter),
            ],
          ),
        ],
      ),
    );
  }
}

/// «ҚАЙДАН → ҚАЙДА» жолағы — орындаушының шешім қабылдауына керек
/// маңызды ақпарат (баға — төменгі бекітілген бөлікте).
///
/// Мекенжайдың толық жолын («Абая 15, 3-подъезд») оқу уақыт алады, ал
/// орындаушыға алдымен МАСШТАБ керек: қала ішінде ме, әлде басқа қалаға
/// ма. Сол себепті мұнда тек қала атаулары ірі әрі қою жазылады, түсі
/// бағыт түрін білдіреді (күлгін — қалааралық, көк — қала ішінде).
/// Толық мекенжайлар, қашықтық пен бағыт атауы төмендегі блоктарда.
class _DirectionStrip extends StatelessWidget {
  final Order order;
  const _DirectionStrip({required this.order});

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
    final cityStyle = TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w900,
      height: 1.15,
      letterSpacing: -0.4,
      color: Gz.ink,
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Gz.tint(accent, 0.12), Gz.surface],
        ),
        borderRadius: BorderRadius.circular(Gz.rLg),
        border: Border.all(color: Gz.tint(accent, 0.24)),
      ),
      // Қала атаулары ұзын болуы мүмкін («Петропавл» / «Усть-Каменогорск»)
      // — екеуі де Flexible + BtnLabel, сол себепті ЕШҚАШАН екінші жолға
      // түспейді де, қиылмайды: сыймаса сәл кішірейеді.
      child: Row(
        children: [
          const _RouteDot.pickup(),
          const SizedBox(width: 9),
          Flexible(child: BtnLabel(from, style: cityStyle)),
          const SizedBox(width: 9),
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Gz.tint(accent, 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.arrow_forward_rounded, size: 16, color: accent),
          ),
          const SizedBox(width: 9),
          Flexible(child: BtnLabel(to, style: cityStyle)),
          const SizedBox(width: 9),
          const _RouteDot.dropoff(),
        ],
      ),
    );
  }
}

class _SheetClient extends StatefulWidget {
  final String clientId;
  const _SheetClient({required this.clientId});

  @override
  State<_SheetClient> createState() => _SheetClientState();
}

class _SheetClientState extends State<_SheetClient> {
  late final Future<Profile?> _future = Repo.profileOf(widget.clientId);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Profile?>(
      future: _future,
      builder: (context, snap) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Gz.surface,
          borderRadius: BorderRadius.circular(Gz.rLg),
          border: Border.all(color: Gz.border),
        ),
        child: ProfileBrief(
          profile: snap.data,
          subtitle: t('Клиент'),
          asRole: 'client',
        ),
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
    final p = myPos;
    final me = p == null ? null : LatLng(p.latitude, p.longitude);
    final points = [for (final o in orders) LatLng(o.fromLat, o.fromLng), ?me];
    final single = points.length < 2;
    return FlutterMap(
      options: gzMapOptions(
        initialCenter: points.isEmpty ? Geo.almaty : points.first,
        initialZoom: 13,
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
            // «Мен осындамын» — қосымшадағы барлық карталардағыдай нүкте.
            if (me != null) myLocationMarker(me),
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
            color: Gz.inkFill,
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
        CustomPaint(size: const Size(10, 6), painter: _PinTailPainter()),
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
    canvas.drawPath(path, Paint()..color = Gz.inkFill);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
