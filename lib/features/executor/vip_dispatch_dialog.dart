import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import 'active_order_screen.dart';

/// Жаңа VIP заказ түскенде шығатын диалог (10 секунд жауап).
Future<void> showVipDispatchDialog(
    BuildContext context, VipDispatch dispatch) async {
  Map<String, dynamic>? row;
  try {
    row = await Repo.c
        .from('orders')
        .select()
        .eq('id', dispatch.orderId)
        .maybeSingle();
  } catch (_) {}
  if (row == null || !context.mounted) return;
  final order = Order.fromMap(row);
  if (order.status != 'searching' || !dispatch.isLive) return;

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => _VipDialog(dispatch: dispatch, order: order),
  );
}

class _VipDialog extends StatefulWidget {
  final VipDispatch dispatch;
  final Order order;
  const _VipDialog({required this.dispatch, required this.order});

  @override
  State<_VipDialog> createState() => _VipDialogState();
}

class _VipDialogState extends State<_VipDialog> {
  Timer? _timer;
  int _left = 25;

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
  }

  void _tick() {
    final left =
        widget.dispatch.expiresAt.difference(DateTime.now()).inSeconds;
    if (left <= 0) {
      _timer?.cancel();
      if (mounted) Navigator.of(context).pop();
      return;
    }
    if (left != _left && mounted) setState(() => _left = left);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _accept() async {
    _timer?.cancel();
    try {
      final orderId = await Repo.acceptVip(widget.dispatch.id);
      if (!mounted) return;
      Navigator.of(context).pop();
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ActiveOrderScreen(orderId: orderId)));
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      showSnack(context, errText(e), error: true);
    }
  }

  Future<void> _decline() async {
    _timer?.cancel();
    try {
      await Repo.declineVip(widget.dispatch.id);
    } catch (_) {}
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Gz.violet.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child:
                      const Icon(Icons.flash_on, color: Gz.violet, size: 22),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Жаңа VIP заказ!',
                      style: TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 17)),
                ),
                // кері санақ
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                        value: _left / 25,
                        strokeWidth: 4,
                        color: _left <= 5 ? Gz.red : Gz.violet,
                        backgroundColor: Gz.border,
                      ),
                    ),
                    Text('$_left',
                        style: const TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 15)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Gz.bg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.lock_outline, size: 18, color: Gz.violet),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text('Баға қабылдағаннан кейін көрінеді',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: Gz.violet)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  RouteLine(from: o.fromDisplay, to: o.toDisplay),
                  const SizedBox(height: 8),
                  Text(
                    '${o.cargoDesc} · ${o.size.label}'
                    '${o.distanceKm > 0 ? ' · ${o.distanceKm.toStringAsFixed(1)} км' : ''}',
                    style: const TextStyle(
                        color: Gz.textSecondary, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _decline,
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Gz.red,
                        side: const BorderSide(color: Gz.red)),
                    child: const Text('Бас тарту'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: Gz.violet,
                        foregroundColor: Colors.white),
                    onPressed: _accept,
                    child: const Text('Қабылдау'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
