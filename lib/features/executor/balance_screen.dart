import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';

/// Баланс: Kaspi арқылы толтыру сұранымы + транзакция тарихы.
class BalanceScreen extends ConsumerStatefulWidget {
  const BalanceScreen({super.key});

  @override
  ConsumerState<BalanceScreen> createState() => _BalanceScreenState();
}

class _BalanceScreenState extends ConsumerState<BalanceScreen> {
  final _amount = TextEditingController();
  Uint8List? _receipt;
  int _refresh = 0;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _pickReceipt() async {
    final f = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 75, maxWidth: 1600);
    if (f != null) {
      final b = await f.readAsBytes();
      setState(() => _receipt = b);
    }
  }

  Future<void> _submit(AppConfig cfg) async {
    final amount = int.tryParse(_amount.text.replaceAll(RegExp(r'\D'), ''));
    if (amount == null || amount < cfg.minTopup) {
      showSnack(context, 'Ең аз сома: ${fmtT(cfg.minTopup)}', error: true);
      return;
    }
    try {
      String? path;
      if (_receipt != null) {
        path = await Repo.uploadDoc('receipt.jpg', _receipt!);
      }
      await Repo.requestTopup(amount, path);
      _amount.clear();
      setState(() {
        _receipt = null;
        _refresh++;
      });
      if (mounted) {
        showSnack(context,
            'Сұраным жіберілді! Модератор растаған соң баланс толады.');
      }
    } catch (e) {
      if (mounted) showSnack(context, errText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final statsAsync = ref.watch(executorStatsStreamProvider);
    final cfgAsync = ref.watch(appConfigProvider);
    final cfg = cfgAsync.value ?? AppConfig();

    return Scaffold(
      appBar: AppBar(title: const Text('Баланс')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Gz.ink,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Ағымдағы баланс',
                    style: TextStyle(color: Colors.white60, fontSize: 13)),
                const SizedBox(height: 4),
                Text(
                  fmtT(statsAsync.value?.balance),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Kaspi нұсқаулығы
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.account_balance_wallet, color: Gz.red),
                    SizedBox(width: 8),
                    Text('Kaspi арқылы толтыру',
                        style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 15)),
                  ],
                ),
                const SizedBox(height: 10),
                InfoRow('1-қадам', 'Kaspi-ден аударыңыз: ${cfg.kaspiNumber} (${cfg.kaspiName})'),
                InfoRow('2-қадам', 'Чек скриншотын осында тіркеңіз'),
                InfoRow('3-қадам', 'Модератор растаған соң баланс толады'),
                const SizedBox(height: 12),
                TextField(
                  controller: _amount,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: 'Сома, ₸ (мин. ${cfg.minTopup})',
                    prefixIcon: const Icon(Icons.payments_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickReceipt,
                        icon: Icon(
                          _receipt == null
                              ? Icons.receipt_long
                              : Icons.check_circle,
                          color: _receipt == null ? null : Gz.green,
                        ),
                        label: Text(
                            _receipt == null ? 'Чек тіркеу' : 'Чек тіркелді'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                BusyButton(
                    label: 'Сұраным жіберу', onPressed: () => _submit(cfg)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text('Толтыру сұранымдары',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 8),
          FutureBuilder<List<TopupRequest>>(
            key: ValueKey('topups$_refresh'),
            future: Repo.myTopups(),
            builder: (context, snap) {
              final rows = snap.data ?? [];
              if (rows.isEmpty) return const SizedBox.shrink();
              return SectionCard(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                child: Column(
                  children: [
                    for (final t in rows)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(fmtT(t.amount),
                            style: const TextStyle(
                                fontWeight: FontWeight.w800)),
                        subtitle: Text(fmtDate(t.createdAt),
                            style: const TextStyle(fontSize: 12.5)),
                        trailing: _topupChip(t.status),
                      ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          const Text('Транзакциялар',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 8),
          FutureBuilder<List<BalanceTxn>>(
            key: ValueKey('txns$_refresh'),
            future: Repo.myTxns(),
            builder: (context, snap) {
              final rows = snap.data ?? [];
              if (rows.isEmpty) {
                return const SectionCard(
                  child: Text('Транзакциялар әзірге жоқ.',
                      style: TextStyle(color: Gz.textSecondary)),
                );
              }
              return SectionCard(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                child: Column(
                  children: [
                    for (final t in rows)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: Gz.bg,
                          child: Icon(
                            t.amount >= 0
                                ? Icons.arrow_downward
                                : Icons.arrow_upward,
                            color: t.amount >= 0 ? Gz.green : Gz.red,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          '${t.amount >= 0 ? '+' : ''}${fmtT(t.amount)}',
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: t.amount >= 0 ? Gz.green : Gz.ink),
                        ),
                        subtitle: Text(
                          '${t.note.isEmpty ? t.type : t.note} · ${fmtDate(t.createdAt)}',
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _topupChip(String status) {
    final (color, label) = switch (status) {
      'approved' => (Gz.green, 'Расталды'),
      'rejected' => (Gz.red, 'Қабылданбады'),
      _ => (Gz.blue, 'Күтуде'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontWeight: FontWeight.w700, fontSize: 12)),
    );
  }
}
