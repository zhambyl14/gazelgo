import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/push_router.dart';
import '../../shared/widgets.dart';

/// Хабарламалар орталығы (0080): келген push-тардың тарихы. Push байқалмай
/// қалса не телефонда өшірулі болса да, маңызды хабар осында сақталады.
///
/// Бет ашылғанда бәрі «оқылды» болып белгіленеді, бірақ осы ашылуда жаңа
/// хабарлар нүктемен белгіленіп тұрады (не жаңа екені көрінсін).
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  late Future<List<AppNotification>> _future = _load();

  Future<List<AppNotification>> _load() async {
    final list = await Repo.myNotifications();
    if (list.any((n) => n.unread)) {
      await Repo.markAllNotificationsRead();
      ref.invalidate(unreadNotificationsProvider);
    }
    return list;
  }

  static (IconData, Color) _look(String? type) => switch (type) {
    'new_order' => (Icons.local_shipping_outlined, Gz.info),
    'new_offer' ||
    'offer_accepted' ||
    'offer_rejected' => (Icons.local_offer_outlined, Gz.accent),
    'order_status' ||
    'order_expired' ||
    'order_reminder' => (Icons.receipt_long_outlined, Gz.info),
    'support_reply' || 'support_message' => (
      Icons.support_agent_rounded,
      Gz.violet,
    ),
    'topup_approved' => (Icons.account_balance_wallet_outlined, Gz.success),
    'topup_rejected' => (Icons.account_balance_wallet_outlined, Gz.danger),
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

  @override
  Widget build(BuildContext context) {
    final ru = Lang.current.value == AppLang.ru;
    return Scaffold(
      appBar: AppBar(title: Text(t('Хабарламалар'))),
      body: FutureBuilder<List<AppNotification>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = snap.data ?? const <AppNotification>[];
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.notifications_none_rounded,
              title: t('Хабарлама әзірге жоқ'),
              subtitle: t('Заказ, ұсыныс және қолдау қызметінің жауаптары '
                  'осында сақталады.'),
            );
          }
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
            final body = ru && (n.bodyRu?.isNotEmpty ?? false)
                ? n.bodyRu!
                : n.body;
            final canOpen = n.data['type'] != null || n.data['order_id'] != null;
            rows.add(
              GzListRow(
                icon: icon,
                color: color,
                title: title,
                subtitle: body.isEmpty ? null : body,
                onTap: canOpen ? () => openPushTarget(n.data) : null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(fmtTime(at), style: Gz.caption),
                    if (n.unread) ...[
                      const SizedBox(width: 6),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Gz.danger,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              setState(() => _future = _load());
              await _future;
            },
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: rows,
            ),
          );
        },
      ),
    );
  }
}
