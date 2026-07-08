import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../core/geo.dart';
import '../../core/kz_cities.dart';
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
        // карта арқылы басқа қалаға ауысып кетсе — қаланы да сәйкестендіреміз
        if (picked.city != null && picked.city!.isNotEmpty) {
          _city = picked.city;
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
                    label: 'Қай қала/елді мекенге?',
                    value: _detectingCity ? 'Анықталуда…' : _city,
                    onTap: _pickCity,
                  ),
                  const SizedBox(height: 10),
                  _fieldTile(
                    label: 'Үй нөмірі мен көше',
                    value: _street,
                    onTap: _pickStreet,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: canSubmit ? _done : null,
                      child: const Text('Дайын'),
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
              decoration: const InputDecoration(
                hintText: 'Қала немесе елді мекен іздеу…',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _filtered.isEmpty
                ? const Center(
                    child: Text('Табылмады',
                        style: TextStyle(color: Gz.textSecondary)))
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
          _results = res;
          _loading = false;
        });
      }
    });
  }

  Future<void> _findOnMap() async {
    final res = await AddressPickerScreen.pick(context,
        title: widget.city, initial: widget.initialPoint);
    if (res != null && mounted) {
      if (!Geo.inKazakhstan(res.point)) {
        showSnack(context, 'Тек Қазақстан ішінде', error: true);
        return;
      }
      Navigator.of(context).pop(res);
    }
  }

  /// Клиент жазған адресті қолдану. Егер геокодер дәл тапса — соның нүктесін
  /// алады. Таппаса (Қазақстанда бұл жиі — тегін карта деректерінде шағын
  /// аудандар жоқ) — үнсіз қала орталығына қоймай, картаны ашып, клиенттің
  /// дәл жерді өзі белгілеуін сұраймыз (жазған адрес мәтіні сақталады).
  Future<void> _useTyped() async {
    final text = _search.text.trim();
    if (text.length < 2) return;
    LatLng? point = _results.isNotEmpty ? _results.first.point : null;
    if (point == null) {
      setState(() => _loading = true);
      final res = await Geo.searchStreet(city: widget.city, street: text);
      point = res.isNotEmpty ? res.first.point : null;
      if (mounted) setState(() => _loading = false);
    }
    if (!mounted) return;
    if (point != null) {
      Navigator.of(context).pop(PickedAddress(text, point, widget.city));
      return;
    }
    // Дәл табылмады → картадан белгілету (жазған мәтін адрес болып қалады)
    final picked = await AddressPickerScreen.pick(
      context,
      title: 'Картадан белгілеңіз: $text',
      initial: Geo.cityCenter(widget.city),
    );
    if (picked != null && mounted) {
      if (!Geo.inKazakhstan(picked.point)) {
        showSnack(context, 'Тек Қазақстан ішінде', error: true);
        return;
      }
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
              child: Text('${widget.city}: көше мен үй нөмірі',
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
                  hintText: 'мыс: Бауыржан Момышулы, 79',
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
              InkWell(
                onTap: _loading ? null : _useTyped,
                child: Container(
                  color: Gz.green.withValues(alpha: 0.08),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                  child: Row(
                    children: [
                      const Icon(Icons.add_location_alt_outlined,
                          size: 20, color: Gz.green),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            style: const TextStyle(
                                color: Gz.ink, fontSize: 13.5),
                            children: [
                              const TextSpan(text: 'Осы адресті қолдану: '),
                              TextSpan(
                                text: '«${_search.text.trim()}»',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Icon(Icons.chevron_right,
                          size: 20, color: Gz.textSecondary),
                    ],
                  ),
                ),
              ),
            InkWell(
              onTap: _findOnMap,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.map_outlined, size: 20, color: Gz.ink),
                    SizedBox(width: 8),
                    Text('Картадан табу',
                        style: TextStyle(fontWeight: FontWeight.w700)),
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
                              ? 'Көше мен үй нөмірін жазыңыз'
                              : (_loading
                                  ? ''
                                  : 'Тізімнен табылмады? Жоғарыдағы «Осы адресті '
                                      'қолдану» → картадан дәл жерді белгілейсіз'),
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
                        onTap: () => Navigator.of(context).pop(
                            PickedAddress(_results[i].name, _results[i].point,
                                _results[i].city ?? widget.city)),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
