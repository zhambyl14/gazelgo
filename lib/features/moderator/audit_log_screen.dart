import 'package:flutter/material.dart';

import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';

/// Модератор: ӘРЕКЕТТЕР ЖУРНАЛЫ (0082) — кім, қашан, не өзгертті
/// (өтінім, бұғат, баланс, толтыру, заказ статусы, баптау, хабарлама).
/// Бірнеше модератор жұмыс істегенде «мұны кім істеді?» деген сұраққа
/// жауап береді.
class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key});

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

enum _AuditFilter { all, people, money, orders, system }

class _AuditLogScreenState extends State<AuditLogScreen> {
  late Future<(List<Map<String, dynamic>>, Map<String, Profile>)> _future =
      _load();
  _AuditFilter _filter = _AuditFilter.all;

  Future<(List<Map<String, dynamic>>, Map<String, Profile>)> _load() async {
    final rows = await Repo.modAuditLog(limit: 300);
    final ids = <String>{
      for (final r in rows) ...[
        if (r['moderator_id'] is String) r['moderator_id'] as String,
        if (r['target_type'] == 'executor' || r['target_type'] == 'user')
          if (r['target_id'] is String) r['target_id'] as String,
      ],
    };
    final profiles = ids.isEmpty
        ? <String, Profile>{}
        : await Repo.profilesByIds(ids.toList());
    return (rows, profiles);
  }

  static _AuditFilter _groupOf(String action) {
    if (action.startsWith('topup_') || action == 'balance_adjust') {
      return _AuditFilter.money;
    }
    if (action == 'order_status') return _AuditFilter.orders;
    if (action == 'setting_change' || action == 'broadcast') {
      return _AuditFilter.system;
    }
    return _AuditFilter.people;
  }

  String _statusText(Object? s) => switch ('$s') {
    'pending' => t('Тексерісте'),
    'approved' => t('Расталды'),
    'rejected' => t('Қабылданбады'),
    'blocked' => t('Бұғатталған'),
    'searching' => t('Іздеуде'),
    'accepted' => t('Қабылданды'),
    'arrived' => t('Келді'),
    'loading' => t('Тиеу'),
    'in_transit' => t('Жолда'),
    'completed' => t('Аяқталды'),
    'cancelled' => t('Тоқтатылды'),
    'expired' => t('Мерзімі өтті'),
    final x => x,
  };

  (IconData, Color, String) _describe(Map<String, dynamic> r) {
    final action = r['action'] as String? ?? '';
    final d = r['details'] is Map
        ? Map<String, dynamic>.from(r['details'] as Map)
        : const <String, dynamic>{};
    String arrow() => '${_statusText(d['from'])} → ${_statusText(d['to'])}';
    return switch (action) {
      'executor_status' => (
        Icons.badge_outlined,
        Gz.blue,
        '${t('Орындаушы статусы')}: ${arrow()}',
      ),
      'docs_requested' => (
        Icons.upload_file_outlined,
        Gz.warning,
        t('Құжат қайта сұралды'),
      ),
      'topup_approved' => (
        Icons.account_balance_wallet_outlined,
        Gz.success,
        '${t('Толтыру мақұлданды')}: ${fmtT(d['amount'] as num?)}',
      ),
      'topup_rejected' => (
        Icons.account_balance_wallet_outlined,
        Gz.danger,
        '${t('Толтыру қабылданбады')}: ${fmtT(d['amount'] as num?)}',
      ),
      'balance_adjust' => (
        Icons.tune_rounded,
        Gz.yellowDeep,
        '${t('Баланс түзетілді')}: ${fmtT(d['amount'] as num?)}',
      ),
      'account_block' => (
        Icons.block_rounded,
        Gz.danger,
        t('Аккаунт бұғатталды'),
      ),
      'account_unblock' => (
        Icons.lock_open_rounded,
        Gz.success,
        t('Бұғат алынды'),
      ),
      'trust_score' => (
        Icons.shield_outlined,
        Gz.violet,
        '${t('Сенім деңгейі')}: ${d['from']} → ${d['to']}',
      ),
      'order_status' => (
        Icons.receipt_long_outlined,
        Gz.info,
        '${t('Заказ статусы')}: ${arrow()}',
      ),
      'setting_change' => (
        Icons.settings_outlined,
        Gz.textSecondary,
        '${t('Баптау өзгерді')}: ${r['target_id'] ?? ''}',
      ),
      'broadcast' => (
        Icons.campaign_outlined,
        Gz.yellowDeep,
        '${t('Жаппай хабарлама')}: ${d['recipients'] ?? 0} ${t('адам')}',
      ),
      _ => (Icons.history_rounded, Gz.textSecondary, action),
    };
  }

  String? _note(Map<String, dynamic> r) {
    final d = r['details'] is Map
        ? Map<String, dynamic>.from(r['details'] as Map)
        : const <String, dynamic>{};
    for (final k in const ['reason', 'comment', 'note', 'title']) {
      final v = d[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            children: [
              for (final f in _AuditFilter.values)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(switch (f) {
                      _AuditFilter.all => t('Барлығы'),
                      _AuditFilter.people => t('Адамдар'),
                      _AuditFilter.money => t('Қаржы'),
                      _AuditFilter.orders => t('Заказдар'),
                      _AuditFilter.system => t('Жүйе'),
                    }),
                    selected: _filter == f,
                    onSelected: (_) => setState(() => _filter = f),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return LoadErrorState(
                  onRetry: () => setState(() => _future = _load()),
                  subtitle: Repo.isMissingFunction(snap.error!)
                      ? t('Серверде 0082 миграциясы әлі қолданылмаған.')
                      : errText(snap.error!),
                );
              }
              final (rows, profiles) = snap.data!;
              final list = [
                for (final r in rows)
                  if (_filter == _AuditFilter.all ||
                      _groupOf(r['action'] as String? ?? '') == _filter)
                    r,
              ];
              if (list.isEmpty) {
                return EmptyState(
                  icon: Icons.history_rounded,
                  title: t('Журнал бос'),
                );
              }
              return RefreshIndicator(
                onRefresh: () async {
                  setState(() => _future = _load());
                  await _future;
                },
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final r = list[i];
                    final (icon, color, title) = _describe(r);
                    final mod =
                        profiles[r['moderator_id']]?.fullName ?? t('Жүйе');
                    final targetType = r['target_type'] as String?;
                    final targetId = r['target_id'] as String?;
                    final target = switch (targetType) {
                      'executor' ||
                      'user' => profiles[targetId]?.fullName ?? '',
                      'order' =>
                        targetId == null ? '' : '#${targetId.substring(0, 8)}',
                      _ => '',
                    };
                    final at = DateTime.tryParse(
                      r['created_at'] as String? ?? '',
                    )?.toLocal();
                    final note = _note(r);
                    return GzListRow(
                      icon: icon,
                      color: color,
                      title: title,
                      subtitle: [
                        if (target.isNotEmpty) target,
                        '${t('Кім')}: $mod · ${fmtDate(at)}',
                        ?note,
                      ].join('\n'),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
