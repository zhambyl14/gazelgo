import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../core/geo.dart';
import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/map_widgets.dart';
import '../../shared/widgets.dart';
import 'active_order_screen.dart';
import 'offer_sheet.dart';

/// Ұсыныс жібергеннен кейінгі орындаушы экраны:
/// клиент жауабын күту → қабылданса белсенді заказға өту.
///
/// Құрылымы: жоғарыда КҮЙ карточкасы (жаңа заказ / ұсыныс жіберілді —
/// клиент таңдап жатыр / қабылданбады / басқаға кетті), содан соң карта,
/// маршрут, заказ деректері, жүк/түсініктеме, ал ең төменде — сол күйге
/// сай әрекет батырмасы.
class ExecutorOrderScreen extends StatefulWidget {
  final String orderId;
  const ExecutorOrderScreen({super.key, required this.orderId});

  @override
  State<ExecutorOrderScreen> createState() => _ExecutorOrderScreenState();
}

class _ExecutorOrderScreenState extends State<ExecutorOrderScreen> {
  /// Заказ ағыны бір рет құрылады (build ішінде құрылса, әр қайта салуда
  /// жаңа polling басталатын).
  late final Stream<Order?> _orderStream = Repo.orderStream(widget.orderId);

  /// Ұсыныстар ағыны — тек заказ «іздеуде» тұрғанда керек. Polling ағыны
  /// бір рет қана тыңдалады, сол себепті заказ ол күйден шыққанда ағын
  /// тасталады да, қайта керек болса жаңасы құрылады.
  Stream<List<Offer>>? _offersStream;

  bool _redirected = false;

  @override
  Widget build(BuildContext context) {
    final myId = Repo.uid;
    return Scaffold(
      appBar: AppBar(title: Text(t('Заказ'))),
      body: StreamBuilder<Order?>(
        stream: _orderStream,
        builder: (context, snap) {
          final o = snap.data;
          // Ұсыныстар StreamBuilder-і тек «іздеуде» күйінде ағашта тұрады.
          // Одан шыққанда ол тыңдауды тоқтатады — polling ағыны бір рет қана
          // тыңдалатындықтан, қайта оралғанда ЖАҢА ағын құрылуы керек
          // (әйтпесе «Stream has already been listened to» қатесі).
          if (o?.status != 'searching') _offersStream = null;
          if (o == null) {
            return const Center(child: CircularProgressIndicator());
          }
          // Маған тағайындалса — белсенді заказ экранына ауысамыз
          if (o.executorId == myId && o.isActive) {
            if (!_redirected) {
              _redirected = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => ActiveOrderScreen(orderId: widget.orderId),
                  ),
                );
              });
            }
            return const Center(child: CircularProgressIndicator());
          }

          // Заказ басқаға кетті немесе жабылды — ұсыныстар керек емес.
          if (o.status != 'searching') {
            return _page(o, _closedState(o, myId));
          }

