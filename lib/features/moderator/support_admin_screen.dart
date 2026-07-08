import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import '../support/chat_view.dart';
import 'order_admin.dart';

/// Модератор жағы: барлық қолдау тредтері + әр тредке жауап беру.
class SupportAdminScreen extends StatefulWidget {
  const SupportAdminScreen({super.key});

  @override
  State<SupportAdminScreen> createState() => _SupportAdminScreenState();
}

class _SupportAdminScreenState extends State<SupportAdminScreen> {
  @override
  void initState() {
    super.initState();
    // жабылған тредтердің ескі суреттерін фондық режимде тазалау
    Repo.cleanupSupportImages();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<SupportThread>>(
      stream: Repo.allThreadsStream(),
      builder: (context, snap) {
        final threads = snap.data ?? [];
        if (snap.connectionState == ConnectionState.waiting && threads.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (threads.isEmpty) {
          return const EmptyState(
              icon: Icons.forum_outlined, title: 'Чат жоқ');
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: threads.length,
          separatorBuilder: (_, i) => const SizedBox(height: 8),
          itemBuilder: (_, i) => _ThreadTile(thread: threads[i]),
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
            title: Text(p?.fullName ?? '…',
                style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(
              '${_roleLabel(p?.role)} · ${fmtDate(thread.lastMsgAt)}',
              style: const TextStyle(fontSize: 12.5),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (thread.isOpen ? Gz.green : Gz.textSecondary)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(thread.isOpen ? 'Ашық' : 'Жабық',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: thread.isOpen ? Gz.green : Gz.textSecondary)),
                ),
                if (waiting)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Icon(Icons.mark_chat_unread,
                        size: 16, color: Gz.red),
                  ),
              ],
            ),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) =>
                  _ModeratorChatScreen(thread: thread, user: p),
            )),
          ),
        );
      },
    );
  }

  String _roleLabel(String? r) => switch (r) {
        'executor' => 'Орындаушы',
        'moderator' => 'Модератор',
        _ => 'Клиент',
      };
}

class _ModeratorChatScreen extends StatelessWidget {
  final SupportThread thread;
  final Profile? user;
  const _ModeratorChatScreen({required this.thread, this.user});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(user?.fullName ?? 'Чат'),
        actions: [
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
            label: const Text('Аяқтау'),
          ),
        ],
      ),
      body: Column(
        children: [
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

/// Чат қай заказ бойынша екенін көрсетеді + модератор әрекеттері.
class _OrderContextBar extends StatelessWidget {
  final String orderId;
  const _OrderContextBar({required this.orderId});

  Future<Order?> _load() async {
    final m =
        await Repo.c.from('orders').select().eq('id', orderId).maybeSingle();
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
          color: const Color(0xFFFFF7E0),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.receipt_long, size: 18, color: Gz.ink),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${fmtT(o.displayPrice)} · ${statusLabel(o.status)}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                Text('${o.fromDisplay} → ${o.toDisplay}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, color: Gz.textSecondary)),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 38),
                        foregroundColor: Gz.ink,
                        side: const BorderSide(color: Gz.border)),
                    onPressed: () =>
                        showOrderAdminSheet(context, orderId),
                    icon: const Icon(Icons.tune, size: 16),
                    label: const Text('Заказды басқару (статус, тоқтату…)',
                        style: TextStyle(fontSize: 12.5)),
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
