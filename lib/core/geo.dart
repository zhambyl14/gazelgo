import 'dart:convert';
import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'kz_cities.dart';

/// Гео-қызметтер: адрес іздеу (Nominatim/OSM), маршрут (OSRM), локация.
///
/// Ескерту: тегін OSM деректері Қазақстанның кейбір шағын аудандарын білмейді.
/// Сол себепті клиент адресті таппаса, картадан дәл жерді өзі белгілейді, ал
/// түзетілген атаулар серверде (address_corrections) жиналып, кейін ұсынылады.
class Geo {
  static const _ua = {'User-Agent': 'GazelGo/1.0 (gazelgo.kz)'};

  /// Әдепкі орталық — Алматы.
  static const almaty = LatLng(43.238949, 76.889709);

  /// Нүкте Қазақстан шекарасында ма? (шамамен bounding box)
  static bool inKazakhstan(LatLng p) =>
      p.latitude >= 40 &&
      p.latitude <= 56 &&
      p.longitude >= 46 &&
      p.longitude <= 88;

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

  /// Адрес іздеу (Қазақстан шегінде) — Nominatim (OSM).
  static Future<List<GeoPlace>> search(String query) async {
    final q = query.trim();
    if (q.length < 3) return [];
    return _searchNominatim(q);
  }

  /// Көше/үй іздеу — таңдалған қала ішінде (структуралық сұраныс, OSM).
  static Future<List<GeoPlace>> searchStreet(
      {required String city, required String street}) async {
    final s = street.trim();
    if (s.length < 2) return [];
    return _searchStreetNominatim(city: city, street: s);
  }

