import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/lang.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';

/// Табыс экраны: бүгінгі / айлық / жалпы + тарих.
class EarningsScreen extends ConsumerWidget {
  const EarningsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(executorStatsStreamProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t('Табыс'))),
      body: statsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => EmptyState(icon: Icons.wifi_off, title: errText(e)),
        data: (s) => RefreshIndicator(
          color: Gz.ink,
          onRefresh: () async {
            ref.invalidate(executorStatsStreamProvider);
            await Future.delayed(const Duration(milliseconds: 600));
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
            Row(
              children: [
                Expanded(child: _tile(t('Бүгін'), fmtT(s.today), Gz.green)),
                const SizedBox(width: 10),
                Expanded(child: _tile(t('Осы ай'), fmtT(s.month), Gz.blue)),
              ],
            ),
            const SizedBox(height: 10),
            _tile(t('Барлық уақытта'), fmtT(s.totalEarned), Gz.ink),
            const SizedBox(height: 8),
            Text(
              t('Табыс — аяқталған заказдардың келісілген бағасы. '
                  'Төлемді клиенттен тікелей аласыз; бұл сома балансқа қосылмайды.'),
              style: const TextStyle(color: Gz.textSecondary, fontSize: 12.5),
            ),
            const SizedBox(height: 18),
            Text(t('Тарих'),
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 8),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: Repo.myEarnings(),
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
                    child: Text(t('Аяқталған заказ әзірге жоқ.'),
                        style: const TextStyle(color: Gz.textSecondary)),
                  );
                }
                return SectionCard(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 4),
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
                            style: const TextStyle(
                                fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(
                            fmtDate(DateTime.tryParse(
                                r['created_at'] as String? ?? '')),
                            style: const TextStyle(fontSize: 12.5),
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
      ),
    );
  }

  Widget _tile(String label, String value, Color color) {
    return SectionCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: Gz.textSecondary, fontSize: 12.5)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w900, color: color)),
        ],
      ),
    );
  }
}
