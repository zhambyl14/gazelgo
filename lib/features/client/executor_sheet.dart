import 'package:flutter/material.dart';

import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';

/// Клиенттің таңдаулы/бұғатталған орындаушылары (0079) — заказ беті бір
/// рет жүктейді, терезелер өзгерткенде жаңартады.
class ExecutorPrefs {
  final bool available;
  final Set<String> favorites;
  final Set<String> blocks;
  const ExecutorPrefs({
    this.available = false,
    this.favorites = const {},
    this.blocks = const {},
  });

  static Future<ExecutorPrefs> load() async {
    if (!await Repo.executorPrefsAvailable()) return const ExecutorPrefs();
    final (fav, blk) = await Repo.myExecutorPrefs();
    return ExecutorPrefs(available: true, favorites: fav, blocks: blk);
  }

  String kindOf(String id) => favorites.contains(id)
      ? 'favorite'
      : (blocks.contains(id) ? 'block' : 'none');
}

/// Орындаушының қысқа профилі (ұсыныс таңдағанда не заказ барысында):
/// рейтинг, рейс саны, көлігі, ЖИІ АЙТЫЛАТЫН тегтер, соңғы пікірлер,
/// «❤ таңдаулы» / «бұғаттау». Қайтарады: жаңа күйі ('favorite' | 'block' |
/// 'none') не өзгермесе — null.
Future<String?> showExecutorSheet(
  BuildContext context, {
  required String executorId,
  required ExecutorPrefs prefs,
}) {
  return showGzSheet<String>(
    context,
    builder: (_) => _ExecutorSheet(executorId: executorId, prefs: prefs),
  );
}

class _ExecutorSheet extends StatefulWidget {
  final String executorId;
  final ExecutorPrefs prefs;
  const _ExecutorSheet({required this.executorId, required this.prefs});

  @override
  State<_ExecutorSheet> createState() => _ExecutorSheetState();
}

class _ExecutorSheetState extends State<_ExecutorSheet> {
  late final Future<
    (Profile?, ExecutorProfile?, Map<String, int>, List<Review>)
  >
  _data = _load();
  late String _kind = widget.prefs.kindOf(widget.executorId);
  bool _busy = false;

  Future<(Profile?, ExecutorProfile?, Map<String, int>, List<Review>)>
  _load() async {
    final id = widget.executorId;
    final res = await Future.wait([
      Repo.profileOf(id),
      Repo.executorProfileOf(id),
      Repo.userReviewTags(id),
      Repo.reviewsOf(id).catchError((_) => <Review>[]),
    ]);
    final reviews = [
      for (final r in res[3] as List<Review>)
        if (r.authorRole != 'executor' && r.comment.trim().isNotEmpty) r,
    ];
    return (
      res[0] as Profile?,
      res[1] as ExecutorProfile?,
      res[2] as Map<String, int>,
      reviews.take(3).toList(),
    );
  }

  Future<void> _set(String kind) async {
    if (kind == 'block') {
      final ok = await confirmDialog(
        context,
        title: t('Орындаушыға шағым қалдыру керек пе?'),
        message: t(
          'Бұл орындаушы тек сіздің заказдарыңызды көрмейді. Оның '
          'аккаунтына, рейтингіне және басқа клиенттердің заказдарына '
          'әсер етпейді. Кейін мәзірдегі «Менің орындаушыларым» '
          'бөлімінен алып тастауға болады.',
        ),
        confirmLabel: t('Шағым қалдыру'),
        confirmColor: Gz.red,
        icon: Icons.block_rounded,
      );
      if (!ok || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      await Repo.setExecutorPref(widget.executorId, kind);
      if (!mounted) return;
      setState(() => _kind = kind);
      showSnack(context, switch (kind) {
        'favorite' => t('Таңдаулыларға қосылды ❤'),
        'block' => t('Шағым қалдырылды'),
        _ => t('Тізімнен алынды'),
      });
      Navigator.pop(context, kind);
    } catch (e) {
      if (mounted) showSnack(context, errText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GzSheetBody(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: FutureBuilder(
          future: _data,
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final (p, ep, tags, reviews) = snap.data!;
            final sortedTags = tags.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value));
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      InitialsAvatar(
                        p?.fullName ?? '?',
                        radius: 30,
                        imageUrl: p?.avatarUrl,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    p?.fullName ?? t('Орындаушы'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Gz.h2,
                                  ),
                                ),
                                if (_kind == 'favorite') ...[
                                  const SizedBox(width: 6),
                                  Icon(
                                    Icons.favorite_rounded,
                                    color: Gz.red,
                                    size: 18,
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            RatingStars(
                              p?.ratingAs('executor') ?? 0,
                              count: p?.ratingCountAs('executor') ?? 0,
                              size: 14,
                            ),
                            if (ep != null)
                              Text(
                                ep.vehicleTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Gz.caption,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: StatTile(
                          label: t('Рейс'),
                          value: '${p?.tripsAs('executor') ?? 0}',
                          icon: Icons.local_shipping_outlined,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: StatTile(
                          label: t('Бағалар'),
                          value: '${p?.ratingCountAs('executor') ?? 0}',
                          icon: Icons.star_outline_rounded,
                        ),
                      ),
                    ],
                  ),
                  if (sortedTags.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    SectionTitle(t('Клиенттер жиі атайды')),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final e in sortedTags.take(6))
                          InfoChip(
                            icon: reviewTagOf(e.key)?.icon,
                            color: (reviewTagOf(e.key)?.positive ?? true)
                                ? Gz.success
                                : Gz.danger,
                            text: '${reviewTagLabel(e.key)} · ${e.value}',
                          ),
                      ],
                    ),
                  ],
                  if (reviews.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    SectionTitle(t('Соңғы пікірлер')),
                    const SizedBox(height: 6),
                    for (final r in reviews)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Gz.bg,
                            borderRadius: BorderRadius.circular(Gz.rSm),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              RatingStars(r.rating.toDouble(), size: 12),
                              const SizedBox(height: 4),
                              Text(r.comment, style: Gz.bodyMuted),
                            ],
                          ),
                        ),
                      ),
                  ],
                  if (widget.prefs.available) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Gz.red,
                              minimumSize: const Size.fromHeight(46),
                            ),
                            onPressed: _busy
                                ? null
                                : () => _set(
                                    _kind == 'favorite' ? 'none' : 'favorite',
                                  ),
                            icon: Icon(
                              _kind == 'favorite'
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              size: 18,
                            ),
                            label: Text(
                              _kind == 'favorite'
                                  ? t('Таңдаулыда')
                                  : t('Таңдаулыға қосу'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: Gz.textSecondary,
                              minimumSize: const Size.fromHeight(46),
                            ),
                            onPressed: _busy
                                ? null
                                : () =>
                                      _set(_kind == 'block' ? 'none' : 'block'),
                            icon: const Icon(Icons.block_rounded, size: 18),
                            label: Text(
                              _kind == 'block'
                                  ? t('Шағымды алу')
                                  : t('Шағым қалдыру'),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      t(
                        'Таңдаулы орындаушыға жаңа заказыңыз туралы бірінші '
                        'болып хабар барады.',
                      ),
                      textAlign: TextAlign.center,
                      style: Gz.caption,
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
