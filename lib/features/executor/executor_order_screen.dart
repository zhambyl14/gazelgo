import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/map_widgets.dart';
import '../../shared/widgets.dart';
import 'active_order_screen.dart';

/// Ұсыныс жібергеннен кейінгі орындаушы экраны:
/// клиент жауабын күту → қабылданса белсенді заказға өту.
class ExecutorOrderScreen extends StatelessWidget {
  final String orderId;
  const ExecutorOrderScreen({super.key, required this.orderId});

  @override
  Widget build(BuildContext context) {
    final myId = Repo.uid;
    return Scaffold(
      appBar: AppBar(title: const Text('Заказ')),
      body: StreamBuilder<Order?>(
        stream: Repo.orderStream(orderId),
        builder: (context, snap) {
          final o = snap.data;
          if (o == null) {
            return const Center(child: CircularProgressIndicator());
          }
          // Маған тағайындалса — белсенді заказ экранына ауысамыз
          if (o.executorId == myId && o.isActive) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              Navigator.of(context).pushReplacement(MaterialPageRoute(
                  builder: (_) => ActiveOrderScreen(orderId: orderId)));
            });
            return const Center(child: CircularProgressIndicator());
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                RouteMap(
                  from: LatLng(o.fromLat, o.fromLng),
                  to: LatLng(o.toLat, o.toLng),
                  height: 160,
                ),
                const SizedBox(height: 10),
                SectionCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RouteLine(from: o.fromAddress, to: o.toAddress),
                      const Divider(height: 20),
                      InfoRow('Жүк', o.cargoDesc),
                      if (o.comment.isNotEmpty)
                        InfoRow('Түсініктеме', o.comment),
                      InfoRow('Клиент бағасы', fmtT(o.clientPrice)),
                      if (o.distanceKm > 0)
                        InfoRow('Қашықтық',
                            '${o.distanceKm.toStringAsFixed(1)} км'),
                    ],
                  ),
                ),
                if (o.photos.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  SectionCard(child: OrderPhotosStrip(paths: o.photos)),
                ],
                const SizedBox(height: 14),
                _statusBlock(context, o, myId),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _statusBlock(BuildContext context, Order o, String? myId) {
    // Заказ басқаға кетті немесе жабылды
    if (o.status != 'searching') {
      final taken = o.executorId != null && o.executorId != myId;
      return SectionCard(
        child: Column(
          children: [
            Icon(taken ? Icons.person_off : Icons.info_outline,
                size: 40, color: Gz.textSecondary),
            const SizedBox(height: 10),
            Text(
              taken
                  ? 'Заказды басқа орындаушы алды'
                  : 'Заказ енді қолжетімсіз',
              style: const TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 15.5),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Лентаға оралу'),
            ),
          ],
        ),
      );
    }

    // Менің ұсынысымның күйін көрсету
    return StreamBuilder<List<Offer>>(
      stream: Repo.offersStream(o.id),
      builder: (context, snap) {
        Offer? mine;
        for (final of in snap.data ?? <Offer>[]) {
          if (of.executorId == myId) mine = of;
        }
        if (mine == null) {
          return const SizedBox.shrink();
        }
        if (mine.status == 'rejected' || mine.status == 'withdrawn') {
          return SectionCard(
            child: Column(
              children: [
                const Icon(Icons.close, size: 40, color: Gz.red),
                const SizedBox(height: 8),
                const Text('Ұсынысыңыз қабылданбады',
                    style: TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 15.5)),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Лентаға оралу'),
                ),
              ],
            ),
          );
        }
        // pending
        return SectionCard(
          child: Column(
            children: [
              const SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(height: 14),
              Text('Ұсынысыңыз жіберілді · ${fmtT(mine.price)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 4),
              const Text('Клиенттің жауабын күтіңіз…',
                  style: TextStyle(color: Gz.textSecondary, fontSize: 13)),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    foregroundColor: Gz.red,
                    side: const BorderSide(color: Gz.border)),
                onPressed: () async {
                  try {
                    await Repo.withdrawOffer(mine!.id);
                    if (context.mounted) Navigator.of(context).pop();
                  } catch (e) {
                    if (context.mounted) {
                      showSnack(context, errText(e), error: true);
                    }
                  }
                },
                icon: const Icon(Icons.undo, size: 18),
                label: const Text('Ұсынысты қайтарып алу'),
              ),
            ],
          ),
        );
      },
    );
  }
}
