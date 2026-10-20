import 'package:flutter/material.dart';

import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import '../support/chat_view.dart';
import 'executors_screen.dart' show ExecutorDraftTile;
import 'order_admin.dart';
import 'trust_actions.dart';

/// Клиенттерді іздеу, профильді тексеру, заказ/чат тарихын көру және
/// аккаунтқа модерация әрекетін жасауға арналған жұмыс экраны.
class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key});

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  final _search = TextEditingController();
  String _filter = 'all';
  late Future<List<Profile>> _future = Repo.modClients();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _reload() => setState(() => _future = Repo.modClients());

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: t('Аты, телефон немесе ID бойынша іздеу'),
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () => setState(_search.clear),
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Row(
            children: [
              for (final (key, label) in [
                ('all', t('Барлығы')),
                ('active', t('Белсенді')),
                ('blocked', t('Бұғатталған')),
              ]) ...[
                ChoiceChip(
                  label: Text(label),
                  selected: _filter == key,
                  onSelected: (_) => setState(() => _filter = key),
                ),
                const SizedBox(width: 6),
              ],
              ActionChip(
                avatar: const Icon(Icons.pending_actions_rounded, size: 17),
                label: Text(t('Тіркелу прогресі')),
                onPressed: _openDrafts,
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            color: Gz.ink,
            onRefresh: () async => _reload(),
            child: FutureBuilder<List<Profile>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return ListView(
                    children: [
                      const SizedBox(height: 100),
                      LoadErrorState(onRetry: _reload),
                    ],
                  );
                }
                final q = _search.text.trim().toLowerCase();
                final rows = (snap.data ?? []).where((p) {
                  final matchesFilter =
                      _filter == 'all' ||
                      (_filter == 'blocked' ? p.isBlocked : !p.isBlocked);
                  final haystack = '${p.fullName} ${p.phone} ${p.id}'
                      .toLowerCase();
                  return matchesFilter && (q.isEmpty || haystack.contains(q));
                }).toList();
                if (rows.isEmpty) {
                  return ListView(
                    children: [
                      const SizedBox(height: 90),
                      EmptyState(
                        icon: Icons.people_outline,
                        title: q.isEmpty
                            ? t('Клиенттер жоқ')
                            : t('Сәйкес клиент табылмады'),
                      ),
                    ],
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                  itemCount: rows.length,
                  separatorBuilder: (_, index) => const SizedBox(height: 8),
                  itemBuilder: (_, i) =>
                      _ClientTile(profile: rows[i], onChanged: _reload),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openDrafts() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const RegistrationDraftsScreen()));
  }
}

String _nameOr(Profile p) =>
    p.fullName.isEmpty ? t('Аты көрсетілмеген') : p.fullName;

