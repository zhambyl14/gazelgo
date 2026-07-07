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
  final List<LatLng> routePoints;
  final double height;

  const RouteMap({
    super.key,
    required this.from,
    required this.to,
    this.routePoints = const [],
    this.height = 200,
  });

  @override
  Widget build(BuildContext context) {
    final points = routePoints.isEmpty ? [from, to] : routePoints;
    return ClipRRect(
      borderRadius: BorderRadius.circular(Gz.radius),
      child: SizedBox(
        height: height,
        child: IgnorePointer(
          child: FlutterMap(
            options: MapOptions(
              initialCameraFit: CameraFit.bounds(
                bounds: LatLngBounds.fromPoints([from, to]),
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
                pointMarker(to, color: Gz.red),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
