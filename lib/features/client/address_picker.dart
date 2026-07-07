import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/geo.dart';
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
  const AddressPickerScreen({super.key, required this.title, this.initial});

  static Future<PickedAddress?> pick(BuildContext context,
      {required String title, LatLng? initial}) {
    return Navigator.of(context).push<PickedAddress>(
      MaterialPageRoute(
          builder: (_) => AddressPickerScreen(title: title, initial: initial)),
    );
  }

  @override
  State<AddressPickerScreen> createState() => _AddressPickerScreenState();
}

class _AddressPickerScreenState extends State<AddressPickerScreen> {
  final _map = MapController();
  final _search = TextEditingController();
  Timer? _debounce;
  Timer? _moveDebounce;
  List<GeoPlace> _results = [];
  String _centerAddress = 'Картаны жылжытыңыз…';
  String? _centerCity;
  LatLng _center = Geo.almaty;
  bool _resolving = false;

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
    super.dispose();
  }

  Future<void> _goToMyLocation() async {
    final pos = await Geo.currentPosition();
    if (pos != null && mounted) {
      final p = LatLng(pos.latitude, pos.longitude);
      _map.move(p, 16);
      _center = p;
      _resolveCenter();
    }
  }

  Future<void> _resolveCenter() async {
    setState(() => _resolving = true);
    final (addr, city) = await Geo.reverseWithCity(_center);
    if (mounted) {
      setState(() {
        _centerAddress = addr;
        _centerCity = city;
        _resolving = false;
      });
    }
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
      _centerAddress = p.name;
      _centerCity = p.city;
    });
    _map.move(p.point, 16.5);
  }

  void _confirm() {
    Navigator.of(context)
        .pop(PickedAddress(_centerAddress, _center, _centerCity));
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
                _moveDebounce?.cancel();
                _moveDebounce = Timer(
                    const Duration(milliseconds: 400), _resolveCenter);
              },
            ),
            children: [osmTileLayer()],
          ),
          // орталық пин
          const IgnorePointer(
            child: Center(
              child: Padding(
                padding: EdgeInsets.only(bottom: 38),
                child: Icon(Icons.location_on, size: 46, color: Gz.red,
                    shadows: [Shadow(color: Colors.black38, blurRadius: 8)]),
              ),
            ),
          ),
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
                      hintText: 'Адрес іздеу…',
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
                    Row(
                      children: [
                        const Icon(Icons.location_on, color: Gz.red, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _resolving
                              ? const Text('Анықталуда…',
                                  style: TextStyle(color: Gz.textSecondary))
                              : Text(
                                  _centerAddress,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700),
                                ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _resolving ? null : _confirm,
                      child: const Text('Осы жерді таңдау'),
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
