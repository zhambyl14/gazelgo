import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../shared/vehicle_picker.dart' show vehicleIcon;

// ═══════════════════════════════════════════════════════════════════════
//  «ОРЫНДАУШЫ ІЗДЕП ЖАТЫРМЫЗ» — TASU СТИЛІНДЕГІ КӨРНЕКІ БӨЛШЕКТЕР
// ═══════════════════════════════════════════════════════════════════════
//
// Біздің тіл — брендтің сары-қара түсі мен логотип-пин:
//   * картада алу нүктесінде Tasu логотип-пині тұрады, оның ұшынан
//     «жерге» сары толқындар таралады (ашылу экранындағы анимациямен
//     бірдей — қосымшаның өз «қолтаңбасы»);
//   * панельдің басында сары карточка: таңдалған көлік түрі «жолмен»
//     жүріп келе жатыр (жүк тасымалы қосымшасының өз бейнесі);
//   * жалған «~N мин» болжамы ЖОҚ — бидинг жүйесінде орындаушы қашан
//     жауап беретінін ешкім білмейді, сол себепті тек нақты ақпарат:
//     өткен уақыт пен келген ұсыныстар.
//
// Мұнда тек КӨРІНІС тұр. Заказдың деректері, стримдер, бас тарту/ұсыныс
// логикасы — order_detail_screen.dart ішінде. Әр анимациялы виджетте БІР
// ғана AnimationController бар әрі ол RepaintBoundary ішінде салынады.

/// Алу нүктесіндегі Tasu маягы: логотип-пин + оның ұшынан таралатын сары
/// эллипс-толқындар (перспективадағы «жер» әсері) + жұмсақ көлеңке.
///
/// Қорап [width]×[height]; координата — қораптың ДӘЛ ортасы (Marker-де
/// `Alignment.center`), пиннің ұшы да сол нүктеде тұрады. Өлшемі
/// ПИКСЕЛЬМЕН — картаның масштабына тәуелсіз.
///
/// [active] = false (жоспарланған тапсырыс әлі ізделмейді) — толқын да,
/// секіру де жоқ, тек тыныш пин.
class TasuPickupBeacon extends StatefulWidget {
  final bool active;
  const TasuPickupBeacon({super.key, this.active = true});

  static const width = 190.0;
  static const height = 150.0;

  @override
  State<TasuPickupBeacon> createState() => _TasuPickupBeaconState();
}

