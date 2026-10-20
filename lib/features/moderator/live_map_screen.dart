import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/geo.dart';
import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/map_widgets.dart';
import '../../shared/vehicle_picker.dart';
import '../../shared/widgets.dart';
import 'order_admin.dart';

/// Модератор: ТІРІ КАРТА (0083) — сұраныс пен ұсыныс бір картада.
///
/// Көк баға-белгі — іздеудегі заказ, жасыл нүкте — орындалып жатқан
/// заказдың алу нүктесі, көлік белгісі — орындаушы (бос көлік жарқын,
/// заказдағысы солғын). Басса: заказ — басқару терезесі, орындаушы —
/// аты, телефоны, күйі.
class LiveMapScreen extends StatefulWidget {
  const LiveMapScreen({super.key});

  @override
  State<LiveMapScreen> createState() => _LiveMapScreenState();
}

class _LiveExecutor {
  final String id;
  final LatLng point;
  final double? heading;
  final VehicleType vehicleType;
  final String name;
  final String phone;
  final bool busy;
  final bool onLine;
  final DateTime? updatedAt;
  final String? orderId;

  _LiveExecutor.fromMap(Map<String, dynamic> m)
    : id = m['id'] as String,
      point = LatLng(
        (m['lat'] as num).toDouble(),
        (m['lng'] as num).toDouble(),
      ),
      heading = (m['heading'] as num?)?.toDouble(),
      vehicleType = vehicleTypeFrom(m['vehicle_type'] as String?),
      name = m['name'] as String? ?? '',
      phone = m['phone'] as String? ?? '',
      busy = m['busy'] == true,
      onLine = m['on_line'] != false,
      updatedAt = DateTime.tryParse(
        m['updated_at'] as String? ?? '',
      )?.toLocal(),
      orderId = m['order_id'] as String?;
}

class _LiveOrder {
  final String id;
  final LatLng point;
  final String status;
  final VehicleType vehicleType;
  final int? price;

  _LiveOrder(this.id, this.point, this.status, this.vehicleType, this.price);

  bool get searching => status == 'searching';
}

