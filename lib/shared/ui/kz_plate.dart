/// Қазақстан мемлекеттік нөмір белгісі (ақ тақташа, сол жақта KZ + ту,
/// ортада нөмір, оң жақта аймақ коды) және көлік түсінің белгісі.
library;

import 'package:flutter/material.dart';

import '../../core/car_colors.dart';
import '../../core/theme.dart';

/// Нөмірді бөліктерге ажыратады: `237BLM01` → ('237 BLM', '01').
/// Таныс емес пішін (ескі нөмір, шетелдік) — тұтас, аймақсыз көрсетіледі.
({String main, String? region}) splitKzPlate(String raw) {
  final s = raw.replaceAll(RegExp(r'\s+'), '').toUpperCase();
  final m = RegExp(r'^(\d{3})(\p{L}{2,3})(\d{2})$', unicode: true).firstMatch(s);
  if (m != null) return (main: '${m[1]} ${m[2]}', region: m[3]);
  return (main: raw.trim().toUpperCase(), region: null);
}

class KzPlate extends StatelessWidget {
  final String plate;

  /// Тақташаның биіктігі; қаріп өлшемі соған қарай есептеледі.
  final double height;
  const KzPlate(this.plate, {super.key, this.height = 44});

  @override
  Widget build(BuildContext context) {
    if (plate.trim().isEmpty) return const SizedBox.shrink();
    final p = splitKzPlate(plate);
    final big = height * 0.56;
    const ink = Color(0xFF111111);
    return Semantics(
      label: plate,
      child: ExcludeSemantics(
        child: Container(
          height: height,
          padding: EdgeInsets.symmetric(horizontal: height * 0.14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(height * 0.16),
            border: Border.all(color: ink, width: 1.6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // KZ + ту
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _Flag(width: height * 0.34),
                  SizedBox(height: height * 0.04),
                  Text(
                    'KZ',
                    style: TextStyle(
                      color: ink,
                      fontWeight: FontWeight.w800,
                      fontSize: height * 0.22,
                      height: 1,
                    ),
                  ),
                ],
              ),
              SizedBox(width: height * 0.16),
              Text(
                p.main,
                style: TextStyle(
                  color: ink,
                  fontWeight: FontWeight.w800,
                  fontSize: big,
                  letterSpacing: 0.5,
                  height: 1.05,
                ),
              ),
              if (p.region != null) ...[
                SizedBox(width: height * 0.14),
                Container(width: 1.6, height: height * 0.7, color: ink),
                SizedBox(width: height * 0.14),
                Text(
                  p.region!,
                  style: TextStyle(
                    color: ink,
                    fontWeight: FontWeight.w800,
                    fontSize: big * 0.95,
                    height: 1.05,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Кішкентай ту: көгілдір фон + сары күн.
class _Flag extends StatelessWidget {
  final double width;
  const _Flag({required this.width});

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: width * 0.62,
    decoration: BoxDecoration(
      color: const Color(0xFF00AFCA),
      borderRadius: BorderRadius.circular(1.5),
    ),
    alignment: Alignment.center,
    child: Container(
      width: width * 0.3,
      height: width * 0.3,
      decoration: const BoxDecoration(
        color: Color(0xFFFEC50C),
        shape: BoxShape.circle,
      ),
    ),
  );
}

/// Түс үлгісі: кішкентай шеңбер.
Widget carColorDot(CarColor c, {double size = 16}) => Container(
  width: size,
  height: size,
  decoration: BoxDecoration(
    color: c.color,
    shape: BoxShape.circle,
    border: Border.all(color: Gz.border, width: 1.2),
  ),
);

/// «● Ақ» — түс үлгісі мен атауы (клиентке көрсетіледі).
class CarColorChip extends StatelessWidget {
  final String? code;
  const CarColorChip(this.code, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = carColorFor(code);
    if (c == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Gz.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Gz.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          carColorDot(c, size: 16),
          const SizedBox(width: 6),
          Text(
            c.label,
            style: TextStyle(
              color: Gz.ink,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

/// Түс таңдау (орындаушы өтінімі, модератор формасы).
class CarColorPicker extends StatelessWidget {
  final String? value;
  final ValueChanged<String> onChanged;
  const CarColorPicker({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final c in kCarColors)
        ChoiceChip(
          avatar: carColorDot(c, size: 18),
          label: Text(c.label),
          selected: value == c.code,
          onSelected: (_) => onChanged(c.code),
        ),
    ],
  );
}
