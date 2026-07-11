import 'package:flutter/foundation.dart' show kIsWeb;
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
class ActiveOrderScreen extends StatefulWidget {
  final String orderId;
  const ActiveOrderScreen({super.key, required this.orderId});

  @override
  State<ActiveOrderScreen> createState() => _ActiveOrderScreenState();
}

class _ActiveOrderScreenState extends State<ActiveOrderScreen> {
  bool _reviewShown = false;

  /// Жақындық шегі (км): нақты нүктеде емес, жақын болса жеткілікті.
  static const _proximityKm = 1.5;

  // «arrived → loading» әдейі ЖОҚ: тиеуді енді КЛИЕНТ растайды (0027).
  // Орындаушы «Келдім» дегеннен кейін клиенттің растауын күтеді, содан соң
  // ғана «Жолға шықтық» батырмасы (loading → in_transit) көрінеді.
  static const _next = {
    'accepted': ('arrived', 'Келдім', Icons.location_on),
    'loading': ('in_transit', 'Жолға шықтық', Icons.local_shipping),
    'in_transit': ('completed', 'Заказды аяқтау', Icons.check_circle),
  };

  /// Заказ аяқталғанда клиентті бағалау терезесін бір рет қалқымалы ашамыз.
  void _maybeShowReview(Order o) {
    if (!_reviewShown && o.status == 'completed') {
      _reviewShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          maybeShowReviewDialog(context,
              orderId: o.id, title: 'Клиентті бағалаңыз');
        }
      });
    }
  }

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
        stream: Repo.orderStream(widget.orderId),
        builder: (context, snap) {
          final o = snap.data;
          if (o == null) {
            return const Center(child: CircularProgressIndicator());
          }
          _maybeShowReview(o);
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
                _NavToggle(
                  onA: () => _navigate(o.fromLat, o.fromLng),
                  onB: () => _navigate(o.toLat, o.toLng),
                ),
                const SizedBox(height: 10),
                SectionCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RouteLine(from: o.fromDisplay, to: o.toDisplay),
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
                  const SizedBox(height: 10),
                  ReportSuspiciousButton(orderId: o.id),
                ],
                const SizedBox(height: 16),
                // «Келдім» дегеннен кейін — клиенттің тиеуді растауын күтеміз
                if (o.status == 'arrived')
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Gz.blue.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(Gz.radius),
                      border: Border.all(color: Gz.blue.withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.hourglass_top, color: Gz.blue),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Клиенттің «Тиеу басталды» деп растауын күтіңіз. '
                            'Растаған соң «Жолға шықтық» батырмасы шығады.',
                            style: TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (o.status == 'arrived') const SizedBox(height: 10),
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
                        if (next.$1 == 'completed') {
                          if (o.photos.isNotEmpty) {
                            Repo.deleteOrderPhotos(o.photos);
                          }
                          if (context.mounted) {
                            showSnack(context,
                                'Заказ аяқталды! Табысыңызға ${fmtT(o.finalPrice)} қосылды 🎉');
                          }
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

  /// 2GIS қосымшасын тікелей турлы-баурай («routeSearch») режимінде ашуға
  /// тырысады (ҚР/ТМД-да ең көп қолданылатын навигация — сол себепті Google
  /// Maps орнына нақ осы таңдалды); орнатылмаса не платформа қолдамаса —
  /// 2GIS веб-бағыттар бетіне (кез келген құрылғыда жұмыс істейді) қайтады.
  Future<void> _navigate(double lat, double lng) async {
    if (!kIsWeb) {
      try {
        final dgis = Uri.parse('dgis://2gis.ru/routeSearch/rsType/car/to/$lng,$lat');
        if (await canLaunchUrl(dgis)) {
          await launchUrl(dgis);
          return;
        }
      } catch (_) {
        // белгісіз платформа/рұқсат қатесі — веб-нұсқаға түсеміз
      }
    }
    launchUrl(
      Uri.parse('https://2gis.kz/routeSearch/rsType/car/to/$lng,$lat'),
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
                  backgroundColor: Gz.red,
                  foregroundColor: Colors.white,
                  shadowColor: const Color(0x59DC2626)),
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

/// A/B навигация — бір тегіс пиллге біріктірілген, басқанда «тірі» жауап
/// беретін (кішірейіп, түсі жанатын) қос жартылы. Бұрын екі бөлек
/// OutlinedButton қатар тұрып, жабыспаған/қосылмаған көрінетін.
class _NavToggle extends StatelessWidget {
  final VoidCallback onA;
  final VoidCallback onB;
  const _NavToggle({required this.onA, required this.onB});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Gz.bg,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Gz.border, width: 1.4),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _NavHalf(
                icon: Icons.trip_origin,
                color: Gz.green,
                label: 'A навигация',
                onTap: onA),
          ),
          Container(width: 1.4, color: Gz.border),
          Expanded(
            child: _NavHalf(
                icon: Icons.location_on,
                color: Gz.red,
                label: 'B навигация',
                onTap: onB),
          ),
        ],
      ),
    );
  }
}

class _NavHalf extends StatefulWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  const _NavHalf({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  State<_NavHalf> createState() => _NavHalfState();
}

class _NavHalfState extends State<_NavHalf> {
  bool _pressed = false;
  void _setPressed(bool v) => setState(() => _pressed = v);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOut,
        color: _pressed ? widget.color.withValues(alpha: 0.1) : Colors.transparent,
        child: Center(
          child: AnimatedScale(
            scale: _pressed ? 0.9 : 1,
            duration: const Duration(milliseconds: 130),
            curve: Curves.easeOut,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, size: 17, color: widget.color),
                const SizedBox(width: 7),
                Text(widget.label,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: widget.color)),
              ],
            ),
          ),
        ),
      ),
    );
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
