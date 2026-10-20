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
import '../../shared/status_check.dart';
import '../../shared/widgets.dart';
import '../auth/executor_apply_screen.dart';
import 'balance_screen.dart';
import 'dashboard_screen.dart';
import 'docs_banner.dart';
import 'feed_screen.dart';

/// Орындаушының басты беті — клиенттегідей бір экранды дизайн:
/// негізгі мазмұн = заказдар лентасы, жоғарыда шағын басқару жолағы
/// (баланс, линия/тариф) «бұрыштарда» тұрады. Табыс профильдің ішінде.
/// Жоғарғы жолақ элементтерінің ортақ биіктігі.
const double _barH = 44;

class ExecutorHomeScreen extends ConsumerWidget {
  const ExecutorHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(executorStatsStreamProvider).value;
    final epAsync = ref.watch(myExecutorProfileProvider);
    final ep = epAsync.value;
    // Өтінім ЖОҚ екені — деректер КЕЛГЕН соң ғана (жүктелу кезінде де
    // `value == null` болады, оны «өтінімсіз» деп оқыса, расталған
    // орындаушыға да «Өтінім толтырыңыз» картасы жыпылықтап кетер еді).
    final noApplication = epAsync.hasValue && ep == null;
    return Scaffold(
      drawer: const AppDrawer(),
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                // жоғарғы жолақ: ☰ мәзір + уведомление + баланс
                // Үшеуі БІРДЕЙ биіктікте (44): жолақ ықшам әрі тегіс.
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: Row(
                    children: [
                      // «☰» — бүйір мәзір: профиль, заказдарым, баланс,
                      // табыс, хабарландырулар тақтасы. Клиенттегідей АЙҚЫН
                      // батырма (бұрын логотип болатын — түйме деп
                      // танылмайтын); белсенді заказ саны бұрышында.
                      Builder(
                        builder: (ctx) => MapRoundButton(
                          icon: Icons.menu_rounded,
                          tooltip: t('Мәзір'),
                          size: _barH,
                          // Белсенді заказдар + оқылмаған хабарламалар
                          // (0080) — мәзірде не күтіп тұрғаны бір белгіден.
                          badge:
                              (ref
                                      .watch(myActiveExecutorOrdersProvider)
                                      .value
                                      ?.length ??
                                  0) +
                              (ref.watch(unreadNotificationsProvider).value ??
                                  0),
                          onTap: () => Scaffold.of(ctx).openDrawer(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Уведомление тумблері — БАЛАНСТЫҢ СОЛ ЖАҒЫНДА.
                      // Бұрын тариф картасының АСТЫНДА, толық ені бар бөлек
                      // жолақ болатын: экранның бір қатарын алып тұрса да,
                      // тек бір қосқыш еді. Енді жоғарғы жолақтың бос орнына
                      // сыйып тұр, жазуы да қысқарды («Уведомление»).
                      // Тек РАСТАЛҒАН орындаушыда: өтінімі қаралып жатқан
                      // адамға жаңа заказ хабары әлі келмейді.
                      if (ep != null && ep.status == 'approved')
                        const Expanded(
                          child: SizedBox(
                            height: _barH,
                            child: _OrderNotifyToggle(),
                          ),
                        )
                      else
                        const Spacer(),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: _barH,
                        child: _BalancePill(
                          balance: s?.balance,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const BalanceScreen(),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // тариф / аккаунт күйі басқару жолағы
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: _LineControlBar(
                    stats: s,
                    ep: ep,
                    noApplication: noApplication,
                  ),
                ),
                // модератордың құжат жаңарту хабары (басты бетте де)
                if (ep != null &&
                    (ep.docsUpdateRequested || ep.docsReviewPending))
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
    return PressScale(
      child: Material(
        color: Gz.surface,
        elevation: 0,
        shape: StadiumBorder(
          side: BorderSide(
            color: Gz.yellow.withValues(alpha: 0.55),
            width: 1.4,
          ),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 8, 0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.account_balance_wallet_rounded,
                  size: 18,
                  color: Gz.yellowDark,
                ),
                const SizedBox(width: 7),
                Text(
                  balance == null ? '—' : fmtT(balance),
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(width: 7),
                // «+» — жалаң иконка емес, САРЫ дөңгелек: «баланс толтыру»
                // әрекеті таблетканың ішіндегі нақты түймедей көрінеді.
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    gradient: Gz.brandGradient,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.add_rounded, size: 16, color: Gz.onBrand),
                ),
              ],
            ),
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

  /// Өтінім МҮЛДЕМ толтырылмаған (0063). `ep == null`-дан бөлек беріледі:
  /// профиль әлі ЖҮКТЕЛІП ЖАТҚАНДА да `ep` null болады.
  final bool noApplication;
  const _LineControlBar({
    required this.stats,
    required this.ep,
    required this.noApplication,
  });

  void _openTariffs(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ExecutorDashboardScreen()));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = stats;
    final e = ep;

    // ӨТІНІМ ӘЛІ ЖОҚ (0063 «танысу режимі») — тариф картасының орнына
    // өтінімге ШАҚЫРУ. Заказдар лентасы астында ашық тұрады: адам алдымен
    // қандай жұмыс бар екенін көреді де, содан кейін өзі шешеді.
    if (noApplication) {
      return _StatusCard(
        icon: Icons.assignment_outlined,
        color: Gz.blue,
        title: t('Заказдармен таныса беріңіз'),
        subtitle: t(
          'Заказ қабылдау үшін өтінім толтырыңыз: көлігіңіз бен '
          'құжаттарыңыз. Модератор растаған соң тариф алып, жұмысқа '
          'кірісесіз.',
        ),
        actionLabel: t('Өтінім толтыру'),
        onAction: () async => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const ExecutorApplyScreen())),
      );
    }

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
          onAction: () async => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => ExecutorApplyScreen(existing: e)),
          ),
        );
      }
      // pending — қаралуда
      return _StatusCard(
        icon: Icons.hourglass_top,
        color: Gz.blue,
        title: t('Өтінім тексеруде'),
        subtitle: t(
          'Модератор құжаттарыңызды қарауда — әдетте 24 сағатқа '
          'дейін. Расталған соң хабарлама келеді, содан кейін тариф алып '
          'заказ қабылдайсыз.',
        ),
        actionLabel: t('Күйін тексеру'),
        onAction: () => checkExecutorStatus(context, ref),
      );
    }

    final hasTariff = s != null && s.hasTariff;

    // Тариф жоқ — тариф сатып алуға шақыру картасы (ТІК орналасу:
    // мәтінге толық ен тиеді, батырма астында толық жазуымен тұрады).
    if (!hasTariff) {
      return _StatusCard(
        icon: Icons.bolt,
        color: Gz.yellowDark,
        title: t('Тарифіңіз жоқ'),
        subtitle: t('Заказ қабылдау үшін тариф сатып алыңыз'),
        actionLabel: t('Тарифке кіру'),
        onAction: () async => _openTariffs(context),
      );
    }

    // Ауысымға берілетін заказ саны — модератор баптауы (0056). Бұрын
    // мұнда «/10» ҚАТЫП тұрған еді: модератор лимитті 20 қойса, орындаушы
    // «20/10» деген мағынасыз жазуды көретін. Енді нақты баптаудан алынады
    // (жүктелмей тұрса — қалған саннан кем болмайтын мән).
    final perShift = ref.watch(appConfigProvider).value?.ordersPerShift;
    final total = (perShift == null || perShift < s.ordersLeft)
        ? s.ordersLeft
        : perShift;
    final used = (total - s.ordersLeft).clamp(0, total);

    // Тариф белсенді — ЫҚШАМ бір қатарлы жолақ (бұрын екі қатарлы үлкен
    // жасыл карточка еді — заказдар лентасының орнын алып тұратын).
    // Жасыл түс — тек «белсенді» белгісінде, фон ақ.
    final progress = total > 0 ? (used / total).clamp(0.0, 1.0) : 0.0;
    return Material(
      color: Gz.surface,
      borderRadius: BorderRadius.circular(Gz.rMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(Gz.rMd),
        onTap: () => _openTariffs(context),
        child: Container(
          height: 46,
          padding: const EdgeInsets.fromLTRB(12, 0, 6, 0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Gz.rMd),
            border: Border.all(color: Gz.border),
          ),
          child: Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: const BoxDecoration(
                  color: Gz.greenBright,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 9),
              Flexible(
                child: Text(
                  '${t('Белсенді')} · ${_tariffLabel(s, total)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              if (total > 0) ...[
                const SizedBox(width: 10),
                // Ауысым лимитінің прогресі — таусылуға жақындағанда сарыға
                // ауысады (лимит бітсе тариф жабылады).
                SizedBox(
                  width: 56,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(Gz.rXs),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 6,
                      backgroundColor: Gz.tint(Gz.greenBright, 0.18),
                      valueColor: AlwaysStoppedAnimation(
                        s.ordersLeft <= 2 ? Gz.amber : Gz.greenBright,
                      ),
                    ),
                  ),
                ),
              ],
              Icon(Icons.chevron_right_rounded, color: Gz.textTertiary),
            ],
          ),
        ),
      ),
    );
  }

  /// «Ауысымда 7/10 заказ» — модератор қойған лимитке қатысты нақты сан.
  String _tariffLabel(ExecutorStats s, int total) {
    if (s.ordersLeft <= 0) return t('Тариф жоқ');
    return '${t('Ауысымда')} ${s.ordersLeft}/$total ${t('заказ')}';
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

  /// Async болуы МАҢЫЗДЫ: «Күйін тексеру» басылғанда spinner көрінеді де,
  /// нәтижесі snackbar-мен айтылады. Бұрын түйме үнсіз ғана деректі қайта
  /// сұрайтын — қолданушыға ЕШТЕҢЕ өзгермеген болып көрініп, «не тексеріп
  /// жатыр, жауабы қайда?» деп шатасатын.
  final Future<void> Function()? onAction;
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
    // ТІК орналасу (иконка+мәтін жоғарыда, батырма толық енімен астында).
    // Бұрын үшеуі БІР ҚАТАРДА тұратын: батырма («Проверить статус») өз
    // енін алып, мәтінге тек 100px қалатын да, тақырып та, түсініктеме де
    // «Ваш а…», «Модератор прове ряет ва…» болып қиылып, оқылмайтын еді.
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      decoration: BoxDecoration(
        // Карта өз түсінің ӨТЕ ЖЕҢІЛ реңкінен ақ түске ауысады: күйдің
        // мағынасы (күту / қате / шақыру) фоннан-ақ оқылады.
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Gz.tint(color, 0.09), Gz.surface],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.32)),
        boxShadow: Gz.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: Gz.tint(color, 0.15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Gz.tint(color, 0.22), width: 1.2),
                ),
                child: Icon(icon, color: color, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        height: 1.25,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Gz.textSecondary,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 14),
            // BusyButton — басылғанда spinner көрсетеді (әрекет шынымен
            // жүріп жатқаны көрініп тұрады).
            BusyButton(label: actionLabel!, onPressed: onAction!),
          ],
        ],
      ),
    );
  }
}

