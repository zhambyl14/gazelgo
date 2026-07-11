import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/repo.dart';
import '../../shared/widgets.dart';
import 'order_detail_screen.dart';

class MyOrdersScreen extends StatelessWidget {
  const MyOrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Тапсырыстарым'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Белсенді'),
            Tab(text: 'Тарих'),
          ]),
        ),
        body: StreamBuilder<List<Order>>(
          stream: Repo.myOrdersStream(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting &&
                !snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final all = (snap.data ?? []).reversed.toList();
            final active = all.where((o) => o.isActive).toList();
            // Тарихта тек СӘТТІ аяқталған заказдар (тоқтатылған/мерзімі
            // өткендер көрсетілмейді).
            final history =
                all.where((o) => o.status == 'completed').toList();
            return TabBarView(
              children: [
                _list(context, active,
                    empty: 'Белсенді заказ жоқ.\nБасты беттен газель шақырыңыз.'),
                _list(context, history,
                    empty: 'Аяқталған заказ әзірге жоқ.'),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _list(BuildContext context, List<Order> orders,
      {required String empty}) {
    if (orders.isEmpty) {
      return EmptyState(icon: Icons.receipt_long, title: empty);
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: orders.length,
      separatorBuilder: (_, i) => const SizedBox(height: 8),
      itemBuilder: (_, i) => OrderCard(
        order: orders[i],
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => OrderDetailScreen(orderId: orders[i].id))),
      ),
    );
  }
}
