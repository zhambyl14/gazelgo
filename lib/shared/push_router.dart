import 'package:flutter/material.dart';

import '../features/chat/order_chat_screen.dart';
import '../features/client/order_detail_screen.dart';
import '../features/executor/balance_screen.dart';
import '../features/executor/executor_order_screen.dart';
import '../features/moderator/moderator_shell.dart';
import '../features/support/support_screen.dart';

/// Push/локал уведомлениелерден навигация үшін — түбір Navigator кілті.
final navigatorKey = GlobalKey<NavigatorState>();

/// Хабарламаны басқанда тиісті бетке өту. FCM (onMessageOpenedApp,
/// getInitialMessage) және Android foreground локал уведомлениесі де осында
/// келеді. Хабардың `type`-ы аудиторияны білдіреді (сервер тек тиісті
/// пайдаланушыға жібереді), сол себепті рөлді бөлек сұрамай, тип бойынша
/// тиісті экранды ашамыз:
///   new_order        → орындаушы: заказды қарап, ұсыныс беру экраны
///   offer_accepted   → орындаушы: ұсынысы қабылданды (белсенді заказға өтеді)
///   offer_rejected   → орындаушы: ұсынысының нәтижесі
///   order_expired    → клиент: өз заказының беті
///   order_reminder   → клиент: өз заказының беті
///   new_offer        → клиент: ұсыныстар тізімі (заказ беті)
///   order_status     → клиент: заказ барысы (заказ беті)
///   support_reply    → клиент/орындаушы: қолдау қызметі
///   support_message  → модератор: қолдау чаттары (қойынды)
///   new_application  → модератор: жаңа өтінімдер (қойынды)
///   new_topup        → модератор: баланс толтыру өтінімдері (қойынды, 0049)
///   topup_approved   → орындаушы: балансы толды (0051)
///   topup_rejected   → орындаушы: толтыруы қабылданбады (0051)
///
/// Модератордың үш беті — панельдің ІШІНДЕГІ қойындылар, өз Scaffold-ы жоқ.
/// Оларды бөлек бет ретінде `push` жасасақ, фоны ҚАРА болып ашылатын; сол
/// себепті олар үшін жаңа бет ашпай, бар панельдің қойындысын ауыстырамыз
/// ([ModeratorShell.openTab]). Қалғандарының өз Scaffold-ы бар — әдеттегідей
/// push жасалады.
void openPushTarget(Map<String, dynamic> data) {
  final type = data['type'] as String?;
  final orderId = data['order_id'] as String?;
  final hasOrder = orderId != null && orderId.isNotEmpty;

  Widget? screen;
  if (hasOrder &&
      (type == 'new_order' ||
          type == 'offer_accepted' ||
          type == 'offer_rejected')) {
    screen = ExecutorOrderScreen(orderId: orderId);
  } else if (hasOrder && type == 'order_status') {
    // Статус өзгерісі екі жаққа да келуі мүмкін (мыс. «тиеу расталды» —
    // орындаушыға), сол себепті сервер `audience` жібереді.
    screen = data['audience'] == 'executor'
        ? ExecutorOrderScreen(orderId: orderId)
        : OrderDetailScreen(orderId: orderId);
  } else if (hasOrder &&
      (type == 'order_expired' ||
          type == 'order_reminder' ||
          type == 'new_offer')) {
    screen = OrderDetailScreen(orderId: orderId);
  } else if (hasOrder && type == 'order_chat') {
    // Заказ чатындағы жаңа хабар (0076): рөл мен екінші тараптың атын
    // чат экраны заказдан өзі анықтайды.
    screen = OrderChatScreen(orderId: orderId);
  } else if (type == 'support_reply') {
    screen = const SupportScreen();
  } else if (type == 'support_message') {
    ModeratorShell.openTab(ModeratorShell.tabSupport);
    return;
  } else if (type == 'new_application') {
    ModeratorShell.openTab(ModeratorShell.tabApplications);
    return;
  } else if (type == 'new_topup') {
    ModeratorShell.openTab(ModeratorShell.tabTopups);
    return;
  } else if (type == 'topup_approved' || type == 'topup_rejected') {
    // Орындаушыға: балансы толды не өтінімі қабылданбады (0051). Бұған дейін
    // орындаушыға МҮЛДЕ хабар келмейтін — қосымшаны қолмен ашып қарауы керек
    // болатын.
    screen = const BalanceScreen();
  } else if (hasOrder) {
    // Тип белгісіз, бірақ заказ id-і бар — қауіпсіз әдепкі: заказ беті.
    screen = OrderDetailScreen(orderId: orderId);
  }
  if (screen == null) return;

  final target = screen;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    navigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => target));
  });
}