class _ClientTile extends StatelessWidget {
  final Profile profile;
  final VoidCallback onChanged;
  const _ClientTile({required this.profile, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = profile;
    return SectionCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(Gz.radius),
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => ClientDetailScreen(profile: p)),
          );
          onChanged();
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              InitialsAvatar(p.fullName, radius: 22, imageUrl: p.avatarUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            _nameOr(p),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Gz.h3,
                          ),
                        ),
                        const SizedBox(width: 8),
                        InfoChip(
                          text: p.isBlocked ? t('Бұғатталған') : t('Белсенді'),
                          color: p.isBlocked ? Gz.danger : Gz.success,
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(p.phone.isEmpty ? p.id : p.phone, style: Gz.caption),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        RatingStars(
                          p.ratingAs('client'),
                          count: p.ratingCountAs('client'),
                          size: 12,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            p.createdAt == null
                                ? t('Тіркелген күні белгісіз')
                                : '${t('Тіркелген')}: ${fmtDate(p.createdAt)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Gz.caption,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Gz.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

class ClientDetailScreen extends StatefulWidget {
  final Profile profile;
  const ClientDetailScreen({super.key, required this.profile});

  @override
  State<ClientDetailScreen> createState() => _ClientDetailScreenState();
}

class _ClientDetailScreenState extends State<ClientDetailScreen> {
  late Profile _p = widget.profile;
  late Future<List<Order>> _orders = Repo.modOrdersOf(_p.id);
  late Future<List<SupportThread>> _threads = Repo.modThreadsOf(_p.id);

  Future<void> _reload() async {
    final fresh = await Repo.profileOf(_p.id, fresh: true);
    if (!mounted) return;
    setState(() {
      if (fresh != null) _p = fresh;
      _orders = Repo.modOrdersOf(_p.id);
      _threads = Repo.modThreadsOf(_p.id);
    });
  }

  Future<void> _toggleBlock() async {
    final blocked = _p.isBlocked;
    String reason = t('Модератор бұғаттан шығарды');
    if (!blocked) {
      final r = await gzInputDialog(
        context,
        icon: Icons.block_rounded,
        confirmColor: Gz.red,
        title: t('Блоктау себебі'),
        presets: [for (final p in kBlockReasonPresets) t(p)],
        confirmLabel: t('Блоктау'),
      );
      if (r == null) return;
      reason = r.isEmpty ? t('Модератор шешімі') : r;
    }
    try {
      await Repo.modSetAccountBlocked(_p.id, !blocked, reason);
      if (!mounted) return;
      showSnack(
        context,
        blocked ? t('Аккаунт бұғаттан шығарылды') : t('Аккаунт бұғатталды'),
      );
      await _reload();
    } catch (e) {
      if (mounted) showSnack(context, errText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    return Scaffold(
      appBar: AppBar(
        title: Text(t('Клиент профилі')),
        actions: [
          IconButton(
            tooltip: t('Сенім әрекеттері'),
            onPressed: () =>
                showTrustActionsSheet(context, p, onChanged: _reload),
            icon: const Icon(Icons.shield_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    InitialsAvatar(
                      p.fullName,
                      radius: 30,
                      imageUrl: p.avatarUrl,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_nameOr(p), style: Gz.h2),
                          const SizedBox(height: 2),
                          Text(p.phone, style: Gz.caption),
                          const SizedBox(height: 4),
                          Text(
                            'ID: ${p.id}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Gz.textTertiary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (p.phone.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ContactButtons(phone: p.phone),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  label: t('Рейтинг'),
                  value: p.ratingCountAs('client') == 0
                      ? '—'
                      : p.ratingAs('client').toStringAsFixed(1),
                  icon: Icons.star_rounded,
                  color: Gz.star,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(
                  label: t('Аяқталған'),
                  value: '${p.tripsAs('client')}',
                  icon: Icons.check_circle_outline_rounded,
                  color: Gz.green,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(
                  label: t('Сенім'),
                  value: '${p.trustScore}',
                  icon: Icons.verified_user_outlined,
                  color: Gz.violet,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionTitle(t('Аккаунт ақпараты')),
                InfoRow(
                  t('Тіркелген'),
                  p.createdAt == null ? '—' : fmtDate(p.createdAt),
                ),
                InfoRow(
                  t('Рөл'),
                  p.hasExecutorRole ? t('Клиент + орындаушы') : t('Клиент'),
                ),
                InfoRow(
                  t('Күйі'),
                  p.isBlocked ? t('Бұғатталған') : t('Белсенді'),
                ),
                if (p.isBlocked && (p.blockReason?.isNotEmpty ?? false))
                  InfoRow(t('Себебі:'), p.blockReason!),
                InfoRow(t('Шақыру коды'), p.referralCode ?? '—'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionTitle(t('Заказ тарихы')),
          FutureBuilder<List<Order>>(
            future: _orders,
            builder: (context, snap) {
              final orders = snap.data ?? const <Order>[];
              if (snap.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (orders.isEmpty) {
                return GzNotice(
                  tone: NoticeTone.neutral,
                  message: t('Бұл клиент әлі заказ бермеген'),
                );
              }
              return Column(
                children: [
                  for (final o in orders.take(8)) ...[
                    OrderCard(
                      order: o,
                      onTap: () => showOrderAdminSheet(
                        context,
                        o.id,
                        onChanged: _reload,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          SectionTitle(t('Қолдау чатының тарихы')),
          FutureBuilder<List<SupportThread>>(
            future: _threads,
            builder: (context, snap) {
              final threads = snap.data ?? const <SupportThread>[];
              if (snap.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (threads.isEmpty) {
                return GzNotice(
                  tone: NoticeTone.neutral,
                  message: t('Қолдау чаты жоқ'),
                );
              }
              return SectionCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < threads.length; i++) ...[
                      if (i > 0) const Divider(height: 1, indent: 60),
                      GzListRow(
                        icon: threads[i].isOpen
                            ? Icons.forum_rounded
                            : Icons.forum_outlined,
                        color: threads[i].isOpen ? Gz.green : Gz.textSecondary,
                        title: threads[i].isOpen
                            ? t('Ашық чат')
                            : t('Жабық чат'),
                        subtitle:
                            '${t('Соңғы хабарлама')}: ${fmtDate(threads[i].lastMsgAt)}',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ModeratorChatReadScreen(
                              thread: threads[i],
                              user: p,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _toggleBlock,
            style: OutlinedButton.styleFrom(
              foregroundColor: p.isBlocked ? Gz.green : Gz.red,
              side: BorderSide(
                color: Gz.tint(p.isBlocked ? Gz.green : Gz.red, 0.45),
                width: 1.4,
              ),
            ),
            icon: Icon(
              p.isBlocked ? Icons.lock_open_rounded : Icons.block_rounded,
            ),
            label: Text(
              p.isBlocked
                  ? t('Аккаунтты бұғаттан шығару')
                  : t('Аккаунтты бұғаттау'),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

/// Жабық thread-ті де оқитын және қажет болса қайта ашып жауап беретін chat view.
class ModeratorChatReadScreen extends StatelessWidget {
  final SupportThread thread;
  final Profile user;
  const ModeratorChatReadScreen({
    super.key,
    required this.thread,
    required this.user,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(user.fullName.isEmpty ? t('Қолдау чаты') : user.fullName),
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: GzNotice(
            dense: true,
            tone: thread.isOpen ? NoticeTone.success : NoticeTone.neutral,
            icon: thread.isOpen
                ? Icons.mark_chat_unread_outlined
                : Icons.history_rounded,
            message: thread.isOpen
                ? t('Ашық чат · клиент контексті қосылды')
                : t('Жабық чат · тарихты оқу режимі'),
          ),
        ),
        Expanded(
          child: ChatView(
            threadId: thread.id,
            asModerator: true,
            threadOpen: thread.isOpen,
            onSend: (body, imagePath) async {
              await Repo.supportReply(thread.id, body, imagePath: imagePath);
              return thread.id;
            },
          ),
        ),
      ],
    ),
  );
}

/// Модераторға тіркелу қай қадамда үзілгенін көрсететін аудит тізімі.
/// Әр адамға бірден қоңырау шалуға не WhatsApp-қа жазуға болады.
class RegistrationDraftsScreen extends StatefulWidget {
  const RegistrationDraftsScreen({super.key});
  @override
  State<RegistrationDraftsScreen> createState() =>
      _RegistrationDraftsScreenState();
}

class _RegistrationDraftsScreenState extends State<RegistrationDraftsScreen> {
  late Future<List<Map<String, dynamic>>> _future =
      Repo.modRegistrationDrafts();
  bool _showCompleted = false;

  void _reload() => setState(() => _future = Repo.modRegistrationDrafts());

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(t('Тіркелу прогресі'))),
    body: RefreshIndicator(
      color: Gz.ink,
      onRefresh: () async => _reload(),
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return ListView(
              children: [
                const SizedBox(height: 120),
                LoadErrorState(onRetry: _reload),
              ],
            );
          }
          final all = snap.data ?? const <Map<String, dynamic>>[];
          final rows = all
              .where((r) => _showCompleted || r['completed_at'] == null)
              .toList();
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Row(
                children: [
                  ChoiceChip(
                    label: Text(t('Үзілгендер')),
                    selected: !_showCompleted,
                    onSelected: (_) => setState(() => _showCompleted = false),
                  ),
                  const SizedBox(width: 6),
                  ChoiceChip(
                    label: Text(t('Барлығы')),
                    selected: _showCompleted,
                    onSelected: (_) => setState(() => _showCompleted = true),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (rows.isEmpty)
                GzNotice(
                  tone: NoticeTone.neutral,
                  message: t('Белсенді тіркелу draft-тері жоқ'),
                ),
              for (final r in rows) ...[
                ExecutorDraftTile(row: r),
                const SizedBox(height: 8),
              ],
            ],
          );
        },
      ),
    ),
  );
}
