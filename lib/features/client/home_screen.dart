import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/geo.dart';
import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/prefs.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/app_drawer.dart';
import '../../shared/drawer_hint.dart';
import '../../shared/map_widgets.dart';
import '../../shared/transitions.dart';
import '../../shared/vehicle_picker.dart';
import '../../shared/widgets.dart';
import 'address_picker.dart';
import 'city_street_sheet.dart';
import 'create_order_screen.dart';
import 'my_orders_screen.dart';
import 'order_detail_screen.dart';
import 'stops_sheet.dart';

class ClientHomeScreen extends ConsumerStatefulWidget {
  /// Гест режимі (кірмеген қолданушы): картамен заказды толық толтыра алады,
  /// бірақ «Шақыру» мен профиль батырмасы кіру экранына бағыттайды.
  final bool isGuest;
  const ClientHomeScreen({super.key, this.isGuest = false});

  @override
  ConsumerState<ClientHomeScreen> createState() => _ClientHomeScreenState();
}

class _ClientHomeScreenState extends ConsumerState<ClientHomeScreen> {
  /// Негізгі панельдің (тек соның — локация батырмасы мен банер кірмейді,
  /// олар картаның үстінде қалқып тұрады) НАҚТЫ өлшенген биіктігі — карта
  /// мен пинді сол мөлшерге сай жоғары ысырамыз. Қатаң санмен емес, әр
  /// кадрда `_blockKey` арқылы өлшенеді, сол себепті шрифт үлкейтілген
  /// құрылғыларда да, панель бүктелгенде де пин панельдің астында қалып
  /// қоймайды.
  final _blockKey = GlobalKey();
  double _bottomInset = 140;

  /// Логотип батырмасы sidebar-ды осы кілт арқылы ашады (Scaffold.of()
  /// бұл жерде жарамайды — логотип Scaffold-тың ӨЗ build-інде тұр).
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  /// Негізгі панель бүктелген бе (қолмен төмен тартып жасырылған).
  bool _panelCollapsed = false;
  double _dragAccum = 0;

  final _map = MapController();
  Timer? _moveDebounce;
  PickedAddress? _from;
  bool _resolvingFrom = true;
  PickedAddress? _to;

  /// Аралық аялдамалар (0047) — «қайдан» мен «қайда» АРАСЫНДА, клиент
  /// қосқан ретпен. Макс [kMaxExtraStops].
  final List<PickedAddress> _stops = [];

  /// Санат (0046): «Такси» бөлімі модератор жағынан ҚОСУЛЫ болғанда ғана
  /// таңдау көрінеді. Өшулі болса экран баяғыдай — бір ғана көлік каруселі.
  VehicleCategory _category = VehicleCategory.cargo;

  /// Спецтехника санатындағы соңғы таңдау — таксиге ауысып, қайта
  /// оралғанда жоғалмауы үшін бөлек сақталады.
  VehicleType _cargoVehicle = VehicleType.gazelle;

  /// Такси санатындағы соңғы таңдау: такси (жолаушы) не доставка (ұсақ жүк).
  /// Ол да бөлек сақталады — санаттар арасында ауысқанда таңдау жоғалмайды.
  VehicleType _taxiVehicle = VehicleType.taxi;

  /// Заказға кететін НАҚТЫ көлік түрі.
  VehicleType get _vehicle => _category == VehicleCategory.taxi
      ? _taxiVehicle
      : _cargoVehicle;

  @override
  void initState() {
    super.initState();
    _resolveFrom(Geo.almaty);
    _initStart();
  }

  @override
  void dispose() {
    _moveDebounce?.cancel();
    super.dispose();
  }

  Future<void> _initStart() async {
    // 1) Соңғы сақталған орын болса — бірден соған жылжимыз. GPS рұқсаты
    //    болмаса да клиент өткен рет қалдырған қаласынан ашылады (Алматы емес).
    final last = await Prefs.lastLocation();
    if (last != null && mounted) {
      final p = LatLng(last.$1, last.$2);
      _map.move(p, 14);
      _resolveFrom(p);
    }
    // 2) GPS рұқсаты болса — нақты орынмен жаңартамыз әрі есте сақтаймыз.
    final pos = await Geo.currentPosition();
    if (pos != null && mounted) {
      final p = LatLng(pos.latitude, pos.longitude);
      _map.move(p, 15.5);
      _resolveFrom(p, persist: true);
    }
  }

