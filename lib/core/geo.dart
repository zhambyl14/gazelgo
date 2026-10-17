import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'geo_text.dart';
import 'kz_cities.dart';
import 'street_index.dart';

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

  /// Рұқсат СҰРАМАЙТЫН нұсқа — фондағы мерзімді жұмыс үшін (орындаушының
  /// орнын картаға жіберу). Рұқсат жоқ болса — үнсіз `null`.
  static Future<Position?> quietPosition() async {
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return null;
      }
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 8));
    } catch (_) {
      return null;
    }
  }

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
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 8));
    } catch (_) {
      return null;
    }
  }

  /// Адрес іздеу (Қазақстан шегінде) — Nominatim (OSM).
  ///
  /// Желі/сервер қатесінде [GeoSearchException] лақтырады — шақырушы
  /// «табылмады» мен «іздеу істемей тұр» дегенді ажырата алуы үшін (бұрын
  /// екеуі де бос тізім болып, клиент қате адрес жазып жүретін).
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
    // Бір сұраныс құлаған болса, екіншісінің нәтижесін көрсетеміз; тек
    // ЕКЕУІ де құласа ғана қате.
    Future<List<GeoPlace>?> safe(Future<List<GeoPlace>> f) async {
      try {
        return await f;
      } on GeoSearchException {
        return null;
      }
    }

    final res = await Future.wait([
      safe(_searchStructured(city: city, street: s)),
      safe(_searchFree('$s, $city', near: bias)),
    ]);
    if (res[0] == null && res[1] == null) throw const GeoSearchException();
    var merged = dedupePlaces([...?res[0], ...?res[1]]);

    // Клиент көшені ОРЫСША, қысқа жазады («Абая 15»), ал картада ол
    // қазақша («Абай даңғылы»), орысшасы тек «проспект Абая» түрінде
    // сақталған. Сол себепті Nominatim «Абая 15» деп басқа көшені (ескі
    // аты «Абая» болған Көкқайнардағы Мәмбетов көшесін) тауып беретін —
    // заказ ҚАТЕ жерге түсетін. Нәтиже терілген көшеге сәйкес келмесе,
    // «проспект …» / «улица …» нұсқаларымен қосымша іздейміз.
    final pq = parseStreetQuery(s);
    bool strong(GeoPlace p) => pq.key != null && placeMatches(p, pq.key!);
    if (pq.key != null && !pq.hasStreetWord && !merged.any(strong)) {
      final extra = await Future.wait([
        safe(_searchFree('проспект $s, $city', near: bias)),
        safe(_searchFree('улица $s, $city', near: bias)),
      ]);
      merged = dedupePlaces([...?extra[0], ...?extra[1], ...merged]);
    }

    // Сәйкес нәтижелер — тізімнің БАСЫНДА.
    final good = merged.where(strong).toList();
    final rest = merged.where((p) => !strong(p)).toList();
    final out = [...good, ...rest];

    // Үй нөмірі картада жоқ (Қазақстанда жиі), бірақ көшенің өзі табылды —
    // «Көше, нөмір» деп ұсынамыз; таңдағанда нүкте картадан РАСТАЛАДЫ.
    final number = pq.number;
    if (number != null &&
        !good.any((p) => _foldKey(p.name).contains(_foldKey(number)))) {
      final street = good.where((p) => _streetKinds.contains(p.kind));
      if (street.isNotEmpty) {
        final st = street.first;
        out.insert(
          0,
          GeoPlace(
            name: '${st.name}, $number',
            point: st.point,
            city: st.city,
            district: st.district,
            kind: kStreetApprox,
          ),
        );
      }
    }
    return out;
  }

  /// [searchStreet] нәтижесіндегі «көше табылды, үй нөмірі картада жоқ»
  /// жолының түрі — таңдалғанда нүкте картадан расталуы керек.
  static const kStreetApprox = 'street_approx';

  static const _streetKinds = {
    'motorway',
    'trunk',
    'primary',
    'secondary',
    'tertiary',
    'residential',
    'unclassified',
    'living_street',
    'pedestrian',
    'service',
    'road',
  };

  static const _streetWords = {
    'ул',
    'улица',
    'көшесі',
    'көше',
    'проспект',
    'пр',
    'просп',
    'даңғылы',
    'мкр',
    'микрорайон',
    'шағынаудан',
    'ықшамаудан',
    'переулок',
    'пер',
    'бульвар',
    'шоссе',
    'тас',
    'жолы',
    'тұйық',
    'тупик',
    'проезд',
    'мөлтек',
  };

  /// Іздеу мәтінін талдайды: көше атының «кілті» (салыстыру үшін), үй
  /// нөмірі және «көше/даңғыл» сияқты сөз бар-жоғы.
  static ({String? key, String? number, bool hasStreetWord}) parseStreetQuery(
    String q,
  ) {
    String? number;
    var hasStreetWord = false;
    String? word;
    for (final raw in q.toLowerCase().split(RegExp(r'[\s,.]+'))) {
      if (raw.isEmpty) continue;
      if (number == null &&
          RegExp(r'^\d+[а-яәғқңөұүһіa-z]?(/\d+)?$').hasMatch(raw)) {
        number = raw;
        continue;
      }
      if (_streetWords.contains(raw)) {
        hasStreetWord = true;
        continue;
      }
      final letters = _foldKey(raw);
      if (word == null && letters.length >= 3) word = letters;
    }
    String? key;
    if (word != null) {
      // Орысша септік жалғауы әр түрлі болады («Абая», «Абаю»…) — тек
      // түбірдің басын салыстырамыз: 3–5 әріп.
      var n = word.length - 1;
      if (n > 5) n = 5;
      if (n < 3) n = 3;
      key = word.substring(0, n > word.length ? word.length : n);
    }
    return (key: key, number: number, hasStreetWord: hasStreetWord);
  }

  /// Нәтиже терілген көшеге сәйкес пе (қазақ/орыс әріптерін бірдей санап).
  static bool placeMatches(GeoPlace p, String key) =>
      _foldKey('${p.name} ${p.district ?? ''}').contains(key);

  /// Салыстыруға арналған «жиналған» түр: кіші әріп, қазақ әріптері орыс
  /// баламасына, әріп пен цифрдан басқасы алынады.
  static String _foldKey(String s) {
    const map = {
      'ә': 'а',
      'ғ': 'г',
      'қ': 'к',
      'ң': 'н',
      'ө': 'о',
      'ұ': 'у',
      'ү': 'у',
      'һ': 'х',
      'і': 'и',
      'ё': 'е',
      'й': 'и',
      'ы': 'и',
      'ь': '',
      'ъ': '',
    };
    final b = StringBuffer();
    for (final ch in s.toLowerCase().split('')) {
      final m = map[ch] ?? ch;
      if (RegExp(r'[a-zа-я0-9/]').hasMatch(m)) b.write(m);
    }
    return b.toString();
  }

  /// Елді мекен іздеу (қала/кент/ауыл/станция) — қала таңдау парағы үшін.
  /// kzCities тізімінде ЖОҚ шағын елді мекендерді (Мерке, Луговой,
  /// Ерейментау, Қосшы…) табу үшін керек.
  static Future<List<GeoPlace>> searchSettlement(String query) async {
    final q = query.trim();
    if (q.length < 2) return [];
    try {
      final uri = Uri.parse('https://nominatim.openstreetmap.org/search')
          .replace(
            queryParameters: {
              'q': q,
              'format': 'jsonv2',
              'countrycodes': 'kz',
              'limit': '20',
              'addressdetails': '1',
              'accept-language': 'kk,ru',
            },
          );
      final res = await http
          .get(uri, headers: _ua)
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return [];
      final list = jsonDecode(res.body) as List;
      final out = <GeoPlace>[];
      for (final raw in list) {
        final e = raw as Map<String, dynamic>;
        final type = _str(e['addresstype']) ?? _str(e['type']) ?? '';
        if (!_settlementTypes.contains(type)) continue;
        final name =
            _str(e['name']) ??
            _str((e['display_name'] as String?)?.split(',').first);
        if (name == null) continue;
        out.add(
          GeoPlace(
            name: name,
            point: LatLng(
              double.parse(e['lat'] as String),
              double.parse(e['lon'] as String),
            ),
            city: name,
            kind: type,
          ),
        );
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

  /// Nominatim-ге сұраныс: 429/5xx/желі қатесінде бір рет қайталайды,
  /// сәтті нәтижені жадта сақтайды (бірдей сұраныс қайта жіберілмейді —
  /// тегін серверге жүктеме азаяды, ал клиент жылдам жауап алады).
  /// Сәтсіз болса [GeoSearchException] лақтырады.
  static Future<List<GeoPlace>> _getPlaces(Uri uri) async {
    final key = uri.toString();
    final cached = _placeCache[key];
    if (cached != null) return cached;
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 800));
      }
      try {
        final res = await http
            .get(uri, headers: _ua)
            .timeout(const Duration(seconds: 8));
        if (res.statusCode == 200) {
          final list = jsonDecode(res.body) as List;
          final out = <GeoPlace>[];
          for (final e in list) {
            try {
              out.add(_placeFrom(e as Map<String, dynamic>));
            } catch (_) {
              // бір бұзық жазба бүкіл тізімді құлатпауы керек
            }
          }
          if (_placeCache.length > 60) _placeCache.clear();
          _placeCache[key] = out;
          return out;
        }
        lastError = 'HTTP ${res.statusCode}';
        // 4xx (429-дан басқа) қайталаудың қажеті жоқ.
        if (res.statusCode < 500 && res.statusCode != 429) break;
      } catch (e) {
        lastError = e;
      }
    }
    throw GeoSearchException('$lastError');
  }

  static final Map<String, List<GeoPlace>> _placeCache = {};

  static Future<List<GeoPlace>> _searchFree(String q, {LatLng? near}) {
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
      params['viewbox'] =
          '${near.longitude - d},${near.latitude + d},'
          '${near.longitude + d},${near.latitude - d}';
    }
    return _getPlaces(
      Uri.parse(
        'https://nominatim.openstreetmap.org/search',
      ).replace(queryParameters: params),
    );
  }

  static Future<List<GeoPlace>> _searchStructured({
    required String city,
    required String street,
  }) {
    return _getPlaces(
      Uri.parse('https://nominatim.openstreetmap.org/search').replace(
        queryParameters: {
          'street': street,
          'city': city,
          'country': 'Kazakhstan',
          'format': 'jsonv2',
          'countrycodes': 'kz',
          'limit': '8',
          'addressdetails': '1',
          'namedetails': '1',
          'accept-language': 'kk,ru',
        },
      ),
    );
  }

  /// Бірдей атау + бірдей маңдағы нүктелерді біріктіреді (екі сұраныстың
  /// нәтижесі қосылғанда қосарлануы мүмкін).
  ///
  /// «Бірдей» = атауы бірдей ЖӘНЕ 300 м-ден жақын: картада бір үйдің бірнеше
  /// нысаны болады (ғимарат, банкомат, кіреберіс…) — бұрын тізімде
  /// «Төле би көшесі, 59» үш рет қатар тұратын.
  static List<GeoPlace> dedupePlaces(List<GeoPlace> src) {
    final out = <GeoPlace>[];
    for (final p in src) {
      final name = p.name.trim().toLowerCase();
      if (name.isEmpty) continue;
      final dup = out.any(
        (q) =>
            q.name.trim().toLowerCase() == name &&
            haversineKm(q.point, p.point) < 0.3,
      );
      if (!dup) out.add(p);
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
      point: LatLng(
        double.parse(e['lat'] as String),
        double.parse(e['lon'] as String),
      ),
      city: parsed.settlement,
      kind: _str(e['type']),
      district: _districtOf(a, parsed),
      road: parsed.road,
      house: parsed.house,
      poi: parsed.poi,
    );
  }

  /// Аудан атауы: көше аты ретінде қолданылмаған `suburb`/`city_district`
  /// не `neighbourhood` (қала/ауыл атынан басқа).
  static String? _districtOf(Map<String, dynamic>? a, _Parsed parsed) {
    if (a == null) return null;
    final road = _str(a['road']) ?? _str(a['pedestrian']) ?? _str(a['footway']);
    for (final k in const ['suburb', 'city_district', 'neighbourhood']) {
      final v = _str(a[k]);
      if (v == null) continue;
      if (road == null &&
          parsed.street != null &&
          parsed.street!.startsWith(v)) {
        continue; // ол көше орнына қолданылып кеткен
      }
      if (parsed.settlement != null && Geo.sameCity(v, parsed.settlement)) {
        continue;
      }
      return v;
    }
    return null;
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
    final raw =
        _str(a['village']) ??
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
    final road =
        _str(a?['road']) ??
        _str(a?['pedestrian']) ??
        _str(a?['footway']) ??
        _str(a?['neighbourhood']) ??
        _str(a?['quarter']) ??
        _str(a?['suburb']);
    final house = _str(a?['house_number']);
    final street = road == null
        ? null
        : (house == null ? road : '$road, $house');

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
    if (poi != null &&
        road != null &&
        poi.toLowerCase() == road.toLowerCase()) {
      poi = null;
    }

    return _Parsed(
      poi: poi,
      street: street,
      settlement: _cityOf(a),
      road: road,
      house: house,
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
  static Future<String> reverse(LatLng p) async =>
      (await reverseWithCity(p)).$1;

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
          .replace(
            queryParameters: {
              'lat': '${p.latitude}',
              'lon': '${p.longitude}',
              'format': 'jsonv2',
              'zoom': '18',
              'addressdetails': '1',
              'namedetails': '1',
              'accept-language': 'kk,ru',
            },
          );
      final res = await http
          .get(uri, headers: _ua)
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
          district: _districtOf(a, parsed),
        );
      }
      final dn = _str(j['display_name']);
      return GeoAddress(
        poi: null,
        street: dn?.split(',').take(2).join(',').trim(),
        settlement: parsed.settlement,
        point: p,
        district: _districtOf(a, parsed),
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
    final key =
        '${p.latitude.toStringAsFixed(4)},'
        '${p.longitude.toStringAsFixed(4)},$radiusM';
    final cached = _nearbyCache[key];
    if (cached != null) return cached;
    try {
      final q =
          '[out:json][timeout:20];'
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
        final name =
            _str(tags['name:kk']) ??
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
        out.add(
          GeoPlace(
            name: street.isEmpty ? name : '$name, $street',
            point: at,
            kind:
                _str(tags['shop']) ??
                _str(tags['amenity']) ??
                _str(tags['tourism']) ??
                _str(tags['leisure']) ??
                _str(tags['office']) ??
                _str(tags['building']),
            distanceM: haversineKm(p, at) * 1000,
          ),
        );
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

  /// Мәтін мекенжай емес, координата/қоқыс па («43.23890, 76.88970ндю»,
  /// «123», «.»). Ондай «атау» клиентке ұсынылмауы және сақталмауы керек.
  static bool isJunkLabel(String s) {
    final t = s.trim();
    if (RegExp(r'-?\d{1,3}\.\d{3,}\s*,\s*-?\d{1,3}\.\d{3,}').hasMatch(t)) {
      return true;
    }
    return RegExp(r'\p{L}', unicode: true).allMatches(t).length < 3;
  }

  static String coordLabel(LatLng p) =>
      '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}';

  /// Маршрут: OSRM (жолдармен), болмаса хаверсин × 1.3.
  static Future<GeoRoute> route(LatLng from, LatLng to) => routeVia([from, to]);

  /// OSRM серверлері — біріншісі жауап бермесе, келесісі сұралады.
  /// Екеуі де ашық OSM серверлері (кілтсіз), CORS-ты қолдайды.
  static const _osrmServers = [
    'https://router.project-osrm.org/route/v1/driving/',
    'https://routing.openstreetmap.de/routed-car/route/v1/driving/',
  ];

  /// Маршрут кэші: бір заказдың картасы (лента, заказ беті, толық экран)
  /// бірнеше рет салынады — әр жолы серверге қайта бармаймыз. Future
  /// сақталады, сондықтан қатар келген сұраулар да БІР запросқа бірігеді.
  static final _routeCache = <String, Future<GeoRoute>>{};

  /// Маршрут БІРНЕШЕ нүкте арқылы (аралық аялдамалармен, 0047).
  /// OSRM нүктелерді `;` арқылы қабылдайды әрі оларды БЕРІЛГЕН РЕТПЕН
  /// жүреді (қайта реттемейді) — клиент қосқан адрес тәртібі сақталады.
  ///
  /// [points] кемінде 2 нүкте болуы шарт; біреу ғана болса нөлдік маршрут
  /// қайтады (қосымша сынбауы үшін).
  static Future<GeoRoute> routeVia(List<LatLng> points) {
    if (points.length < 2) {
      return Future.value(
        GeoRoute(distanceKm: 0, durationMin: 0, points: points),
      );
    }
    final key = points
        .map(
          (p) =>
              '${p.latitude.toStringAsFixed(5)},${p.longitude.toStringAsFixed(5)}',
        )
        .join(';');
    final cached = _routeCache[key];
    if (cached != null) return cached;
    if (_routeCache.length > 60) _routeCache.remove(_routeCache.keys.first);
    final f = _fetchRoute(points).then((r) {
      // Түзу сызықты шамалау кэште ҚАЛМАЙДЫ — желі қалпына келгенде
      // келесі сұрау нақты жол геометриясын алуы керек.
      if (!r.onRoad) _routeCache.remove(key);
      return r;
    });
    _routeCache[key] = f;
    return f;
  }

  static Future<GeoRoute> _fetchRoute(List<LatLng> points) async {
    final coordsPath = points
        .map((p) => '${p.longitude},${p.latitude}')
        .join(';');
    for (final base in _osrmServers) {
      try {
        final uri = Uri.parse(
          '$base$coordsPath?overview=full&geometries=geojson',
        );
        // WEB-те User-Agent header-ін ЖІБЕРМЕЙМІЗ: ол «қарапайым емес»
        // header, браузер алдын ала CORS-сұрау (preflight) жасайды, ал OSRM
        // серверлері тек X-Requested-With/Content-Type-қа рұқсат береді —
        // сұрау бұғатталып, маршрут ТҮЗУ СЫЗЫҚ болып қалатын.
        final res = await http
            .get(uri, headers: kIsWeb ? null : _ua)
            .timeout(const Duration(seconds: 8));
        if (res.statusCode != 200) continue;
        final j = jsonDecode(res.body) as Map<String, dynamic>;
        final routes = j['routes'] as List?;
        if (routes == null || routes.isEmpty) continue;
        final r = routes.first as Map<String, dynamic>;
        final coords = ((r['geometry'] as Map)['coordinates'] as List)
            .cast<List>();
        return GeoRoute(
          distanceKm: (r['distance'] as num).toDouble() / 1000,
          durationMin: (r['duration'] as num).toDouble() / 60,
          points: coords
              .map(
                (c) =>
                    LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
              )
              .toList(),
          onRoad: true,
        );
      } catch (_) {
        // келесі сервер / fallback төменде
      }
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

  /// Қашықтықты қысқа жазу: «850 м», «4,2 км», «125 км» (үтірмен — қазақ
  /// және орыс тілдерінде ондық бөлшек үтірмен жазылады).
  static String formatDistance(double km) {
    if (km < 1) {
      final m = (km * 1000 / 10).round() * 10;
      return '${m < 10 ? 10 : m} м';
    }
    if (km < 100) {
      return '${km.toStringAsFixed(1).replaceAll('.', ',')} км';
    }
    return '${km.round()} км';
  }

  static double haversineKm(LatLng a, LatLng b) {
    const r = 6371.0;
    final dLat = _rad(b.latitude - a.latitude);
    final dLon = _rad(b.longitude - a.longitude);
    final h =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(_rad(a.latitude)) *
            math.cos(_rad(b.latitude)) *
            math.pow(math.sin(dLon / 2), 2);
    return 2 * r * math.asin(math.sqrt(h.toDouble()));
  }

  static double _rad(double d) => d * math.pi / 180;

  // ---------------------------------------------------------------------
  //  ҚАТЕГЕ ТӨЗІМДІ МЕКЕНЖАЙ ІЗДЕУ
  // ---------------------------------------------------------------------

  /// Мекенжай іздеу — клиент 1–2 әріп қате жазса да, латынмен не орысша
  /// жалғаумен жазса да табады.
  ///
  /// ҮШ дереккөз қатар сұралады, себебі әрқайсысы өз тұсын жабады:
  ///  • Nominatim (структуралық) — дұрыс жазылған «көше + үй»;
  ///  • Nominatim (еркін мәтін) — ТРЦ/ЖК/дүкен атаулары;
  ///  • Photon — қате жазылған сұраныс («абаяя 15», «хан шатр»).
  /// Қаланың көше индексі ([StreetIndex]) дайын болса, қате жазылған көше
  /// атауы ДҰРЫС атауға түзетіліп, Nominatim-ге сол атаумен тағы бір рет
  /// сұралады («толеби 59» → «Төле би көшесі 59»).
  ///
  /// Нәтижелер сұранысқа ұқсастығы бойынша сұрыпталады; ұқсамайтындары
  /// (геокодер «шамамен» тапқан бөтен көшелер) тізімге шықпайды.
  /// Барлық дереккөз құласа — [GeoSearchException].
  static Future<List<AddressHit>> searchAddress({
    required String city,
    required String query,
    LatLng? near,
    StreetIndex? index,
  }) async {
    final aq = AddressQuery.parse(query, city: city);
    final qk = NameKey.query(aq.street);
    if (qk.core.length < 2) return const [];
    final bias = near ?? _cityCenter(city);

    // 1) Құрылғыдағы көше тізімі бойынша түзету — желісіз, бірден.
    final local = index?.match(qk, limit: 4) ?? const <StreetMatch>[];
    final best = local.isEmpty ? null : local.first;
    final corrected =
        (best != null && best.score >= 0.7 && best.entry.core != qk.core)
        ? best.entry.name
        : null;
    String withHouse(String street) =>
        aq.house == null ? street : '$street ${aq.house}';

    Future<List<GeoPlace>?> safe(Future<List<GeoPlace>> f) async {
      try {
        return await f;
      } catch (_) {
        return null;
      }
    }

    final jobs = <Future<List<GeoPlace>?>>[
      safe(_searchStructured(city: city, street: withHouse(aq.street))),
      safe(_searchFree('${aq.text}, $city', near: bias)),
      if (bias != null) safe(_searchPhoton(aq.text, near: bias)),
      if (corrected != null)
        safe(_searchStructured(city: city, street: withHouse(corrected))),
    ];
    final res = await Future.wait(jobs);
    if (res.every((r) => r == null) && local.isEmpty) {
      throw const GeoSearchException();
    }

    final hits = <AddressHit>[];
    for (final p in dedupePlaces([for (final r in res) ...?r])) {
      final h = _scoreHit(p, aq, qk, city);
      if (h != null) hits.add(h);
    }

    // 2) Геокодер таппаған, бірақ индексте бар көшелер — «үйді картадан
    //    көрсетесіз» деген жол болып ұсынылады (атауы — картадағы ДҰРЫС
    //    атау, клиент жазғаны емес).
    for (final m in local) {
      if (m.score < 0.7) continue;
      final dup = hits.any(
        (h) =>
            h.place.road != null &&
            GeoText.streetCore(h.place.road!) == m.entry.core,
      );
      if (dup) continue;
      hits.add(
        AddressHit(
          place: GeoPlace(
            name: m.entry.name,
            point: m.entry.nearestTo(bias),
            city: city,
            road: m.entry.name,
            kind: kStreetIndex,
          ),
          score: m.score - 0.04,
          exactHouse: false,
          needsPin: true,
        ),
      );
    }

    hits.sort((a, b) {
      final c = b.score.compareTo(a.score);
      if (c != 0) return c;
      if (bias == null) return 0;
      return haversineKm(
        bias,
        a.place.point,
      ).compareTo(haversineKm(bias, b.place.point));
    });
    return hits.take(12).toList(growable: false);
  }

  /// Индекстен алынған көше (геокодер бұл көшені таппаған).
  static const kStreetIndex = 'street_index';

  /// Бір нәтижені сұранысқа қарай бағалайды; ұқсамаса — null.
  static AddressHit? _scoreHit(
    GeoPlace p,
    AddressQuery aq,
    NameKey qk,
    String city,
  ) {
    var text = 0.0;
    for (final s in [p.road, p.poi, p.name]) {
      if (s == null || s.isEmpty) continue;
      final v = GeoText.similarityKey(qk, NameKey(s));
      if (v > text) text = v;
    }
    if (text < 0.6) return null;
    final street = p.house == null && _streetKinds.contains(p.kind);
    var score = text;
    var exact = false;
    if (aq.house != null) {
      if (p.house != null) {
        if (_sameHouse(p.house!, aq.house!)) {
          score += 0.3;
          exact = true;
        } else {
          score -= 0.25;
        }
      }
    }
    if (p.city == null || sameCity(p.city, city)) score += 0.05;
    return AddressHit(
      place: p,
      score: score,
      exactHouse: exact,
      needsPin: street,
    );
  }

  static bool _sameHouse(String a, String b) {
    String n(String s) =>
        GeoText.fold(s).replaceAll(' ', '').replaceAll('/', '');
    return n(a) == n(b);
  }

  /// Photon (komoot) — OSM негізіндегі, қате жазуға төзімді іздеу.
  /// Таңдалған қаланың ~40 км аймағымен шектеледі.
  static Future<List<GeoPlace>> _searchPhoton(
    String q, {
    required LatLng near,
  }) async {
    const box = 0.35;
    final uri = Uri.https('photon.komoot.io', '/api/', {
      'q': q,
      'limit': '10',
      'lat': '${near.latitude}',
      'lon': '${near.longitude}',
      'location_bias_scale': '0.2',
      'zoom': '12',
      'bbox':
          '${near.longitude - box},${near.latitude - box},'
          '${near.longitude + box},${near.latitude + box}',
    });
    final key = uri.toString();
    final cached = _placeCache[key];
    if (cached != null) return cached;
    final res = await http
        .get(uri, headers: kIsWeb ? null : _ua)
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) {
      throw GeoSearchException('HTTP ${res.statusCode}');
    }
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final out = <GeoPlace>[];
    for (final raw in (j['features'] as List?) ?? const []) {
      try {
        final f = (raw as Map).cast<String, dynamic>();
        final pr = (f['properties'] as Map).cast<String, dynamic>();
        final c = ((f['geometry'] as Map)['coordinates'] as List).cast<num>();
        final type = _str(pr['type']);
        final name = _str(pr['name']);
        final street = _str(pr['street']);
        final house = _str(pr['housenumber']);
        final kind = _str(pr['osm_value']);
        String? road;
        String? poi;
        if (type == 'street') {
          road = name;
        } else {
          road = street;
          poi =
              (name != null &&
                  (street == null ||
                      name.toLowerCase() != street.toLowerCase()))
              ? name
              : null;
        }
        final streetPart = road == null
            ? null
            : (house == null ? road : '$road, $house');
        final label = [poi, streetPart].whereType<String>().join(', ');
        if (label.isEmpty) continue;
        final settlement =
            _str(pr['city']) ?? _str(pr['locality']) ?? _str(pr['county']);
        out.add(
          GeoPlace(
            name: label,
            point: LatLng(c[1].toDouble(), c[0].toDouble()),
            city: settlement == null ? null : displayCity(settlement),
            district: _str(pr['district']),
            kind: type == 'street' ? 'residential' : kind,
            road: road,
            house: house,
            poi: poi,
          ),
        );
      } catch (_) {
        // бір бұзық жазба тізімді құлатпауы керек
      }
    }
    if (_placeCache.length > 60) _placeCache.clear();
    _placeCache[key] = out;
    return out;
  }

  /// Картадағы нүктенің КЛИЕНТКЕ КӨРСЕТІЛЕТІН мекенжайы — әрқашан
  /// картадан анықталады (клиент жазған мәтін емес).
  ///
  /// Reverse-геокодер атау таппаса (шағын аудандарда жиі): маңайдағы
  /// көше → аудан → елді мекен; ештеңе болмаса — «Картадағы нүкте».
  /// Нүкте ДӘЛ болғандықтан орындаушы навигатормен дәл жерге келеді.
  static Future<PointLabel> describePoint(LatLng p, {String? city}) async {
    final addr = await reverseDetailed(p);
    if (addr.label.isNotEmpty) {
      return PointLabel(
        addr.labelFor(city),
        settlement: addr.settlement,
        exact: true,
      );
    }
    final street = await nearestStreetName(p);
    final settlement = addr.settlement;
    final needsSettlement = settlement != null && !sameCity(settlement, city);
    if (street != null) {
      return PointLabel(
        needsSettlement ? '$settlement, $street' : street,
        settlement: settlement,
        exact: false,
      );
    }
    final district = addr.district;
    final base = district ?? (needsSettlement ? settlement : null);
    return PointLabel(
      base == null ? kMapPointLabel : '$base · $kMapPointLabel',
      settlement: settlement,
      exact: false,
    );
  }

  /// Атауы табылмаған нүктенің жалпы атауы (t() арқылы аударылады).
  static const kMapPointLabel = 'Картадағы нүкте';

  /// [p] нүктесіне ЕҢ ЖАҚЫН аты бар көше (80 м ішінде) — Overpass.
  static Future<String?> nearestStreetName(LatLng p) async {
    try {
      final q =
          '[out:json][timeout:15];'
          'way(around:80,${p.latitude},${p.longitude})[highway][name];'
          'out tags center 12;';
      final body = await _overpass(q);
      if (body == null) return null;
      final els =
          ((jsonDecode(body) as Map<String, dynamic>)['elements'] as List?) ??
          const [];
      String? best;
      var bestKm = double.infinity;
      for (final raw in els) {
        final e = (raw as Map).cast<String, dynamic>();
        final tags = (e['tags'] as Map?)?.cast<String, dynamic>() ?? const {};
        final name = _str(tags['name:kk']) ?? _str(tags['name']);
        final c = (e['center'] as Map?)?.cast<String, dynamic>();
        if (name == null || c == null) continue;
        final km = haversineKm(
          p,
          LatLng((c['lat'] as num).toDouble(), (c['lon'] as num).toDouble()),
        );
        if (km < bestKm) {
          bestKm = km;
          best = name;
        }
      }
      return best;
    } catch (_) {
      return null;
    }
  }

  // ============================================================================
}

/// Геокодер (Nominatim) жауап бермеді / қате қайтарды. «Ештеңе табылмады»
/// ([] тізім) емес — іздеу ІСТЕМЕЙ тұр, клиентке қайталауды ұсыну керек.
class GeoSearchException implements Exception {
  final String? detail;
  const GeoSearchException([this.detail]);
  @override
  String toString() => 'GeoSearchException(${detail ?? ''})';
}

class GeoPlace {
  final String name;
  final LatLng point;

  /// Аудан/шағынаудан (болса) — бірдей «Абая, 5» әртүрлі аудандарда
  /// кездескенде тізімде ажырату үшін.
  final String? district;

  /// Нақты елді мекен (ауыл/кент/қала) — тірек қала ЕМЕС.
  final String? city;

  /// OSM түрі (`mall`, `apartments`, `village`…) — белгіше мен сұрыптау үшін.
  final String? kind;

  /// Іздеу нүктесінен қашықтық (метр) — маңайдағы нысандар тізімінде ғана.
  final double? distanceM;

  /// Көше аты (үй нөмірінсіз), үй нөмірі және нысан аты — іздеу
  /// нәтижесін сұранысқа салыстыру үшін (болса).
  final String? road;
  final String? house;
  final String? poi;

  GeoPlace({
    required this.name,
    required this.point,
    this.district,
    this.city,
    this.kind,
    this.distanceM,
    this.road,
    this.house,
    this.poi,
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

  /// Аудан/шағынаудан (болса) — атау табылмағанда нүктені сипаттау үшін.
  final String? district;

  const GeoAddress({
    required this.poi,
    required this.street,
    required this.settlement,
    required this.point,
    this.district,
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
  final String? road;
  final String? house;
  const _Parsed({
    this.poi,
    this.street,
    this.settlement,
    this.road,
    this.house,
  });

  String get label => [poi, street].whereType<String>().join(', ');
}

class GeoRoute {
  final double distanceKm;
  final double durationMin;
  final List<LatLng> points;

  /// `true` — нақты жол геометриясы (OSRM); `false` — түзу сызықты шамалау.
  final bool onRoad;
  GeoRoute({
    required this.distanceKm,
    required this.durationMin,
    required this.points,
    this.onRoad = false,
  });
}

/// Іздеудің бір нәтижесі — бағасы мен түрімен.
class AddressHit {
  final GeoPlace place;

  /// Сұранысқа ұқсастық (+ үй нөмірі дәл болса бонус).
  final double score;

  /// Клиент жазған үй нөмірі дәл осы.
  final bool exactHouse;

  /// Бұл — КӨШЕ (үй нөмірі картада жоқ): үйді картадан көрсету керек.
  final bool needsPin;

  const AddressHit({
    required this.place,
    required this.score,
    required this.exactHouse,
    required this.needsPin,
  });
}

/// Картадағы нүктенің атауы.
class PointLabel {
  final String label;
  final String? settlement;

  /// Геокодер мекенжайды тапты ма (жоқ болса — маңайдағы көше/аудан).
  final bool exact;

  const PointLabel(this.label, {this.settlement, required this.exact});
}
