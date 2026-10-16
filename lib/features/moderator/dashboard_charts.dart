import 'package:flutter/material.dart';

import '../../core/lang.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';

/// Модератор Шолуындағы ГРАФИКТЕР мен ТҮСІМ (0080 `mod_dashboard_series`).
///
/// Құрамы (жоғарыдан төмен):
///   * кезең сүзгісі — бір қатарда, бәрінің үстінде (7 / 14 / 30 күн);
///   * көрсеткіштер (KPI) — заказ, аяқталу үлесі, айналым, тариф түсімі,
///     толтырулар, жаңа тіркелулер;
///   * «Күндік заказдар» — жинақталған бағандар (аяқталды / тоқтады / өзге),
///     аңыз (legend) әрдайым көрінеді — түс жалғыз белгі емес;
///   * «Тариф түсімі» — бір серия (аңызсыз, тақырыбы атайды);
///   * бағанды басса — сол күннің толық мәні (мәні бірінші, атауы кейін);
///   * «Кесте» — барлық мән графиксіз де қолжетімді.
///
/// Сервердегі функция әлі қолданылмаса — виджет мүлдем көрінбейді.
class DashboardCharts extends StatefulWidget {
  const DashboardCharts({super.key});

  @override
  State<DashboardCharts> createState() => _DashboardChartsState();
}

class _DashboardChartsState extends State<DashboardCharts> {
  int _days = 14;
  List<Map<String, dynamic>>? _rows;
  bool _loading = false;
  bool _unavailable = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await Repo.modDashboardSeries(_days);
      if (mounted) setState(() => _rows = rows);
    } catch (e) {
      if (mounted && Repo.isMissingFunction(e)) {
        setState(() => _unavailable = true);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static int _n(Map<String, dynamic> r, String k) {
    final v = r[k];
    return v is num ? v.toInt() : int.tryParse('$v') ?? 0;
  }

  int _sum(String k) => (_rows ?? const []).fold(0, (a, r) => a + _n(r, k));

  @override
  Widget build(BuildContext context) {
    if (_unavailable) return const SizedBox.shrink();
    final rows = _rows;
    if (rows == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final created = _sum('created');
    final completed = _sum('completed');
    final rate = created == 0 ? 0 : (completed * 100 / created).round();

    return AnimatedOpacity(
      // Қайта жүктелгенде соңғы сурет СОЛҒЫНДАП тұрады — секіріс жоқ.
      opacity: _loading ? 0.5 : 1,
      duration: const Duration(milliseconds: 200),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (final d in const [7, 14, 30]) ...[
                ChoiceChip(
                  label: Text('$d ${t('күн')}'),
                  selected: _days == d,
                  onSelected: (_) {
                    if (_days == d) return;
                    _days = d;
                    _load();
                  },
                ),
                const SizedBox(width: 6),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  label: t('Заказ берілді'),
                  value: '$created',
                  hint: '$_days ${t('күнде')}',
                  icon: Icons.receipt_long_outlined,
                  color: Gz.violet,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(
                  label: t('Аяқталды'),
                  value: '$completed',
                  hint: '$rate% ${t('заказдың')}',
                  icon: Icons.check_circle_outline_rounded,
                  color: Gz.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  label: t('Айналым'),
                  value: fmtCompactT(_sum('gmv')),
                  hint: t('аяқталған заказдар сомасы'),
                  icon: Icons.swap_vert_rounded,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(
                  label: t('Тариф түсімі'),
                  value: fmtCompactT(_sum('tariffs')),
                  hint: '${_sum('tariff_count')} ${t('ауысым сатылды')}',
                  icon: Icons.bolt_rounded,
                  color: Gz.yellowDeep,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  label: t('Толтырулар'),
                  value: fmtCompactT(_sum('topups')),
                  hint: t('расталған'),
                  icon: Icons.account_balance_wallet_outlined,
                  color: Gz.blue,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(
                  label: t('Жаңа тіркелу'),
                  value: '${_sum('new_clients') + _sum('new_executors')}',
                  hint: '${_sum('new_clients')} ${t('клиент')} · '
                      '${_sum('new_executors')} ${t('орындаушы')}',
                  icon: Icons.person_add_alt_1_outlined,
                  color: Gz.blue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          GzBarChart(
            title: t('Күндік заказдар'),
            rows: rows,
            series: [
              ChartSeries('completed', t('Аяқталды'), Gz.green),
              ChartSeries('cancelled', t('Тоқтады'), Gz.red),
              ChartSeries('other', t('Өзге (белсенді, іздеуде)'), Gz.disabledBg),
            ],
            valueOf: (r, key) => switch (key) {
              'other' => (_n(r, 'created') - _n(r, 'completed') - _n(r, 'cancelled'))
                  .clamp(0, 1 << 30),
              _ => _n(r, key),
            },
            format: (v) => '$v',
          ),
          const SizedBox(height: 10),
          GzBarChart(
            title: t('Тариф түсімі, ₸'),
            rows: rows,
            series: [ChartSeries('tariffs', t('Тариф түсімі'), Gz.yellowDark)],
            valueOf: (r, key) => _n(r, key),
            format: fmtT,
          ),
          const SizedBox(height: 6),
          _TableView(rows: rows, n: _n),
        ],
      ),
    );
  }
}


/// Кесте — графиктегі әр мән графиксіз де оқылады (қолжетімділік).
class _TableView extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final int Function(Map<String, dynamic>, String) n;
  const _TableView({required this.rows, required this.n});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 4),
        title: Text(t('Кесте түрінде'), style: Gz.caption),
        children: [
          for (final r in rows.reversed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 52,
                    child: Text(
                      () {
                        final d = DateTime.tryParse('${r['day']}');
                        return d == null ? '' : '${two(d.day)}.${two(d.month)}';
                      }(),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '${n(r, 'created')} ${t('заказ')} · '
                      '${n(r, 'completed')} ${t('аяқт.')} · '
                      '${n(r, 'cancelled')} ${t('тоқт.')} · '
                      '${fmtT(n(r, 'tariffs'))}',
                      style: Gz.caption,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
