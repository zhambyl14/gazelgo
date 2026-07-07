import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../core/geo.dart';
import '../../core/theme.dart';
import 'address_picker.dart';

/// Адрес іздеу терезесі (bottom sheet) — жаңа экран ашпай, осында жазады.
/// Картадан таңдау опциясы да бар.
class AddressSearchSheet extends StatefulWidget {
  final String title;
  final LatLng? initial;
  final String? initialQuery;
  const AddressSearchSheet(
      {super.key, required this.title, this.initial, this.initialQuery});

  static Future<PickedAddress?> show(BuildContext context,
      {required String title, LatLng? initial, String? initialQuery}) {
    return showModalBottomSheet<PickedAddress>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Gz.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => AddressSearchSheet(
          title: title, initial: initial, initialQuery: initialQuery),
    );
  }

  @override
  State<AddressSearchSheet> createState() => _AddressSearchSheetState();
}

class _AddressSearchSheetState extends State<AddressSearchSheet> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<GeoPlace> _results = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
      _search.text = widget.initialQuery!;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    if (q.trim().length < 3) {
      setState(() => _results = []);
      return;
    }
    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      final res = await Geo.search(q);
      if (mounted) {
        setState(() {
          _results = res;
          _loading = false;
        });
      }
    });
  }

  Future<void> _useMyLocation() async {
    setState(() => _loading = true);
    final pos = await Geo.currentPosition();
    if (pos == null) {
      if (mounted) {
        setState(() => _loading = false);
        showSnack(context, 'Локация қолжетімсіз', error: true);
      }
      return;
    }
    final p = LatLng(pos.latitude, pos.longitude);
    if (!Geo.inKazakhstan(p)) {
      if (mounted) {
        setState(() => _loading = false);
        showSnack(context, 'Тек Қазақстан ішінде', error: true);
      }
      return;
    }
    final (addr, city) = await Geo.reverseWithCity(p);
    if (mounted) Navigator.pop(context, PickedAddress(addr, p, city));
  }

  Future<void> _openMap() async {
    final res = await AddressPickerScreen.pick(context,
        title: widget.title, initial: widget.initial);
    if (res != null && mounted) {
      if (!Geo.inKazakhstan(res.point)) {
        showSnack(context, 'Тек Қазақстан ішінде', error: true);
        return;
      }
      Navigator.pop(context, res);
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
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Text(widget.title,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w900)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _search,
                autofocus: true,
                onChanged: _onChanged,
                decoration: InputDecoration(
                  hintText: 'Адрес, көше, үй…',
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
                      : _search.text.isEmpty
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
            const SizedBox(height: 6),
            // жылдам әрекеттер
            Row(
              children: [
                Expanded(
                  child: _quickTile(
                      Icons.my_location, 'Менің жерім', _useMyLocation),
                ),
                Expanded(
                  child: _quickTile(Icons.map_outlined, 'Картадан', _openMap),
                ),
              ],
            ),
            const Divider(height: 1),
            Expanded(
              child: _results.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _search.text.trim().length < 3
                              ? 'Адресті жаза бастаңыз немесе картадан таңдаңыз'
                              : (_loading ? '' : 'Ештеңе табылмады'),
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
                        onTap: () => Navigator.pop(
                            context,
                            PickedAddress(_results[i].name, _results[i].point,
                                _results[i].city)),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickTile(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: Gz.ink),
            const SizedBox(width: 8),
            Text(label,
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
