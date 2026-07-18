import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import 'order_admin.dart';

/// «Линия»: қазір неше клиент заказ тастап отыр, неше орындаушы онлайн.
class LineScreen extends StatefulWidget {
  const LineScreen({super.key});

  @override
  State<LineScreen> createState() => _LineScreenState();
}

class _LineScreenState extends State<LineScreen> {
  Map<String, dynamic>? _stats;
  List<Order> _searching = [];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        Repo.modLineStats(),
        Repo.searchingOrders(),
      ]);
      if (mounted) {
        setState(() {
          _stats = results[0] as Map<String, dynamic>;
          _searching = results[1] as List<Order>;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final s = _stats;
    if (s == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final online = (s['online'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final busy = online.where((e) => e['busy_order_id'] != null).length;
    final resting = online.where((e) => e['on_line'] == false).length;
    final free = online.length - busy - resting;

    return RefreshIndicator(
      color: Gz.ink,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        children: [
          Row(children: [
            Expanded(
                child: _tile(t('Іздеуде'), '${s['searching_bidding']}',
                    t('баға ұсыну'), Gz.blue, Icons.gavel)),
            const SizedBox(width: 8),
            Expanded(
                child: _tile(t('Орындалуда'), '${s['active_orders']}',
                    t('заказ'), Gz.green, Icons.local_shipping)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
                child: _tile(t('Линияда'), '${online.length}',
                    t('орындаушы'), Gz.ink, Icons.wifi)),
            const SizedBox(width: 8),
            Expanded(
                child: _tile(t('Бос емес'), '$busy', t('заказда'), Gz.red,
                    Icons.hourglass_bottom)),
            const SizedBox(width: 8),
            Expanded(
                child: _tile(t('Бос'), '$free', t('күтуде'),
                    Gz.green, Icons.check_circle_outline)),
          ]),
          const SizedBox(height: 16),
          Text(t('Онлайн орындаушылар'),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 8),
          if (online.isEmpty)
            SectionCard(
                child: Text(t('Қазір ешкім линияда емес'),
                    style: const TextStyle(color: Gz.textSecondary))),
          for (final e in online)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SectionCard(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    InitialsAvatar(e['full_name'] as String? ?? '?',
                        radius: 18, imageUrl: e['avatar_url'] as String?),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e['full_name'] as String? ?? '…',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800)),
                          Text(
                            vehicleTypeFrom(e['vehicle_type'] as String?)
                                .label,
                            style: const TextStyle(
                                fontSize: 12, color: Gz.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    Wrap(spacing: 4, children: [
                      if (e['tariff_on'] == true || e['simple_on'] == true)
                        _chip(t('Тариф'), Gz.blue),
                      if (e['on_line'] == false)
                        _chip(t('Демалыста'), Gz.textSecondary)
                      else if (e['busy_order_id'] != null)
                        _chip(t('Заказда'), Gz.red)
                      else
                        _chip(t('Бос'), Gz.green),
                    ]),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          Text(t('Іздеудегі заказдар'),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 8),
          if (_searching.isEmpty)
            SectionCard(
                child: Text(t('Іздеудегі заказ жоқ'),
                    style: const TextStyle(color: Gz.textSecondary))),
          for (final o in _searching)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: OrderCard(
                order: o,
                onTap: () => showOrderAdminSheet(context, o.id, onChanged: _load),
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _tile(String label, String value, String hint, Color color,
      IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Gz.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Gz.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w900, color: color)),
          Text('$label · $hint', // label/hint аргументтер шақыру жерінде t() арқылы аударылады
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 10.5, color: Gz.textSecondary)),
        ],
      ),
    );
  }

  Widget _chip(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
      );
}
