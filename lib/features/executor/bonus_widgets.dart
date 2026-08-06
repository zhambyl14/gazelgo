import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';

/// Бонус бағдарламасының түсі — бүкіл қосымшада БІРДЕЙ (лента жолағы,
/// профиль картасы, тарих экраны). Күлгін: сары бренд түсі «тариф/баланс»
/// мағынасында бос емес, сол себепті бонус одан айқын ажырап тұрады.
const _bonusColor = Gz.violet;

/// Лентаның ҮСТІНДЕ тұратын ықшам бонус жолағы (0059).
///
/// Модератор бонус бағдарламасын өшіріп қойса — МҮЛДЕМ көрінбейді
/// (`SizedBox.shrink`), сол себепті бағдарлама жоқ кезде лента баяғы
/// қалпында қалады. Түртсе — толық шарттары бар парақ ашылады.
class BonusStrip extends ConsumerWidget {
  /// Жолақтың СЫРТҚЫ шеті. Лентада ListView-дің өз padding-і бар, сол
  /// себепті әдепкіде нөл — қос шет пайда болмайды.
  final EdgeInsets padding;
  const BonusStrip({super.key, this.padding = EdgeInsets.zero});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = ref.watch(executorBonusStreamProvider).value;
    if (b == null || !b.visible) return const SizedBox.shrink();

    // Қайталанбайтын режимде кезеңдегі бонус алынып қойған — «алдыңыз»
    // деген тыныш күй (жаңа мақсат келесі кезеңде ашылады).
    final done = b.finished;
    final left = b.left;

    return Padding(
      padding: padding,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => showBonusSheet(context, b),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _bonusColor.withValues(alpha: 0.13),
                  _bonusColor.withValues(alpha: 0.04),
                ],
              ),
              border: Border.all(color: _bonusColor.withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: _bonusColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(
                        done
                            ? Icons.emoji_events_rounded
                            : Icons.card_giftcard_rounded,
                        size: 18,
                        color: _bonusColor,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            done
                                ? t('Бонус алынды 🎉')
                                : '${t('Бонусқа')} $left ${t('заказ қалды')}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            done
                                ? '${bonusPeriodNow(b.period)}: '
                                      '${fmtT(b.earned)}'
                                : '${bonusPeriodNow(b.period)} '
                                      '${b.inCycle}/${b.target} ${t('заказ')}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: Gz.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: _bonusColor,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '+${fmtT(b.amount)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                BonusProgressBar(b.progress),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Бонус прогресінің жолағы — бүкіл қосымшада бір көрініс.
class BonusProgressBar extends StatelessWidget {
  final double value;
  final double height;
  const BonusProgressBar(this.value, {super.key, this.height = 7});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
        builder: (_, v, _) => LinearProgressIndicator(
          value: v,
          minHeight: height,
          backgroundColor: _bonusColor.withValues(alpha: 0.15),
          valueColor: const AlwaysStoppedAnimation(_bonusColor),
        ),
      ),
    );
  }
}

/// Бонустың ТОЛЫҚ шарттары мен прогресі — түсіндірме парақ.
void showBonusSheet(BuildContext context, BonusInfo b) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Gz.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _BonusSheet(b),
  );
}