  Future<void> _goToMyLocation() async {
    final pos = await Geo.currentPosition();
    if (pos == null) {
      if (mounted) showSnack(context, t('Локация қолжетімсіз'), error: true);
      return;
    }
    final p = LatLng(pos.latitude, pos.longitude);
    _map.move(p, 16);
    _resolveFrom(p, persist: true);
  }

  void _onMapMove(MapCamera camera, bool hasGesture) {
    if (!hasGesture) return;
    _moveDebounce?.cancel();
    _moveDebounce = Timer(
      const Duration(milliseconds: 500),
      () => _resolveFrom(camera.center, persist: true),
    );
  }

  Future<void> _resolveFrom(LatLng center, {bool persist = false}) async {
    setState(() => _resolvingFrom = true);
    final a = await Geo.reverseDetailed(center);
    if (!mounted) return;
    // Заказға ТІРЕК қала жазылады, себебі орындаушылар лентасы қала бойынша
    // сүзіледі: клиент Қосшыда/Луговойда тұрса да заказды Астана/Тараз
    // орындаушылары көруі керек. Ал ауылдың өз аты адрес жолында қалады
    // («Қосшы, Абылай хан, 12») — орындаушы қайда баратынын біледі.
    final anchor = Geo.anchorCity(center) ?? a.settlement;
    setState(() {
      _from = PickedAddress(a.labelFor(anchor), center, anchor);
      _resolvingFrom = false;
    });
    // Клиент өзі белгілеген орынды есте сақтаймыз (келесі ашылудың әдепкісі).
    if (persist) {
      unawaited(Prefs.setLastLocation(center.latitude, center.longitude));
    }
  }

  /// Автоматты анықталған «Қайдан» адресін сәл өзгертуге мүмкіндік береді.
  Future<void> _editFrom() async {
    final res = await CityStreetSheet.show(
      context,
      title: t('Қайдан аламыз?'),
      initial: _from,
    );
    if (res != null && mounted) {
      setState(() => _from = res);
      unawaited(Prefs.setLastLocation(res.point.latitude, res.point.longitude));
    }
  }

  Future<void> _pickTo() async {
    final res = await CityStreetSheet.show(
      context,
      title: t('Қайда жеткіземіз?'),
      initial: _to,
    );
    if (res != null) setState(() => _to = res);
  }

  /// ЖЕТКІЗУ нүктелері: [...аралық аялдамалар, финиш]. `_to` — әрқашан
  /// соңғысы, сол себепті екеуін бір тізім қылып қараймыз.
  List<PickedAddress> get _destinations => [..._stops, ?_to];

  /// Жеткізу нүктелерінің жаңа тізімін қабылдау: соңғысы — финиш (`_to`),
  /// алдындағылары — аралық аялдамалар (`_stops`).
  void _applyDestinations(List<PickedAddress> dest) {
    if (dest.isEmpty) return;
    setState(() {
      _to = dest.last;
      _stops
        ..clear()
        ..addAll(dest.take(dest.length - 1));
    });
  }

  /// Жаңа аралық аялдама қосу. Ол ӘРҚАШАН «қайдан» мен фиништің АРАСЫНДА
  /// тұрады, сол себепті жаңа мекенжай ФИНИШ болады да, бұрынғы финиш
  /// аралық аялдамаға айналады — Яндекс/inDriver-дегідей «жол бойымен
  /// қосу» логикасы (клиент әдетте соңына тағы бір жер қосады).
  Future<void> _addDestination() async {
    final res = await CityStreetSheet.show(context, title: t('Мекенжай қосу'));
    if (res == null || !mounted) return;
    _applyDestinations([..._destinations, res]);
  }

  /// Мекенжайлар парағы: ретін ауыстыру, өшіру, қосу (фото 2 үлгісі).
  Future<void> _openStopsSheet() async {
    final res = await StopsSheet.show(context, destinations: _destinations);
    if (res != null && mounted) _applyDestinations(res);
  }

  void _onPanelDragUpdate(DragUpdateDetails d) => _dragAccum += d.delta.dy;

