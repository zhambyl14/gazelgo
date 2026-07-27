import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/lang.dart';
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
    final f = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 75,
      maxWidth: 1600,
    );
    if (f != null) {
      final b = await f.readAsBytes();
      setState(() => _receipt = b);
    }
  }

  /// Kaspi QR/төлем сілтемесін сыртқы қосымшада (Kaspi) ашады. Сілтеме өзі
  /// Kaspi-ды ашып, QR-ды сканерлеп, сома енгізуге дейін апарады.
  Future<void> _openKaspi(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme) {
      showSnack(context, t('Kaspi сілтемесі дұрыс емес'), error: true);
      return;
    }
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        showSnack(context, t('Kaspi ашылмады'), error: true);
      }
    } catch (_) {
      if (mounted) showSnack(context, t('Kaspi ашылмады'), error: true);
    }
  }

  Future<void> _submit(AppConfig cfg) async {
    final amount = int.tryParse(_amount.text.replaceAll(RegExp(r'\D'), ''));
    if (amount == null || amount < cfg.minTopup) {
      showSnack(
        context,
        '${t('Ең аз сома:')} ${fmtT(cfg.minTopup)}',
        error: true,
      );
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
        showSnack(
          context,
          t('Сұраным жіберілді! Модератор растаған соң баланс толады.'),
        );
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
      appBar: AppBar(title: Text(t('Баланс'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: Gz.heroGradient,
              borderRadius: BorderRadius.circular(22),
              boxShadow: Gz.cardShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t('Ағымдағы баланс'),
                  style: const TextStyle(color: Colors.white60, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  fmtT(statsAsync.value?.balance),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
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
                Row(
                  children: [
                    const Icon(Icons.account_balance_wallet, color: Gz.red),
                    const SizedBox(width: 8),
                    Text(
                      t('Kaspi арқылы толтыру'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (cfg.kaspiTopupUrl.isNotEmpty) ...[
                  InfoRow(
                    t('1-қадам'),
                    t('Соманы жазып, «Kaspi-мен төлеу» түймесін басыңыз'),
                  ),
                  InfoRow(
                    t('2-қадам'),
                    t('Kaspi-де соманы енгізіп, төлемді растаңыз'),
                  ),
                  InfoRow(
                    t('3-қадам'),
                    t(
                      'Чек скриншотын осында тіркеп, '
                      'сұраным жіберіңіз — модератор растаған соң баланс толады',
                    ),
                  ),
                ] else ...[
                  InfoRow(
                    t('1-қадам'),
                    '${t('Kaspi-ден аударыңыз:')} ${cfg.kaspiNumber} (${cfg.kaspiName})',
                  ),
                  InfoRow(t('2-қадам'), t('Чек скриншотын осында тіркеңіз')),
                  InfoRow(
                    t('3-қадам'),
                    t('Модератор растаған соң баланс толады'),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _amount,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: '${t('Сома, ₸ (мин.')} ${cfg.minTopup})',
                    prefixIcon: const Icon(Icons.payments_outlined),
                  ),
                ),
                if (cfg.kaspiTopupUrl.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => _openKaspi(cfg.kaspiTopupUrl),
                      style: FilledButton.styleFrom(
                        backgroundColor: Gz.red,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(50),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      icon: const Icon(Icons.account_balance_wallet),
                      label: Text(t('Kaspi-мен төлеу')),
                    ),
                  ),
                ],
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
                          t(_receipt == null ? 'Чек тіркеу' : 'Чек тіркелді'),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                BusyButton(
                  label: t('Сұраным жіберу'),
                  onPressed: () => _submit(cfg),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            t('Толтыру сұранымдары'),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 8),
          FutureBuilder<List<TopupRequest>>(
            key: ValueKey('topups$_refresh'),
            future: Repo.myTopups(),
            builder: (context, snap) {
              final rows = snap.data ?? [];
              if (rows.isEmpty) return const SizedBox.shrink();
              return SectionCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 4,
                ),
                child: Column(
                  children: [
                    for (final t in rows)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          fmtT(t.amount),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          fmtDate(t.createdAt),
                          style: const TextStyle(fontSize: 12.5),
                        ),
                        trailing: _topupChip(t.status),
                      ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          Text(
            t('Транзакциялар'),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 8),
          FutureBuilder<List<BalanceTxn>>(
            key: ValueKey('txns$_refresh'),
            future: Repo.myTxns(),
            builder: (context, snap) {
              final rows = snap.data ?? [];
              if (rows.isEmpty) {
                return SectionCard(
                  child: Text(
                    t('Транзакциялар әзірге жоқ.'),
                    style: const TextStyle(color: Gz.textSecondary),
                  ),
                );
              }
              return SectionCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 4,
                ),
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
                            color: t.amount >= 0 ? Gz.green : Gz.ink,
                          ),
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
      'approved' => (Gz.green, t('Расталды')),
      'rejected' => (Gz.red, t('Қабылданбады')),
      _ => (Gz.blue, t('Күтуде')),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}