class _TasuPickupBeaconState extends State<TasuPickupBeacon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  static const _logoH = 46.0;
  static const _logoW = _logoH * 826 / 1013;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(TasuPickupBeacon old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) _sync();
  }

  void _sync() {
    // Жүйеде «анимацияны азайту» қосулы болса — тыныш пин.
    final reduce = WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;
    if (widget.active && !reduce) {
      _c.repeat();
    } else {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// Пиннің шағын секіруі: цикл басында (0..0.22) көтеріліп, қонады.
  static double _hop(double t) {
    if (t > 0.22) return 0;
    return math.sin(t / 0.22 * math.pi);
  }

  @override
  Widget build(BuildContext context) {
    final logo = Image.asset(
      'assets/icon/tasu_logo.png',
      height: _logoH,
      width: _logoW,
      filterQuality: FilterQuality.medium,
    );
    return RepaintBoundary(
      child: SizedBox(
        width: TasuPickupBeacon.width,
        height: TasuPickupBeacon.height,
        child: AnimatedBuilder(
          animation: _c,
          child: logo,
          builder: (context, pin) {
            final hop = widget.active ? _hop(_c.value) : 0.0;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _BeaconGroundPainter(
                      t: _c.value,
                      waves: widget.active,
                      lift: hop,
                    ),
                  ),
                ),
                Positioned(
                  left: (TasuPickupBeacon.width - _logoW) / 2,
                  top: TasuPickupBeacon.height / 2 - _logoH - 9 * hop,
                  child: pin!,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Пиннің астындағы «жер»: көлеңке-эллипс және үш сары толқын.
class _BeaconGroundPainter extends CustomPainter {
  final double t;
  final bool waves;
  final double lift;
  _BeaconGroundPainter({
    required this.t,
    required this.waves,
    required this.lift,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    if (waves) {
      for (var i = 0; i < 3; i++) {
        final k = Curves.easeOut.transform((t + i / 3) % 1);
        final w = 16 + (size.width - 20) * k;
        final rect = Rect.fromCenter(center: c, width: w, height: w * 0.34);
        final fade = 1 - k;
        canvas.drawOval(
          rect,
          Paint()..color = Gz.yellow.withValues(alpha: 0.16 * fade),
        );
        canvas.drawOval(
          rect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = Gz.yellowDark.withValues(alpha: 0.7 * fade),
        );
      }
    }
    final s = 1 - lift * 0.35;
    canvas.drawOval(
      Rect.fromCenter(center: c, width: 20 * s, height: 7 * s),
      Paint()
        ..color = Gz.ink.withValues(alpha: 0.28 * s)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
  }

  @override
  bool shouldRepaint(_BeaconGroundPainter old) =>
      old.t != t || old.waves != waves || old.lift != lift;
}

/// Сары карточкадағы «жол»: қою жолақ, ортасында сары үзік белгі, үстінде
/// таңдалған көлік түрі солдан оңға қарай үздіксіз жүріп өтеді.
///
/// [moving] = false — көлік жолдың ортасында тұрып қалады (анимация жоқ).
class SearchRoadStrip extends StatefulWidget {
  final VehicleType vehicle;
  final bool moving;
  const SearchRoadStrip({super.key, required this.vehicle, this.moving = true});

  @override
  State<SearchRoadStrip> createState() => _SearchRoadStripState();
}

class _SearchRoadStripState extends State<SearchRoadStrip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4200),
  );

  static const _iconSize = 38.0;
  static const _height = 50.0;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(SearchRoadStrip old) {
    super.didUpdateWidget(old);
    if (old.moving != widget.moving) _sync();
  }

  void _sync() {
    final reduce = WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;
    if (widget.moving && !reduce) {
      _c.repeat();
    } else {
      _c.stop();
      _c.value = 0.5;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Тек ОҢҒА қарайтын сурет: қосымшаның PNG-лері (кабинасы оң жақта)
    // немесе Material жүк көлігі. Эмодзи (🚐) көп платформада СОЛҒА қарайды —
    // оңға «кері жүріп» бара жатқандай көрінер еді.
    final png = widget.vehicle.pngAsset;
    final Widget icon = png != null
        ? Image.asset(png, width: _iconSize, height: _iconSize)
        : Icon(
            widget.vehicle.isTaxiCategory
                ? Icons.local_taxi_rounded
                : Icons.local_shipping_rounded,
            size: _iconSize - 2,
            color: Gz.ink,
          );
    return RepaintBoundary(
      child: SizedBox(
        height: _height,
        child: LayoutBuilder(
          builder: (context, box) {
            final w = box.maxWidth;
            return AnimatedBuilder(
              animation: _c,
              child: icon,
              builder: (context, child) {
                final t = _c.value;
                // Көлік кадрдың сыртынан кіріп, сыртына шығады; шеттерде
                // біртіндеп пайда болып/жоғалады.
                final x = -_iconSize + (w + _iconSize) * t;
                final edge = math.min(t, 1 - t);
                final opacity = (edge / 0.12).clamp(0.0, 1.0);
                // Жолдың сәл «дірілі» — қозғалыс сезімі.
                final bump = math.sin(t * math.pi * 14).abs() * 1.2;
                return Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 2,
                      height: 10,
                      child: CustomPaint(
                        painter: _RoadPainter(offset: widget.moving ? t : 0),
                      ),
                    ),
                    Positioned(
                      left: x,
                      bottom: 9 + bump,
                      child: Opacity(opacity: opacity, child: child),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// Қою жол жолағы + ортасында жылжымалы сары үзік белгі.
class _RoadPainter extends CustomPainter {
  final double offset;
  _RoadPainter({required this.offset});

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.height / 2),
    );
    canvas.drawRRect(r, Paint()..color = Gz.ink);
    const dash = 10.0, gap = 9.0;
    final y = size.height / 2;
    final p = Paint()
      ..color = Gz.yellow
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    // Белгі көліктің қарсы бағытында сырғиды — көлік алға жылжып бара
    // жатқандай көрінеді.
    final shift = -(offset * 600) % (dash + gap);
    for (var x = shift + 6; x < size.width - 6; x += dash + gap) {
      final a = math.max(x, 6.0);
      final b = math.min(x + dash, size.width - 6);
      if (b > a) canvas.drawLine(Offset(a, y), Offset(b, y), p);
    }
  }

  @override
  bool shouldRepaint(_RoadPainter old) => old.offset != offset;
}

/// Панельдің басындағы күй карточкасы (Tasu сары түсінде).
///
/// [badge] — тақырыптың алдындағы белгі (ұсыныс саны); [trailing] —
/// оң жақтағы элемент (уақыт); [bottom] — карточканың астыңғы бөлігі
/// (жол анимациясы немесе жоспарланған уақыт).
class SearchStatusCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? badge;
  final Widget? trailing;
  final Widget? bottom;

  /// Карточка түсі: әдепкіде брендтің сарысы; жоспарланған тапсырыста —
  /// күлгін реңк.
  final Color color;
  const SearchStatusCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.badge,
    this.trailing,
    this.bottom,
    this.color = Gz.yellow,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(Gz.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (badge != null) ...[badge!, const SizedBox(width: 8)],
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 19,
                    height: 1.15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                    color: Gz.ink,
                  ),
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 10), trailing!],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.3,
              fontWeight: FontWeight.w500,
              color: Gz.ink.withValues(alpha: 0.72),
            ),
          ),
          if (bottom != null) ...[const SizedBox(height: 6), bottom!],
        ],
      ),
    );
  }
}

/// Өткен уақыт белгісі: қара пилюля, ішінде сағат және «04:27».
/// Секунд сайын тек ОСЫ мәтін қайта салынады — бүкіл экран емес.
class SearchTimerChip extends StatelessWidget {
  final ValueListenable<int> seconds;
  const SearchTimerChip({super.key, required this.seconds});

  static String format(int s) {
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = sec.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
      decoration: BoxDecoration(
        color: Gz.ink,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.schedule_rounded, size: 14, color: Gz.yellow),
          const SizedBox(width: 4),
          ValueListenableBuilder<int>(
            valueListenable: seconds,
            builder: (_, s, _) => Text(
              format(s),
              maxLines: 1,
              textScaler: TextScaler.noScaling,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                // Сандар «билемеуі» үшін — әр цифрдың ені бірдей.
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Ұсыныс саны — қара дөңгелек белгі (сары карточканың үстінде анық).
class SearchCountBadge extends StatelessWidget {
  final int count;
  const SearchCountBadge(this.count, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 26),
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Gz.ink,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Text(
        '$count',
        textScaler: TextScaler.noScaling,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w900,
          color: Gz.yellow,
        ),
      ),
    );
  }
}

/// Баға карточкасы: көлік түрінің суреті мен атауы, сапар сипаттамасы,
/// клиенттің бағасы және «Бағаны көтеру» батырмасы.
class SearchPriceCard extends StatelessWidget {
  final VehicleType vehicle;
  final String meta;
  final String price;
  final VoidCallback? onRaise;
  const SearchPriceCard({
    super.key,
    required this.vehicle,
    required this.meta,
    required this.price,
    this.onRaise,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: Gz.surface,
        borderRadius: BorderRadius.circular(Gz.radius),
        border: Border.all(color: Gz.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Gz.yellow.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: vehicleIcon(vehicle, size: 34),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vehicle.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: Gz.ink,
                      ),
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Gz.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 140),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        price,
                        maxLines: 1,
                        style: const TextStyle(
                          fontSize: 22,
                          height: 1.1,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.4,
                          color: Gz.ink,
                        ),
                      ),
                    ),
                  ),
                  Text(
                    t('Сіздің бағаңыз'),
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Gz.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (onRaise != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRaise,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                foregroundColor: Gz.ink,
                side: const BorderSide(color: Gz.yellowDark, width: 1.4),
              ),
              icon: const Icon(Icons.trending_up_rounded, size: 20),
              label: Text(t('Бағаны көтеру')),
            ),
          ],
        ],
      ),
    );
  }
}

/// Картаның үстіндегі дөңгелек ақ батырма (артқа, бөлісу).
class SearchMapButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  const SearchMapButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final btn = Container(
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: Gz.cardShadow,
      ),
      child: Material(
        color: Gz.surface,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Icon(icon, size: 22, color: Gz.ink),
          ),
        ),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}

/// Панельдің тұтқасы (сүйреп үлкейтуге болатынын көрсетеді).
class SearchSheetHandle extends StatelessWidget {
  const SearchSheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 5,
        margin: const EdgeInsets.only(top: 8, bottom: 12),
        decoration: BoxDecoration(
          color: Gz.disabledBg,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }
}
