import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import '../support/chat_view.dart';
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
              hintText: 'Аты, телефон немесе ID бойынша іздеу',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _search.clear();
                        setState(() {});
                      },
                      icon: const Icon(Icons.close),
                    ),
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Row(
            children: [
              for (final item in const [
                ('all', 'Барлығы'),
                ('active', 'Белсенді'),
                ('blocked', 'Бұғатталған'),
              ]) ...[
                ChoiceChip(
                  label: Text(item.$2),
                  selected: _filter == item.$1,
                  selectedColor: Gz.yellow,
                  onSelected: (_) => setState(() => _filter = item.$1),
                ),
                const SizedBox(width: 6),
              ],
              OutlinedButton.icon(
                onPressed: _openDrafts,
                icon: const Icon(Icons.pending_actions, size: 17),
                label: const Text('Тіркелу прогресі'),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => _reload(),
            child: FutureBuilder<List<Profile>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
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
                            ? 'Клиенттер жоқ'
                            : 'Сәйкес клиент табылмады',
                      ),
                    ],
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
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

class _ClientTile extends StatelessWidget {
  final Profile profile;
  final VoidCallback onChanged;
  const _ClientTile({required this.profile, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final color = profile.isBlocked ? Gz.red : Gz.green;
    return SectionCard(
      padding: const EdgeInsets.all(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ClientDetailScreen(profile: profile),
          ),
        ),
        child: Row(
          children: [
            InitialsAvatar(
              profile.fullName,
              radius: 25,
              imageUrl: profile.avatarUrl,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.fullName.isEmpty
                        ? 'Аты көрсетілмеген'
                        : profile.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    profile.phone.isEmpty ? profile.id : profile.phone,
                    style: const TextStyle(
                      color: Gz.textSecondary,
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    profile.createdAt == null
                        ? 'Тіркелген күні белгісіз'
                        : 'Тіркелген: ${fmtDate(profile.createdAt)}',
                    style: const TextStyle(
                      color: Gz.textSecondary,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Icon(
                  profile.isBlocked ? Icons.block : Icons.check_circle,
                  color: color,
                  size: 18,
                ),
                const SizedBox(height: 4),
                Text(
                  profile.isBlocked ? 'Бұғатталған' : 'Белсенді',
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Icon(Icons.chevron_right, color: Gz.textSecondary),
              ],
            ),
          ],
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
  late Future<List<Order>> _orders = Repo.modOrdersOf(widget.profile.id);
  late Future<List<SupportThread>> _threads = Repo.modThreadsOf(
    widget.profile.id,
  );

  void _reload() {
    setState(() {
      _orders = Repo.modOrdersOf(widget.profile.id);
      _threads = Repo.modThreadsOf(widget.profile.id);
    });
  }

  Future<void> _toggleBlock() async {
    final blocked = widget.profile.isBlocked;
    try {
      await Repo.modSetAccountBlocked(
        widget.profile.id,
        !blocked,
        blocked ? 'Модератор бұғаттан шығарды' : 'Модератор шешімі',
      );
      if (mounted) {
        showSnack(
          context,
          blocked ? 'Аккаунт бұғаттан шығарылды' : 'Аккаунт бұғатталды',
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) showSnack(context, errText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Клиент профилі'),
        actions: [
          IconButton(
            tooltip: 'Сенім әрекеттері',
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
            child: Row(
              children: [
                InitialsAvatar(p.fullName, radius: 34, imageUrl: p.avatarUrl),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.fullName.isEmpty ? 'Аты көрсетілмеген' : p.fullName,
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        p.phone,
                        style: const TextStyle(color: Gz.textSecondary),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'ID: ${p.id}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Gz.textSecondary,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _metric(
                  'Рейтинг',
                  p.ratingAs('client').toStringAsFixed(1),
                  Gz.yellowDark,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _metric('Аяқталған', '${p.tripsAs('client')}', Gz.green),
              ),
              const SizedBox(width: 8),
              Expanded(child: _metric('Trust', '${p.trustScore}', Gz.violet)),
            ],
          ),
          const SizedBox(height: 12),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Аккаунт ақпараты',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
                const SizedBox(height: 8),
                InfoRow(
                  'Тіркелген',
                  p.createdAt == null ? '—' : fmtDate(p.createdAt),
                ),
                InfoRow(
                  'Рөл',
                  p.hasExecutorRole ? 'Клиент + орындаушы' : 'Клиент',
                ),
                InfoRow('Күйі', p.isBlocked ? 'Бұғатталған' : 'Белсенді'),
                InfoRow('Шақыру коды', p.referralCode ?? '—'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _sectionTitle('Заказ тарихы'),
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
              if (orders.isEmpty)
                return const _HintTile(text: 'Бұл клиент әлі заказ бермеген');
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
          _sectionTitle('Қолдау чатының тарихы'),
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
              if (threads.isEmpty)
                return const _HintTile(text: 'Қолдау чаты жоқ');
              return Column(
                children: [
                  for (final thread in threads)
                    Card(
                      child: ListTile(
                        leading: Icon(
                          thread.isOpen ? Icons.forum : Icons.forum_outlined,
                          color: thread.isOpen ? Gz.green : Gz.textSecondary,
                        ),
                        title: Text(
                          thread.isOpen ? 'Ашық чат' : 'Жабық чат',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          'Соңғы хабарлама: ${fmtDate(thread.lastMsgAt)}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ModeratorChatReadScreen(
                              thread: thread,
                              user: p,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _toggleBlock,
            style: OutlinedButton.styleFrom(
              foregroundColor: p.isBlocked ? Gz.green : Gz.red,
            ),
            icon: Icon(p.isBlocked ? Icons.lock_open : Icons.block),
            label: Text(
              p.isBlocked ? 'Аккаунтты бұғаттан шығару' : 'Аккаунтты бұғаттау',
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _metric(String label, String value, Color color) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Gz.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Gz.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Gz.textSecondary, fontSize: 11),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w900,
            fontSize: 17,
          ),
        ),
      ],
    ),
  );

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
    ),
  );
}

class _HintTile extends StatelessWidget {
  final String text;
  const _HintTile({required this.text});
  @override
  Widget build(BuildContext context) => SectionCard(
    child: Row(
      children: [
        const Icon(Icons.info_outline, color: Gz.textSecondary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: const TextStyle(color: Gz.textSecondary)),
        ),
      ],
    ),
  );
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
      title: Text(user.fullName.isEmpty ? 'Қолдау чаты' : user.fullName),
    ),
    body: Column(
      children: [
        Container(
          width: double.infinity,
          color: thread.isOpen ? Gz.green.withValues(alpha: .08) : Gz.bg,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Icon(
                thread.isOpen ? Icons.mark_chat_unread : Icons.history,
                color: thread.isOpen ? Gz.green : Gz.textSecondary,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  thread.isOpen
                      ? 'Ашық чат · клиент контексті қосылды'
                      : 'Жабық чат · тарихты оқу режимі',
                ),
              ),
            ],
          ),
        ),
        Expanded(child: _ModeratorChatBody(thread: thread)),
      ],
    ),
  );
}

class _ModeratorChatBody extends StatelessWidget {
  final SupportThread thread;
  const _ModeratorChatBody({required this.thread});
  @override
  Widget build(BuildContext context) {
    return ChatView(
      threadId: thread.id,
      asModerator: true,
      threadOpen: thread.isOpen,
      onSend: (body, imagePath) async {
        await Repo.supportReply(thread.id, body, imagePath: imagePath);
        return thread.id;
      },
    );
  }
}

/// Модераторға тіркелу қай қадамда үзілгенін көрсететін аудит тізімі.
class RegistrationDraftsScreen extends StatefulWidget {
  const RegistrationDraftsScreen({super.key});
  @override
  State<RegistrationDraftsScreen> createState() =>
      _RegistrationDraftsScreenState();
}

class _RegistrationDraftsScreenState extends State<RegistrationDraftsScreen> {
  late Future<List<Map<String, dynamic>>> _future =
      Repo.modRegistrationDrafts();
  void _reload() => setState(() => _future = Repo.modRegistrationDrafts());
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Тіркелу прогресі')),
    body: RefreshIndicator(
      onRefresh: () async => _reload(),
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting)
            return const Center(child: CircularProgressIndicator());
          final rows = snap.data ?? const <Map<String, dynamic>>[];
          if (rows.isEmpty)
            return ListView(
              children: const [
                SizedBox(height: 120),
                _HintTile(text: 'Белсенді тіркелу draft-тері жоқ'),
              ],
            );
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final r = rows[i];
              final completed = r['completed_at'] != null;
              final name = (r['full_name'] as String?)?.trim();
              final role = r['role'] == 'executor' ? 'Орындаушы' : 'Клиент';
              return SectionCard(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    completed ? Icons.verified : Icons.pending_actions,
                    color: completed ? Gz.green : Gz.yellowDark,
                  ),
                  title: Text(
                    name?.isNotEmpty == true ? name! : 'Аты енгізілмеген',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    '$role · ${r['stage_label'] ?? 'Қадам белгісіз'}\nСоңғы белсенділік: ${r['last_seen_at'] ?? '—'}',
                  ),
                  isThreeLine: true,
                  trailing: Text(
                    completed ? 'Дайын' : 'Үзілген',
                    style: TextStyle(
                      color: completed ? Gz.green : Gz.red,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    ),
  );
}
