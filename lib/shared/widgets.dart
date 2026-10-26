import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../core/app_theme.dart';
import '../core/lang.dart';
import '../core/models.dart';
import '../core/push.dart';
import '../core/repo.dart';
import '../core/theme.dart';
import 'map_widgets.dart';
import 'ui/dialogs.dart';
import 'ui/sheet.dart';
import 'ui/bits.dart';
import 'ui/review_tags.dart';
import 'vehicle_picker.dart';

// Бірыңғай дизайн-жүйенің компоненттері (баннер, терезе, диалог, тег,
// көрсеткіш…). Экрандар тек `widgets.dart`-ты импорттайды — бәрі осы жерден
// қолжетімді болады.
export 'ui/bar_chart.dart';
export 'ui/bits.dart';
export 'ui/contact.dart';
export 'ui/dialogs.dart';
export 'ui/notice.dart';
export 'ui/review_tags.dart';
export 'ui/sheet.dart';

/// Батырма мәтіні: ені жетпесе — ЕКІНШІ ЖОЛҒА ТҮСПЕЙДІ, кішірейіп сыяды.
///
/// Орыс тіліндегі мәтіндер қазақшадан ұзын («Қабылдамау» → «Отклонить»,
/// «Келісу · 5 855 ₸» → «Согласиться · 5 855 ₸»), сол себепті тар
/// батырмаларда мәтін екі жолға сынып, төменгі бөлігі қиылып көрінбей
/// қалатын (Android-та әсіресе). [FittedBox] `scaleDown` мәтінді тек қажет
/// болғанда кішірейтеді — сыйып тұрса, өлшемі өзгермейді.
class BtnLabel extends StatelessWidget {
  final String text;
  final TextStyle? style;
  const BtnLabel(this.text, {super.key, this.style});

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    child: Text(
      text,
      style: style,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
    ),
  );
}

/// Басылғанда сәл КІШІРЕЙЕТІН қаптама — «тірі» батырма әсері.
///
/// Material-дың әдепкі ripple-і жалғыз кері байланыс болатын: сары батырмада
/// ол әрең көрінеді. Масштаб анимациясы кез келген түсте, кез келген
/// платформада (web-те де) бірдей сезіледі. [Listener] қолданылады —
/// GestureDetector-ден бөлек, ол баланың өз басу оқиғасын ҰРЛАМАЙДЫ.
class PressScale extends StatefulWidget {
  final Widget child;
  final double scale;

  /// false болса — анимация мүлдем жүрмейді (өшірулі батырма «басылып»
  /// тұрғандай көрінбеуі керек).
  final bool enabled;

  const PressScale({
    super.key,
    required this.child,
    this.scale = 0.97,
    this.enabled = true,
  });

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  void _set(bool v) {
    if (!widget.enabled || _down == v) return;
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down && widget.enabled ? widget.scale : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Async-әрекеті бар батырма: басқанда spinner көрсетеді.
class BusyButton extends StatefulWidget {
  final String label;
  final Future<void> Function() onPressed;
  final bool outlined;
  final Color? color;
  final IconData? icon;

  /// false болса — батырма сұр әрі басылмайтын күйде (мыс. алдын ала бір
  /// шарт орындалмаса). Дефолт — қосулы.
  final bool enabled;

  const BusyButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.outlined = false,
    this.color,
    this.icon,
    this.enabled = true,
  });

  @override
  State<BusyButton> createState() => _BusyButtonState();
}

class _BusyButtonState extends State<BusyButton> {
  bool _busy = false;

  Future<void> _run() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onPressed();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Spinner батырманың МӘТІН ТҮСІМЕН: түрлі-түсті (қызыл/жасыл) батырмада
    // жазу ақ болады, ал spinner бұрын әрқашан қара еді — қызыл фонда
    // көмескі көрінетін.
    final spinnerColor = widget.outlined
        ? Gz.ink
        : (widget.color == null ? Gz.onBrand : Colors.white);
    final child = _busy
        ? SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: spinnerColor,
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 20),
                const SizedBox(width: 9),
              ],
              // Ұзын мәтін (әсіресе орысша) екінші жолға сынып қиылмауы
              // үшін — қажет болса кішірейеді.
              Flexible(child: BtnLabel(widget.label)),
            ],
          );
    final active = widget.enabled && !_busy;
    // Күй ауысқанда (жазу ↔ spinner) батырма іші «секіріп» алмасын.
    final animated = AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: KeyedSubtree(key: ValueKey(_busy), child: child),
    );
    if (widget.outlined) {
      return PressScale(
        enabled: active,
        child: OutlinedButton(onPressed: active ? _run : null, child: animated),
      );
    }
    return PressScale(
      enabled: active,
      child: FilledButton(
        onPressed: active ? _run : null,
        style: widget.color == null
            ? null
            : FilledButton.styleFrom(
                backgroundColor: widget.color,
                foregroundColor: Colors.white,
                // Көлеңке де батырманың өз түсімен жарқырайды.
                shadowColor: widget.color!.withValues(alpha: 0.5),
              ),
        child: animated,
      ),
    );
  }
}