  void _onPanelDragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (!_panelCollapsed && (_dragAccum > 24 || v > 300)) {
      setState(() => _panelCollapsed = true);
    } else if (_panelCollapsed && (_dragAccum < -24 || v < -300)) {
      setState(() => _panelCollapsed = false);
    }
    _dragAccum = 0;
  }

  /// Астыңғы блоктың нақты биіктігін өлшеп, карта/пиннің ысыру мөлшерін
  /// соған сай ұстап тұрады (`AnimatedSize` анимациясы кезінде де кадр
  /// сайын қайта өлшеніп, картаны панельмен бірге тегіс жылжытады).
  void _measureBottomInset() {
    if (!mounted) return;
    final h = _blockKey.currentContext?.size?.height;
    if (h == null) return;
    final target = h + MediaQuery.paddingOf(context).bottom;
    if ((target - _bottomInset).abs() > 0.5) {
      setState(() => _bottomInset = target);
    }
  }

  Future<void> _maybeContinue() async {
    if (_from == null || _to == null || !mounted) return;

    // Гест: белсенді заказ тексерусіз (auth жоқ) — бірден заказ толтыруға.
    // «Заказ жариялау» басылғанда кіру сұралады (CreateOrderScreen.isGuest).
    if (widget.isGuest) {
      await Navigator.of(context).push(
        slideUpRoute(
          CreateOrderScreen(
            from: _from!,
            to: _to!,
            stops: List.of(_stops),
            vehicleType: _vehicle,
            isGuest: true,
          ),
        ),
      );
      return;
    }

    // белсенді заказ бар ма? — ескерту
    final active = await Repo.c
        .from('orders')
        .select('id')
        .eq('client_id', Repo.uid ?? '')
        .inFilter('status', kActiveOrderStatuses);
    final count = (active as List).length;
    if (count > 0 && mounted) {
      final go = await confirmDialog(
        context,
        title: t('Белсенді заказ бар'),
        message: '$count ${t('белсенді заказыңыз бар — оны «Тапсырыстар» '
            'бетінен қадағалаңыз. Жаңа заказ бересіз бе?')}',
        cancelLabel: t('Жоқ'),
        confirmLabel: t('Жаңа заказ'),
        icon: Icons.local_shipping_outlined,
      );
      if (!go) return;
    }
    if (!mounted) return;

    await Navigator.of(context).push(
      slideUpRoute(
        CreateOrderScreen(
          from: _from!,
          to: _to!,
          stops: List.of(_stops),
          vehicleType: _vehicle,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureBottomInset());
    // «Такси» бөлімі қосулы ма (0046). Желі жоқта/жүктелгенше — false, яғни
    // экран баяғы қалпында (жалғыз карусель) болады.
    final taxiOn = ref.watch(taxiEnabledProvider).value ?? false;
    // Модератор бөлімді жаңа ғана ӨШІРСЕ, таксиде тұрған клиент тұйықта
    // қалмауы керек — жүк санатына қайтарамыз.
    if (!taxiOn && _category == VehicleCategory.taxi) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _category == VehicleCategory.taxi) {
          setState(() => _category = VehicleCategory.cargo);
        }
      });
    }
    return Scaffold(
      key: _scaffoldKey,
      drawer: AppDrawer(isGuest: widget.isGuest),
      // Шеттен саусақпен тарту ӨШІРУЛІ: бүкіл экранды карта алып тұр, әйтпесе
      // картаны солға жылжытқан сайын sidebar ашылып кетер еді. Sidebar тек
      // логотип батырмасымен ашылады.
      drawerEnableOpenDragGesture: false,
      body: Stack(
        children: [
          // Негізгі панельдің нақты өлшенген биіктігіне сай карта мен
          // пинді бірге жоғары ысырамыз (`_bottomInset`,
          // `_measureBottomInset` арқылы әр кадрда жаңартылады). Локация
          // батырмасы мен банер картаның үстінде қалқып тұрады, inset-ке
          // кірмейді. Екеуі бірдей тіктөртбұрышта жатуы МІНДЕТТІ —
          // flutter_map `camera.center` дәл сол виджеттің геометриялық
          // ортасын қайтарады, сол себепті пин визуалды жерімен нақты
          // координата сәйкес келуі үшін FlutterMap-тың өзін де солай
          // ысыру керек.
          Positioned.fill(
            bottom: _bottomInset,
            child: FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: Geo.almaty,
                initialZoom: 13,
                onPositionChanged: _onMapMove,
              ),
              children: [osmTileLayer()],
            ),
          ),
          Positioned.fill(
            bottom: _bottomInset,
            child: IgnorePointer(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedScale(
                        duration: const Duration(milliseconds: 150),
                        scale: _resolvingFrom ? 0.85 : 1,
                        child: const Icon(
                          Icons.location_on,
                          size: 44,
                          color: Gz.green,
                          shadows: [
                            Shadow(color: Colors.black38, blurRadius: 8),
                          ],
                        ),
                      ),
                      Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.only(top: 2),
                        decoration: const BoxDecoration(
                          color: Colors.black26,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  // Логотип — ЕНДІ БАТЫРМА: sol жақтан sidebar ашады
                  // (профиль, тапсырыстар, хабарландырулар тақтасы — бәрі
                  // сонда). Оң жақтағы бөлек профиль батырмасы жойылды.
                  // Бұрышында «мәзір» белгісі бар және өлшемі ұлғайтылған —
                  // адамдар оны түйме екенін байқамай қалатын.
                  child: Row(
                    children: [
                      LogoMenuButton(
                        onTap: () {
                          // Модератор «Такси»/«Хабарландырулар» бөлімін
                          // жаңа ғана қосқан/өшірген болуы мүмкін — қосымшаны
                          // қайта ашуды талап етпей, күйін сұрап аламыз.
                          ref.invalidate(taxiEnabledProvider);
                          _scaffoldKey.currentState?.openDrawer();
                        },
                      ),
                      const Spacer(),
                    ],
                  ),
                ),
                const Spacer(),
                // менің локациям батырмасы — картаның үстінде қалқып тұрады,
                // карта inset-іне кірмейді (жай ғана карта аймағында жүзеді)
                Padding(
                  padding: const EdgeInsets.only(right: 12, bottom: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // «Менің орным» — картаның үстінде тұрған жалғыз
                      // дөңгелек батырма: көлеңкесі күштірек болмаса,
                      // карта суретіне сіңіп кетеді.
                      Container(
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: Gz.cardShadow,
                        ),
                        child: Material(
                          elevation: 0,
                          shape: const CircleBorder(),
                          color: Gz.surface,
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: _goToMyLocation,
                            child: const Padding(
                              padding: EdgeInsets.all(13),
                              child: Icon(
                                Icons.my_location_rounded,
                                color: Gz.ink,
                                size: 22,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // белсенді («Іздеуде») заказ баннері — локация батырмасының астында
                const _ActiveOrdersBanner(),
                // Панельдің (жалғыз опак блок) биіктігі өзгергенде (бүктелу
                // анимациясы, шрифт масштабы) картаның inset-і сол сәтте
                // қайта өлшенеді — `build()` шақырылуын күтпей, сол себепті
                // карта панельмен тегіс жылжиды. Локация батырмасы мен
                // баннер бұған кірмейді — олар әдепкідей картаның үстінде
                // қалқып тұруы керек (map inset-ін ұлғайтпайды).
                NotificationListener<SizeChangedLayoutNotification>(
                  onNotification: (_) {
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _measureBottomInset(),
                    );
                    return true;
                  },
                  child: SizeChangedLayoutNotifier(
                    child: Container(
                      key: _blockKey,
                      // негізгі панель — тұтқасынан (не тақырыптан) қолмен
                      // төмен тартса бүктеледі де карта ашылады, қайта жоғары
                      // тартса не түртсе қайта ашылады
                      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                      decoration: BoxDecoration(
                        color: Gz.surface,
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: Gz.liftShadow,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => setState(
                              () => _panelCollapsed = !_panelCollapsed,
                            ),
                            onVerticalDragUpdate: _onPanelDragUpdate,
                            onVerticalDragEnd: _onPanelDragEnd,
                            child: Column(
                              children: [
                                Container(
                                  width: 44,
                                  height: 5,
                                  margin: const EdgeInsets.only(bottom: 12),
                                  decoration: BoxDecoration(
                                    color: Gz.disabledBg,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                                Row(
                                  children: [
                                    // Санат иконкасы — градиентті шаршыда
                                    // әрі жылы сәулемен: панельдің «жүрегі»
                                    // осы жерде екені бірден көрінеді.
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        gradient: Gz.brandGradient,
                                        borderRadius: BorderRadius.circular(13),
                                        boxShadow: Gz.glow(
                                          Gz.yellow,
                                          alpha: 0.4,
                                          blur: 12,
                                        ),
                                      ),
                                      child: Icon(
                                        _category == VehicleCategory.taxi
                                            ? Icons.local_taxi_rounded
                                            : Icons.local_shipping_rounded,
                                        size: 19,
                                        color: Gz.ink,
                                      ),
                                    ),
                                    const SizedBox(width: 11),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            t('Қандай көлік керек?'),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 16.5,
                                              fontWeight: FontWeight.w900,
                                              height: 1.2,
                                              letterSpacing: -0.35,
                                            ),
                                          ),
                                          if (!_panelCollapsed) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              t('Картадан орныңызды белгілеңіз'),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Gz.textSecondary,
                                                fontSize: 12,
                                                height: 1.2,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    // Бүктеу белгісі — жұмсақ дөңгелек
                                    // фонда: жалаң көрсеткіден гөрі түйме
                                    // екені айқынырақ.
                                    AnimatedRotation(
                                      duration: const Duration(
                                        milliseconds: 200,
                                      ),
                                      turns: _panelCollapsed ? 0.5 : 0,
                                      child: Container(
                                        padding: const EdgeInsets.all(3),
                                        decoration: const BoxDecoration(
                                          color: Gz.surfaceAlt,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.keyboard_arrow_down_rounded,
                                          color: Gz.textSecondary,
                                          size: 22,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          AnimatedSize(
                            duration: const Duration(milliseconds: 260),
                            curve: Curves.easeInOut,
                            alignment: Alignment.topCenter,
                            child: _panelCollapsed
                                ? const SizedBox(width: double.infinity)
                                : Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      const SizedBox(height: 10),
                                      // ---- САНАТ (такси қосулы болғанда) ----
                                      // Модератор «Такси» бөлімін қосса ғана
                                      // екі иконка шығады; өшулі болса бұл
                                      // блок мүлдем салынбайды.
                                      if (taxiOn) ...[
                                        VehicleCategoryTabs(
                                          selected: _category,
                                          onChanged: (c) =>
                                              setState(() => _category = c),
                                          // «ЖАҢА» белгісін модератор алып
                                          // тастай алады (0058).
                                          showNewBadge: ref
                                                  .watch(newBadgesProvider)
                                                  .value
                                                  ?.taxi ??
                                              true,
                                        ),
                                        const SizedBox(height: 10),
                                      ],
                                      // Көлік түрін таңдау — заказ тек сол
                                      // түрдегі орындаушыларға көрінеді.
                                      // ЕКІ САНАТТА ДА карусель: «Такси»
                                      // басылса — «Такси» мен «Доставка»,
                                      // «Спецтехника» басылса — газель,
                                      // фургон, КамАЗ… (бірдей тәртіп).
                                      if (_category == VehicleCategory.taxi)
                                        VehicleTypeCarousel(
                                          selected: _taxiVehicle,
                                          types: kTaxiVehicleTypes,
                                          onChanged: (v) => setState(
                                            () => _taxiVehicle = v,
                                          ),
                                        )
                                      else
                                        VehicleTypeCarousel(
                                          selected: _cargoVehicle,
                                          onChanged: (v) => setState(
                                            () => _cargoVehicle = v,
                                          ),
                                        ),
                                      const SizedBox(height: 10),
                                      // ---- МАРШРУТ ----
                                      // «Қайдан» картамен байланысты, бірақ
                                      // түртіп сәл өзгертуге болады.
                                      AddressRow(
                                        mark: const RoutePointMark.origin(),
                                        text: _resolvingFrom
                                            ? t('Анықталуда…')
                                            : (_from?.address ??
                                                  t('Картаны жылжытыңыз')),
                                        onTap: _resolvingFrom
                                            ? null
                                            : _editFrom,
                                        trailing: _resolvingFrom
                                            ? const SizedBox(
                                                width: 14,
                                                height: 14,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              )
                                            : const Icon(
                                                Icons.edit_outlined,
                                                size: 16,
                                                color: Gz.textSecondary,
                                              ),
                                      ),
                                      const SizedBox(height: 6),
                                      // Жеткізу нүктелері. БІРНЕШЕУ болса —
                                      // панель биіктемеуі үшін БІР ЖОЛҒА
                                      // жиналады («A → B»), түртсе басқару
                                      // парағы ашылады (ретін ауыстыру,
                                      // өшіру, қосу).
                                      if (_stops.isEmpty)
                                        AddressRow(
                                          mark: const RoutePointMark.finish(),
                                          text: _to?.address ??
                                              t('Қайда жеткіземіз?'),
                                          dim: _to == null,
                                          onTap: _pickTo,
                                          trailing: const Icon(
                                            Icons.chevron_right,
                                            color: Gz.textSecondary,
                                          ),
                                        )
                                      else
                                        AddressRow(
                                          mark: const Icon(
                                            Icons.sports_score,
                                            size: 20,
                                            color: Gz.red,
                                          ),
                                          text: _destinations
                                              .map((d) => d.address)
                                              .join('  →  '),
                                          onTap: _openStopsSheet,
                                          trailing: Container(
                                            padding:
                                                const EdgeInsets.symmetric(
                                                  horizontal: 7,
                                                  vertical: 2,
                                                ),
                                            decoration: BoxDecoration(
                                              color: Gz.violet
                                                  .withValues(alpha: 0.14),
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            child: Text(
                                              '${_destinations.length}',
                                              style: const TextStyle(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w900,
                                                color: Gz.violet,
                                              ),
                                            ),
                                          ),
                                        ),
                                      // «Мекенжай қосу» — жеткізу нүктесі
                                      // белгіленген соң ғана әрі шектен
                                      // аспағанда.
                                      if (_to != null &&
                                          _stops.length < kMaxExtraStops) ...[
                                        const SizedBox(height: 8),
                                        AddAddressButton(
                                          onPressed: _addDestination,
                                        ),
                                      ],
                                      const SizedBox(height: 14),
                                      // Экранның ЖАЛҒЫЗ шешуші әрекеті —
                                      // сол себепті градиентті әрі өз
                                      // сәулесі бар нұсқа: панельдегі басқа
                                      // элементтердің ешқайсысы онымен
                                      // «жарысып» тұрмайды.
                                      //
                                      // Жазуы ұзын атауларда
                                      // («Ассенизатор шақыру») не жүйе
                                      // шрифті үлкейтілгенде де БІР жолда
                                      // қалады (ішінде BtnLabel бар).
                                      GzPrimaryButton(
                                        label: vehicleCallLabel(_vehicle),
                                        onPressed:
                                            (_from == null || _resolvingFrom)
                                            ? null
                                            : (_to == null
                                                  ? _pickTo
                                                  : _maybeContinue),
                                      ),
                                    ],
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Sidebar-ды ТАБУҒА көмектесетін екі элемент (0059): сол шеттегі
          // тұрақты тұтқа (түртсе де, оңға тартса да ашылады) және алғашқы
          // ашылуларда шығатын қысқа нұсқау. Екеуі де картаның үстінде,
          // панельдің сыртында тұр — мазмұнды жаппайды.
          const SafeArea(child: DrawerEdgeHandle()),
          const SafeArea(child: DrawerHintOverlay(top: 78)),
        ],
      ),
    );
  }
}

class _ActiveOrdersBanner extends StatelessWidget {
  const _ActiveOrdersBanner();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Order>>(
      stream: Repo.myOrdersStream(),
      builder: (context, snap) {
        final active = (snap.data ?? [])
            .where((o) => o.isActive)
            .toList()
            .reversed
            .toList();
        if (active.isEmpty) return const SizedBox.shrink();
        final o = active.first;
        return GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => active.length > 1
                  ? const MyOrdersScreen()
                  : OrderDetailScreen(orderId: o.id),
            ),
          ),
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              // Жалаң қара тіктөртбұрыштың орнына градиент + тереңдік:
              // банер картаның үстінде «қалқып» тұрғандай көрінеді.
              gradient: Gz.heroGradient,
              borderRadius: BorderRadius.circular(18),
              boxShadow: Gz.liftShadow,
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: Gz.brandGradient,
                    shape: BoxShape.circle,
                    boxShadow: Gz.glow(Gz.yellow, alpha: 0.35, blur: 12),
                  ),
                  child: const Icon(
                    Icons.local_shipping_rounded,
                    size: 18,
                    color: Gz.ink,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        statusLabel(o.status, vehicleType: o.vehicleType),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          height: 1.25,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '${o.fromDisplay} → ${o.toDisplay}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                if (active.length > 1)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '+${active.length - 1}',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                const Icon(Icons.chevron_right, color: Colors.white70),
              ],
            ),
          ),
        );
      },
    );
  }
}
