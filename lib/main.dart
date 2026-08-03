import 'dart:async';
import 'dart:convert';

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
import 'features/auth/executor_apply_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/pending_screen.dart';
import 'features/client/client_shell.dart';
import 'features/client/order_detail_screen.dart';
import 'features/executor/balance_screen.dart';
import 'features/executor/executor_order_screen.dart';
import 'features/executor/executor_shell.dart';
import 'features/moderator/moderator_shell.dart';
import 'features/support/support_screen.dart';
import 'shared/portrait_frame.dart';
import 'shared/update_gate.dart';
import 'shared/widgets.dart';

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
            child: PortraitFrame(child: child!),
          );
        },
        home: Env.isConfigured
            ? const UpdateGate(child: AuthGate())
            : const _NotConfigured(),
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
        // Push-токенді тіркеу — қосымша толық жабық тұрғанда да
        // хабарландыру жеткізілуі үшін. Firebase бапталмаса — үнсіз өтеді.
        // `init()` енді әр кіруде токенді АҒЫМДАҒЫ пайдаланушыға қайта
        // тіркейді (бір телефонда аккаунт ауысса, ескі иесінің push-ы
        // жаңа иесіне келмеуі үшін), ал `Lang.syncToServer()` push тілін
        // серверге жеткізеді.
        unawaited(Push.init());
        unawaited(Lang.syncToServer());
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

    return profile.when(
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
            return const ModeratorShell();
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
      loading: () => const _Splash(),
      error: (e, st) => _RetryScreen(
        onRetry: () => ref.invalidate(myExecutorProfileProvider),
      ),
      data: (e) {
        // Әлі өтінім толтырмаған (профиль жоқ) — толтыру экраны.
        if (e == null) return const ExecutorApplyScreen();
        // Модератор БҰҒАТТАҒАН аккаунт — қосымшаға кіре алмайды.
        if (e.status == 'blocked') return PendingScreen(profile: e);
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

class _SplashState extends State<_Splash> {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Gz.surface,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Image.asset(
                'assets/icon/icon.png',
                width: 120,
                height: 120,
              ),
            ),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                t('Жүк тасымалы және арнайы техника платформасы'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Gz.textSecondary, fontSize: 14.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
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
