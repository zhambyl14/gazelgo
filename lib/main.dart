import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show DeviceOrientation, SystemChrome;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/env.dart';
import 'core/lang.dart';
import 'core/models.dart';
import 'core/notify.dart';
import 'core/push.dart';
import 'core/repo.dart';
import 'core/theme.dart';
import 'features/auth/blocked_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/pending_screen.dart';
import 'features/client/client_shell.dart';
import 'features/client/order_detail_screen.dart';
import 'features/client/track_screen.dart';
import 'features/executor/balance_screen.dart';
import 'features/executor/executor_order_screen.dart';
import 'features/executor/executor_shell.dart';
// Модератор панелі (~10 мың жол + `image` пакеті) — КЕЙІНГЕ ҚАЛДЫРЫЛЫП
// жүктеледі: вебте клиент/орындаушы оны мүлдем жүктемейді (main.dart.js
// кішірейеді → ашылу жылдамырақ). Мобильде loadLibrary() бірден аяқталады.
import 'features/moderator/moderator_shell.dart' deferred as moderator;
import 'features/support/support_screen.dart';
import 'shared/portrait_frame.dart';
import 'shared/update_gate.dart';
import 'shared/web_push_banner.dart';
import 'shared/widgets.dart';

/// Push/локал уведомлениелерден навигация үшін — түбір Navigator кілті.
final navigatorKey = GlobalKey<NavigatorState>();

/// «Сапарды бөлісу» (0060) — тек ВЕБТЕ: URL `/track/<token>` болса, токенді
/// қайтарады. Мобиль қосымшада `Uri.base` мағынасыз (файл жолы), сол
/// себепті `kIsWeb` шартымен қорғалған. AuthGate/ClientShell МҮЛДЕМ
/// айналып өтіледі — сілтемені ашқан адамда аккаунт болуы шарт емес.
String? _shareTrackToken() {
  if (!kIsWeb) return null;
  final segments = Uri.base.pathSegments;
  if (segments.length >= 2 && segments[segments.length - 2] == 'track') {
    final token = segments.last.trim();
    return token.isEmpty ? null : token;
  }
  return null;
}

