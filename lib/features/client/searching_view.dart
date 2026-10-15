import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../core/theme.dart';

// ═══════════════════════════════════════════════════════════════════════
//  «КӨЛІК ІЗДЕП ЖАТЫРМЫЗ» — КӨРНЕКІ БӨЛШЕКТЕР (Yandex Go үлгісі)
// ═══════════════════════════════════════════════════════════════════════
//
// Мұнда тек КӨРІНІС тұр: радар, «~N мин» пині, жүгіретін жолақ, панель
// бөлшектері. Заказдың деректі, стримдер, бас тарту/ұсыныс логикасы —
// order_detail_screen.dart ішінде. Әр анимациялы виджетте БІР ғана
// AnimationController бар әрі ол RepaintBoundary ішінде салынады —
// карта не панель қайта салынғанда анимация оларды қоса сүйретпейді.

/// Алу нүктесінің айналасындағы «радар» — бірінен соң бірі кеңейіп,
/// өшіп отыратын концентрлі шеңберлер («іздеп жатырмыз» әсері).
///
/// Өлшемі ПИКСЕЛЬМЕН берілген (картаның масштабына тәуелсіз): карта
/// жақындатылса да, алыстатылса да радар бірдей көрінеді.
class SearchRadar extends StatefulWidget {
  final double size;
  final Color color;

  /// Бір уақытта көрінетін толқын саны.
  final int waves;

  const SearchRadar({
    super.key,
    this.size = 230,
    this.color = Gz.blue,
    this.waves = 3,
  });

  @override
  State<SearchRadar> createState() => _SearchRadarState();
}

class _SearchRadarState extends State<SearchRadar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.square(widget.size),
          painter: _RadarPainter(_c, widget.color, widget.waves),
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final Animation<double> anim;
  final Color color;
  final int waves;

  _RadarPainter(this.anim, this.color, this.waves) : super(repaint: anim);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final maxR = size.shortestSide / 2;
    // Ортадағы тұрақты солғын дақ — толқындар «осы нүктеден» шығады.
    canvas.drawCircle(
      c,
      maxR * 0.16,
      Paint()..color = color.withValues(alpha: 0.12),
    );
    for (var i = 0; i < waves; i++) {
      final p = (anim.value + i / waves) % 1.0;
      final r = maxR * (0.12 + 0.88 * Curves.easeOutCubic.transform(p));
      // Кеңейген сайын өшеді: шеті ешқашан «кесіліп» қалмайды.
      final fade = math.pow(1 - p, 1.4).toDouble();
      canvas.drawCircle(
        c,
        r,
        Paint()..color = color.withValues(alpha: 0.16 * fade),
      );
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = color.withValues(alpha: 0.5 * fade),
      );
    }
  }

  @override
  bool shouldRepaint(_RadarPainter old) =>
      old.anim != anim || old.color != color || old.waves != waves;
}

/// Алу нүктесі — ақ өзекті көк сақина (Yandex Go-дағы «мен осындамын»).
class SearchPickupDot extends StatelessWidget {
  final double size;
  final Color color;
  const SearchPickupDot({super.key, this.size = 18, this.color = Gz.blue});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: color, width: size * 0.26),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33101828),
            blurRadius: 4,
            offset: Offset(0, 1.5),
          ),
        ],
      ),
    );
  }
}

/// Соңғы нүкте — қара шаршы (маршрут «осында тоқтайды»).
class SearchDestinationSquare extends StatelessWidget {
  final double size;

  /// Картада — ақ контурмен (тайлдан үзіліп тұруы үшін), тізімде — контурсыз.
  final bool outlined;
  const SearchDestinationSquare({
    super.key,
    this.size = 16,
    this.outlined = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Gz.ink,
        borderRadius: BorderRadius.circular(size * 0.22),
        border: outlined ? Border.all(color: Colors.white, width: 2.5) : null,
        boxShadow: outlined
            ? const [
                BoxShadow(
                  color: Color(0x33101828),
                  blurRadius: 4,
                  offset: Offset(0, 1.5),
                ),
              ]
            : null,
      ),
    );
  }
}

/// Аралық аялдама — ақ өзекті сұр сақина (алу нүктесі мен соңғы нүктеден
/// әдейі әлсіз: маршруттың басы мен соңы басым көрінуі керек).
class SearchStopDot extends StatelessWidget {
  final double size;
  const SearchStopDot({super.key, this.size = 13});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: Gz.textSecondary, width: size * 0.26),
      ),
    );
  }
}

/// Алу нүктесінің ҮСТІНДЕ тұратын пин: түрлі-түсті шаршыда айналып тұрған
/// доға (іздеу жүріп жатыр) + ақ капсулада «~N мин». Астында — нүктеге
/// түсетін жіңішке «сабақ».
///
/// [label] `null` болса тек белгі көрінеді (мыс. жоспарланған тапсырыс —
/// уақыты панельде жазылған, оны екі рет қайталамаймыз).
class SearchEtaPill extends StatelessWidget {
  final String? label;
  final Color color;

  /// `true` — ішінде айналып тұрған доға; `false` — [icon].
  final bool spinning;
  final IconData icon;

  /// Сабақтың астындағы бос орын — нүктенің радиусы (сабақ нүктеге дәл
  /// тиіп тұруы үшін).
  final double bottomGap;

  const SearchEtaPill({
    super.key,
    this.label,
    this.color = Gz.blue,
    this.spinning = true,
    this.icon = Icons.schedule_rounded,
    this.bottomGap = 9,
  });

