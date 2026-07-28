import 'package:flutter/material.dart';

import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import '../board/listing_card.dart' show listingKindLabel, listingKindColor;
import 'trust_actions.dart';

/// Хабарландыруға түскен шағымдар (0044).
///
/// Бұрын шағым қолдау чатына жай МӘТІН болып түсетін де, модератор ары қарай
/// ештеңе істей алмайтын. Енді әр шағымның ішінде хабарландырудың өзі
/// (мәтіні, қаласы, суреттері) тұрады әрі ЕКІ шешім бар:
///
///   «Хабарландыруды өшіру» — жазба біржола жойылады, суреттері тазалау
///                            кезегіне кетеді, сол хабарландыруға түскен
///                            БАРЛЫҚ ашық шағым бірден жабылады;
///   «Негізсіз»             — шағым елеусіз қалдырылады.
///
/// Автордың атын түртсе — сенім деңгейі парағы (балл түзету / блоктау).
class ListingReportsScreen extends StatefulWidget {
  const ListingReportsScreen({super.key});

  @override
  State<ListingReportsScreen> createState() => _ListingReportsScreenState();
}

class _ListingReportsScreenState extends State<ListingReportsScreen> {
  late Future<List<ListingReport>> _future = Repo.modListingReports('');

  void _reload() => setState(() => _future = Repo.modListingReports(''));

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ListingReport>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return EmptyState(icon: Icons.wifi_off, title: errText(snap.error!));
        }
        final all = snap.data ?? const <ListingReport>[];
        if (all.isEmpty) {
          return RefreshIndicator(
            color: Gz.ink,
            onRefresh: () async => _reload(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 80),
                EmptyState(
                  icon: Icons.flag_outlined,
                  title: t('Шағым жоқ'),
                  subtitle: t(
                    'Хабарландыруларға шағым түскенде осында көрінеді.',
                  ),
                ),
              ],
            ),
          );
        }
        final open = all.where((r) => r.isOpen).toList();
        final rest = all.where((r) => !r.isOpen).toList();
        return RefreshIndicator(
          color: Gz.ink,
          onRefresh: () async => _reload(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(12),
            children: [
              if (open.isNotEmpty) ...[
                _SectionLabel('${t('Ашық')} (${open.length})'),
                for (final r in open) ...[
                  _ReportCard(report: r, onChanged: _reload),
                  const SizedBox(height: 10),
                ],
              ],
              if (rest.isNotEmpty) ...[
                const SizedBox(height: 6),
                _SectionLabel(t('Қаралған')),
                for (final r in rest.take(30)) ...[
                  _ReportCard(report: r, onChanged: _reload),
                  const SizedBox(height: 10),
                ],
              ],
            ],
          ),
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
    child: Text(
      text,
      style: const TextStyle(
        fontWeight: FontWeight.w800,
        fontSize: 13,
        color: Gz.textSecondary,
      ),
    ),
  );
}

class _ReportCard extends StatefulWidget {
  final ListingReport report;
  final VoidCallback onChanged;
  const _ReportCard({required this.report, required this.onChanged});

  @override
  State<_ReportCard> createState() => _ReportCardState();
}

class _ReportCardState extends State<_ReportCard> {
  bool _busy = false;

