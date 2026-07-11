import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/geo.dart';
import '../../core/models.dart';
import '../../core/prefs.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import 'balance_screen.dart';
import 'dashboard_screen.dart';
import 'docs_banner.dart';
import 'feed_screen.dart';

/// Орындаушының басты беті — клиенттегідей бір экранды дизайн:
/// негізгі мазмұн = заказдар лентасы, жоғарыда шағын басқару жолағы
/// (баланс, линия/тариф) «бұрыштарда» тұрады. Табыс профильдің ішінде.
class ExecutorHomeScreen extends ConsumerWidget {
  const ExecutorHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(executorStatsStreamProvider).value;
    final ep = ref.watch(myExecutorProfileProvider).value;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // жоғарғы жолақ: лого + баланс
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 12, 8),
              child: Row(
                children: [
                  const GazelGoLogo(size: 20),
                  const Spacer(),
                  _BalancePill(
                    balance: s?.balance,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const BalanceScreen())),
                  ),
                ],
              ),
            ),
            // тариф басқару жолағы
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: _LineControlBar(stats: s),
            ),
            // модератордың құжат жаңарту хабары (басты бетте де)
            if (ep != null && (ep.docsUpdateRequested || ep.docsReviewPending))
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: ExecutorDocsBanner(ep: ep),
              ),
            // GPS қаласы тіркелген қаладан өзгеше болса — ауыстыруды ұсынады
            if (ep != null) _CitySwitchBanner(ep: ep),
            // заказдар лентасы (негізгі мазмұн)
            const Expanded(child: ExecutorFeedBody()),
          ],
        ),
      ),
    );
  }
}

/// Балансты көрсететін шағын «таблетка» — түртсе, толтыру экраны ашылады.
class _BalancePill extends StatelessWidget {
  final int? balance;
  final VoidCallback onTap;
  const _BalancePill({required this.balance, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Gz.surface,
      elevation: 1.5,
      shadowColor: Colors.black26,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.account_balance_wallet_outlined,
                  size: 18, color: Gz.yellowDark),
              const SizedBox(width: 7),
              Text(balance == null ? '—' : fmtT(balance),
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 14)),
              const SizedBox(width: 4),
              const Icon(Icons.add, size: 16, color: Gz.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Линия статусы + жедел қосу/өшіру ауыстырғышы + тарифті басқару.
/// Тариф белсенді емес болса — «Тарифке кіру» шақыруы көрсетіледі.
class _LineControlBar extends ConsumerWidget {
  final ExecutorStats? stats;
  const _LineControlBar({required this.stats});

  void _openTariffs(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const ExecutorDashboardScreen()));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = stats;
    final hasTariff = s != null && s.hasTariff;

    // Тариф жоқ — тариф сатып алуға шақыру картасы
    if (!hasTariff) {
      return InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openTariffs(context),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          decoration: BoxDecoration(
            color: Gz.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Gz.border),
            boxShadow: Gz.cardShadow,
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Gz.yellow.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.bolt, color: Gz.yellowDark, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('Тарифіңіз жоқ',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 14.5)),
                    Text('Заказ қабылдау үшін тариф сатып алыңыз',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: Gz.textSecondary, fontSize: 12.5)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => _openTariffs(context),
                child: const Text('Кіру'),
              ),
            ],
          ),
        ),
      );
    }

    // Тариф белсенді — толық ені бар «Тариф пен баланс» түймесі + астында
    // жаңа заказ уведомлениесін қосу/өшіру тумблері.
    return Column(
      children: [
        Material(
          color: Gz.surface,
          elevation: 0,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _openTariffs(context),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Gz.green.withValues(alpha: 0.4)),
                boxShadow: Gz.cardShadow,
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Gz.green, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Тариф пен баланс',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 15)),
                        Text('Белсенді · ${_tariffLabel(s)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Gz.green, fontSize: 12.5)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Gz.textSecondary),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        const _OrderNotifyToggle(),
      ],
    );
  }

  String _tariffLabel(ExecutorStats s) {
    final parts = <String>[];
    if (s.trialActive) parts.add('Тегін кезең');
    // Әр тариф өз лимитімен бөлек көрсетіледі (қосылмайды).
    if (s.simpleActive) parts.add('Простой ${s.simpleLeft}/10');
    if (s.vipActive) parts.add('VIP ${s.vipLeft}/10');
    if (parts.isEmpty) return 'Тариф жоқ';
    return parts.join(' · ');
  }
}