/// Қосымшаның бастапқы беті: Supabase бапталмаса — қате хабары; веб-те
/// `/track/<token>` сілтемесі болса — TrackScreen (аутентификациясыз);
/// қалғаны — кәдімгі AuthGate.
Widget _appHome() {
  if (!Env.isConfigured) return const _NotConfigured();
  final token = _shareTrackToken();
  if (token != null) return TrackScreen(token: token);
  return const UpdateGate(child: AuthGate());
}

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
void _navigateFromData(Map<String, dynamic> data) {
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
  } else if (type == 'support_reply') {
    screen = const SupportScreen();
  } else if (type == 'support_message') {
    _openModeratorTab(() => moderator.ModeratorShell.tabSupport);
    return;
  } else if (type == 'new_application') {
    _openModeratorTab(() => moderator.ModeratorShell.tabApplications);
    return;
  } else if (type == 'new_topup') {
    _openModeratorTab(() => moderator.ModeratorShell.tabTopups);
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

/// Модератор кітапханасын бір рет жүктеу (кейінге қалдырылған импорт).
final Future<void> _moderatorLib = moderator.loadLibrary();

/// Модератор панелінің қойындысын ашу — кітапхана жүктелгеннен КЕЙІН
/// (кейінге қалдырылған кітапхананың мүшесіне ерте қатынау қате береді,
/// сол себепті индекс closure арқылы кейін оқылады).
void _openModeratorTab(int Function() tab) {
  _moderatorLib.then((_) => moderator.ModeratorShell.openTab(tab()));
}

/// Модератор панелі — кітапхана жүктелгенше splash.
class _ModeratorLoader extends StatelessWidget {
  const _ModeratorLoader();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _moderatorLib,
      builder: (context, snap) =>
          snap.connectionState == ConnectionState.done && !snap.hasError
          ? moderator.ModeratorShell()
          : const _Splash(),
    );
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Қосымша ТЕК ТІК (портрет) режимде жұмыс істейді: бүкіл интерфейс — карта,
  // төменгі панельдер, хабарландыру карточкалары — тік телефонға есептелген,
  // көлденең бұрылғанда олар созылып бұзылатын. Android/iOS-та бұл жүйе
  // деңгейінде де бекітілген (AndroidManifest `screenOrientation="portrait"`,
  // Info.plist тек `Portrait`), мұндағы шақыру — қосымша ішінде де
  // өзгермейтініне кепілдік. Вебте бұрылысты бұғаттау мүмкін емес, сол
  // жағдайды [PortraitFrame] шешеді.
  unawaited(
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
  );
  // Flutter әдепкі бойынша 1000 сурет / 100 МБ дейін кэштейді — мобильді
  // қосымша үшін тым үлкен. Жадыны үнемдеу үшін шектейміз.
  PaintingBinding.instance.imageCache.maximumSize = 150;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 30 << 20; // 30 МБ
  if (Env.isConfigured) {
    await Supabase.initialize(
      url: Env.supabaseUrl,
      // ignore: deprecated_member_use
      anonKey: Env.supabaseAnonKey,
    );
  }
  await Notify.init();
  await Lang.init();
  // Көлік түрлерінің каталогы (0050): алдымен ҚҰРЫЛҒЫДАҒЫ кэштен —
  // жылдам әрі желісіз де жұмыс істейді, сол себепті бірінші кадрда
  // тізім дұрыс. Серверден жаңарту фонда жүреді: жауап келгенде
  // `VehicleCatalog.revision` артып, карусельдер өздері қайта салынады
  // (қосымшаның ашылуын күттірмейміз).
  await VehicleCatalog.restoreCache();
  if (Env.isConfigured) {
    unawaited(VehicleCatalog.load(Repo.vehicleCatalog));
  }
  // Хабарламаны басқанда навигация: FCM тап (Push.onOpen) және Android
  // foreground локал уведомлениесінің тап-payload-ы (Notify.onSelect) —
  // екеуі де бір навигация логикасына бағытталады.
  Push.onOpen = _navigateFromData;
  Notify.onSelect = (payload) {
    if (payload == null || payload.isEmpty) return;
    try {
      _navigateFromData(jsonDecode(payload) as Map<String, dynamic>);
    } catch (_) {}
  };
  runApp(const ProviderScope(child: GazelGoApp()));
}

class GazelGoApp extends StatelessWidget {
  const GazelGoApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Тіл ауысқанда бүкіл ағаш қайта салынуы үшін — `t()` жаппай
    // қолданылатын const емес қарапайым функция, оны ешбір widget
    // "тыңдамайды". Сондықтан тіл өзгергенде `key: ValueKey(lang)` арқылы
    // бүкіл MaterialApp-ты (Navigator стегімен қоса) жаңадан құрып, барлық
    // экрандағы `t()` мәтіндері сол мезетте жаңа тілде салынады. Riverpod
    // ProviderScope MaterialApp-тан жоғарыда тұрғандықтан, auth/профиль
    // күйі кэштелген күйінде қалады — қайта кіру не splash жыпылықтауы жоқ.
    return ValueListenableBuilder<AppLang>(
      valueListenable: Lang.current,
      builder: (context, lang, _) => MaterialApp(
        key: ValueKey(lang),
        navigatorKey: navigatorKey,
        title: 'Tasu',
        debugShowCheckedModeBanner: false,
        theme: Gz.theme(),
        // Жүйелік Material/Cupertino элементтерін (артқа тултипі, мәтін
        // таңдау мәзірі, күнтізбе, семантика) таңдалған тілде көрсету.
        locale: Locale(lang == AppLang.ru ? 'ru' : 'kk'),
        supportedLocales: const [Locale('kk'), Locale('ru')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        // Жүйелік қаріп өлшемін шектейміз: кейбір Android-та қаріпті қатты
        // үлкейтсе, бүкіл интерфейс (әсіресе картадағы төменгі панель) шектен
        // тыс үлкейіп, карта көрінбей қалатын. 1.0–1.25 аралығына қысамыз —
        // оқылымдылық сақталады, бірақ орналасу бұзылмайды.
        builder: (context, child) {
          final mq = MediaQuery.of(context);
          return MediaQuery(
            data: mq.copyWith(
              textScaler: mq.textScaler.clamp(
                minScaleFactor: 1.0,
                maxScaleFactor: 1.25,
              ),
            ),
            // Тік (9:16) формат: телефонда — өзгеріссіз, кең терезеде
            // (веб/ноутбук/планшет) қосымша сол пропорцияда ортада салынады.
            child: PortraitFrame(child: WebPushBanner(child: child!)),
          );
        },
        home: _appHome(),
      ),
    );
  }
}

