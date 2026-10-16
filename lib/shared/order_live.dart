import 'dart:async';

import 'package:flutter/material.dart';

import '../core/lang.dart';
import '../core/models.dart';
import '../core/theme.dart';
import 'widgets.dart';

/// Секунд сайын қайта салынатын шағын орам (кері санақ, күту таймері).
class _Ticker extends StatefulWidget {
  final Widget Function(BuildContext context, DateTime now) builder;
  const _Ticker({required this.builder});

  @override
  State<_Ticker> createState() => _TickerState();
}

class _TickerState extends State<_Ticker> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, DateTime.now());
}

String _mmss(Duration d) {
  final s = d.inSeconds.abs();
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = (s % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$sec' : '$m:$sec';
}

/// «Неше минутта жетеді» — орындаушы ұсыныста уәде еткен уақытқа дейінгі
/// КЕРІ САНАҚ (0073, inDrive-тегідей). Уақыт өтіп кетсе — «кешігіп жатыр»
/// (сары → 5 минуттан кейін қызыл) және кешігу минуттары.
///
/// Сервер 0073-сыз болса ([Order.arriveBy] жоқ) — мүлдем көрінбейді.
class EtaCountdownCard extends StatelessWidget {
  final Order order;
  final bool forExecutor;

  /// Көліктен A нүктесіне дейінгі қашықтық (тірі орыннан, бар болса).
  final double? kmLeft;

  /// Кешіккенде көрінетін әрекет (мыс. «Клиентке жазу»).
  final Widget? lateAction;

  const EtaCountdownCard({
    super.key,
    required this.order,
    this.forExecutor = false,
    this.kmLeft,
    this.lateAction,
  });

  @override
  Widget build(BuildContext context) {
    final by = order.arriveBy;
    if (by == null || order.status != 'accepted') return const SizedBox.shrink();
    final total = Duration(minutes: order.executorEtaMin ?? 10);
    return _Ticker(
      builder: (context, now) {
        final left = by.difference(now);
        final late = left.isNegative;
        final veryLate = late && left.inMinutes <= -5;
        final color = veryLate ? Gz.danger : (late ? Gz.warning : Gz.blue);
        final progress = total.inSeconds <= 0
            ? 1.0
            : (1 - left.inSeconds / total.inSeconds).clamp(0.0, 1.0);
        final title = forExecutor
            ? (late ? t('Уәде еткен уақыт өтті') : t('Клиентке жету уақыты'))
            : (late ? t('Орындаушы сәл кешігіп жатыр') : t('Орындаушы жолда'));
        final hint = forExecutor
            ? '${t('Уәде:')} ~${order.executorEtaMin ?? '?'} ${t('мин')} '
                  '(${fmtTime(by)})'
            : '${t('Уәде еткен уақыты:')} ${fmtTime(by)}';
        return Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: Gz.tint(color, 0.07),
            borderRadius: BorderRadius.circular(Gz.rMd),
            border: Border.all(color: Gz.tint(color, 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Gz.tint(color, 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      late ? Icons.running_with_errors_rounded : Icons.timer_outlined,
                      color: color,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: Gz.h3),
                        const SizedBox(height: 2),
                        Text(
                          kmLeft == null
                              ? hint
                              : '$hint · ${kmLeft!.toStringAsFixed(1)} ${t('км қалды')}',
                          style: Gz.caption,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        late ? '+${_mmss(left)}' : _mmss(left),
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: color,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      Text(
                        late ? t('кешігу') : t('қалды'),
                        style: Gz.caption,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(Gz.rXs),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  color: color,
                  backgroundColor: Gz.tint(color, 0.15),
                ),
              ),
              if (late && lateAction != null) ...[
                const SizedBox(height: 10),
                lateAction!,
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Орындаушы «Келдім» дегеннен бергі КҮТУ уақыты (0073 `arrived_at`).
/// Клиентке — «сізді күтіп тұр» (асықсын деп), орындаушыға — «қанша
/// күтіп тұрмын» (кейін клиентке айтуға дәлел).
class WaitingTimerCard extends StatelessWidget {
  final Order order;
  final bool forExecutor;

  /// Таймердің астындағы мазмұн (мыс. клиенттің «Тиеу басталды» батырмасы).
  final Widget? child;

  const WaitingTimerCard({
    super.key,
    required this.order,
    this.forExecutor = false,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final since = order.arrivedAt;
    final isTaxi = order.vehicleType == VehicleType.taxi;
    return _Ticker(
      builder: (context, now) {
        final waited = since == null ? null : now.difference(since);
        final long = (waited?.inMinutes ?? 0) >= 10;
        final color = long ? Gz.warning : Gz.success;
        final title = forExecutor
            ? t('Клиенттің растауын күтіп тұрсыз')
            : (isTaxi ? t('Орындаушы сізді күтіп тұр') : t('Орындаушы келді'));
        final hint = forExecutor
            ? (isTaxi
                  ? t('Клиент «Отырғызу басталды» деп растаған соң «Жолға '
                        'шықтық» батырмасы шығады.')
                  : t('Клиент «Тиеу басталды» деп растаған соң «Жолға '
                        'шықтық» батырмасы шығады.'))
            : (long
                  ? t('Орындаушыны ұзақ күттірмеңіз.')
                  : (isTaxi
                        ? t('Көлікке отырсаңыз — төмендегі батырманы басыңыз.')
                        : t('Тиеу басталса — төмендегі батырманы басыңыз.')));
        return Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: Gz.tint(color, 0.07),
            borderRadius: BorderRadius.circular(Gz.rMd),
            border: Border.all(color: Gz.tint(color, 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Gz.tint(color, 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.hourglass_top_rounded, color: color, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: Gz.h3),
                        const SizedBox(height: 2),
                        Text(hint, style: Gz.caption),
                      ],
                    ),
                  ),
                  if (waited != null) ...[
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _mmss(waited),
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: color,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        Text(t('күту'), style: Gz.caption),
                      ],
                    ),
                  ],
                ],
              ),
              if (child != null) ...[const SizedBox(height: 12), child!],
            ],
          ),
        );
      },
    );
  }
}

/// Заказдың қосымша талаптары (0075): тиеушілер, қабат, лифт. Тек
/// толтырылғандары көрінеді; ештеңе жоқ болса — бос.
class OrderExtrasChips extends StatelessWidget {
  final Order order;
  const OrderExtrasChips({super.key, required this.order});

  static String floorText(int? f) => f == null
      ? '—'
      : (f <= 0 ? t('жер үй') : '$f ${t('қабат')}');

  @override
  Widget build(BuildContext context) {
    final o = order;
    if (!o.hasExtras) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        if (o.loaders > 0)
          InfoChip(
            icon: Icons.groups_rounded,
            color: Gz.violet,
            text: '${t('Тиеуші')}: ${o.loaders}',
          ),
        if (o.floorFrom != null || o.floorTo != null)
          InfoChip(
            icon: Icons.stairs_rounded,
            color: Gz.blue,
            text: 'A: ${floorText(o.floorFrom)} → B: ${floorText(o.floorTo)}',
          ),
        if (o.hasElevator != null)
          InfoChip(
            icon: o.hasElevator!
                ? Icons.elevator_rounded
                : Icons.do_not_disturb_on_outlined,
            color: o.hasElevator! ? Gz.success : Gz.warning,
            text: o.hasElevator! ? t('Лифт бар') : t('Лифт жоқ'),
          ),
      ],
    );
  }
}