class _BonusSheet extends StatelessWidget {
  final BonusInfo b;
  const _BonusSheet(this.b);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Gz.border,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _bonusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.card_giftcard_rounded,
                    color: _bonusColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t('Белсенділік бонусы'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                      Text(
                        '${b.target} ${t('заказ')} → ${fmtT(b.amount)}',
                        style: const TextStyle(
                          color: Gz.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            // Прогресс
            Row(
              children: [
                Text(
                  '${b.finished ? b.target : b.inCycle}',
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    color: _bonusColor,
                    height: 1,
                  ),
                ),
                Text(
                  ' / ${b.target}',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Gz.textSecondary,
                  ),
                ),
                const Spacer(),
                if (!b.finished)
                  Text(
                    '${t('Қалды')}: ${b.left}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            BonusProgressBar(b.progress, height: 10),
            const SizedBox(height: 18),
            // Шарттар
            _rule(
              Icons.local_shipping_outlined,
              '${t('Аяқталған заказ саны')}: ${b.target}',
              '${t('Санақ')} ${bonusPeriodLabel(b.period)} '
                  '${t('жаңарады')}.',
            ),
            _rule(
              Icons.account_balance_wallet_outlined,
              '${t('Бонус')}: ${fmtT(b.amount)}',
              t('Сома БАЛАНСҚА түседі — тариф сатып алуға жұмсалады. '
                  'Қолма-қол шешіп алу әзірге жоқ.'),
            ),
            if (b.repeat)
              _rule(
                Icons.repeat_rounded,
                t('Қайталанады'),
                '${t('Кезең ішінде әр')} ${b.target} ${t('заказ сайын жаңа '
                    'бонус беріледі.')}',
              )
            else
              _rule(
                Icons.looks_one_outlined,
                t('Кезеңде бір рет'),
                '${t('Бір кезеңде бір бонус')} — '
                    '${bonusPeriodLabel(b.period)} ${t('жаңарады')}.',
              ),
            if (b.periodEnd != null)
              _rule(
                Icons.event_outlined,
                t('Кезеңнің аяқталуы'),
                fmtDate(b.periodEnd),
              ),
            const SizedBox(height: 8),
            // Жиналған сома
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Gz.bg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _stat(
                      bonusPeriodNow(b.period),
                      fmtT(b.earned),
                      _bonusColor,
                    ),
                  ),
                  Container(width: 1, height: 34, color: Gz.border),
                  Expanded(
                    child: _stat(
                      t('Барлығы'),
                      fmtT(b.earnedTotal),
                      Gz.ink,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const BonusHistoryScreen()),
                );
              },
              icon: const Icon(Icons.history, size: 20),
              label: BtnLabel(t('Бонус тарихы')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rule(IconData icon, String title, String body) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: _bonusColor),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                ),
              ),
              Text(
                body,
                style: const TextStyle(
                  color: Gz.textSecondary,
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _stat(String label, String value, Color color) => Column(
    children: [
      Text(
        label,
        style: const TextStyle(color: Gz.textSecondary, fontSize: 11.5),
      ),
      const SizedBox(height: 3),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
      ),
    ],
  );
}

/// Берілген бонустардың тарихы.
class BonusHistoryScreen extends StatelessWidget {
  const BonusHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t('Бонус тарихы'))),
      body: FutureBuilder<List<BonusAward>>(
        future: Repo.myBonusAwards(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return EmptyState(
              icon: Icons.wifi_off,
              title: errText(snap.error!),
            );
          }
          final rows = snap.data ?? const <BonusAward>[];
          if (rows.isEmpty) {
            return EmptyState(
              icon: Icons.card_giftcard_outlined,
              title: t('Әзірге бонус жоқ'),
              subtitle: t('Заказ лимитін толтырсаңыз — бонус балансқа '
                  'автоматты түседі.'),
            );
          }
          final total = rows.fold<int>(0, (s, e) => s + e.amount);
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: rows.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              if (i == 0) {
                return SectionCard(
                  child: Row(
                    children: [
                      const Icon(
                        Icons.emoji_events_rounded,
                        color: _bonusColor,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${t('Барлық бонус')}: ${rows.length}×',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      Text(
                        fmtT(total),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          color: _bonusColor,
                        ),
                      ),
                    ],
                  ),
                );
              }
              final a = rows[i - 1];
              return SectionCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _bonusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: const Icon(
                        Icons.card_giftcard_rounded,
                        size: 18,
                        color: _bonusColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${a.ordersAtAward} ${t('заказ')}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            fmtDate(a.createdAt),
                            style: const TextStyle(
                              color: Gz.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '+${fmtT(a.amount)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14.5,
                        color: Gz.green,
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Профильдегі бонус картасы (орындаушыға). Бағдарлама өшірулі болса —
/// көрінбейді.
class BonusProfileCard extends ConsumerWidget {
  const BonusProfileCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = ref.watch(executorBonusStreamProvider).value;
    if (b == null || !b.visible) return const SizedBox.shrink();

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.card_giftcard_rounded,
                size: 18,
                color: _bonusColor,
              ),
              const SizedBox(width: 8),
              Text(
                t('Белсенділік бонусы'),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => showBonusSheet(context, b),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: BtnLabel(t('Шарттары')),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  b.finished
                      ? t('Бонус алынды 🎉')
                      : '${b.inCycle}/${b.target} ${t('заказ')}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
              ),
              Text(
                '+${fmtT(b.amount)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  color: _bonusColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          BonusProgressBar(b.progress),
          const SizedBox(height: 8),
          Text(
            b.finished
                ? '${bonusPeriodNow(b.period)}: ${fmtT(b.earned)} → '
                      '${t('балансқа түсті')}'
                : '${t('Бонусқа')} ${b.left} ${t('заказ қалды')} · '
                      '${t('Барлығы')} ${fmtT(b.earnedTotal)}',
            style: const TextStyle(color: Gz.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
