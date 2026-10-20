import 'package:flutter/material.dart';

import '../../core/lang.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import '../chat/order_chat_screen.dart';

/// Модератор: клиент ↔ орындаушы ЗАКАЗ ЧАТТАРЫН бақылау (0078).
///
/// Соңғы хабар бойынша сұрыпталған тізім; 🚩 — сілтеме не балағат сөз бар
/// чаттар (алаяқтық көбіне «төлемді мына сілтемемен жасаңыз» деп
/// басталады). Ашса — толық чат, қажет болса модератор өзі жазады.
class OrderChatsScreen extends StatefulWidget {
  const OrderChatsScreen({super.key});

  @override
  State<OrderChatsScreen> createState() => _OrderChatsScreenState();
}

class _OrderChatsScreenState extends State<OrderChatsScreen> {
  bool _flaggedOnly = false;
  late Future<List<Map<String, dynamic>>> _future = _load();

  Future<List<Map<String, dynamic>>> _load() =>
      Repo.modOrderChats(flaggedOnly: _flaggedOnly);

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Row(
            children: [
              ChoiceChip(
                label: Text(t('Барлығы')),
                selected: !_flaggedOnly,
                onSelected: (_) {
                  _flaggedOnly = false;
                  _reload();
                },
              ),
              const SizedBox(width: 6),
              ChoiceChip(
                avatar: Icon(Icons.flag_rounded, size: 16, color: Gz.red),
                label: Text(t('Белгіленгендер')),
                selected: _flaggedOnly,
                onSelected: (_) {
                  _flaggedOnly = true;
                  _reload();
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return LoadErrorState(
                  onRetry: _reload,
                  subtitle: Repo.isMissingFunction(snap.error!)
                      ? t('Серверде 0078 миграциясы әлі қолданылмаған.')
                      : errText(snap.error!),
                );
              }
              final list = snap.data ?? const [];
              if (list.isEmpty) {
                return EmptyState(
                  icon: Icons.forum_outlined,
                  title: _flaggedOnly
                      ? t('Белгіленген чат жоқ')
                      : t('Заказ чаттары әзірге жоқ'),
                );
              }
              return RefreshIndicator(
                onRefresh: () async {
                  _reload();
                  await _future;
                },
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 24),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) =>
                      _ChatTile(row: list[i], onOpened: _reload),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ChatTile extends StatelessWidget {
  final Map<String, dynamic> row;
  final VoidCallback onOpened;
  const _ChatTile({required this.row, required this.onOpened});

  @override
  Widget build(BuildContext context) {
    final orderId = row['order_id'] as String;
    final flagged = (row['flagged'] as num?)?.toInt() ?? 0;
    final total = (row['total'] as num?)?.toInt() ?? 0;
    final client = (row['client_name'] as String?) ?? t('Клиент');
    final executor = (row['executor_name'] as String?) ?? t('Орындаушы');
    final last = DateTime.tryParse(row['last_at'] as String? ?? '')?.toLocal();
    final status = row['status'] as String? ?? '';
    return SectionCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(Gz.radius),
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => OrderChatScreen(
                orderId: orderId,
                title: '$client ↔ $executor',
                myRole: 'moderator',
              ),
            ),
          );
          onOpened();
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (flagged > 0) ...[
                    Icon(Icons.flag_rounded, size: 18, color: Gz.red),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: Text(
                      '$client ↔ $executor',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Gz.h3,
                    ),
                  ),
                  Text(fmtDate(last), style: Gz.caption),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                row['last_body'] as String? ?? '',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Gz.bodyMuted,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  StatusChip(status),
                  InfoChip(
                    icon: Icons.chat_bubble_outline_rounded,
                    text: '$total',
                  ),
                  if (flagged > 0)
                    InfoChip(
                      icon: Icons.flag_outlined,
                      color: Gz.red,
                      text: '$flagged',
                    ),
                  InfoChip(text: '#${orderId.substring(0, 8)}'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
