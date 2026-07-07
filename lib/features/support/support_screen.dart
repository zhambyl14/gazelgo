import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import 'chat_view.dart';

/// Заказ экрандарында көрсетілетін «Қолдау қызметі» түймесі.
class SupportOrderButton extends StatelessWidget {
  final String orderId;
  const SupportOrderButton({super.key, required this.orderId});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: EdgeInsets.zero,
      child: ListTile(
        leading: const Icon(Icons.support_agent, color: Gz.ink),
        title: const Text('Қолдау қызметі',
            style: TextStyle(fontWeight: FontWeight.w700)),
        subtitle: const Text('Заказ бойынша мәселе болса — жазыңыз'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => SupportScreen(orderId: orderId))),
      ),
    );
  }
}

/// Пайдаланушы (клиент/орындаушы) жағындағы қолдау чаты.
/// [orderId] берілсе — модератор чат қай заказ бойынша екенін көреді.
class SupportScreen extends StatefulWidget {
  final String? orderId;
  const SupportScreen({super.key, this.orderId});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Қолдау қызметі'),
      ),
      body: StreamBuilder<List<SupportThread>>(
        stream: Repo.myThreadsStream(),
        builder: (context, snap) {
          final threads = snap.data ?? [];
          SupportThread? current;
          for (final t in threads) {
            if (t.isOpen) {
              current = t;
              break;
            }
          }
          current ??= threads.isNotEmpty ? threads.last : null;

          return Column(
            children: [
              if (current != null && current.isOpen)
                Material(
                  color: Gz.surface,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Row(
                      children: [
                        const Icon(Icons.circle, size: 10, color: Gz.green),
                        const SizedBox(width: 6),
                        const Expanded(
                            child: Text('Чат ашық',
                                style: TextStyle(fontSize: 13))),
                        TextButton.icon(
                          onPressed: () async {
                            try {
                              await Repo.supportClose(current!.id);
                            } catch (e) {
                              if (context.mounted) {
                                showSnack(context, errText(e), error: true);
                              }
                            }
                          },
                          icon: const Icon(Icons.check, size: 16),
                          label: const Text('Аяқтау'),
                        ),
                      ],
                    ),
                  ),
                ),
              Expanded(
                child: ChatView(
                  key: ValueKey(current?.id ?? 'new'),
                  threadId: current?.isOpen == true ? current!.id : null,
                  asModerator: false,
                  threadOpen: current?.isOpen ?? true,
                  onSend: (body, imagePath) => Repo.supportSend(body,
                      imagePath: imagePath, orderId: widget.orderId),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
