import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/lang.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';

/// Табыс экраны: бүгін / ай / барлығы + кезең талдауы (күндік график,
/// заказ саны, орташа заказ, тарифке кеткені, ТАЗА табыс) + тарих.
class EarningsScreen extends ConsumerStatefulWidget {
  const EarningsScreen({super.key});

  @override
  ConsumerState<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends ConsumerState<EarningsScreen> {
  int _days = 7;
  late Future<_Period> _period = _loadPeriod();
  late Future<List<Map<String, dynamic>>> _history = Repo.myEarnings();

  Future<_Period> _loadPeriod() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: _days - 1));
    final rows = await Repo.myEarningsSince(start);
    final spend = await Repo.myTariffSpendSince(start);
    final byDay = <String, int>{};
    for (var i = 0; i < _days; i++) {
      final d = start.add(Duration(days: i));
      byDay[_key(d)] = 0;
    }
    var total = 0;
    for (final r in rows) {
      final at = DateTime.tryParse(r['created_at'] as String? ?? '')?.toLocal();
      if (at == null) continue;
      final amount = ((r['amount'] as num?) ?? 0).toInt();
      total += amount;
      final k = _key(at);
      if (byDay.containsKey(k)) byDay[k] = byDay[k]! + amount;
    }
    return _Period(
      days: [
        for (final e in byDay.entries) {'day': e.key, 'earned': e.value},
      ],
      total: total,
      count: rows.length,
      tariffSpend: spend,
    );
  }

  static String _key(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';

  Future<void> _refresh() async {
    ref.invalidate(executorStatsStreamProvider);
    setState(() {
      _period = _loadPeriod();
      _history = Repo.myEarnings();
    });
    await _period;
  }

  @override
  Widget build(BuildContext context) {
    final statsAsync = ref.watch(executorStatsStreamProvider);
    return Scaffold(
      appBar: AppBar(title: Text(t('Табыс'))),
      body: RefreshIndicator(
        color: Gz.ink,
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (statsAsync.value case final s?) ...[
              Row(
                children: [
                  Expanded(
                    child: StatTile(
                      label: t('Бүгін'),
                      value: fmtT(s.today),
                      color: Gz.green,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: StatTile(
                      label: t('Осы ай'),
                      value: fmtT(s.month),
                      color: Gz.blue,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: StatTile(
                      label: t('Барлығы'),
                      value: fmtCompactT(s.totalEarned),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
            ],
            Row(
              children: [
                Expanded(child: SectionTitle(t('Талдау'))),
                for (final d in const [7, 30])
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: ChoiceChip(
                      label: Text('$d ${t('күн')}'),
                      selected: _days == d,
                      onSelected: (_) => setState(() {
                        _days = d;
                        _period = _loadPeriod();
                      }),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            FutureBuilder<_Period>(
              future: _period,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final p = snap.data;
                if (p == null) {
                  return LoadErrorState(
                    onRetry: () => setState(() => _period = _loadPeriod()),
                  );
                }
                final net = p.total - p.tariffSpend;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    GzBarChart(
                      title: t('Күндік табыс'),
                      rows: p.days,
                      series: [ChartSeries('earned', t('Табыс'), Gz.yellowDeep)],
                      valueOf: (r, k) => (r[k] as int?) ?? 0,
                      format: (v) => fmtCompactT(v),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: StatTile(
                            label: t('Заказ'),
                            value: '${p.count}',
                            icon: Icons.local_shipping_outlined,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: StatTile(
                            label: t('Орташа заказ'),
                            value: p.count == 0
                                ? '—'
                                : fmtT((p.total / p.count).round()),
                            icon: Icons.functions_rounded,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: StatTile(
                            label: t('Тарифке кетті'),
                            value: fmtT(p.tariffSpend),
                            icon: Icons.confirmation_number_outlined,
                            color: Gz.danger,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: StatTile(
                            label: t('Таза табыс'),
                            value: fmtT(net),
                            icon: Icons.savings_outlined,
                            color: net >= 0 ? Gz.success : Gz.danger,
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            Text(
              t('Табыс — аяқталған заказдардың келісілген бағасы. '
                  'Төлемді клиенттен тікелей аласыз; бұл сома балансқа қосылмайды.'),
              style: Gz.caption,
            ),
            const SizedBox(height: 18),
            SectionTitle(t('Тарих')),
            const SizedBox(height: 8),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _history,
              builder: (context, snap) {
                final rows = snap.data ?? [];
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (rows.isEmpty) {
                  return SectionCard(
                    child: Text(
                      t('Аяқталған заказ әзірге жоқ.'),
                      style: Gz.bodyMuted,
                    ),
                  );
                }
                return SectionCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 4,
                  ),
                  child: Column(
                    children: [
                      for (final r in rows)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const CircleAvatar(
                            backgroundColor: Gz.bg,
                            child: Icon(Icons.check, color: Gz.green),
                          ),
                          title: Text(
                            fmtT(r['amount'] as num?),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(
                            fmtDate(
                              DateTime.tryParse(r['created_at'] as String? ?? ''),
                            ),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _Period {
  final List<Map<String, dynamic>> days;
  final int total;
  final int count;
  final int tariffSpend;
  const _Period({
    required this.days,
    required this.total,
    required this.count,
    required this.tariffSpend,
  });
}
