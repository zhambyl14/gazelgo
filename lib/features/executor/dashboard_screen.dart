import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import '../auth/executor_apply_screen.dart';
import 'balance_screen.dart';

/// Орындаушының басты экраны: баланс, табыс, тарифтер.
class ExecutorDashboardScreen extends ConsumerWidget {
  const ExecutorDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(executorStatsStreamProvider);
    final ep = ref.watch(myExecutorProfileProvider).value;

    return Scaffold(
      appBar: AppBar(title: const GazelGoLogo(size: 22)),
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
                    child: const Row(children: [
                      Icon(Icons.hourglass_top, color: Gz.blue),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Жаңартылған құжаттар модератор тексеруінде…',
                          style: TextStyle(fontWeight: FontWeight.w700),
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
                                const Text('Құжаттарды жаңарту қажет',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14.5)),
                                Text(
                                  ep.docsUpdateComment?.isNotEmpty == true
                                      ? ep.docsUpdateComment!
                                      : 'Модератор құжаттарыңызды жаңартуды сұрады.',
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
              // Баланс картасы
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Gz.ink,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Баланс',
                        style:
                            TextStyle(color: Colors.white60, fontSize: 13)),
                    const SizedBox(height: 4),
                    Text(fmtT(s.balance),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 30,
                            fontWeight: FontWeight.w900)),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(46)),
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const BalanceScreen()),
                            ),
                            icon: const Icon(Icons.add),
                            label: const Text('Толтыру'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Табыс жолағы
              Row(
                children: [
                  Expanded(
                      child: _statTile('Бүгінгі табыс', fmtT(s.today))),
                  const SizedBox(width: 10),
                  Expanded(
                      child: _statTile('Айлық табыс', fmtT(s.month))),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Text('Тарифтер',
                      style: TextStyle(
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
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.nightlight_round,
                              size: 14, color: Gz.night),
                          SizedBox(width: 4),
                          Text('Түнгі тариф −50%',
                              style: TextStyle(
                                  color: Gz.night,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12)),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Смена: күндіз 08:00–20:00, түнде 20:00–08:00. '
                'Тарифке кірген соң смена соңына дейін заказ қабылдайсыз.',
                style: TextStyle(color: Gz.textSecondary, fontSize: 12.5),
              ),
              const SizedBox(height: 12),
              _TariffCard(
                title: 'Қарапайым тариф',
                color: Gz.blue,
                icon: Icons.gavel,
                description:
                    'Клиенттер бағасын өзі қояды — сіз келісесіз немесе өз бағаңызды ұсынасыз.',
                price: s.priceSimple,
                activeUntil: s.simpleUntil,
                onBuy: () => _buy(context, ref, 'simple', s.priceSimple),
              ),
              const SizedBox(height: 10),
              _TariffCard(
                title: 'VIP тариф',
                color: Gz.violet,
                icon: Icons.flash_on,
                description:
                    'Жедел заказдар тікелей сізге түседі. Бағаны платформа қояды. Жауапқа 10 секунд.',
                price: s.priceVip,
                activeUntil: s.vipUntil,
                onBuy: () => _buy(context, ref, 'vip', s.priceVip),
              ),
              const SizedBox(height: 10),
              const Text(
                'Екі тарифті қатар қосуға болады, бірақ бір уақытта тек бір заказ орындайсыз.',
                style: TextStyle(color: Gz.textSecondary, fontSize: 12.5),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statTile(String label, String value) {
    return SectionCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style:
                  const TextStyle(color: Gz.textSecondary, fontSize: 12.5)),
          const SizedBox(height: 4),
          Text(value,
              style:
                  const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  Future<void> _buy(
      BuildContext context, WidgetRef ref, String kind, int price) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(kind == 'simple' ? 'Қарапайым тариф' : 'VIP тариф'),
        content: Text(
            'Смена соңына дейін доступ: ${fmtT(price)}.\nБаланстан шешіледі. Жалғастырамыз ба?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Жоқ')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Иә, кіремін')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Repo.buyTariff(kind);
      ref.invalidate(executorStatsStreamProvider);
      if (context.mounted) {
        showSnack(context, 'Тариф қосылды! Линиядасыз 🚚');
      }
    } catch (e) {
      if (context.mounted) showSnack(context, errText(e), error: true);
    }
  }
}

class _TariffCard extends StatelessWidget {
  final String title;
  final Color color;
  final IconData icon;
  final String description;
  final int price;
  final DateTime? activeUntil;
  final VoidCallback onBuy;

  const _TariffCard({
    required this.title,
    required this.color,
    required this.icon,
    required this.description,
    required this.price,
    required this.activeUntil,
    required this.onBuy,
  });

  @override
  Widget build(BuildContext context) {
    final active =
        activeUntil != null && activeUntil!.isAfter(DateTime.now());
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Gz.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: active ? color : Gz.border, width: active ? 1.8 : 1.2),
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
                    'Линияда · ${fmtTime(activeUntil)} дейін',
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
          if (!active)
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(46),
              ),
              onPressed: onBuy,
              child: Text('Кіру · ${fmtT(price)}'),
            ),
        ],
      ),
    );
  }
}
