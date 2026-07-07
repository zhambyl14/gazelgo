import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/geo.dart';
import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/map_widgets.dart';
import '../../shared/widgets.dart';
import 'address_picker.dart';
import 'address_search_sheet.dart';
import 'create_order_screen.dart';
import 'order_detail_screen.dart';

class ClientHomeScreen extends StatefulWidget {
  const ClientHomeScreen({super.key});

  @override
  State<ClientHomeScreen> createState() => _ClientHomeScreenState();
}

class _ClientHomeScreenState extends State<ClientHomeScreen> {
  final _map = MapController();
  PickedAddress? _from;
  PickedAddress? _to;

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  Future<void> _initLocation() async {
    final pos = await Geo.currentPosition();
    if (pos != null && mounted) {
      _map.move(LatLng(pos.latitude, pos.longitude), 14.5);
    }
  }

  Future<void> _pickFrom() async {
    final res = await AddressSearchSheet.show(context,
        title: 'Қайдан аламыз?', initial: _from?.point);
    if (res != null) setState(() => _from = res);
  }

  Future<void> _pickTo() async {
    final res = await AddressSearchSheet.show(context,
        title: 'Қайда жеткіземіз?', initial: _to?.point);
    if (res != null) setState(() => _to = res);
  }

  Future<void> _maybeContinue() async {
    if (_from == null || _to == null || !mounted) return;

    // белсенді заказ бар ма? — ескерту
    final active = await Repo.c
        .from('orders')
        .select('id')
        .eq('client_id', Repo.uid ?? '')
        .inFilter('status', kActiveOrderStatuses);
    final count = (active as List).length;
    if (count > 0 && mounted) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Белсенді заказ бар'),
          content: Text(
              'Сізде $count белсенді заказ бар. Оны «Тапсырыстар» бетінен қадағалай аласыз.\n\n'
              'Жаңа заказ бересіз бе?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Жоқ')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Иә, жаңа заказ')),
          ],
        ),
      );
      if (go != true) return;
    }
    if (!mounted) return;

    // Адрестерді сақтап қоямыз (create/cancel-ден кейін қайта жазбау үшін).
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CreateOrderScreen(from: _from!, to: _to!),
    ));
  }

  Widget _addressField({
    required IconData icon,
    required Color color,
    required String hint,
    required PickedAddress? value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        decoration: BoxDecoration(
          color: Gz.bg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                value?.address ?? hint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight:
                      value == null ? FontWeight.w500 : FontWeight.w700,
                  color: value == null ? Gz.textSecondary : Gz.ink,
                  fontSize: 14.5,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, color: Gz.textSecondary),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: const MapOptions(
              initialCenter: Geo.almaty,
              initialZoom: 13,
            ),
            children: [osmTileLayer()],
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Row(
                    children: [
                      Material(
                        elevation: 2,
                        borderRadius: BorderRadius.circular(12),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          child: GazelGoLogo(size: 20),
                        ),
                      ),
                      const Spacer(),
                    ],
                  ),
                ),
                const Spacer(),
                // белсенді заказ баннері
                const _ActiveOrdersBanner(),
                // негізгі панель
                Container(
                  margin: const EdgeInsets.all(12),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Gz.surface,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: const [
                      BoxShadow(
                          color: Colors.black26,
                          blurRadius: 20,
                          offset: Offset(0, 6))
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(
                              color: Gz.yellow,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.local_shipping,
                                size: 22, color: Gz.ink),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Газель керек пе?',
                                    style: TextStyle(
                                        fontSize: 19,
                                        fontWeight: FontWeight.w900)),
                                Text(
                                  'Бірнеше минутта орындаушы табыңыз',
                                  style: TextStyle(
                                      color: Gz.textSecondary,
                                      fontSize: 12.5),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _addressField(
                        icon: Icons.trip_origin,
                        color: Gz.green,
                        hint: 'Қайдан аламыз?',
                        value: _from,
                        onTap: _pickFrom,
                      ),
                      const SizedBox(height: 8),
                      _addressField(
                        icon: Icons.location_on,
                        color: Gz.red,
                        hint: 'Қайда жеткіземіз?',
                        value: _to,
                        onTap: _pickTo,
                      ),
                      const SizedBox(height: 14),
                      FilledButton(
                        onPressed: () {
                          if (_from == null) {
                            _pickFrom();
                          } else if (_to == null) {
                            _pickTo();
                          } else {
                            _maybeContinue();
                          }
                        },
                        child: const Text('Газель шақыру'),
                      ),
                    ],
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
        final active =
            (snap.data ?? []).where((o) => o.isActive).toList().reversed.toList();
        if (active.isEmpty) return const SizedBox.shrink();
        final o = active.first;
        return GestureDetector(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => OrderDetailScreen(orderId: o.id))),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Gz.ink,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                      color: Gz.yellow, shape: BoxShape.circle),
                  child: const Icon(Icons.local_shipping,
                      size: 18, color: Gz.ink),
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
                            fontSize: 14),
                      ),
                      Text(
                        '${o.fromAddress} → ${o.toAddress}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                if (active.length > 1)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('+${active.length - 1}',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12)),
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
