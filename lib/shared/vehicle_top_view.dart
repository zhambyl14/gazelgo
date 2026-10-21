import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/vehicle_catalog.dart';

/// Көліктің ТӨБЕСІНЕН көрінетін силуэтінің түрі.
enum TopViewShape { car, van, truck, machine }

/// Көлік түрінен силуэт таңдау: такси — жеңіл көлік, жеткізу/газель —
/// фургон, ауыр жүк көліктері — кабина + кузов, арнайы техника — шынжыр
/// табанды/ықшам машина.
TopViewShape topViewShapeOf(VehicleType t) {
  switch (t.code) {
    case 'taxi':
    case 'umay':
      return TopViewShape.car;
    case 'delivery':
    case 'minivan':
    case 'furgon':
    case 'gazelle':
      return TopViewShape.van;
    case 'excavator':
    case 'loader':
    case 'tractor':
      return TopViewShape.machine;
  }
  // Модератор қосқан жаңа түр: такси санатында болса — жеңіл көлік,
  // әйтпесе — жүк көлігі.
  return t.isTaxiCategory ? TopViewShape.car : TopViewShape.truck;
}

/// Корпус түсі: такси — брендтік сары, Ұмай — жұмсақ қызғылт, жүк
/// көліктері — ақ корпус + сары кабина, техника — құрылыс сарысы.
Color topViewBodyColor(VehicleType t) => switch (t.code) {
  'umay' => Gz.vehicleUmayBody,
  'delivery' || 'minivan' || 'furgon' || 'gazelle' => Colors.white,
  _ => topViewShapeOf(t) == TopViewShape.truck ? Colors.white : Gz.yellow,
};

/// Төбеден көрінетін көлік — [heading] бағытына қарай ТҰТАС бұрылады
/// (градус, 0 = солтүстік, сағат тілімен; берілмесе — тұмсығы жоғары).
class VehicleTopView extends StatelessWidget {
  final VehicleType type;
  final double size;
  final double? heading;

  const VehicleTopView({
    super.key,
    required this.type,
    this.size = 46,
    this.heading,
  });

  @override
  Widget build(BuildContext context) {
    final painter = _TopViewPainter(
      shape: topViewShapeOf(type),
      body: topViewBodyColor(type),
      accent: Gz.yellow,
      outline: Gz.inkDeep,
    );
    return RepaintBoundary(
      child: Transform.rotate(
        angle: (heading ?? 0) * math.pi / 180,
        child: CustomPaint(size: Size.square(size), painter: painter),
      ),
    );
  }
}

class _TopViewPainter extends CustomPainter {
  final TopViewShape shape;
  final Color body;
  final Color accent;
  final Color outline;

  const _TopViewPainter({
    required this.shape,
    required this.body,
    required this.accent,
    required this.outline,
  });

  static const _glass = Gz.vehicleGlass;
  static const _glassHi = Gz.vehicleGlassHi;
  static const _light = Gz.vehicleHeadlight;
  static const _tail = Gz.vehicleTaillight;

  @override
  void paint(Canvas canvas, Size size) {
    final d = size.shortestSide;
    final c = size.center(Offset.zero);
    final len = d * 0.86;
    switch (shape) {
      case TopViewShape.car:
        _car(canvas, c, len);
      case TopViewShape.van:
        _van(canvas, c, len);
      case TopViewShape.truck:
        _truck(canvas, c, len);
      case TopViewShape.machine:
        _machine(canvas, c, len);
    }
  }

  // ── Ортақ бөлшектер ────────────────────────────────────────────────