  static Future<List<GeoPlace>> _searchNominatim(String q) async {
    try {
      final uri = Uri.parse('https://nominatim.openstreetmap.org/search')
          .replace(queryParameters: {
        'q': q,
        'format': 'jsonv2',
        'countrycodes': 'kz',
        'limit': '8',
        'addressdetails': '1',
        'accept-language': 'kk,ru',
      });
      final res = await http.get(uri, headers: _ua)
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return [];
      final list = jsonDecode(res.body) as List;
      return list.map((e) => _placeFrom(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<GeoPlace>> _searchStreetNominatim(
      {required String city, required String street}) async {
    try {
      final uri = Uri.parse('https://nominatim.openstreetmap.org/search')
          .replace(queryParameters: {
        'street': street,
        'city': city,
        'country': 'Kazakhstan',
        'format': 'jsonv2',
        'countrycodes': 'kz',
        'limit': '8',
        'addressdetails': '1',
        'accept-language': 'kk,ru',
      });
      final res = await http.get(uri, headers: _ua)
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return [];
      final list = jsonDecode(res.body) as List;
      return list.map((e) => _placeFrom(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Қала атауынан оның орталық координатасын қайтарады (белгілі болса).
  static LatLng? cityCenter(String? city) => _cityCenter(city);

  /// Қала атауынан оның орталық координатасын табады (bias үшін).
  static LatLng? _cityCenter(String? city) {
    if (city == null) return null;
    final n = normalizeCity(city);
    if (n.isEmpty) return null;
    for (final e in kzCityCenters.entries) {
      if (normalizeCity(e.key) == n) return e.value;
    }
    return null;
  }

  /// Nominatim жауабынан «көше, үй нөмірі» түріндегі таза атау құрайды
  /// (қала атауын, аудан/облысты жолға қоспайды).
  static GeoPlace _placeFrom(Map<String, dynamic> e) {
    final a = e['address'] as Map<String, dynamic>?;
    String name;
    if (a != null) {
      final parts = [
        a['road'] ?? a['pedestrian'] ?? a['neighbourhood'] ?? a['suburb'],
        a['house_number'],
      ].whereType<String>().toList();
      name = parts.isNotEmpty
          ? parts.join(', ')
          : (e['display_name'] as String).split(',').take(2).join(',');
    } else {
      name = (e['display_name'] as String).split(',').take(2).join(',');
    }
    return GeoPlace(
      name: name,
      point: LatLng(double.parse(e['lat'] as String),
          double.parse(e['lon'] as String)),
      city: _cityOf(a),
    );
  }

  static String? _cityOf(Map<String, dynamic>? a) {
    if (a == null) return null;
    final c = a['city'] ?? a['town'] ?? a['municipality'] ?? a['village'] ?? a['county'];
    return c is String ? c : null;
  }

  static const _cityAdminSuffixes = [
    'қалалық әкімшілігі',
    'қаласының әкімшілігі',
    'әкімшілігі',
    'қаласы',
    'ауданы',
    'облысы',
    'селолық округі',
    'ауылдық округі',
    'городская администрация',
    'администрация города',
    'города',
    'город',
  ];

  /// Қала атауын салыстыруға дайындайды: әкімшілік жұрнақтарын алып тастайды.
  /// («Тараз қаласы» мен «Тараз қалалық әкімшілігі» бір қала болып саналуы үшін.)
  static String normalizeCity(String raw) {
    var s = raw.trim().toLowerCase();
    var changed = true;
    while (changed) {
      changed = false;
      for (final suf in _cityAdminSuffixes) {
        if (s.endsWith(suf)) {
          s = s.substring(0, s.length - suf.length).trim();
          changed = true;
        }
      }
    }
    return s;
  }

  /// Екі қала атауы шын мәнінде бір қала ма (әкімшілік жұрнақтарды алып тастап салыстыру).
  static bool sameCity(String? a, String? b) {
    if (a == null || b == null) return false;
    final na = normalizeCity(a);
    final nb = normalizeCity(b);
    if (na.isEmpty || nb.isEmpty) return false;
    return na == nb || na.contains(nb) || nb.contains(na);
  }

  /// Координатадан адрес атауы (қала атауынсыз).
  static Future<String> reverse(LatLng p) async => (await reverseWithCity(p)).$1;

  /// Координатадан адрес атауы + қала атауы (межгород анықтау үшін) — Nominatim.
  static Future<(String, String?)> reverseWithCity(LatLng p) async {
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
      if (res.statusCode != 200) return (_coordLabel(p), null);
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final a = j['address'] as Map<String, dynamic>?;
      final city = _cityOf(a);
      if (a != null) {
        final parts = [
          a['road'] ?? a['pedestrian'] ?? a['neighbourhood'] ?? a['suburb'],
          a['house_number'],
        ].whereType<String>().toList();
        if (parts.isNotEmpty) return (parts.join(', '), city);
      }
      final dn = j['display_name'] as String?;
      return (dn == null ? _coordLabel(p) : dn.split(',').take(2).join(','), city);
    } catch (_) {
      return (_coordLabel(p), null);
    }
  }

  static String _coordLabel(LatLng p) =>
      '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}';

  /// Маршрут: OSRM демо-сервері, болмаса хаверсин × 1.3.
  static Future<GeoRoute> route(LatLng from, LatLng to) =>
      routeVia([from, to]);

  /// Маршрут БІРНЕШЕ нүкте арқылы (аралық аялдамалармен, 0047).
  /// OSRM нүктелерді `;` арқылы қабылдайды әрі оларды БЕРІЛГЕН РЕТПЕН
  /// жүреді (қайта реттемейді) — клиент қосқан адрес тәртібі сақталады.
  ///
  /// [points] кемінде 2 нүкте болуы шарт; біреу ғана болса нөлдік маршрут
  /// қайтады (қосымша сынбауы үшін).
  static Future<GeoRoute> routeVia(List<LatLng> points) async {
    if (points.length < 2) {
      return GeoRoute(distanceKm: 0, durationMin: 0, points: points);
    }
    try {
      final coordsPath =
          points.map((p) => '${p.longitude},${p.latitude}').join(';');
      final uri = Uri.parse(
          'https://router.project-osrm.org/route/v1/driving/$coordsPath'
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
    // OSRM қолжетімсіз болса — түзу сызық бойынша шамалау (әр аялдама
    // арасындағы бөлікті ҚОСЫП есептейміз, 1.3 — жол қиралығына түзету).
    var km = 0.0;
    for (var i = 0; i + 1 < points.length; i++) {
      km += haversineKm(points[i], points[i + 1]);
    }
    km *= 1.3;
    return GeoRoute(
      distanceKm: km,
      durationMin: km / 40 * 60,
      points: List.of(points),
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
  final String? city;
  GeoPlace({required this.name, required this.point, this.city});
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
