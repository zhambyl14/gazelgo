import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import 'applications_screen.dart' show DocImage;

/// Баланс толтыру сұранымдары (Kaspi чектерін тексеру).
class TopupsScreen extends StatefulWidget {
  const TopupsScreen({super.key});

  @override
  State<TopupsScreen> createState() => _TopupsScreenState();
}

class _TopupsScreenState extends State<TopupsScreen> {
  String _status = 'pending';
  late Future<List<TopupRequest>> _future = Repo.topupsByStatus(_status);

  void _reload() {
    final f = Repo.topupsByStatus(_status);
    setState(() {
      _future = f;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Row(
            children: [
              for (final (s, label) in [
                ('pending', 'Күтуде'),
                ('approved', 'Расталған'),
                ('rejected', 'Қабылданбаған'),
              ]) ...[
                ChoiceChip(
                  label: Text(label),
                  selected: _status == s,
                  selectedColor: Gz.yellow,
                  labelStyle: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    color: _status == s ? Gz.ink : Gz.textSecondary,
                  ),
                  onSelected: (v) {
                    _status = s;
                    _reload();
                  },
                ),
                const SizedBox(width: 6),
              ],
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => _reload(),
            child: FutureBuilder<List<TopupRequest>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final rows = snap.data ?? [];
                if (rows.isEmpty) {
                  return ListView(children: const [
                    SizedBox(height: 100),
                    EmptyState(
                        icon: Icons.account_balance_wallet_outlined,
                        title: 'Сұраным жоқ'),
                  ]);
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: rows.length,
                  separatorBuilder: (_, i) => const SizedBox(height: 8),
                  itemBuilder: (_, i) =>
                      _TopupCard(t: rows[i], onChanged: _reload),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _TopupCard extends StatelessWidget {
  final TopupRequest t;
  final VoidCallback onChanged;
  const _TopupCard({required this.t, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: FutureBuilder<Profile?>(
                  future: Repo.profileOf(t.executorId),
                  builder: (context, snap) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(snap.data?.fullName ?? '…',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 15)),
                      Text(
                        '${snap.data?.phone ?? ''} · ${fmtDate(t.createdAt)}',
                        style: const TextStyle(
                            color: Gz.textSecondary, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
              ),
              Text(fmtT(t.amount),
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Gz.green)),
            ],
          ),
          const SizedBox(height: 10),
          if (t.receiptPath != null)
            SizedBox(
                width: 150,
                child: DocImage(path: t.receiptPath, label: 'Kaspi чек'))
          else
            const Text('Чек тіркелмеген',
                style: TextStyle(color: Gz.red, fontSize: 13)),
          if (t.status == 'pending') ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: BusyButton(
                    label: 'Қабылдамау',
                    outlined: true,
                    onPressed: () => _review(context, false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: BusyButton(
                    label: 'Растау · ${fmtT(t.amount)}',
                    onPressed: () => _review(context, true),
                  ),
                ),
              ],
            ),
          ] else if (t.note?.isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Text('Ескерту: ${t.note}',
                style:
                    const TextStyle(color: Gz.textSecondary, fontSize: 12.5)),
          ],
        ],
      ),
    );
  }

  Future<void> _review(BuildContext context, bool approve) async {
    String note = '';
    if (!approve) {
      final c = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Қабылдамау себебі'),
          content: TextField(
            controller: c,
            autofocus: true,
            decoration:
                const InputDecoration(hintText: 'Мыс: чек табылмады'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Болдырмау')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Жіберу')),
          ],
        ),
      );
      if (ok != true) return;
      note = c.text;
    }
    if (!context.mounted) return;
    try {
      await Repo.modReviewTopup(t.id, approve, note,
          receiptPath: t.receiptPath);
      if (context.mounted) {
        showSnack(context,
            approve ? 'Баланс толтырылды' : 'Сұраным қабылданбады');
      }
      onChanged();
    } catch (e) {
      if (context.mounted) showSnack(context, errText(e), error: true);
    }
  }
}
