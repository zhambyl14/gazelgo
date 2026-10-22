import 'package:flutter/material.dart';

import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import 'order_admin.dart';

int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

DateTime? _date(Object? v) => DateTime.tryParse('$v')?.toLocal();

/// Модератор Шолуы: ҚАЛА-ҚАЛА бойынша жағдай (0089 `mod_city_stats`) —
/// клиенттер, орындаушылар (линияда қаншасы), берілген заказдар және неше
/// адам заказ берді. Сервердегі функция әлі қолданылмаса — көрінбейді.
class CityStatsSection extends StatefulWidget {
  const CityStatsSection({super.key});

  @override
  State<CityStatsSection> createState() => _CityStatsSectionState();
}

class _CityStatsSectionState extends State<CityStatsSection> {
  int _days = 7;
  bool _all = false;
  List<Map<String, dynamic>>? _rows;
  bool _loading = true;
  bool _unavailable = false;
  String? _error;

  /// Кезең ауысқанда көне жауап жаңасын басып кетпесін.
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await Repo.modCityStats(_days);
      if (mounted && seq == _seq) setState(() => _rows = rows);
    } catch (e) {
      if (!mounted || seq != _seq) return;
      if (Repo.isMissingFunction(e)) {
        setState(() => _unavailable = true);
      } else {
        setState(() => _error = errText(e));
      }
    } finally {
      if (mounted && seq == _seq) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_unavailable) return const SizedBox.shrink();
    final rows = _rows ?? const <Map<String, dynamic>>[];
    final shown = _all ? rows : rows.take(8).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        SectionTitle(
          t('Қала бойынша'),
          subtitle: t(
            'Клиенттер, орындаушылар және заказдар. Клиенттің қаласы — '
            'соңғы заказының қаласы.',
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final (d, label) in <(int, String)>[
                (1, t('Бүгін')),
                (7, '7 ${t('күн')}'),
                (30, '30 ${t('күн')}'),
              ]) ...[
                ChoiceChip(
                  label: Text(label),
                  selected: _days == d,
                  onSelected: (_) {
                    _days = d;
                    _load();
                  },
                ),
                const SizedBox(width: 6),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (_error != null)
          LoadErrorState(onRetry: _load, subtitle: _error)
        else if (_loading && _rows == null)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (rows.isEmpty)
          SectionCard(child: Text(t('Дерек жоқ'), style: Gz.caption))
        else ...[
          for (final r in shown) ...[
            _CityCard(row: r),
            const SizedBox(height: 8),
          ],
          if (rows.length > 8)
            TextButton(
              onPressed: () => setState(() => _all = !_all),
              child: Text(
                _all
                    ? t('Жасыру')
                    : '${t('Барлық қала')} (${rows.length})',
              ),
            ),
        ],
      ],
    );
  }
}

class _CityCard extends StatelessWidget {
  final Map<String, dynamic> row;
  const _CityCard({required this.row});

  @override
  Widget build(BuildContext context) {
    final orders = _int(row['orders']);
    return SectionCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.location_city_outlined, size: 18, color: Gz.ink),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${row['city']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Gz.h3,
                ),
              ),
              Text(
                '$orders ${t('заказ')}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              InfoChip(
                icon: Icons.people_outline_rounded,
                color: Gz.blue,
                text: '${t('Клиент')}: ${_int(row['clients'])}',
              ),
              InfoChip(
                icon: Icons.shopping_bag_outlined,
                color: Gz.violet,
                text: '${t('Заказ берген')}: ${_int(row['customers'])}',
              ),
              InfoChip(
                icon: Icons.local_shipping_outlined,
                text:
                    '${t('Орындаушы')}: ${_int(row['approved'])}'
                    '/${_int(row['executors'])}',
              ),
              InfoChip(
                icon: Icons.wifi_rounded,
                color: Gz.green,
                text: '${t('Линияда')}: ${_int(row['on_line'])}',
              ),
              InfoChip(
                icon: Icons.check_circle_outline_rounded,
                color: Gz.green,
                text: '${t('Аяқталды')}: ${_int(row['completed'])}',
              ),
              InfoChip(
                icon: Icons.cancel_outlined,
                color: Gz.red,
                text: '${t('Тоқтады')}: ${_int(row['cancelled'])}',
              ),
              if (_int(row['active']) > 0)
                InfoChip(
                  icon: Icons.bolt_rounded,
                  color: Gz.yellowDeep,
                  text: '${t('Қазір жүр')}: ${_int(row['active'])}',
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// «Заказ статусын кім өзгертті» жолының мәтіні.
String _statusArrow(Map<String, dynamic> r) =>
    '${statusLabel('${r['from_status']}')} → ${statusLabel('${r['to_status']}')}';

String _whoLabel(Map<String, dynamic> r) {
  final name = (r['who'] as String?)?.trim();
  final role = r['is_staff'] == true ? t('қызметкер') : t('модератор');
  return name == null || name.isEmpty ? role : '$name · $role';
}

/// Шолу: ҚЫЗМЕТКЕР/МОДЕРАТОР заказ статусын өзгертсе — соңғы өзгерістер
/// тізімі (кім, қашан, қандай статустан қандайға). Басса — заказ ашылады.
class StatusChangesSection extends StatefulWidget {
  const StatusChangesSection({super.key});

  @override
  State<StatusChangesSection> createState() => _StatusChangesSectionState();
}

class _StatusChangesSectionState extends State<StatusChangesSection> {
  List<Map<String, dynamic>>? _rows;
  bool _unavailable = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await Repo.modStatusChanges(limit: 15);
      if (mounted) setState(() => _rows = rows);
    } catch (e) {
      if (mounted && Repo.isMissingFunction(e)) {
        setState(() => _unavailable = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_unavailable || _rows == null) return const SizedBox.shrink();
    final rows = _rows!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        SectionTitle(
          t('Статусты қолмен өзгерту'),
          subtitle: t(
            'Қолдау қызметкері не модератор заказды аяқтаса / тоқтатса / '
            'статусын ауыстырса — осында көрінеді',
          ),
        ),
        if (rows.isEmpty)
          SectionCard(
            child: Text(t('Әзірге өзгеріс жоқ'), style: Gz.caption),
          )
        else
          SectionCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) const Divider(height: 1, indent: 16),
                  _ChangeRow(row: rows[i], onChanged: _load),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _ChangeRow extends StatelessWidget {
  final Map<String, dynamic> row;
  final VoidCallback onChanged;
  const _ChangeRow({required this.row, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final orderId = '${row['order_id']}';
    final short = orderId.length >= 8 ? orderId.substring(0, 8) : orderId;
    final city = (row['from_city'] as String?)?.trim();
    return InkWell(
      onTap: () => showOrderAdminSheet(context, orderId, onChanged: onChanged),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '#$short · ${_statusArrow(row)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_whoLabel(row)}'
                    '${city == null || city.isEmpty ? '' : ' · $city'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Gz.caption,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(fmtDate(_date(row['at'])), style: Gz.caption),
            Icon(Icons.chevron_right_rounded, color: Gz.textTertiary),
          ],
        ),
      ),
    );
  }
}