class _LiveMapScreenState extends State<LiveMapScreen> {
  final _map = MapController();
  Timer? _timer;
  bool _loaded = false;
  bool _framed = false;
  bool _rpcMissing = false;
  List<_LiveExecutor> _executors = const [];
  List<_LiveOrder> _orders = const [];

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await Repo.modLiveMap();
      List<_LiveExecutor> executors = const [];
      List<_LiveOrder> orders;
      if (res == null) {
        // 0083 әлі жоқ — тек іздеудегі заказдар (тікелей кестеден).
        final list = await Repo.searchingOrders();
        orders = [
          for (final o in list)
            _LiveOrder(
              o.id,
              LatLng(o.fromLat, o.fromLng),
              o.status,
              o.vehicleType,
              o.displayPrice,
            ),
        ];
      } else {
        executors = [
          for (final m in (res['executors'] as List? ?? const []))
            _LiveExecutor.fromMap(Map<String, dynamic>.from(m as Map)),
        ];
        orders = [
          for (final raw in (res['orders'] as List? ?? const []))
            if (raw is Map && raw['lat'] != null && raw['lng'] != null)
              _LiveOrder(
                raw['id'] as String,
                LatLng(
                  (raw['lat'] as num).toDouble(),
                  (raw['lng'] as num).toDouble(),
                ),
                raw['status'] as String? ?? 'searching',
                vehicleTypeFrom(raw['vehicle_type'] as String?),
                (raw['price'] as num?)?.toInt(),
              ),
        ];
      }
      if (!mounted) return;
      setState(() {
        _rpcMissing = res == null;
        _executors = executors;
        _orders = orders;
        _loaded = true;
      });
      if (!_framed) {
        _framed = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => _fitAll());
      }
    } catch (e) {
      if (mounted && !_loaded) {
        setState(() => _loaded = true);
        showSnack(context, errText(e), error: true);
      }
    }
  }

  void _fitAll() {
    final pts = [
      for (final o in _orders) o.point,
      for (final e in _executors) e.point,
    ];
    if (pts.isEmpty) return;
    try {
      if (pts.length == 1) {
        _map.move(pts.first, 13);
      } else {
        _map.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(pts),
            padding: const EdgeInsets.fromLTRB(40, 110, 40, 40),
            maxZoom: 15,
          ),
        );
      }
    } catch (_) {}
  }

  void _openExecutor(_LiveExecutor e) {
    final age = e.updatedAt == null
        ? null
        : DateTime.now().difference(e.updatedAt!).inMinutes;
    showGzSheet<void>(
      context,
      builder: (ctx) => GzSheetBody(
        title: e.name.isEmpty ? t('Орындаушы') : e.name,
        subtitle: [
          e.vehicleType.label,
          e.busy
              ? t('Заказда')
              : (e.onLine ? t('Бос, линияда') : t('Үзілісте')),
          if (age != null) '${t('орны')} $age ${t('мин бұрын')}',
        ].join(' · '),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (e.phone.isNotEmpty) ContactButtons(phone: e.phone),
            if (e.orderId != null) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  showOrderAdminSheet(context, e.orderId!);
                },
                icon: const Icon(Icons.receipt_long_outlined),
                label: Text(t('Заказын ашу')),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final searching = _orders.where((o) => o.searching).length;
    final active = _orders.length - searching;
    final free = _executors.where((e) => !e.busy && e.onLine).length;
    final busy = _executors.where((e) => e.busy).length;
    return Stack(
      children: [
        Positioned.fill(
          child: FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: Geo.almaty,
              initialZoom: 11,
              backgroundColor: Gz.bg,
            ),
            children: [
              osmTileLayer(),
              MarkerLayer(
                markers: [
                  for (final o in _orders.where((o) => !o.searching))
                    Marker(
                      point: o.point,
                      width: 18,
                      height: 18,
                      child: GestureDetector(
                        onTap: () => showOrderAdminSheet(context, o.id),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Gz.green,
                            shape: BoxShape.circle,
                            border: Border.all(color: Gz.surface, width: 3),
                            boxShadow: Gz.cardShadow,
                          ),
                        ),
                      ),
                    ),
                  for (final e in _executors)
                    Marker(
                      point: e.point,
                      width: 34,
                      height: 34,
                      child: GestureDetector(
                        onTap: () => _openExecutor(e),
                        child: Opacity(
                          opacity: e.busy || !e.onLine ? 0.45 : 1,
                          child: VehicleMarker(
                            type: e.vehicleType,
                            size: 34,
                            heading: e.heading,
                          ),
                        ),
                      ),
                    ),
                  for (final o in _orders.where((o) => o.searching))
                    Marker(
                      point: o.point,
                      width: 92,
                      height: 30,
                      alignment: Alignment.topCenter,
                      child: GestureDetector(
                        onTap: () => showOrderAdminSheet(context, o.id),
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(6, 4, 8, 4),
                            decoration: BoxDecoration(
                              color: Gz.blue,
                              borderRadius: BorderRadius.circular(Gz.rSm),
                              boxShadow: Gz.cardShadow,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                vehicleIcon(o.vehicleType, size: 14),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    fmtT(o.price),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        Positioned(
          left: 10,
          right: 10,
          top: 10,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Gz.surface,
                  borderRadius: BorderRadius.circular(Gz.rMd),
                  boxShadow: Gz.cardShadow,
                ),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    InfoChip(
                      icon: Icons.gavel_rounded,
                      color: Gz.blue,
                      text: '${t('Іздеуде')}: $searching',
                    ),
                    InfoChip(
                      icon: Icons.local_shipping_outlined,
                      color: Gz.green,
                      text: '${t('Орындалуда')}: $active',
                    ),
                    if (!_rpcMissing) ...[
                      InfoChip(
                        icon: Icons.check_circle_outline,
                        color: Gz.success,
                        text: '${t('Бос көлік')}: $free',
                      ),
                      InfoChip(
                        icon: Icons.hourglass_bottom_rounded,
                        text: '${t('Заказда')}: $busy',
                      ),
                    ],
                  ],
                ),
              ),
              if (_rpcMissing) ...[
                const SizedBox(height: 8),
                GzNotice(
                  tone: NoticeTone.warning,
                  dense: true,
                  message: t(
                    'Орындаушылардың орны көріну үшін серверде 0083 '
                    'миграциясын қолданыңыз.',
                  ),
                ),
              ],
            ],
          ),
        ),
        Positioned(
          right: 12,
          bottom: 16,
          child: MapRoundButton(
            icon: Icons.fit_screen_rounded,
            tooltip: t('Барлығын көрсету'),
            onTap: _fitAll,
          ),
        ),
        if (!_loaded) const Center(child: CircularProgressIndicator()),
      ],
    );
  }
}
