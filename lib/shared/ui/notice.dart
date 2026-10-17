import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../widgets.dart' show BusyButton;

/// Баннердің МАҒЫНАСЫ — түсі мен әдепкі иконкасын анықтайды
/// ([Gz.success], [Gz.info] … мағыналық рөлдерімен бірдей).
enum NoticeTone { info, success, warning, danger, accent, neutral }

extension NoticeToneX on NoticeTone {
  /// Иконка мен тақырыптың түсі.
  Color get color => switch (this) {
    NoticeTone.info => Gz.info,
    NoticeTone.success => Gz.success,
    NoticeTone.warning => Gz.warning,
    NoticeTone.danger => Gz.danger,
    NoticeTone.accent => Gz.accent,
    NoticeTone.neutral => Gz.textSecondary,
  };

  /// Блоктың жұмсақ фоны. Ескерту — брендтің сары реңкінде (қоңыр
  /// [Gz.warning]-тің өз реңкі кір болып көрінетін).
  Color get background => switch (this) {
    NoticeTone.warning => Gz.tint(Gz.yellow, 0.14),
    NoticeTone.neutral => Gz.surfaceAlt,
    NoticeTone.danger => Gz.tint(Gz.red, 0.06),
    _ => Gz.tint(color, 0.07),
  };

  Color get borderColor => switch (this) {
    NoticeTone.warning => Gz.tint(Gz.yellowDark, 0.40),
    NoticeTone.neutral => Gz.border,
    _ => Gz.tint(color, 0.28),
  };

  IconData get icon => switch (this) {
    NoticeTone.info => Icons.info_outline_rounded,
    NoticeTone.success => Icons.check_circle_outline_rounded,
    NoticeTone.warning => Icons.lightbulb_outline_rounded,
    NoticeTone.danger => Icons.error_outline_rounded,
    NoticeTone.accent => Icons.schedule_rounded,
    NoticeTone.neutral => Icons.info_outline_rounded,
  };
}

/// Бірыңғай ескерту / ақпарат блогы.
///
/// Бұрын қосымшада сегіз түрлі «баннер» болатын (құжат жаңарту, жоспарлы
/// заказ, бағаны көтеру кеңесі, қала ауыстыру, күй карталары…): әрқайсысының
/// өз түсі, өз радиусы, өз шегінісі. Енді бәрі осы бір виджет — құрылымы
/// әрқашан бірдей: сол жақта түрлі-түсті белгі, оң жақта тақырып пен
/// түсініктеме, қажет болса астында толық енді әрекет батырмасы.
class GzNotice extends StatelessWidget {
  final NoticeTone tone;

  /// null — мағынаның әдепкі иконкасы ([NoticeToneX.icon]).
  final IconData? icon;
  final String? title;
  final String? message;

  /// Мәтіннің астындағы қосымша мазмұн (чиптер, шағын батырмалар…).
  final Widget? child;

  /// Блоктың астындағы ТОЛЫҚ ЕНДІ әрекет (мыс. «Өтінім толтыру»).
  final String? actionLabel;
  final Future<void> Function()? onAction;

  /// Оң жақтағы шағын әрекет (мыс. «Ауыстыру» мәтін-батырмасы).
  final Widget? trailing;

  /// Бүкіл блок басылады — оң жақта «›» белгісі шығады.
  final VoidCallback? onTap;

  /// Жабу «✕» батырмасы.
  final VoidCallback? onClose;

  /// Ықшам нұсқа (тізімнің ішінде, тар орында).
  final bool dense;

  const GzNotice({
    super.key,
    this.tone = NoticeTone.info,
    this.icon,
    this.title,
    this.message,
    this.child,
    this.actionLabel,
    this.onAction,
    this.trailing,
    this.onTap,
    this.onClose,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = tone.color;
    final hasTitle = title != null && title!.isNotEmpty;
    final hasMessage = message != null && message!.isNotEmpty;
    final iconBox = dense ? 30.0 : 34.0;

    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasTitle)
          Text(
            title!,
            style: TextStyle(
              fontSize: dense ? 14 : 15,
              fontWeight: FontWeight.w800,
              height: 1.3,
              letterSpacing: -0.2,
              color: tone == NoticeTone.danger ? Gz.red : Gz.ink,
            ),
          ),
        if (hasMessage) ...[
          if (hasTitle) const SizedBox(height: 3),
          Text(
            message!,
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: hasTitle ? Gz.textSecondary : Gz.ink,
              fontWeight: hasTitle ? FontWeight.w400 : FontWeight.w600,
            ),
          ),
        ],
        if (child != null) ...[
          if (hasTitle || hasMessage) const SizedBox(height: 10),
          child!,
        ],
      ],
    );

    final row = Row(
      crossAxisAlignment: hasTitle && hasMessage
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        Container(
          width: iconBox,
          height: iconBox,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Gz.tint(c, 0.14),
            borderRadius: BorderRadius.circular(Gz.rSm),
          ),
          child: Icon(icon ?? tone.icon, size: dense ? 17 : 19, color: c),
        ),
        const SizedBox(width: 12),
        Expanded(child: text),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        if (onTap != null && trailing == null)
          Icon(Icons.chevron_right_rounded, color: c),
        if (onClose != null)
          IconButton(
            onPressed: onClose,
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            color: Gz.textSecondary,
            icon: const Icon(Icons.close_rounded),
          ),
      ],
    );

    final box = Container(
      padding: dense
          ? const EdgeInsets.fromLTRB(12, 10, 10, 10)
          : const EdgeInsets.fromLTRB(14, 13, 12, 13),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(Gz.rMd),
        border: Border.all(color: tone.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          row,
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 12),
            BusyButton(label: actionLabel!, onPressed: onAction!),
          ],
        ],
      ),
    );

    if (onTap == null) return box;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(Gz.rMd),
        onTap: onTap,
        child: box,
      ),
    );
  }
}