/// БАСТЫ әрекет батырмасы — градиентті әрі өз түсімен жарқырайтын нұсқа.
///
/// Жалаң [FilledButton] бүкіл қосымшада негізгі батырма болып қала береді;
/// бұл — экранның БІР ғана шешуші әрекетіне («Шақыру», «Заказ жариялау»)
/// арналған: градиент + жылы сәуле оны басқа батырмалардан бөліп тұрады.
class GzPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double height;

  const GzPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.height = 54,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return PressScale(
      enabled: enabled,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: height,
        decoration: BoxDecoration(
          gradient: enabled ? Gz.brandGradient : null,
          color: enabled ? null : Gz.disabledBg,
          borderRadius: BorderRadius.circular(16),
          boxShadow: enabled ? Gz.glow(Gz.yellow, alpha: 0.45) : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onPressed,
            splashColor: Gz.onBrand.withValues(alpha: 0.10),
            highlightColor: Gz.onBrand.withValues(alpha: 0.06),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(
                      icon,
                      size: 20,
                      color: enabled ? Gz.onBrand : Gz.disabledFg,
                    ),
                    const SizedBox(width: 9),
                  ],
                  Flexible(
                    child: BtnLabel(
                      label,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.1,
                        color: enabled ? Gz.onBrand : Gz.disabledFg,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Растау белгісі — Material [Checkbox] орнына. Дефолт Checkbox таңдалғанда
/// ҚАРА ШАРШЫ болып көрінетін (әсіресе Android-та), қолданушылар оны
/// «галочка қойылмады» деп ойлайтын. Мұнда белгі — АЙҚЫН ЖАСЫЛ ДӨҢГЕЛЕК
/// ішіндегі ақ құсбелгі, ал бос күйі — жай ғана сұр контур.
class ConfirmCheck extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final Widget label;

  /// Белгі автоматты қойылған болса — «есте сақталды» деген жұмсақ белгі.
  final bool auto;

  const ConfirmCheck({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
    this.auto = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutBack,
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: value ? Gz.greenBright : Gz.surfaceAlt,
                shape: BoxShape.circle,
                border: Border.all(
                  color: value ? Gz.greenBright : Gz.border,
                  width: 1.8,
                ),
                // Белгі қойылғанда жасыл дөңгелек жеңіл жарқырайды —
                // «қабылданды» деген сезім күшейеді.
                boxShadow: value
                    ? Gz.glow(Gz.greenBright, alpha: 0.35, blur: 10)
                    : null,
              ),
              child: Icon(
                Icons.check_rounded,
                size: 17,
                color: value ? Colors.white : Colors.transparent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  label,
                  if (value && auto) ...[
                    const SizedBox(height: 3),
                    Text(
                      t('Автоматты қойылды — қаласаңыз алып тастаңыз'),
                      style: TextStyle(fontSize: 11, color: Gz.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Тізімдегі маршрут нүктесінің белгісі — КАРТАДАҒЫ ПИНДЕРМЕН БІР ТІЛДЕ:
///   • алу нүктесі  → жасыл НЫСАНА (ақ сақина + ақ өзек);
///   • аралық аялдама → нөмірленген КҮЛГІН тамшы;
///   • ақырғы нүкте  → ішінде ақ шаршысы бар ҚЫЗЫЛ тамшы.
///
/// Бұрын тізім мен карта ЕКІ БӨЛЕК тілде сөйлейтін (тізімде шахмат туы —
/// картада жалаң материал иконкасы), сол себепті клиент тізімдегі «2» мен
/// картадағы белгіні байланыстыра алмайтын. Енді екеуі де бір [MapPin]:
/// түс те, ақ контур да, көлеңке де дәл бірдей.
///
/// ӨЛШЕМ: [size] — белгінің ЕНІ (тамшы үшін басының диаметрі, жалпы
/// биіктігі ≈1.21·size). Тізім слоттары 20–22 px, сол себепті әдепкі 18.
class RoutePointMark extends StatelessWidget {
  /// null болса — АЛУ нүктесі. 1-ден басталатын сан болса — аралық аялдама.
  final int? number;

  /// true болса — маршруттың АҚЫРҒЫ нүктесі (финиш).
  final bool finish;
  final double size;

  const RoutePointMark({
    super.key,
    this.number,
    this.finish = false,
    this.size = 18,
  });

  /// Алу нүктесі.
  const RoutePointMark.origin({super.key, this.size = 18})
    : number = null,
      finish = false;

  /// Ақырғы нүкте (финиш).
  const RoutePointMark.finish({super.key, this.size = 18})
    : number = null,
      finish = true;

  /// Аралық аялдама — 1-ден басталатын нөмірмен.
  const RoutePointMark.stop(this.number, {super.key, this.size = 18})
    : finish = false;

  @override
  Widget build(BuildContext context) {
    if (finish) return MapPin.destination(size: size, color: Gz.red);
    if (number != null) {
      return MapPin.stop(number, size: size, color: Gz.violet);
    }
    return MapPin.origin(size: size, color: Gz.green);
  }
}

/// «Мекенжай қосу» батырмасы — ЫҚШАМ ПИЛЮЛЯ.
///
/// Бұрын жалаң `TextButton.icon` («+ Мекенжай қосу») тұратын: жиекі жоқ
/// болғандықтан батырма екені білінбейтін де, адрес жолдарының астында
/// «қалып қалған мәтін» болып көрінетін. Енді:
///   • нақты жиегі бар пилюля — басуға болатыны бірден оқылады;
///   • иконка `add_location_alt` — «мекенжай» екені мағынасынан көрінеді
///     (жалаң «+» неге қосылатынын айтпайтын);
///   • мазмұнға сай ені (`MainAxisSize.min`), сол жақта тұрады.
class AddAddressButton extends StatelessWidget {
  final VoidCallback onPressed;
  final String? label;
  const AddAddressButton({super.key, required this.onPressed, this.label});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: PressScale(
        child: Material(
          color: Gz.yellow.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 13, 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Gz.yellow, width: 1.4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // «+» белгісі толтырылған сары дөңгелекте — түйменің
                  // «қосу» әрекеті екені сөзді оқымай-ақ түсінікті.
                  Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: Gz.yellow,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.add_rounded, size: 15, color: Gz.onBrand),
                  ),
                  const SizedBox(width: 7),
                  BtnLabel(
                    label ?? t('Мекенжай қосу'),
                    style: TextStyle(
                      fontSize: 13,
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
      ),
    );
  }
}

/// [RouteFieldsCard] ішіндегі бір жол.
class RouteField {
  /// Сол жақтағы белгі — [RoutePointMark] (алу / финиш).
  final Widget mark;

  /// Үстіндегі кішкене сұр белгі: «Қайдан» / «Қайда».
  final String label;
  final String text;

  /// Мәтін әлі таңдалмаған (placeholder) — солғын.
  final bool dim;
  final VoidCallback? onTap;
  final Widget? trailing;

  const RouteField({
    required this.mark,
    required this.label,
    required this.text,
    this.dim = false,
    this.onTap,
    this.trailing,
  });
}

/// Маршрут өрістері БІР карточкада (Яндекс Go үлгісі): әр жолдың үстінде
/// кішкене сұр белгі («Қайдан» / «Қайда»), астында мекенжай, жолдар арасы
/// жіңішке сызық. Бұрын екі бөлек өріс болатын — қайсысы қайдан, қайсысы
/// қайда екені тек түсті нүктеден ғана білінетін.
class RouteFieldsCard extends StatelessWidget {
  final List<RouteField> fields;
  const RouteFieldsCard({super.key, required this.fields});

  static const _r = Radius.circular(16);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Gz.surfaceAlt,
        borderRadius: const BorderRadius.all(_r),
        border: Border.all(color: Gz.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < fields.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 46, endIndent: 12),
            _row(fields[i], first: i == 0, last: i == fields.length - 1),
          ],
        ],
      ),
    );
  }

  Widget _row(RouteField f, {required bool first, required bool last}) {
    return InkWell(
      onTap: f.onTap,
      borderRadius: BorderRadius.vertical(
        top: first ? _r : Radius.zero,
        bottom: last ? _r : Radius.zero,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(13, 9, 10, 9),
        child: Row(
          children: [
            SizedBox(width: 22, child: Center(child: f.mark)),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    f.label,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.2,
                      color: Gz.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    f.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.25,
                      letterSpacing: -0.15,
                      fontWeight: f.dim ? FontWeight.w500 : FontWeight.w700,
                      color: f.dim ? Gz.textTertiary : Gz.ink,
                    ),
                  ),
                ],
              ),
            ),
            if (f.trailing != null) ...[const SizedBox(width: 8), f.trailing!],
          ],
        ),
      ),
    );
  }
}

class SectionCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const SectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: padding, child: child),
  );
}

class StatusChip extends StatelessWidget {
  final String status;
  final VehicleType? vehicleType;
  const StatusChip(this.status, {super.key, this.vehicleType});

  Color get _color => switch (status) {
    'searching' => Gz.blue,
    'accepted' || 'arrived' || 'loading' || 'in_transit' => Gz.green,
    'completed' => Gz.ink,
    _ => Gz.red,
  };

  @override
  Widget build(BuildContext context) {
    // Түрлі-түсті НҮКТЕ + жиек: чип жалаң боялған тіктөртбұрыш емес,
    // «статус белгісі» болып оқылады әрі түсі солғын фонда да айқын.
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 5, 11, 5),
      decoration: BoxDecoration(
        color: Gz.tint(_color, 0.11),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Gz.tint(_color, 0.26)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(color: _color, shape: BoxShape.circle),
          ),
          Text(
            statusLabel(status, vehicleType: vehicleType),
            style: TextStyle(
              color: _color,
              fontWeight: FontWeight.w800,
              fontSize: 12,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}

class RatingStars extends StatelessWidget {
  final double rating;
  final int count;
  final double size;
  const RatingStars(this.rating, {super.key, this.count = -1, this.size = 16});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.star_rounded, color: Gz.star, size: size + 2),
        const SizedBox(width: 3),
        Text(
          rating <= 0 ? t('жаңа') : rating.toStringAsFixed(1),
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: size * 0.85),
        ),
        if (count >= 0) ...[
          const SizedBox(width: 3),
          Text(
            '($count)',
            style: TextStyle(color: Gz.textSecondary, fontSize: size * 0.8),
          ),
        ],
      ],
    );
  }
}

class InitialsAvatar extends StatelessWidget {
  final String name;
  final double radius;
  final String? imageUrl;
  const InitialsAvatar(this.name, {super.key, this.radius = 22, this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();
    // Суреті жоқ профиль — жалаң қара дөңгелек емес, ГРАДИЕНТТІ «түнгі
    // аспан» фоны мен сары әріптер: аватарлар тізімі әлдеқайда әрлі көрінеді.
    final fallback = Container(
      width: radius * 2,
      height: radius * 2,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        gradient: Gz.heroGradient,
        shape: BoxShape.circle,
      ),
      child: Text(
        initials.isEmpty ? '?' : initials,
        style: TextStyle(
          color: Gz.yellow,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
          fontSize: radius * 0.72,
        ),
      ),
    );
    if (imageUrl == null || imageUrl!.isEmpty) return fallback;
    final px = (radius * 2 * MediaQuery.devicePixelRatioOf(context)).round();
    return CircleAvatar(
      radius: radius,
      backgroundColor: Gz.bg,
      foregroundImage: ResizeImage(
        NetworkImage(imageUrl!),
        width: px,
        height: px,
      ),
      onForegroundImageError: (_, _) {},
      child: Text(
        initials.isEmpty ? '?' : initials,
        style: TextStyle(
          color: Gz.textSecondary,
          fontWeight: FontWeight.w800,
          fontSize: radius * 0.72,
        ),
      ),
    );
  }
}

/// Аты + рейтинг + поездка саны бар қысқа профиль жолы.
///
/// [asRole] — рейтингті ҚАЙ РӨЛ бойынша көрсету ('client' | 'executor').
/// Қос рөлде (0046) бір адамның екі бағасы бар: экрандағы контекст қай
/// рөлге қатысты болса — соны береміз (мыс. заказ бетінде клиентті
/// «клиент» ретінде көрсетеміз, ол қазір орындаушы режимінде отырса да).
/// null болса — сол адамның ағымдағы белсенді рөліндегі бағасы.
class ProfileBrief extends StatelessWidget {
  final Profile? profile;
  final double radius;
  final String? subtitle;
  final String? asRole;
  const ProfileBrief({
    super.key,
    required this.profile,
    this.radius = 20,
    this.subtitle,
    this.asRole,
  });

