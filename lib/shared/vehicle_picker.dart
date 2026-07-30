import 'package:flutter/material.dart';

import '../core/lang.dart';
import '../core/models.dart';
import '../core/theme.dart';

/// «Шақыру» батырмасының жазуы — тілге қарай сөз тәртібі өзгереді
/// (kk: «Газель шақыру», ru: «Вызвать Газель»).
///
/// Такси — жалқы есім емес, сол себепті орысша кіші әріппен («Вызвать
/// такси»): «Вызвать Такси» деп тұрса қате көрінетін.
String vehicleCallLabel(VehicleType v) {
  final ru = Lang.current.value == AppLang.ru;
  final name = (ru && v == VehicleType.taxi) ? 'такси' : v.label;
  return ru ? 'Вызвать $name' : '$name шақыру';
}

/// Көлік түрінің иконкасы. Үш дереккөз — осы КЕЗЕКПЕН:
///   1. модератор жүктеген сурет ([VehicleTypeX.iconUrl], 0050) —
///      кірістірілген суреттен де БАСЫМ, себебі оны модератор әдейі қойған;
///   2. қосымшамен бірге келген PNG (`assets/vehicles/<code>.png`);
///   3. эмодзи (суреті жоқ түрлерге: газель, фургон, трактор…).
/// Үшеуі де ДӘЛ БІРДЕЙ [size]×[size] қораптың ортасында — көрінетін өлшемі
/// бірдей болады. Сурет түрлі-түсті болғандықтан [color] тек эмодзиге әсер
/// етпейді — параметр басқа шақыру орындарымен үйлесімділік үшін қалдырылған.
///
/// Желі суреті жүктелмей қалса (интернет жоқ, сілтеме бұзылған) — үнсіз
/// кірістірілген PNG-ге, ол да жоқ болса эмодзиге қайтады: карусель
/// ЕШҚАШАН бос шаршы көрсетпейді.
Widget vehicleIcon(VehicleType v, {double size = 24, Color? color}) {
  final url = v.iconUrl;
  final png = v.pngAsset;

  Widget fallback() => png != null
      ? Image.asset(png, width: size, height: size, fit: BoxFit.contain)
      : Text(v.emoji, style: TextStyle(fontSize: size * 0.8, height: 1));

  return SizedBox(
    width: size,
    height: size,
    child: Center(
      child: url == null
          ? fallback()
          : Image.network(
              url,
              width: size,
              height: size,
              fit: BoxFit.contain,
              // Жүктеліп жатқанда да орын БІРДЕЙ болып тұрсын (карточкалар
              // «секірмеуі» үшін) — сол себепті әдепкі суретті көрсетеміз.
              loadingBuilder: (_, child, progress) =>
                  progress == null ? child : fallback(),
              errorBuilder: (_, _, _) => fallback(),
            ),
    ),
  );
}

/// Көлік түрін таңдау каруселі (indriver стилі): көлденең айналатын
/// шаршы карточкалар — иконка (PNG не эмодзи, бәрі бірдей өлшемде) + атауы.
/// Таңдалғаны қара фонда сары жиекпен ерекшеленеді. Атауы FittedBox арқылы
/// карточкаға ӘРҚАШАН сыяды — «…» болып қиылмайды, екінші жолға түспейді,
/// жүйе шрифті үлкейтілсе де (accessibility text scale) рамкадан аспайды.
///
/// [types] — көрсетілетін түрлер тізімі. Әдепкі — [kCargoVehicleTypes]
/// (таксиден басқасының бәрі): такси бөлек «Такси» санатында тұрады және
/// модератор қоспайынша мүлдем көрінбейді.
class VehicleTypeCarousel extends StatefulWidget {
  final VehicleType selected;
  final ValueChanged<VehicleType> onChanged;
  final List<VehicleType>? types;

  /// Карточка биіктігі — картаның орнын бекер жемеу үшін ЫҚШАМ (клиенттің
  /// басты бетінде панель картаны ысырады, әр пиксель маңызды).
  static const cardHeight = 62.0;

  const VehicleTypeCarousel({
    super.key,
    required this.selected,
    required this.onChanged,
    this.types,
  });

  @override
  State<VehicleTypeCarousel> createState() => _VehicleTypeCarouselState();
}

class _VehicleTypeCarouselState extends State<VehicleTypeCarousel> {
  static const _cardW = 74.0;
  static const _cardH = VehicleTypeCarousel.cardHeight;
  static const _gap = 7.0;

  /// Таңдалған түр тізімде болмаса (мыс. орындаушы такси таңдап қойған, ал
  /// модератор кейін такси бөлімін өшірген) — оны басына қосамыз: таңдау
  /// «жоғалып», карусель бос орында тұрып қалмайды.
  List<VehicleType> get _types {
    final base = widget.types ?? kCargoVehicleTypes;
    if (base.contains(widget.selected)) return base;
    return [widget.selected, ...base];
  }

  late final ScrollController _scroll = ScrollController(
    // ашылғанда таңдалған түр көрініп тұрсын
    initialScrollOffset: (_types.indexOf(widget.selected) * (_cardW + _gap))
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
    // Каталог серверден жаңарғанда (модератор түр қосты/өшірді/ретін
    // ауыстырды) карусель ӨЗІН қайта салады — қосымшаны қайта ашудың
    // қажеті жоқ (0050).
    return ValueListenableBuilder<int>(
      valueListenable: VehicleCatalog.revision,
      builder: (_, _, _) => _body(),
    );
  }

