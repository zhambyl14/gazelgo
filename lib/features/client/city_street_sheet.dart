import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../core/geo.dart';
import '../../core/kz_cities.dart';
import '../../core/lang.dart';
import '../../core/street_index.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import 'address_picker.dart';
import 'my_addresses_screen.dart';
import 'saved_addresses.dart';

/// Мекенжай таңдау — БІР ПАРАҚ, БІР БАСУ.
///
/// БҰРЫН қалай еді (5–6 басу, ЕКІ деңгейлі ұя):
///   өрісті түрту → парақ ашылады → «қала» тақтайшасы → ЕКІНШІ парақ →
///   қаланы таңдау → артқа → «көше» тақтайшасы → ҮШІНШІ парақ → теру →
///   нәтижені түрту → артқа → «Дайын» батырмасы. Адам жарты жолда шаршайтын.
///
/// ЕНДІ (жиі кездесетін жағдайда — БІР БАСУ):
///   өрісті түрту → парақ клавиатурамен бірге ашылады, сақталған («Үй»,
///   «Жұмыс»), соңғы мекенжайлар мен «менің орным» ДЕРЕУ көрініп тұр →
///   біреуін түрту → парақ жабылады, мекенжай дайын.
///   Жаңа мекенжай керек болса: теру → тізімнен түрту → бітті (растау
///   батырмасы ЖОҚ, себебі таңдаудың өзі — растау).
///
/// ҚАЛА — ҚАДАМ ЕМЕС. Ол GPS арқылы өзі анықталады да, жоғарыда шағын
/// «чип» болып тұрады; керек болса түртіп ауыстыруға болады. Бұрын қала
/// МІНДЕТТІ бірінші қадам болатын — ал іс жүзінде клиенттердің 95%-ы өз
/// қаласында заказ береді.
class CityStreetSheet extends StatefulWidget {
  final String title;
  final PickedAddress? initial;

  /// Тізімдегі әр мекенжайдың ҚАШЫҚТЫҒЫ осы нүктеден есептеледі (Яндекс
  /// Go-дағыдай «12,5 км»). «Қайда» іздегенде — алу нүктесі; берілмесе —
  /// клиенттің өз орны (GPS).
  final LatLng? origin;

  const CityStreetSheet({
    super.key,
    required this.title,
    this.initial,
    this.origin,
  });

  static Future<PickedAddress?> show(
    BuildContext context, {
    required String title,
    PickedAddress? initial,
    LatLng? origin,
  }) {
    return showGzSheet<PickedAddress>(
      context,
      builder: (_) =>
          CityStreetSheet(title: title, initial: initial, origin: origin),
    );
  }

  @override
  State<CityStreetSheet> createState() => _CityStreetSheetState();
}

/// Қала таңдау нәтижесі.
///
/// Клиенттердің бәрі облыс орталығында тұрмайды: Тараз маңында Мерке, Луговой;
/// Астана маңында Ерейментау, Қосшы бар. Сол себепті ЕКІ ұғымды бөлеміз:
///
///  • [city] — ТІРЕК қала. Заказдың `from_city`/`to_city` өрісіне осы жазылады,
///    орындаушылар лентасының қала сүзгісі де осы бойынша жүреді. Егер бұған
///    ауыл атын жазсақ, Луговойдағы заказды ЕШБІР орындаушы көрмей қалады.
///  • [settlement] — клиент таңдаған НАҚТЫ елді мекен. Карта сол жерден
///    ашылады, ал ауыл аты адрес жолына қосылады («Луговой, Абая, 5»).
class CityChoice {
  final String city;
  final String? settlement;
  final LatLng? point;
  const CityChoice({required this.city, this.settlement, this.point});

  /// Клиентке көрсетілетін атау.
  String get label => settlement ?? city;
}

/// Нүкте басқа аймақта болғандағы клиенттің жауабы.
enum _AreaAnswer {
  /// Тапсырыс ұсынылған тірек қалаға тіркелсін.
  switchCity,

  /// Таңдалған қала қалсын (әкімшілік жағынан дұрысын клиент біледі).
  keepCity,

  /// Картадан қайта белгілеймін.
  remark,
}

class _CityStreetSheetState extends State<CityStreetSheet> {
  // ---- қала (тірек) ----
  String? _city;

  /// Тірек қаладан бөлек нақты елді мекен (болса).
  String? _area;

  /// Іздеу мен картаны бағыттайтын орталық (ауыл таңдалса — ауылдың ортасы).
  LatLng? _cityPoint;
  bool _detectingCity = false;

  // ---- іздеу ----
  final _search = TextEditingController();
  Timer? _debounce;
  List<AddressHit> _results = const [];

