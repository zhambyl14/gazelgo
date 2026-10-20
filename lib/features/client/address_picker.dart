import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/geo.dart';
import '../../core/lang.dart';
import '../../core/theme.dart';
import '../../shared/map_widgets.dart';

class PickedAddress {
  final String address;
  final LatLng point;
  final String? city;
  PickedAddress(this.address, this.point, [this.city]);
}

/// Картадан мекенжай таңдау: клиент пинді қояды, мекенжай атауы КАРТАДАН
/// өзі анықталады.
///
/// Атауды клиент ЖАЗБАЙДЫ — бұрын жазылған мәтін адрес болып, нүкте мен
/// атау айырылып кететін (атауы бір көше, нүктесі басқа жер). Енді атау
/// әрқашан нүктенің өзінен алынады: геокодер таппаса — маңайдағы көше,
/// аудан, ең соңында «Картадағы нүкте» (нүкте дәл, орындаушы навигатормен
/// дәл келеді). Маңайдағы ТРЦ/ЖК/базарды бір түртумен таңдауға болады.
class AddressPickerScreen extends StatefulWidget {
  final String title;
  final LatLng? initial;

  /// Карта ашылғандағы жақындату (көшедегі үйді көрсеткенде — 17).
  final double initialZoom;

  /// Клиент таңдаған қала. Адрес жолында осы қаланың аты ҚАЙТАЛАНБАЙДЫ, ал
  /// нүкте басқа елді мекенде болса (Ерейментау, Мерке, Луговой…) — сол елді
  /// мекеннің аты адреске МІНДЕТТІ түрде қосылады.
  final String? city;

  const AddressPickerScreen({
    super.key,
    required this.title,
    this.initial,
    this.initialZoom = 16,
    this.city,
  });

  static Future<PickedAddress?> pick(
    BuildContext context, {
    required String title,
    LatLng? initial,
    double initialZoom = 16,
    String? city,
  }) {
    return Navigator.of(context).push<PickedAddress>(
      MaterialPageRoute(
        builder: (_) => AddressPickerScreen(
          title: title,
          initial: initial,
          initialZoom: initialZoom,
          city: city,
        ),
      ),
    );
  }

  @override
  State<AddressPickerScreen> createState() => _AddressPickerScreenState();
}

class _AddressPickerScreenState extends State<AddressPickerScreen> {
  final _map = MapController();
  Timer? _moveDebounce;

  /// Карта саусақпен жылжып жатыр — орталық пин «көтеріледі».
  bool _pinLifted = false;
  Timer? _dropTimer;

  /// Пайдаланушының нақты GPS орны («мен осындамын» көк нүктесі).
  LatLng? _myPos;
  LatLng _center = Geo.almaty;

  /// Пиннің астындағы мекенжай (картадан анықталған).
  String _label = '';

  /// Геокодер мекенжайды дәл тапты ма (жоқ болса — маңайдағы көше/аудан).
  bool _exact = true;
  String? _centerCity;
  bool _resolving = false;

  /// Маңайдағы аты бар нысандар (ТРЦ, ЖК, базар…) — «мынау ма?» ұсынысы.
  List<GeoPlace> _nearby = const [];

  /// Клиент маңайдағы нысанды таңдады — карта сол нысанға жылжығанда атауы
  /// қайта «жәй көшеге» ауыстырылмасын.
  bool _labelLocked = false;

  @override
  void initState() {
    super.initState();
    _center = widget.initial ?? Geo.almaty;
    _resolveCenter();
    if (widget.initial == null) _goToMyLocation();
  }

  @override
  void dispose() {
    _moveDebounce?.cancel();
    _dropTimer?.cancel();
    super.dispose();
  }

  Future<void> _goToMyLocation() async {
    final pos = await Geo.currentPosition();
    if (pos != null && mounted) {
      final p = LatLng(pos.latitude, pos.longitude);
      setState(() => _myPos = p);
      _map.move(p, 17);
      _center = p;
      _labelLocked = false;
      _resolveCenter();
    }
  }

  Future<void> _resolveCenter() async {
    final target = _center;
    setState(() => _resolving = true);
    final res = await Geo.describePoint(target, city: widget.city);
    if (!mounted || target != _center) return;
    setState(() {
      if (!_labelLocked) {
        _label = res.label.replaceAll(
          Geo.kMapPointLabel,
          t(Geo.kMapPointLabel),
        );
        _exact = res.exact;
      }
      _centerCity = res.settlement;
      _resolving = false;
    });
    // Маңайдағы нысандар — баяу әрі міндетті емес, сол себепті бөлек әрі
    // адрес шыққаннан КЕЙІН жүктеледі (экран қатып қалмауы үшін).
    final near = await Geo.nearbyPlaces(target);
    if (mounted && target == _center) setState(() => _nearby = near);
  }

