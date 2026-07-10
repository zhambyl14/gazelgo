import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import '../profile/reviews_screen.dart';
import 'applications_screen.dart' show DocImage;
import 'order_admin.dart';

/// Барлық орындаушылар: қарау, бұғаттау, баланс түзету.
class ExecutorsScreen extends StatefulWidget {
  const ExecutorsScreen({super.key});

  @override
  State<ExecutorsScreen> createState() => _ExecutorsScreenState();
}

class _ExecutorsScreenState extends State<ExecutorsScreen> {
  String? _status;
  late Future<List<ExecutorProfile>> _future = Repo.executorsByStatus(_status);

  void _reload() {
    final f = Repo.executorsByStatus(_status);
    setState(() {
      _future = f;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Row(
            children: [
              for (final (s, label) in <(String?, String)>[
                (null, 'Барлығы'),
                ('approved', 'Расталған'),
                ('pending', 'Күтуде'),
                ('rejected', 'Қабылданбаған'),
                ('blocked', 'Бұғатталған'),
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
            child: FutureBuilder<List<ExecutorProfile>>(
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
                        icon: Icons.people_outline, title: 'Тізім бос'),
                  ]);
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: rows.length,
                  separatorBuilder: (_, i) => const SizedBox(height: 8),
                  itemBuilder: (_, i) =>
                      _ExecutorTile(ep: rows[i], onChanged: _reload),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _ExecutorTile extends StatelessWidget {
  final ExecutorProfile ep;
  final VoidCallback onChanged;
  const _ExecutorTile({required this.ep, required this.onChanged});

  Color get _statusColor => switch (ep.status) {
        'approved' => Gz.green,
        'pending' => Gz.blue,
        _ => Gz.red,
      };

  String get _statusLabel => switch (ep.status) {
        'approved' => 'Расталған',
        'pending' => 'Күтуде',
        'rejected' => 'Қабылданбаған',
        _ => 'Бұғатталған',
      };

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ExecutorDetailScreen(ep: ep))),
              child: FutureBuilder<Profile?>(
              future: Repo.profileOf(ep.userId),
              builder: (context, snap) {
                final p = snap.data;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(p?.fullName ?? '…',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14.5)),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _statusColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(_statusLabel,
                              style: TextStyle(
                                  color: _statusColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${ep.vehicleTitle} · ${ep.vehiclePlate}'
                      '${ep.city != null ? ' · ${ep.city}' : ''}',
                      style: const TextStyle(
                          color: Gz.textSecondary, fontSize: 12),
                    ),
                    Text(
                      'Баланс: ${fmtT(ep.balance)} · Табыс: ${fmtT(ep.totalEarned)}',
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                    if (ep.busyOrderId != null)
                      Container(
                        margin: const EdgeInsets.only(top: 3),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: Gz.green.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text('🚚 Заказ орындауда',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Gz.green)),
                      ),
                    if (p != null)
                      RatingStars(p.rating, count: p.ratingCount, size: 12),
                  ],
                );
              },
            ),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) => _action(context, v),
            itemBuilder: (_) => [
              if (ep.status == 'approved')
                const PopupMenuItem(
                    value: 'request_docs',
                    child: Text('Құжат жаңартуды сұрау')),
              if (ep.status == 'approved')
                const PopupMenuItem(
                    value: 'block',
                    child: Text('Бұғаттау',
                        style: TextStyle(color: Gz.red))),
              if (ep.status == 'blocked')
                const PopupMenuItem(
                    value: 'unblock', child: Text('Бұғаттан шығару')),
              const PopupMenuItem(
                  value: 'balance', child: Text('Баланс түзету')),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _action(BuildContext context, String action) async {
    try {
      switch (action) {
        case 'request_docs':
          final res = await showDialog<(List<String>, String)>(
            context: context,
            builder: (ctx) => _RequestDocsDialog(isForeign: ep.isForeignCitizen),
          );
          if (res == null) return;
          if (res.$1.isEmpty) {
            if (context.mounted) {
              showSnack(context, 'Кемінде бір құжат таңдаңыз', error: true);
            }
            return;
          }
          await Repo.modRequestDocs(ep.userId, res.$1, res.$2);
          if (context.mounted) {
            showSnack(context, 'Сұраным жіберілді');
          }
        case 'block':
          final c = TextEditingController();
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Бұғаттау себебі'),
              content: TextField(controller: c, autofocus: true),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Болдырмау')),
                FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: Gz.red,
                      foregroundColor: Colors.white,
                      shadowColor: const Color(0x59DC2626)),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Бұғаттау'),
                ),
              ],
            ),
          );
          if (ok != true) return;
          await Repo.modSetExecutorStatus(ep.userId, 'blocked', c.text);
        case 'unblock':
          await Repo.modSetExecutorStatus(ep.userId, 'approved', '');
        case 'balance':
          final c = TextEditingController();
          final note = TextEditingController();
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Баланс түзету'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: c,
                    autofocus: true,
                    keyboardType: TextInputType.text,
                    decoration: const InputDecoration(
                        hintText: 'Сома (теріс болса шегеріледі)'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: note,
                    decoration:
                        const InputDecoration(hintText: 'Себебі'),
                  ),
                ],
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Болдырмау')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Сақтау')),
              ],
            ),
          );
          if (ok != true) return;
          final amount = int.tryParse(c.text.trim());
          if (amount == null || amount == 0) return;
          await Repo.c.rpc('mod_adjust_balance', params: {
            'p_user': ep.userId,
            'p_amount': amount,
            'p_note': note.text,
          });
      }
      onChanged();
    } catch (e) {
      if (context.mounted) showSnack(context, errText(e), error: true);
    }
  }
}

