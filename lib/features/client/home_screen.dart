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
import '../../shared/map_widgets.dart';
import '../../shared/transitions.dart';
import '../../shared/vehicle_picker.dart';
import '../../shared/widgets.dart';
import 'address_picker.dart';
import 'city_street_sheet.dart';
import 'create_order_screen.dart';
import 'my_orders_screen.dart';
import 'order_detail_screen.dart';

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

  /// Жүк/спецтехника санатындағы соңғы таңдау — таксиге ауысып, қайта
  /// оралғанда жоғалмауы үшін бөлек сақталады.
  VehicleType _cargoVehicle = VehicleType.gazelle;

  /// Заказға кететін НАҚТЫ көлік түрі.
  VehicleType get _vehicle => _category == VehicleCategory.taxi
      ? VehicleType.taxi
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
    final (addr, city) = await Geo.reverseWithCity(center);
    if (!mounted) return;
    setState(() {
      _from = PickedAddress(addr, center, city);
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

  /// Аралық аялдама қосу/өзгерту (0047). [index] — `_stops` ішіндегі орын;
  /// null болса ЖАҢА аялдама тізімнің соңына қосылады.
  ///
  /// Аялдамалар ӘРҚАШАН «қайдан» мен «қайда» АРАСЫНДА тұрады, сол себепті
  /// маршрут реті: _from → _stops[0] → … → _to.
  Future<void> _pickStop({int? index}) async {
    final res = await CityStreetSheet.show(
      context,
      title: t('Аялдама мекенжайы'),
      initial: index == null ? null : _stops[index],
    );
    if (res == null || !mounted) return;
    setState(() {
      if (index == null) {
        _stops.add(res);
      } else {
        _stops[index] = res;
      }
    });
  }

  void _removeStop(int index) => setState(() => _stops.removeAt(index));

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
                  child: Row(
                    children: [
                      Material(
                        elevation: 2,
                        borderRadius: BorderRadius.circular(13),
                        clipBehavior: Clip.antiAlias,
                        color: Gz.surface,
                        child: InkWell(
                          onTap: () {
                            // Модератор «Такси»/«Хабарландырулар» бөлімін
                            // жаңа ғана қосқан/өшірген болуы мүмкін — қосымшаны
                            // қайта ашуды талап етпей, күйін сұрап аламыз.
                            ref.invalidate(taxiEnabledProvider);
                            _scaffoldKey.currentState?.openDrawer();
                          },
                          child: Image.asset(
                            'assets/icon/icon.png',
                            width: 46,
                            height: 46,
                            fit: BoxFit.cover,
                          ),
                        ),
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
                      Material(
                        elevation: 3,
                        shape: const CircleBorder(),
                        color: Gz.surface,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _goToMyLocation,
                          child: const Padding(
                            padding: EdgeInsets.all(12),
                            child: Icon(
                              Icons.my_location,
                              color: Gz.ink,
                              size: 22,
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
                        borderRadius: BorderRadius.circular(26),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x260F1720),
                            blurRadius: 30,
                            offset: Offset(0, 10),
                          ),
                        ],
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
                                  width: 40,
                                  height: 4,
                                  margin: const EdgeInsets.only(bottom: 10),
                                  decoration: BoxDecoration(
                                    color: Gz.border,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(7),
                                      decoration: BoxDecoration(
                                        color: Gz.yellow,
                                        borderRadius: BorderRadius.circular(11),
                                      ),
                                      child: Icon(
                                        _category == VehicleCategory.taxi
                                            ? Icons.local_taxi
                                            : Icons.local_shipping,
                                        size: 19,
                                        color: Gz.ink,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            t('Қандай көлік керек?'),
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                          if (!_panelCollapsed)
                                            Text(
                                              t('Картадан орныңызды белгілеңіз'),
                                              style: const TextStyle(
                                                color: Gz.textSecondary,
                                                fontSize: 11.5,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    AnimatedRotation(
                                      duration: const Duration(
                                        milliseconds: 200,
                                      ),
                                      turns: _panelCollapsed ? 0.5 : 0,
                                      child: const Icon(
                                        Icons.keyboard_arrow_down_rounded,
                                        color: Gz.textSecondary,
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
                                        ),
                                        const SizedBox(height: 10),
                                      ],
                                      // көлік түрін таңдау — заказ тек сол
                                      // түрдегі орындаушыларға көрінеді.
                                      // Такси санатында түр біреу — карусель
                                      // орнына қысқа түсініктеме тұрады.
                                      if (_category == VehicleCategory.taxi)
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.info_outline,
                                              size: 15,
                                              color: Gz.textSecondary,
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                VehicleType.taxi.description,
                                                style: const TextStyle(
                                                  color: Gz.textSecondary,
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ],
                                        )
                                      else
                                        VehicleTypeCarousel(
                                          selected: _cargoVehicle,
                                          onChanged: (v) => setState(
                                            () => _cargoVehicle = v,
                                          ),
                                        ),
                                      const SizedBox(height: 10),
                                      // ---- МАРШРУТ: қайдан → аялдамалар → қайда ----
                                      // «Қайдан» картамен байланысты, бірақ
                                      // түртіп сәл өзгертуге болады.
                                      AddressRow(
                                        icon: Icons.trip_origin,
                                        iconColor: Gz.green,
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
                                      // Аралық аялдамалар (0047) — қосылған
                                      // ретімен, әрқайсысын түртіп өзгертуге
                                      // не ✕ арқылы алып тастауға болады.
                                      for (var i = 0; i < _stops.length; i++)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 6),
                                          child: AddressRow(
                                            icon: Icons.adjust,
                                            iconColor: Gz.violet,
                                            text: _stops[i].address,
                                            onTap: () => _pickStop(index: i),
                                            trailing: IconButton(
                                              onPressed: () => _removeStop(i),
                                              icon: const Icon(Icons.close),
                                              iconSize: 16,
                                              visualDensity:
                                                  VisualDensity.compact,
                                              padding: EdgeInsets.zero,
                                              constraints:
                                                  const BoxConstraints(
                                                    minWidth: 28,
                                                    minHeight: 28,
                                                  ),
                                              color: Gz.textSecondary,
                                              tooltip: t('Алып тастау'),
                                            ),
                                          ),
                                        ),
                                      const SizedBox(height: 6),
                                      AddressRow(
                                        icon: Icons.location_on,
                                        iconColor: Gz.red,
                                        text: _to?.address ??
                                            t('Қайда жеткіземіз?'),
                                        dim: _to == null,
                                        onTap: _pickTo,
                                        trailing: const Icon(
                                          Icons.chevron_right,
                                          color: Gz.textSecondary,
                                        ),
                                      ),
                                      // «+ Мекенжай қосу» — жеткізу нүктесі
                                      // белгіленген соң ғана (аялдама әрқашан
                                      // ЕКЕУІНІҢ АРАСЫНДА тұрады) әрі шектен
                                      // аспағанда.
                                      if (_to != null &&
                                          _stops.length < kMaxExtraStops)
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: TextButton.icon(
                                            onPressed: () => _pickStop(),
                                            style: TextButton.styleFrom(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                  ),
                                              minimumSize: Size.zero,
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                            ),
                                            icon: const Icon(
                                              Icons.add_circle_outline,
                                              size: 17,
                                            ),
                                            label: BtnLabel(
                                              t('Мекенжай қосу'),
                                              style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                        ),
                                      const SizedBox(height: 12),
                                      FilledButton(
                                        onPressed:
                                            (_from == null || _resolvingFrom)
                                            ? null
                                            : (_to == null
                                                  ? _pickTo
                                                  : _maybeContinue),
                                        // FittedBox: ұзын атаулар
                                        // («Ассенизатор шақыру» т.б.) не жүйе
                                        // шрифті үлкейтілген кезде де 1
                                        // жолда қалады.
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            vehicleCallLabel(_vehicle),
                                            maxLines: 1,
                                            softWrap: false,
                                          ),
                                        ),
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
              color: Gz.ink,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Gz.yellow,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.local_shipping,
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
                        statusLabel(o.status),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        '${o.fromDisplay} → ${o.toDisplay}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
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
