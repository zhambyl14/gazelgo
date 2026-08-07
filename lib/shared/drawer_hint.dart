import 'package:flutter/material.dart';

import '../core/lang.dart';
import '../core/prefs.dart';
import '../core/theme.dart';

/// Бүйір панельді (sidebar) ТАБУҒА көмектесетін екі элемент (0059).
///
/// Мәселе: панельде ең қажет бөлімдер тұр (профиль, тапсырыстар, баланс,
/// хабарландырулар), бірақ оны сол жақ шеттен тартып ашуға болатынын
/// қолданушылар білмей қалатын — логотипті түйме деп те ойламайтын.
///
/// Шешім екі қабатты:
///   1. [DrawerEdgeHandle] — сол шетте ТҰРАҚТЫ тұратын жіңішке «тұтқа».
///      Байқаусыз, бірақ көзге түседі; түртсе де панель ашылады.
///   2. [DrawerHintOverlay] — алғашқы бірнеше ашылуда шығатын қысқа
///      қалқыма нұсқау («осы жерден оңға тартыңыз»). [Prefs.kDrawerHintTimes]
///      реттен кейін мәңгіге жоғалады.

/// Сол шеттегі тұрақты «тұтқа» — панельдің бар екенін көрсететін белгі.
/// Түртсе де, оңға тартса да панель ашылады.
///
/// МАҢЫЗДЫ (клиенттің басты беті): ол жерде бүкіл экранды карта алып тұр,
/// сол себепті Scaffold-тың өз `drawerEnableOpenDragGesture` мүмкіндігі
/// ӘДЕЙІ өшірулі — әйтпесе картаны солға жылжытқан сайын панель ашылып
/// кетер еді. Осы тұтқа сол шектеуді бұзбай шешеді: тарту тек ОСЫ шағын
/// аймақта (18×74) жұмыс істейді, картаның қалған бөлігі баяғыдай.
class DrawerEdgeHandle extends StatelessWidget {
  const DrawerEdgeHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Scaffold.of(context).openDrawer(),
        onHorizontalDragEnd: (d) {
          // Оңға қарай тартылса ғана — солға тартқан адам панельді
          // жапқысы келген (не кездейсоқ тиген) болуы мүмкін.
          if (d.velocity.pixelsPerSecond.dx > 0) {
            Scaffold.of(context).openDrawer();
          }
        },
        child: Container(
          width: 18,
          height: 74,
          alignment: Alignment.centerLeft,
          child: Container(
            width: 5,
            height: 54,
            decoration: BoxDecoration(
              color: Gz.ink.withValues(alpha: 0.22),
              borderRadius: const BorderRadius.horizontal(
                right: Radius.circular(5),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Алғашқы ашылуларда шығатын қалқыма нұсқау. Көрсетілуін өзі санайды,
/// сол себепті экрандар ешнәрсе басқармайды — тек ағашқа қосады.
class DrawerHintOverlay extends StatefulWidget {
  /// Нұсқау қалқымасының ЖОҒАРЫДАН қашықтығы. Клиенттің басты бетінде
  /// логотип картаның үстінде тұр, орындаушыда — жолақта; екеуінде де
  /// нұсқау логотиптің дәл астынан шығуы керек.
  final double top;

  const DrawerHintOverlay({super.key, this.top = 72});

  @override
  State<DrawerHintOverlay> createState() => _DrawerHintOverlayState();
}

class _DrawerHintOverlayState extends State<DrawerHintOverlay>
    with SingleTickerProviderStateMixin {
  bool _show = false;
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    _maybeShow();
  }

  Future<void> _maybeShow() async {
    final seen = await Prefs.drawerHintSeen();
    if (!mounted || seen >= Prefs.kDrawerHintTimes) return;
    await Prefs.bumpDrawerHint();
    if (!mounted) return;
    setState(() => _show = true);
    _c.repeat();
    // Өзі жабылады — қолданушыны бөгемейді.
    await Future.delayed(const Duration(seconds: 7));
    if (mounted) _hide();
  }

  Future<void> _dismiss() async {
    await Prefs.dismissDrawerHint();
    if (mounted) _hide();
  }

  /// Жасырғанда анимацияны да ТОҚТАТАМЫЗ — әйтпесе көрінбейтін виджет
  /// экранды әр кадр сайын қайта саптырып, батареяны тегін жеп отырар еді.
  void _hide() {
    _c.stop();
    setState(() => _show = false);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !_show,
      child: AnimatedOpacity(
        opacity: _show ? 1 : 0,
        duration: const Duration(milliseconds: 350),
        child: Stack(
          children: [
            // Сол шеттен оңға «тартылып» тұратын саусақ белгісі.
            Align(
              alignment: Alignment.centerLeft,
              child: AnimatedBuilder(
                animation: _c,
                builder: (_, _) {
                  final v = Curves.easeInOut.transform(
                    (_c.value * 2 <= 1) ? _c.value * 2 : 2 - _c.value * 2,
                  );
                  return Padding(
                    padding: EdgeInsets.only(left: 2 + v * 26),
                    child: Opacity(
                      opacity: 0.35 + v * 0.65,
                      child: Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: Gz.ink,
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: Gz.cardShadow,
                        ),
                        child: const Icon(
                          Icons.chevron_right_rounded,
                          color: Gz.yellow,
                          size: 24,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            // Түсіндірме көпіршігі — логотиптің астында.
            Positioned(
              left: 12,
              right: 12,
              top: widget.top,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: _dismiss,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(13, 11, 11, 12),
                    decoration: BoxDecoration(
                      color: Gz.ink,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: Gz.cardShadow,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.swipe_right_alt_rounded,
                          color: Gz.yellow,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t('Мұнда мәзір бар'),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13.5,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                t('Логотипті басыңыз немесе сол шеттегі '
                                    'тұтқадан оңға тартыңыз — профиль, '
                                    'тапсырыстар, баланс, хабарландырулар '
                                    'сонда.'),
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.82),
                                  fontSize: 11.5,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.close, color: Colors.white54, size: 18),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Логотип-түйме: панельді ашады. Бұрын жай сурет еді — енді сыртында
/// шағын «мәзір» белгісі тұр, сол себепті түйме екені бірден көрінеді.
///
/// МАҢЫЗДЫ: белгі логотиптің ІШІНДЕ емес, СЫРТЫНДА тұрады (Stack-тың
/// `clipBehavior: Clip.none`-мен шетінен асып). Бұрын Material-дың өзі
/// клиптейтін еді — сол кезде белгі логотиптің оң-төменгі бұрышында тұрған
/// «Tasu» жазуының «u» әрпін ЖАУЫП тұратын. Енді сурет таза қалады.
class LogoMenuButton extends StatelessWidget {
  final VoidCallback onTap;

  /// Логотиптің қабырғасы. Бұрын 46 еді — көзге түсу үшін ұлғайтылды.
  final double size;

  const LogoMenuButton({super.key, required this.onTap, this.size = 56});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          elevation: 3,
          borderRadius: BorderRadius.circular(size * 0.3),
          clipBehavior: Clip.antiAlias,
          color: Gz.surface,
          shadowColor: Colors.black26,
          child: InkWell(
            onTap: onTap,
            child: Image.asset(
              'assets/icon/icon.png',
              width: size,
              height: size,
              fit: BoxFit.cover,
            ),
          ),
        ),
        // «Мәзір» белгісі — логотиптің сыртында, оң-төменгі бұрышында
        // қалқып тұрады (аватардағы «онлайн» нүктесі сияқты).
        Positioned(
          right: -5,
          bottom: -5,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Gz.ink,
                shape: BoxShape.circle,
                border: Border.all(color: Gz.surface, width: 2),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 3,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              child: const Icon(
                Icons.menu_rounded,
                size: 12,
                color: Gz.yellow,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
