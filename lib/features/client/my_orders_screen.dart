import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import '../executor/active_order_screen.dart';
import 'order_detail_screen.dart';

/// «Тапсырыстарым» (клиент) / «Заказдарым» (орындаушы) — бір экран.
///
/// Екі қойынды: БЕЛСЕНДІ және ТАРИХ. Тарихта бұрын тек аяқталғандар
/// көрінетін — тоқтатылған/мерзімі өткен заказ мүлдем жоғалып кететін
/// (клиент «заказым қайда?» деп қолдау қызметіне жазатын). Енді сүзгі
/// бар (Барлығы / Аяқталған / Тоқтатылған) әрі мекенжай, жүк бойынша
/// іздеуге болады.
class MyOrdersScreen extends ConsumerStatefulWidget {
  /// true — орындаушының өзі алған заказдары.
  final bool asExecutor;
  const MyOrdersScreen({super.key, this.asExecutor = false});

  @override
  ConsumerState<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends ConsumerState<MyOrdersScreen> {
  final _search = TextEditingController();
  String _filter = 'all';

  /// Орындаушының тарихы — бір рет жүктеледі, тартып жаңартылады.
  late Future<List<Order>> _execFuture = Repo.myExecutorOrders();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (widget.asExecutor) {
      setState(() => _execFuture = Repo.myExecutorOrders());
      await _execFuture;
    } else {
      ref.invalidate(myOrdersStreamProvider);
    }
  }

  void _open(Order o) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => widget.asExecutor
            ? ActiveOrderScreen(orderId: o.id)
            : OrderDetailScreen(orderId: o.id),
      ),
    );
  }

  List<Order> _history(List<Order> all) {
    final q = _search.text.trim().toLowerCase();
    return all.where((o) {
      if (o.isActive) return false;
      final f = switch (_filter) {
        'completed' => o.status == 'completed',
        'cancelled' => o.status == 'cancelled' || o.status == 'expired',
        _ => true,
      };
      if (!f) return false;
      if (q.isEmpty) return true;
      return '${o.fromDisplay} ${o.toDisplay} ${o.cargoDesc}'
          .toLowerCase()
          .contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.asExecutor ? t('Заказдарым') : t('Тапсырыстарым');
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          bottom: TabBar(
            tabs: [
              Tab(text: t('Белсенді')),
              Tab(text: t('Тарих')),
            ],
          ),
        ),
        body: widget.asExecutor
            ? FutureBuilder<List<Order>>(
                future: _execFuture,
                builder: (context, snap) => _body(snap.data, snap.hasError,
                    loading: snap.connectionState == ConnectionState.waiting &&
                        !snap.hasData),
              )
            : Builder(
                builder: (context) {
                  final async = ref.watch(myOrdersStreamProvider);
                  return _body(
                    async.value?.reversed.toList(),
                    async.hasError && !async.hasValue,
                    loading: async.isLoading && !async.hasValue,
                  );
                },
              ),
      ),
    );
  }

  /// [all] — жаңасы алдында.
  Widget _body(List<Order>? all, bool error, {required bool loading}) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error) return LoadErrorState(onRetry: _refresh);
    final orders = all ?? const <Order>[];
    final active = orders.where((o) => o.isActive).toList();
    final history = _history(orders);
    return TabBarView(
      children: [
        _list(
          active,
          empty: EmptyState(
            icon: Icons.local_shipping_outlined,
            title: t('Белсенді заказ жоқ'),
            subtitle: widget.asExecutor
                ? t('Лентадан заказ таңдап, ұсыныс беріңіз.')
                : t('Басты беттен көлік шақырыңыз.'),
          ),
        ),
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: t('Мекенжай не жүк бойынша іздеу'),
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () => setState(_search.clear),
                          icon: const Icon(Icons.close_rounded),
                        ),
                ),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: Row(
                children: [
                  for (final (key, label) in [
                    ('all', t('Барлығы')),
                    ('completed', t('Аяқталған')),
                    ('cancelled', t('Тоқтатылған')),
                  ]) ...[
                    ChoiceChip(
                      label: Text(label),
                      selected: _filter == key,
                      onSelected: (_) => setState(() => _filter = key),
                    ),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
            Expanded(
              child: _list(
                history,
                showDate: true,
                empty: EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: t('Тарих бос'),
                  subtitle: t('Аяқталған және тоқтатылған заказдар осында '
                      'сақталады.'),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _list(
    List<Order> orders, {
    required Widget empty,
    bool showDate = false,
  }) {
    return RefreshIndicator(
      color: Gz.ink,
      onRefresh: _refresh,
      child: orders.isEmpty
          ? ListView(children: [const SizedBox(height: 80), empty])
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              itemCount: orders.length,
              separatorBuilder: (_, i) => const SizedBox(height: 8),
              itemBuilder: (_, i) => OrderCard(
                order: orders[i],
                showDate: showDate,
                onTap: () => _open(orders[i]),
              ),
            ),
    );
  }
}
