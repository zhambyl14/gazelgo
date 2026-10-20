import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import 'app_settings_screen.dart';
import 'applications_screen.dart';
import 'audit_log_screen.dart';
import 'broadcast_screen.dart';
import 'clients_screen.dart';
import 'executors_screen.dart';
import 'line_screen.dart';
import 'listings_admin_screen.dart';
import 'live_map_screen.dart';
import 'news_admin_screen.dart';
import 'order_chats_screen.dart';
import 'orders_screen.dart';
import 'overview_screen.dart';
import 'reports_screen.dart';
import 'staff_screen.dart';
import 'support_admin_screen.dart';
import 'topups_screen.dart';
import 'vehicle_types_screen.dart';

/// Модератор панелі.
///
/// БҰРЫН: 12 қойынды бір көлденең жолда — керегін табу үшін жолақты
/// солға-оңға айналдыру керек еді, ал қай бөлімде жұмыс күтіп тұрғаны
/// мүлдем көрінбейтін. ЕНДІ: мағынасы бойынша ТОПТАЛҒАН бүйір мәзір
/// (Басқару · Адамдар · Қаржы · Байланыс · Контент · Жүйе), әр бөлімде
/// күтіп тұрған істердің САНЫ (өтінімдер, толтырулар, чаттар, шағымдар),
/// ал «☰» батырмасының бұрышында — барлығының қосындысы.
///
/// ҚОЛДАУ ҚЫЗМЕТКЕРІ (0084) де осы панельге кіреді, бірақ мәзірде тек
/// модератор оған ашқан бөлімдер көрінеді ([Profile.modCan]).
class ModeratorShell extends ConsumerStatefulWidget {
  const ModeratorShell({super.key});

  // Бөлім нөмірлері — push-хабарламадан өту үшін ([openTab]). Мәндері
  // ӨЗГЕРМЕЙДІ: main.dart пен Шолу экраны осы тұрақтыларды қолданады.
  static const int tabOverview = 0;
  static const int tabLine = 1;
  static const int tabApplications = 2;
  static const int tabTopups = 3;
  static const int tabExecutors = 4;
  static const int tabSupport = 5;
  static const int tabReports = 6;
  static const int tabVehicles = 7;
  static const int tabNews = 8;
  static const int tabSettings = 9;
  static const int tabClients = 10;
  static const int tabOrders = 11;
  static const int tabOrderChats = 12;
  static const int tabBroadcast = 13;
  static const int tabAudit = 14;
  static const int tabLiveMap = 15;
  static const int tabStaff = 16;

  /// Бөлімге өту сұранысы (push-хабарламаны басқанда, Шолудан).
  static final ValueNotifier<int?> tabRequest = ValueNotifier<int?>(null);

  /// Панель әлі ашылмаған болса (қосымша жабық тұрғанда push басылды), мән
  /// осы жерде сақталып тұрады да, панель құрылған сәтте қолданылады.
  static void openTab(int index) => tabRequest.value = index;

  @override
  ConsumerState<ModeratorShell> createState() => _ModeratorShellState();
}

/// Мәзірдегі бір бөлім.
class _Section {
  final int index;
  final IconData icon;
  final Color color;
  final String Function() title;
  final Widget Function() build;

  /// Қызметкерге қажет рұқсат кілті (0084). null — тек толық модератор.
  final String? perm;

  /// Шолу статистикасынан күтіп тұрған істердің санын алу.
  final int Function(Map<String, dynamic> s)? badge;

  const _Section(
    this.index,
    this.icon,
    this.color,
    this.title,
    this.build, {
    required this.perm,
    this.badge,
  });
}

class _ModeratorShellState extends ConsumerState<ModeratorShell> {
  int _index = ModeratorShell.tabOverview;

  /// Ағымдағы адам (модератор не қызметкер). Қызметкерде [_loadStats]
  /// сайын жаңартылады — модератор рұқсатты өзгертсе, мәзір қайта кірмей-ақ
  /// жаңарады. Профиль жоқ болса, мәзір бос тұрады (толық деп есептемейміз).
  late Profile? _me = ref.read(myProfileProvider).value;

