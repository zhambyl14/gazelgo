import 'package:flutter/material.dart';

import '../../core/lang.dart';
import '../../shared/widgets.dart';
import 'app_settings_screen.dart';
import 'applications_screen.dart';
import 'executors_screen.dart';
import 'line_screen.dart';
import 'news_admin_screen.dart';
import 'overview_screen.dart';
import 'reports_screen.dart';
import 'support_admin_screen.dart';
import 'topups_screen.dart';
import 'vehicle_types_screen.dart';

/// Модератор панелі: линия, өтінімдер, толтырулар, орындаушылар, қолдау.
class ModeratorShell extends StatefulWidget {
  const ModeratorShell({super.key});

  // Қойынды нөмірлері — push-хабарламадан өту үшін (төмендегі [openTab]).
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

  /// Қойындыға өту сұранысы (push-хабарламаны басқанда).
  ///
  /// Бұл экрандар — панельдің ІШІНДЕГІ қойындылары (өз Scaffold-ы жоқ).
  /// Бұрын оларды `Navigator.push` арқылы бөлек бет ретінде ашатынбыз, сол
  /// себепті Scaffold-сыз қалып, фоны ҚАРА болып көрінетін. Енді жаңа бет
  /// ашпаймыз — бар панельдің керек қойындысына ауысамыз.
  static final ValueNotifier<int?> tabRequest = ValueNotifier<int?>(null);

  /// Панель әлі ашылмаған болса (қосымша жабық тұрғанда push басылды), мән
  /// осы жерде сақталып тұрады да, панель құрылған сәтте қолданылады.
  static void openTab(int index) => tabRequest.value = index;

  @override
  State<ModeratorShell> createState() => _ModeratorShellState();
}

class _ModeratorShellState extends State<ModeratorShell>
    with SingleTickerProviderStateMixin {
  static const _tabCount = 10;
  late final TabController _tabs =
      TabController(length: _tabCount, vsync: this);

  @override
  void initState() {
    super.initState();
    ModeratorShell.tabRequest.addListener(_applyTabRequest);
    // Қосымша ЖАБЫҚ тұрғанда push басылса, сұраныс панель құрылғанға дейін
    // қойылып қояды — сол себепті мұнда да бір рет тексереміз.
    _applyTabRequest();
  }

  @override
  void dispose() {
    ModeratorShell.tabRequest.removeListener(_applyTabRequest);
    _tabs.dispose();
    super.dispose();
  }

  void _applyTabRequest() {
    final index = ModeratorShell.tabRequest.value;
    if (index == null || index < 0 || index >= _tabCount) return;
    ModeratorShell.tabRequest.value = null; // бір рет қана орындалады
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Үстінде ашық тұрған бет болса (чат, өтінім беті…) — жабамыз да,
      // панельдің өзінде қойындыны ауыстырамыз. Жаңа бет ашылмайды.
      Navigator.of(context).popUntil((r) => r.isFirst);
      _tabs.animateTo(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const GazelGoLogo(size: 20),
            const SizedBox(width: 8),
            Text('· ${t('Модератор')}', style: const TextStyle(fontSize: 15)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: t('Шығу'),
            onPressed: () => confirmSignOut(context),
            icon: const Icon(Icons.logout),
          ),
        ],
        bottom: TabBar(controller: _tabs, isScrollable: true, tabs: [
          Tab(text: t('Шолу')),
          Tab(text: t('Линия')),
          Tab(text: t('Өтінімдер')),
          Tab(text: t('Толтырулар')),
          Tab(text: t('Орындаушылар')),
          Tab(text: t('Қолдау')),
          Tab(text: t('Хабарламалар')),
          Tab(text: t('Көліктер')),
          Tab(text: t('Жаңалықтар')),
          Tab(text: t('Баптаулар')),
        ]),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          ModeratorOverviewScreen(),
          LineScreen(),
          ApplicationsScreen(),
          TopupsScreen(),
          ExecutorsScreen(),
          SupportAdminScreen(),
          ReportsScreen(),
          VehicleTypesScreen(),
          NewsAdminScreen(),
          AppSettingsScreen(),
        ],
      ),
    );
  }
}
