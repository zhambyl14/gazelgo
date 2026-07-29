import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/geo.dart';
import '../../core/lang.dart';
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
  static (String, String, IconData)? _nextFor(String status) => switch (status) {
        'accepted' => ('arrived', t('Келдім'), Icons.location_on),
        'loading' => ('in_transit', t('Жолға шықтық'), Icons.local_shipping),
        'in_transit' => ('completed', t('Заказды аяқтау'), Icons.check_circle),
        _ => null,
      };

  /// Заказ аяқталғанда клиентті бағалау терезесін бір рет қалқымалы ашамыз.
  void _maybeShowReview(Order o) {
    if (!_reviewShown && o.status == 'completed') {
      _reviewShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          maybeShowReviewDialog(context,
              orderId: o.id, title: 'Клиентті бағалаңыз'); // t() ReviewPrompt ішінде
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
      if (context.mounted) await _showLocationNeeded(context);
      return false;
    }
    final dist =
        Geo.haversineKm(LatLng(pos.latitude, pos.longitude), target);
    if (dist > _proximityKm) {
      if (context.mounted) {
        showSnack(
            context,
            '${errText(farErr)} (${dist.toStringAsFixed(1)} ${t('км қашықтық')})',
            error: true);
      }
      return false;
    }
    return true;
  }

  /// Геолокация өшірулі не рұқсат берілмеген кезде — түсіндірме терезесі.
  /// Тек орындаушы «Келдім/Аяқтау» түймесін өзі басқанда шығады (локацияға
  /// тәуелді нақты әрекет), сол себепті параметрлерге өту өз еркімен — мұны
  /// App Store ережесі (5.1.1) осындай жағдайда рұқсат етеді.
  Future<void> _showLocationNeeded(BuildContext context) async {
    final serviceOn = await Geolocator.isLocationServiceEnabled();
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Геолокация керек')),
        content: Text(t(
            '«Келдім» және «Аяқтау» түймелері үшін орналасуыңызды растау қажет '
            '— жүйе нүктеге жеткеніңізді тексереді. Параметрлерден геолокацияны '
            'қосыңыз.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t('Жабу')),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (serviceOn) {
                Geolocator.openAppSettings();
              } else {
                Geolocator.openLocationSettings();
              }
            },
            child: Text(t('Параметрлерді ашу')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t('Белсенді заказ'))),
      body: StreamBuilder<Order?>(
        stream: Repo.orderStream(widget.orderId),
        builder: (context, snap) {
          final o = snap.data;
          if (o == null) {
            return const Center(child: CircularProgressIndicator());
          }
          _maybeShowReview(o);
          final next = _nextFor(o.status);
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
                      InfoRow(t('Жүк'), o.cargoDesc),
                      if (o.comment.isNotEmpty)
                        InfoRow(t('Түсініктеме'), o.comment),
                      if (o.distanceKm > 0)
                        InfoRow(t('Қашықтық'),
                            '${o.distanceKm.toStringAsFixed(1)} км'),
                    ],
                  ),
                ),
                if (o.photos.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  SectionCard(child: OrderPhotosStrip(paths: o.photos)),
                ],
                const SizedBox(height: 10),
                // Заказ тоқтатылса — клиенттің нөмірі/хабарласу батырмасы
                // көрсетілмейді (байланыс тоқтатылған заказда сақталмайды).
                _ClientCard(
                    clientId: o.clientId, showCall: o.status != 'cancelled'),
                if (o.status == 'cancelled') ...[
                  const SizedBox(height: 10),
                  SectionCard(
                    child: Row(children: [
                      const Icon(Icons.info_outline, color: Gz.red),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          (o.cancelReason?.isNotEmpty ?? false)
                              ? '${t('Заказ тоқтатылды. Себебі:')} ${o.cancelReason}'
                              : t('Заказ тоқтатылды'),
                        ),
                      ),
                    ]),
                  ),
                ],
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
                    child: Row(
                      children: [
                        const Icon(Icons.hourglass_top, color: Gz.blue),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            t('Клиенттің «Тиеу басталды» деп растауын күтіңіз. '
                                'Растаған соң «Жолға шықтық» батырмасы шығады.'),
                            style: const TextStyle(
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
                                '${t('Заказ аяқталды! Табысыңызға')} ${fmtT(o.finalPrice)} ${t('қосылды')} 🎉');
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
                  SectionCard(
                    child: Row(children: [
                      const Icon(Icons.check_circle, color: Gz.green),
                      const SizedBox(width: 10),
                      Expanded(child: Text(t('Заказ сәтті аяқталды'))),
                    ]),
                  ),
                  const SizedBox(height: 10),
                  ReviewPrompt(
                      orderId: o.id,
                      title: 'Клиентті бағалаңыз'), // t() ReviewPrompt ішінде
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
                    label: Text(t('Бас тарту')),
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

  static const _execCancelReasons = [
    'Көлігім бос емес',
    'Қашықтық тым алыс',
    'Клиентпен байланыса алмадым',
    'Баға тым төмен',
    'Жүк сипаттамаға сай емес',
  ];

  Future<void> _cancel(BuildContext context, String orderId) async {
    final reason = await pickCancelReason(context,
        title: t('Заказдан бас тарту'),
        presets: [for (final r in _execCancelReasons) t(r)]);
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
                label: t('A навигация'),
                onTap: onA),
          ),
          Container(width: 1.4, color: Gz.border),
          Expanded(
            child: _NavHalf(
                icon: Icons.location_on,
                color: Gz.red,
                label: t('B навигация'),
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
  final bool showCall;
  const _ClientCard({required this.clientId, this.showCall = true});

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
                    Text(t('Клиент'),
                        style: const TextStyle(
                            color: Gz.textSecondary, fontSize: 12)),
                    Text(p?.fullName ?? '…',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 15.5)),
                    // Орындаушы КЛИЕНТТІ көреді → клиенттік рейтинг/рейс
                    // (қос рөл, 0046: ол адамның орындаушылық бағасы бөлек).
                    if (p != null)
                      Row(children: [
                        RatingStars(p.ratingAs('client'),
                            count: p.ratingCountAs('client'), size: 12),
                        if (p.tripsAs('client') > 0)
                          Text('  · ${p.tripsAs('client')} ${t('рейс')}',
                              style: const TextStyle(
                                  fontSize: 11.5, color: Gz.textSecondary)),
                      ]),
                  ],
                ),
              ),
              if (showCall && p != null && p.phone.isNotEmpty)
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
