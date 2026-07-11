import 'package:flutter/material.dart';

import '../../core/lang.dart';
import '../../shared/widgets.dart';
import 'applications_screen.dart';
import 'executors_screen.dart';
import 'line_screen.dart';
import 'reports_screen.dart';
import 'support_admin_screen.dart';
import 'topups_screen.dart';

/// Модератор панелі: линия, өтінімдер, толтырулар, орындаушылар, қолдау.
class ModeratorShell extends StatelessWidget {
  const ModeratorShell({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 6,
      child: Scaffold(
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
          bottom: TabBar(isScrollable: true, tabs: [
            Tab(text: t('Линия')),
            Tab(text: t('Өтінімдер')),
            Tab(text: t('Толтырулар')),
            Tab(text: t('Орындаушылар')),
            Tab(text: t('Қолдау')),
            Tab(text: t('Хабарламалар')),
          ]),
        ),
        body: const TabBarView(
          children: [
            LineScreen(),
            ApplicationsScreen(),
            TopupsScreen(),
            ExecutorsScreen(),
            SupportAdminScreen(),
            ReportsScreen(),
          ],
        ),
      ),
    );
  }
}
