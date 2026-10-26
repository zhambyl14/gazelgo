import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/geo.dart';
import '../core/lang.dart';
import '../core/models.dart';
import '../core/theme.dart';
import 'vehicle_top_view.dart';

/// OSM тайл қабаты — Tasu реңкімен ([Gz.mapFilter]: OSM-нің өз түстері
/// сақталып, тек сәл жұмсартылады). Тайлдар баяғыдай ТЕГІН OSM серверінен
/// келеді — тек түсі өзгереді. Барлық карта (басты бет, адрес таңдау,
/// лента, заказ, тірі карта, модератор) осы бір қабатты қолданады.
///
/// Сүзгі ӘР тайлға бөлек емес (бұрын `tileBuilder` арқылы ~20–30 тайлдың
/// әрқайсысына жеке saveLayer жасалатын), бүкіл қабатқа БІР рет
/// қолданылады — карта жылжығанда кадр арзанырақ салынады.
Widget osmTileLayer() => ColorFiltered(
  colorFilter: Gz.mapFilter,
  child: TileLayer(
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    userAgentPackageName: 'kz.gazelgo.app',
    maxNativeZoom: 19,
    // Экраннан тыс алдын ала тайл сұрамаймыз, қате тайлдар кадрдан
    // шыққанда тасталады — жылдам масштабтағанда сұраныс тасқыны болмайды.
    panBuffer: 0,
    evictErrorTileStrategy: EvictErrorTileStrategy.notVisibleRespectMargin,
  ),
);

/// Ең кіші масштаб: әлем (256·2³ = 2048 px) кез келген телефоннан кең —
/// карта көлденең қайталанбайды.
const double kMapMinZoom = 3;
const double kMapMaxZoom = 18.5;

/// Карта центрі шыға алмайтын аумақ — Қазақстан + кең шет.
final LatLngBounds kMapBounds = LatLngBounds(
  const LatLng(35, 40),
  const LatLng(60, 95),
);

/// Барлық картаның ортақ [MapOptions]-ы.
///
/// БҰРЫН шымшып кішірейткенде масштабтың төменгі шегі жоқ еді: әлем ондаған
/// рет қатар салынып, әр маркер мен маршрут сонша рет көшіріліп, қосымша
/// қатып қалатын. Енді [kMapMinZoom]–[kMapMaxZoom] аралығы мен [kMapBounds]
/// шекарасы бәріне бірдей. Бұру әдепкіде өшірулі — кездейсоқ қисайған
/// карта ең жиі шағым.
MapOptions gzMapOptions({
  required LatLng initialCenter,
  required double initialZoom,
  CameraFit? initialCameraFit,
  bool interactive = true,
  bool allowRotate = false,
  void Function(MapCamera camera, bool hasGesture)? onPositionChanged,
  VoidCallback? onMapReady,
  Color? backgroundColor,
}) => MapOptions(
  initialCenter: initialCenter,
  initialZoom: initialZoom,
  initialCameraFit: initialCameraFit,
  minZoom: kMapMinZoom,
  maxZoom: kMapMaxZoom,
  cameraConstraint: CameraConstraint.containCenter(bounds: kMapBounds),
  backgroundColor: backgroundColor ?? Gz.bg,
  onPositionChanged: onPositionChanged,
  onMapReady: onMapReady,
  interactionOptions: InteractionOptions(
    flags: !interactive
        ? InteractiveFlag.none
        : allowRotate
        ? InteractiveFlag.all
        : InteractiveFlag.all & ~InteractiveFlag.rotate,
  ),
);

/// Түстің ЖАРЫҚ сыңары — градиенттің үстіңгі шеті («жарық жақ»).
Color _lighten(Color c, double a) => Color.lerp(c, Colors.white, a)!;

/// Түстің ҚОЮ сыңары — градиенттің төменгі шеті (көлеңкелі жақ).
Color _deepen(Color c, double a) => Color.lerp(c, Gz.inkDeep, a)!;

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

  /// Соңғы нүкте (B) — ішінде финиш туы бар тамшы.
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
  const MapPin.origin({super.key, this.size = 28, this.color = Gz.pinGreen})
    : kind = MapPinKind.origin,
      number = null,
      label = null,
      icon = null;

  /// Аралық аялдама — ішінде нөмірі бар тамшы.
  const MapPin.stop(
    this.number, {
    super.key,
    this.size = 26,
    this.color = Gz.pinViolet,
  }) : kind = MapPinKind.stop,
       label = null,
       icon = null;

  /// Соңғы нүкте (B) — әдепкіде ішінде шашка торлы финиш туы бар тамшы
  /// (ұсақ өлшемде — ақ шаршы). [icon] не [label] («B») беруге болады.
  const MapPin.destination({
    super.key,
    this.size = 30,
    this.color = Gz.pinRed,
    this.icon,
    this.label,
  }) : kind = MapPinKind.destination,
       number = null;

  /// Орындаушының тірі орны. Тамшы ЕМЕС — тамшы «орынды» білдіреді, ал
  /// қозғалып жүрген көлік — орын емес, объект.
  const MapPin.vehicle({
    super.key,
    this.size = 38,
    this.color = Gz.pinBlue,
    this.icon = Icons.local_shipping_rounded,
  }) : kind = MapPinKind.vehicle,
       number = null,
       label = null;

  /// Тамшының ЖАЛПЫ биіктігі басының диаметріне қатысты:
  /// r (басының үсті) + r·√2 (центрден ұшқа дейін) = d·(0.5 + √½) ≈ 1.2071·d.
  static const double heightRatio = 0.5 + math.sqrt1_2;

  /// Басының диаметрі бойынша пиннің толық биіктігі.
  static double heightFor(double head) => head * heightRatio;

  /// Бұрылған контейнердің ішінде «таза төмен» болып шығатын ығысу.
  /// (dy·√½, dy·√½) векторы +45°-қа бұрылғанда дәл (0, dy) болады.
  static Offset _down(double dy) =>
      Offset(dy * math.sqrt1_2, dy * math.sqrt1_2);

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
    } else if (kind == MapPinKind.destination && d >= 22) {
      // Финиш — шашка торлы ту (Material `sports_score`): карта үстінде
      // «маршрут осында аяқталады» дегені бірден түсінікті болсын.
      glyph = Icon(
        Icons.sports_score_rounded,
        size: d * 0.56,
        color: Colors.white,
      );
    } else {
      // Өте ұсақ белгі (тізімдегі 18 px) немесе аялдама — АҚ ШАРШЫ: ту
      // мұндай өлшемде былығып кетеді, ал шаршы таза оқылады.
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
                  colors: [_lighten(color, 0.22), color, _deepen(color, 0.12)],
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
                    color: Gz.shadowTight,
                    blurRadius: 4,
                    offset: _down(1.5),
                  ),
                  // Жайылған көлеңке — пинді картаға «қондырады».
                  BoxShadow(
                    color: Gz.shadowWide,
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
                    color: Gz.shadowTight,
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
                    color: Gz.shadowTight,
                    blurRadius: 4,
                    offset: Offset(0, 1.5),
                  ),
                  const BoxShadow(
                    color: Gz.shadowWide,
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
  Color color = Gz.pinGreen,
  IconData? icon,
  int? number,
  double size = 30,
}) => Marker(
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
Marker originMarker(LatLng p, {Color color = Gz.pinGreen, double size = 28}) =>
    Marker(
      point: p,
      width: size,
      height: size,
      alignment: Alignment.center,
      child: MapPin.origin(size: size, color: color),
    );

/// Орындаушының тірі орнына арналған маркер.
///
/// [vehicleType] берілсе — белгінің ішінде ОРЫНДАУШЫНЫҢ ӨЗ КӨЛІГІНІҢ
/// суреті тұрады (газель, такси, фура…), [heading] берілсе — қозғалыс
/// бағытын көрсететін нұсқар ([VehicleMarker]). Берілмесе — ескі «шайба»
/// иконкасы ([MapPin.vehicle]); [icon] арқылы такси/жүк көлігін ажыратуға
/// болады.
Marker executorLiveMarker(
  LatLng p, {
  VehicleType? vehicleType,
  double? heading,
  Color color = Gz.pinBlue,
  IconData icon = Icons.local_shipping_rounded,
  double size = 38,
}) {
  if (vehicleType != null) {
    final s = size < 44 ? 46.0 : size;
    return Marker(
      point: p,
      width: s,
      height: s,
      alignment: Alignment.center,
      child: VehicleMarker(type: vehicleType, size: s, heading: heading),
    );
  }
  return Marker(
    point: p,
    width: size,
    height: size,
    alignment: Alignment.center,
    child: MapPin.vehicle(size: size, color: color, icon: icon),
  );
}

/// Картадағы көліктің белгісі — ТӨБЕСІНЕН көрінетін көлік ([VehicleTopView]).
///
/// Такси — жеңіл көлік, газель/жеткізу — фургон, ауыр көлік — кабина +
/// кузов, техника — ықшам машина. [heading] (градус, 0 = солтүстік) берілсе
/// көлік ТҰТАС сол бағытқа бұрылады — Yandex Go/Uber сияқты. Астындағы
/// солғын сары ореол белгінің «тірі» екенін білдіреді.
///
/// Бір белгі бүкіл қосымшада: клиенттің тірі картасы ([LiveTrackMap]),
/// басты беттегі жақын маңдағы бос көліктер, модератордың тірі картасы.
class VehicleMarker extends StatelessWidget {
  final VehicleType type;
  final double size;
  final double? heading;

  const VehicleMarker({
    super.key,
    required this.type,
    this.size = 46,
    this.heading,
  });

  @override
  Widget build(BuildContext context) {
    final d = size;
    return SizedBox(
      width: d,
      height: d,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Солғын ореол — белгі «тірі» екенін білдіреді.
          Container(
            width: d * 0.9,
            height: d * 0.9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Gz.yellow.withValues(alpha: 0.2),
            ),
          ),
          VehicleTopView(type: type, size: d, heading: heading),
        ],
      ),
    );
  }
}