  @override
  Widget build(BuildContext context) {
    final p = profile;
    return Row(
      children: [
        InitialsAvatar(
          p?.fullName ?? '?',
          radius: radius,
          imageUrl: p?.avatarUrl,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                p?.fullName ?? '…',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              Row(
                children: [
                  RatingStars(
                    asRole == null
                        ? (p?.rating ?? 0)
                        : (p?.ratingAs(asRole!) ?? 0),
                    count: asRole == null
                        ? (p?.ratingCount ?? 0)
                        : (p?.ratingCountAs(asRole!) ?? 0),
                    size: 12,
                  ),
                  if ((p?.trips ?? 0) > 0) ...[
                    const SizedBox(width: 8),
                    Icon(
                      Icons.local_shipping,
                      size: 12,
                      color: Gz.textSecondary,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      '${p!.trips}',
                      style: TextStyle(fontSize: 12, color: Gz.textSecondary),
                    ),
                  ],
                ],
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: Gz.textSecondary),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Иконка ЕКІ ҚАБАТТЫ сақинада: сыртқы өте солғын, ішкі қоюлау —
            // жалаң дөңгелектен гөрі «сәуле шашып тұрған» әсер береді.
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: Gz.yellow.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Container(
                padding: const EdgeInsets.all(19),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Gz.yellowLight.withValues(alpha: 0.55),
                      Gz.yellow.withValues(alpha: 0.30),
                    ],
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 38, color: Gz.ink),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                height: 1.3,
                letterSpacing: -0.3,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 7),
              // Ені ШЕКТЕЛГЕН: ұзын сөйлем экранның шетінен шетіне
              // созылмайды — 2-3 қысқа жол болып, көзге әдемі оқылады.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Gz.textSecondary,
                    fontSize: 14,
                    height: 1.5,
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

/// Дерек шынымен бос болған және сұрау орындалмай қалған жағдайларды
/// шатастырмау үшін қолданылатын қайта жүктеу күйі. Бұл экранда қате кодын
/// көрсетпейді: техникалық мәлімет қолданушыға пайдасыз, ал әрекет түсінікті.
class LoadErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  final String? title;
  final String? subtitle;

  const LoadErrorState({
    super.key,
    required this.onRetry,
    this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Gz.tint(Gz.red, 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.cloud_off_outlined, size: 36, color: Gz.red),
            ),
            const SizedBox(height: 16),
            Text(
              title ?? t('Деректерді жүктеу мүмкін болмады'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                height: 1.3,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Text(
                subtitle ?? t('Интернетті тексеріп, қайта көріңіз.'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Gz.textSecondary,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(minimumSize: const Size(180, 48)),
              icon: const Icon(Icons.refresh_rounded),
              label: Text(t('Қайталау')),
            ),
          ],
        ),
      ),
    );
  }
}

/// A → … → B адрес бағаны.
///
/// [stops] — АРАЛЫҚ аялдамалар (0047): «Қайдан» мен «Қайда» арасында
/// күлгін нүктелермен көрсетіледі. Орындаушы маршруттың барлық нүктесін
/// БІРДЕН көруі керек — әйтпесе заказды алып, кейін «айтылмаған екінші
/// адрес» шыға келетін.
class RouteLine extends StatelessWidget {
  final String from;
  final String to;
  final List<String> stops;
  const RouteLine({
    super.key,
    required this.from,
    required this.to,
    this.stops = const [],
  });

  @override
  Widget build(BuildContext context) {
    // Атау (ҚАЙДАН / АЯЛДАМА 1 / ҚАЙДА) — БАС ӘРІППЕН әрі әріп аралығы
    // кеңейтілген микро-жазу. Ол мекенжайдың өзімен ешқашан шатаспайды:
    // көз алдымен қою мекенжайды оқиды, атау «белгі» болып фонда қалады.
    Widget row(Widget lead, String label, String text) => Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(width: 20, child: Center(child: lead)),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label.toUpperCase(), style: Gz.label),
              const SizedBox(height: 1),
              Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    // Нүктелерді жалғайтын сызық — жоғарыдан төмен солғындайды: маршрут
    // «ағып» бара жатқандай көрінеді.
    Widget connector() => Padding(
      padding: const EdgeInsets.only(left: 9),
      child: Container(
        width: 2,
        height: 16,
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
    // Аялдамалар НӨМІРЛЕНЕДІ (1, 2 …), ақырғы нүкте — ФИНИШ ТУЫ. Осылайша
    // маршрут «қайдан → 1 → 2 → финиш» болып оқылады.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row(const RoutePointMark.origin(), t('Қайдан'), from),
        for (var i = 0; i < stops.length; i++) ...[
          connector(),
          row(RoutePointMark.stop(i + 1), '${t('Аялдама')} ${i + 1}', stops[i]),
        ],
        connector(),
        row(
          const RoutePointMark.finish(),
          stops.isEmpty ? t('Қайда') : t('Соңғы нүкте'),
          to,
        ),
      ],
    );
  }
}

/// Заказ карточкасы (лента мен тізімдерге ортақ).
class OrderCard extends StatelessWidget {
  final Order order;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Widget? footer;
  final bool showMap;

  /// Тарих тізімдерінде — уақыттың орнына толық КҮНІ (бүгінгі заказда
  /// сағат жеткілікті, ал тарихта «қай күні?» деген сұрақ маңызды).
  final bool showDate;

