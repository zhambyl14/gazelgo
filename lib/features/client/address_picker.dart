import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/geo.dart';
import '../../core/lang.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/map_widgets.dart';

class PickedAddress {
  final String address;
  final LatLng point;
  final String? city;
  PickedAddress(this.address, this.point, [this.city]);
}

/// Картадан немесе іздеу арқылы адрес таңдау экраны.
class AddressPickerScreen extends StatefulWidget {
  final String title;
  final LatLng? initial;

  /// Клиент таңдаған қала. Адрес жолында осы қаланың аты ҚАЙТАЛАНБАЙДЫ, ал
  /// нүкте басқа елді мекенде болса (Ерейментау, Мерке, Луговой…) — сол елді
  /// мекеннің аты адреске МІНДЕТТІ түрде қосылады.
  final String? city;

  const AddressPickerScreen({
    super.key,
    required this.title,
    this.initial,
    this.city,
  });

  static Future<PickedAddress?> pick(BuildContext context,
      {required String title, LatLng? initial, String? city}) {
    return Navigator.of(context).push<PickedAddress>(
      MaterialPageRoute(
          builder: (_) =>
              AddressPickerScreen(title: title, initial: initial, city: city)),
    );
  }

  @override
  State<AddressPickerScreen> createState() => _AddressPickerScreenState();
}

class _AddressPickerScreenState extends State<AddressPickerScreen> {
  final _map = MapController();
  final _search = TextEditingController();
  final _addr = TextEditingController(); // редакцияланатын мекенжай аты
  Timer? _debounce;
  Timer? _moveDebounce;
  List<GeoPlace> _results = [];
  String _rawAddress = ''; // геокодер қайтарған «шикі» атау (түзетуді анықтау үшін)
  bool _corrected = false; // маңайдағы клиент түзетуі қолданылды ма
  String? _centerCity;
  LatLng _center = Geo.almaty;
  bool _resolving = false;

  /// Маңайдағы аты бар нысандар (ТРЦ, ЖК, базар…) — «мынау ма?» ұсынысы.
  List<GeoPlace> _nearby = const [];

  /// Адрес жолын клиент ӨЗІ таңдады/жазды ма. Rasa болса, картаның жылжуы
  /// (мыс. іздеуден кейінгі анимация) reverse-геокодтауды іске қосып, клиент
  /// таңдаған ТРЦ атын қайтадан «жәй ғана көшеге» ауыстырып жіберетін.
  bool _addrLocked = false;

  @override
  void initState() {
    super.initState();
    _center = widget.initial ?? Geo.almaty;
    _resolveCenter();
    if (widget.initial == null) _goToMyLocation();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _moveDebounce?.cancel();
    _search.dispose();
    _addr.dispose();
    super.dispose();
  }

  Future<void> _goToMyLocation() async {
    final pos = await Geo.currentPosition();
    if (pos != null && mounted) {
      final p = LatLng(pos.latitude, pos.longitude);
      _map.move(p, 16);
      _center = p;
      _addrLocked = false;
      _resolveCenter();
    }
  }

  Future<void> _resolveCenter() async {
    final target = _center;
    setState(() => _resolving = true);
    final addr = await Geo.reverseDetailed(target);
    // Осы маңда клиенттер бұрын түзеткен атау бар ма?
    final corr = await Repo.nearbyAddress(target.latitude, target.longitude);
    if (!mounted || target != _center) return;
    final label = addr.labelFor(widget.city);
    setState(() {
      _rawAddress = label;
      _centerCity = addr.settlement;
      _corrected = corr != null;
      if (!_addrLocked) _addr.text = corr ?? label;
      _resolving = false;
    });
    // Маңайдағы нысандар — баяу әрі міндетті емес, сол себепті бөлек әрі
    // адрес шыққаннан КЕЙІН жүктеледі (экран қатып қалмауы үшін).
    final near = await Geo.nearbyPlaces(target);
    if (mounted && target == _center) setState(() => _nearby = near);
  }

  void _confirmSave() {
    final label = _addr.text.trim().isEmpty ? _rawAddress : _addr.text.trim();
    // Клиент атын түзеткен болса — сол координатаға сақтаймыз (кейін ұсыну үшін).
    // Мәтінді қайта геокодтамаймыз: нүкте — картаның нақ ортасы.
    if (label.isNotEmpty && label != _rawAddress) {
      Repo.saveAddressCorrection(_center.latitude, _center.longitude, label);
    }
    Navigator.of(context).pop(PickedAddress(label, _center, _centerCity));
  }

