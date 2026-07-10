import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';

/// Сенім деңгейі бейджі: балл (0-100) + бұғатталған болса қызыл белгі.
class TrustBadge extends StatelessWidget {
  final int score;
  final bool blocked;
  const TrustBadge({super.key, required this.score, required this.blocked});

  @override
  Widget build(BuildContext context) {
    final color = blocked
        ? Gz.red
        : score < 80
            ? const Color(0xFFB86E00)
            : Gz.green;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(blocked ? Icons.block : Icons.shield_outlined,
              size: 13, color: color),
          const SizedBox(width: 4),
          Text(blocked ? 'Бұғатталған' : 'Сенім $score/100',
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}

/// Модератордың пайдаланушыға сенім/блок әрекеттерін ашатын парақшасы:
/// қолмен балл қосу/азайту (±15) және аккаунтты блоктау/блоктан шығару.
Future<void> showTrustActionsSheet(BuildContext context, Profile profile,
    {VoidCallback? onChanged}) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Gz.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _TrustSheet(profile: profile, onChanged: onChanged),
  );
}

class _TrustSheet extends StatefulWidget {
  final Profile profile;
  final VoidCallback? onChanged;
  const _TrustSheet({required this.profile, this.onChanged});

  @override
  State<_TrustSheet> createState() => _TrustSheetState();
}

class _TrustSheetState extends State<_TrustSheet> {
  late int _score = widget.profile.trustScore;
  late bool _blocked = widget.profile.isBlocked;
  late String? _reason = widget.profile.blockReason;
  bool _busy = false;

  Future<void> _adjust(int delta) async {
    setState(() => _busy = true);
    try {
      final s = await Repo.modAdjustTrustScore(
        widget.profile.id,
        delta,
        delta < 0
            ? 'Модератор күдікті деп белгіледі'
            : 'Модератор сенімді қалпына келтірді',
      );
      if (!mounted) return;
      setState(() {
        _score = s;
        if (s <= 50) _blocked = true;
      });
      widget.onChanged?.call();
      showSnack(context, 'Сенім деңгейі: $s/100');
    } catch (e) {
      if (mounted) showSnack(context, errText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleBlock() async {
    final blocking = !_blocked;
    var reason = '';
    if (blocking) {
      final c = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Блоктау себебі'),
          content: TextField(
            controller: c,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Мыс: тыйым салынған жүкке күдік'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Болдырмау')),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: Gz.red, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Блоктау'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      reason = c.text.trim();
    }
    setState(() => _busy = true);
    try {
      await Repo.modSetAccountBlocked(widget.profile.id, blocking, reason);
      if (!mounted) return;
      setState(() {
        _blocked = blocking;
        _reason = blocking ? reason : null;
        if (!blocking && _score <= 50) _score = 60;
      });
      widget.onChanged?.call();
      showSnack(context, blocking ? 'Аккаунт бұғатталды' : 'Блок алынды');
    } catch (e) {
      if (mounted) showSnack(context, errText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                InitialsAvatar(p.fullName.isEmpty ? '?' : p.fullName,
                    imageUrl: p.avatarUrl),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.fullName.isEmpty ? '…' : p.fullName,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 15)),
                      Text(p.phone,
                          style: const TextStyle(
                              color: Gz.textSecondary, fontSize: 12.5)),
                    ],
                  ),
                ),
                TrustBadge(score: _score, blocked: _blocked),
              ],
            ),
            if (_blocked && (_reason?.isNotEmpty ?? false)) ...[
              const SizedBox(height: 8),
              Text('Себебі: $_reason',
                  style:
                      const TextStyle(color: Gz.textSecondary, fontSize: 12.5)),
            ],
            const SizedBox(height: 18),
            const Text('Сенім деңгейі',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            const SizedBox(height: 4),
            const Text(
              'Хабарлама түскен сайын автоматты −15. 50-ден төмен түссе '
              'аккаунт автоматты бұғатталады (жаңа заказ/ұсыныс бере алмайды).',
              style: TextStyle(color: Gz.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _adjust(-15),
                  child: const Text('−15 (күдікті)',
                      style: TextStyle(fontSize: 12.5)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _adjust(15),
                  child: const Text('+15 (сенімді қалпына келтіру)',
                      style: TextStyle(fontSize: 12.5)),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: _blocked ? Gz.green : Gz.red,
                  foregroundColor: Colors.white,
                ),
                onPressed: _busy ? null : _toggleBlock,
                child: Text(_blocked ? 'Блоктан шығару' : 'Аккаунтты блоктау'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
