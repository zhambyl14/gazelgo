import 'package:flutter/material.dart';

import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import 'chat_view.dart';

/// Заказ экрандарында көрсетілетін «Қолдау қызметі» түймесі.
class SupportOrderButton extends StatelessWidget {
  final String orderId;
  const SupportOrderButton({super.key, required this.orderId});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: EdgeInsets.zero,
      child: ListTile(
        leading: const Icon(Icons.support_agent, color: Gz.ink),
        title: Text(t('Қолдау қызметі'),
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(t('Жиі қойылатын сұрақтар / модераторға жазу')),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => SupportScreen(orderId: orderId))),
      ),
    );
  }
}

/// Қолдау қызметі: алдымен жиі қойылатын сұрақтар (рөлге сай), төменде —
/// «Модераторға жазу» түймесі (нағыз чат). Пайдаланушы бірден сообщение
/// жазбай, көбіне жауабын осы жерден табады.
class SupportScreen extends StatefulWidget {
  final String? orderId;
  const SupportScreen({super.key, this.orderId});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  String? _role; // client | executor | moderator

  @override
  void initState() {
    super.initState();
    Repo.myProfile().then((p) {
      if (mounted) setState(() => _role = p?.role ?? 'client');
    });
  }

  List<(String, String)> get _faq =>
      _role == 'executor' ? _executorFaq : _clientFaq;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t('Қолдау қызметі'))),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Text(t('Жиі қойылатын сұрақтар'),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 4),
          Text(t('Көп сұрақтың жауабы осында. Таппасаңыз — төменнен '
              'модераторға жазыңыз.'),
              style: const TextStyle(color: Gz.textSecondary, fontSize: 12.5)),
          const SizedBox(height: 12),
          for (final (q, a) in _faq) _FaqItem(question: t(q), answer: t(a)),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Gz.surface,
              borderRadius: BorderRadius.circular(Gz.radius),
              border: Border.all(color: Gz.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(t('Жауабын таппадыңыз ба?'),
                    style: const
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 4),
                Text(t('Модератор жеке жауап береді.'),
                    style: const
                        TextStyle(color: Gz.textSecondary, fontSize: 12.5)),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) =>
                        SupportChatScreen(orderId: widget.orderId),
                  )),
                  icon: const Icon(Icons.support_agent),
                  label: Text(t('Қолдау алу (модераторға жазу)')),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  static const _clientFaq = <(String, String)>[
    (
      'Газельді қалай шақырамын?',
      'Басты беттен «Газель шақыру» → «Қайдан» және «Қайда» адрестерін '
          'таңдап, бағаңызды қойып, заказ беріңіз. Орындаушылар ұсыныс жібереді.'
    ),
    (
      'Бағаны кім қояды?',
      'Бағаны СІЗ ұсынасыз. Орындаушылар келіседі немесе өз бағасын ұсынады — '
          'қолайлысын таңдайсыз.'
    ),
    (
      'Орындаушы келгенін қалай растаймын?',
      'Орындаушы «Келдім» дегенде, заказ экранында «Тиеу басталды» түймесі '
          'шығады. Орындаушы шынымен келсе ғана растаңыз — содан соң ол жолға '
          'шыға алады.'
    ),
    (
      'Заказды қалай тоқтатамын?',
      'Заказ экранында «Заказды тоқтату» (орындаушы тиеуді бастамай тұрып '
          'болады). Тиеу басталғаннан кейін тоқтатуға болмайды.'
    ),
    (
      'Төлемді қалай жасаймын?',
      'Төлем орындаушымен тікелей (Kaspi аударым немесе қолма-қол). Қосымша '
          'ақшаңызды ұстамайды.'
    ),
    (
      'Қандай жүкке тыйым салынған?',
      'Заңсыз, қауіпті, тыйым салынған заттарды тасымалдауға болмайды. Толығын '
          'Пайдаланушы келісімінен қараңыз.'
    ),
  ];

  static const _executorFaq = <(String, String)>[
    (
      'Тариф деген не?',
      'Тариф = 1 ауысым (12 сағат: 08:00–20:00 не 20:00–08:00), сол ауысымда '
          '10 заказға дейін. Тариф біреу ғана — бағасы күндіз де, түнде де '
          'бірдей.'
    ),
    (
      'Заказды қалай аламын?',
      'Лентадан заказды таңдап «Келісу» (клиент бағасына) не «Өз бағам» '
          '(қарсы ұсыныс). Клиент қабылдаса — заказ сіздікі.'
    ),
    (
      'Клиент «Тиеу басталды» демей жатыр ше?',
      'Сіз «Келдім» дегеннен кейін клиент тиеуді растауы керек. Ол растамайынша '
          '«Жолға шықтық» батырмасы шықпайды — клиентке хабарласыңыз.'
    ),
    (
      'Ақшамды қашан аламын?',
      'Заказды аяқтағанда табысыңызға қосылады. Балансты Kaspi арқылы шешіп '
          'аласыз (Баланс экранынан).'
    ),
    (
      'Қандай заказдарды көремін?',
      'Тіркелгенде таңдаған көлік түріңізге (газель, фургон, КамАЗ…) берілген '
          'және өз қалаңыздан шығатын заказдарды ғана көресіз.'
    ),
    (
      'Құжаттарым қайтарылды ше?',
      'Профильдегі / басты беттегі «Құжаттарды жаңарту» баннерін басып, '
          'модератор көрсеткен құжатты қайта жүктеңіз.'
    ),
  ];
}