/// Екі нүкте арасындағы бағыт (градус, 0 = солтүстік, сағат тілімен) —
/// орындаушының соңғы екі орнынан қозғалыс бағытын есептеу үшін.
double bearingDeg(LatLng a, LatLng b) {
  final lat1 = a.latitude * math.pi / 180;
  final lat2 = b.latitude * math.pi / 180;
  final dLng = (b.longitude - a.longitude) * math.pi / 180;
  final y = math.sin(dLng) * math.cos(lat2);
  final x =
      math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

/// Экранның дәл ортасында тұратын пин — Tasu ЛОГОТИП-ПИНІ (сары тамшы,
/// ішінде «T»). Мекенжай таңдау экрандарында «осы жер» белгісі.
///
/// ҚИЫНДЫҒЫ: тамшының ҰШЫ картаның центріне ДӘЛ түсуі керек, ал ұш —
/// суреттің төменгі жиегінде (логотип файлы ұшына дейін қиылған). Сол
/// себепті бағанның астына пиннің биіктігіне тең БОС ОРЫН қосамыз: сонда
/// бағанның геометриялық ортасы = ұштың орны, ал Center оны картаның
/// центріне қояды.
///
/// [lifted] — клиент картаны саусақпен жылжытып жатыр: пин Yandex Go-дағыдай
/// жоғары «көтеріледі», астындағы көлеңке кішірейіп солғындайды; қолын
/// алғанда серпіліп орнына «қонады». [busy] — мекенжай анықталып жатыр.
class MapCenterPin extends StatelessWidget {
  /// Логотип-пиннің БИІКТІГІ (ені пропорциясымен шығады).
  final double size;

  /// Мекенжай анықталып жатыр — пин сәл кішірейеді (ұшы орнында қалады).
  final bool busy;

  /// Карта жылжып жатыр — пин көтеріліп тұрады.
  final bool lifted;

  const MapCenterPin({
    super.key,
    this.size = 50,
    this.busy = false,
    this.lifted = false,
  });

  /// Логотиптің ені/биіктігі (assets/icon/tasu_logo.png: 826×1013).
  static const aspect = 826 / 1013;

  /// Көтерілу биіктігі (px).
  static const _lift = 14.0;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: lifted ? 1 : 0),
          duration: Duration(milliseconds: lifted ? 160 : 260),
          // Қонғанда сәл серпіледі (easeOutBack) — «тірі» сезім береді.
          curve: lifted ? Curves.easeOut : Curves.easeOutBack,
          child: AnimatedScale(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            // Ұшы қозғалмауы үшін төменгі-ортасынан масштабталады.
            alignment: Alignment.bottomCenter,
            scale: busy ? 0.9 : 1,
            child: Image.asset(
              'assets/icon/tasu_logo.png',
              height: size,
              width: size * aspect,
              filterQuality: FilterQuality.medium,
            ),
          ),
          builder: (context, v, pin) => Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // «Жер» көлеңкесі — координатаның ДӘЛ өзі. Пин көтерілгенде
              // кішірейіп, солғындайды.
              Container(
                width: 16 - 6 * v,
                height: 6 - 2 * v,
                decoration: BoxDecoration(
                  color: Gz.ink.withValues(alpha: 0.32 - 0.14 * v),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Transform.translate(
                offset: Offset(0, -_lift * v),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    pin!,
                    SizedBox(height: size),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// «Мен осындамын» — пайдаланушының НАҚТЫ GPS орны: ақ сақиналы көк нүкте
/// және одан үздіксіз таралатын солғын толқын (Apple/Google/Yandex
/// карталарындағы таныс белгі). Ортадағы логотип-пиннен ([MapCenterPin])
/// бөлек: пин — «таңдалған жер», нүкте — «мен қазір қайдамын».
class MyLocationDot extends StatefulWidget {
  final double size;
  const MyLocationDot({super.key, this.size = 18});

  @override
  State<MyLocationDot> createState() => _MyLocationDotState();
}

class _MyLocationDotState extends State<MyLocationDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.size;
    final dot = Container(
      width: d,
      height: d,
      decoration: BoxDecoration(
        color: Gz.blue,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: d * 0.17),
        boxShadow: [
          BoxShadow(
            color: Gz.ink.withValues(alpha: 0.28),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
    );
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        child: dot,
        builder: (context, child) {
          final v = Curves.easeOut.transform(_c.value);
          return Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: d + d * 2.6 * v,
                height: d + d * 2.6 * v,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Gz.blue.withValues(alpha: 0.28 * (1 - v)),
                ),
              ),
              child!,
            ],
          );
        },
      ),
    );
  }
}

/// [MyLocationDot] маркері. Симметриялы — координата дәл ортасында.
Marker myLocationMarker(LatLng p, {double size = 18}) => Marker(
  point: p,
  width: size * 3.8,
  height: size * 3.8,
  alignment: Alignment.center,
  child: MyLocationDot(size: size),
);

// ═══════════════════════════════════════════════════════════════════════
//  МАРШРУТ КАРТАСЫ
// ═══════════════════════════════════════════════════════════════════════

/// Маршрут сызығы — Tasu стилі: қою «асфальт» жолақ, ортасында брендтің
/// сары үзік «жол белгісі», астында ақ контур (сызық кез келген тайлдан —
/// су, орман, қою көше — бөлініп тұрады) және жұмсақ көлеңке.
///
/// [onRoad] = false — нақты жол геометриясы ЖОҚ (OSRM уақытша жауап
/// бермеді): нүктелер [_arcPoints] доғасымен, ақ жолақтағы ҮЗІК сызықпен
/// салынады — «бұл тек бағыт, нақты жол емес» деген айқын белгі. Бұрын
/// мұндайда «үп-түзу» көк сызық тұратын: әрі қатқыл көрінетін, әрі
/// «осы жолмен жүреді» деген жалған әсер беретін.
List<Polyline> _routeLines(List<LatLng> points, {required bool onRoad}) {
  if (!onRoad) {
    final arc = _arcPoints(points);
    return [
      Polyline(
        points: arc,
        strokeWidth: 7,
        color: Colors.white.withValues(alpha: 0.95),
      ),
      Polyline(
        points: arc,
        strokeWidth: 3.4,
        color: Gz.ink,
        pattern: StrokePattern.dashed(segments: const [9, 7]),
      ),
    ];
  }
  return [
    Polyline(
      points: points,
      strokeWidth: 11,
      color: Gz.ink.withValues(alpha: 0.10),
    ),
    Polyline(points: points, strokeWidth: 8.5, color: Colors.white),
    Polyline(points: points, strokeWidth: 5.6, color: Gz.ink),
    Polyline(
      points: points,
      strokeWidth: 1.5,
      color: Gz.yellow,
      pattern: StrokePattern.dashed(segments: const [6, 6]),
    ),
  ];
}

