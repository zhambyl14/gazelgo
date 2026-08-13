import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/geo.dart';
import '../core/lang.dart';
import '../core/theme.dart';

TileLayer osmTileLayer() => TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'kz.gazelgo.app',
    );

/// Түстің ЖАРЫҚ сыңары — градиенттің үстіңгі шеті («жарық жақ»).
Color _lighten(Color c, double a) => Color.lerp(c, Colors.white, a)!;

/// Түстің ҚОЮ сыңары — градиенттің төменгі шеті (көлеңкелі жақ).
Color _deepen(Color c, double a) => Color.lerp(c, Gz.ink, a)!;

/// `num.clamp` статикалық типі `num` — өлшемдер `double` болып қалуы үшін
/// өз шектегішімізді қолданамыз (аналайзер шағымданбайды).
double _clampD(double v, double lo, double hi) =>
    v < lo ? lo : (v > hi ? hi : v);

// ═══════════════════════════════════════════════════════════════════════
//  КАРТА БЕЛГІЛЕРІНІҢ ОТБАСЫ — [MapPin]
// ═══════════════════════════════════════════════════════════════════════
//
// НЕЛІКТЕН БҰЛАЙ. Жақсы карта белгісі (Yandex Go, inDrive, Uber, Bolt,
// 2GIS, Google Maps) ҮШ нәрсемен ұтады:
//   1. ТАМШЫ СИЛУЭТІ — ұшы дәл координатада тұрады, сол себепті «қай жерді
//      көрсетіп тұр?» деген сұрақ мүлде тумайды (жалаң `Icons.location_on`
//      материал иконкасы — тек сурет, оның ұшы қай пиксельде екені белгісіз);
//   2. ҚАЛЫҢ АҚ КОНТУР — карта тайлы қандай түсті болса да (орман, су,
//      тас жол, қала қуысы) белгі фоннан ҮЗІЛІП тұрады;
//   3. ЖҰМСАҚ КӨЛЕҢКЕ — белгі картаның ҮСТІНДЕ қалқып тұрғандай көрінеді,
//      суреттің ішіне сіңіп кетпейді.
// Оның үстіне түс ЖАЛҒЫЗ белгі болмауы керек: ішінде глиф болады (нөмір,
// финиш шаршысы, көлік иконкасы) — дальтоник те, ұсақ экранда да оқиды.
//
// ГЕОМЕТРИЯ (CustomPainter-сіз). d×d квадраттың ҮШ бұрышы R = d/2, ал
// bottomRight бұрышы үшкір. R = d/2 болғанда сол үш доғаның ЦЕНТРІ БІР
// нүктеде — квадраттың дәл ортасында, яғни олар БІР шеңбер құрайды
// (диаметрі d). Ал үшкір бұрышқа баратын оң және төменгі жиектер сол
// шеңберге ЖАНАМА (тангенс) болып шығады. Демек фигура = «шеңбер + оған
// жанама екі түзу, олар бір нүктеде түйіседі» — нақ идеалды карта тамшысы.
//
// БҰРУ БАҒЫТЫ (тексерілді). Flutter-де Transform.rotate оң бұрышы —
// САҒАТ ТІЛІМЕН: (x, y) → (x·cos − y·sin, x·sin + y·cos). θ = π/4 үшін
// bottomRight бұрышы (+1, +1) → (0, +1.414) — яғни ДӘЛ ТӨМЕН. Сондықтан
// `angle: math.pi / 4` үшкір ұшты ТӨМЕНГЕ шығарады, ал ішкі глиф тік
// тұруы үшін −math.pi/4-ке кері бұрылады.
//
// РАДИУСТЫ АНЫҚ ЖАЗАМЫЗ. «Radius.circular(50)» айласының орнына нақты
// `d/2` жазылған: Skia/Impeller шектен асқан радиустарды БІР ортақ
// коэффициентпен ТӨРТЕУІН БІРДЕЙ кішірейтеді, сол себепті «50» деп
// жазсақ ұштың радиусы пиннің өлшеміне қарай өзгеріп кетер еді.
//
// КӨЛЕҢКЕ ТУРАЛЫ ЕСКЕРТУ. Transform.rotate контейнердің КӨЛЕҢКЕСІН де
// бірге бұрады: (0, dy) ығысуы 45°-тан кейін солға-төмен қарай кетеді.
// Сол себепті ығысуды АЛДЫН АЛА кері бұрып береміз — [MapPin._down].

/// Белгі түрі.
enum MapPinKind {
  /// Алу нүктесі (A) — «мен осындамын» стиліндегі НЫСАНА.
  origin,

  /// Аралық аялдама — ішінде НӨМІРІ бар тамшы.
  stop,

  /// Соңғы нүкте (B) — ішінде ақ шаршысы бар тамшы.
  destination,

  /// Орындаушының тірі орны — көлік «шайбасы».
  vehicle,
}

/// Картадағы ДА, тізімдегі ДЕ бірыңғай белгі.
///
/// Бір виджет болғандықтан тізімдегі белгі мен картадағы пин ешқашан
/// «айырылысып» кетпейді: түс те, ақ контур да, көлеңке де дәл бірдей.
class MapPin extends StatelessWidget {
  /// Белгі түрі.
  final MapPinKind kind;

