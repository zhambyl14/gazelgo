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
    return _searchFree(q);
  }

  /// Көше/үй/НЫСАН іздеу — таңдалған қала мен оның маңы ішінде.
  ///
  /// ЕКІ сұраныс қатар жіберіледі, себебі олар БАСҚА-БАСҚА нәрсе табады:
  ///  1) структуралық (`street=`+`city=`) — «Бараева 25» тәрізді адрестер;
  ///  2) еркін мәтін («<сұраныс>, <қала>») — «Хан Шатыр», «MEGA», «ЖК Хайвилл»
  ///     тәрізді ТРЦ/ЖК/дүкен АТТАРЫ. Структуралық сұраныс мұндай нысанды
  ///     ешқашан таппайды (ол тек көше индексінен іздейді) — бұрын клиент
  ///     «МЕГА» деп жазса нәтиже нөл болатын, сол себепті осы қосылды.
  static Future<List<GeoPlace>> searchStreet({
    required String city,
    required String street,
    LatLng? near,
  }) async {
    final s = street.trim();
    if (s.length < 2) return [];
    final bias = near ?? _cityCenter(city);
    final res = await Future.wait([
      _searchStructured(city: city, street: s),
      _searchFree('$s, $city', near: bias),
    ]);
    return dedupePlaces([...res[0], ...res[1]]);
  }

  /// Елді мекен іздеу (қала/кент/ауыл/станция) — қала таңдау парағы үшін.
  /// kzCities тізімінде ЖОҚ шағын елді мекендерді (Мерке, Луговой,
  /// Ерейментау, Қосшы…) табу үшін керек.
  static Future<List<GeoPlace>> searchSettlement(String query) async {
    final q = query.trim();
    if (q.length < 2) return [];
    try {
      final uri = Uri.parse('https://nominatim.openstreetmap.org/search')
          .replace(queryParameters: {
        'q': q,
        'format': 'jsonv2',
        'countrycodes': 'kz',
        'limit': '20',
        'addressdetails': '1',
        'accept-language': 'kk,ru',
      });
      final res = await http.get(uri, headers: _ua)
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return [];
      final list = jsonDecode(res.body) as List;
      final out = <GeoPlace>[];
      for (final raw in list) {
        final e = raw as Map<String, dynamic>;
        final type = _str(e['addresstype']) ?? _str(e['type']) ?? '';
        if (!_settlementTypes.contains(type)) continue;
        final name = _str(e['name']) ??
            _str((e['display_name'] as String?)?.split(',').first);
        if (name == null) continue;
        out.add(GeoPlace(
          name: name,
          point: LatLng(double.parse(e['lat'] as String),
              double.parse(e['lon'] as String)),
          city: name,
          kind: type,
        ));
      }
      return dedupePlaces(out);
    } catch (_) {
      return [];
    }
  }

  static const _settlementTypes = {
    'city',
    'town',
    'village',
    'hamlet',
    'municipality',
    'suburb',
    'borough',
    'quarter',
    'neighbourhood',
    'isolated_dwelling',
    'allotments',
  };

  static Future<List<GeoPlace>> _searchFree(String q, {LatLng? near}) async {
    try {
      final params = <String, String>{
        'q': q,
        'format': 'jsonv2',
        'countrycodes': 'kz',
        'limit': '10',
        'addressdetails': '1',
        'namedetails': '1',
        'accept-language': 'kk,ru',
      };
      if (near != null) {
        // ~60 км viewbox — нәтижелерді осы аймаққа қарай бұрады (bounded=1
        // ҚОЙМАЙМЫЗ: қала шетіндегі ауыл түсіп қалмауы үшін).
        const d = 0.55;
        params['viewbox'] = '${near.longitude - d},${near.latitude + d},'
            '${near.longitude + d},${near.latitude - d}';
      }
      final uri = Uri.parse('https://nominatim.openstreetmap.org/search')
          .replace(queryParameters: params);
      final res = await http.get(uri, headers: _ua)
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return [];
      final list = jsonDecode(res.body) as List;
      return list.map((e) => _placeFrom(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<GeoPlace>> _searchStructured(
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
        'namedetails': '1',
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

  /// Бірдей атау + бірдей маңдағы нүктелерді біріктіреді (екі сұраныстың
  /// нәтижесі қосылғанда қосарлануы мүмкін).
  static List<GeoPlace> dedupePlaces(List<GeoPlace> src) {
    final seen = <String>{};
    final out = <GeoPlace>[];
    for (final p in src) {
      if (p.name.trim().isEmpty) continue;
      final key = '${p.name.trim().toLowerCase()}|'
          '${p.point.latitude.toStringAsFixed(3)},'
          '${p.point.longitude.toStringAsFixed(3)}';
      if (!seen.add(key)) continue;
      out.add(p);
    }
    return out;
  }

  /// Қала атауынан оның орталық координатасын қайтарады (белгілі болса).
  static LatLng? cityCenter(String? city) => _cityCenter(city);

  /// Нүктеге ЕҢ ЖАҚЫН «тірек қала» (kzCityCenters ішінен).
  ///
  /// НЕГЕ КЕРЕК: клиент Астананы таңдап, картадан Ерейментауды (не Таразды
  /// таңдап, Мерке/Луговойды) белгілегенде — бұл қате емес, сол аймақтағы
  /// қалыпты тапсырыс. Тірек қала арқылы «бұл сол аймақ па, әлде мүлдем
  /// басқа облыс па» дегенді ажыратамыз: аймақ ішінде болса үнсіз
  /// қабылдаймыз, мүлдем басқа аймақ болса ғана сұраймыз.
  ///
  /// Тірек қала заказдың `city` өрісіне жазылады — сол себепті лентадағы
  /// қала бойынша сүзгі (feed) бұзылмайды: Луговойдағы заказды Тараз
  /// орындаушылары бұрынғыдай көреді.
  static String? anchorCity(LatLng p, {double maxKm = 250}) {
    String? best;
    var bestKm = double.infinity;
    for (final e in kzCityCenters.entries) {
      final km = haversineKm(p, e.value);
      if (km < bestKm) {
        bestKm = km;
        best = e.key;
      }
    }
    return bestKm <= maxKm ? best : null;
  }

  /// Қаланың қызмет аймағының радиусы. Тараз → Мерке ~148 км,
  /// Астана → Ерейментау ~125 км осында сияды.
  static const cityAreaRadiusKm = 150.0;

  /// Нүкте [city] қаласының қызмет аймағында ма — картадан белгіленген жерді
  /// қабылдау ЕРЕЖЕСІ.
  ///
  /// Бұрын салыстыру тек қала АТЫ бойынша жүретін, сол себепті қала
  /// сыртындағы кез келген ауыл «басқа қала» саналып, клиент оны МҮЛДЕМ
  /// таңдай алмайтын. Енді ЕКІ шарттың бірі жетеді — олар бірін-бірі
  /// толықтырады:
  ///
  ///  1. Нүктеге ең жақын тірек қала — осы қала (Мерке/Луговой → Тараз,
  ///     Қосшы → Астана). Тек қашықтық шарты жарамайды: Мерке Тараздан
  ///     ~148 км, радиустың дәл шетінде.
  ///  2. Не болмаса қала орталығынан [cityAreaRadiusKm] шамасында. Бұл шарт
  ///     керек, себебі кей жерге басқа тірек қала жақынырақ болып шығады:
  ///     Ерейментау Астанадан 125 км, ал Степногорсктен 116 км.
  static bool inCityArea(LatLng p, String? city, {LatLng? center}) {
    if (!inKazakhstan(p)) return false;
    final anchor = anchorCity(p);
    if (anchor != null && sameCity(anchor, city)) return true;
    final c = center ?? _cityCenter(city);
    if (c == null) return true; // қала орталығы белгісіз — қарсы тұрмаймыз
    return haversineKm(p, c) <= cityAreaRadiusKm;
  }

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

  /// Nominatim жауабынан «нысан аты, көше, үй нөмірі» түріндегі таза атау
  /// құрайды (қала атауын, аудан/облысты жолға қоспайды).
  static GeoPlace _placeFrom(Map<String, dynamic> e) {
    final a = (e['address'] as Map?)?.cast<String, dynamic>();
    final parsed = _parse(e, a);
    return GeoPlace(
      name: parsed.label.isEmpty
          ? ((e['display_name'] as String?) ?? '').split(',').take(2).join(',')
          : parsed.label,
      point: LatLng(double.parse(e['lat'] as String),
          double.parse(e['lon'] as String)),
      city: parsed.settlement,
      kind: _str(e['type']),
    );
  }

  static String? _str(Object? v) {
    if (v is! String) return null;
    final s = v.trim();
    return s.isEmpty ? null : s;
  }

  /// Нақты елді мекен (қала/кент/АУЫЛ). Тәртіп маңызды: `village`/`town`
  /// `city`-ден БҰРЫН тұр, себебі Nominatim ауылдың жауабында облыс орталығын
  /// да `city` етіп қайтаруы мүмкін — сонда Луговой «Тараз» болып кетеді.
  static String? _cityOf(Map<String, dynamic>? a) {
    if (a == null) return null;
    final raw = _str(a['village']) ??
        _str(a['hamlet']) ??
        _str(a['town']) ??
        _str(a['city']) ??
        _str(a['municipality']) ??
        _str(a['county']);
    return raw == null ? null : displayCity(raw);
  }

  /// `address` ішіндегі НЫСАН (ТРЦ/ЖК/дүкен/ғимарат) атын беретін кілттер.
  static const _poiKeys = [
    'amenity',
    'shop',
    'mall',
    'office',
    'tourism',
    'leisure',
    'healthcare',
    'club',
    'craft',
    'historic',
    'man_made',
    'aeroway',
    'railway',
    'building',
    'residential',
  ];

  /// Nominatim жауабын бөлшектейді: нысан аты / көше+үй / елді мекен.
  static _Parsed _parse(Map<String, dynamic> e, Map<String, dynamic>? a) {
    // Көше + үй нөмірі.
    final road = _str(a?['road']) ??
        _str(a?['pedestrian']) ??
        _str(a?['footway']) ??
        _str(a?['neighbourhood']) ??
        _str(a?['quarter']) ??
        _str(a?['suburb']);
    final house = _str(a?['house_number']);
    final street = road == null ? null : (house == null ? road : '$road, $house');

    // Нысан аты: жергілікті тілдегі атау → жауаптың `name` өрісі →
    // `address` ішіндегі нысан кілттері.
    final nd = (e['namedetails'] as Map?)?.cast<String, dynamic>();
    var poi = _str(nd?['name:kk']) ?? _str(nd?['name:ru']) ?? _str(nd?['name']);
    poi ??= _str(e['name']);
    if (poi == null && a != null) {
      for (final k in _poiKeys) {
        final v = _str(a[k]);
        // `building=yes` тәрізді техникалық мәндер атау емес.
        if (v != null && v != 'yes' && v != 'true') {
          poi = v;
          break;
        }
      }
    }
    // Nominatim КӨШЕНІҢ өзін қайтарғанда `name` = көше аты болады — оны
    // «нысан» деп қайталап жазбаймыз («Абая, Абая, 5» болып кетпеуі үшін).
    if (poi != null && road != null && poi.toLowerCase() == road.toLowerCase()) {
      poi = null;
    }

    return _Parsed(
      poi: poi,
      street: street,
      settlement: _cityOf(a),
    );
  }

  /// Nominatim қайтаратын әкімшілік жұрнақтар. Тізім қайталап қолданылады,
  /// сол себепті «Ерейментау қаласы әкімдігі» → «қаласы» → «Ерейментау»
  /// болып екі қадамда тазарады (бәрін бір жолмен жазудың қажеті жоқ).
  static const _cityAdminSuffixes = [
    'қалалық әкімшілігі',
    'қаласының әкімшілігі',
    'әкімшілігі',
    'әкімдігі',
    'қ.ә.',
    'а.ә.',
    'а.о.',
    'қаласы',
    'ауданы',
    'ауданының',
    'қаласының',
    'облысы',
    'қалалық',
    'аудандық',
    'ауылдық',
    'кенттік',
    'селолық',
    'округі',
    'округ',
    'ауылы',
    'кенті',
    'селосы',
    'городская администрация',
    'администрация города',
    'сельский округ',
    'поселковый округ',
    'акимат города',
    'акимат',
    'города',
    'город',
    'село',
    'посёлок',
    'поселок',
  ];

  /// Атаудың соңындағы әкімшілік жұрнақтарын қайталап алып тастайды.
  ///
  /// Жұрнақ ЖЕКЕ СӨЗ болуы шарт (алдында бос орын тұруы керек), әйтпесе
  /// «Белгород» → «Бел», «Ақсело» → «Ақ» болып атаулар бүлінеді.
  static String _stripAdmin(String raw) {
    var s = raw.trim();
    var changed = true;
    while (changed) {
      changed = false;
      final low = s.toLowerCase();
      for (final suf in _cityAdminSuffixes) {
        final cut = s.length - suf.length;
        if (cut > 0 && low.endsWith(suf) && _isBoundary(s[cut - 1])) {
          s = s.substring(0, cut).trim();
          changed = true;
          break;
        }
      }
    }
    // Тазалаудан кейін қалған тыныс белгілерін алып тастаймыз («Тараз,» → «Тараз»).
    return s.replaceAll(RegExp(r'[\s,\-—]+$'), '');
  }

  static bool _isBoundary(String ch) => ch == ' ' || ch == ',' || ch == '-';

  /// Қала атауын салыстыруға дайындайды: әкімшілік жұрнақтарын алып тастайды.
  /// («Тараз қаласы» мен «Тараз қалалық әкімшілігі» бір қала болып саналуы үшін.)
  static String normalizeCity(String raw) => _stripAdmin(raw).toLowerCase();

  /// Клиентке КӨРСЕТУГЕ лайық атау: «Ерейментау қаласы әкімдігі» →
  /// «Ерейментау». Адрес жолында кеңсе тілі тұрмауы керек, ал бас әріп
  /// сақталады (сол себепті [normalizeCity] жарамайды — ол кіші әріпке
  /// түсіреді, тек салыстыруға арналған).
  static String displayCity(String raw) {
    final s = _stripAdmin(raw);
    return s.isEmpty ? raw.trim() : s;
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

  /// Координатадан адрес атауы + елді мекен (межгород анықтау үшін).
  static Future<(String, String?)> reverseWithCity(LatLng p) async {
    final a = await reverseDetailed(p);
    return (a.label, a.settlement);
  }

  /// Координатадан ТОЛЫҚ адрес: нысан аты + көше/үй + елді мекен.
  ///
  /// `zoom=18` + `namedetails=1` МІНДЕТТІ: осылар болмаса Nominatim тек көше
  /// деңгейін қайтарады да, ТРЦ/ЖК/базар аты жоғалып, адрес «жәй ғана көше»
  /// болып жазылады (клиенттердің басты шағымы дәл сол еді).
  static Future<GeoAddress> reverseDetailed(LatLng p) async {
    try {
      final uri = Uri.parse('https://nominatim.openstreetmap.org/reverse')
          .replace(queryParameters: {
        'lat': '${p.latitude}',
        'lon': '${p.longitude}',
        'format': 'jsonv2',
        'zoom': '18',
        'addressdetails': '1',
        'namedetails': '1',
        'accept-language': 'kk,ru',
      });
      final res = await http.get(uri, headers: _ua)
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return GeoAddress.unknown(p);
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final a = (j['address'] as Map?)?.cast<String, dynamic>();
      final parsed = _parse(j, a);
      if (parsed.label.isNotEmpty) {
        return GeoAddress(
          poi: parsed.poi,
          street: parsed.street,
          settlement: parsed.settlement,
          point: p,
        );
      }
      final dn = _str(j['display_name']);
      return GeoAddress(
        poi: null,
        street: dn?.split(',').take(2).join(',').trim(),
        settlement: parsed.settlement,
        point: p,
      );
    } catch (_) {
      return GeoAddress.unknown(p);
    }
  }

  /// Нүктенің МАҢЫНДАҒЫ аты бар нысандар (ТРЦ, ЖК, базар, дүкен, мектеп…).
  ///
  /// Nominatim тек пин ДӘЛ ғимарат контурының ішіне түскенде ғана оның атын
  /// біледі. Клиент үлкен ТРЦ-ны белгілегенде пин көбіне тұраққа не жолға
  /// түседі де, атау жоғалады. Сол себепті Overpass арқылы маңайдағы аты бар
  /// нысандарды бөлек сұраймыз да, клиентке «мынау ма?» деп ұсынамыз.
  ///
  /// Тегін қызмет — қатесі/таймауты болса үнсіз бос тізім қайтарады (бұл
  /// қосымша мүмкіндік, адрес таңдау онсыз да жұмыс істейді).
  static Future<List<GeoPlace>> nearbyPlaces(
    LatLng p, {
    int radiusM = 180,
    int limit = 12,
  }) async {
    final key = '${p.latitude.toStringAsFixed(4)},'
        '${p.longitude.toStringAsFixed(4)},$radiusM';
    final cached = _nearbyCache[key];
    if (cached != null) return cached;
    try {
      final q = '[out:json][timeout:20];'
          'nwr(around:$radiusM,${p.latitude},${p.longitude})'
          '[name][~"^(amenity|shop|office|tourism|leisure|building)\$"~"."];'
          'out center 60;';
      final body = await _overpass(q);
      if (body == null) return const [];
      final j = jsonDecode(body) as Map<String, dynamic>;
      final els = (j['elements'] as List?) ?? const [];
      final out = <GeoPlace>[];
      for (final raw in els) {
        final e = (raw as Map).cast<String, dynamic>();
        final tags = (e['tags'] as Map?)?.cast<String, dynamic>() ?? const {};
        final name = _str(tags['name:kk']) ??
            _str(tags['name:ru']) ??
            _str(tags['name']);
        if (name == null) continue;
        final center = (e['center'] as Map?)?.cast<String, dynamic>();
        final lat = (e['lat'] ?? center?['lat']) as num?;
        final lon = (e['lon'] ?? center?['lon']) as num?;
        if (lat == null || lon == null) continue;
        final at = LatLng(lat.toDouble(), lon.toDouble());
        final street = [
          _str(tags['addr:street']),
          _str(tags['addr:housenumber']),
        ].whereType<String>().join(', ');
        out.add(GeoPlace(
          name: street.isEmpty ? name : '$name, $street',
          point: at,
          kind: _str(tags['shop']) ??
              _str(tags['amenity']) ??
              _str(tags['tourism']) ??
              _str(tags['leisure']) ??
              _str(tags['office']) ??
              _str(tags['building']),
          distanceM: haversineKm(p, at) * 1000,
        ));
      }
      // Ірі нысандар (ТРЦ, базар, ЖК, аурухана…) алдымен, содан кейін
      // қашықтық бойынша — клиент іздеп тұрғаны әдетте солар.
      out.sort((x, y) {
        final b = (_bigPoi(y.kind) ? 1 : 0) - (_bigPoi(x.kind) ? 1 : 0);
        if (b != 0) return b;
        return (x.distanceM ?? 0).compareTo(y.distanceM ?? 0);
      });
      final result = dedupePlaces(out).take(limit).toList(growable: false);
      if (_nearbyCache.length > 40) _nearbyCache.clear();
      _nearbyCache[key] = result;
      return result;
    } catch (_) {
      return const [];
    }
  }

  static final Map<String, List<GeoPlace>> _nearbyCache = {};

  /// Overpass айналары. Тегін серверлер жиі бос болмай қалады (504
  /// «server is probably too busy»), сол себепті бірінші жауап бергенін
  /// аламыз да, бәрі құласа үнсіз бас тартамыз.
  static const _overpassEndpoints = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.private.coffee/api/interpreter',
    'https://overpass.osm.ch/api/interpreter',
  ];

  static Future<String?> _overpass(String query) async {
    for (final ep in _overpassEndpoints) {
      try {
        final res = await http
            .post(Uri.parse(ep), headers: _ua, body: {'data': query})
            .timeout(const Duration(seconds: 14));
        // Сервер бос болмаса HTML қате бетін қайтарады — JSON емесін тексереміз.
        if (res.statusCode == 200 && res.body.trimLeft().startsWith('{')) {
          return res.body;
        }
      } catch (_) {
        // келесі айнаға көшеміз
      }
    }
    return null;
  }

  static const _bigPoiKinds = {
    'mall',
    'department_store',
    'supermarket',
    'marketplace',
    'apartments',
    'residential',
    'commercial',
    'retail',
    'hospital',
    'clinic',
    'university',
    'college',
    'school',
    'hotel',
    'stadium',
    'bus_station',
    'train_station',
    'terminal',
    'warehouse',
    'industrial',
  };

  static bool _bigPoi(String? kind) =>
      kind != null && _bigPoiKinds.contains(kind);

  static String coordLabel(LatLng p) =>
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

  /// Нақты елді мекен (ауыл/кент/қала) — тірек қала ЕМЕС.
  final String? city;

  /// OSM түрі (`mall`, `apartments`, `village`…) — белгіше мен сұрыптау үшін.
  final String? kind;

  /// Іздеу нүктесінен қашықтық (метр) — маңайдағы нысандар тізімінде ғана.
  final double? distanceM;

  GeoPlace({
    required this.name,
    required this.point,
    this.city,
    this.kind,
    this.distanceM,
  });
}

/// Reverse-геокодтау нәтижесінің БӨЛШЕКТЕЛГЕН түрі.
///
/// Бөлшектеп сақтаудың мәні: елді мекенді қашан қосу керегін ШАҚЫРУШЫ
/// шешеді. Клиент «Астана» деп таңдап тұрғанда адрес жолында «Астана»
/// қайталанбауы керек, ал Ерейментауды белгілегенде — «Ерейментау» МІНДЕТТІ
/// түрде жазылуы керек, әйтпесе орындаушы қайда баратынын білмейді.
class GeoAddress {
  /// Ғимарат/ТРЦ/ЖК/базар аты (болса).
  final String? poi;

  /// «Көше, үй нөмірі» (болса).
  final String? street;

  /// Нақты елді мекен (ауыл/кент/қала).
  final String? settlement;

  final LatLng point;

  const GeoAddress({
    required this.poi,
    required this.street,
    required this.settlement,
    required this.point,
  });

  factory GeoAddress.unknown(LatLng p) =>
      GeoAddress(poi: null, street: null, settlement: null, point: p);

  /// Елді мекенсіз атау: «Хан Шатыр, Түркістан, 37».
  String get label => [poi, street].whereType<String>().join(', ');

  /// Таңдалған қалаға ҚАТЫСТЫ толық атау.
  ///
  /// Елді мекен таңдалған қаладан бөлек болса — алдына қосылады
  /// («Ерейментау, Абая, 5»), себебі бұл маңызды ақпарат. Бірдей болса —
  /// қосылмайды (қала өрісі онсыз да бөлек көрсетіліп тұр).
  String labelFor(String? selectedCity) {
    final base = label;
    final s = settlement;
    final needsSettlement =
        s != null && s.isNotEmpty && !Geo.sameCity(s, selectedCity);
    if (base.isEmpty) {
      return needsSettlement ? s : Geo.coordLabel(point);
    }
    return needsSettlement ? '$s, $base' : base;
  }
}

/// Nominatim жауабының бөлшектелген түрі (ішкі қолданыс).
class _Parsed {
  final String? poi;
  final String? street;
  final String? settlement;
  const _Parsed({this.poi, this.street, this.settlement});

  String get label => [poi, street].whereType<String>().join(', ');
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
