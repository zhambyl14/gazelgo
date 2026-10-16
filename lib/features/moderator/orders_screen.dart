import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import 'order_admin.dart';

/// Барлық заказды, соның ішінде completed/cancelled/expired архивін бір
/// жерден іздеу, сүзу, басқару және CSV-ке шығару экраны.
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});
  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  final _search = TextEditingController();
  String _status = 'all';

  /// Кезең (күн): 1 — бүгін, 7, 30, null — барлығы (соңғы 1000).
  int? _days = 7;
  VehicleType? _vehicle;
  late Future<List<Order>> _future = _load();

  Future<List<Order>> _load() {
    final d = _days;
    if (d == null) return Repo.modAllOrders();
    final now = DateTime.now();
    final since = d == 1
        ? DateTime(now.year, now.month, now.day)
        : now.subtract(Duration(days: d));
    return Repo.modAllOrders(since: since);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _reload() => setState(() => _future = _load());

  List<Order> _filter(List<Order> all) {
    final q = _search.text.trim().toLowerCase();
    return all.where((o) {
      final statusMatch = switch (_status) {
        'active' => o.isActive,
        'all' => true,
        _ => o.status == _status,
      };
      if (!statusMatch) return false;
      if (_vehicle != null && o.vehicleType != _vehicle) return false;
      if (q.isEmpty) return true;
      final haystack =
          '${o.id} ${o.fromDisplay} ${o.toDisplay} ${o.cargoDesc} '
                  '${o.fromCity ?? ''} ${o.toCity ?? ''} ${o.status}'
              .toLowerCase();
      return haystack.contains(q);
    }).toList();
  }

  /// Сүзілген заказдарды CSV файл етіп бөлісу (Excel ашады — UTF-8 BOM).
  Future<void> _export(List<Order> rows) async {
    String esc(Object? v) {
      final s = '${v ?? ''}'.replaceAll('"', '""');
      return '"$s"';
    }

    final buf = StringBuffer('﻿')
      ..writeln(
        [
          'ID',
          t('Құрылды'),
          t('Күйі'),
          t('Көлік'),
          t('Қайдан'),
          t('Қайда'),
          'км',
          t('Баға'),
          t('Жүк'),
        ].map(esc).join(','),
      );
    for (final o in rows) {
      buf.writeln(
        [
          o.id,
          fmtDate(o.createdAt),
          statusLabel(o.status, vehicleType: o.vehicleType),
          o.vehicleType.label,
          o.fromDisplay,
          o.toDisplay,
          o.distanceKm.toStringAsFixed(1),
          o.displayPrice ?? '',
          o.cargoDesc,
        ].map(esc).join(','),
      );
    }
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              utf8.encode(buf.toString()),
              mimeType: 'text/csv',
              name: 'tasu-orders.csv',
            ),
          ],
          fileNameOverrides: const ['tasu-orders.csv'],
        ),
      );
    } catch (e) {
      if (mounted) showSnack(context, errText(e), error: true);
    }
  }

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
              hintText: t('ID, мекенжай, жүк немесе қала бойынша іздеу'),
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
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
          child: Row(
            children: [
              for (final (key, label) in [
                ('all', t('Барлығы')),
                ('searching', t('Іздеуде')),
                ('active', t('Белсенді')),
                ('completed', t('Аяқталған')),
                ('cancelled', t('Тоқтатылған')),
              ]) ...[
                ChoiceChip(
                  label: Text(label),
                  selected: _status == key,
                  onSelected: (_) => setState(() => _status = key),
                ),
                const SizedBox(width: 6),
              ],
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
          child: Row(
            children: [
              for (final (days, label) in <(int?, String)>[
                (1, t('Бүгін')),
                (7, t('7 күн')),
                (30, t('30 күн')),
                (null, t('Барлық уақыт')),
              ]) ...[
                ChoiceChip(
                  avatar: _days == days
                      ? null
                      : const Icon(Icons.calendar_today_outlined, size: 14),
                  label: Text(label),
                  selected: _days == days,
                  onSelected: (_) {
                    _days = days;
                    _reload();
                  },
                ),
                const SizedBox(width: 6),
              ],
              PopupMenuButton<VehicleType?>(
                tooltip: t('Көлік түрі'),
                onSelected: (v) => setState(() => _vehicle = v),
                itemBuilder: (_) => [
                  PopupMenuItem(value: null, child: Text(t('Барлық көлік'))),
                  for (final v in VehicleType.values)
                    PopupMenuItem(value: v, child: Text(v.label)),
                ],
                child: Chip(
                  avatar: const Icon(Icons.local_shipping_outlined, size: 16),
                  label: Text(_vehicle?.label ?? t('Барлық көлік')),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            color: Gz.ink,
            onRefresh: () async => _reload(),
            child: FutureBuilder<List<Order>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return ListView(
                    children: [
                      const SizedBox(height: 100),
                      LoadErrorState(onRetry: _reload),
                    ],
                  );
                }
                final rows = _filter(snap.data ?? const []);
                if (rows.isEmpty) {
                  return ListView(
                    children: [
                      const SizedBox(height: 110),
                      EmptyState(
                        icon: Icons.receipt_long_outlined,
                        title: t('Заказ табылмады'),
                      ),
                    ],
                  );
                }
                final done = rows.where((o) => o.status == 'completed');
                final sum = done.fold<int>(
                  0,
                  (a, o) => a + (o.displayPrice ?? 0),
                );
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                  itemCount: rows.length + 1,
                  separatorBuilder: (_, index) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    if (i == 0) {
                      return GzNotice(
                        tone: NoticeTone.neutral,
                        icon: Icons.summarize_outlined,
                        dense: true,
                        message:
                            '${rows.length} ${t('заказ')} · '
                            '${t('аяқталғаны')} ${done.length} · '
                            '${t('сомасы')} ${fmtT(sum)}',
                        trailing: TextButton.icon(
                          onPressed: () => _export(rows),
                          icon: const Icon(Icons.download_rounded, size: 18),
                          label: const Text('CSV'),
                        ),
                      );
                    }
                    return _OrderAdminTile(
                      order: rows[i - 1],
                      onChanged: _reload,
                    );
                  },
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
    // қашықтықпен (км), көлік түрімен.
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
          Text(fmtDate(order.createdAt), style: Gz.caption),
        ],
      ),
    );
  }
}
