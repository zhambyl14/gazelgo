import 'package:flutter/material.dart';

import '../../core/lang.dart';

/// Бағалау тегі (0079) — «не ұнады / не ұнамады» бір басумен. Кодтар
/// сервердегі `submit_review` рұқсат тізімімен ДӘЛ бірдей болуы керек.
class ReviewTag {
  final String code;

  /// Қазақша мәтін (t() арқылы аударылады).
  final String label;
  final IconData icon;
  final bool positive;

  const ReviewTag(this.code, this.label, this.icon, {this.positive = true});
}

/// Клиент ОРЫНДАУШЫНЫ бағалағанда.
const kExecutorReviewTags = [
  ReviewTag('punctual', 'Уақытында келді', Icons.schedule_rounded),
  ReviewTag('careful', 'Жүкке ұқыпты', Icons.inventory_2_outlined),
  ReviewTag('polite', 'Сыпайы', Icons.sentiment_satisfied_alt_rounded),
  ReviewTag('helpful', 'Тиеуге көмектесті', Icons.handshake_outlined),
  ReviewTag('clean_car', 'Көлігі таза', Icons.local_car_wash_outlined),
  ReviewTag(
    'late',
    'Кешікті',
    Icons.running_with_errors_rounded,
    positive: false,
  ),
  ReviewTag(
    'rude',
    'Дөрекі',
    Icons.sentiment_dissatisfied_rounded,
    positive: false,
  ),
  ReviewTag(
    'damaged',
    'Жүкті бүлдірді',
    Icons.broken_image_outlined,
    positive: false,
  ),
  ReviewTag(
    'overpriced',
    'Келісілгеннен көп сұрады',
    Icons.money_off_rounded,
    positive: false,
  ),
];

/// Орындаушы КЛИЕНТТІ бағалағанда.
const kClientReviewTags = [
  ReviewTag(
    'ready_on_time',
    'Жүк дайын болды',
    Icons.check_circle_outline_rounded,
  ),
  ReviewTag('clear_info', 'Ақпарат нақты', Icons.fact_check_outlined),
  ReviewTag('polite', 'Сыпайы', Icons.sentiment_satisfied_alt_rounded),
  ReviewTag(
    'long_wait',
    'Ұзақ күттірді',
    Icons.hourglass_bottom_rounded,
    positive: false,
  ),
  ReviewTag(
    'wrong_info',
    'Ақпарат сәйкес емес',
    Icons.report_gmailerrorred_rounded,
    positive: false,
  ),
  ReviewTag(
    'rude',
    'Дөрекі',
    Icons.sentiment_dissatisfied_rounded,
    positive: false,
  ),
];

/// Тег кодының оқылатын атауы (профильдегі «жиі айтылады» тізімі үшін).
ReviewTag? reviewTagOf(String code) {
  for (final tg in [...kExecutorReviewTags, ...kClientReviewTags]) {
    if (tg.code == code) return tg;
  }
  return null;
}

String reviewTagLabel(String code) {
  final tg = reviewTagOf(code);
  return tg == null ? code : t(tg.label);
}
