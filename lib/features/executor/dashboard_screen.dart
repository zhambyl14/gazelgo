import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/lang.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import '../auth/executor_apply_screen.dart';
import 'balance_screen.dart';

/// Орындаушының тариф пен баланс экраны (басты беттен ашылады).
class ExecutorDashboardScreen extends ConsumerWidget {
  const ExecutorDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(executorStatsStreamProvider);
    final ep = ref.watch(myExecutorProfileProvider).value;

    return Scaffold(
      appBar: AppBar(title: Text(t('Тариф және баланс'))),
      body: RefreshIndicator(
        color: Gz.ink,
        onRefresh: () async {
          ref.invalidate(executorStatsStreamProvider);
          ref.invalidate(myExecutorProfileProvider);
          await Future.delayed(const Duration(milliseconds: 600));
        },
        child: statsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => ListView(children: [
            const SizedBox(height: 120),
            EmptyState(icon: Icons.wifi_off, title: errText(e)),
          ]),
          data: (s) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (ep != null && ep.docsReviewPending)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF3FF),
                      borderRadius: BorderRadius.circular(Gz.radius),
                      border: Border.all(color: Gz.blue.withValues(alpha: 0.3)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.hourglass_top, color: Gz.blue),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          t('Жаңартылған құжаттар модератор тексеруінде…'),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ]),
                  ),
                )
              else if (ep != null && ep.docsUpdateRequested)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(Gz.radius),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => ExecutorApplyScreen(existing: ep))),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF0F0),
                        borderRadius: BorderRadius.circular(Gz.radius),
                        border: Border.all(color: Gz.red.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.assignment_late, color: Gz.red),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(t('Құжаттарды жаңарту қажет'),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14.5)),
                                Text(
                                  ep.docsUpdateComment?.isNotEmpty == true
                                      ? ep.docsUpdateComment!
                                      : t('Модератор құжаттарыңызды жаңартуды сұрады.'),
                                  style: const TextStyle(
                                      color: Gz.textSecondary, fontSize: 12.5),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, color: Gz.red),
                        ],
                      ),
                    ),
                  ),
                ),
              // Баланс hero-картасы
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: Gz.heroGradient,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: Gz.cardShadow,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(t('Баланс'),
                            style: const TextStyle(
                                color: Colors.white60, fontSize: 13)),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                s.hasTariff
                                    ? Icons.check_circle
                                    : Icons.remove_circle_outline,
                                size: 13,
                                color: s.hasTariff
                                    ? const Color(0xFF4ADE80)
                                    : Colors.white38,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                s.hasTariff ? t('Тариф белсенді') : t('Тариф жоқ'),
                                style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: s.hasTariff
                                        ? const Color(0xFF4ADE80)
                                        : Colors.white38),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(fmtT(s.balance),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5)),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48)),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const BalanceScreen()),
                      ),
                      icon: const Icon(Icons.add),
                      label: Text(t('Баланс толтыру')),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Text(t('Тарифтер'),
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 17)),
                  const Spacer(),
                  if (s.isNight)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Gz.night.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.nightlight_round,
                              size: 14, color: Gz.night),
                          const SizedBox(width: 4),
                          Text(t('Түнгі баға'),
                              style: const TextStyle(
                                  color: Gz.night,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12)),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              if (s.trialActive)
                _TrialBanner(trialUntil: s.trialUntil),
              const SizedBox(height: 4),
              Text(
                t('Тариф = 1 ауысым (12 сағат: 08:00–20:00 не 20:00–08:00), сол '
                        'ауысымда 10 заказға дейін. Ауысым бітсе не 10 заказ алсаңыз — '
                        'тариф жабылады, қайтадан сатып аласыз.') +
                    (s.isNight ? '\n${t('Қазір түнгі баға (20:00–08:00).')}' : ''),
                style: const TextStyle(color: Gz.textSecondary, fontSize: 12.5),
              ),
              const SizedBox(height: 12),
              _TariffCard(
                title: t('Қарапайым тариф'),
                color: Gz.blue,
                icon: Icons.local_shipping_outlined,
                description:
                    t('1 ауысым · 10 заказға дейін. Клиент бағасын өзі қояды — сіз '
                        'келісесіз немесе өз бағаңызды ұсынасыз.'),
                price: s.priceSimple,
                active: s.simpleActive,
                ordersLeft: s.simpleLeft,
                until: s.simpleUntil,
                onBuy: () => _buy(context, ref, 'simple', s.priceSimple),
              ),
              const SizedBox(height: 10),
              _TariffCard(
                title: 'VIP ${t('тариф')}',
                color: Gz.violet,
                icon: Icons.workspace_premium_outlined,
                description:
                    t('1 ауысым · 10 заказға дейін. Жұмыс тәртібі Простоймен '
                        'бірдей — клиент бағасын өзі қояды. Премиум деңгей.'),
                price: s.priceVip,
                active: s.vipActive,
                ordersLeft: s.vipLeft,
                until: s.vipUntil,
                onBuy: () => _buy(context, ref, 'vip', s.priceVip),
              ),
              const SizedBox(height: 10),
              Text(
                t('Простой мен VIP — бөлек тарифтер. Әрқайсысының ауысымы да, '
                    '10 заказ лимиті де өз тұсында саналады.'),
                style: const TextStyle(color: Gz.textSecondary, fontSize: 12.5),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _buy(
      BuildContext context, WidgetRef ref, String kind, int price) async {
    final isVip = kind == 'vip';
    final ok = await confirmDialog(
      context,
      title: isVip ? 'VIP ${t('тариф')}' : t('Қарапайым тариф'),
      message: '${t('1 ауысым (12 сағат), 10 заказға дейін:')} ${fmtT(price)}.\n'
          '${t('Баланстан шешіледі. Жалғастырамыз ба?')}',
      confirmLabel: t('Иә, сатып аламын'),
      confirmColor: isVip ? Gz.violet : Gz.blue,
      icon: isVip
          ? Icons.workspace_premium_outlined
          : Icons.local_shipping_outlined,
    );
    if (!ok || !context.mounted) return;
    try {
      await Repo.buyTariff(kind);
      ref.invalidate(executorStatsStreamProvider);
      ref.invalidate(executorFeedStreamProvider);
      if (context.mounted) {
        showSnack(context, t('Тариф қосылды — ауысым басталды, 10 заказға дейін! 🚚'));
      }
    } catch (e) {
      if (context.mounted) showSnack(context, errText(e), error: true);
    }
  }
}

