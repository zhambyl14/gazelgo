import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/geo.dart';
import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/map_widgets.dart';
import '../../shared/nav_apps.dart';
import '../../shared/order_live.dart';
import '../../shared/widgets.dart';
import '../chat/order_chat_screen.dart';
import '../support/support_screen.dart';
import 'delivery_code_sheet.dart';

/// Орындаушының белсенді заказ экраны: келу уақыты, навигация, клиент
/// пен алушы, қадамдар («Келдім» → «Жолға шықтық» → «Аяқтау»).
///
/// Негізгі әрекет батырмасы ТӨМЕНДЕ БЕКІТІЛГЕН — жүргізуші бетті
/// айналдырып іздемейді. Орынды серверге жіберу бұл экранда ЕМЕС, орындаушы
/// қабығында (лентада не басқа бетте тұрса да клиенттің картасы тірі
/// қалады).
class ActiveOrderScreen extends StatefulWidget {
  final String orderId;
  const ActiveOrderScreen({super.key, required this.orderId});

  @override
  State<ActiveOrderScreen> createState() => _ActiveOrderScreenState();
}

class _ActiveOrderScreenState extends State<ActiveOrderScreen> {
  late final Stream<Order?> _stream = Repo.orderStream(widget.orderId);
  bool _reviewShown = false;
  bool _chatAvailable = false;

  /// Алушы (0074) — статус ауысқан сайын қайта сұралады (клиент алушыны
  /// жолда қосуы не кодты өзі растауы мүмкін).
  OrderRecipient? _recipient;
  String? _recipientFor;

  /// Жақындық шегі (км): нақты нүктеде емес, жақын болса жеткілікті.
  static const _proximityKm = 1.5;

  @override
  void initState() {
    super.initState();
    Repo.orderChatAvailable().then((v) {
      if (mounted) setState(() => _chatAvailable = v);
    });
  }

  void _syncRecipient(Order o) {
    if (_recipientFor == o.status) return;
    _recipientFor = o.status;
    if (!o.isActive && o.status != 'completed') return;
    Repo.orderRecipient(o.id).then((r) {
      if (mounted) setState(() => _recipient = r);
    }, onError: (_) {});
  }

  // «arrived → loading» әдейі ЖОҚ: тиеуді КЛИЕНТ растайды (0027).
  static (String, String, IconData)? _nextFor(String status) =>
      switch (status) {
        'accepted' => ('arrived', t('Келдім'), Icons.location_on),
        'loading' => ('in_transit', t('Жолға шықтық'), Icons.local_shipping),
        'in_transit' => ('completed', t('Заказды аяқтау'), Icons.check_circle),
        _ => null,
      };

