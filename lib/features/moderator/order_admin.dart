import 'package:flutter/material.dart';

import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import 'trust_actions.dart';

/// Модератордың заказ басқару терезесі: детальдар + статусты өзгерту /
/// тоқтату / қайта ұсыну. Оқыс оқиғаларға арналған.
Future<void> showOrderAdminSheet(BuildContext context, String orderId,
    {VoidCallback? onChanged}) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Gz.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _OrderAdminSheet(orderId: orderId, onChanged: onChanged),
  );
}

class _OrderAdminSheet extends StatefulWidget {
  final String orderId;
  final VoidCallback? onChanged;
  const _OrderAdminSheet({required this.orderId, this.onChanged});

  @override
  State<_OrderAdminSheet> createState() => _OrderAdminSheetState();
}

class _OrderAdminSheetState extends State<_OrderAdminSheet> {
  Order? _order;
  Map<String, dynamic>? _fraud;

  @override
  void initState() {
    super.initState();
    _load();
    _loadFraud();
  }

  Future<void> _load() async {
    final o = await Repo.orderById(widget.orderId);
    if (mounted) setState(() => _order = o);
  }

  Future<void> _loadFraud() async {
    try {
      final f = await Repo.orderFraudFlags(widget.orderId);
      if (mounted) setState(() => _fraud = f);
    } catch (_) {
      // эвристика сәтсіз болса — үнсіз өтеді, негізгі экранды бұзбайды
    }
  }

  /// Эвристика бойынша ескерту мәтіні (тек статистика — ML/дерек-анализ
  /// емес; себебі мен нәтиже жоқ жерде де флаг көрсетпейді).
  String? get _fraudWarning {
    final f = _fraud;
    if (f == null) return null;
    final pairCount = (f['repeated_pair_count'] as num?)?.toInt() ?? 0;
    final isNewHighValue = f['is_new_account_high_value'] == true;
    final parts = <String>[];
    if (pairCount >= 3) {
      parts.add(
          '${t('Бұл клиент пен газелист соңғы 30 күнде')} $pairCount ${t('рет '
              'бірге аяқтаған заказ жасаған — қайталанатын жұп.')}');
    }
    if (isNewHighValue) {
      parts.add(t('Клиент аккаунты жаңа (<24 сағ) әрі заказ бағасы жоғары.'));
    }
    if (parts.isEmpty) return null;
    return '${t('Тексеру қажет болуы мүмкін:')} ${parts.join(' ')}';
  }

  static const _statuses = [
    ('searching', 'Іздеуге қайтару (қайта ұсыну)'),
    ('accepted', 'Қабылданды'),
    ('arrived', 'Келді'),
    ('loading', 'Тиеу'),
    ('in_transit', 'Тасымалдауда'),
    ('completed', 'Аяқталды'),
    ('cancelled', 'Тоқтатылды'),
  ];

  Future<void> _setStatus(String status) async {
    final label = t(_statuses.firstWhere((s) => s.$1 == status).$2);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Статусты өзгерту')),
        content: Text('${t('Заказ статусы')} «$label» ${t('болады. Растайсыз ба?')}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(t('Жоқ'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(t('Иә, өзгерту'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Repo.modSetOrderStatus(widget.orderId, status);
      if ((status == 'completed' || status == 'cancelled') &&
          _order!.photos.isNotEmpty) {
        Repo.deleteOrderPhotos(_order!.photos);
      }
      widget.onChanged?.call();
      await _load();
      if (mounted) showSnack(context, '${t('Статус өзгертілді:')} $label');
    } catch (e) {
      if (mounted) showSnack(context, errText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = _order;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, scroll) => o == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              controller: scroll,
              padding: const EdgeInsets.all(16),
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: Gz.border,
                        borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(fmtT(o.displayPrice),
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w900)),
                    ),
                    StatusChip(o.status),
                  ],
                ),
                if (_fraudWarning != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3E0),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFFB74D)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.warning_amber_rounded,
                            color: Color(0xFFB86E00), size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_fraudWarning!,
                              style: const TextStyle(
                                  color: Color(0xFF8A5300),
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  height: 1.4)),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                SectionCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RouteLine(
                        from: o.fromDisplay,
                        to: o.toDisplay,
                        stops: o.stops.map((s) => s.display).toList(),
                      ),
                      const Divider(height: 20),
                      InfoRow(t('Жүк'), o.cargoDesc),
                      InfoRow(t('Көлік'), o.vehicleType.label),
                      InfoRow(t('Бағыты'),
                          o.intercity ? t('Қалааралық') : t('Қала ішінде')),
                      InfoRow(t('Құрылды'), fmtDate(o.createdAt)),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                // Тараптар (басу арқылы сенім деңгейі/блок әрекеттері ашылады)
                FutureBuilder<Profile?>(
                  future: Repo.profileOf(o.clientId),
                  builder: (context, snap) => _PartyCard(
                    profile: snap.data,
                    subtitle: t('Клиент'),
                    asRole: 'client',
                    onChanged: () => setState(() {}),
                  ),
                ),
                if (o.executorId != null) ...[
                  const SizedBox(height: 8),
                  FutureBuilder<Profile?>(
                    future: Repo.profileOf(o.executorId!),
                    builder: (context, snap) => _PartyCard(
                      profile: snap.data,
                      subtitle: t('Орындаушы'),
                      asRole: 'executor',
                      onChanged: () => setState(() {}),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Text(t('Статусты өзгерту'),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 4),
                Text(
                  t('Тек оқыс оқиғада қолданыңыз (мыс: орындаушы аяқтай алмай тұр).'),
                  style: const TextStyle(color: Gz.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (key, label) in _statuses)
                      if (key != o.status)
                        ActionChip(
                          label: Text(t(label),
                              style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700)),
                          backgroundColor: key == 'cancelled'
                              ? Gz.red.withValues(alpha: 0.08)
                              : Gz.bg,
                          side: BorderSide(
                              color: key == 'cancelled'
                                  ? Gz.red.withValues(alpha: 0.4)
                                  : Gz.border),
                          onPressed: () => _setStatus(key),
                        ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}

/// Клиент/орындаушы карточкасы — басу арқылы сенім деңгейі/блок парақшасы ашылады.
class _PartyCard extends StatelessWidget {
  final Profile? profile;
  final String subtitle;

  /// Рейтингті қай рөл бойынша көрсету (қос рөл, 0046).
  final String asRole;
  final VoidCallback onChanged;
  const _PartyCard({
    required this.profile,
    required this.subtitle,
    required this.asRole,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = profile;
    return InkWell(
      borderRadius: BorderRadius.circular(Gz.radius),
      onTap: p == null
          ? null
          : () => showTrustActionsSheet(context, p, onChanged: onChanged),
      child: SectionCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
                child: ProfileBrief(
                    profile: p, subtitle: subtitle, asRole: asRole)),
            if (p != null) ...[
              const SizedBox(width: 8),
              TrustBadge(score: p.trustScore, blocked: p.isBlocked),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, size: 18, color: Gz.textSecondary),
            ],
          ],
        ),
      ),
    );
  }
}