          // Менің ұсынысымның күйін көрсету
          return StreamBuilder<List<Offer>>(
            stream: _offersStream ??= Repo.offersStream(o.id),
            builder: (context, snap) {
              // Ұсыныстар әлі жүктелмеген — «жаңа заказ» күйі бір сәтке
              // жыпылықтап шықпауы үшін күте тұрамыз.
              if (!snap.hasData && !snap.hasError) {
                return _page(o, null);
              }
              Offer? mine;
              for (final of in snap.data ?? <Offer>[]) {
                if (of.executorId == myId) mine = of;
              }
              return _page(o, _offerState(o, mine));
            },
          );
        },
      ),
    );
  }

  /// Бүкіл бет: [state] — жоғарыдағы күй карточкасы мен төменгі әрекет
  /// (null болса — жүктелуде).
  Widget _page(Order o, _ScreenState? state) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: KeyedSubtree(
              key: ValueKey(state?.key ?? 'loading'),
              child:
                  state?.header ??
                  const SizedBox(
                    height: 120,
                    child: Center(child: CircularProgressIndicator()),
                  ),
            ),
          ),
          const SizedBox(height: 12),
          RouteMap(
            from: LatLng(o.fromLat, o.fromLng),
            to: LatLng(o.toLat, o.toLng),
            stops: o.stops.map((s) => LatLng(s.lat, s.lng)).toList(),
            height: 175,
            fromLabel: o.fromDisplay,
            toLabel: o.toDisplay,
            stopLabels: o.stops.map((s) => s.display).toList(),
            distanceKm: o.distanceKm,
          ),
          const SizedBox(height: 10),
          SectionCard(
            padding: const EdgeInsets.all(14),
            child: ExecRouteTimeline(order: o),
          ),
          const SizedBox(height: 10),
          _FactsGrid(order: o),
          if (ExecOrderNotes.hasContent(o)) ...[
            const SizedBox(height: 10),
            ExecOrderNotes(order: o),
          ],
          if (state?.action != null) ...[
            const SizedBox(height: 16),
            state!.action!,
          ],
        ],
      ),
    );
  }

  /// Заказ «іздеуде» емес: басқа орындаушы алды не заказ жабылды.
  _ScreenState _closedState(Order o, String? myId) {
    final taken = o.executorId != null && o.executorId != myId;
    final back = _BackToFeedButton(
      onPressed: () => Navigator.of(context).pop(),
    );
    if (taken) {
      return _ScreenState(
        key: 'taken',
        header: _StateBanner(
          color: Gz.amber,
          icon: Icons.person_off_rounded,
          title: t('Заказды басқа орындаушы алды'),
          text: t(
            'Клиент басқа орындаушының ұсынысын таңдады. '
            'Лентада сізге лайық басқа заказдар бар.',
          ),
        ),
        action: back,
      );
    }
    return _ScreenState(
      key: 'closed',
      header: _StateBanner(
        color: Gz.textSecondary,
        icon: Icons.block_rounded,
        title: t('Заказ енді қолжетімсіз'),
        // cancelled_by = тоқтатқан адамның id-і: клиенттің өзі болмаса
        // (мыс. модератор) — «Клиент тоқтатты» деп өтірік айтпаймыз.
        text: o.status == 'cancelled'
            ? t(
                o.cancelledBy == null || o.cancelledBy == o.clientId
                    ? 'Клиент заказды тоқтатты.'
                    : 'Заказ тоқтатылды',
              )
            : t('Бұл заказ жабылды не мерзімі өтті.'),
      ),
      action: back,
    );
  }

  /// Заказ «іздеуде»: менің ұсынысымның күйі.
  _ScreenState _offerState(Order o, Offer? mine) {
    // Әлі ұсыныс бермеген: бұл экран «Жаңа заказ» хабарландыруын басып
    // ашылғанда осы күйде келеді. Бұрын мұнда БОС орын (SizedBox.shrink)
    // қайтатын — заказ көрінетін, бірақ ештеңе істей алмайтын («тек
    // қарап тұрасың»). Енді лентадағыдай «Келісу / Өз бағам»
    // батырмалары көрсетіледі.
    if (mine == null) {
      return _ScreenState(
        key: 'new',
        header: _NewOrderHeader(order: o),
        action: _OfferActions(order: o),
      );
    }
    if (mine.status == 'rejected' || mine.status == 'withdrawn') {
      return _ScreenState(
        key: 'rejected',
        header: _StateBanner(
          color: Gz.red,
          icon: Icons.close_rounded,
          title: t('Ұсынысыңыз қабылданбады'),
          text: mine.status == 'withdrawn'
              ? t(
                  'Ұсыныс кері қайтарылды. '
                  'Лентадан басқа заказ алып көріңіз.',
                )
              : t(
                  'Клиент бұл ұсынысты таңдамады. '
                  'Лентадан басқа заказ алып көріңіз.',
                ),
        ),
        action: _BackToFeedButton(onPressed: () => Navigator.of(context).pop()),
      );
    }
    // pending
    final offer = mine;
    return _ScreenState(
      key: 'pending',
      header: _WaitingHeader(myPrice: offer.price, clientPrice: o.clientPrice),
      action: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: Gz.red,
          side: BorderSide(color: Gz.border),
        ),
        onPressed: () async {
          try {
            await Repo.withdrawOffer(offer.id);
            if (mounted) Navigator.of(context).pop();
          } catch (e) {
            if (mounted) showSnack(context, errText(e), error: true);
          }
        },
        icon: const Icon(Icons.undo, size: 18),
        label: Text(t('Ұсынысты қайтарып алу')),
      ),
    );
  }
}

