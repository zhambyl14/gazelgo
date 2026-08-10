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

/// Адрес таңдау: қала бөлек, көше мен үй нөмірі бөлек өрісте.
/// Осылай адрес жолында тек «көше, үй нөмірі» ғана қалады, ал көше іздеу
/// таңдалған қала ішінде ғана жүреді — сол себепті ұсыныстар жазып
/// тұрған адреске сәйкес келеді.
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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

class _CityStreetSheetState extends State<CityStreetSheet> {
  String? _city;

  /// Тірек қаладан бөлек нақты елді мекен (болса).
  String? _area;

  /// Іздеу мен картаны бағыттайтын орталық (ауыл таңдалса — ауылдың ортасы).
  LatLng? _cityPoint;

  String? _street;
  LatLng? _point;
  bool _detectingCity = false;

  // Сақталған + соңғы мекенжайлар (жылдам таңдау үшін).
  List<SavedAddress> _saved = [];
  List<PickedAddress> _recent = [];

  @override
  void initState() {
    super.initState();
    _city = widget.initial?.city;
    _street = widget.initial?.address;
    _point = widget.initial?.point;
    if (_city == null) _detectCity();
    _loadBook();
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

  /// Ағымдағы (қала + көше + нүкте толық) мекенжайды сақтауға ұсынады.
  Future<void> _saveCurrent() async {
    final city = _city, street = _street, point = _point;
    if (city == null || street == null || point == null) return;
    final ok = await showSaveAddressSheet(
      context,
      place: PickedAddress(street, point, city),
    );
    if (!ok) return;
    await _loadBook();
    if (mounted) showSnack(context, t('Мекенжай сақталды'));
  }

  /// Өз орнының қаласын автоматты анықтайды (GPS арқылы).
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
    final (_, settlement) = await Geo.reverseWithCity(p);
    if (!mounted) return;
    final anchor = Geo.anchorCity(p) ?? settlement;
    setState(() {
      _city = anchor;
      _area = (settlement != null && !Geo.sameCity(settlement, anchor))
          ? settlement
          : null;
      _cityPoint = p;
      _detectingCity = false;
    });
  }