  /// Негізгі түс: Gz.green (A), Gz.violet (аялдама), Gz.red (B),
  /// Gz.blue (орындаушы).
  final Color color;

  /// `origin`/`vehicle` үшін — СЫРТҚЫ диаметр;
  /// тамшы үшін — БАСЫНЫҢ диаметрі (жалпы биіктігі одан ≈1.21 есе үлкен).
  final double size;

  /// Тамшы ішіндегі нөмір (аралық аялдама).
  final int? number;

  /// Нөмірдің орнына жазу («A», «B» — қажет болса).
  final String? label;

  /// Жазудың орнына иконка.
  final IconData? icon;

  /// Алу нүктесі (A) — ақ сақиналы дөңгелек + солғын ореол.
  /// Тамшыдан ӘДЕЙІ ЖЕҢІЛ көрінеді: «бастау» соңғы нүктемен таласпауы керек.
  const MapPin.origin({super.key, this.size = 28, this.color = Gz.green})
      : kind = MapPinKind.origin,
        number = null,
        label = null,
        icon = null;

  /// Аралық аялдама — ішінде нөмірі бар тамшы.
  const MapPin.stop(this.number,
      {super.key, this.size = 26, this.color = Gz.violet})
      : kind = MapPinKind.stop,
        label = null,
        icon = null;

  /// Соңғы нүкте (B) — әдепкіде ішінде ақ «финиш» шаршысы бар тамшы.
  /// Қаласаңыз [icon] («ту») немесе [label] («B») беруге болады.
  const MapPin.destination({
    super.key,
    this.size = 30,
    this.color = Gz.red,
    this.icon,
    this.label,
  })  : kind = MapPinKind.destination,
        number = null;

  /// Орындаушының тірі орны. Тамшы ЕМЕС — тамшы «орынды» білдіреді, ал
  /// қозғалып жүрген көлік — орын емес, объект.
  const MapPin.vehicle({
    super.key,
    this.size = 38,
    this.color = Gz.blue,
    this.icon = Icons.local_shipping_rounded,
  })  : kind = MapPinKind.vehicle,
        number = null,
        label = null;

  /// Тамшының ЖАЛПЫ биіктігі басының диаметріне қатысты:
  /// r (басының үсті) + r·√2 (центрден ұшқа дейін) = d·(0.5 + √½) ≈ 1.2071·d.
  static const double heightRatio = 0.5 + math.sqrt1_2;

  /// Басының диаметрі бойынша пиннің толық биіктігі.
  static double heightFor(double head) => head * heightRatio;

  /// Бұрылған контейнердің ішінде «таза төмен» болып шығатын ығысу.
  /// (dy·√½, dy·√½) векторы +45°-қа бұрылғанда дәл (0, dy) болады.
  static Offset _down(double dy) => Offset(dy * math.sqrt1_2, dy * math.sqrt1_2);

  @override
  Widget build(BuildContext context) => switch (kind) {
        MapPinKind.origin => _origin(),
        MapPinKind.vehicle => _vehicle(),
        MapPinKind.stop || MapPinKind.destination => _teardrop(),
      };

