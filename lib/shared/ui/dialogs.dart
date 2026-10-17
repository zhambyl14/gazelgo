import 'package:flutter/material.dart';

import '../../core/lang.dart';
import '../../core/theme.dart';
import '../widgets.dart' show BtnLabel;

/// Диалогтағы батырмаларға ортақ стиль: көлденең padding КІШІ (мәтінге
/// орын қалуы үшін) әрі шрифт 15 — сонда орысша жазулар да толық өлшемінде
/// бір жолда сыяды (FittedBox қосылмайды → екеуінің шрифті бірдей).
final ButtonStyle _dialogBtnStyle = ButtonStyle(
  padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 6)),
  textStyle: const WidgetStatePropertyAll(
    TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w700,
      fontFamily: Gz.fontFamily,
    ),
  ),
);

/// Диалогтың БІРЫҢҒАЙ жақтауы — қосымшадағы барлық диалог осыны қолданады.
///
/// Бұрын екі түрлі диалог қатар жүретін: ескі `AlertDialog` (бәрі ортада,
/// батырмалар оң жақта ұсақ мәтінмен) және жаңа растау терезесі (бәрі сол
/// жақта, батырмалар толық енмен). Енді бәрі бір үлгіде: сол жақта иконка-
/// белгі, тақырып, түсініктеме, мазмұн, ең астында 1–2 тең батырма.
class GzDialogFrame extends StatelessWidget {
  final IconData? icon;

  /// Иконка белгісінің түсі (мағынасына қарай: қызыл — қауіпті әрекет).
  final Color color;
  final String title;
  final String? message;

  /// Түсініктеменің астындағы мазмұн (өріс, чиптер…).
  final Widget? content;

  /// Батырмалар — әрқайсысы бір қатарда тең ен алады.
  final List<Widget> actions;

  /// Батырмалар ҮШ немесе одан көп болса (не жазулары ұзын) — бір-бірінің
  /// астына толық енмен тізіледі (бір қатарда сыймай, қысылып кетпеуі үшін).
  final bool verticalActions;

  const GzDialogFrame({
    super.key,
    this.icon,
    this.color = Gz.ink,
    required this.title,
    this.message,
    this.content,
    required this.actions,
    this.verticalActions = false,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (icon != null) ...[
              // «Featured icon»: дөңгелектелген шаршыда, айналасы екі қабат
              // реңкпен. Бүкіл мазмұн СОЛ ЖАҚҚА тураланған — көз бір бағанда
              // оқиды.
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Gz.tint(color, 0.12),
                    borderRadius: BorderRadius.circular(Gz.rMd),
                    border: Border.all(color: Gz.tint(color, 0.22), width: 1.4),
                  ),
                  child: Icon(icon, color: color, size: 26),
                ),
              ),
              const SizedBox(height: 16),
            ],
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                height: 1.25,
                letterSpacing: -0.35,
              ),
            ),
            if (message != null && message!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                style: const TextStyle(
                  color: Gz.textSecondary,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ],
            if (content != null) ...[const SizedBox(height: 16), content!],
            const SizedBox(height: 22),
            if (verticalActions)
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                actions[i],
              ]
            else
              Row(
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(width: 10),
                    Expanded(child: actions[i]),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Диалогтың «бас тарту» батырмасы (контур).
Widget gzDialogCancel(BuildContext ctx, String label, {Object? result}) =>
    OutlinedButton(
      style: _dialogBtnStyle,
      onPressed: () => Navigator.pop(ctx, result),
      child: BtnLabel(label),
    );

/// Диалогтың негізгі батырмасы (толтырылған). [color] берілсе — сол түсте
/// (қызыл — қауіпті әрекет), әйтпесе брендтің сары батырмасы.
Widget gzDialogPrimary(
  String label, {
  required VoidCallback? onPressed,
  Color? color,
}) =>
    FilledButton(
      style: color == null
          ? _dialogBtnStyle
          : _dialogBtnStyle.copyWith(
              backgroundColor: WidgetStateProperty.resolveWith(
                (s) => s.contains(WidgetState.disabled) ? Gz.disabledBg : color,
              ),
              foregroundColor: WidgetStateProperty.resolveWith(
                (s) => s.contains(WidgetState.disabled)
                    ? Gz.disabledFg
                    : Colors.white,
              ),
              shadowColor: WidgetStatePropertyAll(color.withValues(alpha: 0.35)),
            ),
      onPressed: onPressed,
      child: BtnLabel(label),
    );

/// Екі батырмалы растау диалогы. `true` — келісті.
///
/// [emphasizeCancel] — қайтарылмайтын әрекеттің СОҢҒЫ растауында қауіпті
/// түймені басым емес, қайта «бас тарту» түймесін басым қылу үшін (мыс.
/// аккаунтты өшірудің 2-қадамы).
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String? cancelLabel,
  required String confirmLabel,
  Color confirmColor = Gz.ink,
  IconData? icon,
  bool emphasizeCancel = false,
}) async {
  final cancelText = cancelLabel ?? t('Жоқ');
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => GzDialogFrame(
      icon: icon,
      color: confirmColor,
      title: title,
      message: message,
      actions: emphasizeCancel
          ? [
              FilledButton(
                style: _dialogBtnStyle,
                onPressed: () => Navigator.pop(ctx, false),
                child: BtnLabel(cancelText),
              ),
              OutlinedButton(
                style: _dialogBtnStyle.copyWith(
                  foregroundColor: WidgetStatePropertyAll(confirmColor),
                  side: WidgetStatePropertyAll(
                    BorderSide(
                      color: confirmColor.withValues(alpha: 0.4),
                      width: 1.4,
                    ),
                  ),
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: BtnLabel(confirmLabel),
              ),
            ]
          : [
              gzDialogCancel(ctx, cancelText, result: false),
              gzDialogPrimary(
                confirmLabel,
                color: confirmColor,
                onPressed: () => Navigator.pop(ctx, true),
              ),
            ],
    ),
  );
  return ok == true;
}

