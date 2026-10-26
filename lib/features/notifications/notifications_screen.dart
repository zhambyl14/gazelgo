import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/push_router.dart';
import '../../shared/widgets.dart';

/// Хабарламалар орталығы (0080): тек МАҢЫЗДЫ хабарлар (модератор хабары,
/// жаңалық, баға, баланс, қолдау) — заказдың әр қадамы мұнда жиналмайды
/// (0095). Бет ашылғанда ештеңе автоматты «оқылды» болмайды: хабарламаны
/// ашқанда ОЛ ғана оқылады, ал жоғарыдағы батырма бәрін бірден оқылды
/// етеді — қызыл белгілер көзге түсіп тұрмауы үшін.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  late Future<List<AppNotification>> _future = Repo.myNotifications();

  /// Осы бетте оқылды деп белгіленгендер (сервер жауабын күтпей көрсету үшін).
  final Set<String> _read = {};

  bool _unread(AppNotification n) => n.unread && !_read.contains(n.id);

  static (IconData, Color) _look(String? type) => switch (type) {
    'support_reply' ||
    'support_message' => (Icons.support_agent_rounded, Gz.violet),
    'topup_approved' => (Icons.account_balance_wallet_outlined, Gz.success),
    'topup_rejected' => (Icons.account_balance_wallet_outlined, Gz.danger),
    'bonus' => (Icons.card_giftcard_rounded, Gz.success),
    'review_received' => (Icons.star_rounded, Gz.star),
    'broadcast' => (Icons.campaign_outlined, Gz.yellowDeep),
    _ => (Icons.notifications_none_rounded, Gz.textSecondary),
  };

  String _dayLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return t('Бүгін');
    if (diff == 1) return t('Кеше');
    return fmtDate(d).split(' ').first;
  }

  Future<void> _open(AppNotification n) async {
    if (_unread(n)) {
      setState(() => _read.add(n.id));
      await Repo.markNotificationRead(n.id);
      ref.invalidate(unreadNotificationsProvider);
    }
    openPushTarget(n.data);
  }

  Future<void> _markAll(List<AppNotification> list) async {
    setState(() => _read.addAll(list.map((n) => n.id)));
    await Repo.markAllNotificationsRead();
    ref.invalidate(unreadNotificationsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final ru = Lang.current.value == AppLang.ru;
    return FutureBuilder<List<AppNotification>>(
      future: _future,
      builder: (context, snap) {
        final done = snap.connectionState == ConnectionState.done;
        final list = snap.data ?? const <AppNotification>[];
        final hasUnread = done && list.any(_unread);
        return Scaffold(
          appBar: AppBar(
            title: Text(t('Хабарламалар')),
            actions: [
              if (hasUnread)
                IconButton(
                  tooltip: t('Барлығын оқылды деп белгілеу'),
                  icon: const Icon(Icons.done_all_rounded),
                  onPressed: () => _markAll(list),
                ),
            ],
          ),
          body: !done
              ? const Center(child: CircularProgressIndicator())
              : list.isEmpty
              ? EmptyState(
                  icon: Icons.notifications_none_rounded,
                  title: t('Хабарлама әзірге жоқ'),
                  subtitle: t(
                    'Модератор хабарламалары, жаңалықтар, бағалар мен баланс '
                    'өзгерістері осында сақталады.',
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () async {
                    setState(() {
                      _read.clear();
                      _future = Repo.myNotifications();
                    });
                    await _future;
                  },
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: _rows(list, ru),
                  ),
                ),
        );
      },
    );
  }

  List<Widget> _rows(List<AppNotification> list, bool ru) {
    final rows = <Widget>[];
    String? lastDay;
    for (final n in list) {
      final at = n.createdAt?.toLocal();
      final day = at == null ? '' : _dayLabel(at);
      if (day != lastDay) {
        lastDay = day;
        rows.add(SectionTitle(day));
      }
      final (icon, color) = _look(n.data['type'] as String?);
      final title = ru && (n.titleRu?.isNotEmpty ?? false)
          ? n.titleRu!
          : n.title;
      final body = ru && (n.bodyRu?.isNotEmpty ?? false) ? n.bodyRu! : n.body;
      final unread = _unread(n);
      rows.add(
        GzListRow(
          icon: icon,
          color: color,
          title: title,
          subtitle: body.isEmpty ? null : body,
          onTap: () => _open(n),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(fmtTime(at), style: Gz.caption),
              if (unread) ...[
                const SizedBox(width: 6),
                // Қызыл емес — көзге ұрмайтын жұмсақ түс.
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Gz.info,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return rows;
  }
}