  // ── ТАМШЫ (аялдама / соңғы нүкте) ────────────────────────────────────
  Widget _teardrop() {
    final d = size;
    // Ақ контур — пиннің ең маңызды бөлігі: карта тайлынан үзіп тұрады.
    final ring = _clampD(d * 0.105, 1.6, 3.2);

    // Ішкі глиф ӘРҚАШАН АҚ: түрлі-түсті денеде ең контрасты нұсқа.
    final Widget glyph;
    if (icon != null) {
      glyph = Icon(icon, size: d * 0.44, color: Colors.white);
    } else if (label != null || number != null) {
      // Екі таңбалы нөмір (10, 11 …) де сыюы керек — сол үшін FittedBox.
      glyph = FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label ?? '$number',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: d * 0.5,
            height: 1,
            letterSpacing: -0.3,
          ),
        ),
      );
    } else {
      // Финиш глифі — АҚ ШАРШЫ. Шахмат туы 26–32 px-те былығып кетеді,
      // ал шаршы кез келген өлшемде таза оқылады («маршрут осында тоқтайды»).
      glyph = Container(
        width: d * 0.3,
        height: d * 0.3,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(d * 0.075),
        ),
      );
    }

    return SizedBox(
      width: d,
      height: d * heightRatio,
      child: Align(
        // Тамшының БАСЫ жоғарыда, ұшы — қораптың дәл төменгі-ортасында.
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: d,
          height: d,
          child: Transform.rotate(
            // Оң бұрыш = сағат тілімен → үшкір bottomRight бұрышы ТӨМЕНГЕ.
            angle: math.pi / 4,
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                // Бұрылған жүйеде topLeft→bottomRight градиенті экранда
                // ТАЗА ТІК (үстінен төмен) болып көрінеді: R((1,1)) ∝ (0,1).
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    _lighten(color, 0.22),
                    color,
                    _deepen(color, 0.12),
                  ],
                  stops: const [0.0, 0.55, 1.0],
                ),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(d / 2),
                  topRight: Radius.circular(d / 2),
                  bottomLeft: Radius.circular(d / 2),
                  // Үшкір ұш. Мүлде 0 емес — 1 пиксельдік дөңгелектеу
                  // антиалиасингте ұшты «тікенектей» етпейді.
                  bottomRight: Radius.circular(d * 0.06),
                ),
                border: Border.all(color: Colors.white, width: ring),
                boxShadow: [
                  // Тығыз көлеңке — жиекті айқындайды.
                  BoxShadow(
                    color: const Color(0x38101828),
                    blurRadius: 4,
                    offset: _down(1.5),
                  ),
                  // Жайылған көлеңке — пинді картаға «қондырады».
                  BoxShadow(
                    color: const Color(0x24101828),
                    blurRadius: 12,
                    offset: _down(5),
                  ),
                  // Өз түсімен әлсіз сәуле — белгі «тірі» көрінеді.
                  BoxShadow(
                    color: color.withValues(alpha: 0.22),
                    blurRadius: 9,
                    offset: _down(3),
                  ),
                ],
              ),
              // Глиф тік тұруы үшін кері бұрылады.
              child: Transform.rotate(angle: -math.pi / 4, child: glyph),
            ),
          ),
        ),
      ),
    );
  }

  // ── АЛУ НҮКТЕСІ (A) ──────────────────────────────────────────────────
  Widget _origin() {
    final d = size;
    final ring = _clampD(d * 0.09, 1.5, 3.0);
    return SizedBox(
      width: d,
      height: d,
      child: Center(
        child: Container(
          // Солғын ореол — «дәлдік аймағы» әсері (Google/Yandex тілі).
          width: d,
          height: d,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.14),
          ),
          child: Center(
            child: Container(
              width: d * 0.66,
              height: d * 0.66,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [_lighten(color, 0.2), color],
                ),
                border: Border.all(color: Colors.white, width: ring),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33101828),
                    blurRadius: 5,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              // Ақ өзек — белгі «нүкте» емес, НЫСАНА болып оқылады.
              child: Center(
                child: Container(
                  width: d * 0.24,
                  height: d * 0.24,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── ОРЫНДАУШЫ (тірі орны) ────────────────────────────────────────────
  Widget _vehicle() {
    final d = size;
    final body = d * 0.76;
    final ring = _clampD(d * 0.08, 2.0, 3.4);
    return SizedBox(
      width: d,
      height: d,
      child: Center(
        child: Container(
          width: d,
          height: d,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.16),
          ),
          child: Center(
            child: Container(
              width: body,
              height: body,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [_lighten(color, 0.24), color, _deepen(color, 0.1)],
                  stops: const [0.0, 0.55, 1.0],
                ),
                border: Border.all(color: Colors.white, width: ring),
                boxShadow: [
                  const BoxShadow(
                    color: Color(0x38101828),
                    blurRadius: 4,
                    offset: Offset(0, 1.5),
                  ),
                  const BoxShadow(
                    color: Color(0x24101828),
                    blurRadius: 12,
                    offset: Offset(0, 5),
                  ),
                  BoxShadow(
                    color: color.withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(
                icon ?? Icons.local_shipping_rounded,
                color: Colors.white,
                size: d * 0.34,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  MARKER ФАБРИКАЛАРЫ (ескі қолтаңбалар сақталған)
// ═══════════════════════════════════════════════════════════════════════

/// Маршрут нүктесінің тамшы-пині.
///
/// ЕСКІ ҚОЛТАҢБА сақталды (`color`, `icon`) — бұрынғы шақыру орындары
/// өзгеріссіз компиляцияланады. Жаңа [number] берілсе — ішіне НӨМІР
/// жазылады (аралық аялдама), әйтпесе ақ «финиш» шаршысы шығады.
///
/// `alignment: Alignment.topCenter` — flutter_map 8.3.1-де бұл виджет
/// нүктенің ҮСТІНДЕ орналасады дегенді білдіреді, яғни оның ТӨМЕНГІ
/// ЖИЕГІ координатаға дәл түседі. Тамшының ұшы да дәл сол жерде тұр
/// (қораптың биіктігі — [MapPin.heightFor]), демек ұш = координата.
Marker pointMarker(
  LatLng p, {
  Color color = Gz.green,
  IconData? icon,
  int? number,
  double size = 30,
}) =>
    Marker(
      point: p,
      width: size,
      height: MapPin.heightFor(size),
      alignment: Alignment.topCenter,
      child: number == null
          ? MapPin.destination(size: size, color: color, icon: icon)
          : MapPin.stop(number, size: size, color: color),
    );

/// A нүктесінің белгісі — ақ сақиналы жасыл НЫСАНА (тамшы емес: бастау
/// нүктесі соңғы нүктеден жеңіл көрінуі керек).
///
/// Симметриялы белгі болғандықтан `Alignment.center` (flutter_map-тың
/// әдепкісі): координата дөңгелектің дәл ортасында.
Marker originMarker(LatLng p, {Color color = Gz.green, double size = 28}) =>
    Marker(
      point: p,
      width: size,
      height: size,
      alignment: Alignment.center,
      child: MapPin.origin(size: size, color: color),
    );

/// Орындаушының тірі орнына арналған маркер (көлік «шайбасы»).
/// [icon] арқылы такси/жүк көлігін ажыратуға болады.
Marker executorLiveMarker(
  LatLng p, {
  Color color = Gz.blue,
  IconData icon = Icons.local_shipping_rounded,
  double size = 38,
}) =>
    Marker(
      point: p,
      width: size,
      height: size,
      alignment: Alignment.center,
      child: MapPin.vehicle(size: size, color: color, icon: icon),
    );

/// Экранның дәл ортасында тұратын пин (мекенжай таңдау экрандары үшін).
///
/// ҚИЫНДЫҒЫ: тамшының ҰШЫ картаның центріне ДӘЛ түсуі керек, ал ұш —
/// пиннің төменгі жиегінде. Сол себепті бағанның астына пиннің биіктігіне
/// тең БОС ОРЫН қосамыз: сонда бағанның геометриялық ортасы = ұштың орны,
/// ал Center оны картаның центріне қояды. Қолмен «bottom: 20» деп
/// теңшеудің қажеті жоқ — есеп өзі дәл шығады.
class MapCenterPin extends StatelessWidget {
  final Color color;
  final double size;

  /// Мекенжай анықталып жатыр — пин сәл кішірейеді (ұшы орнында қалады).
  final bool busy;
  final IconData? icon;

  const MapCenterPin({
    super.key,
    this.color = Gz.red,
    this.size = 34,
    this.busy = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final h = MapPin.heightFor(size);
    return IgnorePointer(
      child: Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            // «Жер» белгісі — координатаның ДӘЛ өзі. Пин кішірейгенде де
            // қайда тұрғаны көрініп қалады.
            Container(
              width: 9,
              height: 5,
              decoration: BoxDecoration(
                color: Gz.ink.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedScale(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  // Ұшы қозғалмауы үшін төменгі-ортасынан масштабталады.
                  alignment: Alignment.bottomCenter,
                  scale: busy ? 0.88 : 1,
                  child: MapPin.destination(
                      size: size, color: color, icon: icon),
                ),
                SizedBox(height: h),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  МАРШРУТ КАРТАСЫ
// ═══════════════════════════════════════════════════════════════════════

/// Маршрут сызығын салады: астында ақ «контур», үстінде көк сызық.
/// Қою тайлдарда (орман, су) жалғыз көк сызық жоғалып кететін.
List<Polyline> _routeLines(List<LatLng> points) => [
      Polyline(
        points: points,
        strokeWidth: 7,
        color: Colors.white.withValues(alpha: 0.9),
      ),
      Polyline(points: points, strokeWidth: 4.5, color: Gz.blue),
    ];

/// Маршруттың барлық белгісі. РЕТІ МАҢЫЗДЫ: тығыз тұрған нүктелерде
/// соңғы нүкте (B) аялдамалардың үстінде, ал орындаушы — бәрінен де
/// үстінде тұруы керек.
List<Marker> _routeMarkers({
  required LatLng from,
  required LatLng to,
  required List<LatLng> stops,
  required List<Marker> extra,
  double scale = 1,
}) =>
    [
      originMarker(from, size: 28 * scale),
      for (var i = 0; i < stops.length; i++)
        pointMarker(stops[i], color: Gz.violet, number: i + 1, size: 27 * scale),
      pointMarker(to, color: Gz.red, size: 32 * scale),
      ...extra,
    ];

/// Камера теңшеуі. Барлық нүкте БІР жерде болса (мыс. `from == to`, немесе
/// клиент әлі жеткізу нүктесін таңдамаған) шектің ауданы НӨЛ болады да,
/// [CameraFit.bounds] шексіз zoom есептеп жіберуі мүмкін — сол себепті
/// ондай жағдайда жай ғана центр + тұрақты zoom береміз.
bool _degenerate(List<LatLng> pts) {
  if (pts.length < 2) return true;
  final b = LatLngBounds.fromPoints(pts);
  return (b.north - b.south).abs() < 1e-6 && (b.east - b.west).abs() < 1e-6;
}

/// Маршрутты көрсететін шағын карта (A → B + сызық).
///
/// ЖАҢА (0068): карта — ЕНДІ ТҮЙМЕ. Түртсе, толық экранды интерактивті
/// [RouteMapScreen] ашылады: сонда еркін жылжытып, жақындатып, маршруттың
/// дұрыстығына көз жеткізуге болады.
///
/// ІШКІ КАРТА НЕГЕ ИНТЕРАКТИВТІ ЕМЕС. Бұл виджет әрқашан айналдырылатын
/// беттің ішінде тұрады (SingleChildScrollView, ListView,
/// DraggableScrollableSheet). Интерактивті FlutterMap саусақтың ТІК
/// қозғалысын өзіне тартып алады да, бет айналдырылмай қалады — жиі
/// кездесетін әрі өте ыңғайсыз қате. Сол себепті inDrive/Yandex Go/Uber
/// сияқты: ішкі карта — АЛДЫН АЛА КӨРІНІС, ал нақты қарау толық экранда.
class RouteMap extends StatelessWidget {
  final LatLng from;
  final LatLng to;

  /// АРАЛЫҚ аялдамалар (0047) — картада НӨМІРЛЕНГЕН күлгін тамшылармен
  /// белгіленеді (тізімдегі «Аялдама 1, 2 …» дегенмен дәл сәйкес) әрі
  /// камера оларды да қамтиды (әйтпесе аялдама кадрдан шығып қалатын).
  final List<LatLng> stops;
  final List<LatLng> routePoints;
  final double height;

  /// Қосымша маркерлер (0060, орындаушыны тірі көрсету) — мыс. орындаушының
  /// ағымдағы GPS нүктесі. Бос болса ештеңе өзгермейді.
  final List<Marker> extraMarkers;

  /// Түртсе толық экранды карта ашылсын ба. Тізім ішіндегі карточкаларда
  /// (мыс. [OrderCard]) `false` болуы керек — онда түрту заказдың өз бетін
  /// ашуы тиіс.
  final bool expandable;

  /// Толық экранда көрсетілетін мекенжай жазулары.
  final String? fromLabel;
  final String? toLabel;
  final List<String> stopLabels;

  /// Қашықтық (км) — толық экранның төменгі жолағында көрсетіледі.
  final double? distanceKm;

  const RouteMap({
    super.key,
    required this.from,
    required this.to,
    this.stops = const [],
    this.routePoints = const [],
    this.height = 200,
    this.extraMarkers = const [],
    this.expandable = true,
    this.fromLabel,
    this.toLabel,
    this.stopLabels = const [],
    this.distanceKm,
  });

  void _open(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RouteMapScreen(
        from: from,
        to: to,
        stops: stops,
        routePoints: routePoints,
        extraMarkers: extraMarkers,
        fromLabel: fromLabel,
        toLabel: toLabel,
        stopLabels: stopLabels,
        distanceKm: distanceKm,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final all = [from, ...stops, to, for (final m in extraMarkers) m.point];
    final points = routePoints.isEmpty ? [from, ...stops, to] : routePoints;
    final flat = _degenerate(all);
    // Картаның айналасында ЖИЕК бар: ақ карточкаға тікелей жапсырылған
    // тайл суреті «жамау» болып көрінетін — жіңішке жиек оны нақты
    // блокқа айналдырады.
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Gz.radius),
        border: Border.all(color: Gz.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: flat ? from : const LatLng(48.02, 66.9),
                    initialZoom: flat ? 15 : 5,
                    initialCameraFit: flat
                        ? null
                        : CameraFit.bounds(
                            bounds: LatLngBounds.fromPoints(all),
                            // Шеті 48: B пині координатадан ЖОҒАРЫ ≈39 px
                            // көтеріледі, 40-та кадрдың жиегіне тіреліп
                            // қалатын еді.
                            padding: const EdgeInsets.all(48),
                          ),
                    interactionOptions:
                        const InteractionOptions(flags: InteractiveFlag.none),
                  ),
                  children: [
                    osmTileLayer(),
                    PolylineLayer(polylines: _routeLines(points)),
                    MarkerLayer(
                      markers: _routeMarkers(
                        from: from,
                        to: to,
                        stops: stops,
                        extra: extraMarkers,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (expandable) ...[
              // Бүкіл алдын ала көрініс — БІР ҮЛКЕН ТҮЙМЕ.
              Positioned.fill(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(onTap: () => _open(context)),
                ),
              ),
              // Ашуға болатынын АЙҚЫН айтатын белгі. Онсыз қозғалмайтын
              // карта «бұзылған» болып көрінеді.
              Positioned(
                right: 8,
                bottom: 8,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(9, 6, 11, 6),
                    decoration: BoxDecoration(
                      color: Gz.surface,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: Gz.cardShadow,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.open_in_full_rounded,
                            size: 14, color: Gz.ink),
                        const SizedBox(width: 6),
                        Text(
                          t('Картаны ашу'),
                          style: const TextStyle(
                            fontSize: 11.5,
                            height: 1.1,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.1,
                            color: Gz.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  ТОЛЫҚ ЭКРАНДЫ ИНТЕРАКТИВТІ МАРШРУТ КАРТАСЫ
// ═══════════════════════════════════════════════════════════════════════

/// Маршрутты ТОЛЫҚ ЭКРАНДА көрсететін бет: еркін жылжытуға, жақындатуға,
/// алыстатуға болады.
///
/// НЕГЕ КЕРЕК. Клиент мекенжайларды енгізген соң «бағыт дұрыс па?» деп
/// тексергісі келеді — ол үшін картаны айналдырып, жақындатып қарау керек.
/// Орындаушыға да заказды алар алдында «қайдан қайда?» дегенді бір қарап
/// шығу керек. Кішкентай алдын ала көрініс бұған жеткіліксіз.
///
/// [routePoints] бос болса — нақты ЖОЛ геометриясы OSRM-нен өзі сұралады
/// (алдын ала көріністе түзу сызық болса да, толық экранда нақты жол
/// көрінеді). Сұрау сәтсіз болса түзу сызық қалады — бет ешқашан сынбайды.
class RouteMapScreen extends StatefulWidget {
  final LatLng from;
  final LatLng to;
  final List<LatLng> stops;
  final List<LatLng> routePoints;
  final List<Marker> extraMarkers;
  final String? fromLabel;
  final String? toLabel;
  final List<String> stopLabels;
  final double? distanceKm;

  const RouteMapScreen({
    super.key,
    required this.from,
    required this.to,
    this.stops = const [],
    this.routePoints = const [],
    this.extraMarkers = const [],
    this.fromLabel,
    this.toLabel,
    this.stopLabels = const [],
    this.distanceKm,
  });

  @override
  State<RouteMapScreen> createState() => _RouteMapScreenState();
}

class _RouteMapScreenState extends State<RouteMapScreen> {
  final _map = MapController();

  /// Төменгі панельдің НАҚТЫ биіктігін өлшейтін кілт. Бұрын басқару
  /// батырмалары мен камера шегінісі «236 / 230» деген ҚОЛМЕН табылған
  /// сандарға сүйенетін. Ұзын мекенжай екі жолға сынғанда, аялдама
  /// қосылғанда немесе жүйелік қаріп 1.25-ке ұлғайғанда панель биіктей
  /// түсетін де, батырмалар оның астында ҚАЛЫП қоятын. Енді өлшенеді.
  final _sheetKey = GlobalKey();

  late List<LatLng> _points = widget.routePoints;
  late double? _km = widget.distanceKm;
  double? _min;

  /// Маршрут тізімі жабық/ашық (карта толық көрінуі үшін жинауға болады).
  bool _sheetOpen = true;

  /// Өлшенген панель биіктігі (әлі өлшенбегенде — ақылға қонымды болжам).
  double _sheetH = 150;

  /// Камера бір рет НАҚТЫ өлшемдермен кадрланды ма.
  bool _framed = false;

  /// Жол геометриясы OSRM-нен СҰРАЛЫП жатыр ма. Бұрын мұндай күй болмайтын:
  /// қашықтық белгісіз кезде тақырып жолағы да, төменгі жолақ та бірдей
  /// «Маршрут» деп тұратын — бір беттегі бір сөздің екі рет қайталануы әрі
  /// «есептеліп жатыр ма, әлде мәлімет жоқ па?» деген белгісіздік.
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.routePoints.isEmpty) {
      _loading = true;
      _loadRoute();
    }
  }

  Future<void> _loadRoute() async {
    final r = await Geo.routeVia([widget.from, ...widget.stops, widget.to]);
    if (!mounted) return;
    // Желі жоқ / OSRM жауап бермеді — «есептелуде» деп мәңгі тұрып қалмауы
    // үшін күйді МІНДЕТТІ түрде жабамыз.
    if (r.points.length < 2) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _points = r.points;
      _km ??= r.distanceKm;
      _min = r.durationMin;
      _loading = false;
    });
    // Нақты жол геометриясы A→B тіктөртбұрышынан ШЫҒЫП кетуі мүмкін
    // (айналма жол, көпір, тұйық көше) — сол себепті геометрия келгенде
    // кадрды қайта есептейміз, әйтпесе маршруттың бір бөлігі кадрдан тыс
    // қалатын.
    if (_framed) _fit();
  }

  /// Панельдің биіктігін өлшеу. [_sheetKey] АНИМАЦИЯЛАНАТЫН қораптың емес,
  /// оның ІШКІ мазмұнының үстінде тұр: `AnimatedSize` баласын әрқашан
  /// табиғи өлшемімен орналастырады да, тек өз өлшемін анимациялайды.
  /// Демек биіктік анимация БІТКЕНШЕ күтпей-ақ, бірден дұрыс шығады.
  void _measureSheet() {
    if (!mounted) return;
    final h = _sheetKey.currentContext?.size?.height;
    if (h == null) return;
    if ((h - _sheetH).abs() > 0.5) {
      setState(() => _sheetH = h);
      return; // жаңа өлшеммен келесі кадрда кадрлаймыз
    }
    if (!_framed) {
      _framed = true;
      _fit();
    }
  }

  /// Панельдің экран ТҮБІНЕН бастап алатын толық орны
  /// (`Positioned(bottom: 10)` + жүйелік шегініс + мазмұн).
  double get _sheetTop => 10 + MediaQuery.paddingOf(context).bottom + _sheetH;

  List<LatLng> get _all => [
        widget.from,
        ...widget.stops,
        widget.to,
        for (final m in widget.extraMarkers) m.point,
      ];

  /// Бүкіл маршрут кадрға сыятындай етіп камераны қайта теңшейді.
  void _fit() {
    if (!mounted) return;
    if (_degenerate(_all)) {
      _map.move(widget.from, 15);
      return;
    }
    _map.fitCamera(CameraFit.bounds(
      // Тек A/B емес, ЖОЛДЫҢ ӨЗІ де қамтылады.
      bounds: LatLngBounds.fromPoints([..._all, ..._points]),
      padding: EdgeInsets.fromLTRB(
        44,
        MediaQuery.paddingOf(context).top + 76,
        44,
        _sheetTop + 24,
      ),
    ));
  }

  void _zoom(double delta) {
    final c = _map.camera;
    _map.move(c.center, (c.zoom + delta).clamp(3.0, 18.0));
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureSheet());
    final line = _points.isEmpty
        ? [widget.from, ...widget.stops, widget.to]
        : _points;
    final flat = _degenerate(_all);
    final ctrlBottom = _sheetTop + 12;
    return Scaffold(
      backgroundColor: Gz.bg,
      // ⚠️ SizedBox.expand МІНДЕТТІ. `Scaffold` өз `body`-іне БОС (loose)
      // биіктік шектеуін береді, ал `Stack` мұндайда өзінің
      // ПОЗИЦИЯЛАНБАҒАН балаларының өлшеміне жиырылады. Мұндағы жалғыз
      // позицияланбаған бала — жоғарғы жолақ, сол себепті бүкіл экран
      // ≈100 px-ке қысылып, карта жіңішке жолаққа айналатын да, `bottom: 10`
      // панелі экранның ЖОҒАРЫСЫНА шығып кететін. Экранның қалғанын Scaffold
      // фоны толтыратын — «карта ашылмайды» деген қате нақ осы болатын.
      body: SizedBox.expand(
        child: Stack(
          children: [
            // ── КАРТА: барлық қимыл ЕРКІН ──────────────────────────────
            // `rotate` ӘДЕЙІ өшірілген: екі саусақпен кездейсоқ бұрып алу
            // ең жиі кездесетін шағым (карта қисайып қалады да, қалай
            // түзетуді ешкім білмейді). Қалғанының бәрі қосулы, соның
            // ішінде `scrollWheelZoom` — web-те тінтуірмен жақындату.
            Positioned.fill(
              child: FlutterMap(
                mapController: _map,
                options: MapOptions(
                  initialCenter: flat ? widget.from : const LatLng(48.02, 66.9),
                  initialZoom: flat ? 15 : 5,
                  // Тайл жүктелгенше көрінетін фон. Әдепкі сұрғылт
                  // (0xFFE0E0E0) қосымшаның ашық реңкінен «жамау» болып
                  // бөлектеніп тұратын.
                  backgroundColor: Gz.bg,
                  initialCameraFit: flat
                      ? null
                      : CameraFit.bounds(
                          bounds: LatLngBounds.fromPoints(_all),
                          padding: const EdgeInsets.fromLTRB(44, 120, 44, 240),
                        ),
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                  ),
                ),
                children: [
                  osmTileLayer(),
                  PolylineLayer(polylines: _routeLines(line)),
                  MarkerLayer(
                    markers: _routeMarkers(
                      from: widget.from,
                      to: widget.to,
                      stops: widget.stops,
                      extra: widget.extraMarkers,
                      // Толық экранда пиндер сәл ірілеу — саусақпен көрсетуге
                      // де, алыстан қарауға да ыңғайлы.
                      scale: 1.15,
                    ),
                  ),
                ],
              ),
            ),

            // ── ЖОҒАРҒЫ ПЕРДЕ ──────────────────────────────────────────
            // Қою тайлдың (орман, су, түнгі аудан) үстінде ақ батырмалар
            // «еріп» кетпеуі үшін жұмсақ градиент. Түртуді ұстамайды.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Container(
                  height: MediaQuery.paddingOf(context).top + 72,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Gz.bg.withValues(alpha: 0.92),
                        Gz.bg.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // ── ЖОҒАРҒЫ ЖОЛАҚ: жабу ────────────────────────────────────
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Row(
                    children: [
                      _round(
                        icon: Icons.arrow_back_rounded,
                        onTap: () => Navigator.of(context).maybePop(),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 9),
                        decoration: BoxDecoration(
                          color: Gz.surface,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: Gz.cardShadow,
                        ),
                        // Иконка ӘДЕЙІ жоқ: маршрут белгісі төменгі жолақта
                        // тұр, оны бір бетте екі рет қайталау — шу.
                        child: Text(
                          t('Маршрут'),
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 13.5,
                            height: 1.1,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      const Spacer(),
                      // Тепе-теңдік үшін (тақырып дәл ортада тұруы керек).
                      const SizedBox(width: 42),
                    ],
                  ),
                ),
              ),
            ),

            // ── ОҢ ЖАҚТАҒЫ БАСҚАРУ: жақындату / алыстату / бүкілін көрсету
            // Орны ӨЛШЕНГЕН панель биіктігіне байланған: тізім жиналғанда
            // да, ұзын мекенжайдан панель биіктегенде де тасаланбайды.
            AnimatedPositioned(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOut,
              right: 12,
              bottom: ctrlBottom,
              child: Column(
                children: [
                  // Зум — БІР капсула: екі бөлек дөңгелектің орнына тұтас
                  // блок (Yandex Go / 2GIS тілі), саусаққа да жақынырақ.
                  Container(
                    decoration: BoxDecoration(
                      color: Gz.surface,
                      borderRadius: BorderRadius.circular(21),
                      boxShadow: Gz.cardShadow,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _tap(Icons.add_rounded, () => _zoom(1)),
                        Container(width: 26, height: 1, color: Gz.border),
                        _tap(Icons.remove_rounded, () => _zoom(-1)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  _round(
                    icon: Icons.center_focus_strong_rounded,
                    onTap: _fit,
                    tint: Gz.yellow,
                  ),
                ],
              ),
            ),

            // ── ДЕРЕК КӨЗІ ─────────────────────────────────────────────
            // OpenStreetMap тайлдарын пайдаланғанда сілтеме МІНДЕТТІ
            // (OSMF tile usage policy). Бұрын мүлде жоқ болатын.
            AnimatedPositioned(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOut,
              left: 12,
              bottom: ctrlBottom,
              child: IgnorePointer(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Gz.surface.withValues(alpha: 0.82),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Text(
                    '© OpenStreetMap',
                    style: TextStyle(
                      fontSize: 9.5,
                      height: 1.1,
                      fontWeight: FontWeight.w700,
                      color: Gz.textSecondary,
                    ),
                  ),
                ),
              ),
            ),

            // ── ТӨМЕНГІ КАРТА: маршрут тізімі ──────────────────────────
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: SafeArea(
                top: false,
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeInOut,
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    // Биіктігі ӨЛШЕНЕТІН қорап — [_measureSheet] қараңыз.
                    key: _sheetKey,
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                    decoration: BoxDecoration(
                      color: Gz.surface,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: Gz.liftShadow,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Тұтқа — картаны толық көру үшін тізімді жинауға
                        // болады.
                        InkWell(
                          onTap: () => setState(() => _sheetOpen = !_sheetOpen),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Column(
                              children: [
                                Container(
                                  width: 44,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    color: Gz.disabledBg,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    // Есептеліп жатқанда — тірі индикатор.
                                    // Өлшемі иконкамен БІРДЕЙ (17×17), сол
                                    // себепті жол «секірмейді».
                                    SizedBox(
                                      width: 17,
                                      height: 17,
                                      child: _loading
                                          ? const Padding(
                                              padding: EdgeInsets.all(1.5),
                                              child:
                                                  CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Gz.blue,
                                              ),
                                            )
                                          : const Icon(Icons.route_rounded,
                                              size: 17, color: Gz.blue),
                                    ),
                                    const SizedBox(width: 7),
                                    Expanded(
                                      child: Text(
                                        _summary(),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 13.5,
                                          height: 1.2,
                                          letterSpacing: -0.2,
                                        ),
                                      ),
                                    ),
                                    AnimatedRotation(
                                      duration:
                                          const Duration(milliseconds: 200),
                                      turns: _sheetOpen ? 0 : 0.5,
                                      child: const Icon(
                                        Icons.keyboard_arrow_down_rounded,
                                        color: Gz.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (_sheetOpen)
                          // Аялдамасы КӨП маршрутта (5–10 нүкте) тізім
                          // экраннан асып кетер еді — сол себепті биіктігі
                          // шектеліп, ішінен айналдырылады.
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight:
                                  MediaQuery.sizeOf(context).height * 0.42,
                            ),
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const SizedBox(height: 6),
                                  _leg(const MapPin.origin(size: 18),
                                      t('Қайдан'), widget.fromLabel),
                                  for (var i = 0;
                                      i < widget.stops.length;
                                      i++) ...[
                                    _connector(),
                                    _leg(
                                      MapPin.stop(i + 1, size: 18),
                                      '${t('Аялдама')} ${i + 1}',
                                      i < widget.stopLabels.length
                                          ? widget.stopLabels[i]
                                          : null,
                                    ),
                                  ],
                                  _connector(),
                                  _leg(
                                    const MapPin.destination(size: 18),
                                    widget.stops.isEmpty
                                        ? t('Қайда')
                                        : t('Соңғы нүкте'),
                                    widget.toLabel,
                                  ),
                                ],
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
      ),
    );
  }

  /// «12.4 км · ≈18 мин» — тізім жабық тұрғанда да негізгі сан көрінеді.
  ///
  /// ҚАЙТАЛАМАУ ЕРЕЖЕСІ. Аялдама САНЫ тек тізім ЖАБЫҚ тұрғанда қосылады:
  /// ашық тұрғанда аялдамалардың өзі дәл астында нөмірленіп тізіліп тұр,
  /// «+2 аялдама» деп қайта жазу — сол беттегі сол ақпараттың екінші рет
  /// қайталануы. Дерек мүлде болмағанда да «Маршрут» деп жазбаймыз — ол
  /// сөз жоғарғы жолақта тұр.
  String _summary() {
    final parts = <String>[];
    if (_km != null && _km! > 0) {
      parts.add('${_km!.toStringAsFixed(1)} ${t('км')}');
    }
    if (_min != null && _min! > 0) {
      parts.add('≈ ${_min!.round()} ${t('мин')}');
    }
    if (!_sheetOpen && widget.stops.isNotEmpty) {
      parts.add('+${widget.stops.length} ${t('аялдама')}');
    }
    if (parts.isNotEmpty) return parts.join(' · ');
    return _loading ? t('Жол есептелуде…') : t('Қашықтық белгісіз');
  }

  Widget _leg(Widget mark, String label, String? value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(width: 20, child: Center(child: mark)),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label.toUpperCase(), style: Gz.label),
                  const SizedBox(height: 1),
                  Text(
                    value == null || value.isEmpty ? '—' : value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                      letterSpacing: -0.1,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _connector() => Padding(
        padding: const EdgeInsets.only(left: 9),
        child: Container(
          width: 2,
          height: 12,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(1),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Gz.border, Gz.border.withValues(alpha: 0.35)],
            ),
          ),
        ),
      );

  /// Капсула ішіндегі бір басу аймағы (зум блогының жартысы).
  Widget _tap(IconData icon, VoidCallback onTap) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(11),
            child: Icon(icon, size: 20, color: Gz.ink),
          ),
        ),
      );

  /// Картаның үстінде тұратын дөңгелек батырма.
  Widget _round({
    required IconData icon,
    required VoidCallback onTap,
    Color? tint,
  }) =>
      Container(
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: Gz.cardShadow,
        ),
        child: Material(
          color: tint ?? Gz.surface,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(11),
              child: Icon(icon, size: 20, color: Gz.ink),
            ),
          ),
        ),
      );
}