/// Жаңа заказ уведомлениелерін қосу/өшіру тумблері. Сервердегі мәнге
/// (`executor_profiles.order_push_enabled`) сай инициализацияланады — сол
/// мән арқылы push ҚОСЫМША ЖАБЫҚ болса да келеді (0028); жергілікті Prefs
/// қосымша тірі/фонда тұрғанда жылдам foreground хабарлау үшін сақталады.
class _OrderNotifyToggle extends ConsumerStatefulWidget {
  const _OrderNotifyToggle();

  @override
  ConsumerState<_OrderNotifyToggle> createState() =>
      _OrderNotifyToggleState();
}

class _OrderNotifyToggleState extends ConsumerState<_OrderNotifyToggle> {
  bool _on = true;
  bool _initialized = false;

  void _initFrom(bool serverValue) {
    if (_initialized) return;
    _initialized = true;
    _on = serverValue;
    Prefs.setOrderNotify(serverValue);
  }

  Future<void> _toggle(bool v) async {
    setState(() => _on = v);
    await Prefs.setOrderNotify(v);
    try {
      await Repo.setOrderPushEnabled(v);
    } catch (e) {
      if (mounted) showSnack(context, errText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ep = ref.watch(myExecutorProfileProvider).value;
    if (ep != null) _initFrom(ep.orderPushEnabled);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
      decoration: BoxDecoration(
        color: Gz.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Gz.border),
      ),
      child: Row(
        children: [
          Icon(_on ? Icons.notifications_active : Icons.notifications_off,
              size: 20, color: _on ? Gz.yellowDark : Gz.textSecondary),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('Заказдарға уведомление',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          ),
          Switch(
            value: _on,
            activeThumbColor: Gz.green,
            onChanged: _toggle,
          ),
        ],
      ),
    );
  }
}

/// Орындаушының GPS арқылы анықталған қаласы тіркелген қаладан өзгеше болса
/// (мыс. басқа қалаға сапарға шықса), қаланы ауыстыруды ұсынады.
class _CitySwitchBanner extends ConsumerStatefulWidget {
  final ExecutorProfile ep;
  const _CitySwitchBanner({required this.ep});

  @override
  ConsumerState<_CitySwitchBanner> createState() => _CitySwitchBannerState();
}

class _CitySwitchBannerState extends ConsumerState<_CitySwitchBanner> {
  String? _detectedCity;
  bool _dismissed = false;
  bool _switching = false;

  @override
  void initState() {
    super.initState();
    _detect();
  }

  Future<void> _detect() async {
    final pos = await Geo.currentPosition();
    if (pos == null || !mounted) return;
    final (_, city) =
        await Geo.reverseWithCity(LatLng(pos.latitude, pos.longitude));
    if (mounted) setState(() => _detectedCity = city);
  }

  Future<void> _switchCity() async {
    final city = _detectedCity;
    if (city == null) return;
    setState(() => _switching = true);
    try {
      await Repo.setExecutorCity(city);
      ref.invalidate(myExecutorProfileProvider);
      ref.invalidate(executorFeedStreamProvider);
      if (mounted) {
        showSnack(context, 'Қала $city болып ауыстырылды');
        setState(() => _dismissed = true);
      }
    } catch (e) {
      if (mounted) showSnack(context, errText(e), error: true);
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final city = _detectedCity;
    if (_dismissed || city == null || Geo.sameCity(city, widget.ep.city)) {
      return const SizedBox.shrink();
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Gz.blue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Gz.blue.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.location_on_outlined, color: Gz.blue, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Қазір $city қаласындасыз (тіркелген: '
              '${widget.ep.city ?? '—'}). Ауыстырайық па?',
              style:
                  const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 6),
          _switching
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : TextButton(
                  onPressed: _switchCity,
                  style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  child: const Text('Ауыстыру',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                ),
          IconButton(
            iconSize: 18,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => setState(() => _dismissed = true),
            icon: const Icon(Icons.close, color: Gz.textSecondary),
          ),
        ],
      ),
    );
  }
}