  /// Қаланың көше тізімі — қате жазылған атауды түзету үшін (фонда
  /// жүктеледі; дайын болмаса іздеу онсыз да жұмыс істейді).
  StreetIndex? _index;
  bool _loading = false;

  /// Іздеу желі/сервер қатесімен аяқталды (бос тізімнен өзгеше: «табылмады»
  /// емес, «іздеу істемей тұр»).
  bool _searchFailed = false;

  /// Соңғы сұраныстың нөмірі: баяу ескі жауап жаңа сұраныстың нәтижесін
  /// басып кетпеуі үшін (бұрын «Абай» деп жазып, «Абая 15» дегенде тізім
  /// кері ескі нәтижеге ауысып кететін).
  int _searchSeq = 0;

  // ---- жылдам таңдау ----
  List<SavedAddress> _saved = [];
  List<PickedAddress> _recent = [];

  /// GPS-тен анықталған ағымдағы орын — тізімнің ЕҢ БАСЫНДА тұрады.
  /// «Қайдан» өрісі үшін бұл ең жиі керек жауап, ол — бір басу.
  PickedAddress? _myPlace;

  @override
  void initState() {
    super.initState();
    _city = widget.initial?.city;
    _cityPoint = widget.initial?.point;
    // Мекенжайды өңдеп жатсақ — мәтін дайын тұрады да, теруді бастаса
    // бірден алмасады (толық белгіленген).
    final init = widget.initial?.address;
    if (init != null && init.isNotEmpty) {
      _search.text = init;
      _search.selection = TextSelection(
        baseOffset: 0,
        extentOffset: init.length,
      );
    }
    _detectCity();
    _loadBook();
    _loadIndex();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  /// Сақталған және соңғы мекенжайларды жүктейді. Соңғылардан сақталғанмен
  /// қайталанатындарын алып тастаймыз (екі рет көрсетпеу үшін).
  Future<void> _loadBook() async {
    final s = await AddressBook.saved();
    final r = await AddressBook.recent();
    String key(String a, String? c) =>
        '${a.trim().toLowerCase()}|${(c ?? '').trim().toLowerCase()}';
    final savedKeys = s.map((e) => key(e.address, e.city)).toSet();
    final recent = r
        .where((e) => !savedKeys.contains(key(e.address, e.city)))
        .toList();
    if (mounted) {
      setState(() {
        _saved = s;
        _recent = recent;
      });
    }
  }

  /// Өз орнының қаласын ЖӘНЕ мекенжайын автоматты анықтайды (GPS арқылы).
  ///
  /// Reverse-геокодер НАҚТЫ елді мекенді береді («Қосшы», «Луговой»), ал
  /// заказға тірек қала керек — сол себепті екеуін бөліп аламыз.
  Future<void> _detectCity() async {
    setState(() => _detectingCity = true);
    final pos = await Geo.currentPosition();
    if (pos == null || !mounted) {
      if (mounted) setState(() => _detectingCity = false);
      return;
    }
    final p = LatLng(pos.latitude, pos.longitude);
    if (!Geo.inKazakhstan(p)) {
      setState(() => _detectingCity = false);
      return;
    }
    // Қашықтықты есептеу үшін ([widget.origin] берілмесе).
    setState(() => _here = p);
    final anchor = Geo.anchorCity(p);
    final addr = await Geo.reverseDetailed(p);
    if (!mounted) return;
    final settlement = addr.settlement;
    final city = anchor ?? settlement;
    setState(() {
      // Мекенжай ӨҢДЕЛІП жатса, клиент таңдаған қаланы ЖОҚҚА ШЫҒАРМАЙМЫЗ —
      // GPS тек қала БЕЛГІСІЗ болғанда толтырады.
      if (_city == null) {
        _city = city;
        _area = (settlement != null && !Geo.sameCity(settlement, city))
            ? settlement
            : null;
        _cityPoint = p;
      }
      // Геокодер құлағанда `labelFor` координата қайтарады — ол мекенжай
      // емес, сондықтан «Менің орным» ретінде ұсынбаймыз.
      final label = addr.labelFor(city);
      _myPlace = label == Geo.coordLabel(p)
          ? null
          : PickedAddress(label, p, city);
      _detectingCity = false;
    });
    // Қала анықталғанша клиент мәтін теріп қойған болса — енді іздейміз.
    _loadIndex();
    if (_search.text.trim().length >= 2) unawaited(_runSearch());
  }

  LatLng? get _center => _cityPoint ?? Geo.cityCenter(_city);

  /// Клиенттің GPS-тегі орны (анықталса).
  LatLng? _here;

  /// Қашықтық есептелетін нүкте: алу нүктесі, болмаса өз орны.
  LatLng? get _origin => widget.origin ?? _here;

  /// «12,5 км» / «850 м» — нүкте белгісіз болса null (жазылмайды).
  String? _distanceTo(LatLng p) {
    final o = _origin;
    if (o == null) return null;
    return Geo.formatDistance(Geo.haversineKm(o, p));
  }

  // ═══════════════════════════════════════════════════════════════════
  //  ІЗДЕУ
  // ═══════════════════════════════════════════════════════════════════

  void _onChanged(String q) {
    _debounce?.cancel();
    final n = q.trim();
    if (n.length < 2) {
      _searchSeq++;
      setState(() {
        _results = const [];
        _loading = false;
        _searchFailed = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _searchFailed = false;
    });
    // Тегін Nominatim — әр таңбада сұрау жіберуге болмайды.
    _debounce = Timer(const Duration(milliseconds: 550), _runSearch);
  }

  /// Іздеуді орындайды. Қала белгісіз болса — күтеді: қала анықталғанда
  /// ([_detectCity]) осы әдіс қайта шақырылады.
  Future<void> _runSearch() async {
    final n = _search.text.trim();
    if (n.length < 2) return;
    final city = _city;
    if (city == null) {
      if (mounted) setState(() => _loading = _detectingCity);
      return;
    }
    final seq = ++_searchSeq;
    if (mounted) {
      setState(() {
        _loading = true;
        _searchFailed = false;
      });
    }
    try {
      final res = await Geo.searchAddress(
        city: city,
        query: n,
        near: _center,
        index: _index,
      );
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _results = _inSelectedArea(res);
        _loading = false;
      });
    } on GeoSearchException {
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _results = const [];
        _loading = false;
        _searchFailed = true;
      });
    }
  }

  /// Нүкте таңдалған қаланың аймағында ма ([Geo.inCityArea] ережесі).
  bool _pointInArea(LatLng p) => Geo.inCityArea(p, _city, center: _center);

  /// Таңдалған қала мен оның маңындағы нәтижелерді ғана қалдырады.
  /// (Бұрын дәл қала аты талап етілетін — сондықтан «Луговой, Абая» деп
  /// іздегенде тізім әрқашан бос болатын.)
  ///
  /// Таңдалған ҚАЛАНЫҢ ӨЗІНДЕГІ нәтижелер — алдымен; маңайдағы ауылдардың
  /// нәтижелері (Алматыда «Абая 15» деп іздегенде Талғар, Қарғалы,
  /// Панфилово… «улица Абая, 15») қаладағы нәтиже бар болса 3-ке дейін
  /// қысқартылады — әйтпесе олар тізімді толтырып, дұрысын көмеді.
  List<AddressHit> _inSelectedArea(List<AddressHit> res) {
    final inArea = res
        .where(
          (e) =>
              Geo.sameCity(e.place.city, _city) || _pointInArea(e.place.point),
        )
        .toList();
    final own = inArea
        .where((e) => e.place.city == null || Geo.sameCity(e.place.city, _city))
        .toList();
    final around = inArea
        .where(
          (e) => e.place.city != null && !Geo.sameCity(e.place.city, _city),
        )
        .toList();
    // Маңайдағы елді мекендер — жақыннан алысқа.
    final ref = _origin ?? _center;
    if (ref != null) {
      around.sort(
        (a, b) => Geo.haversineKm(
          ref,
          a.place.point,
        ).compareTo(Geo.haversineKm(ref, b.place.point)),
      );
    }
    return [...own, ...(own.isEmpty ? around : around.take(3))];
  }

  /// Адрестің басындағы қала атауын алып тастайды («Тараз, Абая, 5» →
  /// «Абая, 5»), қала өрісінде онсыз да сол қала тұрғанда қайталанбауы үшін.
  static String _stripCityPrefix(String address, String city) {
    final parts = address.split(',');
    if (parts.length > 1 && Geo.sameCity(parts.first.trim(), city)) {
      return parts.skip(1).join(',').trim();
    }
    return address;
  }

  // ═══════════════════════════════════════════════════════════════════
  //  ҚАБЫЛДАУ
  // ═══════════════════════════════════════════════════════════════════

  /// Картадан/тізімнен белгіленген нүктені ҚАБЫЛДАУ.
  ///
  /// Нүкте ЕШҚАШАН жоғалмайды:
  ///  • Қала аймағында — үнсіз қабылданады, ауыл аты адрес жолына қосылып
  ///    қойған болады.
  ///  • Мүлдем басқа аймақта — қаланы ауыстыруды сұраймыз (қате таңдау болуы
  ///    ықтимал), клиент келіссе жаңа қаламен қайтарамыз.
  Future<PickedAddress?> _accept(PickedAddress p) async {
    final city = _city;
    if (!Geo.inKazakhstan(p.point)) {
      showSnack(context, t('Тек Қазақстан ішінде'), error: true);
      return null;
    }
    if (city == null) return p;
    if (_pointInArea(p.point)) {
      return PickedAddress(p.address, p.point, city);
    }
    final suggested = Geo.anchorCity(p.point) ?? p.city;
    if (suggested == null || Geo.sameCity(suggested, city) || !mounted) {
      // Тірек қала табылмады (шалғай жер) не сол қаланың өзі — нүктені
      // сұраусыз қабылдаймыз.
      return PickedAddress(p.address, p.point, city);
    }
    switch (await _askSwitchCity(suggested, p.city)) {
      case _AreaAnswer.switchCity:
        return PickedAddress(
          _stripCityPrefix(p.address, suggested),
          p.point,
          suggested,
        );
      case _AreaAnswer.keepCity:
        return PickedAddress(p.address, p.point, city);
      case _AreaAnswer.remark:
      case null:
        return null;
    }
  }

  /// «Бұл нүкте басқа аймақта — қаланы ауыстырайық па?» сұрағы.
  ///
  /// ҮШ жауап болуы МАҢЫЗДЫ. Тірек қала әрдайым әкімшілік жағынан дұрыс
  /// бола бермейді: мысалы Жаңатас — Жамбыл облысы (Тараз), бірақ картада
  /// оған Түркістан жақынырақ. Сондықтан «таңдалған қаланы қалдыру» деген
  /// жауап болмаса, клиент дұрыс нүктесінен айырылып қалар еді.
  Future<_AreaAnswer?> _askSwitchCity(String suggested, String? settlement) {
    final ru = Lang.current.value == AppLang.ru;
    final label = _area ?? _city ?? '';
    final where =
        (settlement != null &&
            settlement.isNotEmpty &&
            !Geo.sameCity(settlement, suggested))
        ? '$settlement ($suggested)'
        : suggested;
    return showDialog<_AreaAnswer>(
      context: context,
      builder: (ctx) => GzDialogFrame(
        icon: Icons.map_outlined,
        color: Gz.info,
        title: ru ? 'Другой регион' : 'Басқа аймақ',
        message: ru
            ? 'Отмеченная точка находится в: $where, '
                  'а выбранный город — $label.\n\n'
                  'К какому городу отнести заказ? '
                  'Точка на карте сохранится в любом случае.'
            : 'Белгіленген нүкте — $where, ал таңдалған қала — '
                  '$label.\n\n'
                  'Тапсырыс қай қалаға тіркелсін? '
                  'Картадағы нүкте екі жағдайда да сақталады.',
        verticalActions: true,
        actions: [
          gzDialogPrimary(
            suggested,
            onPressed: () => Navigator.of(ctx).pop(_AreaAnswer.switchCity),
          ),
          gzDialogCancel(ctx, label, result: _AreaAnswer.keepCity),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_AreaAnswer.remark),
            child: Text(ru ? 'Отметить заново' : 'Қайта белгілеу'),
          ),
        ],
      ),
    );
  }

  /// Мекенжайды ҚАБЫЛДАП, парақты жабады — бұл «бір басу» ағынының соңы.
  Future<void> _use(PickedAddress p) async {
    final accepted = await _accept(p);
    if (accepted != null && mounted) Navigator.of(context).pop(accepted);
  }

  /// Сақталған/соңғы мекенжай — аймақ тексерусіз, БІРДЕН (клиент оны
  /// бұрын өзі растап қойған, қайта сұрау артық қадам болар еді).
  void _useDirect(PickedAddress p) => Navigator.of(context).pop(p);

  // ═══════════════════════════════════════════════════════════════════
  //  ӘРЕКЕТТЕР
  // ═══════════════════════════════════════════════════════════════════

  Future<void> _pickCity() async {
    FocusScope.of(context).unfocus();
    final picked = await showGzSheet<CityChoice>(
      context,
      builder: (_) => const _CityPickerSheet(),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _city = picked.city;
      _area = picked.settlement;
      _cityPoint = picked.point ?? Geo.cityCenter(picked.city);
      // Қала ауысты — ескі нәтижелер басқа қалаға тиесілі.
      _results = const [];
    });
    _loadIndex();
    // Терілген мәтін болса — жаңа қала бойынша қайта іздейміз.
    if (_search.text.trim().length >= 2) _onChanged(_search.text);
  }

  /// Таңдалған қаланың көше тізімін фонда жүктейді; дайын болғанда
  /// терілген сұраныс қайта ізделеді (енді қате жазылғаны да табылады).
  void _loadIndex() {
    final city = _city;
    final center = _center;
    if (city == null || center == null) return;
    final ready = StreetIndex.peek(city, center);
    if (ready != null) {
      _index = ready;
      return;
    }
    unawaited(
      StreetIndex.load(city, center, settlement: _area != null).then((idx) {
        if (!mounted || idx == null || city != _city) return;
        _index = idx;
        if (_search.text.trim().length >= 2) unawaited(_runSearch());
      }),
    );
  }

  /// Картадан дәл жерді белгілеу (екінші деңгейлі әрекет).
  Future<void> _findOnMap() async {
    FocusScope.of(context).unfocus();
    final city = _city;
    final res = await AddressPickerScreen.pick(
      context,
      title: _area ?? city ?? t('Картадан белгілеу'),
      city: city,
      initial: widget.initial?.point ?? _center,
    );
    if (res == null || !mounted) return;
    await _use(res);
  }

  /// Табылған КӨШЕДЕ үйді картадан көрсету: үй нөмірі картада жоқ болса
  /// (Қазақстанда жиі), карта сол көшеде ашылады, клиент пинді үйіне
  /// қояды. Мекенжай атауы әрқашан КАРТАДАН анықталады — клиент жазған
  /// мәтін адрес болып кетпейді (атау мен нүкте ешқашан айырылмайды).
  Future<void> _pinOnMap(AddressHit h) async {
    FocusScope.of(context).unfocus();
    final picked = await AddressPickerScreen.pick(
      context,
      title: t('Үйді картадан көрсетіңіз'),
      city: _city,
      initial: h.place.point,
      initialZoom: 17,
    );
    if (picked == null || !mounted) return;
    await _use(picked);
  }

  /// Табылған мекенжайды «Үй»/«Жұмыс» етіп сақтау (таңдамай-ақ).
  Future<void> _save(PickedAddress p) async {
    FocusScope.of(context).unfocus();
    final ok = await showSaveAddressSheet(context, place: p);
    if (!ok) return;
    await _loadBook();
    if (mounted) showSnack(context, t('Мекенжай сақталды'));
  }

  // ═══════════════════════════════════════════════════════════════════
  //  КӨРІНІС
  // ═══════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // Клавиатура ашық тұрғанда парақ одан ЖОҒАРЫ қалуы керек, әйтпесе
    // тізім клавиатураның астына кіріп кетеді.
    // (`num.clamp` статикалық типі `num` — BoxConstraints `double` күтеді,
    // сол себепті шектеуді қолмен жазамыз.)
    final rawH = media.size.height * 0.92 - media.viewInsets.bottom;
    final maxH = rawH < 300 ? 300.0 : rawH;
    final query = _search.text.trim();
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Gz.disabledBg,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              // ---- тақырып + қала чипі ----
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Gz.h2,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: IconButton.styleFrom(
                        backgroundColor: Gz.surfaceAlt,
                        foregroundColor: Gz.textSecondary,
                      ),
                      icon: const Icon(Icons.close_rounded, size: 20),
                    ),
                  ],
                ),
              ),
              // Қала — ҚАДАМ ЕМЕС, ШАҒЫН ЧИП. Өзі анықталады, керек болса
              // түртіп ауыстыруға болады.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _cityChip(),
                ),
              ),
              // ---- ІЗДЕУ ӨРІСІ (клавиатура бірден ашық) ----
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: TextField(
                  controller: _search,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onChanged: (v) => setState(() => _onChanged(v)),
                  // Enter — тек клавиатураны жабады: тізім толық көрінсін,
                  // клиент дұрысын өзі таңдасын.
                  onSubmitted: (_) => FocusScope.of(context).unfocus(),
                  decoration: InputDecoration(
                    hintText: t('Көше, үй нөмірі не нысан аты'),
                    prefixIcon: const Icon(Icons.search_rounded),
                    // Оң жақта — «Карта» (Яндекс Go үлгісі): картадан
                    // белгілеу әрқашан бір басуда, тізімнің астын іздеудің
                    // қажеті жоқ.
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_loading)
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        else if (query.isNotEmpty)
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(
                              Icons.cancel_rounded,
                              size: 20,
                              color: Gz.textTertiary,
                            ),
                            onPressed: () {
                              _search.clear();
                              _searchSeq++;
                              setState(() {
                                _results = const [];
                                _loading = false;
                                _searchFailed = false;
                              });
                            },
                          ),
                        // Сұраныс терілгенде «Карта» тізімнің соңында тұрады
                        // («Тізімде жоқ па?») — бір әрекет екі жерде болмасын.
                        if (query.length < 2) ...[
                          Container(width: 1, height: 22, color: Gz.border),
                          TextButton(
                            onPressed: _findOnMap,
                            style: TextButton.styleFrom(
                              foregroundColor: Gz.blue,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              minimumSize: const Size(0, 40),
                            ),
                            child: Text(
                              t('Карта'),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: query.length < 2 ? _quickList() : _resultList(query),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Қала чипі: «📍 Тараз ⌄». Ауылда болса, астында тірек қала жазылады.
  Widget _cityChip() {
    final label = _detectingCity && _city == null
        ? t('Анықталуда…')
        : (_area ?? _city ?? t('Қаланы таңдаңыз'));
    final unknown = _city == null && !_detectingCity;
    return PressScale(
      child: Material(
        color: unknown ? Gz.tint(Gz.red, 0.10) : Gz.surfaceAlt,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: _pickCity,
          child: Container(
            padding: const EdgeInsets.fromLTRB(11, 7, 9, 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: unknown ? Gz.tint(Gz.red, 0.35) : Gz.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.location_city_rounded,
                  size: 16,
                  color: unknown ? Gz.red : Gz.textSecondary,
                ),
                const SizedBox(width: 7),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 200),
                  child: BtnLabel(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.15,
                      color: unknown ? Gz.red : Gz.ink,
                    ),
                  ),
                ),
                // Ауыл/кент таңдалса, заказ қай қалаға тіркелетінін ашық
                // жазамыз — клиент «неге Тараз?» деп таңданбауы үшін
                // (орындаушылар сол қаладан келеді).
                if (_area != null && _city != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Gz.tint(Gz.blue, 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _city!,
                      style: const TextStyle(
                        fontSize: 11,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                        color: Gz.blue,
                      ),
                    ),
                  ),
                ],
                const Icon(
                  Icons.expand_more_rounded,
                  size: 18,
                  color: Gz.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── ТЕРУСІЗ КӨРІНЕТІН ТІЗІМ (ең жиі жағдай — бір басу) ─────────────
  Widget _quickList() {
    final my = _myPlace;
    return ListView(
      padding: const EdgeInsets.only(top: 4, bottom: 12),
      children: [
        if (my != null)
          _placeRow(
            icon: Icons.near_me_rounded,
            iconColor: Gz.blue,
            title: t('Менің орным'),
            subtitle: my.address,
            onTap: () => _useDirect(my),
          ),
        if (_saved.isNotEmpty) ...[
          _header(Icons.bookmark_rounded, t('Сақталған')),
          ..._divided([
            for (final a in _saved)
              _placeRow(
                icon: a.isPrimary
                    ? Icons.star_rounded
                    : savedAddressIcon(a.kind),
                iconColor: a.isPrimary ? Gz.yellowDark : Gz.ink,
                title: savedAddressTitle(a),
                subtitle: a.address,
                distance: _distanceTo(a.toPicked().point),
                onTap: () => _useDirect(a.toPicked()),
              ),
          ]),
        ],
        if (_recent.isNotEmpty) ...[
          _header(Icons.history_rounded, t('Соңғы мекенжайлар')),
          ..._divided([
            for (final p in _recent)
              _placeRow(
                icon: Icons.history_rounded,
                title: p.address,
                subtitle: p.city,
                distance: _distanceTo(p.point),
                onTap: () => _useDirect(p),
              ),
          ]),
        ],
        if (my == null && _saved.isEmpty && _recent.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
            child: Column(
              children: [
                const Icon(
                  Icons.travel_explore_rounded,
                  size: 40,
                  color: Gz.textTertiary,
                ),
                const SizedBox(height: 10),
                Text(
                  t(
                    'Мекенжайды жазыңыз — мыс. «Абая 15» не «Хан Шатыр». '
                    'Дәл жерді белгілеу үшін — «Карта».',
                  ),
                  textAlign: TextAlign.center,
                  style: Gz.bodyMuted,
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ── ІЗДЕУ НӘТИЖЕЛЕРІ ───────────────────────────────────────────────
  Widget _resultList(String query) {
    final empty = _results.isEmpty && !_loading;
    return ListView(
      padding: const EdgeInsets.only(top: 4, bottom: 12),
      children: [
        ..._divided([for (final r in _results) _resultRow(r)]),
        if (_city == null && !_detectingCity)
          _note(t('Алдымен жоғарыдан қаланы таңдаңыз.'))
        else if (_searchFailed)
          // Іздеу ІСТЕМЕЙ тұр (желі/сервер) — «табылмады» деп жалған
          // айтпаймыз, қайталау батырмасын береміз.
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 6),
            child: Column(
              children: [
                Text(
                  t(
                    'Іздеу қазір жұмыс істемей тұр. Интернетті тексеріп, '
                    'қайталап көріңіз.',
                  ),
                  textAlign: TextAlign.center,
                  style: Gz.bodyMuted,
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _runSearch,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(t('Қайталау')),
                ),
              ],
            ),
          )
        else if (empty)
          _note(
            t(
              'Мұндай мекенжай табылмады. Жазылуын тексеріңіз не нүктені '
              'картадан көрсетіңіз — мекенжайын өзіміз анықтаймыз.',
            ),
          ),
        // Картадан көрсету — тізімде дұрысы болмаса. Мекенжай атауы
        // КАРТАДАН анықталады (клиент жазған мәтін адрес болмайды).
        if (_city != null && !_loading)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
            child: _row(
              icon: Icons.map_rounded,
              iconColor: empty ? Gz.green : Gz.blue,
              title: empty
                  ? t('Картадан көрсету')
                  : t('Тізімде жоқ па? Картадан көрсетіңіз'),
              subtitle: t('Нүктені қойсаңыз, мекенжайы өзі анықталады'),
              onTap: _findOnMap,
              strong: empty,
            ),
          ),
      ],
    );
  }

  Widget _resultRow(AddressHit h) {
    final r = h.place;
    // Нәтиже қала маңындағы ауылда болса, ауыл атын АДРЕСКЕ қосамыз —
    // орындаушы қайда баратынын адрестің өзінен көруі керек. Тізімде ол
    // тақырыпта емес, астыңғы жолда («аудан, елді мекен») тұрады.
    final other =
        r.city != null && r.city!.isNotEmpty && !Geo.sameCity(r.city, _city);
    final label = other ? '${r.city}, ${r.name}' : r.name;
    final picked = PickedAddress(label, r.point, _city);
    final place = r.city ?? _area ?? _city;
    final district = r.district;
    final where = [
      if (district != null && !Geo.sameCity(district, place)) district,
      ?place,
    ].join(', ');
    // Көше табылды, бірақ үй картада жоқ — үйді картадан көрсетеді.
    final sub = h.needsPin
        ? t('Көше табылды — үйді картадан көрсетесіз')
        : where;
    return _placeRow(
      icon: h.needsPin
          ? Icons.edit_location_alt_rounded
          : (h.exactHouse ? Icons.home_rounded : Icons.place_rounded),
      iconColor: h.needsPin
          ? Gz.blue
          : (h.exactHouse ? Gz.ink : Gz.textTertiary),
      title: r.name,
      subtitle: sub.isEmpty ? null : sub,
      distance: _distanceTo(r.point),
      onTap: () => h.needsPin ? _pinOnMap(h) : _use(picked),
      // Ұзақ басса — «Үй»/«Жұмыс» етіп сақтау (тізімді белгішелермен
      // шұбарламау үшін батырма емес, ұзақ басу).
      onLongPress: h.needsPin ? null : () => _save(picked),
    );
  }

  /// Жолдардың арасына жіңішке сызық (белгішеден кейін басталады).
  List<Widget> _divided(List<Widget> rows) => [
    for (var i = 0; i < rows.length; i++) ...[
      if (i > 0) const Divider(height: 1, indent: 54, endIndent: 16),
      rows[i],
    ],
  ];

  Widget _note(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 18, 24, 6),
    child: Text(text, textAlign: TextAlign.center, style: Gz.bodyMuted),
  );

  /// Мекенжай жолы — Яндекс Go үлгісі: сұр белгіше, үстінде көше/нысан,
  /// астында «аудан, қала», оң жақта ҚАШЫҚТЫҚ («12,5 км»).
  Widget _placeRow({
    required IconData icon,
    Color iconColor = Gz.textTertiary,
    required String title,
    String? subtitle,
    String? distance,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
  }) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            Icon(icon, size: 24, color: iconColor),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.25,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.15,
                    ),
                  ),
                  if (subtitle != null && subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.3,
                        color: Gz.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (distance != null) ...[
              const SizedBox(width: 10),
              Text(
                distance,
                style: const TextStyle(
                  fontSize: 13,
                  color: Gz.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _header(IconData icon, String label) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Row(
      children: [
        Icon(icon, size: 14, color: Gz.textTertiary),
        const SizedBox(width: 7),
        Text(label.toUpperCase(), style: Gz.label),
      ],
    ),
  );

  /// Тізімнің бір жолы — БҮКІЛ жол басылады (нысана үлкен, саусақ адаспайды).
  Widget _row({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    Widget? trailing,
    bool strong = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Material(
        color: strong ? Gz.tint(Gz.green, 0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.fromLTRB(10, 10, trailing == null ? 12 : 4, 10),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Gz.tint(iconColor, 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 19, color: iconColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          height: 1.25,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.15,
                        ),
                      ),
                      if (subtitle != null && subtitle.isNotEmpty) ...[
                        const SizedBox(height: 1),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            height: 1.3,
                            color: Gz.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  ҚАЛА ТАҢДАУ (екінші деңгей — сирек ашылады)
// ═══════════════════════════════════════════════════════════════════════

class _CityPickerSheet extends StatefulWidget {
  const _CityPickerSheet();

  @override
  State<_CityPickerSheet> createState() => _CityPickerSheetState();
}

class _CityPickerSheetState extends State<_CityPickerSheet> {
  final _search = TextEditingController();
  Timer? _debounce;

  /// Дайын тізімнен сүзілген қалалар (лезде шығады).
  List<String> _filtered = kzCities;

  /// Картадан ізделген елді мекендер — тізімде ЖОҚ ауыл/кенттер
  /// (Мерке, Луговой, Ерейментау, Қосшы…). Тегін тізімге бәрін тығу мүмкін
  /// емес, сол себепті олар осылай — сұраныс бойынша табылады.
  List<GeoPlace> _found = const [];
  bool _loading = false;

  void _onChanged(String q) {
    final n = q.trim().toLowerCase();
    setState(() {
      _filtered = n.isEmpty
          ? kzCities
          : kzCities.where((c) => c.toLowerCase().contains(n)).toList();
      if (n.length < 2) {
        _found = const [];
        _loading = false;
      } else {
        _loading = true;
      }
    });
    _debounce?.cancel();
    if (n.length < 2) return;
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      final res = await Geo.searchSettlement(q);
      if (!mounted) return;
      setState(() {
        // Дайын тізімде бары қайталанбасын.
        _found = res
            .where((e) => !kzCities.any((c) => Geo.sameCity(c, e.name)))
            .toList();
        _loading = false;
      });
    });
  }

  /// Тізімдегі ірі қала — тірек қаланың өзі.
  void _pickKnown(String city) => Navigator.of(
    context,
  ).pop(CityChoice(city: city, point: Geo.cityCenter(city)));

  /// Ауыл/кент — тірек қала ретінде ЕҢ ЖАҚЫН ірі қала жазылады, ал ауылдың
  /// өз аты адрес пен картаға барады.
  void _pickSettlement(GeoPlace p) {
    final anchor = Geo.anchorCity(p.point);
    Navigator.of(context).pop(
      CityChoice(
        city: anchor ?? p.name,
        settlement: anchor == null ? null : p.name,
        point: p.point,
      ),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasQuery = _search.text.trim().length >= 2;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.92,
      builder: (context, scroll) => Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: Gz.disabledBg,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _search,
              autofocus: true,
              onChanged: _onChanged,
              decoration: InputDecoration(
                hintText: t('Қала, кент немесе ауыл іздеу…'),
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(13),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: (_filtered.isEmpty && _found.isEmpty && !_loading)
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        t(
                          'Табылмады. Атын басқаша жазып көріңіз '
                          '(мыс. орысша немесе қазақша).',
                        ),
                        textAlign: TextAlign.center,
                        style: Gz.bodyMuted,
                      ),
                    ),
                  )
                : ListView(
                    controller: scroll,
                    children: [
                      for (final c in _filtered)
                        ListTile(
                          leading: const Icon(
                            Icons.location_city_rounded,
                            color: Gz.textSecondary,
                          ),
                          title: Text(c),
                          onTap: () => _pickKnown(c),
                        ),
                      if (_found.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                          child: Text(
                            t('Кент, ауыл, шағын қалалар').toUpperCase(),
                            style: Gz.label,
                          ),
                        ),
                        for (final p in _found)
                          ListTile(
                            leading: const Icon(
                              Icons.holiday_village_rounded,
                              color: Gz.green,
                            ),
                            title: Text(p.name),
                            subtitle: Builder(
                              builder: (_) {
                                final anchor = Geo.anchorCity(p.point);
                                return Text(
                                  anchor == null
                                      ? t('Қазақстан')
                                      : '$anchor ${t('маңы')}',
                                  style: const TextStyle(fontSize: 12),
                                );
                              },
                            ),
                            onTap: () => _pickSettlement(p),
                          ),
                      ],
                      if (hasQuery && _found.isEmpty && !_loading)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                          child: Text(
                            t(
                              'Ауылыңыз тізімде жоқ па? Ең жақын қаланы '
                              'таңдаңыз да, келесі қадамда картадан дәл '
                              'жерді белгілеңіз — ауыл аты адреске өзі '
                              'қосылады.',
                            ),
                            style: Gz.bodyMuted,
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
