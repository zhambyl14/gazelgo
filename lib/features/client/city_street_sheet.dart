import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../core/geo.dart';
import '../../core/kz_cities.dart';
import '../../core/lang.dart';
import '../../core/theme.dart';
import 'address_picker.dart';

/// Адрес таңдау: қала бөлек, көше мен үй нөмірі бөлек өрісте.
/// Осылай адрес жолында тек «көше, үй нөмірі» ғана қалады, ал көше іздеу
/// таңдалған қала ішінде ғана жүреді — сол себепті ұсыныстар жазып
/// тұрған адреске сәйкес келеді.
class CityStreetSheet extends StatefulWidget {
  final String title;
  final PickedAddress? initial;
  const CityStreetSheet({super.key, required this.title, this.initial});

  static Future<PickedAddress?> show(BuildContext context,
      {required String title, PickedAddress? initial}) {
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

class _CityStreetSheetState extends State<CityStreetSheet> {
  String? _city;
  String? _street;
  LatLng? _point;
  bool _detectingCity = false;

  @override
  void initState() {
    super.initState();
    _city = widget.initial?.city;
    _street = widget.initial?.address;
    _point = widget.initial?.point;
    if (_city == null) _detectCity();
  }

  /// Өз орнының қаласын автоматты анықтайды (GPS арқылы).
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
    final (_, city) = await Geo.reverseWithCity(p);
    if (mounted) {
      setState(() {
        _city = city;
        _detectingCity = false;
      });
    }
  }

  Future<void> _pickCity() async {
    final picked = await showModalBottomSheet<String>(
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
        _city = picked;
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
          city: city, initialQuery: _street, initialPoint: _point),
    );
    if (picked != null && mounted) {
      setState(() {
        _street = picked.address;
        _point = picked.point;
        // Қаланы ЕШҚАШАН ауыстырмаймыз: пайдаланушы таңдаған қала — түпкі дереккөз.
        // (Адрес сол қала ішінде ғана ізделеді әрі картада расталады.)
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
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Gz.border, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(widget.title,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w900)),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Column(
                children: [
                  _fieldTile(
                    label: t('Қай қала/елді мекенге?'),
                    value: _detectingCity ? t('Анықталуда…') : _city,
                    onTap: _pickCity,
                  ),
                  const SizedBox(height: 10),
                  _fieldTile(
                    label: t('Үй нөмірі мен көше'),
                    value: _street,
                    onTap: _pickStreet,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: canSubmit ? _done : null,
                      child: Text(t('Дайын')),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fieldTile(
      {required String label, required String? value, required VoidCallback onTap}) {
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
                  Text(label,
                      style:
                          const TextStyle(color: Gz.textSecondary, fontSize: 12.5)),
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
                            : Gz.ink),
                  ),
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
  List<String> _filtered = kzCities;

  void _onChanged(String q) {
    final n = q.trim().toLowerCase();
    setState(() {
      _filtered = n.isEmpty
          ? kzCities
          : kzCities.where((c) => c.toLowerCase().contains(n)).toList();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                color: Gz.border, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _search,
              autofocus: true,
              onChanged: _onChanged,
              decoration: InputDecoration(
                hintText: t('Қала немесе елді мекен іздеу…'),
                prefixIcon: const Icon(Icons.search),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _filtered.isEmpty
                ? Center(
                    child: Text(t('Табылмады'),
                        style: const TextStyle(color: Gz.textSecondary)))
                : ListView.separated(
                    controller: scroll,
                    itemCount: _filtered.length,
                    separatorBuilder: (_, i) => const Divider(height: 1),
                    itemBuilder: (_, i) => ListTile(
                      leading: const Icon(Icons.location_city_outlined,
                          color: Gz.textSecondary),
                      title: Text(_filtered[i]),
                      onTap: () => Navigator.of(context).pop(_filtered[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _StreetPickerSheet extends StatefulWidget {
  final String city;
  final String? initialQuery;
  final LatLng? initialPoint;
  const _StreetPickerSheet(
      {required this.city, this.initialQuery, this.initialPoint});

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
      final res = await Geo.searchStreet(city: widget.city, street: q);
      if (mounted) {
        setState(() {
          // ЕРЕЖЕ №1: таңдалған қаладан тыс нәтижелерді МҮЛДЕ көрсетпейміз.
          // Nominatim кейде «Алматы» сұрағанда Шымкенттегі нәтиже қайтарады —
          // ол клиентке ешқашан көрінбеуі керек.
          _results = _onlySelectedCity(res);
          _loading = false;
        });
      }
    });
  }

  /// Тек таңдалған қала ішіндегі нәтижелерді қалдырады.
  /// Қаласы белгісіз (null) нәтижелерді де алып тастаймыз — басқа қалаға
  /// «жасырын» өтіп кетпеу үшін (табылмаса — картадан белгілейді).
  List<GeoPlace> _onlySelectedCity(List<GeoPlace> res) =>
      res.where((e) => Geo.sameCity(e.city, widget.city)).toList();

  /// Картадан белгіленген нүкте таңдалған қалаға сай ма (ЕРЕЖЕ №6).
  /// Қаласы анықталмаса (ауылдық жер, тегін деректе жоқ) — рұқсат етеміз.
  bool _pointInSelectedCity(PickedAddress p) {
    if (!Geo.inKazakhstan(p.point)) {
      showSnack(context, t('Тек Қазақстан ішінде'), error: true);
      return false;
    }
    if (p.city != null &&
        p.city!.isNotEmpty &&
        !Geo.sameCity(p.city, widget.city)) {
      showSnack(
          context,
          Lang.current.value == AppLang.ru
              ? 'Эта точка не в городе ${widget.city}. '
                  'Отметьте в пределах ${widget.city}.'
              : 'Бұл нүкте ${widget.city} ішінде емес. '
                  '${widget.city} шегінде белгілеңіз.',
          error: true);
      return false;
    }
    return true;
  }

  Future<void> _findOnMap() async {
    // Карта таңдалған қаланың ортасынан ашылады.
    final res = await AddressPickerScreen.pick(context,
        title: widget.city,
        initial: widget.initialPoint ?? Geo.cityCenter(widget.city));
    if (res != null && mounted) {
      if (!_pointInSelectedCity(res)) return;
      // Қаланы таңдалған қалаға бекітеміз (координата сол қалада расталды).
      Navigator.of(context)
          .pop(PickedAddress(res.address, res.point, widget.city));
    }
  }

  /// Клиент жазған адресті қолдану. Егер геокодер дәл тапса — соның нүктесін
  /// алады. Таппаса (Қазақстанда бұл жиі — тегін карта деректерінде шағын
  /// аудандар жоқ) — үнсіз қала орталығына қоймай, картаны ашып, клиенттің
  /// дәл жерді өзі белгілеуін сұраймыз (жазған адрес мәтіні сақталады).
  Future<void> _useTyped() async {
    final text = _search.text.trim();
    if (text.length < 2) return;
    // Тек таңдалған қаладағы нәтиженің нүктесін аламыз (ЕРЕЖЕ №4):
    // тізімдегі бірінші элемент басқа қала болуы мүмкін, сондықтан фильтрлеп аламыз.
    LatLng? point = _results.isNotEmpty ? _results.first.point : null;
    if (point == null) {
      setState(() => _loading = true);
      final res =
          _onlySelectedCity(await Geo.searchStreet(city: widget.city, street: text));
      point = res.isNotEmpty ? res.first.point : null;
      if (mounted) setState(() => _loading = false);
    }
    if (!mounted) return;
    if (point != null) {
      Navigator.of(context).pop(PickedAddress(text, point, widget.city));
      return;
    }
    // Қала ішінде дәл табылмады → басқа қаланы ЕШҚАШАН ұсынбаймыз,
    // тек картадан дәл жерді белгілетеміз (жазған мәтін адрес болып қалады).
    final picked = await AddressPickerScreen.pick(
      context,
      title: '${t('Картадан белгілеңіз:')} $text',
      initial: Geo.cityCenter(widget.city),
    );
    if (picked != null && mounted) {
      if (!_pointInSelectedCity(picked)) return;
      // Клиент жазған мәтінді сақтаймыз, координата — картадан дәл.
      Navigator.of(context).pop(PickedAddress(text, picked.point, widget.city));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
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
                  color: Gz.border, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text('${widget.city}: ${t('көше мен үй нөмірі')}',
                  style:
                      const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                controller: _search,
                autofocus: true,
                onChanged: _onChanged,
                decoration: InputDecoration(
                  hintText: t('мыс: Бауыржан Момышулы, 79'),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _loading
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                              width: 18,
                              height: 18,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : null,
                ),
              ),
            ),
            if (_search.text.trim().length >= 2)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: FilledButton.icon(
                  onPressed: _loading ? null : _useTyped,
                  style: FilledButton.styleFrom(
                    backgroundColor: Gz.green,
                    foregroundColor: Colors.white,
                    shadowColor: const Color(0x5916A34A),
                    minimumSize: const Size.fromHeight(50),
                    textStyle: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 14.5),
                  ),
                  icon: const Icon(Icons.add_location_alt, size: 20),
                  label: Text(
                    '${t('Осы адресті қолдану:')} «${_search.text.trim()}»',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
                    Text(t('Картадан табу'),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
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
                                  : t('Тізімнен табылмады? Жоғарыдағы «Осы адресті '
                                      'қолдану» → картадан дәл жерді белгілейсіз')),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Gz.textSecondary, fontSize: 13.5),
                        ),
                      ),
                    )
                  : ListView.separated(
                      controller: scroll,
                      itemCount: _results.length,
                      separatorBuilder: (_, i) => const Divider(height: 1),
                      itemBuilder: (_, i) => ListTile(
                        leading:
                            const Icon(Icons.place_outlined, color: Gz.red),
                        title: Text(_results[i].name,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        // Қала әрдайым таңдалған қала болып қалады (нәтиже
                        // онсыз да сол қала ішінен фильтрленген).
                        onTap: () => Navigator.of(context).pop(PickedAddress(
                            _results[i].name, _results[i].point, widget.city)),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
