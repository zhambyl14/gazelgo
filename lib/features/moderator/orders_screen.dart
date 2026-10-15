import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import 'order_admin.dart';

/// Барлық заказды, соның ішінде completed/cancelled/expired архивін бір
/// жерден іздеу және басқару экраны.
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});
  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  final _search = TextEditingController();
  String _status = 'all';
  late Future<List<Order>> _future = Repo.modAllOrders();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _reload() => setState(() => _future = Repo.modAllOrders());

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'ID, мекенжай, жүк немесе статус бойынша іздеу',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _search.clear();
                        setState(() {});
                      },
                      icon: const Icon(Icons.close),
                    ),
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Row(
            children: [
              for (final item in const [
                ('all', 'Барлығы'),
                ('searching', 'Іздеуде'),
                ('active', 'Белсенді'),
                ('completed', 'Аяқталған'),
                ('cancelled', 'Тоқтатылған'),
              ]) ...[
                ChoiceChip(
                  label: Text(item.$2),
                  selected: _status == item.$1,
                  selectedColor: Gz.yellow,
                  onSelected: (_) => setState(() => _status = item.$1),
                ),
                const SizedBox(width: 6),
              ],
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => _reload(),
            child: FutureBuilder<List<Order>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final q = _search.text.trim().toLowerCase();
                final rows = (snap.data ?? []).where((o) {
                  final statusMatch = switch (_status) {
                    'active' => o.isActive,
                    'all' => true,
                    _ => o.status == _status,
                  };
                  final haystack =
                      '${o.id} ${o.fromDisplay} ${o.toDisplay} ${o.cargoDesc} ${o.status}'
                          .toLowerCase();
                  return statusMatch && (q.isEmpty || haystack.contains(q));
                }).toList();
                if (rows.isEmpty) {
                  return ListView(
                    children: const [
                      SizedBox(height: 110),
                      EmptyState(
                        icon: Icons.receipt_long_outlined,
                        title: 'Заказ табылмады',
                      ),
                    ],
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                  itemCount: rows.length,
                  separatorBuilder: (_, index) => const SizedBox(height: 8),
                  itemBuilder: (_, i) =>
                      _OrderAdminTile(order: rows[i], onChanged: _reload),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _OrderAdminTile extends StatelessWidget {
  final Order order;
  final VoidCallback onChanged;
  const _OrderAdminTile({required this.order, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    // Клиент пен орындаушы көретін ОРТАҚ карточка: маршрут нүктелерімен,
    // қашықтықпен (км), көлік түрімен. Бұрын модераторда жеке, жұпыны
    // карточка болатын: қашықтық жоқ, жолаушы саны «қорап» белгішесімен,
    // ұзын UUID бүтін жолды алып тұратын.
    final id = order.id.length > 8 ? order.id.substring(0, 8) : order.id;
    return OrderCard(
      order: order,
      onTap: () => showOrderAdminSheet(context, order.id, onChanged: onChanged),
      footer: Row(
        children: [
          const Icon(Icons.tag_rounded, size: 14, color: Gz.textTertiary),
          const SizedBox(width: 3),
          Text(
            id,
            style: const TextStyle(color: Gz.textTertiary, fontSize: 12),
          ),
          const Spacer(),
          Text(
            fmtDate(order.createdAt),
            style: const TextStyle(color: Gz.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