/// Бір FAQ жазбасы — басқанда жауабы ашылады.
class _FaqItem extends StatelessWidget {
  final String question;
  final String answer;
  const _FaqItem({required this.question, required this.answer});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Gz.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Gz.border),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          shape: const Border(),
          title: Text(question,
              style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 14)),
          iconColor: Gz.ink,
          collapsedIconColor: Gz.textSecondary,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(answer,
                  style: const TextStyle(
                      color: Gz.textSecondary, fontSize: 13.5, height: 1.45)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Нағыз қолдау чаты (пайдаланушы ↔ модератор). FAQ-тан «Қолдау алу»
/// түймесі арқылы ашылады. [orderId] берілсе — модератор чат қай заказ
/// бойынша екенін көреді.
class SupportChatScreen extends StatefulWidget {
  final String? orderId;
  const SupportChatScreen({super.key, this.orderId});

  @override
  State<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends State<SupportChatScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t('Модераторға жазу'))),
      body: StreamBuilder<List<SupportThread>>(
        stream: Repo.myThreadsStream(),
        builder: (context, snap) {
          final threads = snap.data ?? [];
          SupportThread? current;
          for (final t in threads) {
            if (t.isOpen) {
              current = t;
              break;
            }
          }
          current ??= threads.isNotEmpty ? threads.last : null;

          return Column(
            children: [
              if (current != null && current.isOpen)
                Material(
                  color: Gz.surface,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Row(
                      children: [
                        const Icon(Icons.circle, size: 10, color: Gz.green),
                        const SizedBox(width: 6),
                        Expanded(
                            child: Text(t('Чат ашық'),
                                style: const TextStyle(fontSize: 13))),
                        TextButton.icon(
                          onPressed: () async {
                            try {
                              await Repo.supportClose(current!.id);
                            } catch (e) {
                              if (context.mounted) {
                                showSnack(context, errText(e), error: true);
                              }
                            }
                          },
                          icon: const Icon(Icons.check, size: 16),
                          label: Text(t('Аяқтау')),
                        ),
                      ],
                    ),
                  ),
                ),
              Expanded(
                child: ChatView(
                  key: ValueKey(current?.id ?? 'new'),
                  threadId: current?.isOpen == true ? current!.id : null,
                  asModerator: false,
                  threadOpen: current?.isOpen ?? true,
                  onSend: (body, imagePath) => Repo.supportSend(body,
                      imagePath: imagePath, orderId: widget.orderId),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
