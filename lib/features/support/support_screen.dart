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

  /// Тариф ұзақтығы (0055) — «Тариф деген не?» FAQ жауабы модератордың
  /// нақты баптауын көрсетуі үшін.
  AppConfig _cfg = AppConfig();

  @override
  void initState() {
    super.initState();
    Repo.myProfile().then((p) {
      if (mounted) setState(() => _role = p?.role ?? 'client');
    });
    Repo.settings().then((s) {
      final tariffs = s['tariffs'];
      if (mounted) {
        setState(() => _cfg = AppConfig.fromSettings(null,
            tariffs: tariffs is Map ? Map<String, dynamic>.from(tariffs) : null));
      }
    }).catchError((_) {});
  }

  List<(String, String)> get _faq => _role == 'executor'
      ? [('Тариф деген не?', tariffDefinitionText(_cfg)), ..._executorFaqRest]
      : _clientFaq;

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
      'Заказды қалай беремін?',
      'Басты беттен керек көлік түрін таңдап, «Қайдан» және «Қайда» '
          'адрестерін қойыңыз. Содан соң бағаңызды ұсынып, заказды '
          'жариялаңыз — орындаушылар ұсыныс жібере бастайды.'
    ),
    (
      '«Такси» мен «Доставка» айырмашылығы неде?',
      '«Такси» — АДАМ тасымалы: заказ формасында жолаушы санын '
          'көрсетесіз, жүк сипаттамасы да, фото да сұралмайды. '
          '«Доставка» — жеңіл көлікпен ҰСАҚ ЖҮК жеткізу: құжат, дәрі, '
          'кішкене қап. Екеуі де жеңіл көлікпен орындалады.'
    ),
    (
      'Бір заказға бірнеше мекенжай қосуға бола ма?',
      'Иә. Адрес жолының астындағы «Адрес қосу» арқылы 3 жеткізу нүктесіне '
          'дейін қосасыз: маршрут A → 1 → 2 → финиш. Мекенжайлардың ретін '
          'сүйреп ауыстыруға болады. Қашықтық та, баға да БҮКІЛ маршрут '
          'бойынша есептеледі.'
    ),
    (
      'Бағаны кім қояды?',
      'Бағаны СІЗ ұсынасыз. Орындаушылар келіседі немесе өз бағасын ұсынады — '
          'қолайлысын таңдайсыз.'
    ),
    (
      'Орындаушы келгенін қалай растаймын?',
      'Орындаушы «Келдім» дегенде, заказ экранында растау түймесі шығады: '
          'жүк заказында «Тиеу басталды», таксиде «Отырғызу басталды». '
          'Орындаушы шынымен келсе ғана растаңыз — содан соң ол жолға '
          'шыға алады.'
    ),
    (
      'Заказды қалай тоқтатамын?',
      'Заказ экранындағы «Заказды тоқтату» арқылы — орындаушы тиеуді '
          'бастамай тұрып. Тиеу басталғаннан кейін тоқтатуға болмайды.'
    ),
    (
      'Заказымды ешкім қабылдамай жатыр ше?',
      'Көбіне себебі — баға. Заказ экранында «Бағаны көтеру» ұсынысы '
          'шығады, соны қолданып көріңіз. Сондай-ақ адрестің дұрыс '
          'қойылғанын және керек көлік түрін таңдағаныңызды тексеріңіз.'
    ),
    (
      'Төлемді қалай жасаймын?',
      'Төлем орындаушымен тікелей: Kaspi аударым немесе қолма-қол. Қосымша '
          'сіздің ақшаңызды ұстамайды және төлемге араласпайды.'
    ),
    (
      'Қандай жүкке тыйым салынған?',
      'Есірткі, қару-жарақ, жарылғыш және улы заттар, құжатсыз акциз '
          'тауарлары, ұрланған мүлік, ақша мен банк карталары және тағы '
          'басқа. Толық тізім — заказ бетіндегі «Тізім» сілтемесінде '
          'немесе Пайдаланушы келісімінің 5-бөлімінде.'
    ),
    (
      'Күдікті жағдай болса не істеймін?',
      'Заказ экранындағы «Күдікті жағдай туралы хабарлау» арқылы модераторға '
          'дереу жазыңыз. Бұл заказды бас тартумен шатастырылмайды — '
          'заказдың күйі өзгермейді.'
    ),
    (
      'Өзім орындаушы бола аламын ба?',
      'Иә. Мәзірден «Орындаушы болу» дейсіз де, құжаттарыңызды жүктеп '
          'модерациядан өтесіз. Клиенттік деректеріңіз ЖОЙЫЛМАЙДЫ — кез '
          'келген уақытта кері ауысасыз. Рейтинг әр рөл бойынша бөлек '
          'жүреді. Белсенді заказ бар кезде рөл ауыстыруға болмайды.'
    ),
    (
      'Аккаунтымды қалай өшіремін?',
      '«Профиль → Аккаунтты өшіру». Белсенді заказ болмаса, өшіру бірден '
          'орындалады және кері қайтарылмайды. Екі рөлдің де деректері '
          'жойылады.'
    ),
  ];

  /// Тариф сұрағы алынып тасталды — ол енді [_tariffFaqAnswer]-мен
  /// динамикалық түрде _faq getter-інде ЕҢ АЛДЫҢҒЫ орынға қойылады.
  static const _executorFaqRest = <(String, String)>[
    (
      'Балансты қалай толтырамын?',
      '«Баланс» экранынан соманы жазып, Kaspi арқылы аударасыз да, чектің '
          'фотосын тіркеп жібересіз. Модератор чекті тексерген соң сома '
          'балансыңызға қосылады. Өтінімнің күйін сол экранның төменгі '
          'жағынан көресіз.'
    ),
    (
      'Заказды қалай аламын?',
      'Лентадан заказды таңдап «Келісу» (клиент бағасына) не «Өз бағам» '
          '(қарсы ұсыныс). Клиент қабылдаса — заказ сіздікі.'
    ),
    (
      'Такси мен доставка заказдарын көрмеймін ше?',
      'Бұл екі бөлімді әкімшілік бөлек қосады, әрі оларға тіркелгенде '
          'таңдаған көлік түріңіз сай болуы керек. Көлік түрін өзгерту '
          'қажет болса — қолдау қызметіне жазыңыз.'
    ),
    (
      'Клиент растауды бермей жатыр ше?',
      'Сіз «Келдім» дегеннен кейін клиент растауы керек: жүк заказында '
          '«Тиеу басталды», таксиде «Отырғызу басталды». Ол растамайынша '
          '«Жолға шықтық» батырмасы шықпайды — клиентке хабарласыңыз.'
    ),
    (
      '«Келдім» немесе «Аяқтау» басылмай тұр ше?',
      'Бұл екі әрекет орналасуыңызды тексереді: тиісті нүктеге шамамен '
          '1,5 км жақын болуыңыз керек. Геолокацияны қосыңыз және '
          'қосымшаға рұқсат берілгенін тексеріңіз.'
    ),
    (
      'Көп мекенжайлы заказ қалай орындалады?',
      'Заказда бірнеше нүкте болса, лентада «+N аялдама» белгісі тұрады. '
          'Заказ экранынан барлық нүктені бірден көресіз де, әрқайсысына '
          'навигация саласыз. Келісілген баға БҮКІЛ маршрутқа қатысты.'
    ),
    (
      'Ақшамды қашан аламын?',
      'Төлемді клиент сізге ТІКЕЛЕЙ береді — қолма-қол не Kaspi аударыммен. '
          'Қосымша ақшаны ұстамайды; балансыңыз тек тариф төлеу үшін.'
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
    (
      'Клиент болып та жұмыс істей аламын ба?',
      'Иә. Мәзірден «Клиентке ауысу» дейсіз — орындаушылық деректеріңіз бен '
          'құжаттарыңыз сақталады, кез келген уақытта кері ауысасыз. Рейтинг '
          'әр рөл бойынша БӨЛЕК жүреді. Белсенді заказ бар кезде рөл '
          'ауыстыруға болмайды.'
    ),
    (
      'Рейтингім қалай есептеледі?',
      'Заказ аяқталған соң клиент сізді бағалайды. Орындаушы ретіндегі '
          'рейтингіңіз клиент ретіндегіден мүлдем бөлек — біреуі екіншісіне '
          'әсер етпейді.'
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
          // Ашық тред жоқ болса — ЕҢ СОҢҒЫ (жабық) тред. Тізім `last_msg_at`
          // бойынша кемімелі келеді, сол себепті ол — `first`.
          current ??= threads.isNotEmpty ? threads.first : null;

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
                  // ЖАБЫҚ тредтің де id-і беріледі — пайдаланушы соңғы
                  // сөйлесуін оқи алуы керек. Бұрын мұнда `null` тұрғандықтан
                  // чат жабылған соң қосымшаны қайта ашқанда тарих БОС
                  // экранға ауысатын; 0058-ден кейін чат 20 минутта өзі
                  // жабылатындықтан, бұл әдепкі жағдайға айналар еді.
                  // `threadOpen: false` кезінде ChatView төменде «қайта
                  // жазсаңыз ашылады» деп ескертеді, ал жаңа хабарлама
                  // `support_send` арқылы жаңа тред ашады.
                  threadId: current?.id,
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