class _NotConfigured extends StatelessWidget {
  const _NotConfigured();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GazelGoLogo(size: 32),
              SizedBox(height: 24),
              Text(
                'Backend бапталмаған',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 12),
              Text(
                'lib/core/env.dart ішіне Supabase ANON KEY қойыңыз '
                'және supabase/APPLY.md нұсқаулығын орындаңыз.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Gz.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// [AuthGate] қай пайдаланушы үшін бір реттік баптауды жасап қойды.
String? _bootstrappedUid;

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);

    return auth.when(
      loading: () => const _Splash(),
      error: (e, st) => const LoginScreen(),
      data: (state) {
        final session = Supabase.instance.client.auth.currentSession;
        // Кірмеген қолданушы (жаңа орнатқан не аккаунттан шыққан) — гест режимі:
        // клиенттің басты беті ашылады, заказды толық толтыра алады. Аккаунт тек
        // «Шақыру» басылғанда немесе профильге кіргенде сұралады.
        if (session == null) return const ClientShell(guest: true);
        // Пайдаланушыға БІР РЕТ (аккаунт ауысса — қайтадан):
        //  * push-токенді АҒЫМДАҒЫ пайдаланушыға тіркеу (бір телефонда
        //    аккаунт ауысса, ескі иесінің push-ы жаңа иесіне келмеуі үшін);
        //  * push тілін серверге жеткізу;
        //  * орындаушы профилін профильмен ҚАТАР жүктей бастау (бұрын
        //    профиль келгеннен кейін ғана сұралатын — ашылуға тағы бір
        //    желі айналымы қосылатын).
        // Бұрын бұлар AuthGate-тің ӘР build-інде (әр токен жаңаруында)
        // қайталанатын — артық желі сұраулары.
        final uid = session.user.id;
        if (_bootstrappedUid != uid) {
          _bootstrappedUid = uid;
          unawaited(Push.init());
          unawaited(Lang.syncToServer());
          ref.read(myExecutorProfileProvider);
        }
        return const _RoleRouter();
      },
    );
  }
}

class _RoleRouter extends ConsumerWidget {
  const _RoleRouter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(myProfileProvider);

    // Қайта жүктеу кезінде (invalidate, аккаунт деректері жаңарғанда)
    // бұрынғы мән КӨРСЕТІЛЕ береді — бүкіл қосымша splash-қа ауыспайды.
    return profile.when(
      skipLoadingOnReload: true,
      loading: () => const _Splash(),
      error: (e, st) =>
          _RetryScreen(onRetry: () => ref.invalidate(myProfileProvider)),
      data: (p) {
        if (p == null) {
          return _RetryScreen(onRetry: () => ref.invalidate(myProfileProvider));
        }
        // Сенім деңгейі бойынша бұғатталған аккаунт (0024) — модератордан
        // басқа ешкім қосымшаға мүлдем кіре алмайды.
        if (p.isBlocked && p.role != 'moderator') {
          return BlockedScreen(profile: p);
        }
        switch (p.role) {
          case 'moderator':
            return const _ModeratorLoader();
          case 'executor':
            return const _ExecutorRouter();
          default:
            return const ClientShell();
        }
      },
    );
  }
}

class _ExecutorRouter extends ConsumerWidget {
  const _ExecutorRouter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ep = ref.watch(myExecutorProfileProvider);

