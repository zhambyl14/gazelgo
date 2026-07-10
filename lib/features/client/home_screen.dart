import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/geo.dart';
import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/map_widgets.dart';
import '../../shared/transitions.dart';
import '../../shared/widgets.dart';
import '../profile/profile_screen.dart';
import 'address_picker.dart';
import 'city_street_sheet.dart';
import 'create_order_screen.dart';
import 'order_detail_screen.dart';

class ClientHomeScreen extends ConsumerStatefulWidget {
  const ClientHomeScreen({super.key});

  @override
  ConsumerState<ClientHomeScreen> createState() => _ClientHomeScreenState();
}

class _ClientHomeScreenState extends ConsumerState<ClientHomeScreen> {
  final _map = MapController();
  Timer? _moveDebounce;
  PickedAddress? _from;
  bool _resolvingFrom = true;
  PickedAddress? _to;

  @override
  void initState() {
    super.initState();
    _resolveFrom(Geo.almaty);
    _initLocation();
  }

  @override
  void dispose() {
    _moveDebounce?.cancel();
    super.dispose();
  }

  Future<void> _initLocation() async {
    final pos = await Geo.currentPosition();
    if (pos != null && mounted) {
      final p = LatLng(pos.latitude, pos.longitude);
      _map.move(p, 15.5);
      _resolveFrom(p);
    }
  }

  Future<void> _goToMyLocation() async {
    final pos = await Geo.currentPosition();
    if (pos == null) {
      if (mounted) showSnack(context, 'Локация қолжетімсіз', error: true);
      return;
    }
    final p = LatLng(pos.latitude, pos.longitude);
    _map.move(p, 16);
    _resolveFrom(p);
  }

  void _onMapMove(MapCamera camera, bool hasGesture) {
    if (!hasGesture) return;
    _moveDebounce?.cancel();
    _moveDebounce = Timer(
        const Duration(milliseconds: 500), () => _resolveFrom(camera.center));
  }

  Future<void> _resolveFrom(LatLng center) async {
    setState(() => _resolvingFrom = true);
    final (addr, city) = await Geo.reverseWithCity(center);
    if (!mounted) return;
    setState(() {
      _from = PickedAddress(addr, center, city);
      _resolvingFrom = false;
    });
  }

  /// Автоматты анықталған «Қайдан» адресін сәл өзгертуге мүмкіндік береді.
  Future<void> _editFrom() async {
    final res = await CityStreetSheet.show(context,
        title: 'Қайдан аламыз?', initial: _from);
    if (res != null && mounted) setState(() => _from = res);
  }

  Future<void> _pickTo() async {
    final res = await CityStreetSheet.show(context,
        title: 'Қайда жеткіземіз?', initial: _to);
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

    await Navigator.of(context).push(
      slideUpRoute(CreateOrderScreen(from: _from!, to: _to!)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(myProfileProvider);
    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: Geo.almaty,
              initialZoom: 13,
              onPositionChanged: _onMapMove,
            ),
            children: [osmTileLayer()],
          ),
          // орталық пин — картаның нақ ортасы = «Қайдан аламыз»
          IgnorePointer(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedScale(
                      duration: const Duration(milliseconds: 150),
                      scale: _resolvingFrom ? 0.85 : 1,
                      child: const Icon(Icons.location_on,
                          size: 44,
                          color: Gz.green,
                          shadows: [
                            Shadow(color: Colors.black38, blurRadius: 8)
                          ]),
                    ),
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.only(top: 2),
                      decoration: const BoxDecoration(
                        color: Colors.black26,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
              ),
            ),
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
                      _ProfileButton(profile: profileAsync.value),
                    ],
                  ),
                ),
                const Spacer(),
                // менің локациям батырмасы
                Padding(
                  padding: const EdgeInsets.only(right: 12, bottom: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Material(
                        elevation: 3,
                        shape: const CircleBorder(),
                        color: Gz.surface,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _goToMyLocation,
                          child: const Padding(
                            padding: EdgeInsets.all(12),
                            child:
                                Icon(Icons.my_location, color: Gz.ink, size: 22),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // белсенді («Іздеуде») заказ баннері — локация батырмасының астында
                const _ActiveOrdersBanner(),
                // негізгі панель
                Container(
                  margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Gz.surface,
                    borderRadius: BorderRadius.circular(26),
                    boxShadow: const [
                      BoxShadow(
                          color: Color(0x260F1720),
                          blurRadius: 30,
                          offset: Offset(0, 10))
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
                                  'Картаны жылжытып, орныңызды белгілеңіз',
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
                      // Қайдан — картамен байланысты, бірақ түртіп сәл өзгертуге болады
                      InkWell(
                        onTap: _resolvingFrom ? null : _editFrom,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 13),
                          decoration: BoxDecoration(
                            color: Gz.bg,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.trip_origin,
                                  size: 18, color: Gz.green),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _resolvingFrom
                                      ? 'Анықталуда…'
                                      : (_from?.address ?? 'Картаны жылжытыңыз'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: Gz.ink,
                                      fontSize: 14.5),
                                ),
                              ),
                              if (_resolvingFrom)
                                const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                              else
                                const Icon(Icons.edit_outlined,
                                    size: 16, color: Gz.textSecondary),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: _pickTo,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 13),
                          decoration: BoxDecoration(
                            color: Gz.bg,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.location_on,
                                  size: 18, color: Gz.red),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _to?.address ?? 'Қайда жеткіземіз?',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: _to == null
                                        ? FontWeight.w500
                                        : FontWeight.w700,
                                    color: _to == null
                                        ? Gz.textSecondary
                                        : Gz.ink,
                                    fontSize: 14.5,
                                  ),
                                ),
                              ),
                              const Icon(Icons.chevron_right,
                                  color: Gz.textSecondary),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      FilledButton(
                        onPressed: (_from == null || _resolvingFrom)
                            ? null
                            : (_to == null ? _pickTo : _maybeContinue),
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

class _ProfileButton extends StatelessWidget {
  final Profile? profile;
  const _ProfileButton({this.profile});

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24));
    return Material(
      elevation: 2,
      shape: shape,
      color: Gz.surface,
      child: InkWell(
        customBorder: shape,
        onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ProfileScreen())),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 3, 12, 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              InitialsAvatar(profile?.fullName ?? '?',
                  radius: 17, imageUrl: profile?.avatarUrl),
              const SizedBox(width: 8),
              Icon(Icons.keyboard_arrow_down_rounded,
                  size: 18, color: Gz.textSecondary.withValues(alpha: 0.7)),
            ],
          ),
        ),
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
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
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
                        '${o.fromDisplay} → ${o.toDisplay}',
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
