import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../widgets.dart' show PressScale;

/// Шағын ақпарат белгісі (тег): «12.4 км», «Межгород», «+2 аялдама»…
///
/// Бұрын заказ карточкасында да, лентада да, хабарландыруларда да өз
/// `_tag()` функциясы болатын — өлшемдері мен түстері сәл-сәлден ерекше.
class InfoChip extends StatelessWidget {
  final IconData? icon;

  /// Иконканың орнына кез келген виджет (мыс. көлік суреті).
  final Widget? leading;
  final String text;

  /// null — бейтарап сұр тег; түс берілсе — сол түстің жұмсақ реңкі.
  final Color? color;

  /// Ұзын мәтін (жүк сипаттамасы) — ені шектеледі, артығы «…».
  final bool flexible;

  const InfoChip({
    super.key,
    this.icon,
    this.leading,
    required this.text,
    this.color,
    this.flexible = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = color;
    final chip = Container(
      padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
      decoration: BoxDecoration(
        color: c == null ? Gz.surfaceAlt : Gz.tint(c, 0.11),
        borderRadius: BorderRadius.circular(Gz.rXs),
        border: Border.all(color: c == null ? Gz.border : Gz.tint(c, 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null)
            leading!
          else if (icon != null)
            Icon(icon, size: 14, color: c ?? Gz.textSecondary),
          if (leading != null || icon != null) const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: c ?? Gz.ink,
                letterSpacing: -0.05,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (!flexible) return chip;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 180),
      child: chip,
    );
  }
}

/// Көрсеткіш плиткасы: иконка, ірі сан, атауы, (міндетті емес) түсініктеме.
/// Модератордың Шолуы, Линия, орындаушы беті, табыс — бәрінде бірдей.
class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final String? hint;
  final IconData? icon;
  final Color? color;
  final VoidCallback? onTap;

  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.hint,
    this.icon,
    this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? Gz.ink;
    final body = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Gz.surface,
        borderRadius: BorderRadius.circular(Gz.rMd),
        border: Border.all(color: Gz.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 6),
          ],
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                height: 1.15,
                letterSpacing: -0.5,
                color: color,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          if (hint != null)
            Text(
              hint!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: Gz.textSecondary),
            ),
        ],
      ),
    );
    if (onTap == null) return body;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(Gz.rMd),
        onTap: onTap,
        child: body,
      ),
    );
  }
}

/// Дөңгелек «−»/«+» батырмасы (баға, тиеуші саны, сома степперлері).
/// Ұзақ басса — үлкен қадам ([onLongPress]).
class GzStepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double size;

  const GzStepButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.onLongPress,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return PressScale(
      enabled: enabled,
      scale: 0.92,
      child: Material(
        color: Gz.surface,
        shape: CircleBorder(
          side: BorderSide(
            color: enabled ? Gz.border : Gz.disabledBg,
            width: 1.4,
          ),
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          onLongPress: onLongPress,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(
              icon,
              size: size * 0.48,
              color: enabled ? Gz.ink : Gz.disabledFg,
            ),
          ),
        ),
      ),
    );
  }
}

/// Бөлімнің тақырыбы (+ түсініктеме, + оң жақтағы әрекет). Барлық экранда
/// бөлім тақырыбы осындай: бұрын бірде 15, бірде 16, бірде 17 болатын.
class SectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsets padding;

  const SectionTitle(
    this.title, {
    super.key,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.only(bottom: 8),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Gz.h3),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: Gz.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Санауыш белгі (badge): «3» жаңа өтінім, «12» белсенді заказ…
/// 0 болса көрінбейді.
class CountBadge extends StatelessWidget {
  final int count;

  /// Қызыл — шұғыл назар керек (модератордың күтіп тұрған ісі); әйтпесе
  /// брендтің сары белгісі.
  final bool urgent;

  const CountBadge(this.count, {super.key, this.urgent = false});

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    return Container(
      constraints: const BoxConstraints(minWidth: 22),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: urgent ? Gz.red : Gz.yellow,
        borderRadius: BorderRadius.circular(Gz.rSm),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w900,
          height: 1.1,
          color: urgent ? Colors.white : Gz.onBrand,
        ),
      ),
    );
  }
}

/// Тізім жолы: түрлі-түсті шаршыдағы иконка, тақырып (+ түсініктеме),
/// оң жақта «›» немесе өз виджеті. Профиль, мәзір, баптаулар — бәрі осы.
class GzListRow extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Қауіпті әрекет (Шығу, Өшіру) — тақырып қызыл.
  final bool danger;

  const GzListRow({
    super.key,
    required this.icon,
    this.color,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? Gz.ink;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14),
      horizontalTitleGap: 12,
      minLeadingWidth: 34,
      leading: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Gz.tint(color, 0.12),
          borderRadius: BorderRadius.circular(Gz.rSm),
        ),
        child: Icon(icon, size: 18, color: color),
      ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 15,
          letterSpacing: -0.15,
          color: danger ? Gz.red : Gz.ink,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, style: const TextStyle(fontSize: 13)),
      trailing:
          trailing ??
          (onTap == null
              ? null
              : Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: Gz.textTertiary,
                )),
      onTap: onTap,
    );
  }
}

/// Картаның үстіндегі дөңгелек ақ батырма («☰ мәзір», «менің орным»).
/// Көлеңкесі күштірек — әйтпесе карта суретіне сіңіп кетеді.
class MapRoundButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final double size;

  /// Бұрыштағы шағын белгі (мыс. белсенді заказ саны).
  final int badge;

  const MapRoundButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.size = 48,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    final button = Container(
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: Gz.cardShadow,
      ),
      child: Material(
        shape: const CircleBorder(),
        color: Gz.surface,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, color: Gz.ink, size: size * 0.48),
          ),
        ),
      ),
    );
    final withTip = tooltip == null
        ? button
        : Tooltip(message: tooltip!, child: button);
    if (badge <= 0) return PressScale(child: withTip);
    return PressScale(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          withTip,
          Positioned(
            right: -4,
            top: -4,
            child: IgnorePointer(child: CountBadge(badge, urgent: true)),
          ),
        ],
      ),
    );
  }
}