/// [_routeLines]-тың ашық нұсқасы — өз картасын салатын экрандар үшін
/// (мыс. клиенттің іздеу экраны): маршрут барлық жерде БІРДЕЙ көрінеді.
List<Polyline> routePolylines(List<LatLng> points, {required bool onRoad}) =>
    _routeLines(points, onRoad: onRoad);

/// Жол геометриясы жоқ кезде нүктелерді жұмсақ ДОҒАМЕН қосады (әр бөлік —
/// квадраттық Безье қисығы, ортасынан кесінді ұзындығының 16%-ына
/// ауытқиды).
///
/// Доға жергілікті ЖАЗЫҚ координатада есептеледі (бойлық cos(ендік)-ке
/// көбейтіледі) — әйтпесе солтүстікте (Астана ≈51°) доға қисайып,
/// «жайылып» кететін.
List<LatLng> _arcPoints(List<LatLng> pts) {
  if (pts.length < 2) return List.of(pts);
  final out = <LatLng>[pts.first];
  for (var i = 0; i + 1 < pts.length; i++) {
    final a = pts[i], b = pts[i + 1];
    final k = math.cos((a.latitude + b.latitude) / 2 * math.pi / 180);
    final ax = a.longitude * k, ay = a.latitude;
    final bx = b.longitude * k, by = b.latitude;
    final dx = bx - ax, dy = by - ay;
    final cx = (ax + bx) / 2 - dy * 0.16;
    final cy = (ay + by) / 2 + dx * 0.16;
    const n = 28;
    for (var j = 1; j <= n; j++) {
      final t = j / n, u = 1 - t;
      final x = u * u * ax + 2 * u * t * cx + t * t * bx;
      final y = u * u * ay + 2 * u * t * cy + t * t * by;
      out.add(LatLng(y, k.abs() < 1e-9 ? x : x / k));
    }
  }
  return out;
}