  void _confirm() {
    if (_label.isEmpty) return;
    Navigator.of(context).pop(PickedAddress(_label, _center, _centerCity));
  }

  /// Маңайдағы нысанды таңдау: пин сол нысанның дәл ортасына көшеді, ал адрес
  /// жолы «ТРЦ аты, көше, үй» болып жазылады.
  void _selectNearby(GeoPlace p) {
    final settlement = _centerCity;
    final needsSettlement =
        settlement != null &&
        settlement.isNotEmpty &&
        !Geo.sameCity(settlement, widget.city);
    setState(() {
      _center = p.point;
      _label = needsSettlement ? '$settlement, ${p.name}' : p.name;
      _exact = true;
      _labelLocked = true;
    });
    _map.move(p.point, 17);
  }

  Widget _nearbyStrip() {
    if (_nearby.isEmpty) return const SizedBox.shrink();
    final chosen = _label.toLowerCase();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        Text(
          t('Осы жерде — түртіп таңдаңыз:'),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: Gz.textSecondary,
          ),
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
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: active ? Gz.yellow : Gz.bg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: active ? Gz.yellowDark : Gz.border,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_nearbyIcon(p.kind), size: 15, color: active ? Gz.onBrand : Gz.ink),
                      const SizedBox(width: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 190),
                        child: Text(
                          p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
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
    final busy = _resolving && !_labelLocked;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      // `expand` позицияланбаған балаларға ТЫҒЫЗ шектеу береді — әйтпесе
      // Stack карта мен пиннің өлшеміне жиырылып кетуі мүмкін.
      body: Stack(
        fit: StackFit.expand,
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: widget.initialZoom,
              onPositionChanged: (camera, hasGesture) {
                _center = camera.center;
                // Картаны клиент ӨЗ ҚОЛЫМЕН жылжытты — жаңа жерді іздеп
                // жатыр, таңдалған нысан атауын ұстап тұрудың қажеті жоқ.
                if (hasGesture) {
                  _labelLocked = false;
                  if (!_pinLifted) setState(() => _pinLifted = true);
                  _dropTimer?.cancel();
                  _dropTimer = Timer(const Duration(milliseconds: 180), () {
                    if (mounted) setState(() => _pinLifted = false);
                  });
                }
                _moveDebounce?.cancel();
                _moveDebounce = Timer(
                  const Duration(milliseconds: 400),
                  _resolveCenter,
                );
              },
            ),
            children: [
              osmTileLayer(),
              if (_myPos != null)
                MarkerLayer(markers: [myLocationMarker(_myPos!)]),
            ],
          ),
          // Орталық пин — ұшы картаның центріне ДӘЛ түседі, сол себепті
          // таңдалған нүкте мен анықталған мекенжай айырылмайды.
          MapCenterPin(busy: busy, lifted: _pinLifted),
          // менің локациям
          Positioned(
            right: 14,
            bottom: 210,
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
            child: SafeArea(
              top: false,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(Gz.radius),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Icon(
                              Icons.location_on,
                              color: Gz.red,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              busy
                                  ? t('Мекенжай анықталуда…')
                                  : (_label.isEmpty
                                        ? t('Картаны жылжытып, нүктені қойыңыз')
                                        : _label),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16,
                                height: 1.25,
                                fontWeight: FontWeight.w700,
                                color: busy ? Gz.textTertiary : Gz.ink,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_centerCity != null &&
                          !Geo.sameCity(_centerCity, widget.city)) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 14,
                              color: Gz.blue,
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                '${t('Елді мекен:')} $_centerCity',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Gz.blue,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      _nearbyStrip(),
                      if (!busy && !_exact) ...[
                        const SizedBox(height: 8),
                        Text(
                          t(
                            'Бұл жердің нақты мекенжайы картада жоқ — нүкте '
                            'дәл сақталады, орындаушы навигатормен дәл келеді.',
                          ),
                          style: TextStyle(
                            fontSize: 12,
                            color: Gz.textSecondary,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: busy || _label.isEmpty ? null : _confirm,
                        child: Text(t('Осы мекенжайды таңдау')),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