/// Жаңа заказ уведомлениелерін қосу/өшіру тумблері — ЖОҒАРҒЫ ЖОЛАҚТА,
/// баланс «таблеткасының» СОЛ ЖАҒЫНДА тұратын ықшам «таблетка».
///
/// Сервердегі мәнге (`executor_profiles.order_push_enabled`) сай
/// инициализацияланады — сол мән арқылы push ҚОСЫМША ЖАБЫҚ болса да келеді
/// (0028); жергілікті Prefs қосымша тірі/фонда тұрғанда жылдам foreground
/// хабарлау үшін сақталады.
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
    return Material(
      color: _on ? Gz.surface : Gz.surfaceAlt,
      elevation: 0,
      shape: StadiumBorder(
        // Қосулы күйде жиегі ЖАСЫЛ, өшірулі күйде — бейтарап сұр: тумблерге
        // қарамай-ақ, таблетканың өзінен күйі оқылады.
        side: BorderSide(
          color: _on ? Gz.green.withValues(alpha: 0.45) : Gz.border,
          width: 1.4,
        ),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        // Жазуды түртсе де қосылады/өшеді — кішкентай тумблерді дәл басу
        // қиын (әсіресе қолғаппен).
        onTap: () => _toggle(!_on),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(11, 2, 2, 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _on
                    ? Icons.notifications_active_rounded
                    : Icons.notifications_off_rounded,
                size: 18,
                color: _on ? Gz.green : Gz.textTertiary,
              ),
              const SizedBox(width: 6),
              // Жазу ҚЫСҚАРДЫ («Заказдарға уведомление» → «Уведомление»):
              // таблетка жоғарғы жолақтағы бос орынға сыюы керек. Тар
              // экранда (не жүйе шрифті үлкейтілгенде) FittedBox оны
              // кішірейтеді — ЕШҚАШАН екінші жолға түспейді.
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    t('Уведомление'),
                    maxLines: 1,
                    softWrap: false,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              // Стандарт Switch таблеткаға сыймайды — кішірейтіп қоямыз.
              Transform.scale(
                scale: 0.75,
                child: Switch(
                  value: _on,
                  activeThumbColor: Gz.green,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: _toggle,
                ),
              ),
            ],
          ),
        ),
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
    final p = LatLng(pos.latitude, pos.longitude);
    // ТІРЕК қала (лентаның қала сүзгісі осы бойынша жүреді). Reverse-геокодер
    // қайтаратын нақты елді мекенді («Қосшы», «Луговой») алсақ, орындаушының
    // қаласы сол ауыл болып өзгеріп, лентадағы БАРЛЫҚ заказ жоғалып кетеді.
    final anchor = Geo.anchorCity(p);
    if (mounted) setState(() => _detectedCity = anchor);
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
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Gz.blue.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.location_on_outlined, color: Gz.blue, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${t('Қазір')} $city ${t('қаласындасыз (тіркелген:')} '
              '${widget.ep.city ?? '—'}). ${t('Ауыстырайық па?')}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
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
            icon: Icon(Icons.close, color: Gz.textSecondary),
          ),
        ],
      ),
    );
  }
}
