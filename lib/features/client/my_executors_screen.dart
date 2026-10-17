import 'package:flutter/material.dart';

import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import 'executor_sheet.dart';

/// Клиенттің «Менің орындаушыларым» (0079): ТАҢДАУЛЫЛАР (жаңа заказ
/// туралы оларға бірінші хабар барады) және БҰҒАТТАЛҒАНДАР (заказдарыңызды
/// көрмейді). Осы жерден тізімнен алып тастауға болады.
class MyExecutorsScreen extends StatefulWidget {
  const MyExecutorsScreen({super.key});

  @override
  State<MyExecutorsScreen> createState() => _MyExecutorsScreenState();
}

class _MyExecutorsScreenState extends State<MyExecutorsScreen> {
  late Future<(ExecutorPrefs, Map<String, Profile>)> _future = _load();

  Future<(ExecutorPrefs, Map<String, Profile>)> _load() async {
    final prefs = await ExecutorPrefs.load();
    final ids = {...prefs.favorites, ...prefs.blocks}.toList();
    final profiles = ids.isEmpty
        ? <String, Profile>{}
        : await Repo.profilesByIds(ids);
    return (prefs, profiles);
  }

  Future<void> _remove(String id, bool blocked) async {
    if (blocked) {
      final ok = await confirmDialog(
        context,
        title: t('Бұғаттан шығару керек пе?'),
        message: t('Бұл орындаушы сіздің заказдарыңызды қайта көреді.'),
        confirmLabel: t('Бұғаттан шығару'),
        icon: Icons.lock_open_rounded,
      );
      if (!ok || !mounted) return;
    }
    try {
      await Repo.setExecutorPref(id, 'none');
      if (!mounted) return;
      showSnack(context, t('Тізімнен алынды'));
      setState(() => _future = _load());
    } catch (e) {
      if (mounted) showSnack(context, errText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t('Менің орындаушыларым')),
          bottom: TabBar(
            tabs: [
              Tab(text: t('Таңдаулылар')),
              Tab(text: t('Бұғатталғандар')),
            ],
          ),
        ),
        body: FutureBuilder(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError || snap.data == null) {
              return LoadErrorState(
                onRetry: () => setState(() => _future = _load()),
              );
            }
            final (prefs, profiles) = snap.data!;
            if (!prefs.available) {
              return EmptyState(
                icon: Icons.favorite_border_rounded,
                title: t('Бұл мүмкіндік серверде әлі қосылмаған.'),
              );
            }
            Widget list(Set<String> ids, {required bool blocked}) {
              if (ids.isEmpty) {
                return EmptyState(
                  icon: blocked
                      ? Icons.block_rounded
                      : Icons.favorite_border_rounded,
                  title: blocked
                      ? t('Бұғатталған орындаушы жоқ')
                      : t('Таңдаулы орындаушы әзірге жоқ'),
                  subtitle: blocked
                      ? null
                      : t('Заказ аяқталған соң орындаушыны ❤ таңдаулыға '
                            'қосыңыз — жаңа заказыңыз туралы оған бірінші '
                            'болып хабар барады.'),
                );
              }
              return ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  for (final id in ids)
                    _ExecutorRow(
                      profile: profiles[id],
                      blocked: blocked,
                      onOpen: () async {
                        final kind = await showExecutorSheet(
                          context,
                          executorId: id,
                          prefs: prefs,
                        );
                        if (kind != null && mounted) {
                          setState(() => _future = _load());
                        }
                      },
                      onRemove: () => _remove(id, blocked),
                    ),
                ],
              );
            }

            return TabBarView(
              children: [
                list(prefs.favorites, blocked: false),
                list(prefs.blocks, blocked: true),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ExecutorRow extends StatelessWidget {
  final Profile? profile;
  final bool blocked;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  const _ExecutorRow({
    required this.profile,
    required this.blocked,
    required this.onOpen,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final p = profile;
    return ListTile(
      onTap: onOpen,
      leading: InitialsAvatar(
        p?.fullName ?? '?',
        radius: 22,
        imageUrl: p?.avatarUrl,
      ),
      title: Text(
        p?.fullName ?? t('Орындаушы'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Gz.h3,
      ),
      subtitle: p == null
          ? null
          : Row(
              children: [
                RatingStars(
                  p.ratingAs('executor'),
                  count: p.ratingCountAs('executor'),
                  size: 12,
                ),
                if (p.tripsAs('executor') > 0)
                  Text(
                    '  · ${p.tripsAs('executor')} ${t('рейс')}',
                    style: Gz.caption,
                  ),
              ],
            ),
      trailing: IconButton(
        tooltip: blocked ? t('Бұғаттан шығару') : t('Таңдаулыдан алу'),
        onPressed: onRemove,
        icon: Icon(
          blocked ? Icons.lock_open_rounded : Icons.favorite_rounded,
          color: blocked ? Gz.textSecondary : Gz.red,
        ),
      ),
    );
  }
}