/// Маршруттың барлық белгісі. РЕТІ МАҢЫЗДЫ: тығыз тұрған нүктелерде
/// соңғы нүкте (B) аялдамалардың үстінде, ал орындаушы — бәрінен де
/// үстінде тұруы керек.
List<Marker> _routeMarkers({
  required LatLng from,
  required LatLng to,
  required List<LatLng> stops,
  required List<Marker> extra,
  double scale = 1,
}) => [
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

/// Екі нүкте тізімі бірдей ме (виджет қайта құрылғанда маршрут шынымен
/// өзгерді ме — жоқ па).
bool _samePoints(List<LatLng> a, List<LatLng> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Нақты ЖОЛ геометриясын сұрайды. [Geo.routeVia] кэштейді — лента, заказ
/// беті, тірі карта, толық экран бір маршрутты бір-ақ рет сұрайды. Жол
/// табылса ғана [onRoad] шақырылады; табылмаса (желі/OSRM) — доға қалады.
void _requestRoad(
  List<LatLng> waypoints,
  void Function(List<LatLng> road) onRoad,
) {
  if (_degenerate(waypoints)) return;
  Geo.routeVia(waypoints).then((r) {
    if (r.onRoad && r.points.length >= 2) onRoad(r.points);
  });
}

// ═══════════════════════════════════════════════════════════════════════
//  ОРЫНДАУШЫДАН A НҮКТЕСІНЕ ДЕЙІНГІ СҰР ЖОЛ
// ═══════════════════════════════════════════════════════════════════════

/// Нүктенің сынық сызыққа ең жақын проекциясы: [seg]-кесінді, ондағы
/// үлес [t] (0…1), проекция нүктесі және одан қашықтық (метр).
class _LineHit {
  final int seg;
  final double t;
  final LatLng point;
  final double distM;
  const _LineHit(this.seg, this.t, this.point, this.distM);
}

/// Метр/градус (ендік бойынша).
const double _mPerDeg = 111320;

/// Жергілікті ЖАЗЫҚ координатада (бойлық cos(ендік)-ке көбейтіледі) ең
/// жақын кесіндіні табады. Қала көлеміндегі қашықтыққа дәлдігі жеткілікті.
_LineHit? _nearestOnLine(List<LatLng> line, LatLng p) {
  if (line.length < 2) return null;
  final k = math.cos(p.latitude * math.pi / 180) * _mPerDeg;
  _LineHit? best;
  for (var i = 0; i + 1 < line.length; i++) {
    final a = line[i], b = line[i + 1];
    final ax = (a.longitude - p.longitude) * k;
    final ay = (a.latitude - p.latitude) * _mPerDeg;
    final dx = (b.longitude - a.longitude) * k;
    final dy = (b.latitude - a.latitude) * _mPerDeg;
    final l2 = dx * dx + dy * dy;
    final t = l2 < 1e-9 ? 0.0 : _clampD(-(ax * dx + ay * dy) / l2, 0, 1);
    final x = ax + dx * t, y = ay + dy * t;
    final d = math.sqrt(x * x + y * y);
    if (best == null || d < best.distM) {
      best = _LineHit(
        i,
        t,
        LatLng(
          a.latitude + (b.latitude - a.latitude) * t,
          a.longitude + (b.longitude - a.longitude) * t,
        ),
        d,
      );
    }
  }
  return best;
}

/// Сызықтың [p] нүктесінен КЕЙІНГІ бөлігі: сұр жол көліктің өзінен
/// басталып, ол жүрген сайын қысқара береді.
List<LatLng> _trimLine(List<LatLng> line, LatLng p) {
  final h = _nearestOnLine(line, p);
  if (h == null) return line;
  return [p, h.point, ...line.sublist(h.seg + 1)];
}

/// Сызық бойындағы жинақталған қашықтық (метр) — көлікті ЖОЛ БОЙЫМЕН
/// жылжыту үшін.
class _PathMeasure {
  final List<LatLng> line;
  final List<double> cum;

  _PathMeasure._(this.line, this.cum);

  factory _PathMeasure(List<LatLng> line) {
    final cum = <double>[0];
    for (var i = 1; i < line.length; i++) {
      cum.add(cum.last + Geo.haversineKm(line[i - 1], line[i]) * 1000);
    }
    return _PathMeasure._(line, cum);
  }

  double get length => cum.last;

  /// Нүктенің сызық бойындағы орны (метр) және сызықтан қашықтығы.
  ({double s, double off})? locate(LatLng p) {
    final h = _nearestOnLine(line, p);
    if (h == null) return null;
    final segLen = cum[h.seg + 1] - cum[h.seg];
    return (s: cum[h.seg] + segLen * h.t, off: h.distM);
  }

  /// [s] метрдегі нүкте және сол жердегі жол бағыты (градус).
  (LatLng, double) at(double s) {
    final v = _clampD(s, 0, length);
    var lo = 0, hi = cum.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (cum[mid] <= v) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final a = line[lo], b = line[hi];
    final segLen = cum[hi] - cum[lo];
    final t = segLen < 1e-6 ? 0.0 : (v - cum[lo]) / segLen;
    return (
      LatLng(
        a.latitude + (b.latitude - a.latitude) * t,
        a.longitude + (b.longitude - a.longitude) * t,
      ),
      bearingDeg(a, b),
    );
  }
}

/// Орындаушыдан A-ға дейінгі жолды OSRM-нен СИРЕК сұрайтын көмекші.
///
/// Әр GPS нүктесінде жаңа сұрау жібермейді (тегін серверге салмақ әрі
/// кэшті толтырып жібереді): тек мақсат ауысқанда, көлік жолдан 80 м-ден
/// астам шыққанда немесе 90 с өтіп, көлік едәуір жылжығанда ғана. Арада
/// бар жол көліктің орнынан кесіліп көрсетіледі ([trimmed]).
class _ApproachRoad {
  List<LatLng> points = const [];
  bool onRoad = false;
  LatLng? _askedFrom;
  LatLng? _to;
  DateTime? _askedAt;
  bool _busy = false;

  void reset() {
    points = const [];
    onRoad = false;
    _askedFrom = null;
    _to = null;
    _askedAt = null;
  }

  /// Көліктің жаңа орны. Жол жаңарса [onChange] шақырылады.
  void update(LatLng from, LatLng to, VoidCallback onChange) {
    if (_to != to) {
      reset();
      _to = to;
    }
    if (_busy) return;
    final now = DateTime.now();
    final age = _askedAt == null
        ? const Duration(days: 1)
        : now.difference(_askedAt!);
    final off = onRoad ? (_nearestOnLine(points, from)?.distM ?? 1e9) : 0.0;
    final need =
        _askedFrom == null ||
        (!onRoad && age > const Duration(seconds: 30)) ||
        (onRoad && off > 80 && age > const Duration(seconds: 10)) ||
        (age > const Duration(seconds: 90) &&
            Geo.haversineKm(from, _askedFrom!) > 0.05);
    if (!need) return;
    _busy = true;
    _askedFrom = from;
    _askedAt = now;
    Geo.route(from, to).then((r) {
      _busy = false;
      if (_to != to) return;
      onRoad = r.onRoad && r.points.length >= 2;
      points = onRoad ? r.points : [from, to];
      onChange();
    });
  }

  /// Көліктің [car] орнынан басталатын қалған жол.
  List<LatLng> trimmed(LatLng car) {
    final to = _to;
    if (to == null) return const [];
    if (!onRoad) return [car, to];
    return _trimLine(points, car);
  }
}

/// СҰР жол сызығы — орындаушыдан A-ға дейін. Заказдың өз маршрутының
/// (қара + сары) АСТЫНДА салынады: «бұл жүргізушінің келетін жолы, заказ
/// емес» дегені бір қарағанда түсінікті.
const Color kApproachGrey = Gz.approachGrey;

List<Polyline> approachPolylines(List<LatLng> points, {required bool onRoad}) {
  if (points.length < 2) return const [];
  if (!onRoad) {
    final arc = _arcPoints(points);
    return [
      Polyline(
        points: arc,
        strokeWidth: 6,
        color: Colors.white.withValues(alpha: 0.85),
      ),
      Polyline(
        points: arc,
        strokeWidth: 3.2,
        color: kApproachGrey,
        pattern: StrokePattern.dashed(segments: const [8, 7]),
      ),
    ];
  }
  return [
    Polyline(
      points: points,
      strokeWidth: 8,
      color: Colors.white.withValues(alpha: 0.85),
    ),
    Polyline(points: points, strokeWidth: 5, color: kApproachGrey),
  ];
}

/// Тірі көліктің бір сәттегі күйі: [pos] — қазір көрініп тұрған (жылжу
/// ортасындағы) орны, [fix] — серверден келген соңғы нақты нүкте.
@immutable
class LiveVehicleFix {
  final LatLng pos;
  final LatLng fix;
  final double? heading;
  final VehicleType type;

  /// Жүргізуші әлі A-ға келе жатыр ма (`accepted`) — сұр жол тек сонда.
  final bool toA;

  const LiveVehicleFix({
    required this.pos,
    required this.fix,
    required this.type,
    this.heading,
    this.toA = false,
  });
}

/// Көліктің [from]→[to] жылжуын ЖОЛ БОЙЫМЕН жасауға бола ма: екі нүкте де
/// [line] бойында (60 м ішінде) әрі алға қарай жүріп жатса ғана. Әйтпесе
/// (жолдан ауытқыды, кері бұрылды) — null, түзу жылжу.
({_PathMeasure m, double s0, double s1})? _planAlong(
  List<LatLng> line,
  LatLng from,
  LatLng to,
) {
  if (line.length < 2) return null;
  final m = _PathMeasure(line);
  final a = m.locate(from), b = m.locate(to);
  if (a == null || b == null || a.off > 60 || b.off > 60) return null;
  final along = b.s - a.s;
  final straight = Geo.haversineKm(from, to) * 1000;
  if (along < -5 || along > straight * 3 + 80) return null;
  return (m: m, s0: a.s, s1: b.s);
}

/// Жаңа нүктеге дейінгі жылжу ұзақтығы — алдыңғы нүктеден бері өткен
/// уақыт (көлік келесі жаңарту келгенше тоқтамай жүреді), 1,4–8 с.
Duration _glideGap(DateTime? last, DateTime now) {
  const short = Duration(milliseconds: 1400);
  if (last == null) return short;
  final gap = now.difference(last);
  if (gap <= short || gap > const Duration(seconds: 30)) return short;
  return gap > const Duration(seconds: 8) ? const Duration(seconds: 8) : gap;
}

/// Жылжып жүрген көлік + (керек болса) оны сұр жолдың басымен қосатын
/// қысқа кесінді. Сұр жол соңғы НАҚТЫ нүктеден кесіледі, ал көлік оған
/// қарай жылжып келе жатады — арадағы аз ғана бос орынды осы толтырады.
Widget _liveVehicleLayers(LiveVehicleFix? f, {required bool connect}) {
  if (f == null) return const SizedBox.shrink();
  return Stack(
    children: [
      if (connect)
        PolylineLayer(
          polylines: [
            Polyline(
              points: [f.pos, f.fix],
              strokeWidth: 5,
              color: kApproachGrey,
            ),
          ],
        ),
      MarkerLayer(
        markers: [
          executorLiveMarker(f.pos, vehicleType: f.type, heading: f.heading),
        ],
      ),
    ],
  );
}

/// Орындаушының белгісі: көлік түрі белгілі болса — төбеден көрінетін
/// көлік, әйтпесе — көк «мен осындамын» нүктесі.
Marker _approachMarker(LatLng p, VehicleType? type, double? heading) =>
    type == null
    ? myLocationMarker(p)
    : executorLiveMarker(p, vehicleType: type, heading: heading);

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
class RouteMap extends StatefulWidget {
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

  /// Орындаушының қазіргі орны. Берілсе — картада орындаушы және одан A
  /// нүктесіне дейінгі СҰР жол ([approachPolylines]) салынады: заказды
  /// алмас бұрын «маған қанша жүру керек» дегенді көзбен бағалау үшін.
  final LatLng? approachFrom;

  /// Орындаушының көлік түрі ([approachFrom] белгісі үшін). null — көк
  /// «мен осындамын» нүктесі.
  final VehicleType? approachVehicle;
  final double? approachHeading;

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
    this.approachFrom,
    this.approachVehicle,
    this.approachHeading,
  });

  @override
  State<RouteMap> createState() => _RouteMapState();
}

/// [RouteMap]-тың күйі: нақты ЖОЛ геометриясын OSRM-нен өзі сұрайды
/// ([RouteMap.routePoints] берілмесе) және жауап келгенде камераны жолдың
/// өзіне қайта кадрлайды (айналма жол A→B тіктөртбұрышынан шығып кетуі
/// мүмкін). [Geo.routeVia] кэштейді — лента, заказ беті, толық экран бір
/// маршрутты бір-ақ рет сұрайды.
class _RouteMapState extends State<RouteMap> {
  final _map = MapController();
  bool _ready = false;

  /// Нақты жол нүктелері (бос — әзірге жоқ, доға салынады).
  late List<LatLng> _road = widget.routePoints;

  List<LatLng> get _waypoints => [widget.from, ...widget.stops, widget.to];

  List<LatLng> get _linePoints =>
      _road.isNotEmpty ? _road : _arcPoints(_waypoints);