/// Экран күйі: жоғарғы карточка + төменгі әрекет.
class _ScreenState {
  final String key;
  final Widget header;
  final Widget? action;
  const _ScreenState({required this.key, required this.header, this.action});
}

class _BackToFeedButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _BackToFeedButton({required this.onPressed});

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onPressed,
    icon: const Icon(Icons.arrow_back_rounded, size: 18),
    label: Text(t('Лентаға оралу')),
  );
}

// ═══════════════════════════════════════════════════════════════════════
//  КҮЙ КАРТОЧКАЛАРЫ
// ═══════════════════════════════════════════════════════════════════════

/// Әлі ұсыныс берілмеген заказ: клиент бағасы — басты сан.
class _NewOrderHeader extends StatelessWidget {
  final Order order;
  const _NewOrderHeader({required this.order});

  @override
  Widget build(BuildContext context) {
    final price = order.clientPrice;
    return _HeroBox(
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Gz.yellow.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.local_offer_rounded,
              color: Gz.yellow,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t('Клиент бағасы'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _HeroBox.caption,
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    price == null ? t('Баға ұсынылмаған') : fmtT(price),
                    maxLines: 1,
                    style: TextStyle(
                      color: Gz.yellow,
                      fontSize: price == null ? 20 : 28,
                      height: 1.15,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  price == null
                      ? t(
                          'Өз бағаңызды ұсыныңыз — клиент ең ыңғайлысын '
                          'таңдайды.',
                        )
                      : t(
                          'Келісіңіз немесе өз бағаңызды ұсыныңыз — клиент '
                          'ең ыңғайлысын таңдайды.',
                        ),
                  style: _HeroBox.body,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Ұсыныс жіберілді, клиент таңдап жатыр: тыныстайтын құм сағат,
/// түсініктеме және «менің бағам ↔ клиент бағасы» салыстыруы.
///
/// Бір AnimationController: толқын сақиналары мен құм сағаттың аударылуы
/// сол бір мәннен есептеледі; тек иконка бөлігі қайта салынады.
class _WaitingHeader extends StatefulWidget {
  final int myPrice;
  final int? clientPrice;
  const _WaitingHeader({required this.myPrice, required this.clientPrice});

  @override
  State<_WaitingHeader> createState() => _WaitingHeaderState();
}

class _WaitingHeaderState extends State<_WaitingHeader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // «Анимацияны азайту» қосулы болса — тыныш күйде қалады.
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final client = widget.clientPrice;
    final diff = client == null ? 0 : widget.myPrice - client;
    return _HeroBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              RepaintBoundary(
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: AnimatedBuilder(
                    animation: _c,
                    builder: (context, child) {
                      final v = _c.value;
                      // Құм сағат циклдің соңғы ширегінде 180° аударылады.
                      final flip = v < 0.75
                          ? 0.0
                          : Curves.easeInOut.transform((v - 0.75) / 0.25);
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          for (final shift in const [0.0, 0.5])
                            _ring((v + shift) % 1.0),
                          Transform.rotate(
                            angle: flip * 3.14159265,
                            child: child,
                          ),
                        ],
                      );
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        color: Gz.yellow,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.hourglass_top_rounded,
                        color: Gz.onBrand,
                        size: 22,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t('Ұсынысыңыз жіберілді'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        height: 1.25,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      t(
                        'Клиент ұсыныстарды салыстырып, орындаушы таңдап '
                        'жатыр. Сізді таңдаса, заказ өзі ашылады.',
                      ),
                      style: _HeroBox.body,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _PriceTile(
                    label: t('Сіздің бағаңыз'),
                    price: widget.myPrice,
                    accent: true,
                    badge: diff == 0
                        ? null
                        : '${diff > 0 ? '+' : '−'}${fmtT(diff.abs())}',
                  ),
                ),
                if (client != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: _PriceTile(label: t('Клиент бағасы'), price: client),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Ортадан тарап, сөніп бара жатқан сақина ([v] 0→1).
  Widget _ring(double v) {
    final size = 40 + 16 * v;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Gz.yellow.withValues(alpha: 0.55 * (1 - v)),
          width: 2,
        ),
      ),
    );
  }
}

/// Баға плиткасы (күту карточкасының ішінде).
class _PriceTile extends StatelessWidget {
  final String label;
  final int price;
  final bool accent;
  final String? badge;
  const _PriceTile({
    required this.label,
    required this.price,
    this.accent = false,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
      decoration: BoxDecoration(
        color: accent
            ? Gz.yellow.withValues(alpha: 0.13)
            : Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(Gz.rMd),
        border: Border.all(
          color: accent
              ? Gz.yellow.withValues(alpha: 0.4)
              : Colors.white.withValues(alpha: 0.12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _HeroBox.caption,
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              fmtT(price),
              maxLines: 1,
              style: TextStyle(
                color: accent ? Gz.yellow : Colors.white,
                fontSize: 20,
                height: 1.2,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.3,
              ),
            ),
          ),
          if (badge != null) ...[
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                '$badge ${t('клиент бағасынан')}',
                maxLines: 1,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Қою градиентті күй карточкасы (жаңа заказ / күту).
class _HeroBox extends StatelessWidget {
  final Widget child;
  const _HeroBox({required this.child});

  static final caption = TextStyle(
    color: Colors.white.withValues(alpha: 0.62),
    fontSize: 12,
    fontWeight: FontWeight.w600,
  );
  static final body = TextStyle(
    color: Colors.white.withValues(alpha: 0.78),
    fontSize: 13,
    height: 1.4,
  );

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: Gz.heroGradient,
      borderRadius: BorderRadius.circular(Gz.radius),
      boxShadow: Gz.cardShadow,
    ),
    child: child,
  );
}

/// Аяқталған күй (қабылданбады / басқаға кетті / жабылды): түсті белгі +
/// тақырып + бір сөйлем түсініктеме.
class _StateBanner extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String title;
  final String text;
  const _StateBanner({
    required this.color,
    required this.icon,
    required this.title,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Gz.surface,
        borderRadius: BorderRadius.circular(Gz.radius),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1.4),
        boxShadow: Gz.cardShadow,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Gz.tint(color, 0.13),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.25,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: Gz.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  ЗАКАЗ ДЕРЕКТЕРІ (2 БАҒАНДЫ ТОР)
// ═══════════════════════════════════════════════════════════════════════

/// Көлік түрі, қашықтық, қала/қалааралық, жарияланған және орындалу
/// уақыты — 2 бағанды плиткалар. Баға мұнда ЖОҚ (жоғарғы карточкада тұр).
class _FactsGrid extends StatelessWidget {
  final Order order;
  const _FactsGrid({required this.order});

  /// «Бүгін 14:05» / «Ертең 09:30» / «12.10.2026 14:05».
  static String _when(DateTime d) {
    final l = d.toLocal();
    final now = DateTime.now();
    final day = DateTime(l.year, l.month, l.day);
    final today = DateTime(now.year, now.month, now.day);
    final delta = day.difference(today).inDays;
    if (delta == 0) return '${t('Бүгін')} ${fmtTime(l)}';
    if (delta == 1) return '${t('Ертең')} ${fmtTime(l)}';
    return fmtDate(l);
  }

  @override
  Widget build(BuildContext context) {
    final o = order;
    final taxi = o.vehicleType == VehicleType.taxi;
    final facts = <_Fact>[
      _Fact(
        taxi ? Icons.local_taxi_rounded : Icons.local_shipping_rounded,
        t('Көлік'),
        o.vehicleType.label,
        Gz.yellowDeep,
      ),
      if (o.distanceKm > 0)
        _Fact(
          Icons.straighten_rounded,
          t('Қашықтық'),
          '${o.distanceKm.toStringAsFixed(1)} км',
          Gz.blue,
        ),
      _Fact(
        o.intercity ? Icons.alt_route_rounded : Icons.location_city_rounded,
        t('Бағыт'),
        o.intercity ? t('Қалааралық') : t('Қала ішінде'),
        o.intercity ? Gz.night : Gz.green,
      ),
      // Алдын ала тапсырыс — уақыты күлгінмен ерекшеленеді.
      _Fact(
        o.scheduledAt != null ? Icons.event_rounded : Icons.bolt_rounded,
        t('Орындау уақыты'),
        o.scheduledAt != null ? _when(o.scheduledAt!) : t('Дәл қазір'),
        o.scheduledAt != null ? Gz.violet : Gz.amber,
        highlight: o.isScheduledPending,
      ),
      if (o.createdAt != null)
        _Fact(
          Icons.schedule_rounded,
          t('Жарияланды'),
          _when(o.createdAt!),
          Gz.textSecondary,
        ),
    ];
    final rows = <Widget>[];
    for (var i = 0; i < facts.length; i += 2) {
      final pair = facts.skip(i).take(2).toList();
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 8));
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _FactTile(fact: pair[0])),
              const SizedBox(width: 8),
              Expanded(
                child: pair.length > 1
                    ? _FactTile(fact: pair[1])
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}

class _Fact {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final bool highlight;
  const _Fact(
    this.icon,
    this.label,
    this.value,
    this.color, {
    this.highlight = false,
  });
}

class _FactTile extends StatelessWidget {
  final _Fact fact;
  const _FactTile({required this.fact});

  @override
  Widget build(BuildContext context) {
    final f = fact;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
      decoration: BoxDecoration(
        color: f.highlight ? Gz.tint(f.color, 0.08) : Gz.surface,
        borderRadius: BorderRadius.circular(Gz.rMd),
        border: Border.all(
          color: f.highlight ? f.color.withValues(alpha: 0.4) : Gz.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(f.icon, size: 16, color: f.color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  f.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Gz.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            f.value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              height: 1.25,
              fontWeight: FontWeight.w800,
              color: f.highlight ? f.color : Gz.ink,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  ҰСЫНЫС БЕРУ
// ═══════════════════════════════════════════════════════════════════════

/// «Келісу» / «Өз бағам» — әлі ұсыныс берілмеген заказ үшін.
///
/// Ұсыныс беру құқығын (тариф, растау, қала) СЕРВЕР `place_offer` ішінде
/// тексереді — рұқсат болмаса, қатенің себебі snack арқылы көрсетіледі.
class _OfferActions extends StatelessWidget {
  final Order order;
  const _OfferActions({required this.order});

  /// Баға + келу уақыты + хабар — лентадағыдай бір терезеде
  /// (offer_sheet.dart: ETA таңдау + дайын фразалар).
  Future<void> _offer(BuildContext context, {required bool counter}) async {
    final pos = await Geo.currentPosition();
    if (!context.mounted) return;
    final km = pos == null
        ? null
        : Geo.haversineKm(
            LatLng(pos.latitude, pos.longitude),
            LatLng(order.fromLat, order.fromLng),
          );
    final d = await showOfferSheet(
      context,
      order: order,
      counter: counter,
      kmToPickup: km,
    );
    if (d == null || !context.mounted) return;
    try {
      await Repo.placeOffer(order.id, d.price, d.message, etaMin: d.etaMin);
      Repo.offersStream(order.id, fresh: true);
    } catch (e) {
      if (context.mounted) showSnack(context, errText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final base = order.clientPrice;
    return Row(
      children: [
        if (base != null) ...[
          Expanded(
            flex: 3,
            child: BusyButton(
              // Баға жоғарғы карточкада үлкен жазылған — батырмада
              // қайталанбайды.
              label: t('Келісу'),
              onPressed: () => _offer(context, counter: false),
            ),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          flex: 2,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              side: BorderSide(color: Gz.ink, width: 1.6),
            ),
            onPressed: () => _offer(context, counter: true),
            child: BtnLabel(t('Өз бағам')),
          ),
        ),
      ],
    );
  }
}
