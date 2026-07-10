import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import 'order_admin.dart';
import 'trust_actions.dart';

/// Модератор «Хабарламалар» табы: «Күдікті жүк туралы хабарлау» арқылы
/// түскен барлық жазбалар (0021/0024) — ашықтар бірінші, қаралғандар соңында.
/// Әр жазбада хабарланған тараптың сенім деңгейін көріп, дереу әрекет
/// ете алады (балл түзету, блоктау, заказды ашу).
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<OrderReport>>(
      stream: Repo.openReportsStream(),
      builder: (context, snap) {
        final all = snap.data ?? const <OrderReport>[];
        if (snap.connectionState == ConnectionState.waiting && all.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (all.isEmpty) {
          return const EmptyState(
            icon: Icons.shield_outlined,
            title: 'Хабарлама жоқ',
            subtitle: 'Күдікті жүк туралы хабарламалар осында көрінеді.',
          );
        }
        final open = all.where((r) => r.status == 'open').toList();
        final rest = all.where((r) => r.status != 'open').toList();
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (open.isNotEmpty) ...[
              _SectionLabel('Ашық (${open.length})'),
              for (final r in open) ...[
                _ReportTile(report: r),
                const SizedBox(height: 8),
              ],
            ],
            if (rest.isNotEmpty) ...[
              const SizedBox(height: 8),
              const _SectionLabel('Қаралған'),
              for (final r in rest.take(30)) ...[
                _ReportTile(report: r),
                const SizedBox(height: 8),
              ],
            ],
          ],
        );
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
        child: Text(text,
            style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: Gz.textSecondary)),
      );
}

class _ReportTile extends StatefulWidget {
  final OrderReport report;
  const _ReportTile({required this.report});

  @override
  State<_ReportTile> createState() => _ReportTileState();
}

class _ReportTileState extends State<_ReportTile> {
  Order? _order;
  Profile? _reporter;
  Profile? _reported;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = widget.report;
    final o = await Repo.orderById(r.orderId);
    Profile? reporter, reported;
    if (o != null) {
      final reportedId = r.reporterRole == 'client' ? o.executorId : o.clientId;
      final res = await Future.wait([
        Repo.profileOf(r.reporterId),
        reportedId != null ? Repo.profileOf(reportedId) : Future.value(null),
      ]);
      reporter = res[0];
      reported = res[1];
    }
    if (mounted) {
      setState(() {
        _order = o;
        _reporter = reporter;
        _reported = reported;
        _loading = false;
      });
    }
  }

  Future<void> _setStatus(String status) async {
    try {
      await Repo.modSetReportStatus(widget.report.id, status);
      if (mounted) {
        showSnack(context,
            status == 'dismissed' ? 'Елеусіз қалдырылды' : 'Қаралды деп белгіленді');
      }
    } catch (e) {
      if (mounted) showSnack(context, errText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.report;
    if (_loading) {
      return const SectionCard(
        padding: EdgeInsets.all(14),
        child: SizedBox(
            height: 40,
            child: Center(
                child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }
    final o = _order;
    return SectionCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  size: 18, color: r.status == 'open' ? Gz.red : Gz.textSecondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Хабарлаған: ${_reporter?.fullName ?? '…'} '
                  '(${r.reporterRole == 'client' ? 'клиент' : 'газелист'})',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
              Text(fmtDate(r.createdAt),
                  style: const TextStyle(fontSize: 11.5, color: Gz.textSecondary)),
            ],
          ),
          if (r.reason.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('«${r.reason}»',
                style: const TextStyle(
                    fontSize: 12.5,
                    color: Gz.textSecondary,
                    fontStyle: FontStyle.italic)),
          ],
          if (o != null) ...[
            const SizedBox(height: 10),
            Text(o.cargoDesc, style: const TextStyle(fontSize: 12.5)),
            const SizedBox(height: 4),
            Text('${o.fromDisplay} → ${o.toDisplay}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Gz.textSecondary)),
          ],
          if (_reported != null) ...[
            const SizedBox(height: 10),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => showTrustActionsSheet(context, _reported!,
                  onChanged: () => setState(() {})),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Gz.bg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('Хабарланған: ${_reported!.fullName}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 12.5)),
                    ),
                    TrustBadge(
                        score: _reported!.trustScore,
                        blocked: _reported!.isBlocked),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right,
                        size: 18, color: Gz.textSecondary),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              if (o != null)
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => showOrderAdminSheet(context, o.id),
                    child: const Text('Заказды ашу',
                        style: TextStyle(fontSize: 12.5)),
                  ),
                ),
              if (o != null && r.status == 'open') const SizedBox(width: 8),
              if (r.status == 'open')
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _setStatus('dismissed'),
                    child: const Text('Елеусіз қалдыру',
                        style: TextStyle(fontSize: 12.5)),
                  ),
                ),
              if (r.status == 'open') const SizedBox(width: 8),
              if (r.status == 'open')
                Expanded(
                  child: FilledButton(
                    onPressed: () => _setStatus('reviewed'),
                    child: const Text('Қаралды',
                        style: TextStyle(fontSize: 12.5)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