  Future<void> _pickCity() async {
    final picked = await showModalBottomSheet<CityChoice>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Gz.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _CityPickerSheet(),
    );
    if (picked != null && mounted) {
      setState(() {
        _city = picked.city;
        _area = picked.settlement;
        _cityPoint = picked.point ?? Geo.cityCenter(picked.city);
        // қала өзгерсе, бұрын таңдалған нүкте басқа қалаға тиесілі болуы мүмкін
        _street = null;
        _point = null;
      });
    }
  }

  Future<void> _pickStreet() async {
    final city = _city;
    if (city == null) {
      await _pickCity();
      return;
    }
    if (!mounted) return;
    final picked = await showModalBottomSheet<PickedAddress>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Gz.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _StreetPickerSheet(
        city: city,
        cityLabel: _area ?? city,
        cityPoint: _cityPoint ?? Geo.cityCenter(city),
        initialQuery: _street,
        initialPoint: _point,
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _street = picked.address;
        _point = picked.point;
        // Клиент картадан МҮЛДЕМ басқа аймақты белгілеп, қаланы ауыстыруға
        // келіскен болса ғана тірек қала өзгереді (парақ соны қайтарады).
        final returned = picked.city;
        if (returned != null &&
            returned.isNotEmpty &&
            !Geo.sameCity(returned, city)) {
          _city = returned;
          _area = null;
          _cityPoint = Geo.cityCenter(returned) ?? picked.point;
        }
      });
    }
  }

  void _done() {
    final city = _city;
    final street = _street;
    final point = _point;
    if (city == null || street == null || point == null) return;
    Navigator.of(context).pop(PickedAddress(street, point, city));
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = _city != null && _street != null && _point != null;
    final maxH = MediaQuery.of(context).size.height * 0.9;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Gz.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_saved.isNotEmpty || _recent.isNotEmpty) ...[
                        _quickPick(),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Expanded(child: Divider()),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              child: Text(
                                t('немесе жаңа мекенжай'),
                                style: const TextStyle(
                                  color: Gz.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const Expanded(child: Divider()),
                          ],
                        ),
                        const SizedBox(height: 10),
                      ],
                      _fieldTile(
                        label: t('Қай қала/елді мекенге?'),
                        value: _detectingCity
                            ? t('Анықталуда…')
                            : (_area ?? _city),
                        // Ауыл/кент таңдалса, заказ қай қалаға тіркелетінін
                        // ашық жазамыз — клиент «неге Тараз?» деп таңданбауы
                        // үшін (орындаушылар сол қаладан келеді).
                        hint: _area == null
                            ? null
                            : '${t('Тапсырыс тіркелетін қала:')} $_city',
                        onTap: _pickCity,
                      ),
                      const SizedBox(height: 10),
                      _fieldTile(
                        label: t('Үй нөмірі мен көше'),
                        value: _street,
                        onTap: _pickStreet,
                      ),
                      if (canSubmit) ...[
                        const SizedBox(height: 4),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: _saveCurrent,
                            icon: const Icon(
                              Icons.bookmark_add_outlined,
                              size: 18,
                            ),
                            label: Text(t('Осы мекенжайды сақтау')),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: canSubmit ? _done : null,
                    child: Text(t('Дайын')),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Сақталған (чиптер) + соңғы (тізім) мекенжайлар — бір рет түртіп таңдау.
  Widget _quickPick() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_saved.isNotEmpty) ...[
          _quickHeader(Icons.bookmark_rounded, t('Сақталған')),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final a in _saved) _savedChip(a)],
          ),
          const SizedBox(height: 12),
        ],
        if (_recent.isNotEmpty) ...[
          _quickHeader(Icons.history_rounded, t('Соңғы')),
          const SizedBox(height: 2),
          for (final p in _recent) _recentRow(p),
        ],
      ],
    );
  }

  Widget _quickHeader(IconData icon, String label) => Row(
    children: [
      Icon(icon, size: 15, color: Gz.textSecondary),
      const SizedBox(width: 6),
      Text(
        label,
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 12.5,
          color: Gz.textSecondary,
        ),
      ),
    ],
  );

  Widget _savedChip(SavedAddress a) {
    return InkWell(
      onTap: () => Navigator.of(context).pop(a.toPicked()),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: Gz.bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: a.isPrimary ? Gz.yellowDark : Gz.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              a.isPrimary ? Icons.star_rounded : savedAddressIcon(a.kind),
              size: 17,
              color: a.isPrimary ? Gz.yellowDark : Gz.ink,
            ),
            const SizedBox(width: 7),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  savedAddressTitle(a),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 170),
                  child: Text(
                    a.address,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Gz.textSecondary,
                      fontSize: 11.5,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _recentRow(PickedAddress p) {
    return InkWell(
      onTap: () => Navigator.of(context).pop(p),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            const Icon(
              Icons.history_rounded,
              size: 18,
              color: Gz.textSecondary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                p.city != null && p.city!.isNotEmpty
                    ? '${p.address} · ${p.city}'
                    : p.address,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Icon(
              Icons.north_west_rounded,
              size: 15,
              color: Gz.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _fieldTile({
    required String label,
    required String? value,
    required VoidCallback onTap,
    String? hint,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Gz.bg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Gz.textSecondary,
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value == null || value.isEmpty ? '—' : value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      color: value == null || value.isEmpty
                          ? Gz.textSecondary
                          : Gz.ink,
                    ),
                  ),
                  if (hint != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      hint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Gz.blue,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Gz.textSecondary),
          ],
        ),
      ),
    );
  }
}

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
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.92,
      builder: (context, scroll) => Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Gz.border,
              borderRadius: BorderRadius.circular(2),
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
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
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
                        style: const TextStyle(color: Gz.textSecondary),
                      ),
                    ),
                  )
                : ListView(
                    controller: scroll,
                    children: [
                      for (final c in _filtered)
                        ListTile(
                          leading: const Icon(
                            Icons.location_city_outlined,
                            color: Gz.textSecondary,
                          ),
                          title: Text(c),
                          onTap: () => _pickKnown(c),
                        ),
                      if (_found.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                          child: Text(
                            t('Кент, ауыл, шағын қалалар'),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: Gz.textSecondary,
                            ),
                          ),
                        ),
                        for (final p in _found)
                          ListTile(
                            leading: const Icon(
                              Icons.holiday_village_outlined,
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
                            style: const TextStyle(
                              color: Gz.textSecondary,
                              fontSize: 12.5,
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

/// Нүкте басқа аймақта болғандағы клиенттің жауабы.
enum _AreaAnswer {
  /// Тапсырыс ұсынылған тірек қалаға тіркелсін.
  switchCity,

  /// Таңдалған қала қалсын (әкімшілік жағынан дұрысын клиент біледі).
  keepCity,

  /// Картадан қайта белгілеймін.
  remark,
}

class _StreetPickerSheet extends StatefulWidget {
  /// Тірек қала — заказға жазылатын қала.
  final String city;

  /// Клиентке көрсетілетін атау (ауыл таңдалса — ауылдың аты).
  final String cityLabel;

  /// Іздеу мен картаның орталығы.
  final LatLng? cityPoint;

  final String? initialQuery;
  final LatLng? initialPoint;
  const _StreetPickerSheet({
    required this.city,
    required this.cityLabel,
    this.cityPoint,
    this.initialQuery,
    this.initialPoint,
  });

  @override
  State<_StreetPickerSheet> createState() => _StreetPickerSheetState();
}

class _StreetPickerSheetState extends State<_StreetPickerSheet> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<GeoPlace> _results = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery != null) _search.text = widget.initialQuery!;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) {
      setState(() => _results = []);
      return;
    }
    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      final res = await Geo.searchStreet(
        city: widget.city,
        street: q,
        near: widget.cityPoint,
      );
      if (mounted) {
        setState(() {
          _results = _inSelectedArea(res);
          _loading = false;
        });
      }
    });
  }

  LatLng? get _center => widget.cityPoint ?? Geo.cityCenter(widget.city);

  /// Нүкте таңдалған қаланың аймағында ма ([Geo.inCityArea] ережесі).
  bool _pointInArea(LatLng p) =>
      Geo.inCityArea(p, widget.city, center: _center);

  /// Таңдалған қала мен оның маңындағы нәтижелерді ғана қалдырады.
  /// (Бұрын дәл қала аты талап етілетін — сондықтан «Луговой, Абая» деп
  /// іздегенде тізім әрқашан бос болатын.)
  List<GeoPlace> _inSelectedArea(List<GeoPlace> res) => res
      .where((e) => Geo.sameCity(e.city, widget.city) || _pointInArea(e.point))
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

  /// Картадан белгіленген нүктені ҚАБЫЛДАУ.
  ///
  /// БҰРЫН: нүктенің елді мекені таңдалған қаладан өзгеше болса — қатемен
  /// қайтарылатын. Сол себепті Астананы таңдап Ерейментауды, Таразды таңдап
  /// Мерке/Луговойды белгілеу МҮЛДЕМ мүмкін емес еді — ал клиенттердің
  /// үлкен бөлігі дәл сол қала маңындағы елді мекендерде тұрады.
  ///
  /// ЕНДІ нүкте ЕШҚАШАН жоғалмайды:
  ///  • Қала аймағында (≤ [_areaRadiusKm]) — үнсіз қабылданады, ауыл аты
  ///    адрес жолына қосылып қойған болады.
  ///  • Мүлдем басқа аймақта — қаланы ауыстыруды сұраймыз (қате таңдау болуы
  ///    ықтимал), клиент келіссе жаңа қаламен қайтарамыз.
  Future<PickedAddress?> _accept(PickedAddress p) async {
    if (!Geo.inKazakhstan(p.point)) {
      showSnack(context, t('Тек Қазақстан ішінде'), error: true);
      return null;
    }
    if (_pointInArea(p.point)) {
      return PickedAddress(p.address, p.point, widget.city);
    }
    final suggested = Geo.anchorCity(p.point) ?? p.city;
    if (suggested == null ||
        Geo.sameCity(suggested, widget.city) ||
        !mounted) {
      // Тірек қала табылмады (шалғай жер) не сол қаланың өзі — нүктені
      // сұраусыз қабылдаймыз.
      return PickedAddress(p.address, p.point, widget.city);
    }
    switch (await _askSwitchCity(suggested, p.city)) {
      case _AreaAnswer.switchCity:
        return PickedAddress(
          _stripCityPrefix(p.address, suggested),
          p.point,
          suggested,
        );
      case _AreaAnswer.keepCity:
        return PickedAddress(p.address, p.point, widget.city);
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
                  'а выбранный город — ${widget.cityLabel}.\n\n'
                  'К какому городу отнести заказ? '
                  'Точка на карте сохранится в любом случае.'
              : 'Белгіленген нүкте — $where, ал таңдалған қала — '
                  '${widget.cityLabel}.\n\n'
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
            child: Text(widget.cityLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(_AreaAnswer.switchCity),
            child: Text(suggested),
          ),
        ],
      ),
    );
  }

  Future<void> _findOnMap() async {
    // Карта таңдалған қаланың (не ауылдың) ортасынан ашылады.
    final res = await AddressPickerScreen.pick(
      context,
      title: widget.cityLabel,
      city: widget.city,
      initial: widget.initialPoint ?? _center,
    );
    if (res == null || !mounted) return;
    final accepted = await _accept(res);
    if (accepted != null && mounted) Navigator.of(context).pop(accepted);
  }

  /// Клиент жазған адресті қолдану. Егер геокодер дәл тапса — соның нүктесін
  /// алады. Таппаса (Қазақстанда бұл жиі — тегін карта деректерінде шағын
  /// аудандар жоқ) — үнсіз қала орталығына қоймай, картаны ашып, клиенттің
  /// дәл жерді өзі белгілеуін сұраймыз (жазған адрес мәтіні сақталады).
  Future<void> _useTyped() async {
    final text = _search.text.trim();
    if (text.length < 2) return;
    // Тек таңдалған қала мен оның маңындағы нәтиженің нүктесін аламыз:
    // тізімдегі бірінші элемент басқа облыс болуы мүмкін.
    LatLng? point = _results.isNotEmpty ? _results.first.point : null;
    if (point == null) {
      setState(() => _loading = true);
      final res = _inSelectedArea(
        await Geo.searchStreet(
          city: widget.city,
          street: text,
          near: widget.cityPoint,
        ),
      );
      point = res.isNotEmpty ? res.first.point : null;
      if (mounted) setState(() => _loading = false);
    }
    if (!mounted) return;
    if (point != null) {
      Navigator.of(context).pop(PickedAddress(text, point, widget.city));
      return;
    }
    // Аймақ ішінен дәл табылмады → басқа облысты ЕШҚАШАН ұсынбаймыз,
    // тек картадан дәл жерді белгілетеміз (жазған мәтін адрес болып қалады).
    final picked = await AddressPickerScreen.pick(
      context,
      title: '${t('Картадан белгілеңіз:')} $text',
      city: widget.city,
      initial: _center,
    );
    if (picked == null || !mounted) return;
    // Клиент жазған мәтінді сақтаймыз, координата — картадан дәл.
    final accepted = await _accept(PickedAddress(text, picked.point, picked.city));
    if (accepted != null && mounted) Navigator.of(context).pop(accepted);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scroll) => Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Gz.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                '${widget.cityLabel}: ${t('көше, үй немесе нысан аты')}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                controller: _search,
                autofocus: true,
                onChanged: _onChanged,
                decoration: InputDecoration(
                  hintText: t('мыс: Бауыржан Момышулы 79 немесе «Хан Шатыр»'),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _loading
                      ? const Padding(
                          padding: EdgeInsets.all(12),
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
            if (_search.text.trim().length >= 2)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: FilledButton.icon(
                  onPressed: _loading ? null : _useTyped,
                  style: FilledButton.styleFrom(
                    backgroundColor: Gz.green,
                    foregroundColor: Colors.white,
                    shadowColor: const Color(0x5916A34A),
                    minimumSize: const Size.fromHeight(50),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14.5,
                    ),
                  ),
                  icon: const Icon(Icons.add_location_alt, size: 20),
                  // Жазуға қолданушы жазған мәтін кіреді — ұзындығы белгісіз.
                  // Бұрын «…» болып ҚИЫЛАТЫН (адрестің өзі көрінбей қалатын),
                  // енді сыймаса кішірейеді.
                  label: BtnLabel(
                    '${t('Осы адресті қолдану:')} «${_search.text.trim()}»',
                  ),
                ),
              ),
            InkWell(
              onTap: _findOnMap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.map_outlined, size: 20, color: Gz.ink),
                    const SizedBox(width: 8),
                    Text(
                      t('Картадан табу'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _results.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _search.text.trim().length < 2
                              ? t('Көше мен үй нөмірін жазыңыз')
                              : (_loading
                                    ? ''
                                    : t(
                                        'Тізімнен табылмады? Жоғарыдағы «Осы адресті '
                                        'қолдану» → картадан дәл жерді белгілейсіз',
                                      )),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Gz.textSecondary,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      controller: scroll,
                      itemCount: _results.length,
                      separatorBuilder: (_, i) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final r = _results[i];
                        // Нәтиже қала маңындағы ауылда болса, ауыл атын
                        // адреске ҚОСАМЫЗ — орындаушы қайда баратынын
                        // адрестің өзінен көруі керек.
                        final other = r.city != null &&
                            r.city!.isNotEmpty &&
                            !Geo.sameCity(r.city, widget.city);
                        final label = other ? '${r.city}, ${r.name}' : r.name;
                        return ListTile(
                          leading: const Icon(
                            Icons.place_outlined,
                            color: Gz.red,
                          ),
                          title: Text(
                            label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          // Тірек қала өзгермейді: нәтиже сол қаланың
                          // аймағынан сүзілген.
                          onTap: () => Navigator.of(context).pop(
                            PickedAddress(label, r.point, widget.city),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
