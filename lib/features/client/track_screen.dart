import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/env.dart';
import '../../core/geo.dart';
import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/map_widgets.dart';
import '../../shared/widgets.dart';

/// АВТОРИЗАЦИЯСЫЗ ашылатын бет (`/track/<token>`, тек вебте).
///
/// Екі түрлі адам ашады:
///  * АЛУШЫ (0076) — клиент WhatsApp арқылы жіберген жеке сілтеме: көлік
///    картада, жүктің күйі және ЖЕТКІЗУ КОДЫ (жүкті алғанда жүргізушіге
///    айтады);
///  * «Сапарды бөлісу» (0060) — клиенттің туысы/досы: тек барысы, кодсыз.
///
/// Бет Tasu-ды да таныстырады (тегін жарнама): төменде қосымшаға сілтеме.
class TrackScreen extends StatefulWidget {
  final String token;
  const TrackScreen({super.key, required this.token});

  @override
  State<TrackScreen> createState() => _TrackScreenState();
}

class _TrackScreenState extends State<TrackScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await Repo.trackOrder(widget.token);
      if (!mounted) return;
      if (res['error'] != null) {
        setState(() => _error = res['error'] as String);
      } else {
        setState(() {
          _data = res;
          _error = null;
        });
      }
      // Аяқталған/тоқтатылған заказды сұрай берудің мәні жоқ.
      final st = res['status'];
      if (st == 'completed' || st == 'cancelled' || st == 'expired') {
        _timer?.cancel();
      }
    } catch (e) {
      if (mounted && _data == null) setState(() => _error = 'NETWORK');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Gz.bg,
      appBar: AppBar(
        backgroundColor: Gz.surface,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/icon/tasu_logo.png',
              height: 30,
              width: 30 * 826 / 1013,
              filterQuality: FilterQuality.medium,
            ),
            const SizedBox(width: 10),
            Text(t('Жүк қайда?')),
          ],
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_error == 'DISABLED') {
      return EmptyState(
        icon: Icons.link_off,
        title: t('Бұл сілтеме қазір өшірулі'),
      );
    }
    if (_error == 'NOT_FOUND') {
      return EmptyState(
        icon: Icons.error_outline,
        title: t('Сілтеме жарамсыз немесе мерзімі өткен'),
      );
    }
    if (_error == 'NETWORK' && _data == null) {
      return LoadErrorState(onRetry: _load);
    }
    final d = _data;
    if (d == null) return const Center(child: CircularProgressIndicator());

    final status = d['status'] as String? ?? 'searching';
    final vehicle = vehicleTypeFrom(d['vehicle_type'] as String?);
    double? n(String k) => (d[k] as num?)?.toDouble();
    final fromLat = n('from_lat'), fromLng = n('from_lng');
    final toLat = n('to_lat'), toLng = n('to_lng');
    final lat = n('lat'), lng = n('lng');
    final car = lat == null || lng == null ? null : LatLng(lat, lng);
    final locAt = DateTime.tryParse(d['loc_updated_at'] as String? ?? '');
    final executorName = (d['executor_name'] as String?)?.trim() ?? '';
    final isRecipient = d['is_recipient'] == true;
    final recipientName = (d['recipient_name'] as String?)?.trim() ?? '';
    final code = d['delivery_code'] as String?;
    final delivered = d['delivered'] == true;
    final fromText = '${d['from_city'] ?? ''} ${d['from_address'] ?? ''}'
        .trim();
    final toText = '${d['to_city'] ?? ''} ${d['to_address'] ?? ''}'.trim();
    final active = const {
      'accepted',
      'arrived',
      'loading',
      'in_transit',
    }.contains(status);

    // Жолда кезінде: көліктен B нүктесіне дейінгі ТҮЗУ қашықтық (≈) қана —
    // уақыт ойдан шығарылмайды. Нақты маршрут салынбайды.
    double? kmLeft;
    if (status == 'in_transit' &&
        car != null &&
        toLat != null &&
        toLng != null) {
      kmLeft = Geo.haversineKm(car, LatLng(toLat, toLng)) * 1.25;
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        if (isRecipient) ...[
          Text(
            recipientName.isEmpty
                ? t('Сәлеметсіз бе!')
                : '${t('Сәлеметсіз бе,')} $recipientName!',
            style: Gz.h2,
          ),
          const SizedBox(height: 2),
          Text(t('Сізге Tasu арқылы жүк келе жатыр'), style: Gz.bodyMuted),
          const SizedBox(height: 14),
        ],
        _StatusHero(
          status: status,
          vehicle: vehicle,
          kmLeft: kmLeft,
          isRecipient: isRecipient,
        ),
        if (isRecipient && delivered) ...[
          const SizedBox(height: 12),
          GzNotice(
            tone: NoticeTone.success,
            icon: Icons.verified_rounded,
            title: t('Жүк тапсырылды'),
            message: t('Жеткізу расталды. Tasu-ны таңдағаныңызға рахмет!'),
          ),
        ] else if (code != null &&
            code.isNotEmpty &&
            status != 'cancelled') ...[
          const SizedBox(height: 12),
          _CodeCard(code: code),
        ],
        if (fromLat != null &&
            fromLng != null &&
            toLat != null &&
            toLng != null) ...[
          const SizedBox(height: 12),
          if (active)
            LiveTrackMap.route(
              route: TrackRoute(
                from: LatLng(fromLat, fromLng),
                to: LatLng(toLat, toLng),
                status: status,
                vehicleType: vehicle,
                fromLabel: fromText,
                toLabel: toText,
                distanceKm: n('distance_km'),
              ),
              vehicle: car,
              heading: n('heading'),
              ageSec: locAt == null
                  ? null
                  : DateTime.now().difference(locAt.toLocal()).inSeconds,
              height: 260,
            )
          else
            RouteMap(
              from: LatLng(fromLat, fromLng),
              to: LatLng(toLat, toLng),
              height: 220,
              fromLabel: fromText,
              toLabel: toText,
              distanceKm: n('distance_km'),
            ),
        ],
        const SizedBox(height: 12),
        SectionCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RouteLine(from: fromText, to: toText),
              const Divider(height: 20),
              InfoRow(t('Көлік'), vehicle.label),
              if (executorName.isNotEmpty)
                InfoRow(t('Жүргізуші'), executorName),
              if (d['distance_km'] != null)
                InfoRow(
                  t('Қашықтық'),
                  '${(d['distance_km'] as num).toStringAsFixed(1)} км',
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const _TasuPromo(),
      ],
    );
  }
}

