import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/geo.dart';
import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/prefs.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/app_drawer.dart';
import '../auth/executor_apply_screen.dart';
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
      drawer: const AppDrawer(),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // жоғарғы жолақ: лого (sidebar батырмасы) + баланс
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 12, 8),
              child: Row(
                children: [
                  // Логотип — sidebar ашатын батырма: профиль, баланс, табыс,
                  // хабарландырулар тақтасы — бәрі сонда (бөлек «Профиль»
                  // табы жойылды).
                  Builder(
                    builder: (ctx) => Material(
                      elevation: 2,
                      borderRadius: BorderRadius.circular(10),
                      clipBehavior: Clip.antiAlias,
                      color: Gz.surface,
                      child: InkWell(
                        onTap: () => Scaffold.of(ctx).openDrawer(),
                        child: Image.asset(
                          'assets/icon/icon.png',
                          width: 40,
                          height: 40,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  _BalancePill(
                    balance: s?.balance,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const BalanceScreen()),
                    ),
                  ),
                ],
              ),
            ),
            // тариф / аккаунт күйі басқару жолағы
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: _LineControlBar(stats: s, ep: ep),
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
              const Icon(
                Icons.account_balance_wallet_outlined,
                size: 18,
                color: Gz.yellowDark,
              ),
              const SizedBox(width: 7),
              Text(
                balance == null ? '—' : fmtT(balance),
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
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
  final ExecutorProfile? ep;
  const _LineControlBar({required this.stats, required this.ep});

  void _openTariffs(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ExecutorDashboardScreen()));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = stats;
    final e = ep;

    // Аккаунт әлі РАСТАЛМАҒАН — тариф картасының орнына күй картасы
    // (тарифті тек расталған орындаушы сатып ала алады).
    if (e != null && e.status != 'approved') {
      if (e.status == 'rejected') {
        return _StatusCard(
          icon: Icons.cancel_outlined,
          color: Gz.red,
          title: t('Өтінім қабылданбады'),
          subtitle: e.moderationComment?.isNotEmpty == true
              ? e.moderationComment!
              : t('Деректерді түзетіп, қайта жіберіңіз.'),
          actionLabel: t('Қайта толтыру'),
          onAction: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => ExecutorApplyScreen(existing: e)),
          ),
        );
      }
      // pending — қаралуда
      return _StatusCard(
        icon: Icons.hourglass_top,
        color: Gz.blue,
        title: t('Аккаунтыңыз тексеруде'),
        subtitle: t(
          'Модератор құжаттарыңызды тексеруде. Расталған соң тариф '
          'сатып алып, заказ қабылдай аласыз.',
        ),
        actionLabel: t('Күйін тексеру'),
        onAction: () => ref.invalidate(myExecutorProfileProvider),
      );
    }

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
                  children: [
                    Text(
                      t('Тарифіңіз жоқ'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                      ),
                    ),
                    Text(
                      t('Заказ қабылдау үшін тариф сатып алыңыз'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Gz.textSecondary,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => _openTariffs(context),
                child: Text(t('Кіру')),
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
                        Text(
                          t('Тариф пен баланс'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          '${t('Белсенді')} · ${_tariffLabel(s)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Gz.green,
                            fontSize: 12.5,
                          ),
                        ),
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
    if (s.ordersLeft > 0) parts.add('${t('Тариф')} ${s.ordersLeft}/10');
    if (parts.isEmpty) return t('Тариф жоқ');
    return parts.join(' · ');
  }
}

/// Аккаунт күйінің картасы (тексеруде / қабылданбады) — тариф картасының
/// орнына көрсетіледі. Оң жақта міндетті емес әрекет батырмасы болады
/// (қайта толтыру / күйін тексеру).
class _StatusCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  const _StatusCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: Gz.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        boxShadow: Gz.cardShadow,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Gz.textSecondary,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(width: 8),
            FilledButton(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: onAction,
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

/// Жаңа заказ уведомлениелерін қосу/өшіру тумблері. Сервердегі мәнге
/// (`executor_profiles.order_push_enabled`) сай инициализацияланады — сол
/// мән арқылы push ҚОСЫМША ЖАБЫҚ болса да келеді (0028); жергілікті Prefs
/// қосымша тірі/фонда тұрғанда жылдам foreground хабарлау үшін сақталады.
class _OrderNotifyToggle extends ConsumerStatefulWidget {
  const _OrderNotifyToggle();

  @override
  ConsumerState<_OrderNotifyToggle> createState() => _OrderNotifyToggleState();
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
          Icon(
            _on ? Icons.notifications_active : Icons.notifications_off,
            size: 20,
            color: _on ? Gz.yellowDark : Gz.textSecondary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              t('Заказдарға уведомление'),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
          ),
          Switch(value: _on, activeThumbColor: Gz.green, onChanged: _toggle),
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
    final (_, city) = await Geo.reverseWithCity(
      LatLng(pos.latitude, pos.longitude),
    );
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
        showSnack(context, '${t('Қала')} $city ${t('болып ауыстырылды')}');
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
              '${t('Қазір')} $city ${t('қаласындасыз (тіркелген:')} '
              '${widget.ep.city ?? '—'}). ${t('Ауыстырайық па?')}',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 6),
          _switching
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : TextButton(
                  onPressed: _switchCity,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    t('Ауыстыру'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
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
