import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/lang.dart';
import '../core/repo.dart';
import '../core/theme.dart';

/// «Күйін тексеру» — орындаушы өтінімінің КҮЙІН серверден қайта сұрап,
/// НӘТИЖЕСІН АЙТАДЫ.
///
/// Бұрын түйме тек `ref.invalidate(...)` шақыратын: сұраныс үнсіз кетіп,
/// экранда ештеңе өзгермейтін де, жаңа тіркелген орындаушы «не тексерілді,
/// жауабы қайда?» деп шатасатын. Енді әрқашан НАҚТЫ жауап көрсетіледі:
///   • әлі тексеруде → «модератор қарағанда хабарлама келеді»;
///   • расталды      → құттықтау (карта да автоматты жаңарады);
///   • қабылданбады  → себебін қарауға шақыру;
///   • желі жоқ      → қатенің өзі.
Future<void> checkExecutorStatus(BuildContext context, WidgetRef ref) async {
  try {
    ref.invalidate(myExecutorProfileProvider);
    final fresh = await ref.read(myExecutorProfileProvider.future);
    if (!context.mounted) return;
    final msg = switch (fresh?.status) {
      'approved' => t('Расталды! Енді тариф алып, заказ қабылдай аласыз 🎉'),
      'rejected' => t('Өтінім қабылданбады — себебін қарап, қайта жіберіңіз.'),
      'blocked' => t('Аккаунт бұғатталған. Қолдау қызметіне жазыңыз.'),
      null => t('Өтінім табылмады — оны толтырып жіберіңіз.'),
      _ => t('Әлі тексеруде. Модератор қарағанда хабарлама келеді.'),
    };
    showSnack(context, msg);
  } catch (e) {
    if (context.mounted) showSnack(context, errText(e), error: true);
  }
}