/// Құжат жаңартуды сұрау диалогы — қай құжатты + түсініктеме.
class _RequestDocsDialog extends StatefulWidget {
  final bool isForeign;
  const _RequestDocsDialog({required this.isForeign});

  @override
  State<_RequestDocsDialog> createState() => _RequestDocsDialogState();
}

class _RequestDocsDialogState extends State<_RequestDocsDialog> {
  final _fields = <String>{};
  final _comment = TextEditingController();

  List<(String, String)> get _options => [
        widget.isForeign
            ? ('passport', 'Шетел паспорты')
            : ('id', 'Жеке куәлік'),
        ('license', 'Жүргізуші куәлігі'),
        ('tech', 'Техпаспорт'),
        ('photos', 'Көлік фотолары'),
      ];

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Қай құжатты жаңарту керек?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (key, label) in _options)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(label),
              value: _fields.contains(key),
              onChanged: (v) => setState(() {
                if (v == true) {
                  _fields.add(key);
                } else {
                  _fields.remove(key);
                }
              }),
            ),
          const SizedBox(height: 8),
          TextField(
            controller: _comment,
            decoration: const InputDecoration(
                hintText: 'Түсініктеме (мыс: анық емес, ескірген)'),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Болдырмау')),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, (_fields.toList(), _comment.text)),
          child: const Text('Жіберу'),
        ),
      ],
    );
  }
}

/// Модератор: орындаушының толық картасы — статистика, көлік, құжаттар, пікірлер.
class ExecutorDetailScreen extends StatefulWidget {
  final ExecutorProfile ep;
  const ExecutorDetailScreen({super.key, required this.ep});

  @override
  State<ExecutorDetailScreen> createState() => _ExecutorDetailScreenState();
}

class _ExecutorDetailScreenState extends State<ExecutorDetailScreen> {
  ExecutorProfile get ep => widget.ep;

