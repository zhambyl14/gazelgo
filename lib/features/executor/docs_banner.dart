import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/theme.dart';
import '../auth/executor_apply_screen.dart';

/// Модератордың құжат жаңарту сұранымы / ревью күйі баннері.
/// Басты бетте де, профильде де, тариф экранында да көрсетіледі.
class ExecutorDocsBanner extends StatelessWidget {
  final ExecutorProfile? ep;
  final EdgeInsets padding;
  const ExecutorDocsBanner(
      {super.key, required this.ep, this.padding = EdgeInsets.zero});

  @override
  Widget build(BuildContext context) {
    final e = ep;
    if (e == null) return const SizedBox.shrink();

    if (e.docsReviewPending) {
      return Padding(
        padding: padding,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFEAF3FF),
            borderRadius: BorderRadius.circular(Gz.radius),
            border: Border.all(color: Gz.blue.withValues(alpha: 0.3)),
          ),
          child: const Row(children: [
            Icon(Icons.hourglass_top, color: Gz.blue),
            SizedBox(width: 10),
            Expanded(
              child: Text('Жаңартылған құжаттар модератор тексеруінде…',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      );
    }

    if (e.docsUpdateRequested) {
      return Padding(
        padding: padding,
        child: InkWell(
          borderRadius: BorderRadius.circular(Gz.radius),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ExecutorApplyScreen(existing: e))),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF0F0),
              borderRadius: BorderRadius.circular(Gz.radius),
              border: Border.all(color: Gz.red.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.assignment_late, color: Gz.red),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Құжаттарды жаңарту қажет',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 14.5)),
                      Text(
                        e.docsUpdateComment?.isNotEmpty == true
                            ? e.docsUpdateComment!
                            : 'Модератор құжаттарыңызды жаңартуды сұрады.',
                        style: const TextStyle(
                            color: Gz.textSecondary, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Gz.red),
              ],
            ),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
