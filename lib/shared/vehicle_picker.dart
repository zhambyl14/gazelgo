import 'package:flutter/material.dart';

import '../core/lang.dart';
import '../core/models.dart';
import '../core/theme.dart';

/// «Шақыру» батырмасының жазуы — тілге қарай сөз тәртібі өзгереді
/// (kk: «Газель шақыру», ru: «Вызвать Газель»).
String vehicleCallLabel(VehicleType v) => Lang.current.value == AppLang.ru
    ? 'Вызвать ${v.label}'
    : '${v.label} шақыру';

/// Көлік түрінің иконкасы: PNG бар түрлерге (kamaz/crane/manipulator/
/// assenizator/excavator/loader/minivan) — түрлі-түсті сурет, қалғанына
/// (gazelle/furgon/tractor) — эмодзи. Екеуі де ДӘЛ БІРДЕЙ [size]×[size]
/// қораптың ортасында — көрінетін өлшемі бірдей болады. PNG түрлі-түсті
/// болғандықтан [color] тек эмодзиге әсер етпейді (глиф өз түсін сақтайды) —
/// параметр басқа шақыру орындарымен үйлесімділік үшін қалдырылған.
Widget vehicleIcon(VehicleType v, {double size = 24, Color? color}) {
  final png = v.pngAsset;
  return SizedBox(
    width: size,
    height: size,
    child: Center(
      child: png != null
          ? Image.asset(png, width: size, height: size, fit: BoxFit.contain)
          : Text(v.emoji, style: TextStyle(fontSize: size * 0.8, height: 1)),
    ),
  );
}

/// Көлік түрін таңдау каруселі (indriver стилі): көлденең айналатын
/// шаршы карточкалар — иконка (PNG не эмодзи, бәрі бірдей өлшемде) + атауы.
/// Таңдалғаны қара фонда сары жиекпен ерекшеленеді. Атауы FittedBox арқылы
/// карточкаға ӘРҚАШАН сыяды —
/// «…» болып қиылмайды, екінші жолға түспейді, жүйе шрифті үлкейтілсе де
/// (accessibility text scale) рамкадан аспайды. Клиент заказ бергенде де,
/// орындаушы тіркелгенде де қолданылады.
class VehicleTypeCarousel extends StatefulWidget {
  final VehicleType selected;
  final ValueChanged<VehicleType> onChanged;
  const VehicleTypeCarousel({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  State<VehicleTypeCarousel> createState() => _VehicleTypeCarouselState();
}

class _VehicleTypeCarouselState extends State<VehicleTypeCarousel> {
  static const _cardW = 82.0;
  static const _cardH = 72.0;
  static const _gap = 8.0;

  late final ScrollController _scroll = ScrollController(
    // ашылғанда таңдалған түр көрініп тұрсын
    initialScrollOffset:
        (VehicleType.values.indexOf(widget.selected) * (_cardW + _gap))
            .clamp(0, double.infinity)
            .toDouble(),
  );

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final desc = widget.selected.description;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _carousel(),
        // Таңдалған көлік түрінің түсініктемесі (мыс. «Фура» — 5–20 тонна).
        // Түсініктеме бар түрлерге ғана көрінеді, таңдау өзгергенде жаңарады.
        if (desc.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.info_outline, size: 15, color: Gz.textSecondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  desc,
                  style: const TextStyle(
                    color: Gz.textSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _carousel() {
    return SizedBox(
      height: _cardH,
      child: ListView.separated(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        itemCount: VehicleType.values.length,
        separatorBuilder: (_, i) => const SizedBox(width: _gap),
        itemBuilder: (_, i) {
          final v = VehicleType.values[i];
          final sel = v == widget.selected;
          final fg = sel ? Colors.white : Gz.ink;
          return GestureDetector(
            onTap: () => widget.onChanged(v),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: _cardW,
              height: _cardH,
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 8),
              decoration: BoxDecoration(
                color: sel ? Gz.ink : Gz.bg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: sel ? Gz.yellow : Gz.border,
                  width: sel ? 2 : 1.2,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  vehicleIcon(v, size: 27, color: fg),
                  const SizedBox(height: 6),
                  // FittedBox: атау рамкаға сыймаса — кішірейеді (қиылмайды,
                  // екінші жолға түспейді). Тұрақты өлшемді box (ені + биіктігі)
                  // жүйе шрифті масштабы үлкейгенде де асып кетуді болдырмайды.
                  SizedBox(
                    width: double.infinity,
                    height: 14,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        v.label,
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: fg,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
