import 'package:flutter/material.dart';

import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';

/// Ұсыныстың нәтижесі: баға, келу уақыты (мин) және қысқа хабар.
typedef OfferDraft = ({int price, int etaMin, String message});

/// Ұсыныс беру терезесі (inDrive үлгісі).
///
/// Бір терезеде үш сұрақ:
///   1. БАҒА — «Келісу» режимінде клиенттің бағасы (өзгертілмейді),
///      «Өз бағам» режимінде ±100 ₸ степпер;
///   2. «НЕШЕ МИНУТТА ЖЕТЕСІЗ?» — 3 / 5 / 7 / 10 / 15 / 20 / 30 / 45 / 60 мин.
///      Әдепкісі орындаушының алу нүктесіне дейінгі қашықтығынан есептеледі
///      (бір басумен растауға болады). Клиент ұсыныстарды осы уақыт бойынша
///      салыстырады, қабылдаған соң кері санақты көреді;
///   3. КЛИЕНТКЕ ҚЫСҚА ХАБАР (міндетті емес) — дайын фразалар.
Future<OfferDraft?> showOfferSheet(
  BuildContext context, {
  required Order order,
  required bool counter,
  double? kmToPickup,
}) {
  return showGzSheet<OfferDraft>(
    context,
    builder: (_) =>
        _OfferSheet(order: order, counter: counter, kmToPickup: kmToPickup),
  );
}

/// Келу уақытының нұсқалары, минут.
const kEtaChoices = [3, 5, 7, 10, 15, 20, 30, 45, 60];

/// Қашықтықтан ұсынылатын келу уақыты: қалада орташа ~25 км/сағ + 2 мин
/// дайындық, ең жақын үлкен нұсқаға дейін дөңгелектенеді.
int suggestEta(double? km) {
  if (km == null) return 10;
  final minutes = km / 25 * 60 + 2;
  for (final c in kEtaChoices) {
    if (c >= minutes) return c;
  }
  return kEtaChoices.last;
}

class _OfferSheet extends StatefulWidget {
  final Order order;
  final bool counter;
  final double? kmToPickup;
  const _OfferSheet({
    required this.order,
    required this.counter,
    this.kmToPickup,
  });

  @override
  State<_OfferSheet> createState() => _OfferSheetState();
}

class _OfferSheetState extends State<_OfferSheet> {
  late int _price = widget.order.clientPrice ?? 1000;
  late int _eta = suggestEta(widget.kmToPickup);
  final _msg = TextEditingController();

  static const _step = 100;

  static const _phrases = [
    'Қазір шығамын',
    'Тиеушілер бар',
    'Көлігім бос, таза',
    'Жолдамын, жақынмын',
  ];

  @override
  void dispose() {
    _msg.dispose();
    super.dispose();
  }

  void _bump(int delta) =>
      setState(() => _price = (_price + delta).clamp(100, 100000000));

  @override
  Widget build(BuildContext context) {
    final base = widget.order.clientPrice;
    return GzSheetBody(
      title: widget.counter ? t('Өз бағаңызды ұсыныңыз') : t('Бағаға келісу'),
      subtitle: base == null ? null : '${t('Клиенттің бағасы:')} ${fmtT(base)}',
      showClose: true,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.counter) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GzStepButton(
                    icon: Icons.remove_rounded,
                    size: 52,
                    onTap: () => _bump(-_step),
                    onLongPress: () => _bump(-1000),
                  ),
                  Column(
                    children: [
                      Text(fmtT(_price), style: Gz.moneyXl),
                      Text(t('±100 ₸ қадам'), style: Gz.caption),
                    ],
                  ),
                  GzStepButton(
                    icon: Icons.add_rounded,
                    size: 52,
                    onTap: () => _bump(_step),
                    onLongPress: () => _bump(1000),
                  ),
                ],
              ),
              const SizedBox(height: 18),
            ],
            Row(
              children: [
                const Icon(Icons.timer_outlined, size: 18, color: Gz.ink),
                const SizedBox(width: 6),
                Expanded(child: Text(t('Неше минутта жетесіз?'), style: Gz.h3)),
                if (widget.kmToPickup != null)
                  Text(
                    '${t('Сізден')} ${widget.kmToPickup!.toStringAsFixed(1)} ${t('км')}',
                    style: Gz.caption,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in kEtaChoices)
                  _EtaChip(
                    minutes: m,
                    selected: _eta == m,
                    onTap: () => setState(() => _eta = m),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            Text(t('Клиентке хабар (міндетті емес)'), style: Gz.h3),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final p in _phrases)
                  ChoiceChip(
                    label: Text(t(p)),
                    selected: _msg.text == t(p),
                    onSelected: (_) => setState(() => _msg.text = t(p)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _msg,
              maxLength: 120,
              maxLines: 1,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: t('Мысалы: 2 тиеушім бар'),
                counterText: '',
                prefixIcon: const Icon(Icons.chat_bubble_outline_rounded),
              ),
            ),
            const SizedBox(height: 16),
            GzPrimaryButton(
              label:
                  '${t('Ұсыну')} · ${fmtT(widget.counter ? _price : (base ?? _price))} · ~$_eta ${t('мин')}',
              onPressed: () => Navigator.pop<OfferDraft>(context, (
                price: widget.counter ? _price : (base ?? _price),
                etaMin: _eta,
                message: _msg.text.trim(),
              )),
            ),
          ],
        ),
      ),
    );
  }
}

/// Келу уақытының чипі: таңдалғаны қара фонда сары жазумен (көлік
/// каруселіндегі таңдаумен бірдей тіл).
class _EtaChip extends StatelessWidget {
  final int minutes;
  final bool selected;
  final VoidCallback onTap;
  const _EtaChip({
    required this.minutes,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return PressScale(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 64,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? Gz.ink : Gz.surface,
            borderRadius: BorderRadius.circular(Gz.rMd),
            border: Border.all(
              color: selected ? Gz.yellow : Gz.border,
              width: selected ? 2 : 1.4,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$minutes',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                  color: selected ? Gz.yellow : Gz.ink,
                ),
              ),
              Text(
                t('мин'),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white70 : Gz.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