  Widget _statTile(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Gz.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Gz.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: Gz.textSecondary, fontSize: 12)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w900, color: color)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Орындаушы')),
      body: FutureBuilder<Profile?>(
        future: Repo.profileOf(ep.userId),
        builder: (context, psnap) {
          final p = psnap.data;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SectionCard(
                child: Row(
                  children: [
                    InitialsAvatar(p?.fullName ?? '?',
                        radius: 26, imageUrl: p?.avatarUrl),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p?.fullName ?? '…',
                              style: const TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.w800)),
                          Text(p?.phone ?? '',
                              style: const TextStyle(
                                  color: Gz.textSecondary, fontSize: 13)),
                          if (p != null)
                            RatingStars(p.rating,
                                count: p.ratingCount, size: 13),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Статистика
              FutureBuilder<Map<String, dynamic>>(
                future: Repo.modExecutorSummary(ep.userId),
                builder: (context, snap) {
                  final s = snap.data;
                  if (s == null) {
                    return const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  return Column(
                    children: [
                      Row(children: [
                        Expanded(
                            child: _statTile('Бүгін', '${s['today']} заказ',
                                Gz.green)),
                        const SizedBox(width: 8),
                        Expanded(
                            child: _statTile(
                                '7 күн', '${s['week']} заказ', Gz.blue)),
                        const SizedBox(width: 8),
                        Expanded(
                            child: _statTile(
                                'Барлығы', '${s['total']} заказ', Gz.ink)),
                      ]),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                            child: _statTile('Белсенді',
                                '${s['active']}', Gz.violet)),
                        const SizedBox(width: 8),
                        Expanded(
                            child: _statTile('Бас тартқан',
                                '${s['cancelled']}', Gz.red)),
                        const SizedBox(width: 8),
                        Expanded(
                            child: _statTile('Бүгінгі табыс',
                                fmtT(s['earned_today'] as num?), Gz.green)),
                      ]),
                    ],
                  );
                },
              ),
              if (ep.busyOrderId != null) ...[
                const SizedBox(height: 12),
                const Text('Қазіргі заказы',
                    style:
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 8),
                FutureBuilder<Order?>(
                  future: Repo.orderById(ep.busyOrderId!),
                  builder: (context, snap) {
                    final o = snap.data;
                    if (o == null) return const SizedBox.shrink();
                    return OrderCard(
                      order: o,
                      onTap: () =>
                          showOrderAdminSheet(context, o.id,
                              onChanged: () => setState(() {})),
                    );
                  },
                ),
              ],
              const SizedBox(height: 12),
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Көлік',
                        style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 15)),
                    const SizedBox(height: 8),
                    InfoRow('Маркасы', ep.vehicleTitle),
                    if (ep.city != null) InfoRow('Қала', ep.city!),
                    InfoRow('Мемнөмір', ep.vehiclePlate),
                    InfoRow('Баланс', fmtT(ep.balance)),
                    InfoRow('Жалпы табыс', fmtT(ep.totalEarned)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Құжаттар',
                      style:
                          TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Gz.bg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      ep.isForeignCitizen ? 'Шетел азаматы' : 'ҚР азаматы',
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                    child: DocImage(
                        path: ep.licensePath, label: 'Жүргізуші куәлігі')),
                const SizedBox(width: 8),
                Expanded(
                    child: DocImage(
                        path: ep.licenseSelfiePath, label: 'Правамен селфи')),
              ]),
              const SizedBox(height: 8),
              if (!ep.isForeignCitizen)
                Row(children: [
                  Expanded(
                      child:
                          DocImage(path: ep.idDocPath, label: 'Жеке куәлік')),
                  const SizedBox(width: 8),
                  Expanded(
                      child: DocImage(
                          path: ep.idSelfiePath, label: 'Куәлікпен селфи')),
                ])
              else
                Row(children: [
                  Expanded(
                      child: DocImage(
                          path: ep.passportPath, label: 'Шетел паспорты')),
                  const SizedBox(width: 8),
                  Expanded(
                      child: DocImage(
                          path: ep.passportSelfiePath,
                          label: 'Паспортпен селфи')),
                ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                    child: DocImage(
                        path: ep.techPassportPath, label: 'Техпаспорт')),
                const SizedBox(width: 8),
                Expanded(
                    child: DocImage(
                        path: ep.techPassportSelfiePath,
                        label: 'Техпаспортпен фото')),
              ]),
              const SizedBox(height: 12),
              if (p != null)
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ReviewsScreen(
                      userId: p.id,
                      name: p.fullName,
                      rating: p.rating,
                      ratingCount: p.ratingCount,
                    ),
                  )),
                  icon: const Icon(Icons.star_outline),
                  label: const Text('Пікірлерді қарау'),
                ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}
