import 'package:flutter/material.dart';

import '../../core/lang.dart';
import '../../core/theme.dart';
import '../widgets.dart';

/// Графиктің бір сериясы (атауы + түсі; мәні [GzBarChart.valueOf] арқылы).
class ChartSeries {
  final String key;
  final String label;
  final Color color;
  const ChartSeries(this.key, this.label, this.color);
}

/// Күндік бағандар картасы (бір не бірнеше жинақталған серия). Бағанды
/// басса — астында сол күннің мәні. Модератор панелі мен орындаушының
/// табыс беті бір үлгіні қолданады (dataviz ережелері: жіңішке баған,
/// үсті 4px дөңгелек, сегменттер арасы 2px, 2+ серияда аңыз).
class GzBarChart extends StatefulWidget {
  final String title;
  final List<Map<String, dynamic>> rows;
  final List<ChartSeries> series;
  final int Function(Map<String, dynamic> row, String key) valueOf;
  final String Function(int) format;

  const GzBarChart({
    super.key,
    required this.title,
    required this.rows,
    required this.series,
    required this.valueOf,
    required this.format,
  });

  @override
  State<GzBarChart> createState() => _GzBarChartState();
}

class _GzBarChartState extends State<GzBarChart> {
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
                                      () =>
                                          _selected = _selected == i ? null : i,
                                    ),
                                    child: Align(
                                      alignment: Alignment.bottomCenter,
                                      child: _bar(
                                        rows[i],
                                        max,
                                        barW,
                                        selected: _selected == i,
                                      ),
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
                ? Text(
                    t('Бағанды басыңыз — күннің мәні көрінеді'),
                    style: Gz.caption,
                  )
                : Wrap(
                    spacing: 14,
                    runSpacing: 4,
                    children: [
                      Text(
                        _dayLabel(sel),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
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

/// Үлкен соманы ықшам жазу: 1 284 000 → «1.3 млн ₸», 54 300 → «54.3 мың ₸».
String fmtCompactT(num v) {
  final a = v.abs();
  if (a >= 1000000) return '${(v / 1000000).toStringAsFixed(1)} ${t('млн')} ₸';
  if (a >= 10000) return '${(v / 1000).toStringAsFixed(1)} ${t('мың')} ₸';
  return fmtT(v);
}
