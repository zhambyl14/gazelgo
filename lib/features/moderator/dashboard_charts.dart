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
          _ChartCard(
            title: t('Күндік заказдар'),
            rows: rows,
            series: [
              _Series('completed', t('Аяқталды'), Gz.green),
              _Series('cancelled', t('Тоқтады'), Gz.red),
              _Series('other', t('Өзге (белсенді, іздеуде)'), Gz.disabledBg),
            ],
            valueOf: (r, key) => switch (key) {
              'other' => (_n(r, 'created') - _n(r, 'completed') - _n(r, 'cancelled'))
                  .clamp(0, 1 << 30),
              _ => _n(r, key),
            },
            format: (v) => '$v',
          ),
          const SizedBox(height: 10),
          _ChartCard(
            title: t('Тариф түсімі, ₸'),
            rows: rows,
            series: [_Series('tariffs', t('Тариф түсімі'), Gz.yellowDark)],
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

/// Үлкен соманы ықшам жазу: 1 284 000 → «1.3 млн ₸», 54 300 → «54.3 мың ₸».
String fmtCompactT(num v) {
  final a = v.abs();
  if (a >= 1000000) return '${(v / 1000000).toStringAsFixed(1)} ${t('млн')} ₸';
  if (a >= 10000) return '${(v / 1000).toStringAsFixed(1)} ${t('мың')} ₸';
  return fmtT(v);
}

class _Series {
  final String key;
  final String label;
  final Color color;
  const _Series(this.key, this.label, this.color);
}

/// Жинақталған бағандар картасы. Бағанды басса — астында сол күннің мәні.
class _ChartCard extends StatefulWidget {
  final String title;
  final List<Map<String, dynamic>> rows;
  final List<_Series> series;
  final int Function(Map<String, dynamic> row, String key) valueOf;
  final String Function(int) format;

  const _ChartCard({
    required this.title,
    required this.rows,
    required this.series,
    required this.valueOf,
    required this.format,
  });

  @override
  State<_ChartCard> createState() => _ChartCardState();
}

class _ChartCardState extends State<_ChartCard> {
  int? _selected;

  static const _chartHeight = 120.0;

  int _total(Map<String, dynamic> r) =>
      widget.series.fold(0, (a, s) => a + widget.valueOf(r, s.key));

  String _dayLabel(Map<String, dynamic> r) {
    final d = DateTime.tryParse('${r['day']}');
    return d == null ? '' : '${two(d.day)}.${two(d.month)}';
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.rows;
    final max = rows.fold<int>(1, (a, r) => _total(r) > a ? _total(r) : a);
    final sel = _selected == null || _selected! >= rows.length
        ? null
        : rows[_selected!];

    return SectionCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title, style: Gz.h3),
          // Аңыз — 2+ серия болса әрдайым (тек түске сенбеу үшін).
          if (widget.series.length > 1) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                for (final s in widget.series)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: s.color,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(s.label, style: Gz.caption),
                    ],
                  ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Y осінің жалғыз белгісі — ең үлкен мән (тап таза сан).
              SizedBox(
                width: 44,
                height: _chartHeight,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Text(
                    widget.format(max),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Gz.caption,
                  ),
                ),
              ),
              Expanded(
                child: SizedBox(
                  height: _chartHeight,
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final slot = c.maxWidth / rows.length;
                      final barW = (slot * 0.62).clamp(3.0, 24.0);
                      return Stack(
                        children: [
                          // Жоғарғы жіңішке тор сызығы (ең үлкен мән деңгейі).
                          const Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: Divider(height: 1, color: Gz.border),
                          ),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              for (var i = 0; i < rows.length; i++)
                                Expanded(
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () => setState(
                                      () => _selected = _selected == i ? null : i,
                                    ),
                                    child: Align(
                                      alignment: Alignment.bottomCenter,
                                      child: _bar(rows[i], max, barW,
                                          selected: _selected == i),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
          // Негіз (baseline) — жалғыз, жіңішке.
          const Padding(
            padding: EdgeInsets.only(left: 44),
            child: Divider(height: 1, thickness: 1, color: Gz.border),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 44),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_dayLabel(rows.first), style: Gz.caption),
                if (rows.length > 2)
                  Text(_dayLabel(rows[rows.length ~/ 2]), style: Gz.caption),
                Text(_dayLabel(rows.last), style: Gz.caption),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Таңдалған күннің мәні: МӘНІ бірінші (қою), атауы кейін.
          AnimatedSize(
            duration: const Duration(milliseconds: 160),
            child: sel == null
                ? Text(t('Бағанды басыңыз — күннің мәні көрінеді'),
                    style: Gz.caption)
                : Wrap(
                    spacing: 14,
                    runSpacing: 4,
                    children: [
                      Text(_dayLabel(sel),
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w800)),
                      for (final s in widget.series)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(width: 10, height: 2, color: s.color),
                            const SizedBox(width: 5),
                            Text(
                              widget.format(widget.valueOf(sel, s.key)),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(s.label, style: Gz.caption),
                          ],
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// Бір күннің бағаны: сегменттер арасы 2px «бос» (беттің түсі),
  /// үстінгі ұшы 4px дөңгелек, негізі тік.
  Widget _bar(
    Map<String, dynamic> r,
    int max,
    double width, {
    required bool selected,
  }) {
    final parts = <Widget>[];
    // Төменнен жоғары: серия реті — бірінші серия негізде.
    for (final s in widget.series.reversed) {
      final v = widget.valueOf(r, s.key);
      if (v <= 0) continue;
      final h = (v / max) * (_chartHeight - 2);
      if (parts.isNotEmpty) parts.add(const SizedBox(height: 2));
      parts.add(
        Container(
          height: h < 2 ? 2 : h,
          color: selected ? Color.lerp(s.color, Gz.ink, 0.12) : s.color,
        ),
      );
    }
    if (parts.isEmpty) return SizedBox(width: width, height: 0);
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
      child: SizedBox(
        width: width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.end,
          children: parts,
        ),
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
