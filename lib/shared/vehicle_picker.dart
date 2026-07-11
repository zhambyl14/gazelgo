import 'package:flutter/material.dart';

import '../core/lang.dart';
import '../core/models.dart';
import '../core/theme.dart';

/// «Шақыру» батырмасының жазуы — тілге қарай сөз тәртібі өзгереді
/// (kk: «Газель шақыру», ru: «Вызвать Газель»).
String vehicleCallLabel(VehicleType v) => Lang.current.value == AppLang.ru
    ? 'Вызвать ${v.label}'
    : '${v.label} шақыру';

/// Көлік түрін таңдау каруселі (indriver стилі): көлденең айналатын
/// шаршы карточкалар — эмодзи + атауы ғана (қосымша сипаттама жоқ).
/// Таңдалғаны қара фонда сары жиекпен ерекшеленеді. Клиент заказ бергенде
/// де, орындаушы тіркелгенде де қолданылады.
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
  static const _cardW = 74.0;
  static const _cardH = 68.0;
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
          return GestureDetector(
            onTap: () => widget.onChanged(v),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: _cardW,
              height: _cardH,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              decoration: BoxDecoration(
                color: sel ? Gz.ink : Gz.bg,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                  color: sel ? Gz.yellow : Gz.border,
                  width: sel ? 2 : 1.2,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(v.icon,
                      size: 24, color: sel ? Colors.white : Gz.ink),
                  const SizedBox(height: 4),
                  Text(
                    v.label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      height: 1.1,
                      fontWeight: FontWeight.w800,
                      color: sel ? Colors.white : Gz.ink,
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
