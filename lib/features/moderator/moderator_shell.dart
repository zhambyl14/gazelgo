import 'package:flutter/material.dart';

import '../../core/repo.dart';
import '../../shared/widgets.dart';
import 'applications_screen.dart';
import 'executors_screen.dart';
import 'line_screen.dart';
import 'support_admin_screen.dart';
import 'topups_screen.dart';

/// Модератор панелі: линия, өтінімдер, толтырулар, орындаушылар, қолдау.
class ModeratorShell extends StatelessWidget {
  const ModeratorShell({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Row(
            children: [
              GazelGoLogo(size: 20),
              SizedBox(width: 8),
              Text('· Модератор', style: TextStyle(fontSize: 15)),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Шығу',
              onPressed: Repo.signOut,
              icon: const Icon(Icons.logout),
            ),
          ],
          bottom: const TabBar(isScrollable: true, tabs: [
            Tab(text: 'Линия'),
            Tab(text: 'Өтінімдер'),
            Tab(text: 'Толтырулар'),
            Tab(text: 'Орындаушылар'),
            Tab(text: 'Қолдау'),
          ]),
        ),
        body: const TabBarView(
          children: [
            LineScreen(),
            ApplicationsScreen(),
            TopupsScreen(),
            ExecutorsScreen(),
            SupportAdminScreen(),
          ],
        ),
      ),
    );
  }
}
