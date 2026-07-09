import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import 'balance_screen.dart';
import 'dashboard_screen.dart';
import 'docs_banner.dart';
import 'feed_screen.dart';

/// Орындаушының басты беті — клиенттегідей бір экранды дизайн:
/// негізгі мазмұн = заказдар лентасы, жоғарыда шағын басқару жолағы
/// (баланс, линия/тариф) «бұрыштарда» тұрады. Табыс профильдің ішінде.
class ExecutorHomeScreen extends ConsumerWidget {
  const ExecutorHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(executorStatsStreamProvider).value;
    final ep = ref.watch(myExecutorProfileProvider).value;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // жоғарғы жолақ: лого + баланс
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 12, 8),
              child: Row(
                children: [
                  const GazelGoLogo(size: 20),
                  const Spacer(),
                  _BalancePill(
                    balance: s?.balance,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const BalanceScreen())),
                  ),
                ],
              ),
            ),
            // тариф басқару жолағы
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: _LineControlBar(stats: s),
            ),
            // модератордың құжат жаңарту хабары (басты бетте де)
            if (ep != null && (ep.docsUpdateRequested || ep.docsReviewPending))
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: ExecutorDocsBanner(ep: ep),
              ),
            // заказдар лентасы (негізгі мазмұн)
            const Expanded(child: ExecutorFeedBody()),
          ],
        ),
      ),
    );
  }
}

/// Балансты көрсететін шағын «таблетка» — түртсе, толтыру экраны ашылады.
class _BalancePill extends StatelessWidget {
  final int? balance;
  final VoidCallback onTap;
  const _BalancePill({required this.balance, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Gz.surface,
      elevation: 1.5,
      shadowColor: Colors.black26,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.account_balance_wallet_outlined,
                  size: 18, color: Gz.yellowDark),
              const SizedBox(width: 7),
              Text(balance == null ? '—' : fmtT(balance),
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 14)),
              const SizedBox(width: 4),
              const Icon(Icons.add, size: 16, color: Gz.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Линия статусы + жедел қосу/өшіру ауыстырғышы + тарифті басқару.
/// Тариф белсенді емес болса — «Тарифке кіру» шақыруы көрсетіледі.
class _LineControlBar extends ConsumerWidget {
  final ExecutorStats? stats;
  const _LineControlBar({required this.stats});

  void _openTariffs(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const ExecutorDashboardScreen()));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = stats;
    final hasTariff = s != null && s.hasTariff;

    // Тариф жоқ — тариф сатып алуға шақыру картасы
    if (!hasTariff) {
      return InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openTariffs(context),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          decoration: BoxDecoration(
            color: Gz.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Gz.border),
            boxShadow: Gz.cardShadow,
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Gz.yellow.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.bolt, color: Gz.yellowDark, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('Тарифіңіз жоқ',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 14.5)),
                    Text('Заказ қабылдау үшін тариф сатып алыңыз',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: Gz.textSecondary, fontSize: 12.5)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => _openTariffs(context),
                child: const Text('Кіру'),
              ),
            ],
          ),
        ),
      );
    }

    // Тариф белсенді — статус + басқару (линия/демалыс тумблері жоқ)
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: BoxDecoration(
        color: Gz.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Gz.green.withValues(alpha: 0.4)),
        boxShadow: Gz.cardShadow,
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Gz.green, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Тариф белсенді',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                        color: Gz.green)),
                Text(_tariffLabel(s),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Gz.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Тариф пен баланс',
            onPressed: () => _openTariffs(context),
            icon: const Icon(Icons.tune, color: Gz.ink),
          ),
        ],
      ),
    );
  }

  String _tariffLabel(ExecutorStats s) {
    final parts = <String>[];
    if (s.trialActive) parts.add('Тегін кезең');
    // Әр тариф өз лимитімен бөлек көрсетіледі (қосылмайды).
    if (s.simpleActive) parts.add('Простой ${s.simpleLeft}/10');
    if (s.vipActive) parts.add('VIP ${s.vipLeft}/10');
    if (parts.isEmpty) return 'Тариф жоқ';
    return parts.join(' · ');
  }
}