  void _onSearchChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      final res = await Geo.search(q);
      if (mounted) setState(() => _results = res);
    });
  }

  void _selectPlace(GeoPlace p) {
    FocusScope.of(context).unfocus();
    setState(() {
      _results = [];
      _search.text = p.name;
      _center = p.point;
      _rawAddress = p.name;
      _corrected = false;
      _addr.text = p.name;
      _addrLocked = true;
      _centerCity = p.city;
      _nearby = const [];
    });
    _map.move(p.point, 16.5);
  }

  /// Маңайдағы нысанды таңдау: пин сол нысанның дәл ортасына көшеді, ал адрес
  /// жолы «ТРЦ аты, көше, үй» болып жазылады.
  void _selectNearby(GeoPlace p) {
    FocusScope.of(context).unfocus();
    final settlement = _centerCity;
    final needsSettlement = settlement != null &&
        settlement.isNotEmpty &&
        !Geo.sameCity(settlement, widget.city);
    setState(() {
      _center = p.point;
      _addr.text = needsSettlement ? '$settlement, ${p.name}' : p.name;
      _addrLocked = true;
      _corrected = false;
    });
    _map.move(p.point, 17);
  }

  /// «Осы жерде:» — маңайдағы нысандар лентасы. Клиент ТРЦ/ЖК/базарды бір
  /// түртумен адрес етіп қоя алады (қолмен теруден құтылады).
  Widget _nearbyStrip() {
    if (_nearby.isEmpty) return const SizedBox.shrink();
    final chosen = _addr.text.trim().toLowerCase();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        Text(
          t('Осы жерде — түртіп таңдаңыз:'),
          style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: Gz.textSecondary),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 34,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _nearby.length,
            separatorBuilder: (_, i) => const SizedBox(width: 7),
            itemBuilder: (_, i) {
              final p = _nearby[i];
              final active = chosen.contains(p.name.toLowerCase());
              return InkWell(
                onTap: () => _selectNearby(p),
                borderRadius: BorderRadius.circular(17),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: active ? Gz.yellow : Gz.bg,
                    borderRadius: BorderRadius.circular(17),
                    border: Border.all(
                        color: active ? Gz.yellowDark : Gz.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_nearbyIcon(p.kind), size: 15, color: Gz.ink),
                      const SizedBox(width: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 190),
                        child: Text(
                          p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  static IconData _nearbyIcon(String? kind) {
    switch (kind) {
      case 'mall':
      case 'department_store':
      case 'supermarket':
      case 'convenience':
        return Icons.storefront_rounded;
      case 'marketplace':
        return Icons.shopping_basket_rounded;
      case 'apartments':
      case 'residential':
        return Icons.apartment_rounded;
      case 'hospital':
      case 'clinic':
      case 'pharmacy':
        return Icons.local_hospital_rounded;
      case 'school':
      case 'university':
      case 'college':
        return Icons.school_rounded;
      case 'bus_station':
      case 'train_station':
      case 'terminal':
        return Icons.directions_bus_rounded;
      case 'hotel':
        return Icons.hotel_rounded;
      case 'restaurant':
      case 'cafe':
      case 'fast_food':
        return Icons.restaurant_rounded;
      case 'bank':
        return Icons.account_balance_rounded;
      default:
        return Icons.place_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: 14,
              onPositionChanged: (camera, hasGesture) {
                _center = camera.center;
                // Картаны клиент ӨЗ ҚОЛЫМЕН жылжытты — демек жаңа жерді
                // іздеп жатыр, ескі атауды ұстап тұрудың қажеті жоқ.
                if (hasGesture) _addrLocked = false;
                _moveDebounce?.cancel();
                _moveDebounce = Timer(
                    const Duration(milliseconds: 400), _resolveCenter);
              },
            ),
            children: [osmTileLayer()],
          ),
          // Орталық пин. Ұшы картаның центріне ДӘЛ түседі ([MapCenterPin]
          // биіктігіне тең бос орынмен теңгереді) — бұрынғы «bottom: 38»
          // жуықтауының орнына нақты есеп, сол себепті таңдалған нүкте мен
          // анықталған мекенжай айырылмайды.
          MapCenterPin(color: Gz.red, size: 36, busy: _resolving),
          // іздеу өрісі
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Column(
              children: [
                Material(
                  elevation: 3,
                  borderRadius: BorderRadius.circular(14),
                  child: TextField(
                    controller: _search,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText: t('Адрес іздеу…'),
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _search.clear();
                                setState(() => _results = []);
                              },
                            ),
                    ),
                  ),
                ),
                if (_results.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    constraints: const BoxConstraints(maxHeight: 260),
                    decoration: BoxDecoration(
                      color: Gz.surface,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: const [
                        BoxShadow(color: Colors.black26, blurRadius: 10)
                      ],
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: _results.length,
                      separatorBuilder: (_, i) => const Divider(height: 1),
                      itemBuilder: (_, i) => ListTile(
                        dense: true,
                        leading: const Icon(Icons.place_outlined, size: 20),
                        title: Text(_results[i].name,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        onTap: () => _selectPlace(_results[i]),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // менің локациям
          Positioned(
            right: 14,
            bottom: 150,
            child: FloatingActionButton.small(
              heroTag: 'myloc',
              backgroundColor: Gz.surface,
              foregroundColor: Gz.ink,
              onPressed: _goToMyLocation,
              child: const Icon(Icons.my_location),
            ),
          ),
          // төменгі панель
          Positioned(
            left: 12,
            right: 12,
            bottom: 16,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(Gz.radius),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _addr,
                      textCapitalization: TextCapitalization.sentences,
                      onChanged: (_) => _addrLocked = true,
                      decoration: InputDecoration(
                        isDense: true,
                        prefixIcon: const Icon(Icons.location_on,
                            color: Gz.red, size: 20),
                        hintText: _resolving ? t('Анықталуда…') : t('Мекенжай аты'),
                        labelText: t('Осы жердің аты (түзетуге болады)'),
                      ),
                    ),
                    if (_centerCity != null &&
                        !Geo.sameCity(_centerCity, widget.city)) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.info_outline,
                              size: 14, color: Gz.blue),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              '${t('Елді мекен:')} $_centerCity',
                              style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: Gz.blue),
                            ),
                          ),
                        ],
                      ),
                    ],
                    _nearbyStrip(),
                    const SizedBox(height: 6),
                    Text(
                      _corrected
                          ? t('Бұл маңайдағы атау бұрын клиенттер арқылы түзетілген.')
                          : t('Картадағы белгі дұрыс емес пе? Атын түзетіңіз — осы '
                              'нүктеге сол атпен сақталады, қаладағы басқа жерге '
                              'ауыспайды.'),
                      style: TextStyle(
                          fontSize: 11.5,
                          color: _corrected ? Gz.green : Gz.textSecondary),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _resolving ? null : _confirmSave,
                      child: Text(t('Осы жерді таңдау')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