/// Бір заказдың статус тарихы (заказ терезесінде): кім, қашан, не өзгертті.
/// Өзгеріс болмаса немесе сервер функциясы жоқ болса — көрінбейді.
class OrderStatusHistory extends StatelessWidget {
  final String orderId;
  const OrderStatusHistory({super.key, required this.orderId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: Repo.modStatusChanges(limit: 20, orderId: orderId),
      builder: (context, snap) {
        final rows = snap.data;
        if (rows == null || rows.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 14),
            SectionTitle(
              t('Статусты кім өзгертті'),
              padding: const EdgeInsets.only(bottom: 8),
            ),
            SectionCard(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Column(
                children: [
                  for (final r in rows)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _statusArrow(r),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(_whoLabel(r), style: Gz.caption),
                              ],
                            ),
                          ),
                          Text(fmtDate(_date(r['at'])), style: Gz.caption),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Орындаушы бетінде: КІМ тіркеді/қабылдады, кейін не өзгертті
/// (мәртебе, деректер, бұғат, баланс, құжат сұрау). 0089.
class ExecutorHistoryCard extends StatelessWidget {
  final String userId;
  final DateTime? createdAt;
  const ExecutorHistoryCard({super.key, required this.userId, this.createdAt});

  static String _status(Object? s) => switch ('$s') {
    'pending' => t('Күтуде'),
    'approved' => t('Расталған'),
    'rejected' => t('Қабылданбаған'),
    'blocked' => t('Бұғатталған'),
    final x => x,
  };

  String _describe(Map<String, dynamic> e) {
    final d = e['details'] is Map
        ? Map<String, dynamic>.from(e['details'] as Map)
        : const <String, dynamic>{};
    return switch ('${e['action']}') {
      'executor_status' =>
        '${_status(d['from'])} → ${_status(d['to'])}'
            '${(d['comment'] as String?)?.isNotEmpty == true ? ' · ${d['comment']}' : ''}',
      'executor_create' => t('Қолмен қосты'),
      'executor_update' => t('Деректерін өзгертті'),
      'executor_delete' => t('Жойды'),
      'executor_umay' => d['on'] == true
          ? t('Ұмай белгісін қойды')
          : t('Ұмай белгісін алды'),
      'docs_requested' => t('Құжат жаңартуды сұрады'),
      'balance_adjust' =>
        '${t('Баланс түзетті')}: ${_int(d['amount']) > 0 ? '+' : ''}${_int(d['amount'])} ₸',
      'account_block' => t('Аккаунтты бұғаттады'),
      'account_unblock' => t('Аккаунтты бұғаттан шығарды'),
      final a => a,
    };
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: Repo.modExecutorHistory(userId),
      builder: (context, snap) {
        final h = snap.data;
        if (h == null) return const SizedBox.shrink();
        final events = [
          for (final e in (h['events'] as List? ?? const []))
            Map<String, dynamic>.from(e as Map),
        ];
        final by = (h['moderated_by'] as String?)?.trim();
        final regAt = _date(h['registered_at']) ?? createdAt;
        final modAt = _date(h['moderated_at']);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionTitle(t('Тіркеу және қабылдау')),
                  InfoRow(t('Тіркелген'), fmtDate(regAt)),
                  InfoRow(
                    t('Соңғы шешім'),
                    by == null || by.isEmpty
                        ? '—'
                        : '$by · ${fmtDate(modAt)}',
                  ),
                  if (events.isNotEmpty) ...[
                    const Divider(height: 20),
                    for (final e in events)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _describe(e),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(_whoLabel(e), style: Gz.caption),
                                ],
                              ),
                            ),
                            Text(fmtDate(_date(e['at'])), style: Gz.caption),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
