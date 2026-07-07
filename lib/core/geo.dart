import 'dart:convert';
import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Гео-қызметтер: адрес іздеу (Nominatim/Photon), маршрут (OSRM), локация.
class Geo {
  static const _ua = {'User-Agent': 'GazelGo/1.0 (gazelgo.kz)'};

  /// Әдепкі орталық — Алматы.
  static const almaty = LatLng(43.238949, 76.889709);

  static Future<Position?> currentPosition() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return null;
      }
      return await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 8));
    } catch (_) {
      return null;
    }
  }

  /// Адрес іздеу (Қазақстан шегінде).
  static Future<List<GeoPlace>> search(String query) async {
    final q = query.trim();
    if (q.length < 3) return [];
    try {
      final uri = Uri.parse('https://nominatim.openstreetmap.org/search')
          .replace(queryParameters: {
        'q': q,
        'format': 'jsonv2',
        'countrycodes': 'kz',
        'limit': '8',
        'accept-language': 'kk,ru',
      });
      final res = await http.get(uri, headers: _ua)
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return [];
      final list = jsonDecode(res.body) as List;
      return list
          .map((e) => GeoPlace(
                name: (e['display_name'] as String).split(',').take(3).join(','),
                point: LatLng(double.parse(e['lat'] as String),
                    double.parse(e['lon'] as String)),
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Координатадан адрес атауы.
  static Future<String> reverse(LatLng p) async {
    try {
      final uri = Uri.parse('https://nominatim.openstreetmap.org/reverse')
          .replace(queryParameters: {
        'lat': '${p.latitude}',
        'lon': '${p.longitude}',
        'format': 'jsonv2',
        'accept-language': 'kk,ru',
      });
      final res = await http.get(uri, headers: _ua)
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return _coordLabel(p);
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final a = j['address'] as Map<String, dynamic>?;
      if (a != null) {
        final parts = [
          a['road'] ?? a['pedestrian'] ?? a['neighbourhood'] ?? a['suburb'],
          a['house_number'],
          a['city'] ?? a['town'] ?? a['village'] ?? a['county'],
        ].whereType<String>().toList();
        if (parts.isNotEmpty) return parts.join(', ');
      }
      final dn = j['display_name'] as String?;
      return dn == null ? _coordLabel(p) : dn.split(',').take(3).join(',');
    } catch (_) {
      return _coordLabel(p);
    }
  }

  static String _coordLabel(LatLng p) =>
      '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}';

  /// Маршрут: OSRM демо-сервері, болмаса хаверсин × 1.3.
  static Future<GeoRoute> route(LatLng from, LatLng to) async {
    try {
      final uri = Uri.parse(
          'https://router.project-osrm.org/route/v1/driving/'
          '${from.longitude},${from.latitude};${to.longitude},${to.latitude}'
          '?overview=full&geometries=geojson');
      final res = await http.get(uri, headers: _ua)
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final j = jsonDecode(res.body) as Map<String, dynamic>;
        final routes = j['routes'] as List?;
        if (routes != null && routes.isNotEmpty) {
          final r = routes.first as Map<String, dynamic>;
          final coords =
              ((r['geometry'] as Map)['coordinates'] as List).cast<List>();
          return GeoRoute(
            distanceKm: (r['distance'] as num).toDouble() / 1000,
            durationMin: (r['duration'] as num).toDouble() / 60,
            points: coords
                .map((c) =>
                    LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
                .toList(),
          );
        }
      }
    } catch (_) {
      // fallback төменде
    }
    final km = haversineKm(from, to) * 1.3;
    return GeoRoute(
      distanceKm: km,
      durationMin: km / 40 * 60,
      points: [from, to],
    );
  }

  static double haversineKm(LatLng a, LatLng b) {
    const r = 6371.0;
    final dLat = _rad(b.latitude - a.latitude);
    final dLon = _rad(b.longitude - a.longitude);
    final h = math.pow(math.sin(dLat / 2), 2) +
        math.cos(_rad(a.latitude)) *
            math.cos(_rad(b.latitude)) *
            math.pow(math.sin(dLon / 2), 2);
    return 2 * r * math.asin(math.sqrt(h.toDouble()));
  }

  static double _rad(double d) => d * math.pi / 180;
}

class GeoPlace {
  final String name;
  final LatLng point;
  GeoPlace({required this.name, required this.point});
}

class GeoRoute {
  final double distanceKm;
  final double durationMin;
  final List<LatLng> points;
  GeoRoute(
      {required this.distanceKm,
      required this.durationMin,
      required this.points});
}