  Future<void> _resolve(String action) async {
    final r = widget.report;
    if (action == 'delete') {
      final ok = await confirmDialog(
        context,
        title: t('Хабарландыруды өшіру'),
        message: t(
          'Хабарландыру мен оның суреттері біржола жойылады. Осы '
          'хабарландыруға түскен барлық шағым жабылады.',
        ),
        confirmLabel: t('Өшіру'),
        confirmColor: Gz.red,
        icon: Icons.delete_forever_outlined,
      );
      if (!ok || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      await Repo.modResolveListingReport(r.id, action);
      widget.onChanged();
      if (mounted) {
        showSnack(
          context,
          action == 'delete'
              ? t('Хабарландыру өшірілді')
              : t('Шағым негізсіз деп жабылды'),
        );
      }
    } catch (e) {
      if (mounted) showSnack(context, errText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openAuthor() async {
    final id = widget.report.authorId;
    if (id == null) return;
    final p = await Repo.profileOf(id);
    if (p == null || !mounted) return;
    await showTrustActionsSheet(context, p, onChanged: widget.onChanged);
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.report;
    return SectionCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---- кім шағымданды ----
          Row(
            children: [
              Icon(
                Icons.flag,
                size: 18,
                color: r.isOpen ? Gz.red : Gz.textSecondary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${t('Шағымдаған:')} ${r.reporterName} '
                  '(${r.reporterRole == 'executor' ? t('орындаушы') : t('клиент')})',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              Text(
                fmtDate(r.createdAt),
                style: const TextStyle(
                  fontSize: 11.5,
                  color: Gz.textSecondary,
                ),
              ),
            ],
          ),
          if (r.reason.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '«${r.reason}»',
              style: const TextStyle(
                fontSize: 12.5,
                color: Gz.textSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],

          // ---- шағымданған хабарландырудың өзі ----
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Gz.bg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: listingKindColor(r.kind),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        listingKindLabel(r.kind),
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${r.vehicleType.label} · ${r.city}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: Gz.textSecondary,
                        ),
                      ),
                    ),
                    if (!r.listingAlive)
                      Text(
                        t('өшірілген'),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Gz.textSecondary,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  r.body,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, height: 1.35),
                ),
                // Суреттер тек хабарландыру ТІРІ тұрғанда көрсетіледі:
                // өшкен соң файлдар Storage-тан тазаланады.
                if (r.listingAlive && r.photos.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 66,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: r.photos.length,
                      separatorBuilder: (_, i) => const SizedBox(width: 6),
                      itemBuilder: (_, i) => _Photo(path: r.photos[i]),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // ---- автор (түртсе — сенім деңгейі / блоктау) ----
          const SizedBox(height: 10),
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: r.authorId == null ? null : _openAuthor,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Gz.bg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${t('Автор:')} ${r.authorName} '
                      '(${r.authorRole == 'executor' ? t('орындаушы') : t('клиент')})',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                  if (r.authorBlocked)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Gz.red.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        t('Бұғатталған'),
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: Gz.red,
                        ),
                      ),
                    ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: Gz.textSecondary,
                  ),
                ],
              ),
            ),
          ),

          // Бір хабарландыруға бірнеше адам шағымданса — бұл маңызды белгі.
          if (r.reportsTotal > 1) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.people_alt_outlined, size: 15, color: Gz.red),
                const SizedBox(width: 6),
                Text(
                  '${t('Бұл хабарландыруға шағым саны:')} ${r.reportsTotal}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Gz.red,
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 12),
          if (r.isOpen)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : () => _resolve('keep'),
                    child: Text(
                      t('Негізсіз'),
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Gz.red,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _busy ? null : () => _resolve('delete'),
                    child: Text(
                      t('Хабарландыруды өшіру'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                Icon(
                  r.action == 'deleted'
                      ? Icons.delete_outline
                      : Icons.check_circle_outline,
                  size: 16,
                  color: r.action == 'deleted' ? Gz.red : Gz.green,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    r.action == 'deleted'
                        ? t('Хабарландыру өшірілді')
                        : t('Негізсіз деп жабылды'),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Gz.textSecondary,
                    ),
                  ),
                ),
                if (r.resolvedAt != null)
                  Text(
                    fmtDate(r.resolvedAt),
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Gz.textSecondary,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Photo extends StatelessWidget {
  final String path;
  const _Photo({required this.path});

  @override
  Widget build(BuildContext context) {
    const size = 66.0;
    final url = Repo.listingPhotoUrl(path);
    final px = (size * MediaQuery.devicePixelRatioOf(context)).round();
    return GestureDetector(
      onTap: () => showDialog(
        context: context,
        builder: (_) => Dialog(
          insetPadding: const EdgeInsets.all(10),
          child: InteractiveViewer(child: Image.network(url)),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          cacheWidth: px,
          cacheHeight: px,
          errorBuilder: (_, e, s) => Container(
            width: size,
            height: size,
            color: Gz.surface,
            child: const Icon(Icons.broken_image, color: Gz.textSecondary),
          ),
        ),
      ),
    );
  }
}