    return ep.when(
      skipLoadingOnReload: true,
      loading: () => const _Splash(),
      error: (e, st) => _RetryScreen(
        onRetry: () => ref.invalidate(myExecutorProfileProvider),
      ),
      data: (e) {
        // Модератор БҰҒАТТАҒАН аккаунт — қосымшаға кіре алмайды.
        if (e != null && e.status == 'blocked') {
          return PendingScreen(profile: e);
        }
        // ӘЛІ ӨТІНІМ ТОЛТЫРМАҒАН (профиль жоқ) да ExecutorShell-ге кіреді.
        // Бұрын мұндай адам бірден ExecutorApplyScreen-ге тірелетін де,
        // құжаттарын жинамайынша қосымшада не бар екенін МҮЛДЕМ көрмейтін.
        // Бұл теріс: жүйеде өзіне лайық заказ бар-жоғын білмей тұрып құжат
        // толтыруға мәжбүрлеу. Енді лента бірден ашық (сервер 0063 «танысу
        // режимінде» бәрін көрсетеді), ал өтінім — экранның үстіндегі
        // шақыру картасы мен заказды басқандағы гейт арқылы ұсынылады.
        // Қалғаны (pending/rejected/approved) — кәдімгі орындаушыдай кіреді:
        // заказдар лентасы мен профильге қолжетімді. Расталмаған/қабылданбаған
        // болса — лентада «тексеруде / қайта толтыру» деп ескертіледі әрі
        // ұсыныс беру бөгеледі (feed_screen ішіндегі гейт + сервер).
        return const ExecutorShell();
      },
    );
  }
}

/// Көлік түрі иконкалары (assets/vehicles/*.png) бума ішінде бумаланған
/// болса да, Flutter оларды бірінші РЕТ виджетте көрінгенде ғана оқып
/// декодтайды — сол сәтте бір кадр бос орын/жыпылықтау көрінуі мүмкін
/// (мыс. көлік каруселінде тез айналдырғанда). Splash экраны — авторизация
/// жүктеліп жатқан кез келген уақытта көрінетін ЖАЛҒЫЗ орын, сол себепті
/// осында алдын ала precacheImage жасаймыз: пайдаланушы каруседьге жеткенде
/// иконкалар қолданбаның жад-кэшінде дайын тұрады.
bool _vehicleIconsPrecached = false;

class _Splash extends StatefulWidget {
  const _Splash();

  @override
  State<_Splash> createState() => _SplashState();
}

/// Ашылу анимациясы. Native splash (ақ фон + ортадағы логотип-пин, биіктігі
/// ~100dp) БІТКЕН ЖЕРДЕН жалғасады: логотип дәл сол орында, сол өлшемде
/// тұрады, сондықтан ауысу «секірмейді». Содан кейін пин бір рет секіріп
/// жерге «қонады», қонған жерінен сары толқындар таралады, астынан «Tasu»
/// жазуы мен слоган біртіндеп шығады.
///
/// Жүктеу кезеңдері (сессия → профиль → рөл) әрқайсысы `_Splash`-ты ЖАҢА
/// данамен қайта салуы мүмкін — анимация басынан қайта ойнамауы үшін
/// басталу уақыты статикалық [_t0]-да сақталады.
class _SplashState extends State<_Splash> with TickerProviderStateMixin {
  static DateTime? _t0;
  static const _introMs = 1100;