  void _maybeShowReview(Order o) {
    if (_reviewShown || o.status != 'completed') return;
    _reviewShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      maybeShowReviewDialog(
        context,
        orderId: o.id,
        title: t('Клиентті бағалаңыз'),
        tags: kClientReviewTags,
      );
    });
  }

  /// Геолокация + жақындықты тексереді. Қажет болмаса — true.
  Future<bool> _checkProximity(String nextStatus, Order o) async {
    LatLng? target;
    var farErr = '';
    if (nextStatus == 'arrived') {
      target = LatLng(o.fromLat, o.fromLng);
      farErr = 'TOO_FAR_FROM_A';
    } else if (nextStatus == 'completed') {
      target = LatLng(o.toLat, o.toLng);
      farErr = 'TOO_FAR_FROM_B';
    }
    if (target == null) return true;

    final pos = await Geo.currentPosition();
    if (pos == null) {
      if (mounted) await _showLocationNeeded();
      return false;
    }
    final dist = Geo.haversineKm(LatLng(pos.latitude, pos.longitude), target);
    if (dist > _proximityKm) {
      if (mounted) {
        showSnack(
          context,
          '${errText(farErr)} (${dist.toStringAsFixed(1)} ${t('км қашықтық')})',
          error: true,
        );
      }
      return false;
    }
    return true;
  }

  /// Геолокация өшірулі не рұқсат берілмеген — түсіндірме терезесі. Тек
  /// орындаушы «Келдім/Аяқтау» батырмасын өзі басқанда шығады (App Store
  /// 5.1.1 осындай жағдайда параметрлерге жіберуге рұқсат етеді).
  Future<void> _showLocationNeeded() async {
    final serviceOn = await Geolocator.isLocationServiceEnabled();
    if (!mounted) return;
    await gzInfoDialog(
      context,
      icon: Icons.location_off_outlined,
      color: Gz.warning,
      title: t('Геолокация керек'),
      message: t(
        '«Келдім» және «Аяқтау» түймелері үшін орналасуыңызды растау қажет '
        '— жүйе нүктеге жеткеніңізді тексереді. Параметрлерден геолокацияны '
        'қосыңыз.',
      ),
      actionLabel: t('Параметрлерді ашу'),
      onAction: () {
        if (serviceOn) {
          Geolocator.openAppSettings();
        } else {
          Geolocator.openLocationSettings();
        }
      },
    );
  }

  /// Алушы қосылған заказда жеткізу кодын сұрайды. Код керек емес болса
  /// не дұрыс енгізілсе — true.
  Future<bool> _ensureCode(Order o, {bool refresh = false}) async {
    var r = _recipient;
    if (r == null || refresh) {
      try {
        r = await Repo.orderRecipient(o.id);
      } catch (_) {}
    }
    if (r == null || !r.hasCode || r.verified) return true;
    if (!mounted) return false;
    final ok = await showDeliveryCodeSheet(
      context,
      orderId: o.id,
      recipientName: r.name,
      recipientPhone: r.phone,
    );
    if (ok) _recipientFor = null; // «код расталды» күйін қайта сұрау
    return ok;
  }

  Future<void> _advance(Order o, String next) async {
    if (!await _checkProximity(next, o)) return;
    if (next == 'completed' && !await _ensureCode(o)) return;
    try {
      await Repo.orderAdvance(o.id, next);
    } catch (e) {
      // Клиент алушыны дәл қазір қосқан болса — кодты сұрап, қайталаймыз.
      if (!e.toString().contains('CODE_REQUIRED')) {
        if (mounted) showSnack(context, errText(e), error: true);
        return;
      }
      if (!await _ensureCode(o, refresh: true)) return;
      try {
        await Repo.orderAdvance(o.id, next);
      } catch (e2) {
        if (mounted) showSnack(context, errText(e2), error: true);
        return;
      }
    }
    if (next == 'completed') {
      if (o.photos.isNotEmpty) Repo.deleteOrderPhotos(o.photos);
      if (mounted) {
        showSnack(
          context,
          '${t('Заказ аяқталды! Табысыңызға')} ${fmtT(o.finalPrice)} ${t('қосылды')} 🎉',
        );
      }
    }
  }

  static const _execCancelReasons = [
    'Көлігім бос емес',
    'Қашықтық тым алыс',
    'Клиентпен байланыса алмадым',
    'Баға тым төмен',
    'Жүк сипаттамаға сай емес',
  ];

  Future<void> _cancel(String orderId) async {
    final reason = await pickCancelReason(
      context,
      title: t('Заказдан бас тарту'),
      presets: [for (final r in _execCancelReasons) t(r)],
    );
    if (reason == null || !mounted) return;
    try {
      await Repo.cancelOrder(orderId, reason);
      if (mounted) Navigator.of(context).maybePop();
    } catch (e) {
      if (mounted) showSnack(context, errText(e), error: true);
    }
  }

  Future<void> _sendLate(Order o) async {
    try {
      await Repo.orderChatSend(o.id, t('Кептеліс, сәл кешігемін'));
      if (mounted) showSnack(context, t('Клиентке хабар жіберілді'));
    } catch (e) {
      if (mounted) showSnack(context, errText(e), error: true);
    }
  }

  /// «⋯» — навигаторды ауыстыру, мекенжайды көшіру.
  void _navMenu(Order o) {
    showGzSheet<void>(
      context,
      builder: (ctx) => GzSheetBody(
        title: t('Навигация'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GzListRow(
              icon: Icons.swap_horiz_rounded,
              color: Gz.info,
              title: t('Навигаторды ауыстыру'),
              onTap: () {
                Navigator.pop(ctx);
                NavApps.pick(context);
              },
            ),
            GzListRow(
              icon: Icons.copy_rounded,
              color: Gz.green,
              title: t('A мекенжайын көшіру'),
              subtitle: o.fromDisplay,
              onTap: () {
                Navigator.pop(ctx);
                copyAddress(context, o.fromAddress);
              },
            ),
            for (var i = 0; i < o.stops.length; i++)
              GzListRow(
                icon: Icons.copy_rounded,
                color: Gz.violet,
                title: '${t('Аялдама')} ${i + 1}',
                subtitle: o.stops[i].display,
                onTap: () {
                  Navigator.pop(ctx);
                  copyAddress(context, o.stops[i].address);
                },
              ),
            GzListRow(
              icon: Icons.copy_rounded,
              color: Gz.red,
              title: t('B мекенжайын көшіру'),
              subtitle: o.toDisplay,
              onTap: () {
                Navigator.pop(ctx);
                copyAddress(context, o.toAddress);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Order?>(
      stream: _stream,
      builder: (context, snap) {
        final o = snap.data;
        if (o == null) {
          return Scaffold(
            appBar: AppBar(title: Text(t('Белсенді заказ'))),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        _maybeShowReview(o);
        _syncRecipient(o);
        final next = _nextFor(o.status);
        final r = _recipient;
        final needsCode = o.status == 'in_transit' &&
            r != null &&
            r.hasCode &&
            !r.verified;
        return Scaffold(
          appBar: AppBar(title: Text(t('Белсенді заказ'))),
          bottomNavigationBar: next == null
              ? null
              : SafeArea(
                  top: false,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                    decoration: const BoxDecoration(
                      color: Gz.surface,
                      boxShadow: Gz.cardShadow,
                    ),
                    child: BusyButton(
                      label: needsCode ? t('Кодты енгізіп аяқтау') : next.$2,
                      icon: needsCode ? Icons.pin_rounded : next.$3,
                      color: o.status == 'in_transit' ? Gz.green : null,
                      onPressed: () => _advance(o, next.$1),
                    ),
                  ),
                ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Row(
                children: [
                  Expanded(child: Text(fmtT(o.finalPrice), style: Gz.moneyXl)),
                  StatusChip(o.status, vehicleType: o.vehicleType),
                ],
              ),
              const SizedBox(height: 8),
              _StepProgress(status: o.status, vehicleType: o.vehicleType),
              if (o.status == 'accepted' && o.arriveBy != null) ...[
                const SizedBox(height: 12),
                EtaCountdownCard(
                  order: o,
                  forExecutor: true,
                  lateAction: _chatAvailable
                      ? OutlinedButton.icon(
                          onPressed: () => _sendLate(o),
                          icon: const Icon(Icons.chat_outlined, size: 18),
                          label: Text(t('Клиентке «кешігемін» деп жазу')),
                        )
                      : null,
                ),
              ],
              if (o.status == 'arrived') ...[
                const SizedBox(height: 12),
                WaitingTimerCard(order: o, forExecutor: true),
              ],
              const SizedBox(height: 12),
              RouteMap(
                from: LatLng(o.fromLat, o.fromLng),
                to: LatLng(o.toLat, o.toLng),
                stops: o.stops.map((s) => LatLng(s.lat, s.lng)).toList(),
                height: 180,
                fromLabel: o.fromDisplay,
                toLabel: o.toDisplay,
                stopLabels: o.stops.map((s) => s.display).toList(),
                distanceKm: o.distanceKm,
              ),
              if (o.isActive) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _NavToggle(
                        onA: () => NavApps.open(context, o.fromLat, o.fromLng),
                        onB: () => NavApps.open(context, o.toLat, o.toLng),
                        onStops: [
                          for (final s in o.stops)
                            () => NavApps.open(context, s.lat, s.lng),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 52,
                      height: 52,
                      child: IconButton.outlined(
                        tooltip: t('Навигация'),
                        style: IconButton.styleFrom(
                          side: const BorderSide(color: Gz.border, width: 1.4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(Gz.rMd),
                          ),
                        ),
                        onPressed: () => _navMenu(o),
                        icon: const Icon(Icons.more_horiz_rounded),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              SectionCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RouteLine(
                      from: o.fromDisplay,
                      to: o.toDisplay,
                      stops: o.stops.map((s) => s.display).toList(),
                    ),
                    const Divider(height: 20),
                    InfoRow(t('Жүк'), o.cargoDesc),
                    if (o.comment.isNotEmpty)
                      InfoRow(t('Түсініктеме'), o.comment),
                    if (o.distanceKm > 0)
                      InfoRow(
                        t('Қашықтық'),
                        '${o.distanceKm.toStringAsFixed(1)} км',
                      ),
                    if (o.hasExtras) ...[
                      const SizedBox(height: 6),
                      OrderExtrasChips(order: o),
                    ],
                  ],
                ),
              ),
              if (o.photos.isNotEmpty) ...[
                const SizedBox(height: 10),
                SectionCard(child: OrderPhotosStrip(paths: o.photos)),
              ],
              const SizedBox(height: 10),
              // Тоқтатылған заказда байланыс батырмалары көрсетілмейді.
              _ClientCard(order: o, showContacts: o.status != 'cancelled'),
              if (r != null && o.status != 'cancelled') ...[
                const SizedBox(height: 10),
                _RecipientCard(recipient: r, showContacts: o.isActive),
              ],
              if (o.status == 'cancelled') ...[
                const SizedBox(height: 10),
                GzNotice(
                  tone: NoticeTone.danger,
                  message: (o.cancelReason?.isNotEmpty ?? false)
                      ? '${t('Заказ тоқтатылды. Себебі:')} ${o.cancelReason}'
                      : t('Заказ тоқтатылды'),
                ),
              ],
              if (o.status == 'completed') ...[
                const SizedBox(height: 10),
                GzNotice(
                  tone: NoticeTone.success,
                  icon: Icons.check_circle_rounded,
                  message: t('Заказ сәтті аяқталды'),
                ),
                const SizedBox(height: 10),
                ReviewPrompt(
                  orderId: o.id,
                  title: t('Клиентті бағалаңыз'),
                  tags: kClientReviewTags,
                ),
              ],
              if (o.isActive) ...[
                const SizedBox(height: 16),
                SupportOrderButton(orderId: o.id),
                const SizedBox(height: 10),
                ReportSuspiciousButton(orderId: o.id),
              ],
              // Орындаушы тек «қабылданды» кезеңінде (келмей тұрып) бас тарта алады
              if (o.status == 'accepted') ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Gz.red,
                    side: const BorderSide(color: Gz.red),
                  ),
                  onPressed: () => _cancel(o.id),
                  icon: const Icon(Icons.close),
                  label: Text(t('Бас тарту')),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Заказ қадамдары бір жолда: Клиентке → Тиеу → Жолда → Аяқталды.
class _StepProgress extends StatelessWidget {
  final String status;
  final VehicleType vehicleType;
  const _StepProgress({required this.status, required this.vehicleType});

  @override
  Widget build(BuildContext context) {
    final isTaxi = vehicleType == VehicleType.taxi;
    final steps = [
      ('accepted', t('Клиентке бару')),
      ('arrived', isTaxi ? t('Отырғызу') : t('Тиеу')),
      ('in_transit', t('Жолда')),
      ('completed', t('Аяқталды')),
    ];
    // «loading» — тиеу қадамының жалғасы.
    final cur = status == 'loading' ? 'arrived' : status;
    final idx = steps.indexWhere((s) => s.$1 == cur);
    if (idx < 0) return const SizedBox.shrink();
    return Row(
      children: [
        for (var i = 0; i < steps.length; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i < steps.length - 1 ? 4 : 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    height: 4,
                    decoration: BoxDecoration(
                      color: i <= idx ? Gz.green : Gz.disabledBg,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    steps[i].$2,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: i == idx ? FontWeight.w800 : FontWeight.w600,
                      color: i <= idx ? Gz.ink : Gz.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// A / аялдамалар / B навигация — бір тегіс пиллге біріктірілген.
class _NavToggle extends StatelessWidget {
  final VoidCallback onA;
  final VoidCallback onB;

  /// Аралық аялдамаларға навигация (0047).
  final List<VoidCallback> onStops;

  const _NavToggle({
    required this.onA,
    required this.onB,
    this.onStops = const [],
  });

  @override
  Widget build(BuildContext context) {
    // Аялдама көп болса жазулар ықшам («A», «1», «2», «B»).
    final compact = onStops.isNotEmpty;
    return Container(
      height: 52,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Gz.bg,
        borderRadius: BorderRadius.circular(Gz.rMd),
        border: Border.all(color: Gz.border, width: 1.4),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _NavHalf(
              icon: Icons.trip_origin,
              color: Gz.green,
              label: compact ? 'A' : t('A навигация'),
              onTap: onA,
            ),
          ),
          for (var i = 0; i < onStops.length; i++) ...[
            Container(width: 1.4, color: Gz.border),
            Expanded(
              child: _NavHalf(
                icon: Icons.adjust,
                color: Gz.violet,
                label: '${i + 1}',
                onTap: onStops[i],
              ),
            ),
          ],
          Container(width: 1.4, color: Gz.border),
          Expanded(
            child: _NavHalf(
              icon: Icons.location_on,
              color: Gz.red,
              label: compact ? 'B' : t('B навигация'),
              onTap: onB,
            ),
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
        color: _pressed ? Gz.tint(widget.color, 0.1) : Colors.transparent,
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
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: widget.color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Клиент: аты, клиенттік рейтингі, чат + қоңырау.
class _ClientCard extends StatelessWidget {
  final Order order;
  final bool showContacts;
  const _ClientCard({required this.order, this.showContacts = true});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Profile?>(
      future: Repo.profileOf(order.clientId),
      builder: (context, snap) {
        final p = snap.data;
        return SectionCard(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              InitialsAvatar(
                p?.fullName ?? '?',
                radius: 22,
                imageUrl: p?.avatarUrl,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t('Клиент'), style: Gz.caption),
                    Text(
                      p?.fullName ?? '…',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Gz.h3,
                    ),
                    // Орындаушы КЛИЕНТТІ көреді → клиенттік рейтинг/рейс
                    // (қос рөл, 0046).
                    if (p != null)
                      Row(
                        children: [
                          RatingStars(
                            p.ratingAs('client'),
                            count: p.ratingCountAs('client'),
                            size: 12,
                          ),
                          if (p.tripsAs('client') > 0)
                            Text(
                              '  · ${p.tripsAs('client')} ${t('рейс')}',
                              style: Gz.caption,
                            ),
                        ],
                      ),
                  ],
                ),
              ),
              if (showContacts) ...[
                OrderChatButton(
                  order: order,
                  title: p?.fullName ?? t('Клиент'),
                  myRole: 'executor',
                ),
                if (p != null && p.phone.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  IconButton.filled(
                    tooltip: t('Қоңырау'),
                    style: IconButton.styleFrom(
                      backgroundColor: Gz.green,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => callPhone(context, p.phone),
                    icon: const Icon(Icons.call),
                  ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Жүкті қабылдайтын адам (0074): аты, телефоны, код керек пе.
class _RecipientCard extends StatelessWidget {
  final OrderRecipient recipient;
  final bool showContacts;
  const _RecipientCard({required this.recipient, this.showContacts = true});

  @override
  Widget build(BuildContext context) {
    final r = recipient;
    return SectionCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Gz.tint(Gz.violet, 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.person_pin_circle_rounded,
                  color: Gz.violet,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t('Жүкті қабылдайтын адам'), style: Gz.caption),
                    Text(
                      r.name.isEmpty ? t('Алушы') : r.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Gz.h3,
                    ),
                  ],
                ),
              ),
              if (r.verified)
                InfoChip(
                  icon: Icons.verified_rounded,
                  color: Gz.success,
                  text: t('Код расталды'),
                )
              else if (r.hasCode)
                InfoChip(
                  icon: Icons.pin_rounded,
                  color: Gz.warning,
                  text: t('Код керек'),
                ),
            ],
          ),
          if (!r.verified && r.hasCode) ...[
            const SizedBox(height: 10),
            GzNotice(
              tone: NoticeTone.warning,
              dense: true,
              message: t('Жүкті тапсырғанда алушыдан 4 таңбалы кодты '
                  'сұраңыз — кодсыз заказ аяқталмайды.'),
            ),
          ],
          if (showContacts && r.phone.isNotEmpty) ...[
            const SizedBox(height: 10),
            ContactButtons(
              phone: r.phone,
              whatsappText: t('Сәлеметсіз бе! Мен Tasu жүргізушісімін, '
                  'сізге жүк әкеле жатырмын.'),
            ),
          ],
        ],
      ),
    );
  }
}
