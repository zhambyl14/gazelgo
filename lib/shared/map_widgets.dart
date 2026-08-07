import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/theme.dart';

TileLayer osmTileLayer() => TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'kz.gazelgo.app',
    );

Marker pointMarker(LatLng p, {Color color = Gz.green, IconData? icon}) =>
    Marker(
      point: p,
      width: 38,
      height: 38,
      alignment: Alignment.topCenter,
      child: Icon(
        icon ?? Icons.location_on,
        color: color,
        size: 38,
        shadows: const [Shadow(color: Colors.black38, blurRadius: 6)],
      ),
    );

/// A нүктесінің таза белгісі — жасыл сақина (домалақ емес).
Marker originMarker(LatLng p) => Marker(
      point: p,
      width: 26,
      height: 26,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          border: Border.all(color: Gz.green, width: 5),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
        ),
      ),
    );

/// Маршрутты көрсететін шағын карта (A → B + сызық).
class RouteMap extends StatelessWidget {
  final LatLng from;
  final LatLng to;

  /// АРАЛЫҚ аялдамалар (0047) — картада күлгін нүктелермен белгіленеді әрі
  /// камера оларды да қамтиды (әйтпесе аялдама кадрдан шығып қалатын).
  final List<LatLng> stops;
  final List<LatLng> routePoints;
  final double height;

  /// Қосымша маркерлер (0060, орындаушыны тірі көрсету) — мыс. орындаушының
  /// ағымдағы GPS нүктесі. Бос болса ештеңе өзгермейді.
  final List<Marker> extraMarkers;

  const RouteMap({
    super.key,
    required this.from,
    required this.to,
    this.stops = const [],
    this.routePoints = const [],
    this.height = 200,
    this.extraMarkers = const [],
  });

  @override
  Widget build(BuildContext context) {
    final all = [from, ...stops, to, for (final m in extraMarkers) m.point];
    final points = routePoints.isEmpty ? [from, ...stops, to] : routePoints;
    return ClipRRect(
      borderRadius: BorderRadius.circular(Gz.radius),
      child: SizedBox(
        height: height,
        child: IgnorePointer(
          child: FlutterMap(
            options: MapOptions(
              initialCameraFit: CameraFit.bounds(
                // БАРЛЫҚ нүкте бойынша — аялдамамен қоса.
                bounds: LatLngBounds.fromPoints(all),
                padding: const EdgeInsets.all(40),
              ),
              interactionOptions:
                  const InteractionOptions(flags: InteractiveFlag.none),
            ),
            children: [
              osmTileLayer(),
              PolylineLayer(polylines: [
                Polyline(points: points, strokeWidth: 4, color: Gz.blue),
              ]),
              MarkerLayer(markers: [
                originMarker(from),
                for (final s in stops) pointMarker(s, color: Gz.violet),
                pointMarker(to, color: Gz.red),
                ...extraMarkers,
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

/// Орындаушының тірі орнына арналған маркер (жүк көлігі иконкасы, көк).
Marker executorLiveMarker(LatLng p) => Marker(
      point: p,
      width: 34,
      height: 34,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Gz.blue,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 6)],
        ),
        child: const Icon(Icons.local_shipping,
            color: Colors.white, size: 16),
      ),
    );