  /// Орындаушыдан A-ға дейінгі сұр жол.
  final _approach = _ApproachRoad();

  List<LatLng> get _approachLine {
    final p = widget.approachFrom;
    return p == null ? const [] : _approach.trimmed(p);
  }

  /// Камера қамтуы тиіс нүктелер: белгілер + сызықтың өзі.
  List<LatLng> get _boundsPoints => [
    ..._waypoints,
    for (final m in widget.extraMarkers) m.point,
    ?widget.approachFrom,
    ..._linePoints,
    ..._approachLine,
  ];

  @override
  void initState() {
    super.initState();
    _loadRoad();
    _loadApproach(refit: true);
  }

  /// Сұр жолды сұрайды (керек болса ғана — [_ApproachRoad] шешеді). Жол
  /// алғаш келгенде камера оны да қамтиды.
  void _loadApproach({bool refit = false}) {
    final p = widget.approachFrom;
    if (p == null) {
      _approach.reset();
      return;
    }
    final first = _approach.points.isEmpty;
    _approach.update(p, widget.from, () {
      if (!mounted) return;
      setState(() {});
      if (first || refit) _fit();
    });
  }

  @override
  void didUpdateWidget(RouteMap old) {
    super.didUpdateWidget(old);
    final moved =
        old.from != widget.from ||
        old.to != widget.to ||
        !_samePoints(old.stops, widget.stops) ||
        !_samePoints(old.routePoints, widget.routePoints);
    if (moved) {
      _road = widget.routePoints;
      _loadRoad();
      _fit();
    }
    if (old.approachFrom != widget.approachFrom || moved) {
      _loadApproach(refit: old.approachFrom == null);
      // Орындаушы кадрдан шығып бара жатса ғана камераны жылжытамыз —
      // әр GPS нүктесінде карта «секірмесін».
      final p = widget.approachFrom;
      if (p != null && _ready) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (!_map.camera.visibleBounds.contains(p)) _fit();
        });
      }
    }
  }

  void _loadRoad() {
    if (_road.isNotEmpty) return;
    final asked = _waypoints;
    _requestRoad(asked, (road) {
      // Сұрау жүріп жатқанда мекенжай ауысқан болса — ескі жауап керек емес.
      if (!mounted || !_samePoints(asked, _waypoints)) return;
      setState(() => _road = road);
      _fit();
    });
  }

  void _onReady() {
    _ready = true;
    // Жол карта дайын болғанша келіп үлгерген болса — енді кадрлаймыз.
    if (_road.isNotEmpty) _fit();
  }

  void _fit() {
    if (!_ready || !mounted) return;
    final pts = _boundsPoints;
    if (_degenerate(pts)) {
      _map.move(widget.from, 15);
      return;
    }
    _map.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(pts),
        padding: const EdgeInsets.all(48),
      ),
    );
  }

  void _open(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RouteMapScreen(
          from: widget.from,
          to: widget.to,
          stops: widget.stops,
          routePoints: _road,
          extraMarkers: widget.extraMarkers,
          fromLabel: widget.fromLabel,
          toLabel: widget.toLabel,
          stopLabels: widget.stopLabels,
          distanceKm: widget.distanceKm,
          approachFrom: widget.approachFrom,
          approachVehicle: widget.approachVehicle,
          approachHeading: widget.approachHeading,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final from = widget.from;
    final all = _boundsPoints;
    final me = widget.approachFrom;
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
        height: widget.height,
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: FlutterMap(
                  mapController: _map,
                  options: gzMapOptions(
                    onMapReady: _onReady,
                    initialCenter: flat ? from : const LatLng(48.02, 66.9),
                    initialZoom: flat ? 15 : 5,
                    interactive: false,
                    initialCameraFit: flat
                        ? null
                        : CameraFit.bounds(
                            bounds: LatLngBounds.fromPoints(all),
                            // Шеті 48: B пині координатадан ЖОҒАРЫ ≈39 px
                            // көтеріледі, 40-та кадрдың жиегіне тіреліп
                            // қалатын еді.
                            padding: const EdgeInsets.all(48),
                          ),
                  ),
                  children: [
                    osmTileLayer(),
                    if (me != null)
                      PolylineLayer(
                        polylines: approachPolylines(
                          _approachLine,
                          onRoad: _approach.onRoad,
                        ),
                      ),
                    PolylineLayer(
                      polylines: _routeLines(
                        _road.isNotEmpty ? _road : _waypoints,
                        onRoad: _road.isNotEmpty,
                      ),
                    ),
                    MarkerLayer(
                      markers: _routeMarkers(
                        from: from,
                        to: widget.to,
                        stops: widget.stops,
                        extra: [
                          ...widget.extraMarkers,
                          if (me != null)
                            _approachMarker(
                              me,
                              widget.approachVehicle,
                              widget.approachHeading,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (widget.expandable) ...[
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
                        Icon(
                          Icons.open_in_full_rounded,
                          size: 14,
                          color: Gz.ink,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          t('Картаны ашу'),
                          style: TextStyle(
                            fontSize: 12,
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

  /// [RouteMap.approachFrom]-дағыдай: орындаушы + A-ға дейінгі сұр жол.
  final LatLng? approachFrom;
  final VehicleType? approachVehicle;
  final double? approachHeading;

  /// Тірі көлік ([LiveTrackMap]-тан): берілсе, толық экранда да көлік
  /// ЖЫЛЖЫП тұрады, ал [approachToA] болса — A-ға дейінгі сұр жол да.
  final ValueListenable<LiveVehicleFix?>? live;
  final bool approachToA;

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
    this.approachFrom,
    this.approachVehicle,
    this.approachHeading,
    this.live,
    this.approachToA = false,
  });

  @override
  State<RouteMapScreen> createState() => _RouteMapScreenState();
}

class _RouteMapScreenState extends State<RouteMapScreen>
    with SingleTickerProviderStateMixin {
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

  final _approach = _ApproachRoad();

  /// Сұр жол соңғы рет кесілген көлік нүктесі (тірі режимде).
  LatLng? _approachFix;

  /// Сұр жолдың бастауы: тірі көліктің соңғы нүктесі не берілген орын.
  LatLng? get _me =>
      widget.live == null ? widget.approachFrom : widget.live!.value?.fix;

  /// Тірі режимде — статусқа қарай (жүргізуші A-ға жетіп, жолға шықса
  /// сұр жол жоғалады), әйтпесе — орын берілсе.
  bool get _showApproach => widget.live == null
      ? widget.approachFrom != null
      : (widget.live!.value?.toA ?? widget.approachToA);

  // ── Тірі көліктің ӨЗ жылжуы ──────────────────────────────────────────
  // Астыңғы беттегі [LiveTrackMap]-тың анимациясы толық экран ашық
  // тұрғанда ТОҚТАП тұрады (Flutter жабылған беттің тикерін өшіреді) —
  // сол себепті бұл бет жаңа нүктелерді өзі жылжытады.
  late final AnimationController _glide;
  LatLng? _gFrom;
  LatLng? _gTo;
  ({_PathMeasure m, double s0, double s1})? _gPath;
  DateTime? _gLastAt;

  (LatLng, double?)? get _glidePos {
    final to = _gTo;
    if (to == null) return null;
    final from = _gFrom;
    final heading = widget.live?.value?.heading;
    if (from == null) return (to, heading);
    final k = _glide.value;
    final p = _gPath;
    if (p != null) {
      final (pt, b) = p.m.at(p.s0 + (p.s1 - p.s0) * k);
      return (pt, (p.s1 - p.s0).abs() > 3 ? b : heading);
    }
    return (
      LatLng(
        from.latitude + (to.latitude - from.latitude) * k,
        from.longitude + (to.longitude - from.longitude) * k,
      ),
      heading,
    );
  }

  @override
  void initState() {
    super.initState();
    if (widget.routePoints.isEmpty) {
      _loading = true;
      _loadRoute();
    }
    // initState-те БІРДЕН жасалады: жалқау (late) болса, тірі емес экранда
    // алғаш dispose ішінде құрылып, Flutter қате береді.
    _glide = AnimationController(vsync: this);
    final v = widget.live?.value;
    if (v != null) {
      _gTo = v.pos;
      _gLastAt = DateTime.now();
    }
    widget.live?.addListener(_onLive);
    _updateApproach();
  }

  @override
  void dispose() {
    widget.live?.removeListener(_onLive);
    _glide.dispose();
    super.dispose();
  }

  /// Тірі көліктің ЖАҢА нүктесі келгенде ғана: жылжу басталады және сұр
  /// жол қайта кесіледі (әр анимация кадрында емес).
  void _onLive() {
    final v = widget.live?.value;
    if (v == null) return;
    if (!v.toA && _approachFix != null) {
      _approach.reset();
      setState(() => _approachFix = null);
    }
    final fix = v.fix;
    if (fix == _gTo) return;
    final now = DateTime.now();
    final from = _glidePos?.$1 ?? fix;
    final line = v.toA
        ? (_approach.onRoad ? _approach.points : const <LatLng>[])
        : _points;
    _gPath = _planAlong(line, from, fix);
    _gFrom = from;
    _gTo = fix;
    _glide.duration = _glideGap(_gLastAt, now);
    _gLastAt = now;
    _glide.forward(from: 0);
    if (v.toA) {
      setState(() => _approachFix = fix);
      _updateApproach();
    }
  }

  void _updateApproach() {
    final p = _me;
    if (!_showApproach || p == null) return;
    _approachFix = p;
    _approach.update(p, widget.from, () {
      if (mounted) setState(() {});
    });
  }

  Future<void> _loadRoute() async {
    final r = await Geo.routeVia([widget.from, ...widget.stops, widget.to]);
    if (!mounted) return;
    // Желі жоқ / OSRM жауап бермеді — «есептелуде» деп мәңгі тұрып қалмауы
    // үшін күйді МІНДЕТТІ түрде жабамыз.
    // Нақты жол табылмаса (желі/OSRM) — шамаланған уақыт пен қашықтықты
    // НАҚТЫ деп көрсетпейміз (бұрын «≈ 40 км/сағ» бойынша ойдан шығарылған
    // уақыт шығатын); бағыт доғамен салынады.
    if (!r.onRoad || r.points.length < 2) {
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
    ?_me,
  ];

  /// Бүкіл маршрут кадрға сыятындай етіп камераны қайта теңшейді.
  void _fit() {
    if (!mounted) return;
    if (_degenerate(_all)) {
      _map.move(widget.from, 15);
      return;
    }
    _map.fitCamera(
      CameraFit.bounds(
        // Тек A/B емес, ЖОЛДЫҢ ӨЗІ де қамтылады.
        bounds: LatLngBounds.fromPoints([..._all, ..._points]),
        padding: EdgeInsets.fromLTRB(
          44,
          MediaQuery.paddingOf(context).top + 76,
          44,
          _sheetTop + 24,
        ),
      ),
    );
  }

  void _zoom(double delta) {
    final c = _map.camera;
    _map.move(c.center, (c.zoom + delta).clamp(3.0, 18.0));
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureSheet());
    final onRoad = _points.isNotEmpty;
    final line = onRoad ? _points : [widget.from, ...widget.stops, widget.to];
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
                options: gzMapOptions(
                  initialCenter: flat ? widget.from : const LatLng(48.02, 66.9),
                  initialZoom: flat ? 15 : 5,
                  initialCameraFit: flat
                      ? null
                      : CameraFit.bounds(
                          bounds: LatLngBounds.fromPoints(_all),
                          padding: const EdgeInsets.fromLTRB(44, 120, 44, 240),
                        ),
                ),
                children: [
                  osmTileLayer(),
                  if (_showApproach && _approachFix != null)
                    PolylineLayer(
                      polylines: approachPolylines(
                        _approach.trimmed(_approachFix!),
                        onRoad: _approach.onRoad,
                      ),
                    ),
                  PolylineLayer(polylines: _routeLines(line, onRoad: onRoad)),
                  MarkerLayer(
                    markers: _routeMarkers(
                      from: widget.from,
                      to: widget.to,
                      stops: widget.stops,
                      extra: [
                        ...widget.extraMarkers,
                        if (widget.live == null && widget.approachFrom != null)
                          _approachMarker(
                            widget.approachFrom!,
                            widget.approachVehicle,
                            widget.approachHeading,
                          ),
                      ],
                      // Толық экранда пиндер сәл ірілеу — саусақпен көрсетуге
                      // де, алыстан қарауға да ыңғайлы.
                      scale: 1.15,
                    ),
                  ),
                  if (widget.live != null)
                    RepaintBoundary(
                      child: AnimatedBuilder(
                        animation: _glide,
                        builder: (_, _) {
                          final g = _glidePos;
                          final v = widget.live!.value;
                          return _liveVehicleLayers(
                            g == null || v == null
                                ? null
                                : LiveVehicleFix(
                                    pos: g.$1,
                                    fix: _gTo!,
                                    heading: g.$2,
                                    type: v.type,
                                    toA: v.toA,
                                  ),
                            connect: _showApproach && _approachFix != null,
                          );
                        },
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
                          horizontal: 14,
                          vertical: 9,
                        ),
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
                            fontSize: 14,
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
                      borderRadius: BorderRadius.circular(Gz.rLg),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Gz.surface.withValues(alpha: 0.82),
                    borderRadius: BorderRadius.circular(Gz.rXs),
                  ),
                  child: Text(
                    '© OpenStreetMap',
                    style: TextStyle(
                      fontSize: 10,
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
                                    borderRadius: BorderRadius.circular(4),
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
                                          ? Padding(
                                              padding: EdgeInsets.all(1.5),
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Gz.blue,
                                              ),
                                            )
                                          : Icon(
                                              Icons.route_rounded,
                                              size: 17,
                                              color: Gz.blue,
                                            ),
                                    ),
                                    const SizedBox(width: 7),
                                    Expanded(
                                      child: Text(
                                        _summary(),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 14,
                                          height: 1.2,
                                          letterSpacing: -0.2,
                                        ),
                                      ),
                                    ),
                                    AnimatedRotation(
                                      duration: const Duration(
                                        milliseconds: 200,
                                      ),
                                      turns: _sheetOpen ? 0 : 0.5,
                                      child: Icon(
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
                                  _leg(
                                    const MapPin.origin(size: 18),
                                    t('Қайдан'),
                                    widget.fromLabel,
                                  ),
                                  for (
                                    var i = 0;
                                    i < widget.stops.length;
                                    i++
                                  ) ...[
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
                  fontSize: 14,
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
        borderRadius: BorderRadius.circular(2),
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
  }) => Container(
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

// ═══════════════════════════════════════════════════════════════════════
//  «КӨЛІК ҚАЙДА КЕЛЕ ЖАТЫР» — ТІРІ КАРТА (0075)
// ═══════════════════════════════════════════════════════════════════════

/// Тірі картаға керек маршрут деректері (заказ моделінен не алушының
/// веб-бетіндегі JSON-нан).
class TrackRoute {
  final LatLng from;
  final LatLng to;
  final List<LatLng> stops;
  final String status;
  final VehicleType vehicleType;
  final String? fromLabel;
  final String? toLabel;
  final List<String> stopLabels;
  final double? distanceKm;

  const TrackRoute({
    required this.from,
    required this.to,
    this.stops = const [],
    required this.status,
    required this.vehicleType,
    this.fromLabel,
    this.toLabel,
    this.stopLabels = const [],
    this.distanceKm,
  });

  factory TrackRoute.of(Order o) => TrackRoute(
    from: LatLng(o.fromLat, o.fromLng),
    to: LatLng(o.toLat, o.toLng),
    stops: [for (final s in o.stops) LatLng(s.lat, s.lng)],
    status: o.status,
    vehicleType: o.vehicleType,
    fromLabel: o.fromDisplay,
    toLabel: o.toDisplay,
    stopLabels: [for (final s in o.stops) s.display],
    distanceKm: o.distanceKm,
  );

  /// Маршрут нүктелері ретімен: A → аялдамалар → B.
  List<LatLng> get waypoints => [from, ...stops, to];
}

/// Клиенттің (және алушының) тірі картасы: орындаушының көлігі ӨЗ ТҮРІНІҢ
/// белгісімен ([VehicleMarker]), бағыт нұсқарымен, ҮЗІЛІССІЗ жылжиды.
///
/// Жаңа нүкте әдетте 12–15 с сайын келеді (орындаушы 15 с сайын жібереді,
/// клиент 12 с сайын сұрайды). Бұрын көлік 1,4 с ішінде жаңа нүктеге
/// «жүгіріп» барып, қалған 10+ секунд орнында тұратын — секіріп-тоқтап
/// жүргендей. Енді жылжу келесі жаңартуға дейінгі уақытқа созылады
/// (тұрақты жылдамдықпен) — Yandex Go-дағыдай шынайы қозғалыс.
///
/// Заказдың өз маршруты (A → аялдамалар → B) [RouteMap]-дегідей нақты ЖОЛ
/// бойымен, Tasu стилінде салынады (жол табылмаса — үзік доға). Жүргізуші
/// A-ға келе жатқанда (`accepted`) көліктен A-ға дейінгі жол СҰР түспен
/// көрсетіледі ([approachPolylines]) және көлік жүрген сайын қысқарады.
///
/// Жол геометриясы бар кезде көлік екі GPS нүктесінің арасында түзу
/// сызықпен емес, ЖОЛДЫҢ ӨЗІМЕН жылжиды, бағыты да жолдың бұрылысына
/// қарай бұрылады — шынайы қозғалыс.
///
/// Камера өзі теңшеледі: заказ қабылданғанда — көлік пен A нүктесі
/// (жүргізуші сізге келе жатыр), жолға шыққан соң — көлік пен B нүктесі.
/// Ішкі карта интерактивті ЕМЕС ([RouteMap]-дегі себеппен — бет
/// айналмай қалады); түртсе — толық экран.
class LiveTrackMap extends StatefulWidget {
  final TrackRoute route;

  /// Көліктің соңғы белгілі нүктесі (null — әлі белгісіз).
  final LatLng? vehicle;

  /// GPS бағыты (градус). null болса — қозғалыстан өзі есептеледі.
  final double? heading;

  /// Нүкте қаншалықты ескі (сек) — 3 минуттан асса «сигнал әлсіз».
  final int? ageSec;

  final double height;

  LiveTrackMap({
    super.key,
    required Order order,
    this.vehicle,
    this.heading,
    this.ageSec,
    this.height = 230,
  }) : route = TrackRoute.of(order);

  /// Заказ моделі жоқ жерде (алушының веб-беті) — жеке мәндермен.
  const LiveTrackMap.route({
    super.key,
    required this.route,
    this.vehicle,
    this.heading,
    this.ageSec,
    this.height = 230,
  });

  @override
  State<LiveTrackMap> createState() => _LiveTrackMapState();
}

class _LiveTrackMapState extends State<LiveTrackMap>
    with SingleTickerProviderStateMixin {
  /// Қысқа жылжу: алғашқы нүкте, жиі жаңарту не ұзақ үзілістен кейін.
  static const _glideShort = Duration(milliseconds: 1400);

  /// Ең ұзақ жылжу — клиенттің сұрау аралығынан сәл ұзақ (сұрау 5 с):
  /// көлік келесі нүкте келгенше тоқтамай жүріп тұрады.
  static const _glideMax = Duration(seconds: 8);

  /// Осыдан ұзақ үзіліс (көлік тұрып қалған / сигнал жоғалған) болса —
  /// көлік «баяу жүзбейді», жаңа орнына қысқа жылжумен барады.
  static const _gapReset = Duration(seconds: 30);

  final _map = MapController();
  bool _ready = false;
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: _glideShort,
  );

  /// Ұзақ жылжу — тұрақты жылдамдық (linear); қысқасы — жайлап басталып,
  /// жайлап тоқтайды.
  Curve _curve = Curves.easeInOut;
  LatLng? _animFrom;
  LatLng? _animTo;
  double? _bearing;

  /// Соңғы ЖАҢА нүкте келген сәт — келесі жылжудың ұзақтығы осыдан.
  DateTime? _lastFixAt;

  /// Заказ маршрутының нақты жол нүктелері (бос — әзірге жоқ, доға).
  List<LatLng> _road = const [];

  /// Көліктен A-ға дейінгі сұр жол (тек `accepted` кезінде).
  final _approach = _ApproachRoad();

  /// Көлік ЖОЛ БОЙЫМЕН жылжып жатса — сол сызық пен басы/соңы (метр).
  _PathMeasure? _path;
  double _pathS0 = 0;
  double _pathS1 = 0;

  /// Толық экранға берілетін тірі күй ([RouteMapScreen.live]).
  final _live = ValueNotifier<LiveVehicleFix?>(null);

  TrackRoute get _o => widget.route;
  LatLng get _a => _o.from;
  LatLng get _b => _o.to;
  bool get _toPickup => _o.status == 'accepted' || _o.status == 'arrived';
  LatLng get _target => _toPickup ? _a : _b;

  /// A-ға келе жатыр — сұр жол көрсетіледі.
  bool get _driving => _o.status == 'accepted';

  /// Көлік қазір жүріп келе жатқан жолдың геометриясы (жылжу үшін).
  List<LatLng> get _activeLine {
    if (_driving) return _approach.onRoad ? _approach.points : const [];
    return _road;
  }

  /// Көліктің ҚАЗІР көрініп тұрған орны мен бағыты (жылжу ортасында —
  /// аралық нүкте).
  (LatLng, double?)? get _currentState {
    final to = _animTo;
    final from = _animFrom;
    if (to == null) return null;
    if (from == null) return (to, _bearing);
    final k = _curve.transform(_anim.value);
    final path = _path;
    if (path != null) {
      final (p, b) = path.at(_pathS0 + (_pathS1 - _pathS0) * k);
      // Орнында тұрғанда жол бағыты емес, соңғы белгілі бағыт қалады.
      return (p, (_pathS1 - _pathS0).abs() > 3 ? b : _bearing);
    }
    return (
      LatLng(
        from.latitude + (to.latitude - from.latitude) * k,
        from.longitude + (to.longitude - from.longitude) * k,
      ),
      _bearing,
    );
  }

  LatLng? get _current => _currentState?.$1;

  @override
  void initState() {
    super.initState();
    _animTo = widget.vehicle;
    _bearing = widget.heading;
    if (widget.vehicle != null) _lastFixAt = DateTime.now();
    _anim.addListener(_pushLive);
    _loadRoad();
    _loadApproach();
    _pushLive();
  }

  bool _pushQueued = false;

  void _pushLive() {
    // build кезінде (initState/didUpdateWidget ішіндегі `forward`) басқа
    // беттегі тыңдаушыға (толық экран) setState жіберуге болмайды —
    // келесі кадрға қалдырамыз.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_pushQueued) return;
      _pushQueued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _pushQueued = false;
        if (mounted) _pushLive();
      });
      return;
    }
    final s = _currentState;
    final fix = _animTo;
    _live.value = s == null || fix == null
        ? null
        : LiveVehicleFix(
            pos: s.$1,
            fix: fix,
            heading: s.$2,
            type: _o.vehicleType,
            toA: _driving,
          );
  }

  /// Көліктің соңғы нүктесінен A-ға дейінгі сұр жолды сұрайды (сирек —
  /// [_ApproachRoad] өзі шешеді).
  void _loadApproach() {
    final v = _animTo;
    if (!_driving || v == null) {
      if (!_driving) _approach.reset();
      return;
    }
    _approach.update(v, _a, () {
      if (!mounted) return;
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fit();
      });
    });
  }

  /// Жаңа нүктеге дейінгі жылжуды ЖОЛ БОЙЫМЕН жасауға бола ма: екі нүкте
  /// де жолдың бойында (60 м ішінде) және алға қарай жүріп жатса ғана.
  /// Әйтпесе (жолдан ауытқыды, кері бұрылды) — түзу жылжу.
  void _planPath(LatLng from, LatLng to) {
    final p = _planAlong(_activeLine, from, to);
    _path = p?.m;
    _pathS0 = p?.s0 ?? 0;
    _pathS1 = p?.s1 ?? 0;
  }

  void _loadRoad() {
    final asked = _o.waypoints;
    _requestRoad(asked, (road) {
      // Сұрау жүріп жатқанда маршрут ауысқан болса — ескі жауап керек емес.
      if (!mounted || !_samePoints(asked, _o.waypoints)) return;
      setState(() => _road = road);
    });
  }

  /// Келесі жылжудың ұзақтығы — алдыңғы жаңа нүктеден бері өткен уақыт:
  /// көлік келесі жаңарту келгенше жүріп тұрады.
  Duration _glideFor(DateTime now) {
    final last = _lastFixAt;
    if (last == null) return _glideShort;
    final gap = now.difference(last);
    if (gap <= _glideShort || gap > _gapReset) return _glideShort;
    return gap > _glideMax ? _glideMax : gap;
  }

  @override
  void didUpdateWidget(LiveTrackMap old) {
    super.didUpdateWidget(old);
    if (!_samePoints(old.route.waypoints, _o.waypoints)) {
      _road = const [];
      _loadRoad();
    }
    final v = widget.vehicle;
    var refit = widget.route.status != old.route.status;
    final last = _animTo;
    if (v != null && (last == null || Geo.haversineKm(last, v) > 0.003)) {
      final prev = _current ?? v;
      final now = DateTime.now();
      // Сервер бағыт бермесе (ескі қосымша, GPS бағыты жоқ) — соңғы
      // жылжудан есептейміз; орнында тұрса бұрынғы бағыт сақталады.
      _bearing =
          widget.heading ??
          (Geo.haversineKm(prev, v) > 0.015 ? bearingDeg(prev, v) : _bearing);
      final glide = _glideFor(now);
      _lastFixAt = now;
      _curve = glide > _glideShort ? Curves.linear : Curves.easeInOut;
      _planPath(prev, v);
      _animFrom = prev;
      _animTo = v;
      _anim.duration = glide;
      _anim.forward(from: 0);
      refit = true;
      _loadApproach();
    } else if (widget.heading != null) {
      _bearing = widget.heading;
    }
    if (widget.route.status != old.route.status) _loadApproach();
    _pushLive();
    // Камераны build аяқталған соң ғана жылжытамыз (didUpdateWidget build
    // ішінде шақырылады — MapController-ді сол сәтте қозғау қауіпті).
    if (refit) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fit();
      });
    }
  }

  @override
  void dispose() {
    _anim.removeListener(_pushLive);
    _anim.dispose();
    // [_live] әдейі dispose етілмейді: толық экран ([RouteMapScreen]) әлі
    // ашық болып, бұл карта ертерек жабылса, ол өз dispose-ында тыңдаушысын
    // алып тастайды — жабылған нотификаторда бұл қате болар еді.
    super.dispose();
  }

  /// A-ға дейінгі сұр жолдың көрінетін бөлігі (соңғы нақты нүктеден).
  List<LatLng> get _approachLine {
    final v = _animTo;
    if (!_driving || v == null) return const [];
    return _approach.trimmed(v);
  }

  void _fit() {
    if (!_ready) return;
    // Көліктің ҚАЗІР көрініп тұрған орны да кадрда болуы керек: ол жаңа
    // нүктеге қарай бірнеше секунд жылжиды — әйтпесе кадрдың сыртынан
    // «кіріп» келер еді. Сұр жол айналма болса — ол да кадрда.
    final pts = [?_current, ?_animTo, _target, ..._approachLine];
    // Көліктің орны әлі белгісіз, ал сапар жолда (мақсат — B): B-ға 16
    // zoom-пен жақындатсақ карта бос көрінеді (сілтемемен бөліскен адам
    // тек B белгісін көреді) — бүкіл маршрутты (A → аялдамалар → B) көрсетеміз.
    if (_animTo == null && !_toPickup) {
      final route = [_a, ..._o.stops, _b];
      try {
        if (_degenerate(route)) {
          _map.move(_b, 16);
        } else {
          _map.fitCamera(
            CameraFit.bounds(
              bounds: LatLngBounds.fromPoints(route),
              padding: const EdgeInsets.fromLTRB(56, 72, 56, 48),
            ),
          );
        }
      } catch (_) {
        // карта әлі өлшенбеген — келесі жаңартуда теңшеледі
      }
      return;
    }
    try {
      if (pts.length < 2 ||
          _degenerate(pts) ||
          pts.every((p) => Geo.haversineKm(p, _target) < 0.08)) {
        _map.move(_animTo ?? _target, 16);
      } else {
        _map.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(pts),
            padding: const EdgeInsets.fromLTRB(56, 72, 56, 48),
          ),
        );
      }
    } catch (_) {
      // карта әлі өлшенбеген — келесі жаңартуда теңшеледі
    }
  }

  void _openFull(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RouteMapScreen(
          from: _a,
          to: _b,
          stops: _o.stops,
          routePoints: _road,
          // Толық экранда да көлік ТІРІ жылжиды.
          live: _live,
          approachToA: _driving,
          fromLabel: _o.fromLabel,
          toLabel: _o.toLabel,
          stopLabels: _o.stopLabels,
          distanceKm: _o.distanceKm,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stops = _o.stops;
    final stale = (widget.ageSec ?? 0) > 180;
    final onRoad = _road.isNotEmpty;
    return Container(
      height: widget.height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Gz.radius),
        border: Border.all(color: Gz.border),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: FlutterMap(
                mapController: _map,
                options: gzMapOptions(
                  initialCenter: widget.vehicle ?? _target,
                  initialZoom: 14,
                  interactive: false,
                  onMapReady: () {
                    _ready = true;
                    _fit();
                  },
                ),
                children: [
                  osmTileLayer(),
                  // Жүргізуші A-ға келе жатқанда — оның жолы СҰР түспен,
                  // заказ маршрутының астында.
                  if (_driving && _animTo != null)
                    PolylineLayer(
                      polylines: approachPolylines(
                        _approachLine,
                        onRoad: _approach.onRoad,
                      ),
                    ),
                  PolylineLayer(
                    polylines: _routeLines(
                      onRoad ? _road : _o.waypoints,
                      onRoad: onRoad,
                    ),
                  ),
                  MarkerLayer(
                    markers: _routeMarkers(
                      from: _a,
                      to: _b,
                      stops: stops,
                      extra: const [],
                    ),
                  ),
                  // Жылжып жүрген көлік — ӨЗ RepaintBoundary-сінде: FlutterMap
                  // бүкіл картаны бір шекарада салады, онсыз ұзақ жылжу кезінде
                  // әр кадрда сүзгіленген тайл қабаты да қайта салынар еді.
                  RepaintBoundary(
                    child: ValueListenableBuilder<LiveVehicleFix?>(
                      valueListenable: _live,
                      builder: (_, f, _) =>
                          _liveVehicleLayers(f, connect: _driving),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(onTap: () => _openFull(context)),
            ),
          ),
          if (widget.vehicle == null || stale)
            Positioned(
              left: 10,
              top: 10,
              right: 10,
              child: IgnorePointer(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
                    decoration: BoxDecoration(
                      color: Gz.surface,
                      borderRadius: BorderRadius.circular(Gz.rLg),
                      boxShadow: Gz.cardShadow,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.gps_not_fixed_rounded,
                          size: 15,
                          color: Gz.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            widget.vehicle == null
                                ? t('Көліктің орны әзірге белгісіз')
                                : t('Сигнал әлсіз — соңғы белгілі орны'),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Gz.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            right: 8,
            bottom: 8,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: Gz.surface,
                  shape: BoxShape.circle,
                  boxShadow: Gz.cardShadow,
                ),
                child: Icon(
                  Icons.open_in_full_rounded,
                  size: 15,
                  color: Gz.ink,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
