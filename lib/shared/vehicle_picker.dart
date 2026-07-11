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
/// карточкалар — эмодзи, атауы, қысқа сипаттама. Таңдалғаны қара фонда
/// сары жиекпен ерекшеленеді. Клиент заказ бергенде де, орындаушы
/// тіркелгенде де қолданылады.
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
  static const _cardW = 92.0;
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
      height: 98,
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
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              decoration: BoxDecoration(
                color: sel ? Gz.ink : Gz.bg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: sel ? Gz.yellow : Gz.border,
                  width: sel ? 2 : 1.2,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(v.emoji, style: const TextStyle(fontSize: 26)),
                  const SizedBox(height: 4),
                  Text(
                    v.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: sel ? Colors.white : Gz.ink,
                    ),
                  ),
                  Text(
                    v.hint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9.5,
                      color: sel ? Colors.white60 : Gz.textSecondary,
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
