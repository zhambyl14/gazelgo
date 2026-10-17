import 'package:flutter/material.dart';

import '../../core/lang.dart';
import '../../core/models.dart';
import '../../shared/widgets.dart';
import '../auth/executor_apply_screen.dart';

/// Модератордың құжат жаңарту сұранымы / ревью күйі баннері.
/// Басты бетте де, профильде де, тариф экранында да — БІР ғана виджет
/// (бұрын тариф экранында оның көшірмесі тұратын).
class ExecutorDocsBanner extends StatelessWidget {
  final ExecutorProfile? ep;
  final EdgeInsets padding;
  const ExecutorDocsBanner({
    super.key,
    required this.ep,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final e = ep;
    if (e == null) return const SizedBox.shrink();

    if (e.docsReviewPending) {
      return Padding(
        padding: padding,
        child: GzNotice(
          tone: NoticeTone.info,
          icon: Icons.hourglass_top_rounded,
          message: t('Жаңартылған құжаттар модератор тексеруінде…'),
        ),
      );
    }

    if (e.docsUpdateRequested) {
      return Padding(
        padding: padding,
        child: GzNotice(
          tone: NoticeTone.danger,
          icon: Icons.assignment_late_outlined,
          title: t('Құжаттарды жаңарту қажет'),
          message: e.docsUpdateComment?.isNotEmpty == true
              ? e.docsUpdateComment!
              : t('Модератор құжаттарыңызды жаңартуды сұрады.'),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => ExecutorApplyScreen(existing: e)),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