  @override
  Widget build(BuildContext context) {
    final badge = Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: spinning
          ? const SizedBox(
              width: 16,
              height: 16,
              child: RepaintBoundary(
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  strokeCap: StrokeCap.round,
                  color: Colors.white,
                ),
              ),
            )
          : Icon(icon, size: 18, color: Colors.white),
    );
    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.fromLTRB(5, 5, label == null ? 5 : 13, 5),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: Gz.liftShadow,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  badge,
                  if (label != null) ...[
                    const SizedBox(width: 9),
                    Text(
                      label!,
                      maxLines: 1,
                      textScaler: TextScaler.noScaling,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        height: 1.1,
                        letterSpacing: -0.2,
                        color: Gz.ink,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Container(
              width: 2.5,
              height: 10,
              decoration: BoxDecoration(
                color: Gz.ink.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            SizedBox(height: bottomGap),
          ],
        ),
      ),
    );
  }
}

/// Жіңішке «шексіз» жолақ: ашық жолдың бойымен көк кесінді жүгіреді.
/// Іздеу ТОҚТАМАҒАНЫН көрсетеді (пайыз жоқ — қашан табылатыны белгісіз).
class SearchProgressBar extends StatefulWidget {
  final Color color;
  final double height;
  const SearchProgressBar({super.key, this.color = Gz.blue, this.height = 4});

  @override
  State<SearchProgressBar> createState() => _SearchProgressBarState();
}

class _SearchProgressBarState extends State<SearchProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: Size(double.infinity, widget.height),
        painter: _BarPainter(_c, widget.color),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  final Animation<double> anim;
  final Color color;
  _BarPainter(this.anim, this.color) : super(repaint: anim);

  @override
  void paint(Canvas canvas, Size size) {
    final r = Radius.circular(size.height / 2);
    final track = RRect.fromRectAndRadius(Offset.zero & size, r);
    canvas.drawRRect(track, Paint()..color = color.withValues(alpha: 0.14));
    canvas.save();
    canvas.clipRRect(track);
    final seg = size.width * 0.34;
    final x =
        -seg + (size.width + seg) * Curves.easeInOut.transform(anim.value);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(x, 0, seg, size.height), r),
      Paint()..color = color,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BarPainter old) => old.anim != anim || old.color != color;
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
        margin: const EdgeInsets.only(top: 8, bottom: 14),
        decoration: BoxDecoration(
          color: Gz.disabledBg,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }
}

/// Іздеу басталғаннан бергі уақыт: «04:27» (сағаттан асса «1:04:27»).
/// Секунд сайын тек ОСЫ мәтін қайта салынады — бүкіл экран емес.
class SearchElapsedText extends StatelessWidget {
  final ValueListenable<int> seconds;
  final TextStyle? style;
  const SearchElapsedText({super.key, required this.seconds, this.style});

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
    return ValueListenableBuilder<int>(
      valueListenable: seconds,
      builder: (_, s, _) => Text(
        format(s),
        maxLines: 1,
        style: (style ?? const TextStyle()).copyWith(
          // Сандар «билемеуі» үшін — әр цифрдың ені бірдей.
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// Ұсыныс саны — сары дөңгелек белгі.
class SearchCountBadge extends StatelessWidget {
  final int count;
  const SearchCountBadge(this.count, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 24),
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Gz.yellow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$count',
        textScaler: TextScaler.noScaling,
        style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w900,
          color: Gz.ink,
        ),
      ),
    );
  }
}

/// Маршрут карточкасы (ашық сұр): көк сақина → аялдамалар → қара шаршы.
class SearchRouteCard extends StatelessWidget {
  final String from;
  final String to;
  final List<String> stops;
  const SearchRouteCard({
    super.key,
    required this.from,
    required this.to,
    this.stops = const [],
  });

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[
      _row(const SearchPickupDot(size: 14), from),
      for (final s in stops) ...[_divider(), _row(const SearchStopDot(), s)],
      _divider(),
      _row(const SearchDestinationSquare(size: 13, outlined: false), to),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: Gz.surfaceAlt,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Gz.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      ),
    );
  }

  Widget _row(Widget mark, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      children: [
        SizedBox(width: 18, child: Center(child: mark)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text.isEmpty ? '—' : text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              height: 1.25,
              letterSpacing: -0.1,
              color: Gz.ink,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _divider() =>
      const Divider(height: 1, thickness: 1, indent: 30, color: Gz.border);
}

/// Төлем жолы: ақша иконкасы + «Қолма-қол не аударым» (астында көлік түрі)
/// + оң жақта баға.
class SearchPaymentRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final String price;
  const SearchPaymentRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.price,
  });

  @override
  Widget build(BuildContext context) {
    Widget row(double maxW) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Gz.tint(Gz.green),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.payments_outlined, color: Gz.green),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: Gz.ink,
                  ),
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: Gz.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Үлкен сома (межгород, 1 000 000+ ₸) тар экранда сызықтан
          // шықпайды — енінің жартысынан аспайды, сыймаса кішірейеді.
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxW * 0.45),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                price,
                maxLines: 1,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 19,
                  letterSpacing: -0.4,
                  color: Gz.ink,
                ),
              ),
            ),
          ),
        ],
      ),
    );
    return LayoutBuilder(builder: (_, box) => row(box.maxWidth));
  }
}

/// Үлкен ашық сұр батырма (панельдің ең астында: «Күте алмаймын»).
class SearchSoftButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  const SearchSoftButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: Gz.disabledBg,
        foregroundColor: Gz.ink,
        minimumSize: const Size.fromHeight(54),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(
          fontFamily: Gz.fontFamily,
          fontWeight: FontWeight.w800,
          fontSize: 16,
        ),
      ),
      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}
