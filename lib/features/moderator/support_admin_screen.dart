import 'package:flutter/material.dart';

import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import '../support/chat_view.dart';
import 'clients_screen.dart';
import 'order_admin.dart';

/// Жабылған қолдау чаты архивте қанша күн тұрады (cleanup-storage
/// функциясындағы SUPPORT_RETENTION_DAYS-пен БІРДЕЙ болуы керек).
const kSupportArchiveDays = 30;

/// Модератор жағы: барлық қолдау тредтері + әр тредке жауап беру.
/// Жабылған чаттар [kSupportArchiveDays] күн «Архив» сүзгісінде сақталады.
class SupportAdminScreen extends StatefulWidget {
  const SupportAdminScreen({super.key});

  @override
  State<SupportAdminScreen> createState() => _SupportAdminScreenState();
}

class _SupportAdminScreenState extends State<SupportAdminScreen> {
  /// open | archive | all
  String _filter = 'open';

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<SupportThread>>(
      stream: Repo.allThreadsStream(),
      builder: (context, snap) {
        final all = snap.data ?? [];
        if (snap.connectionState == ConnectionState.waiting && all.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        final threads = [
          for (final th in all)
            if (switch (_filter) {
              'open' => th.isOpen,
              'archive' => !th.isOpen,
              _ => true,
            })
              th,
        ];
        final openCount = all.where((th) => th.isOpen).length;
        return Column(
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Row(
                children: [
                  for (final (key, label) in <(String, String)>[
                    ('open', '${t('Ашық')} · $openCount'),
                    ('archive', '${t('Архив')} · ${all.length - openCount}'),
                    ('all', t('Барлығы')),
                  ]) ...[
                    ChoiceChip(
                      label: Text(label),
                      selected: _filter == key,
                      onSelected: (_) => setState(() => _filter = key),
                    ),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
            if (_filter == 'archive')
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Text(
                  '${t('Жабылған чат архивте сақталады')}'
                  ': $kSupportArchiveDays ${t('күн')}',
                  style: Gz.caption,
                ),
              ),
            Expanded(
              child: threads.isEmpty
                  ? EmptyState(
                      icon: Icons.forum_outlined,
                      title: _filter == 'archive'
                          ? t('Архив бос')
                          : t('Чат жоқ'),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: threads.length,
                      separatorBuilder: (_, i) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _ThreadTile(thread: threads[i]),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _ThreadTile extends StatelessWidget {
  final SupportThread thread;
  const _ThreadTile({required this.thread});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Profile?>(
      future: Repo.profileOf(thread.userId),
      builder: (context, snap) {
        final p = snap.data;
        final waiting = thread.isOpen && thread.lastSenderRole == 'user';
        return Card(
          child: ListTile(
            leading: InitialsAvatar(p?.fullName ?? '?', imageUrl: p?.avatarUrl),
            title: Text(
              p?.fullName ?? '…',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              '${_roleLabel(p?.role)} · ${fmtDate(thread.lastMsgAt)}'
              '${_archiveLeft(thread)}',
              style: const TextStyle(fontSize: 13),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: (thread.isOpen ? Gz.green : Gz.textSecondary)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    thread.isOpen ? t('Ашық') : t('Жабық'),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: thread.isOpen ? Gz.green : Gz.textSecondary,
                    ),
                  ),
                ),
                if (waiting)
                  Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Icon(
                      Icons.mark_chat_unread,
                      size: 16,
                      color: Gz.red,
                    ),
                  ),
              ],
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => _ModeratorChatScreen(thread: thread, user: p),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Жабық чат үшін: «· архивте N күн қалды» (ашық чатта бос жол).
  String _archiveLeft(SupportThread th) {
    final closed = th.closedAt;
    if (th.isOpen || closed == null) return '';
    final left = kSupportArchiveDays - DateTime.now().difference(closed).inDays;
    return ' · ${t('архивте')} ${left < 0 ? 0 : left} ${t('күн қалды')}';
  }

  String _roleLabel(String? r) => switch (r) {
    'executor' => t('Орындаушы'),
    'moderator' => t('Модератор'),
    _ => t('Клиент'),
  };
}

/// Модератордың бір чатты ашатын экраны. AI-кеңесші (қолмен басатын
/// ұсыныс батырмасы) ӘДЕЙІ ЖОҚ — оның орнына бот (0054, `support_bot`
/// баптауы қосулы болса) пайдаланушыға ӨЗІ ТІКЕЛЕЙ жауап жазады, модератор
/// ештеңе баспайды. Бот жауабы осында, кәдімгі хабарлама ретінде көрінеді.
class _ModeratorChatScreen extends StatelessWidget {
  final SupportThread thread;
  final Profile? user;
  const _ModeratorChatScreen({required this.thread, this.user});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(user?.fullName ?? t('Чат')),
        actions: [
          if (thread.isOpen)
            TextButton.icon(
              onPressed: () async {
                try {
                  await Repo.supportClose(thread.id);
                  if (context.mounted) Navigator.of(context).pop();
                } catch (e) {
                  if (context.mounted) {
                    showSnack(context, errText(e), error: true);
                  }
                }
              },
              icon: const Icon(Icons.check, size: 18),
              label: Text(t('Аяқтау')),
            ),
        ],
      ),
      body: Column(
        children: [
          if (user != null) _ModeratorUserContext(profile: user!),
          if (thread.orderId != null)
            _OrderContextBar(orderId: thread.orderId!),
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
}

class _ModeratorUserContext extends StatelessWidget {
  final Profile profile;
  const _ModeratorUserContext({required this.profile});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Order>>(
      future: Repo.modOrdersOf(profile.id),
      builder: (context, snap) {
        final orders = snap.data ?? const <Order>[];
        return Material(
          color: Gz.surface,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 7),
            child: Row(
              children: [
                InitialsAvatar(
                  profile.fullName,
                  radius: 22,
                  imageUrl: profile.avatarUrl,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.fullName.isEmpty
                            ? 'Аты көрсетілмеген'
                            : profile.fullName,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        '${profile.phone} · ${orders.length} заказ · Trust ${profile.trustScore}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Gz.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (profile.role == 'client')
                  IconButton(
                    tooltip: 'Толық профиль',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ClientDetailScreen(profile: profile),
                      ),
                    ),
                    icon: const Icon(Icons.open_in_new, size: 19),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Чат қай заказ бойынша екенін көрсетеді + модератор әрекеттері.
class _OrderContextBar extends StatelessWidget {
  final String orderId;
  const _OrderContextBar({required this.orderId});

  Future<Order?> _load() async {
    final m = await Repo.c
        .from('orders')
        .select()
        .eq('id', orderId)
        .maybeSingle();
    return m == null ? null : Order.fromMap(m);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Order?>(
      future: _load(),
      builder: (context, snap) {
        final o = snap.data;
        if (o == null) return const SizedBox.shrink();
        return Material(
          color: Gz.tint(Gz.yellow, 0.14),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.receipt_long, size: 18, color: Gz.ink),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${fmtT(o.displayPrice)} · '
                        '${statusLabel(o.status, vehicleType: o.vehicleType)}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                Text(
                  '${o.fromDisplay} → ${o.toDisplay}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: Gz.textSecondary),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 38),
                      foregroundColor: Gz.ink,
                      side: BorderSide(color: Gz.border),
                    ),
                    onPressed: () => showOrderAdminSheet(context, orderId),
                    icon: const Icon(Icons.tune, size: 16),
                    label: Text(
                      t('Заказды басқару (статус, тоқтату…)'),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