  const OrderCard({
    super.key,
    required this.order,
    this.onTap,
    this.trailing,
    this.footer,
    this.showMap = false,
    this.showDate = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(Gz.radius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    // Баға — карточкадағы ЕҢ САЛМАҚТЫ элемент: орындаушы
                    // лентаны сол сан бойынша шолады.
                    child: Text(fmtT(order.displayPrice), style: Gz.money),
                  ),
                  const SizedBox(width: 8),
                  trailing ??
                      StatusChip(order.status, vehicleType: order.vehicleType),
                ],
              ),
              const SizedBox(height: 12),
              RouteLine(
                from: order.fromDisplay,
                to: order.toDisplay,
                stops: order.stops.map((s) => s.display).toList(),
              ),
              if (showMap) ...[
                const SizedBox(height: 10),
                RouteMap(
                  from: LatLng(order.fromLat, order.fromLng),
                  to: LatLng(order.toLat, order.toLng),
                  stops: order.stops.map((s) => LatLng(s.lat, s.lng)).toList(),
                  height: 104,
                  // Тізім ішіндегі карточкада картаны түрту заказдың ӨЗ
                  // бетін ашуы керек — толық экранды карта емес (әйтпесе
                  // карточканы басу орны екіге бөлініп, шатастырады).
                  expandable: false,
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  InfoChip(
                    text: order.vehicleType.label,
                    leading: vehicleIcon(
                      order.vehicleType,
                      size: 14,
                      color: Gz.textSecondary,
                    ),
                  ),
                  // Аралық аялдама бар заказ (0047) — орындаушы оны БІРДЕН
                  // көруі керек: маршрут ұзағырақ, жұмыс та көбірек.
                  if (order.hasStops)
                    InfoChip(
                      icon: Icons.adjust,
                      text: '+${order.stops.length} ${t('аялдама')}',
                      color: Gz.accent,
                    ),
                  if (order.fromCity != null && order.toCity != null)
                    InfoChip(
                      icon: order.intercity
                          ? Icons.alt_route
                          : Icons.location_city_outlined,
                      text: order.intercity ? t('Межгород') : t('Қала ішінде'),
                      color: order.intercity ? Gz.accent : null,
                    ),
                  if (order.distanceKm > 0)
                    InfoChip(
                      icon: Icons.route,
                      text: '${order.distanceKm.toStringAsFixed(1)} км',
                    ),
                  // Қосымша талаптар (0077) — орындаушы лентада бірден
                  // көреді: тиеуші керек пе, қай қабат, лифт бар ма.
                  if (order.loaders > 0)
                    InfoChip(
                      icon: Icons.groups_rounded,
                      text: '${order.loaders} ${t('тиеуші')}',
                      color: Gz.violet,
                    ),
                  if (order.floorFrom != null || order.floorTo != null)
                    InfoChip(
                      icon: Icons.stairs_rounded,
                      text:
                          '${order.floorFrom ?? '—'} → '
                          '${order.floorTo ?? '—'} ${t('қабат')}'
                          '${order.hasElevator == true ? ' · ${t('лифт')}' : ''}',
                      color: Gz.blue,
                    ),
                  if (order.createdAt != null && trailing == null)
                    InfoChip(
                      icon: showDate ? Icons.event_outlined : Icons.schedule,
                      text: showDate
                          ? fmtDate(order.createdAt)
                          : fmtTime(order.createdAt),
                    ),
                ],
              ),
              if (order.cargoDesc.isNotEmpty) ...[
                const SizedBox(height: 9),
                Text(
                  order.cargoDesc,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Gz.textSecondary,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ],
              if (footer != null) ...[const SizedBox(height: 12), footer!],
            ],
          ),
        ),
      ),
    );
  }
}

/// Белсенді заказ(дар) баннері — клиентте де, орындаушыда да БІР үлгі.
///
/// Бұрын клиентте қара-көк «қалқыма», орындаушыда экранның түбіндегі жасыл
/// жолақ болатын — бір мағынадағы элемент екі түрлі көрінетін. Енді екеуі
/// де: қою hero-градиент, сары иконка-шайба, күйі + маршруты, бірнеше
/// заказ болса «+N» белгісі.
class ActiveOrderBanner extends StatelessWidget {
  final List<Order> orders;
  final VoidCallback onTap;

  /// Күйдің орнына көрсетілетін тақырып (null — заказдың ағымдағы күйі).
  final String? title;

  /// Тақырыптың астындағы қосымша жол (null — «қайдан → қайда»).
  final String? subtitle;

  const ActiveOrderBanner({
    super.key,
    required this.orders,
    required this.onTap,
    this.title,
    this.subtitle,
  });

