import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/geo.dart';
import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/map_widgets.dart';
import '../../shared/widgets.dart';
import '../support/support_screen.dart';

/// Орындаушының белсенді заказ экраны: клиент, маршрут, статус ауыстыру.
class ActiveOrderScreen extends StatelessWidget {
  final String orderId;
  const ActiveOrderScreen({super.key, required this.orderId});

  /// Жақындық шегі (км): нақты нүктеде емес, жақын болса жеткілікті.
  static const _proximityKm = 1.5;

  static const _next = {
    'accepted': ('arrived', 'Келдім', Icons.location_on),
    'arrived': ('loading', 'Тиеуді бастадық', Icons.upload),
    'loading': ('in_transit', 'Жолға шықтық', Icons.local_shipping),
    'in_transit': ('completed', 'Заказды аяқтау', Icons.check_circle),
  };

  /// Геолокация + жақындықты тексереді. Қажет болмаса — true.
  Future<bool> _checkProximity(
      BuildContext context, String nextStatus, Order o) async {
    // «Келдім» → A нүктесіне жақын; «Аяқтау» → B нүктесіне жақын
    LatLng? target;
    String farErr = '';
    if (nextStatus == 'arrived') {
      target = LatLng(o.fromLat, o.fromLng);
      farErr = 'TOO_FAR_FROM_A';
    } else if (nextStatus == 'completed') {
      target = LatLng(o.toLat, o.toLng);
      farErr = 'TOO_FAR_FROM_B';
    }
    if (target == null) return true; // басқа қадамдар — тексеріссіз

    final pos = await Geo.currentPosition();
    if (pos == null) {
      if (context.mounted) showSnack(context, errText('LOCATION_OFF'), error: true);
      return false;
    }
    final dist =
        Geo.haversineKm(LatLng(pos.latitude, pos.longitude), target);
    if (dist > _proximityKm) {
      if (context.mounted) {
        showSnack(
            context,
            '${errText(farErr)} (${dist.toStringAsFixed(1)} км қашықтық)',
            error: true);
      }
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Белсенді заказ')),
      body: StreamBuilder<Order?>(
        stream: Repo.orderStream(orderId),
        builder: (context, snap) {
          final o = snap.data;
          if (o == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final next = _next[o.status];
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(fmtT(o.finalPrice),
                          style: const TextStyle(
                              fontSize: 24, fontWeight: FontWeight.w900)),
                    ),
                    StatusChip(o.status),
                  ],
                ),
                const SizedBox(height: 12),
                RouteMap(
                  from: LatLng(o.fromLat, o.fromLng),
                  to: LatLng(o.toLat, o.toLng),
                  height: 170,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _navigate(o.fromLat, o.fromLng),
                        icon: const Icon(Icons.navigation_outlined, size: 18),
                        label: const Text('A навигация',
                            style: TextStyle(fontSize: 13)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _navigate(o.toLat, o.toLng),
                        icon: const Icon(Icons.navigation, size: 18),
                        label: const Text('B навигация',
                            style: TextStyle(fontSize: 13)),
                      ),
                    ),
                  ],
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
                const SizedBox(height: 10),
                _ClientCard(clientId: o.clientId),
                if (o.isActive) ...[
                  const SizedBox(height: 10),
                  SupportOrderButton(orderId: o.id),
                ],
                const SizedBox(height: 16),
                if (next != null)
                  BusyButton(
                    label: next.$2,
                    icon: next.$3,
                    color: o.status == 'in_transit' ? Gz.green : null,
                    onPressed: () async {
                      // A/B нүктесіне жақындықты тексеру
                      final ok =
                          await _checkProximity(context, next.$1, o);
                      if (!ok) return;
                      try {
                        await Repo.orderAdvance(o.id, next.$1);
                        if (next.$1 == 'completed' && context.mounted) {
                          showSnack(context,
                              'Заказ аяқталды! Табысыңызға ${fmtT(o.finalPrice)} қосылды 🎉');
                        }
                      } catch (e) {
                        if (context.mounted) {
                          showSnack(context, errText(e), error: true);
                        }
                      }
                    },
                  ),
                if (o.status == 'completed') ...[
                  const SectionCard(
                    child: Row(children: [
                      Icon(Icons.check_circle, color: Gz.green),
                      SizedBox(width: 10),
                      Expanded(child: Text('Заказ сәтті аяқталды')),
                    ]),
                  ),
                  const SizedBox(height: 10),
                  ReviewPrompt(orderId: o.id, title: 'Клиентті бағалаңыз'),
                ],
                // Орындаушы тек «қабылданды» кезеңінде (келмей тұрып) бас тарта алады
                if (o.status == 'accepted') ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Gz.red,
                        side: const BorderSide(color: Gz.red)),
                    onPressed: () => _cancel(context, o.id),
                    icon: const Icon(Icons.close),
                    label: const Text('Бас тарту'),
                  ),
                ],
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }

  void _navigate(double lat, double lng) {
    launchUrl(
      Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng'),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _cancel(BuildContext context, String orderId) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = TextEditingController();
        return AlertDialog(
          title: const Text('Заказдан бас тарту'),
          content: TextField(
            controller: c,
            decoration: const InputDecoration(hintText: 'Себебі'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Жоқ')),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: Gz.red, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, c.text),
              child: const Text('Бас тарту'),
            ),
          ],
        );
      },
    );
    if (reason == null || !context.mounted) return;
    try {
      await Repo.cancelOrder(orderId, reason);
      if (context.mounted) Navigator.of(context).maybePop();
    } catch (e) {
      if (context.mounted) showSnack(context, errText(e), error: true);
    }
  }
}

class _ClientCard extends StatelessWidget {
  final String clientId;
  const _ClientCard({required this.clientId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Profile?>(
      future: Repo.profileOf(clientId),
      builder: (context, snap) {
        final p = snap.data;
        return SectionCard(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              InitialsAvatar(p?.fullName ?? '?',
                  radius: 22, imageUrl: p?.avatarUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Клиент',
                        style: TextStyle(
                            color: Gz.textSecondary, fontSize: 12)),
                    Text(p?.fullName ?? '…',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 15.5)),
                    if (p != null)
                      Row(children: [
                        RatingStars(p.rating, count: p.ratingCount, size: 12),
                        if (p.trips > 0)
                          Text('  · ${p.trips} рейс',
                              style: const TextStyle(
                                  fontSize: 11.5, color: Gz.textSecondary)),
                      ]),
                  ],
                ),
              ),
              if (p != null && p.phone.isNotEmpty)
                IconButton.filled(
                  style: IconButton.styleFrom(
                      backgroundColor: Gz.green,
                      foregroundColor: Colors.white),
                  onPressed: () =>
                      launchUrl(Uri(scheme: 'tel', path: p.phone)),
                  icon: const Icon(Icons.call),
                ),
            ],
          ),
        );
      },
    );
  }
}
