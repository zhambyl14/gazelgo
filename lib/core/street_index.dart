import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'geo.dart';
import 'geo_text.dart';

/// Қала көшелерінің АТАУЛАРЫ — қате жазылған мекенжайды түзету үшін.
///
/// Тегін геокодер (Nominatim) «толеби», «жельтоксан», «abaya» тәрізді қате
/// жазылған көшені мүлдем таппайды. Сол себепті қаланың барлық көше атауын
/// (OpenStreetMap, Overpass арқылы) БІР РЕТ жүктеп, құрылғыда 30 күн
/// сақтаймыз; іздеуде клиент жазғанын осы тізіммен салыстырып ([GeoText]),
/// дұрыс атауды тауып аламыз. Бір рет жүктелген соң желісіз де жұмыс істейді.
///
/// Индекс — тек КӨМЕКШІ: ол дайын болмаса не жүктелмей қалса, іздеу
/// бұрынғыдай геокодерлермен жұмыс істей береді.
class StreetIndex {
  /// Кэш кілті (қала + орталық).
  final String key;
  final List<StreetEntry> entries;

  StreetIndex._(this.key, this.entries);

  static final _mem = <String, StreetIndex>{};
  static final _loading = <String, Future<StreetIndex?>>{};

  static const _ttl = Duration(days: 30);
  // v2: шағын аудандар/тұрғын массивтер де сақталады (v1 кэші елеусіз
  // қалады да, бір рет қайта жүктеледі).
  static const _prefsPrefix = 'street_idx_v2:';
  static const _prefsKeys = 'street_idx_v2_keys';

  /// Құрылғыда ең көбі неше қаланың тізімі сақталады (ескісі өшеді).
  static const _maxCities = 4;

  /// Ірі қалалардың радиусы (метр) — қала шегін толық қамтуы үшін.
  static const _bigRadius = {
    'алматы': 18000.0,
    'астана': 15000.0,
    'шымкент': 14000.0,
    'караганди': 12000.0,
    'актобе': 11000.0,
    'тараз': 12000.0,
    'павлодар': 10000.0,
    'оскемен': 10000.0,
    'семеи': 10000.0,
    'атирау': 10000.0,
    'костанаи': 9000.0,
    'кизилорда': 9000.0,
    'орал': 9000.0,
    'петропавл': 8000.0,
    'актау': 9000.0,
  };

  static String _cacheKey(String city, LatLng c) =>
      '${GeoText.streetCore(city)}@'
      '${c.latitude.toStringAsFixed(2)},${c.longitude.toStringAsFixed(2)}';

  /// Жадта дайын тұрған индекс — бірден, желісіз (жоқ болса null).
  static StreetIndex? peek(String? city, LatLng? center) {
    if (city == null || center == null) return null;
    return _mem[_cacheKey(city, center)];
  }

  /// Индексті алу: жад → құрылғы кэші → Overpass. Қатар шақырулар бір
  /// сұрауға бірігеді. Қате болса — null (іздеу онсыз да жұмыс істейді).
  ///
  /// [settlement] — ауыл/кент таңдалса: ол үшін шағын радиус жеткілікті.
  static Future<StreetIndex?> load(
    String city,
    LatLng center, {
    bool settlement = false,
  }) {
    final key = _cacheKey(city, center);
    final ready = _mem[key];
    if (ready != null) return Future.value(ready);
    final pending = _loading[key];
    if (pending != null) return pending;
    final f = _load(key, city, center, settlement).whenComplete(() {
      // Блок түрінде — `=> _loading.remove(key)` өшірілген Future-дың ӨЗІН
      // қайтарар еді, ал whenComplete оны күтіп, мәңгі тұрып қалатын.
      _loading.remove(key);
    });
    _loading[key] = f;
    return f;
  }