  /// Қабылданған заказда — уәде еткен келу уақытына дейін қанша минут
  /// қалды (0075): «Орындаушы жолда · ~6 мин». Кешіксе — тек күйі.
  static String? _etaTitle(Order o) {
    final by = o.arriveBy;
    if (o.status != 'accepted' || by == null) return null;
    final min = by.difference(DateTime.now()).inSeconds / 60;
    if (min <= 0) return null;
    return '${statusLabel(o.status, vehicleType: o.vehicleType)} · '
        '~${min.ceil()} ${t('мин')}';
  }

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) return const SizedBox.shrink();
    final o = orders.first;
    final etaTitle = orders.length == 1 ? _etaTitle(o) : null;
    return PressScale(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(Gz.rLg),
          onTap: onTap,
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              gradient: Gz.heroGradient,
              borderRadius: BorderRadius.circular(Gz.rLg),
              boxShadow: Gz.liftShadow,
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: Gz.brandGradient,
                    shape: BoxShape.circle,
                    boxShadow: Gz.glow(Gz.yellow, alpha: 0.35, blur: 12),
                  ),
                  child: vehicleIcon(o.vehicleType, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title ??
                            etaTitle ??
                            statusLabel(o.status, vehicleType: o.vehicleType),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          height: 1.25,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        subtitle ?? '${o.fromDisplay} → ${o.toDisplay}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                if (orders.length > 1)
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(Gz.rSm),
                    ),
                    child: Text(
                      '+${orders.length - 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                const Icon(Icons.chevron_right_rounded, color: Colors.white70),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const InfoRow(this.label, this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Атау бағаны ТҰРАҚТЫ ЕНДІ: ұзын орысша атаулар («Государственный
          // номер») бұрын екі жолға түсіп, мәні (оң жақ баған) жоғарыда
          // жалғыз қалып, жол қиқы-жиқы көрінетін. BtnLabel сыймаса
          // кішірейтеді — атау да, мәні де бір қатарда тегіс тұрады.
          SizedBox(
            width: 132,
            child: Align(
              alignment: Alignment.centerLeft,
              child: BtnLabel(
                label,
                style: TextStyle(color: Gz.textSecondary, fontSize: 14),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Мәні қоюлау әрі қара: атау (солғын) мен мәннің АРАСЫНДАҒЫ айырма
          // көзге бірден түседі — жол «екі баған» болып оқылады.
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                height: 1.4,
                color: Gz.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Заказ фотоларының жолағы (public 'orders' бакеті). Басқанда үлкейеді.
class OrderPhotosStrip extends StatelessWidget {
  final List<String> paths;
  const OrderPhotosStrip({super.key, required this.paths});

  @override
  Widget build(BuildContext context) {
    if (paths.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t('Жүк фотолары'),
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 84,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: paths.length,
            separatorBuilder: (_, i) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final url = Repo.orderPhotoUrl(paths[i]);
              return GestureDetector(
                onTap: () => showDialog(
                  context: context,
                  builder: (_) => Dialog(
                    insetPadding: const EdgeInsets.all(10),
                    child: InteractiveViewer(child: Image.network(url)),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    url,
                    width: 84,
                    height: 84,
                    fit: BoxFit.cover,
                    cacheWidth: (84 * MediaQuery.devicePixelRatioOf(context))
                        .round(),
                    cacheHeight: (84 * MediaQuery.devicePixelRatioOf(context))
                        .round(),
                    errorBuilder: (_, e, s) => Container(
                      width: 84,
                      height: 84,
                      color: Gz.bg,
                      child: Icon(Icons.broken_image, color: Gz.textSecondary),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Осы сессияда бағаланған заказдар: төменнен ашылған терезеде пікір
/// жіберілсе, экрандағы inline [ReviewPrompt] да бірден «рахмет» күйіне
/// ауысады (қайта сұрамайды).
final ValueNotifier<Set<String>> _reviewedOrders = ValueNotifier({});

/// Заказ аяқталғанда бағалау терезесін ТӨМЕННЕН ашады (bottom sheet) —
/// клиентке де, орындаушыға да бір үлгі. Бұрын бағаланған болса мүлдем
/// ашылмайды.
Future<void> maybeShowReviewDialog(
  BuildContext context, {
  required String orderId,
  required String title,
  List<ReviewTag> tags = const [],
}) async {
  if (_reviewedOrders.value.contains(orderId)) return;
  try {
    final rows = await Repo.c
        .from('reviews')
        .select('id')
        .eq('order_id', orderId)
        .eq('author_id', Repo.uid ?? '');
    if ((rows as List).isNotEmpty) return;
  } catch (_) {
    return; // тексере алмасақ — терезені ашпаймыз (inline нұсқасы қалады)
  }
  if (!context.mounted) return;
  await showGzSheet<void>(
    context,
    builder: (ctx) => ReviewPrompt(
      orderId: orderId,
      title: title,
      tags: tags,
      asSheet: true,
      onDone: () => Navigator.of(ctx).maybePop(),
    ),
  );
}

/// Пікір қалдыру блогы (клиент те, орындаушы да — екінші тарапты бағалайды).
/// [asSheet] болса — төменнен ашылатын терезенің толық дизайны, әйтпесе
/// экран ішіндегі ықшам карточка.
class ReviewPrompt extends StatefulWidget {
  final String orderId;
  final String title;
  final VoidCallback? onDone;
  final bool asSheet;

  /// Бір басумен белгіленетін тегтер (0081): 4–5 жұлдызда — «не ұнады»,
  /// 1–2-де — «не ұнамады», 3-те — екеуі де.
  final List<ReviewTag> tags;

  const ReviewPrompt({
    super.key,
    required this.orderId,
    this.title = 'Бағалаңыз',
    this.tags = const [],
    this.onDone,
    this.asSheet = false,
  });

  @override
  State<ReviewPrompt> createState() => _ReviewPromptState();
}

class _ReviewPromptState extends State<ReviewPrompt> {
  int _rating = 5;
  final _comment = TextEditingController();
  bool _done = false;
  bool _checked = false;
  final Set<String> _tags = {};

  List<ReviewTag> get _visibleTags => [
    for (final tg in widget.tags)
      if (_rating == 3 || (_rating >= 4) == tg.positive) tg,
  ];

  /// Клиент орындаушыны бағалай ма (тегтерге қарап) — иконка үшін.
  bool get _ratesExecutor => identical(widget.tags, kExecutorReviewTags);

  /// Жолаушы такси жүргізушісін бағалай ма — такси иконкасы мен сөздігі.
  bool get _ratesDriver => identical(widget.tags, kTaxiReviewTags);

  @override
  void initState() {
    super.initState();
    _reviewedOrders.addListener(_onReviewed);
    if (widget.asSheet) {
      _checked = true; // терезе ашылмас бұрын тексерілген
    } else {
      _check();
    }
  }

  void _onReviewed() {
    if (!_done && _reviewedOrders.value.contains(widget.orderId) && mounted) {
      setState(() => _done = true);
    }
  }

  Future<void> _check() async {
    if (_reviewedOrders.value.contains(widget.orderId)) {
      setState(() {
        _done = true;
        _checked = true;
      });
      return;
    }
    try {
      final rows = await Repo.c
          .from('reviews')
          .select('id')
          .eq('order_id', widget.orderId)
          .eq('author_id', Repo.uid ?? '');
      if (mounted) {
        setState(() {
          _done = (rows as List).isNotEmpty;
          _checked = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _checked = true);
    }
  }

  @override
  void dispose() {
    _reviewedOrders.removeListener(_onReviewed);
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    try {
      // Жұлдыз ауысқанда жасырылып қалған тегтер жіберілмейді.
      final visible = {for (final tg in _visibleTags) tg.code};
      await Repo.submitReview(
        widget.orderId,
        _rating,
        _comment.text,
        tags: [
          for (final c in _tags)
            if (visible.contains(c)) c,
        ].take(6).toList(),
      );
      _reviewedOrders.value = {..._reviewedOrders.value, widget.orderId};
      if (mounted) setState(() => _done = true);
      if (mounted) showSnack(context, t('Пікіріңіз үшін рахмет!'));
      widget.onDone?.call();
    } catch (e) {
      if (mounted) showSnack(context, errText(e), error: true);
    }
  }

  static const _labels = ['Өте нашар', 'Нашар', 'Орташа', 'Жақсы', 'Керемет!'];

  /// Бағаның «көңіл-күй» түсі: 1–2 — қызыл, 3 — сары, 4–5 — жасыл.
  Color get _moodColor =>
      _rating <= 2 ? Gz.danger : (_rating == 3 ? Gz.warning : Gz.success);

  Widget _stars({double size = 34}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 1; i <= 5; i++)
          Semantics(
            button: true,
            label: '$i',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _rating = i),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: AnimatedScale(
                  duration: const Duration(milliseconds: 160),
                  scale: i == _rating ? 1.15 : 1,
                  child: Icon(
                    i <= _rating
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    size: size,
                    color: i <= _rating ? Gz.star : Gz.disabledFg,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _tagsBlock({bool center = false}) {
    if (_visibleTags.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: center
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Text(
          _rating >= 4
              ? t('Не ұнады?')
              : (_rating <= 2 ? t('Не ұнамады?') : t('Қысқаша айтыңыз')),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Gz.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: center ? WrapAlignment.center : WrapAlignment.start,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final tg in _visibleTags)
              GzPickChip(
                label: t(tg.label),
                icon: tg.icon,
                tone: tg.positive ? Gz.success : Gz.danger,
                selected: _tags.contains(tg.code),
                onTap: () => setState(
                  () => _tags.contains(tg.code)
                      ? _tags.remove(tg.code)
                      : _tags.add(tg.code),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _commentField() => TextField(
    controller: _comment,
    minLines: 1,
    maxLines: 3,
    maxLength: 500,
    textCapitalization: TextCapitalization.sentences,
    decoration: InputDecoration(
      hintText: t('Пікір жазыңыз (міндетті емес)'),
      counterText: '',
      prefixIcon: const Icon(Icons.edit_note_rounded),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (!_checked) return const SizedBox.shrink();
    if (widget.asSheet) return _sheet();
    if (_done) {
      return SectionCard(
        child: Row(
          children: [
            Icon(Icons.check_circle, color: Gz.green),
            const SizedBox(width: 10),
            Expanded(child: Text(t('Пікіріңіз үшін рахмет!'))),
          ],
        ),
      );
    }
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            t(widget.title),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 8),
          _stars(),
          const SizedBox(height: 4),
          Text(
            t(_labels[_rating - 1]),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: _moodColor,
            ),
          ),
          const SizedBox(height: 12),
          _tagsBlock(),
          if (_visibleTags.isNotEmpty) const SizedBox(height: 12),
          _commentField(),
          const SizedBox(height: 12),
          BusyButton(label: t('Жіберу'), onPressed: _submit),
        ],
      ),
    );
  }

  /// Төменнен ашылатын терезенің толық дизайны.
  Widget _sheet() {
    return GzSheetBody(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 6),
            Center(
              child: Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Gz.tint(Gz.yellow, 0.22),
                  border: Border.all(color: Gz.yellow, width: 2),
                ),
                child: Icon(
                  _ratesDriver
                      ? Icons.local_taxi_rounded
                      : _ratesExecutor
                      ? Icons.local_shipping_rounded
                      : Icons.person_rounded,
                  size: 32,
                  color: Gz.ink,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              t(widget.title),
              textAlign: TextAlign.center,
              style: Gz.h2.copyWith(color: Gz.ink),
            ),
            const SizedBox(height: 4),
            Text(
              t(
                _ratesDriver
                    ? 'Сапар аяқталды. Бағаңыз сервисті жақсартуға көмектеседі.'
                    : 'Заказ аяқталды. Бағаңыз сервисті жақсартуға көмектеседі.',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Gz.textSecondary),
            ),
            const SizedBox(height: 16),
            _stars(size: 44),
            const SizedBox(height: 6),
            Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Gz.tint(_moodColor, 0.14),
                  borderRadius: BorderRadius.circular(Gz.rSm),
                ),
                child: Text(
                  t(_labels[_rating - 1]),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: _moodColor,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              alignment: Alignment.topCenter,
              child: _tagsBlock(center: true),
            ),
            if (_visibleTags.isNotEmpty) const SizedBox(height: 16),
            _commentField(),
            const SizedBox(height: 16),
            BusyButton(
              label: t('Жіберу'),
              icon: Icons.send_rounded,
              onPressed: _submit,
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              style: TextButton.styleFrom(foregroundColor: Gz.textSecondary),
              child: Text(t('Кейінірек')),
            ),
          ],
        ),
      ),
    );
  }
}

/// Үлкен hero-логотип (кіру/сплэш экрандарына): мөлдір фондағы сары
/// логотип-пин + «Tasu» атауы.
class GazelGoHero extends StatelessWidget {
  final String? subtitle;
  const GazelGoHero({super.key, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Логотип-пин МӨЛДІР фонда — беттің ақ фонымен бірігіп, тек сары
        // тамшы мен «T» көрінеді (айналасында шаршы да, жарқыл да жоқ).
        Image.asset(
          'assets/icon/tasu_logo.png',
          height: 112,
          width: 112 * 826 / 1013,
          filterQuality: FilterQuality.medium,
        ),
        const SizedBox(height: 12),
        Text(
          'Tasu',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.6,
            color: Gz.ink,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 18),
          // Ені шектеулі — слоган экранның екі шетіне созылмай, ортада
          // теңгерімді екі жол болып тұрады.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Gz.textSecondary,
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Растаумен шығу: диалог көрсетеді, келіссе — экран стегін түбірге дейін
/// тазалап (әйтпесе үстінде тұрған push-телген экрандар көрінуін жалғастыра
/// береді, өйткені AuthGate тек өз route-ы ішінде қайта құрылады), содан
/// соң нақты signOut жасайды. Барлық «Шығу» батырмалары осыны қолдануы керек.
Future<void> confirmSignOut(BuildContext context) async {
  final ok = await confirmDialog(
    context,
    title: t('Шығасыз ба?'),
    message: t('Аккаунттан шығуға сенімдісіз бе?'),
    confirmLabel: t('Шығу'),
    confirmColor: Gz.red,
    icon: Icons.logout_outlined,
  );
  if (!ok || !context.mounted) return;
  Navigator.of(context).popUntil((r) => r.isFirst);
  // Push-токенді АЛДЫМЕН өшіреміз (әлі сессия бар — RPC өтеді): әйтпесе
  // құрылғы шыққан пайдаланушының хабарландыруларын ала береді, ал басқа
  // аккаунтпен кіргенде «бөтен» push келеді.
  await Push.clearToken();
  await Repo.signOut();
}

/// «Күдікті жағдай туралы хабарлау» — заказ экрандарында (клиент те,
/// орындаушы да). Хабарлама модератордың қолдау чатына дереу түседі
/// (report_order RPC). Заказды бас тартумен шатастырмау керек — бұл тек
/// ескерту, заказдың күйіне әсер етпейді. Мәтін ӘДЕЙІ жүкке қатысты емес —
/// такси (жолаушы тасымалы) заказдарында да дәл осы батырма қолданылады.
class ReportSuspiciousButton extends StatelessWidget {
  final String orderId;
  const ReportSuspiciousButton({super.key, required this.orderId});

  Future<void> _report(BuildContext context) async {
    final reason = await gzInputDialog(
      context,
      icon: Icons.report_outlined,
      confirmColor: Gz.red,
      title: t('Күдікті жағдай туралы хабарлау'),
      message: t(
        'Хабарлама дереу модераторға жіберіледі. Бұл заказды бас '
        'тартумен шатастырмаңыз — заказдың күйі өзгермейді.',
      ),
      hint: t('Не күдікті көрдіңіз? (міндетті емес)'),
      confirmLabel: t('Хабарлау'),
    );
    if (reason == null || !context.mounted) return;
    try {
      await Repo.reportOrder(orderId, reason);
      if (context.mounted) {
        showSnack(context, t('Хабарлама модераторға жіберілді'));
      }
    } catch (e) {
      if (context.mounted) showSnack(context, errText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(Icons.report_outlined, color: Gz.red),
        title: Text(
          t('Күдікті жағдай туралы хабарлау'),
          style: TextStyle(fontWeight: FontWeight.w700, color: Gz.red),
        ),
        subtitle: Text(t('Заңсыз/қауіпті жағдайға күдіктенсеңіз')),
        onTap: () => _report(context),
      ),
    );
  }
}

/// Тіл ауыстырғыш (ҚАЗ/РУС) — кіру бетінде және профильде қолданылады.
/// `Lang.current`-ты өзі тыңдайды, сол себепті ешбір parent state қажет
/// емес (тіл ауысқанда main.dart-тағы жоғарғы деңгей rebuild жасайды).
class LanguageSwitcher extends StatelessWidget {
  const LanguageSwitcher({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLang>(
      valueListenable: Lang.current,
      builder: (context, lang, _) => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Gz.surfaceAlt,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Gz.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _langPill('ҚАЗ', lang == AppLang.kk, () => Lang.set(AppLang.kk)),
            _langPill('РУС', lang == AppLang.ru, () => Lang.set(AppLang.ru)),
          ],
        ),
      ),
    );
  }

  Widget _langPill(String label, bool active, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
        decoration: BoxDecoration(
          // Белсенді тіл — градиентті «таблетка» + жеңіл көлеңке: қай тіл
          // қосулы екені бір қарағанда көрінеді.
          gradient: active ? Gz.brandGradient : null,
          borderRadius: BorderRadius.circular(16),
          boxShadow: active ? Gz.glow(Gz.yellow, alpha: 0.35, blur: 8) : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
            color: active ? Gz.onBrand : Gz.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// Интерфейс режимін ауыстыру: ☀ ақ · ☾ қара · ◐ құрылғыдағыдай.
/// [LanguageSwitcher]-мен бір үлгіде (жанында тұрады).
class ThemeSwitcher extends StatelessWidget {
  const ThemeSwitcher({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppThemeMode>(
      valueListenable: AppTheme.mode,
      builder: (context, mode, _) => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Gz.surfaceAlt,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Gz.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _pill(Icons.light_mode_rounded, t('Ақ'), mode, AppThemeMode.light),
            _pill(Icons.dark_mode_rounded, t('Қара'), mode, AppThemeMode.dark),
            _pill(
              Icons.brightness_auto_rounded,
              t('Құрылғыдағыдай'),
              mode,
              AppThemeMode.system,
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(
    IconData icon,
    String tooltip,
    AppThemeMode current,
    AppThemeMode value,
  ) {
    final active = current == value;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => AppTheme.set(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            gradient: active ? Gz.brandGradient : null,
            borderRadius: BorderRadius.circular(16),
            boxShadow: active ? Gz.glow(Gz.yellow, alpha: 0.35, blur: 8) : null,
          ),
          child: Icon(
            icon,
            size: 18,
            color: active ? Gz.onBrand : Gz.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// Заказды тоқтату/бас тарту себебін таңдату: дайын нұсқалар тізімі +
/// «Басқа себеп» (өз мәтінін жазады). null қайтарса — пайдаланушы бас тартты.
Future<String?> pickCancelReason(
  BuildContext context, {
  required String title,
  required List<String> presets,
}) {
  return showGzSheet<String>(
    context,
    builder: (_) => _CancelReasonSheet(title: title, presets: presets),
  );
}

class _CancelReasonSheet extends StatefulWidget {
  final String title;
  final List<String> presets;
  const _CancelReasonSheet({required this.title, required this.presets});

  @override
  State<_CancelReasonSheet> createState() => _CancelReasonSheetState();
}

class _CancelReasonSheetState extends State<_CancelReasonSheet> {
  static const _other = 'Басқа себеп';
  String? _selected;
  final _customCtrl = TextEditingController();

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  bool get _canConfirm {
    if (_selected == null) return false;
    if (_selected == _other) return _customCtrl.text.trim().isNotEmpty;
    return true;
  }

  void _confirm() {
    final reason = _selected == _other ? _customCtrl.text.trim() : _selected!;
    Navigator.of(context).pop(reason);
  }

  @override
  Widget build(BuildContext context) {
    return GzSheetBody(
      title: widget.title,
      subtitle: t('Себебін таңдаңыз'),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final p in [...widget.presets, _other])
              InkWell(
                borderRadius: BorderRadius.circular(Gz.rSm),
                onTap: () => setState(() => _selected = p),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 9,
                    horizontal: 2,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _selected == p
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        size: 21,
                        color: _selected == p ? Gz.red : Gz.textSecondary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          t(p),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: _selected == p
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (_selected == _other) ...[
              const SizedBox(height: 4),
              TextField(
                controller: _customCtrl,
                autofocus: true,
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(hintText: t('Себебіңізді жазыңыз')),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              style: Gz.dangerFilled(),
              onPressed: _canConfirm ? _confirm : null,
              child: Text(t('Растау')),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tasu логотипі (мәтіндік).
class GazelGoLogo extends StatelessWidget {
  final double size;
  const GazelGoLogo({super.key, this.size = 28});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/icon/tasu_logo.png',
          height: size * 1.35,
          width: size * 1.35 * 826 / 1013,
          filterQuality: FilterQuality.medium,
        ),
        SizedBox(width: size * 0.3),
        Text(
          'Tasu',
          style: TextStyle(
            fontSize: size,
            fontWeight: FontWeight.w900,
            color: Gz.ink,
          ),
        ),
      ],
    );
  }
}
