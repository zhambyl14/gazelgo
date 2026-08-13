import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../core/geo.dart';
import '../../core/kz_cities.dart';
import '../../core/lang.dart';
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
  const CityStreetSheet({super.key, required this.title, this.initial});

  static Future<PickedAddress?> show(
    BuildContext context, {
    required String title,
    PickedAddress? initial,
  }) {
    return showModalBottomSheet<PickedAddress>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Gz.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (_) => CityStreetSheet(title: title, initial: initial),
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
  List<GeoPlace> _results = const [];
  bool _loading = false;

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
      _search.selection = TextSelection(baseOffset: 0, extentOffset: init.length);
    }
    _detectCity();
    _loadBook();
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
    final recent =
        r.where((e) => !savedKeys.contains(key(e.address, e.city))).toList();
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
      _myPlace = PickedAddress(addr.labelFor(city), p, city);
      _detectingCity = false;
    });
  }

  LatLng? get _center => _cityPoint ?? Geo.cityCenter(_city);

  // ═══════════════════════════════════════════════════════════════════
  //  ІЗДЕУ
  // ═══════════════════════════════════════════════════════════════════

  void _onChanged(String q) {
    _debounce?.cancel();
    final n = q.trim();
    if (n.length < 2) {
      setState(() {
        _results = const [];
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    // Тегін Nominatim — әр таңбада сұрау жіберуге болмайды.
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      final city = _city;
      if (city == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final res =
          await Geo.searchStreet(city: city, street: n, near: _cityPoint);
      if (!mounted) return;
      setState(() {
        _results = _inSelectedArea(res);
        _loading = false;
      });
    });
  }

  /// Нүкте таңдалған қаланың аймағында ма ([Geo.inCityArea] ережесі).
  bool _pointInArea(LatLng p) => Geo.inCityArea(p, _city, center: _center);

  /// Таңдалған қала мен оның маңындағы нәтижелерді ғана қалдырады.
  /// (Бұрын дәл қала аты талап етілетін — сондықтан «Луговой, Абая» деп
  /// іздегенде тізім әрқашан бос болатын.)
  List<GeoPlace> _inSelectedArea(List<GeoPlace> res) => res
      .where((e) => Geo.sameCity(e.city, _city) || _pointInArea(e.point))
      .toList();

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
    final where = (settlement != null &&
            settlement.isNotEmpty &&
            !Geo.sameCity(settlement, suggested))
        ? '$settlement ($suggested)'
        : suggested;
    return showDialog<_AreaAnswer>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ru ? 'Другой регион' : 'Басқа аймақ'),
        content: Text(
          ru
              ? 'Отмеченная точка находится в: $where, '
                  'а выбранный город — $label.\n\n'
                  'К какому городу отнести заказ? '
                  'Точка на карте сохранится в любом случае.'
              : 'Белгіленген нүкте — $where, ал таңдалған қала — '
                  '$label.\n\n'
                  'Тапсырыс қай қалаға тіркелсін? '
                  'Картадағы нүкте екі жағдайда да сақталады.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_AreaAnswer.remark),
            child: Text(ru ? 'Отметить заново' : 'Қайта белгілеу'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_AreaAnswer.keepCity),
            child: Text(label),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(_AreaAnswer.switchCity),
            child: Text(suggested),
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
    final picked = await showModalBottomSheet<CityChoice>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Gz.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
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
    // Терілген мәтін болса — жаңа қала бойынша қайта іздейміз.
    if (_search.text.trim().length >= 2) _onChanged(_search.text);
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

  /// Клиент жазған мәтінді адрес ретінде қолдану. Геокодер дәл тапса —
  /// соның нүктесін алады; таппаса (Қазақстанда бұл жиі — тегін карта
  /// деректерінде шағын аудандар жоқ) картаны ашып, дәл жерді клиенттің
  /// өзі белгілейді (жазған мәтіні сақталады).
  Future<void> _useTyped() async {
    final text = _search.text.trim();
    final city = _city;
    if (text.length < 2 || city == null) return;
    LatLng? point = _results.isNotEmpty ? _results.first.point : null;
    if (point == null) {
      setState(() => _loading = true);
      final res = _inSelectedArea(
        await Geo.searchStreet(city: city, street: text, near: _cityPoint),
      );
      point = res.isNotEmpty ? res.first.point : null;
      if (mounted) setState(() => _loading = false);
    }
    if (!mounted) return;
    if (point != null) {
      Navigator.of(context).pop(PickedAddress(text, point, city));
      return;
    }
    // Аймақ ішінен дәл табылмады → басқа облысты ЕШҚАШАН ұсынбаймыз,
    // тек картадан дәл жерді белгілетеміз (жазған мәтін адрес болып қалады).
    final picked = await AddressPickerScreen.pick(
      context,
      title: '${t('Картадан белгілеңіз:')} $text',
      city: city,
      initial: _center,
    );
    if (picked == null || !mounted) return;
    await _use(PickedAddress(text, picked.point, picked.city));
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
                  borderRadius: BorderRadius.circular(3),
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
                  onSubmitted: (_) => _useTyped(),
                  decoration: InputDecoration(
                    hintText: t('Көше, үй нөмірі не нысан аты'),
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
                        : (query.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.clear_rounded),
                                onPressed: () {
                                  _search.clear();
                                  setState(() => _results = const []);
                                },
                              )),
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
                  color: unknown ? Gz.tint(Gz.red, 0.35) : Gz.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.location_city_rounded,
                    size: 16, color: unknown ? Gz.red : Gz.textSecondary),
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: Gz.tint(Gz.blue, 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _city!,
                      style: const TextStyle(
                        fontSize: 10.5,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                        color: Gz.blue,
                      ),
                    ),
                  ),
                ],
                const Icon(Icons.expand_more_rounded,
                    size: 18, color: Gz.textSecondary),
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
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      children: [
        if (my != null)
          _row(
            icon: Icons.my_location_rounded,
            iconColor: Gz.green,
            title: t('Менің орным'),
            subtitle: my.address,
            onTap: () => _useDirect(my),
          ),
        if (_saved.isNotEmpty) ...[
          _header(Icons.bookmark_rounded, t('Сақталған')),
          for (final a in _saved)
            _row(
              icon: a.isPrimary ? Icons.star_rounded : savedAddressIcon(a.kind),
              iconColor: a.isPrimary ? Gz.yellowDark : Gz.ink,
              title: savedAddressTitle(a),
              subtitle: a.address,
              onTap: () => _useDirect(a.toPicked()),
            ),
        ],
        if (_recent.isNotEmpty) ...[
          _header(Icons.history_rounded, t('Соңғы мекенжайлар')),
          for (final p in _recent)
            _row(
              icon: Icons.history_rounded,
              iconColor: Gz.textSecondary,
              title: p.address,
              subtitle: p.city,
              onTap: () => _useDirect(p),
            ),
        ],
        const SizedBox(height: 4),
        _mapRow(),
        if (my == null && _saved.isEmpty && _recent.isEmpty) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: Text(
              t('Мекенжайды жазып іздеңіз — мыс. «Абая 15» немесе «Хан '
                  'Шатыр». Не болмаса картадан дәл жерді белгілеңіз.'),
              textAlign: TextAlign.center,
              style: Gz.bodyMuted,
            ),
          ),
        ],
      ],
    );
  }

  // ── ІЗДЕУ НӘТИЖЕЛЕРІ ───────────────────────────────────────────────
  Widget _resultList(String query) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      children: [
        for (final r in _results) _resultRow(r),
        if (_results.isEmpty && !_loading) ...[
          // Тұйыққа тірелмеу керек: табылмаса да ЕКІ жол ашық қалады —
          // жазғанын сол күйі қолдану немесе картадан белгілеу.
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Text(
              t('Тізімнен табылмады. Жазғаныңызды сол күйі қолдансаңыз, '
                  'картадан дәл жерді белгілейсіз.'),
              textAlign: TextAlign.center,
              style: Gz.bodyMuted,
            ),
          ),
        ],
        // «Жазғанымды қолдану» — ӘРҚАШАН қолжетімді (тізім бос болса да,
        // толы болса да): геокодер Қазақстандағы шағын аудандарды жиі
        // танымайды, ал клиент өз адресін өзі жақсы біледі.
        _row(
          icon: Icons.edit_location_alt_rounded,
          iconColor: Gz.green,
          title: '${t('Осыны қолдану')}: «$query»',
          subtitle: t('Картадан дәл жерін белгілейсіз'),
          onTap: _useTyped,
          strong: true,
        ),
        _mapRow(),
      ],
    );
  }

  Widget _resultRow(GeoPlace r) {
    // Нәтиже қала маңындағы ауылда болса, ауыл атын адреске ҚОСАМЫЗ —
    // орындаушы қайда баратынын адрестің өзінен көруі керек.
    final other =
        r.city != null && r.city!.isNotEmpty && !Geo.sameCity(r.city, _city);
    final label = other ? '${r.city}, ${r.name}' : r.name;
    final picked = PickedAddress(label, r.point, _city);
    return _row(
      icon: Icons.place_rounded,
      iconColor: Gz.red,
      title: label,
      subtitle: other ? r.city : null,
      onTap: () => _use(picked),
      // Жаңа мекенжайды таңдамай-ақ «Үй»/«Жұмыс» етіп сақтауға болады.
      trailing: IconButton(
        tooltip: t('Сақтау'),
        onPressed: () => _save(picked),
        icon: const Icon(Icons.bookmark_add_outlined,
            size: 19, color: Gz.textTertiary),
      ),
    );
  }

  Widget _mapRow() => _row(
        icon: Icons.map_rounded,
        iconColor: Gz.blue,
        title: t('Картадан белгілеу'),
        subtitle: t('Пинді дәл керек жерге апарасыз'),
        onTap: _findOnMap,
      );

  Widget _header(IconData icon, String label) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
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
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.5,
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
  void _pickKnown(String city) => Navigator.of(context).pop(
        CityChoice(city: city, point: Geo.cityCenter(city)),
      );

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
              borderRadius: BorderRadius.circular(3),
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
                        t('Табылмады. Атын басқаша жазып көріңіз '
                            '(мыс. орысша немесе қазақша).'),
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
                            t('Ауылыңыз тізімде жоқ па? Ең жақын қаланы '
                                'таңдаңыз да, келесі қадамда картадан дәл '
                                'жерді белгілеңіз — ауыл аты адреске өзі '
                                'қосылады.'),
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