  static Future<StreetIndex?> _load(
    String key,
    String city,
    LatLng center,
    bool settlement,
  ) async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_prefsPrefix$key');
      if (raw != null) {
        final idx = _decode(key, raw);
        if (idx != null) {
          _mem[key] = idx.$1;
          // Ескірген болса — көрсете береміз, фонда жаңартамыз.
          if (DateTime.now().difference(idx.$2) > _ttl) {
            unawaited(_fetchAndStore(key, city, center, settlement, prefs));
          }
          return idx.$1;
        }
      }
    } catch (_) {
      // кэш оқылмаса — желіден аламыз
    }
    return _fetchAndStore(key, city, center, settlement, prefs);
  }

  static Future<StreetIndex?> _fetchAndStore(
    String key,
    String city,
    LatLng center,
    bool settlement,
    SharedPreferences? prefs,
  ) async {
    final radius = settlement
        ? 4500.0
        : (_bigRadius[GeoText.streetCore(city)] ?? 7000.0);
    final r = radius.round();
    final at = '${center.latitude},${center.longitude}';
    final body = await _overpassCsv(
      '[out:csv(name,place,landuse,::lat,::lon;false;"|")][timeout:90];'
      '(way(around:$r,$at)'
      '[highway~"^(motorway|trunk|primary|secondary|tertiary|residential|'
      'unclassified|living_street|pedestrian|service|road)\$"][name];'
      // Шағын аудандар мен тұрғын массивтер («Абай шағын ауданы»,
      // «12-ші шағын ауданы», «ЖК …») — клиент мекенжайды солармен жазады.
      'nwr(around:$r,$at)[place~"^(suburb|neighbourhood|quarter)\$"][name];'
      'nwr(around:$r,$at)[landuse=residential][name];'
      ');out center;',
    );
    if (body == null) return null;
    final idx = _parseCsv(key, body, center);
    if (idx.entries.isEmpty) return null;
    _mem[key] = idx;
    try {
      final p = prefs ?? await SharedPreferences.getInstance();
      await p.setString('$_prefsPrefix$key', _encode(idx));
      final keys = [...(p.getStringList(_prefsKeys) ?? const <String>[])]
        ..remove(key)
        ..add(key);
      while (keys.length > _maxCities) {
        await p.remove('$_prefsPrefix${keys.removeAt(0)}');
      }
      await p.setStringList(_prefsKeys, keys);
    } catch (_) {
      // кэшке жазылмаса да, осы сессияда жадта тұр
    }
    return idx;
  }

  /// Overpass айналары — біріншісі жауап бермесе, келесісі.
  static const _endpoints = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.private.coffee/api/interpreter',
  ];

  static Future<String?> _overpassCsv(String query) async {
    for (final ep in _endpoints) {
      try {
        final res = await http
            .post(
              Uri.parse(ep),
              headers: kIsWeb
                  ? null
                  : const {'User-Agent': 'Tasu/1.0 (gazelgo.kz)'},
              body: {'data': query},
            )
            .timeout(const Duration(seconds: 100));
        if (res.statusCode == 200 && res.body.contains('|')) {
          return utf8.decode(res.bodyBytes);
        }
      } catch (_) {
        // келесі айнаға көшеміз
      }
    }
    return null;
  }

  /// «атау|place|landuse|lat|lon» жолдарынан индекс құрайды: бір атаудың
  /// бірнеше нүктесі (әртүрлі ауданда бірдей көше) 1,5 км-ден алыс болса —
  /// бөлек сақталады. place/landuse толы болса — бұл шағын аудан.
  static StreetIndex _parseCsv(String key, String body, LatLng center) {
    final byName = <(String, bool), List<LatLng>>{};
    for (final line in const LineSplitter().convert(body)) {
      final parts = line.split('|');
      if (parts.length < 5) continue;
      final name = parts[0].trim();
      final area = parts[1].trim().isNotEmpty || parts[2].trim().isNotEmpty;
      final lat = double.tryParse(parts[3]);
      final lon = double.tryParse(parts[4]);
      if (name.isEmpty || lat == null || lon == null) continue;
      (byName[(name, area)] ??= []).add(LatLng(lat, lon));
    }
    final entries = <StreetEntry>[];
    byName.forEach((k, pts) {
      final (name, area) = k;
      pts.sort(
        (a, b) =>
            Geo.haversineKm(center, a).compareTo(Geo.haversineKm(center, b)),
      );
      final kept = <LatLng>[];
      for (final p in pts) {
        if (kept.length >= 4) break;
        if (kept.every((k) => Geo.haversineKm(k, p) >= 1.5)) kept.add(p);
      }
      entries.add(StreetEntry(name, kept, area: area));
    });
    return StreetIndex._(key, entries);
  }

  static String _encode(StreetIndex idx) {
    final b = StringBuffer('${DateTime.now().millisecondsSinceEpoch}\n');
    for (final e in idx.entries) {
      b
        ..write(e.name.replaceAll('\t', ' ').replaceAll('\n', ' '))
        ..write('\t')
        ..write(
          e.points
              .map(
                (p) =>
                    '${p.latitude.toStringAsFixed(5)},'
                    '${p.longitude.toStringAsFixed(5)}',
              )
              .join(';'),
        )
        ..write(e.area ? '\ta' : '')
        ..write('\n');
    }
    return b.toString();
  }

  static (StreetIndex, DateTime)? _decode(String key, String raw) {
    final lines = const LineSplitter().convert(raw);
    if (lines.isEmpty) return null;
    final ms = int.tryParse(lines.first);
    if (ms == null) return null;
    final entries = <StreetEntry>[];
    for (final line in lines.skip(1)) {
      final cols = line.split('\t');
      if (cols.length < 2 || cols[0].isEmpty) continue;
      final pts = <LatLng>[];
      for (final s in cols[1].split(';')) {
        final c = s.split(',');
        if (c.length != 2) continue;
        final lat = double.tryParse(c[0]);
        final lon = double.tryParse(c[1]);
        if (lat != null && lon != null) pts.add(LatLng(lat, lon));
      }
      if (pts.isNotEmpty) {
        final area = cols.length > 2 && cols[2] == 'a';
        entries.add(StreetEntry(cols[0], pts, area: area));
      }
    }
    if (entries.isEmpty) return null;
    return (
      StreetIndex._(key, entries),
      DateTime.fromMillisecondsSinceEpoch(ms),
    );
  }

  /// Сұранысқа ең ұқсас көшелер (бір өзекті атаулар біреу болып
  /// біріктіріледі: «улица Абая» мен «Абай көшесі» — бір көше).
  ///
  /// [areas] — көшелердің орнына шағын аудандар/тұрғын массивтер ішінен.
  /// Толық сұраныс ештеңеге ұқсамаса, оның БІР БӨЛІГІ бойынша да іздейді
  /// («абай туран» → «Тұран көшесі»).
  List<StreetMatch> match(
    NameKey q, {
    int limit = 5,
    double minScore = 0.6,
    bool areas = false,
  }) {
    if (q.core.length < 2) return const [];
    var scored = _score(q, minScore, areas, words: false);
    if (!scored.any((m) => m.score >= 0.7)) {
      scored = _score(q, minScore, areas, words: true);
    }
    scored.sort((a, b) {
      final c = b.score.compareTo(a.score);
      if (c != 0) return c;
      return a.entry.name.length.compareTo(b.entry.name.length);
    });
    final seen = <String>{};
    final out = <StreetMatch>[];
    for (final m in scored) {
      if (!seen.add(m.entry.core)) continue;
      out.add(m);
      if (out.length >= limit) break;
    }
    return out;
  }

  List<StreetMatch> _score(
    NameKey q,
    double minScore,
    bool areas, {
    required bool words,
  }) {
    final out = <StreetMatch>[];
    for (final e in entries) {
      if (e.area != areas) continue;
      final s = GeoText.similarityKey(q, e.key, words: words);
      if (s >= minScore) out.add(StreetMatch(e, s));
    }
    return out;
  }
}

class StreetEntry {
  final String name;

  /// Көшенің бір не бірнеше нүктесі (орталыққа жақыны — бірінші).
  final List<LatLng> points;

  /// Көше емес — шағын аудан / тұрғын массив.
  final bool area;

  StreetEntry(this.name, this.points, {this.area = false});

  late final NameKey key = NameKey(name);
  late final String core = GeoText.streetCore(name);

  /// [ref] нүктесіне ең жақын нүктесі.
  LatLng nearestTo(LatLng? ref) {
    if (ref == null || points.length == 1) return points.first;
    var best = points.first;
    var bestKm = Geo.haversineKm(ref, best);
    for (final p in points.skip(1)) {
      final km = Geo.haversineKm(ref, p);
      if (km < bestKm) {
        bestKm = km;
        best = p;
      }
    }
    return best;
  }
}

class StreetMatch {
  final StreetEntry entry;
  final double score;
  const StreetMatch(this.entry, this.score);
}