/// Тегін триал баннері (§7): расталған соң 24 сағат шексіз Простой заказ.
class _TrialBanner extends StatelessWidget {
  final DateTime? trialUntil;
  const _TrialBanner({required this.trialUntil});

  @override
  Widget build(BuildContext context) {
    if (trialUntil == null || !trialUntil!.isAfter(DateTime.now())) {
      return const SizedBox.shrink();
    }
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Gz.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.card_giftcard, size: 18, color: Gz.green),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${t('Тегін кезең белсенді —')} ${fmtTime(trialUntil)} '
              '${t('дейін шексіз Простой заказ')}',
              style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                  color: Gz.green),
            ),
          ),
        ],
      ),
    );
  }
}

class _TariffCard extends StatelessWidget {
  final String title;
  final Color color;
  final IconData icon;
  final String description;
  final int price;
  final bool active;
  final int ordersLeft;
  final DateTime? until;
  final VoidCallback onBuy;

  const _TariffCard({
    required this.title,
    required this.color,
    required this.icon,
    required this.description,
    required this.price,
    required this.active,
    required this.ordersLeft,
    required this.until,
    required this.onBuy,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: active
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  color.withValues(alpha: 0.06),
                  Gz.surface,
                ],
              )
            : null,
        color: active ? null : Gz.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: active ? color : Gz.border, width: active ? 1.8 : 1.2),
        boxShadow: active ? Gz.cardShadow : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 16)),
              ),
              if (active)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Gz.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    t('Белсенді'),
                    style: const TextStyle(
                        color: Gz.green,
                        fontWeight: FontWeight.w700,
                        fontSize: 12),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(description,
              style:
                  const TextStyle(color: Gz.textSecondary, fontSize: 13)),
          const SizedBox(height: 12),
          // Белсенді болса — қайта сатуға болмайды (ауысым бітсін не 10 заказ
          // бітсін). Оның орнына қалған заказ + ауысым соңы көрсетіледі.
          if (active)
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.confirmation_number_outlined,
                      size: 18, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${t('Қалған заказ:')} $ordersLeft / 10',
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13.5,
                                color: color)),
                        if (until != null)
                          Text('${t('Ауысым')} ${fmtTime(until)} ${t('дейін')}',
                              style: const TextStyle(
                                  color: Gz.textSecondary, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(46),
                shadowColor: color.withValues(alpha: 0.4),
              ),
              onPressed: onBuy,
              child: Text('${t('Сатып алу')} · ${fmtT(price)}'),
            ),
        ],
      ),
    );
  }
}
