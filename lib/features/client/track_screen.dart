import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/map_widgets.dart';
import '../../shared/widgets.dart';

/// «Сапарды бөлісу» (0060) — АВТОРИЗАЦИЯСЫЗ ашылатын бет. Клиент туысқанына/
/// досына сілтеме жібереді (`/track/<token>`), ол қосымшасыз, кірместен
/// заказдың барысын көреді. Тек WEB-те қолжетімді (main.dart `Uri.base`
/// арқылы осы экранды тікелей ашады, ClientShell/AuthGate айналып өтіледі).
class TrackScreen extends StatefulWidget {
  final String token;
  const TrackScreen({super.key, required this.token});

  @override
  State<TrackScreen> createState() => _TrackScreenState();
}

class _TrackScreenState extends State<TrackScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await Repo.trackOrder(widget.token);
      if (!mounted) return;
      if (res['error'] != null) {
        setState(() => _error = res['error'] as String);
      } else {
        setState(() {
          _data = res;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && _data == null) {
        setState(() => _error = 'NETWORK');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Gz.bg,
      appBar: AppBar(
        title: Text(t('Тапсырыстың барысы')),
        backgroundColor: Gz.surface,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error == 'DISABLED') {
      return EmptyState(
        icon: Icons.link_off,
        title: t('Бұл сілтеме қазір өшірулі'),
      );
    }
    if (_error == 'NOT_FOUND') {
      return EmptyState(
        icon: Icons.error_outline,
        title: t('Сілтеме жарамсыз немесе мерзімі өткен'),
      );
    }
    final d = _data;
    if (d == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final status = d['status'] as String? ?? 'searching';
    final vehicle = vehicleTypeFrom(d['vehicle_type'] as String?);
    final fromLat = (d['from_lat'] as num?)?.toDouble();
    final fromLng = (d['from_lng'] as num?)?.toDouble();
    final toLat = (d['to_lat'] as num?)?.toDouble();
    final toLng = (d['to_lng'] as num?)?.toDouble();
    final lat = (d['lat'] as num?)?.toDouble();
    final lng = (d['lng'] as num?)?.toDouble();
    final executorName = d['executor_name'] as String?;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  vehicle.label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 18),
                ),
              ),
              StatusChip(status, vehicleType: vehicle),
            ],
          ),
          const SizedBox(height: 12),
          if (fromLat != null && fromLng != null && toLat != null && toLng != null)
            RouteMap(
              from: LatLng(fromLat, fromLng),
              to: LatLng(toLat, toLng),
              height: 220,
              extraMarkers: [
                if (lat != null && lng != null)
                  executorLiveMarker(LatLng(lat, lng)),
              ],
              fromLabel:
                  '${d['from_city'] ?? ''} ${d['from_address'] ?? ''}'.trim(),
              toLabel:
                  '${d['to_city'] ?? ''} ${d['to_address'] ?? ''}'.trim(),
              distanceKm: (d['distance_km'] as num?)?.toDouble(),
            ),
          const SizedBox(height: 12),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InfoRow(t('Қайдан'),
                    '${d['from_city'] ?? ''} ${d['from_address'] ?? ''}'.trim()),
                InfoRow(t('Қайда'),
                    '${d['to_city'] ?? ''} ${d['to_address'] ?? ''}'.trim()),
                if (d['distance_km'] != null)
                  InfoRow(t('Қашықтық'),
                      '${(d['distance_km'] as num).toStringAsFixed(1)} км'),
                if (executorName != null && executorName.trim().isNotEmpty)
                  InfoRow(t('Орындаушы'), executorName),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              'Tasu',
              style: TextStyle(
                  color: Gz.textSecondary.withValues(alpha: 0.6),
                  fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