/// Жүктің қазіргі күйі — бір ірі жол + қадамдар жолағы.
class _StatusHero extends StatelessWidget {
  final String status;
  final VehicleType vehicle;
  final double? kmLeft;
  final bool isRecipient;

  const _StatusHero({
    required this.status,
    required this.vehicle,
    required this.kmLeft,
    required this.isRecipient,
  });

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color, String title) = switch (status) {
      'searching' => (Icons.search_rounded, Gz.info, t('Жүргізуші ізделуде')),
      'accepted' => (
        Icons.local_shipping_outlined,
        Gz.info,
        t('Жүргізуші жүкті алуға бара жатыр'),
      ),
      'arrived' ||
      'loading' => (Icons.inventory_2_outlined, Gz.warning, t('Жүк тиелуде')),
      'in_transit' => (
        Icons.local_shipping_rounded,
        Gz.success,
        isRecipient ? t('Жүк сізге келе жатыр') : t('Жүк жолда'),
      ),
      'completed' => (Icons.check_circle_rounded, Gz.success, t('Жеткізілді')),
      'cancelled' => (Icons.cancel_outlined, Gz.danger, t('Заказ тоқтатылды')),
      _ => (
        Icons.schedule_rounded,
        Gz.textSecondary,
        t('Заказдың мерзімі өтті'),
      ),
    };
    final steps = ['accepted', 'loading', 'in_transit', 'completed'];
    final cur = switch (status) {
      'arrived' => 'loading',
      _ => status,
    };
    final idx = steps.indexOf(cur);
    final km = kmLeft;
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
                  color: Gz.tint(color, 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Gz.h3),
                    // Тек шамалас қашықтық (≈) — ойдан шығарылған «~N мин»
                    // көрсетілмейді. Жүргізуші аты төмендегі маршрут
                    // карточкасында (екі рет қайталанбасын).
                    if (km != null)
                      Text(
                        '≈ ${Geo.formatDistance(km)} ${t('қалды')}',
                        style: Gz.caption,
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (idx >= 0) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                for (var i = 0; i < steps.length; i++)
                  Expanded(
                    child: Container(
                      height: 4,
                      margin: EdgeInsets.only(
                        right: i < steps.length - 1 ? 4 : 0,
                      ),
                      decoration: BoxDecoration(
                        color: i <= idx ? Gz.green : Gz.disabledBg,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Үлкен ЖЕТКІЗУ КОДЫ — алушы жүкті алғанда жүргізушіге айтады.
class _CodeCard extends StatelessWidget {
  final String code;
  const _CodeCard({required this.code});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        gradient: Gz.brandGradient,
        borderRadius: BorderRadius.circular(Gz.rLg),
        boxShadow: Gz.glow(Gz.yellow, alpha: 0.3, blur: 18),
      ),
      child: Column(
        children: [
          Text(
            t('Жеткізу коды'),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Gz.onBrand,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            code.split('').join(' '),
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: 10,
              color: Gz.onBrand,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            t(
              'Жүкті қолыңызға алғанда жүргізушіге айтыңыз. Оған дейін '
              'ешкімге бермеңіз.',
            ),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Gz.ink),
          ),
        ],
      ),
    );
  }
}

/// Tasu-ны таныстыру — сілтемені ашқан әр адам үшін.
class _TasuPromo extends StatelessWidget {
  const _TasuPromo();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Gz.inkFill,
        borderRadius: BorderRadius.circular(Gz.rLg),
      ),
      child: Row(
        children: [
          Image.asset(
            'assets/icon/tasu_logo.png',
            height: 48,
            width: 48 * 826 / 1013,
            filterQuality: FilterQuality.medium,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tasu',
                  style: TextStyle(
                    color: Gz.yellow,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  t('Газель, жүк көлігі, такси — бағаны өзіңіз ұсынасыз.'),
                  style: const TextStyle(color: Gz.onDarkMuted, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Gz.yellow,
              foregroundColor: Gz.onBrand,
              minimumSize: const Size(0, 40),
            ),
            onPressed: () => launchUrl(Uri.parse(Env.webBaseUrl)),
            child: Text(t('Ашу')),
          ),
        ],
      ),
    );
  }
}