/// Ақпараттық диалог — бір ғана шешімі бар хабар («Тарифіңіз жоқ»,
/// «Аккаунтыңыз тексеруде»…). [actionLabel] берілсе — екі батырма:
/// «Жабу» және негізгі әрекет; әйтпесе бір ғана «Түсінікті».
Future<void> gzInfoDialog(
  BuildContext context, {
  required String title,
  required String message,
  IconData icon = Icons.info_outline_rounded,
  Color color = Gz.info,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => GzDialogFrame(
      icon: icon,
      color: color,
      title: title,
      message: message,
      actions: [
        if (actionLabel != null && onAction != null) ...[
          gzDialogCancel(ctx, t('Жабу')),
          gzDialogPrimary(
            actionLabel,
            onPressed: () {
              Navigator.pop(ctx);
              onAction();
            },
          ),
        ] else
          gzDialogPrimary(t('Түсінікті'), onPressed: () => Navigator.pop(ctx)),
      ],
    ),
  );
}

/// Мәтін енгізу диалогы: себеп, түсініктеме, сома. Бас тартса — `null`.
///
/// [presets] берілсе — дайын нұсқалар ЧИП болып шығады: біреуін басса өріс
/// сол мәтінмен толады (модератор «Себебін» әр жолы қолмен термейді).
/// [required] — бос мәтінмен растауға болмайды.
Future<String?> gzInputDialog(
  BuildContext context, {
  required String title,
  String? message,
  String? hint,
  String initial = '',
  required String confirmLabel,
  Color? confirmColor,
  IconData? icon,
  List<String> presets = const [],
  bool required = false,
  int maxLines = 3,
  TextInputType? keyboardType,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _InputDialog(
      title: title,
      message: message,
      hint: hint,
      initial: initial,
      confirmLabel: confirmLabel,
      confirmColor: confirmColor,
      icon: icon,
      presets: presets,
      required: required,
      maxLines: maxLines,
      keyboardType: keyboardType,
    ),
  );
}

class _InputDialog extends StatefulWidget {
  final String title;
  final String? message;
  final String? hint;
  final String initial;
  final String confirmLabel;
  final Color? confirmColor;
  final IconData? icon;
  final List<String> presets;
  final bool required;
  final int maxLines;
  final TextInputType? keyboardType;

  const _InputDialog({
    required this.title,
    required this.message,
    required this.hint,
    required this.initial,
    required this.confirmLabel,
    required this.confirmColor,
    required this.icon,
    required this.presets,
    required this.required,
    required this.maxLines,
    required this.keyboardType,
  });

  @override
  State<_InputDialog> createState() => _InputDialogState();
}

class _InputDialogState extends State<_InputDialog> {
  late final _ctrl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool get _canConfirm => !widget.required || _ctrl.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return GzDialogFrame(
      icon: widget.icon,
      color: widget.confirmColor ?? Gz.ink,
      title: widget.title,
      message: widget.message,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.presets.isNotEmpty) ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final p in widget.presets)
                  ChoiceChip(
                    label: Text(p),
                    selected: _ctrl.text.trim() == p,
                    onSelected: (_) => setState(() {
                      _ctrl.text = p;
                      _ctrl.selection =
                          TextSelection.collapsed(offset: p.length);
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _ctrl,
            autofocus: widget.presets.isEmpty,
            maxLines: widget.maxLines,
            minLines: 1,
            keyboardType: widget.keyboardType,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(hintText: widget.hint),
          ),
        ],
      ),
      actions: [
        gzDialogCancel(context, t('Болдырмау')),
        gzDialogPrimary(
          widget.confirmLabel,
          color: widget.confirmColor,
          onPressed: _canConfirm
              ? () => Navigator.pop(context, _ctrl.text.trim())
              : null,
        ),
      ],
    );
  }
}