  Widget _body() {
    final desc = widget.selected.description;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _carousel(),
        // Таңдалған көлік түрінің қысқа түсініктемесі (мыс. «Ауыр жүк»).
        // ТҰРАҚТЫ БИІКТІК (16px, бір жол): түсініктеме ұзын түрге ауысқанда
        // панель «секіріп» биіктемейді, демек карта да жылжып кетпейді.
        if (desc.isNotEmpty) ...[
          const SizedBox(height: 6),
          SizedBox(
            height: 16,
            child: Row(
              children: [
                const Icon(Icons.info_outline,
                    size: 14, color: Gz.textSecondary),
                const SizedBox(width: 5),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      desc,
                      maxLines: 1,
                      softWrap: false,
                      style: const TextStyle(
                        color: Gz.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _carousel() {
    final types = _types;
    return SizedBox(
      height: _cardH,
      child: ListView.separated(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        itemCount: types.length,
        separatorBuilder: (_, i) => const SizedBox(width: _gap),
        itemBuilder: (_, i) {
          final v = types[i];
          final sel = v == widget.selected;
          final fg = sel ? Colors.white : Gz.ink;
          return GestureDetector(
            onTap: () => widget.onChanged(v),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: _cardW,
              height: _cardH,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
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
                  vehicleIcon(v, size: 25, color: fg),
                  const SizedBox(height: 4),
                  // FittedBox: атау рамкаға сыймаса — кішірейеді (қиылмайды,
                  // екінші жолға түспейді). Тұрақты өлшемді box (ені + биіктігі)
                  // жүйе шрифті масштабы үлкейгенде де асып кетуді болдырмайды.
                  SizedBox(
                    width: double.infinity,
                    height: 13,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        v.label,
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          fontSize: 10.5,
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

/// Клиенттің қызмет САНАТЫ (0046) — «Такси» бөлімі қосулы кезде ғана
/// көрінеді. Екі ықшам плитка:
///   • Такси — оң жақ төбесінде «ЖАҢА» белгісі бар;
///   • Спецтехника — басқанда астында көлік түрлерінің каруселі ашылады.
/// Модератор такси бөлімін өшірсе бұл виджет мүлдем салынбайды, экран
/// баяғыдай (жалғыз карусель) болып қалады.
enum VehicleCategory { taxi, cargo }

class VehicleCategoryTabs extends StatelessWidget {
  final VehicleCategory selected;
  final ValueChanged<VehicleCategory> onChanged;

  /// Плитканың биіктігі — ЫҚШАМ (52): бұл блок клиенттің басты бетінде
  /// картаның орнын жейді, сол себепті мүмкіндігінше аласа. Екеуінде де
  /// ҚАТАҢ бірдей, демек бір плитка көршісінен биік болып қалмайды.
  static const tileHeight = 52.0;

  const VehicleCategoryTabs({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _tile(
            active: selected == VehicleCategory.taxi,
            emoji: '🚕',
            label: t('Такси'),
            badge: t('ЖАҢА'),
            onTap: () => onChanged(VehicleCategory.taxi),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _tile(
            active: selected == VehicleCategory.cargo,
            emoji: '🚚',
            // ҚЫСҚА атау ӘДЕЙІ: «Жүк · Спецтехника» деген ұзын жазу
            // орысшада плиткаға сыймай, FittedBox оны кішірейтетін де,
            // көршісіндегі «Такси» толық өлшемде тұрып, ЕКІ ПЛИТКАНЫҢ
            // ШРИФТІ ӘРТҮРЛІ болып көрінетін. Қысқа атаумен екеуі де
            // толық өлшемінде сыяды → шрифт бірдей.
            label: t('Спецтехника'),
            onTap: () => onChanged(VehicleCategory.cargo),
          ),
        ),
      ],
    );
  }

  /// Санат плиткасы: иконка мен жазу БІР ҚАТАРДА (аласа болуы үшін).
  /// Атаулар қысқа болғандықтан екеуі де толық өлшемінде сыяды.
  Widget _tile({
    required bool active,
    required String emoji,
    required String label,
    required VoidCallback onTap,
    String? badge,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: tileHeight,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          color: active ? Gz.ink : Gz.bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active ? Gz.yellow : Gz.border,
            width: active ? 2 : 1.2,
          ),
        ),
        // Белгі («ЖАҢА») плитканың оң жақ ТӨБЕСІНДЕ, мазмұнның үстінде
        // қалқып тұрады — сол себепті мәтінге орын алмайды.
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 19, height: 1)),
                  const SizedBox(width: 7),
                  // Тұрақты биіктікті box + FittedBox: жүйе шрифті
                  // үлкейтілсе де жазу рамкадан аспайды, қиылмайды.
                  Flexible(
                    child: SizedBox(
                      height: 16,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          label,
                          maxLines: 1,
                          softWrap: false,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: active ? Colors.white : Gz.ink,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (badge != null)
              Positioned(
                top: -8,
                right: -4,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: Gz.yellow,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Gz.surface, width: 1.5),
                  ),
                  child: Text(
                    badge,
                    style: const TextStyle(
                      fontSize: 8.5,
                      height: 1.2,
                      fontWeight: FontWeight.w900,
                      color: Gz.ink,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