  bool _allowed(_Section s) {
    final me = _me;
    if (me == null) return false;
    return s.perm == null ? me.isFullModerator : me.modCan(s.perm!);
  }
  final _scaffold = GlobalKey<ScaffoldState>();
  Map<String, dynamic> _stats = const {};
  Timer? _timer;

  static int _n(Map<String, dynamic> s, String k) {
    final v = s[k];
    return v is num ? v.toInt() : int.tryParse('$v') ?? 0;
  }

  /// Топтар мен бөлімдер — мәзір осы тізімнен салынады.
  late final List<(String Function(), List<_Section>)> _groups = [
    (
      () => t('Басқару'),
      [
        _Section(
          ModeratorShell.tabOverview,
          perm: 'overview',
          Icons.space_dashboard_outlined,
          Gz.ink,
          () => t('Шолу'),
          () => const ModeratorOverviewScreen(),
        ),
        _Section(
          ModeratorShell.tabLine,
          perm: 'line',
          Icons.sensors_rounded,
          Gz.green,
          () => t('Линия'),
          () => const LineScreen(),
        ),
        _Section(
          ModeratorShell.tabLiveMap,
          perm: 'live_map',
          Icons.map_outlined,
          Gz.blue,
          () => t('Тірі карта'),
          () => const LiveMapScreen(),
        ),
        _Section(
          ModeratorShell.tabOrders,
          perm: 'orders',
          Icons.receipt_long_outlined,
          Gz.violet,
          () => t('Заказдар'),
          () => const OrdersScreen(),
        ),
      ],
    ),
    (
      () => t('Адамдар'),
      [
        _Section(
          ModeratorShell.tabApplications,
          perm: 'applications',
          Icons.assignment_ind_outlined,
          Gz.blue,
          () => t('Өтінімдер'),
          () => const ApplicationsScreen(),
          badge: (s) =>
              _n(s, 'applications_pending') + _n(s, 'docs_review_pending'),
        ),
        _Section(
          ModeratorShell.tabExecutors,
          perm: 'executors',
          Icons.local_shipping_outlined,
          Gz.ink,
          () => t('Орындаушылар'),
          () => const ExecutorsScreen(),
        ),
        _Section(
          ModeratorShell.tabClients,
          perm: 'clients',
          Icons.people_outline_rounded,
          Gz.blue,
          () => t('Клиенттер'),
          () => const ClientsScreen(),
        ),
      ],
    ),
    (
      () => t('Қаржы'),
      [
        _Section(
          ModeratorShell.tabTopups,
          perm: 'topups',
          Icons.account_balance_wallet_outlined,
          Gz.yellowDeep,
          () => t('Толтырулар'),
          () => const TopupsScreen(),
          badge: (s) => _n(s, 'topups_pending'),
        ),
      ],
    ),
    (
      () => t('Байланыс'),
      [
        _Section(
          ModeratorShell.tabSupport,
          perm: 'support',
          Icons.support_agent_rounded,
          Gz.green,
          () => t('Қолдау'),
          () => const SupportAdminScreen(),
          badge: (s) => _n(s, 'support_open'),
        ),
        _Section(
          ModeratorShell.tabReports,
          perm: 'reports',
          Icons.flag_outlined,
          Gz.red,
          () => t('Шағымдар'),
          () => const ReportsScreen(),
          badge: (s) => _n(s, 'reports_open') + _n(s, 'listing_reports_open'),
        ),
        _Section(
          ModeratorShell.tabOrderChats,
          perm: 'order_chats',
          Icons.forum_outlined,
          Gz.blue,
          () => t('Заказ чаттары'),
          () => const OrderChatsScreen(),
        ),
        _Section(
          ModeratorShell.tabBroadcast,
          perm: 'broadcast',
          Icons.campaign_outlined,
          Gz.yellowDeep,
          () => t('Жаппай хабарлама'),
          () => const BroadcastScreen(),
        ),
      ],
    ),
    (
      () => t('Контент'),
      [
        _Section(
          ModeratorShell.tabNews,
          perm: 'news',
          Icons.auto_stories_outlined,
          Gz.violet,
          () => t('Жаңалықтар'),
          () => const NewsAdminScreen(),
        ),
        _Section(
          ModeratorShell.tabVehicles,
          perm: 'vehicles',
          Icons.directions_car_outlined,
          Gz.ink,
          () => t('Көліктер'),
          () => const VehicleTypesScreen(),
        ),
      ],
    ),
    (
      () => t('Жүйе'),
      [
        _Section(
          ModeratorShell.tabSettings,
          perm: 'settings',
          Icons.tune_rounded,
          Gz.textSecondary,
          () => t('Баптаулар'),
          () => const AppSettingsScreen(),
        ),
        _Section(
          ModeratorShell.tabAudit,
          perm: 'audit',
          Icons.history_rounded,
          Gz.textSecondary,
          () => t('Әрекеттер журналы'),
          () => const AuditLogScreen(),
        ),
        _Section(
          ModeratorShell.tabStaff,
          perm: null,
          Icons.badge_outlined,
          Gz.blue,
          () => t('Қызметкерлер'),
          () => const StaffScreen(),
        ),
      ],
    ),
  ];