  late final AnimationController _intro;
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  @override
  void initState() {
    super.initState();
    _t0 ??= DateTime.now();
    final done = DateTime.now().difference(_t0!).inMilliseconds / _introMs;
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: _introMs),
      value: done.clamp(0.0, 1.0),
    )..forward();
  }

  @override
  void dispose() {
    _intro.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_vehicleIconsPrecached) {
      _vehicleIconsPrecached = true;
      for (final v in VehicleType.values) {
        final png = v.pngAsset;
        if (png != null) unawaited(precacheImage(AssetImage(png), context));
      }
    }
  }

  /// Пиннің секіруі: 0..0.25 — орнында, 0.25..0.5 — жоғары, 0.5..0.68 —
  /// төмен түсіп қонады (сәл «жаншылып»), содан кейін тыныш тұрады.
  static double _hop(double t) {
    if (t < 0.25 || t > 0.68) return 0;
    if (t < 0.5) return Curves.easeOut.transform((t - 0.25) / 0.25);
    return 1 - Curves.easeIn.transform((t - 0.5) / 0.18);
  }

  static double _squash(double t) {
    if (t < 0.68 || t > 0.82) return 0;
    final k = (t - 0.68) / 0.14;
    return k < 0.5 ? k * 2 : (1 - k) * 2;
  }

  static double _fade(double t, double from, double to) =>
      Curves.easeOutCubic.transform(((t - from) / (to - from)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    const logoH = 100.0;
    const logoW = logoH * 826 / 1013;
    final logo = Image.asset(
      'assets/icon/tasu_logo.png',
      height: logoH,
      width: logoW,
      filterQuality: FilterQuality.medium,
    );
    return Scaffold(
      backgroundColor: Gz.surface,
      body: RepaintBoundary(
        child: AnimatedBuilder(
          animation: Listenable.merge([_intro, _pulse]),
          builder: (context, _) {
            final p = _intro.value;
            final hop = _hop(p);
            final squash = _squash(p);
            // Толқындар тек пин қонғаннан кейін басталады.
            final pulseOn = _fade(p, 0.66, 0.8);
            return Stack(
              alignment: Alignment.center,
              children: [
                // Пиннің ұшы тұрған «жер» (экран ортасынан logoH/2 төмен).
                Transform.translate(
                  offset: const Offset(0, logoH / 2),
                  child: SizedBox(
                    width: 180,
                    height: 60,
                    child: CustomPaint(
                      painter: _GroundPainter(
                        pulse: _pulse.value,
                        pulseOpacity: pulseOn,
                        shadow: 1 - hop * 0.6,
                      ),
                    ),
                  ),
                ),
                Transform.translate(
                  offset: Offset(0, -26 * hop),
                  child: Transform(
                    alignment: Alignment.bottomCenter,
                    transform: Matrix4.diagonal3Values(
                      1 + 0.05 * squash,
                      1 - 0.07 * squash,
                      1,
                    ),
                    child: logo,
                  ),
                ),
                Transform.translate(
                  offset: Offset(
                    0,
                    logoH / 2 + 62 + 10 * (1 - _fade(p, 0.55, 0.9)),
                  ),
                  child: Opacity(
                    opacity: _fade(p, 0.55, 0.9),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Tasu',
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                            color: Gz.ink,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Opacity(
                          opacity: _fade(p, 0.7, 1),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Text(
                              t('Жүк тасымалы және арнайы техника платформасы'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Gz.textSecondary,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Пиннің астындағы «жер»: жұмсақ көлеңке-эллипс және одан таралатын
/// екі сары толқын (бірі екіншісінен жарты кезеңге кешігеді).
class _GroundPainter extends CustomPainter {
  final double pulse;
  final double pulseOpacity;
  final double shadow;
  _GroundPainter({
    required this.pulse,
    required this.pulseOpacity,
    required this.shadow,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    if (pulseOpacity > 0) {
      for (final phase in [pulse, (pulse + 0.5) % 1]) {
        final k = Curves.easeOut.transform(phase);
        final w = 18 + 150 * k;
        canvas.drawOval(
          Rect.fromCenter(center: c, width: w, height: w * 0.32),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2
            ..color = Gz.yellowDark.withValues(
              alpha: 0.55 * (1 - k) * pulseOpacity,
            ),
        );
      }
    }
    canvas.drawOval(
      Rect.fromCenter(center: c, width: 26 * shadow, height: 8 * shadow),
      Paint()
        ..color = Gz.ink.withValues(alpha: 0.18 * shadow)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
    );
  }

  @override
  bool shouldRepaint(_GroundPainter old) =>
      old.pulse != pulse ||
      old.pulseOpacity != pulseOpacity ||
      old.shadow != shadow;
}

class _RetryScreen extends StatelessWidget {
  final VoidCallback onRetry;
  const _RetryScreen({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off, size: 48, color: Gz.textSecondary),
              const SizedBox(height: 16),
              Text(
                t('Жүктеу мүмкін болмады'),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: 220,
                child: FilledButton(
                  onPressed: onRetry,
                  child: Text(t('Қайталау')),
                ),
              ),
              TextButton(
                onPressed: () => confirmSignOut(context),
                child: Text(t('Шығу')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