  /// Корпустың жұмсақ көлеңкесі — көлік картаның үстінде қалқып тұрады.
  void _shadow(Canvas canvas, RRect r) {
    canvas.drawRRect(
      r.shift(Offset(0, r.width * 0.06)),
      Paint()
        ..color = Gz.vehicleShadow
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r.width * 0.14),
    );
  }

  /// Корпус: жоғарыдан төмен сәл қоюланатын градиент + жіңішке контур
  /// (ашық та, қараңғы карта сүзгісінде де фоннан бөлініп тұрады).
  void _body(Canvas canvas, RRect r, Color color) {
    canvas.drawRRect(
      r,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Color.lerp(color, Colors.black, 0.12)!,
            Color.lerp(color, Colors.white, 0.18)!,
            Color.lerp(color, Colors.black, 0.12)!,
          ],
        ).createShader(r.outerRect),
    );
    canvas.drawRRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.8, r.width * 0.045)
        ..color = outline.withValues(alpha: 0.55),
    );
  }

  /// Трапеция пішінді әйнек (алдыңғы/артқы).
  void _glassPane(
    Canvas canvas,
    double cx,
    double top,
    double bottom,
    double wTop,
    double wBottom,
  ) {
    final p = Path()
      ..moveTo(cx - wTop / 2, top)
      ..lineTo(cx + wTop / 2, top)
      ..lineTo(cx + wBottom / 2, bottom)
      ..lineTo(cx - wBottom / 2, bottom)
      ..close();
    canvas.drawPath(
      p,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_glassHi, _glass],
        ).createShader(p.getBounds()),
    );
  }

  void _headlights(Canvas canvas, double cx, double y, double w) {
    final r = w * 0.1;
    final p = Paint()..color = _light;
    canvas.drawCircle(Offset(cx - w * 0.32, y), r, p);
    canvas.drawCircle(Offset(cx + w * 0.32, y), r, p);
  }

  void _taillights(Canvas canvas, double cx, double y, double w) {
    final p = Paint()..color = _tail;
    final s = Size(w * 0.2, w * 0.07);
    for (final dx in [-w * 0.3, w * 0.3]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(cx + dx, y),
            width: s.width,
            height: s.height,
          ),
          Radius.circular(s.height / 2),
        ),
        p,
      );
    }
  }

  void _mirrors(Canvas canvas, double cx, double y, double w, Color color) {
    final p = Paint()..color = Color.lerp(color, Colors.black, 0.25)!;
    for (final sx in [-1.0, 1.0]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx + sx * (w / 2 + w * 0.06), y),
          width: w * 0.16,
          height: w * 0.1,
        ),
        p,
      );
    }
  }

  // ── Силуэттер ──────────────────────────────────────────────────────

  void _car(Canvas canvas, Offset c, double len) {
    final w = len * 0.47;
    final r = RRect.fromRectAndRadius(
      Rect.fromCenter(center: c, width: w, height: len),
      Radius.circular(w * 0.36),
    );
    final top = r.top;
    _shadow(canvas, r);
    _mirrors(canvas, c.dx, top + len * 0.33, w, body);
    _body(canvas, r, body);
    // Алдыңғы әйнек, төбе, артқы әйнек.
    _glassPane(
      canvas,
      c.dx,
      top + len * 0.24,
      top + len * 0.38,
      w * 0.6,
      w * 0.78,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(
          c.dx - w * 0.36,
          top + len * 0.38,
          c.dx + w * 0.36,
          top + len * 0.7,
        ),
        Radius.circular(w * 0.14),
      ),
      Paint()..color = Color.lerp(body, Colors.white, 0.28)!,
    );
    _glassPane(
      canvas,
      c.dx,
      top + len * 0.7,
      top + len * 0.82,
      w * 0.74,
      w * 0.56,
    );
    _headlights(canvas, c.dx, top + len * 0.05, w);
    _taillights(canvas, c.dx, r.bottom - len * 0.035, w);
  }

  void _van(Canvas canvas, Offset c, double len) {
    final w = len * 0.5;
    final r = RRect.fromRectAndCorners(
      Rect.fromCenter(center: c, width: w, height: len),
      topLeft: Radius.circular(w * 0.34),
      topRight: Radius.circular(w * 0.34),
      bottomLeft: Radius.circular(w * 0.12),
      bottomRight: Radius.circular(w * 0.12),
    );
    final top = r.top;
    _shadow(canvas, r);
    _mirrors(canvas, c.dx, top + len * 0.2, w, accent);
    _body(canvas, r, body);
    // Кабинаның сары төбесі — брендтің белгісі.
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTRB(r.left, top, r.right, top + len * 0.3),
        topLeft: Radius.circular(w * 0.34),
        topRight: Radius.circular(w * 0.34),
      ),
      Paint()..color = accent,
    );
    _glassPane(
      canvas,
      c.dx,
      top + len * 0.11,
      top + len * 0.24,
      w * 0.66,
      w * 0.82,
    );
    // Жүк бөлігінің төбесіндегі қабырғалар.
    final rib = Paint()
      ..color = outline.withValues(alpha: 0.14)
      ..strokeWidth = math.max(0.6, w * 0.03);
    for (var i = 1; i <= 3; i++) {
      final y = top + len * (0.36 + i * 0.14);
      canvas.drawLine(
        Offset(r.left + w * 0.14, y),
        Offset(r.right - w * 0.14, y),
        rib,
      );
    }
    _headlights(canvas, c.dx, top + len * 0.04, w);
    _taillights(canvas, c.dx, r.bottom - len * 0.03, w);
  }

  void _truck(Canvas canvas, Offset c, double len) {
    final cabW = len * 0.4;
    final boxW = len * 0.46;
    final top = c.dy - len / 2;
    final cab = RRect.fromRectAndCorners(
      Rect.fromLTWH(c.dx - cabW / 2, top, cabW, len * 0.27),
      topLeft: Radius.circular(cabW * 0.3),
      topRight: Radius.circular(cabW * 0.3),
      bottomLeft: Radius.circular(cabW * 0.08),
      bottomRight: Radius.circular(cabW * 0.08),
    );
    final box = RRect.fromRectAndRadius(
      Rect.fromLTWH(c.dx - boxW / 2, top + len * 0.3, boxW, len * 0.7),
      Radius.circular(boxW * 0.08),
    );
    _shadow(canvas, box);
    _shadow(canvas, cab);
    _mirrors(canvas, c.dx, top + len * 0.15, cabW, accent);
    _body(canvas, box, body);
    _body(canvas, cab, accent);
    _glassPane(
      canvas,
      c.dx,
      top + len * 0.07,
      top + len * 0.16,
      cabW * 0.62,
      cabW * 0.78,
    );
    final rib = Paint()
      ..color = outline.withValues(alpha: 0.14)
      ..strokeWidth = math.max(0.6, boxW * 0.03);
    for (var i = 1; i <= 4; i++) {
      final y = box.top + box.height * i / 5;
      canvas.drawLine(
        Offset(box.left + boxW * 0.12, y),
        Offset(box.right - boxW * 0.12, y),
        rib,
      );
    }
    _headlights(canvas, c.dx, top + len * 0.035, cabW);
    _taillights(canvas, c.dx, box.bottom - len * 0.025, boxW);
  }

  void _machine(Canvas canvas, Offset c, double len) {
    final w = len * 0.56;
    final bodyLen = len * 0.62;
    final bodyTop = c.dy - len / 2 + len * 0.26;
    final tracks = Paint()..color = Gz.vehicleTracks;
    // Шынжыр табандар / дөңгелектер.
    for (final sx in [-1.0, 1.0]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            c.dx + sx * w / 2 - (sx > 0 ? w * 0.2 : 0),
            bodyTop - len * 0.02,
            w * 0.2,
            bodyLen + len * 0.06,
          ),
          Radius.circular(w * 0.08),
        ),
        tracks,
      );
    }
    final r = RRect.fromRectAndRadius(
      Rect.fromLTWH(c.dx - w * 0.36, bodyTop, w * 0.72, bodyLen),
      Radius.circular(w * 0.12),
    );
    _shadow(canvas, r);
    // Алдыңғы жебе / шөміш.
    final boom = RRect.fromRectAndRadius(
      Rect.fromLTWH(c.dx - w * 0.1, c.dy - len / 2, w * 0.2, len * 0.34),
      Radius.circular(w * 0.06),
    );
    _body(canvas, boom, Color.lerp(accent, Colors.black, 0.08)!);
    _body(canvas, r, body);
    // Кабина әйнегі.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          c.dx - w * 0.22,
          bodyTop + bodyLen * 0.14,
          w * 0.44,
          bodyLen * 0.32,
        ),
        Radius.circular(w * 0.08),
      ),
      Paint()..color = _glass,
    );
  }

  @override
  bool shouldRepaint(_TopViewPainter old) =>
      old.shape != shape ||
      old.body != body ||
      old.accent != accent ||
      old.outline != outline;
}