  /// Осы адамға РҰҚСАТ етілген бөлімдер ғана.
  Map<int, _Section> get _byIndex => {
    for (final g in _groups)
      for (final s in g.$2)
        if (_allowed(s)) s.index: s,
  };

  int get _totalBadge {
    var sum = 0;
    for (final s in _byIndex.values) {
      sum += s.badge?.call(_stats) ?? 0;
    }
    return sum;
  }

  @override
  void initState() {
    super.initState();
    ModeratorShell.tabRequest.addListener(_applyTabRequest);
    // Қосымша ЖАБЫҚ тұрғанда push басылса, сұраныс панель құрылғанға дейін
    // қойылып қояды — сол себепті мұнда да бір рет тексереміз.
    _applyTabRequest();
    _loadStats();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _loadStats());
  }

  @override
  void dispose() {
    ModeratorShell.tabRequest.removeListener(_applyTabRequest);
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadStats() async {
    if (_me?.isStaff ?? false) unawaited(_refreshMe());
    try {
      final s = await Repo.modOverviewStats();
      if (mounted) setState(() => _stats = s);
    } catch (_) {
      // Санауыштар уақытша көрінбейді — панель жұмыс істей береді.
    }
  }

  /// Қызметкердің рұқсаттарын серверден қайта оқу.
  Future<void> _refreshMe() async {
    try {
      final p = await Repo.myProfile();
      if (!mounted || p == null) return;
      // Аккаунт өшірілсе — бұғат экранына (main.dart маршрутизаторы).
      if (p.isBlocked) {
        ref.invalidate(myProfileProvider);
        return;
      }
      setState(() => _me = p);
    } catch (_) {
      // Желі жоқ — бұрынғы рұқсаттармен жалғасады.
    }
  }

  void _applyTabRequest() {
    final index = ModeratorShell.tabRequest.value;
    if (index == null || !_byIndex.containsKey(index)) return;
    ModeratorShell.tabRequest.value = null; // бір рет қана орындалады
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Үстінде ашық тұрған бет болса (чат, өтінім беті…) — жабамыз да,
      // панельдің өзінде бөлімді ауыстырамыз. Жаңа бет ашылмайды.
      Navigator.of(context).popUntil((r) => r.isFirst);
      _select(index);
    });
  }

  void _select(int index) {
    setState(() => _index = index);
    // Бөлім ауысқанда санауыштарды бірден жаңартамыз (жұмыс жасалған соң).
    _loadStats();
  }

  @override
  Widget build(BuildContext context) {
    StaffAccess.me = _me;
    final sections = _byIndex;
    // Таңдалған бөлімге рұқсат жоқ болса (қызметкер, не рұқсаты алынды) —
    // рұқсат етілген біріншісі ашылады.
    final current =
        sections[_index] ?? (sections.isEmpty ? null : sections.values.first);
    if (current == null) {
      return Scaffold(
        appBar: AppBar(title: Text(t('Қолдау қызметі'))),
        drawer: _drawer(context),
        body: EmptyState(
          icon: Icons.lock_outline_rounded,
          title: t('Сізге әлі бөлім ашылмаған'),
          subtitle: t('Модератор рұқсат бергенде бөлімдер осында пайда болады.'),
        ),
      );
    }
    _index = current.index; // мәзірде дұрыс жол белгіленсін
    return Scaffold(
      key: _scaffold,
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Center(
            child: _MenuIcon(
              badge: _totalBadge,
              onTap: () => _scaffold.currentState?.openDrawer(),
            ),
          ),
        ),
        leadingWidth: 60,
        title: Text(current.title()),
        actions: [
          IconButton(
            tooltip: t('Жаңарту'),
            onPressed: _loadStats,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      drawer: _drawer(context),
      body: KeyedSubtree(
        key: ValueKey(current.index),
        child: current.build(),
      ),
    );
  }

  Widget _drawer(BuildContext context) {
    return Drawer(
      backgroundColor: Gz.surface,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
              child: Row(
                children: [
                  const GazelGoLogo(size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: InfoChip(
                      text: (_me?.isStaff ?? false)
                          ? t('Қолдау қызметі')
                          : t('Модератор'),
                      color: Gz.violet,
                    ),
                  ),
                  const LanguageSwitcher(),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  for (final (groupTitle, sections) in _groups)
                    if (sections.any(_allowed)) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 16, 4),
                        child: Text(
                          groupTitle().toUpperCase(),
                          style: Gz.label,
                        ),
                      ),
                      for (final s in sections)
                        if (_allowed(s)) _row(context, s),
                    ],
                  const SizedBox(height: 8),
                  if (_me?.modCan('reports') ?? false)
                    _link(
                      context,
                      Icons.storefront_outlined,
                      t('Хабарландырулар тізімі'),
                      () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ListingsAdminScreen(),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 14, 4),
              child: Row(
                children: [
                  Icon(
                    Icons.contrast_rounded,
                    size: 20,
                    color: Gz.textSecondary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(t('Түс режимі'), style: Gz.h3)),
                  const ThemeSwitcher(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: GzListRow(
                icon: Icons.logout_rounded,
                color: Gz.red,
                title: t('Шығу'),
                danger: true,
                onTap: () {
                  Navigator.of(context).pop();
                  confirmSignOut(context);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, _Section s) {
    final selected = s.index == _index;
    final badge = s.badge?.call(_stats) ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: selected ? Gz.tint(Gz.yellow, 0.18) : Colors.transparent,
        borderRadius: BorderRadius.circular(Gz.rMd),
        child: GzListRow(
          icon: s.icon,
          color: s.color,
          title: s.title(),
          trailing: badge > 0 ? CountBadge(badge, urgent: true) : null,
          onTap: () {
            Navigator.of(context).pop();
            _select(s.index);
          },
        ),
      ),
    );
  }

  Widget _link(
    BuildContext context,
    IconData icon,
    String title,
    VoidCallback onTap,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: GzListRow(
        icon: icon,
        color: Gz.textSecondary,
        title: title,
        onTap: () {
          Navigator.of(context).pop();
          onTap();
        },
      ),
    );
  }
}

/// AppBar-дағы «☰» + күтіп тұрған істердің жалпы саны.
class _MenuIcon extends StatelessWidget {
  final int badge;
  final VoidCallback onTap;
  const _MenuIcon({required this.badge, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          tooltip: t('Мәзір'),
          onPressed: onTap,
          icon: const Icon(Icons.menu_rounded),
        ),
        if (badge > 0)
          Positioned(
            right: 0,
            top: 2,
            child: IgnorePointer(child: CountBadge(badge, urgent: true)),
          ),
      ],
    );
  }
}
