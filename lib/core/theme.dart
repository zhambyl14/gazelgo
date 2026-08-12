import 'package:flutter/material.dart';

import 'lang.dart';

/// GazelGo дизайн-жүйесі.
///
/// ЖАРЫҚ ПАЛИТРА ЕРЕЖЕСІ: әр семантикалық түстің ЕКІ нұсқасы бар —
///   • негізгі (`green`, `red`, `blue` …) — МӘТІН мен иконкаға арналған,
///     ақ фонда контрасты жеткілікті (≥ 3.2:1, ұсақ қаріп те оқылады);
///   • `*Bright` — тек ТОЛТЫРУ (fill), градиент, индикатор үшін: жарқын,
///     бірақ оның үстіне ұсақ мәтін жазылмайды.
/// Осылайша дизайн жарқын әрі әдемі болады, ал оқылымдылық құрбан болмайды.
class Gz {
  // ---- Бренд (сары — такси/логистика тілі) ----
  /// Негізгі бренд сарысы — батырма, индикатор, белсенді күй.
  static const yellow = Color(0xFFFFC61A);

  /// Градиенттің жарық шеті әрі «жарқ ету» (glow) реңкі.
  static const yellowLight = Color(0xFFFFE066);

  /// Басылған күй / иконка реңкі.
  static const yellowDark = Color(0xFFE8A800);

  /// Ақ фондағы САРЫ МӘТІН үшін ғана (контраст 4.3:1) — `yellowDark`
  /// мәтінге тым ашық, оны тек иконка/толтыруға қалдырамыз.
  static const yellowDeep = Color(0xFFB67A00);

  /// Сарының жылы сыңары — градиенттің төменгі шеті.
  static const amber = Color(0xFFFF9E1B);

  // ---- Негізгі қара-көк ----
  static const ink = Color(0xFF101828);
  static const inkSoft = Color(0xFF1D2939);

  // ---- Беттер ----
  /// Экран фоны — суық-бейтарап, сарымен әдемі үйлеседі әрі бұрынғыдан
  /// жарқынырақ.
  static const bg = Color(0xFFF4F7FC);
  static const surface = Colors.white;

  /// Ақ беттің ІШІНДЕГІ жұмсақ блоктар (өріс, адрес жолы, чип фоны).
  static const surfaceAlt = Color(0xFFF6F9FD);
  static const border = Color(0xFFE7ECF4);
  static const textSecondary = Color(0xFF64748B);

  /// Placeholder/hint — екінші деңгейден де солғын.
  static const textTertiary = Color(0xFF94A3B8);

  // ---- Семантика: мәтінге жарамды негізгі реңк ----
  static const green = Color(0xFF0EA65B);
  static const red = Color(0xFFE4344A);
  static const blue = Color(0xFF2F7BF6);
  static const violet = Color(0xFF8B5CF6);
  static const night = Color(0xFF4338CA);

  // ---- Семантика: тек толтыру/градиентке арналған жарқын реңк ----
  static const greenBright = Color(0xFF22C55E);
  static const redBright = Color(0xFFFF5A6E);
  static const blueBright = Color(0xFF60A5FA);

  /// Басылмайтын (disabled) батырманың түстері — «әлі дайын емес» деген
  /// белгі. Бүкіл қосымшада БІРДЕЙ: шарт орындалғанша сұр, орындалса сары.
  static const disabledBg = Color(0xFFEBEFF5);
  static const disabledFg = Color(0xFFA3AFBD);

  static const radius = 22.0;

  /// Негізгі қаріп (assets/fonts — Rubik, қазақ әліпбиін толық қолдайды).
  static const fontFamily = 'Rubik';

  /// Түстің ЖЕҢІЛ реңкі (chip/banner фоны). Бүкіл қосымшада бірдей қоюлық
  /// болуы үшін — `withValues(alpha: …)` әр жерде әртүрлі жазылмасын.
  static Color tint(Color c, [double alpha = 0.12]) =>
      c.withValues(alpha: alpha);

  /// Негізгі әрекет батырмасының градиенті (жарық сары → жылы алтын).
  /// Түсі жоғарыдан төмен қараңғылана түседі — батырма «дөңес» көрінеді.
  static const brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFD84D), Color(0xFFFFC61A), Color(0xFFFFAE00)],
    stops: [0.0, 0.55, 1.0],
  );

  /// Қара-көк hero-карталарға арналған градиент (сәл көгілдір реңкпен —
  /// жалаң қара емес, «түнгі аспан» әсері).
  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF243449), Color(0xFF162031), Color(0xFF101828)],
    stops: [0.0, 0.5, 1.0],
  );

  /// Карталарға жұмсақ, ЕКІ ҚАБАТТЫ көлеңке: жақын әрі тығыз көлеңке
  /// жиекті айқындайды, алыс әрі жайылған көлеңке тереңдік береді.
  static const cardShadow = [
    BoxShadow(
      color: Color(0x0A101828),
      blurRadius: 3,
      offset: Offset(0, 1),
    ),
    BoxShadow(
      color: Color(0x14101828),
      blurRadius: 18,
      offset: Offset(0, 6),
    ),
  ];

  /// Қалқып тұрған элементтерге (панель, диалог, bottom sheet) — тереңірек.
  static const liftShadow = [
    BoxShadow(
      color: Color(0x0F101828),
      blurRadius: 6,
      offset: Offset(0, 2),
    ),
    BoxShadow(
      color: Color(0x1F101828),
      blurRadius: 34,
      offset: Offset(0, 14),
    ),
  ];

  /// Түрлі-түсті «жарқ ету»: батырма/белсенді элемент өз түсімен жарқырайды.
  static List<BoxShadow> glow(Color c, {double alpha = 0.38, double blur = 22}) =>
      [
        BoxShadow(
          color: c.withValues(alpha: alpha),
          blurRadius: blur,
          offset: const Offset(0, 8),
        ),
      ];

  // ---- ТИПОГРАФИКА ----
  // Мәтіннің көзге әдемі көрінуі үш нәрсеге тәуелді: ӨЛШЕМ САТЫСЫ (әр
  // деңгей нақты ажыратылады), ЖОЛ БИІКТІГІ (height) және ӘРІП АРАЛЫҒЫ
  // (үлкен қаріпте теріс, ұсақ қаріпте сәл оң). Экрандарда осы стильдерді
  // қолдану керек — «fontSize: 14.5, w800» деп қолмен жазудың орнына.

  /// Экранның бас тақырыбы (кіру беті, hero сома).
  static const display = TextStyle(
      fontSize: 28, fontWeight: FontWeight.w900, height: 1.15, letterSpacing: -0.7);

  /// Бөлім тақырыбы.
  static const h1 = TextStyle(
      fontSize: 22, fontWeight: FontWeight.w900, height: 1.2, letterSpacing: -0.5);

  /// Карта/диалог тақырыбы.
  static const h2 = TextStyle(
      fontSize: 18, fontWeight: FontWeight.w800, height: 1.25, letterSpacing: -0.3);

  /// Тізім элементінің тақырыбы.
  static const h3 = TextStyle(
      fontSize: 15.5, fontWeight: FontWeight.w800, height: 1.3, letterSpacing: -0.15);

  /// Негізгі мәтін.
  static const body = TextStyle(fontSize: 14.5, height: 1.5);

  /// Қосымша түсіндірме мәтін.
  static const bodyMuted = TextStyle(
      fontSize: 13.5, height: 1.5, color: textSecondary);

  /// Ұсақ белгі (күн, сан, статус астындағы жазу).
  static const caption = TextStyle(
      fontSize: 12, height: 1.4, letterSpacing: 0.1, color: textSecondary);

  /// Өріс/блок үстіндегі МИКРО тақырып — БАС ӘРІППЕН жазуға арналған.
  static const label = TextStyle(
      fontSize: 10.5,
      fontWeight: FontWeight.w800,
      height: 1.2,
      letterSpacing: 0.8,
      color: textSecondary);

  /// Ақша сомасы — сандар тығыз әрі салмақты тұруы керек.
  static const money = TextStyle(
      fontSize: 19, fontWeight: FontWeight.w900, height: 1.15, letterSpacing: -0.6);

  static const TextTheme _textTheme = TextTheme(
    displaySmall: display,
    headlineMedium: h1,
    headlineSmall: TextStyle(
        fontSize: 20, fontWeight: FontWeight.w900, height: 1.2, letterSpacing: -0.4),
    titleLarge: TextStyle(
        fontSize: 18, fontWeight: FontWeight.w800, height: 1.25, letterSpacing: -0.3),
    titleMedium: TextStyle(
        fontSize: 15.5, fontWeight: FontWeight.w800, height: 1.3, letterSpacing: -0.15),
    titleSmall: TextStyle(
        fontSize: 13.5, fontWeight: FontWeight.w700, height: 1.3),
    bodyLarge: TextStyle(fontSize: 15.5, height: 1.5, letterSpacing: 0),
    bodyMedium: TextStyle(fontSize: 14, height: 1.48, letterSpacing: 0),
    bodySmall: TextStyle(fontSize: 12.5, height: 1.42, letterSpacing: 0.1),
    labelLarge: TextStyle(
        fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 0.1),
    labelMedium: TextStyle(
        fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: 0.1),
    labelSmall: label,
  );

  static ThemeData theme() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: yellow,
        primary: yellow,
        onPrimary: ink,
        secondary: ink,
        onSecondary: yellow,
        surface: surface,
        onSurface: ink,
        surfaceContainerHighest: surfaceAlt,
        outline: border,
        outlineVariant: border,
        error: red,
      ),
      scaffoldBackgroundColor: bg,
      fontFamily: fontFamily,
      fontFamilyFallback: const ['Roboto', 'Arial'],
      textTheme: _textTheme.apply(bodyColor: ink, displayColor: ink),
      // Толқын (ripple) әдепкіде сұр әрі көмескі — брендтің өз реңкі
      // басылғанын айқын әрі әдемі көрсетеді.
      splashColor: yellow.withValues(alpha: 0.16),
      highlightColor: yellow.withValues(alpha: 0.08),
    );
    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: ink,
          fontSize: 19.5,
          fontWeight: FontWeight.w900,
          fontFamily: fontFamily,
          letterSpacing: -0.4,
        ),
      ),
      // ӨШІРУЛІ (disabled) күй ӘРҚАШАН СҰР болуы керек: `styleFrom` дефолт
      // бойынша disabled фонды `backgroundColor`-дан шығармайды да, сары
      // батырма басылмайтын күйде де САРЫ болып тұратын — қолданушы «неге
      // басылмайды?» деп шатасатын (мыс. тіркелудегі нөмір расталмай тұрып
      // «Тіркелу»). Енді: расталмаған/толмаған = сұр, дайын = сары.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: yellow,
          foregroundColor: ink,
          disabledBackgroundColor: disabledBg,
          disabledForegroundColor: disabledFg,
          minimumSize: const Size.fromHeight(54),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          elevation: 6,
          // Көлеңке БРЕНД ТҮСІМЕН — батырманың астынан жылы сәуле шыққандай
          // болады. Сұр көлеңке батырманы «кірлеткен» болып көрсететін.
          shadowColor: yellow.withValues(alpha: 0.55),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.1,
              fontFamily: fontFamily),
        ).copyWith(
          // Өшірулі күйде көлеңке де болмауы керек — әйтпесе сұр батырма
          // «басылатын» болып көрінеді. Басылған сәтте көлеңке кішірейеді:
          // батырма шынымен «басылып» кеткендей әсер береді.
          elevation: WidgetStateProperty.resolveWith((s) {
            if (s.contains(WidgetState.disabled)) return 0;
            if (s.contains(WidgetState.pressed)) return 2;
            return 6;
          }),
          overlayColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.pressed)
                  ? ink.withValues(alpha: 0.10)
                  : ink.withValues(alpha: 0.05)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          // Ақ фон: сұр экран бетінде контур батырма «жоқ жер» емес, нақты
          // батырма болып оқылады.
          backgroundColor: surface,
          disabledForegroundColor: disabledFg,
          minimumSize: const Size.fromHeight(54),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          side: const BorderSide(color: border, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.1,
              fontFamily: fontFamily),
        ).copyWith(
          // Басқанда/тінтуір үстіне келгенде жиегі БРЕНД түсіне ауысады —
          // «бұл да батырма» деген белгі web/desktop-та да көрінеді.
          side: WidgetStateProperty.resolveWith((s) {
            if (s.contains(WidgetState.disabled)) {
              return const BorderSide(color: disabledBg, width: 1.5);
            }
            if (s.contains(WidgetState.pressed) ||
                s.contains(WidgetState.hovered)) {
              return const BorderSide(color: yellow, width: 1.8);
            }
            return const BorderSide(color: border, width: 1.5);
          }),
          overlayColor: WidgetStatePropertyAll(yellow.withValues(alpha: 0.12)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: ink,
          disabledForegroundColor: disabledFg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(
              fontWeight: FontWeight.w800,
              letterSpacing: 0.1,
              fontFamily: fontFamily),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: ink,
          highlightColor: yellow.withValues(alpha: 0.18),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        // Өріс АҚ ЕМЕС, сәл реңкті: ақ карта бетінде «мұнда жазу керек»
        // деген орын өзінен өзі көрініп тұрады (бұрын ақ-ақтың үстінде
        // жалаң жіңішке жиек қана болатын).
        fillColor: surfaceAlt,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: border, width: 1.4),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: border, width: 1.4),
        ),
        // Фокус — БРЕНД сақинасы: қай өрісте тұрғаны бірден көзге түседі.
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: yellow, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: red, width: 1.4),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: red, width: 2),
        ),
        hintStyle: const TextStyle(color: textTertiary, fontWeight: FontWeight.w400),
        prefixIconColor: textSecondary,
        suffixIconColor: textSecondary,
        errorStyle: const TextStyle(
            color: red, fontSize: 12, fontWeight: FontWeight.w600, height: 1.3),
      ),
      cardTheme: CardThemeData(
        color: surface,
        // Жиек + ЖҰМСАҚ КӨЛЕҢКЕ: карта беттен «көтеріліп» тұрады, бұрынғы
        // мүлдем жазық (elevation 0) нұсқасынан әлдеқайда тірі көрінеді.
        elevation: 3,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: const BorderSide(color: border),
        ),
        shadowColor: const Color(0x1A101828),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        shadowColor: const Color(0x40101828),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        titleTextStyle: const TextStyle(
            color: ink,
            fontSize: 18.5,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.3,
            fontFamily: fontFamily),
        contentTextStyle: const TextStyle(
            color: textSecondary,
            fontSize: 13.5,
            height: 1.55,
            fontFamily: fontFamily),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 16,
        shadowColor: Color(0x33101828),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
      ),
      dividerTheme: const DividerThemeData(color: border, thickness: 1),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: ink,
        elevation: 8,
        insetPadding: const EdgeInsets.fromLTRB(14, 5, 14, 14),
        contentTextStyle: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            height: 1.4,
            fontWeight: FontWeight.w600,
            fontFamily: fontFamily),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: textSecondary,
        titleTextStyle: const TextStyle(
            color: ink,
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
            fontFamily: fontFamily),
        subtitleTextStyle: const TextStyle(
            color: textSecondary,
            fontSize: 12.5,
            height: 1.4,
            fontFamily: fontFamily),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceAlt,
        selectedColor: yellow,
        side: const BorderSide(color: border),
        labelStyle: const TextStyle(
            fontSize: 12.5, fontWeight: FontWeight.w700, fontFamily: fontFamily),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: yellowDark,
        linearTrackColor: disabledBg,
        circularTrackColor: Colors.transparent,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: ink,
        unselectedItemColor: textSecondary,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        elevation: 8,
        height: 70,
        // Таңдалған тарауды АЙҚЫН сары «таблетка» белгілейді (бұрын жарты
        // мөлдір еді — қай бөлімде тұрғаны күңгірт көрінетін).
        indicatorColor: yellow,
        indicatorShape: const StadiumBorder(),
        surfaceTintColor: Colors.transparent,
        shadowColor: const Color(0x1A101828),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? ink
                : textSecondary,
            size: 24,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11.5,
            letterSpacing: 0.1,
            fontFamily: fontFamily,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w800
                : FontWeight.w600,
            color: states.contains(WidgetState.selected)
                ? ink
                : textSecondary,
          ),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: ink,
        unselectedLabelColor: textSecondary,
        indicatorColor: yellow,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: border,
        // Индикатор — жуан әрі ДӨҢГЕЛЕКТЕЛГЕН сызық (жалаң 2px сызықтан
        // әлдеқайда әрлі).
        indicator: const UnderlineTabIndicator(
          borderSide: BorderSide(color: yellow, width: 3.5),
          borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
        ),
        overlayColor: WidgetStatePropertyAll(yellow.withValues(alpha: 0.10)),
        labelStyle: const TextStyle(
            fontWeight: FontWeight.w800, fontSize: 14, fontFamily: fontFamily),
        unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w600, fontSize: 14, fontFamily: fontFamily),
      ),
    );
  }
}

/// Ақша форматы: 12500 -> "12 500 ₸"
String fmtT(num? v) {
  if (v == null) return '— ₸';
  final s = v.round().abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    buf.write(s[i]);
    final left = s.length - 1 - i;
    if (left > 0 && left % 3 == 0) buf.write(' ');
  }
  return '${v < 0 ? '-' : ''}$buf ₸';
}

String two(int n) => n < 10 ? '0$n' : '$n';

/// 06.07.2026 14:05
String fmtDate(DateTime? d) {
  if (d == null) return '';
  final l = d.toLocal();
  return '${two(l.day)}.${two(l.month)}.${l.year} ${two(l.hour)}:${two(l.minute)}';
}

String fmtTime(DateTime? d) {
  if (d == null) return '';
  final l = d.toLocal();
  return '${two(l.hour)}:${two(l.minute)}';
}

/// Қалқымалы хабарлама. Жалаң мәтіннің орнына ИКОНКА + мәтін: қате ме,
/// әлде «бәрі ойдағыдай» ма — оқымай тұрып, бір қарағанда түсінікті.
void showSnack(BuildContext context, String text, {bool error = false}) {
  ScaffoldMessenger.of(context)
    // Бірінің үстіне бірі жиналып қалмасын (әсіресе форма қателерінде).
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(
              error ? Icons.priority_high_rounded : Icons.check_rounded,
              size: 17,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
      backgroundColor: error ? Gz.red : Gz.ink,
      duration: Duration(seconds: error ? 4 : 3),
    ));
}

/// Backend қате кодтарын қазақшаға аудару.
String errText(Object e) {
  final raw = e.toString();
  const map = {
    'INSUFFICIENT_BALANCE': 'Балансыңыз жеткіліксіз. Алдымен баланс толтырыңыз.',
    'ALREADY_ACTIVE':
        'Бұл тариф әлі белсенді. Ауысым бітсін не заказ лимиті бітсін — сосын қайта аласыз.',
    'NOT_APPROVED': 'Аккаунтыңыз әлі модерациядан өтпеген.',
    'NOT_EXECUTOR': 'Орындаушы профилі табылмады.',
    'NOT_CLIENT': 'Тек клиент заказ бере алады.',
    'NO_SESSION': 'Алдымен тариф сатып алыңыз.',
    'BAD_VEHICLE_TYPE': 'Көлік түрі дұрыс емес.',
    'NO_ORDERS_LEFT':
        'Тарифіңіздегі заказ лимиті бітті. Жаңа тариф сатып алыңыз.',
    'EXEC_NO_ORDERS': 'Орындаушының тариф лимиті бітіп қалды.',
    'NOT_ELIGIBLE':
        'Бұл заказ сізге қолжетімсіз (басқа қала немесе қазір бос емессіз).',
    'MIN_CITY': 'Қала ішіндегі заказ бағасы кемінде 100 ₸ болуы керек.',
    'MIN_INTERCITY': 'Қалааралық (межгород) заказ бағасы кемінде 1000 ₸.',
    'BUSY': 'Сізде орындалып жатқан заказ бар.',
    'EXEC_BUSY': 'Бұл орындаушы қазір бос емес.',
    'EXEC_UNAVAILABLE': 'Бұл орындаушы қазір қолжетімсіз.',
    'NOT_PENDING': 'Бұл ұсыныс енді белсенді емес.',
    'NOT_AVAILABLE': 'Заказ енді қолжетімсіз.',
    'SIZE_MISMATCH': 'Газель өлшемі сәйкес емес.',
    'OFFER_GONE': 'Ұсыныс енді жарамсыз.',
    'ALREADY_ACCEPTED': 'Ұсыныс қабылданып қойған.',
    'ALREADY_REVIEWED': 'Пікір бұрын қалдырылған.',
    'NOT_COMPLETED': 'Заказ әлі аяқталмаған.',
    'TOO_MANY_ACTIVE': 'Белсенді заказ саны шектен асты (5).',
    'TOO_MANY_CANCELS':
        'Соңғы сағатта тым көп заказды өзіңіз тоқтаттыңыз. '
            'Сәл үзіліс жасап, кейінірек қайталаңыз.',
    'HAS_ACTIVE_ORDERS':
        'Белсенді заказыңыз бар — алдымен оны аяқтаңыз не тоқтатыңыз.',
    'ACCOUNT_BLOCKED':
        'Аккаунтыңыз уақытша бұғатталған (сенім деңгейі төмен түсті). '
            'Қолдау қызметіне жазыңыз.',
    'DELETE_FAILED': 'Аккаунтты өшіру сәтсіз. Қолдау қызметіне жазыңыз.',
    'CANNOT_CANCEL_IN_PROGRESS':
        'Заказ орындалу үстінде — енді бас тартуға болмайды.',
    'REASON_REQUIRED': 'Бас тарту себебін жазыңыз.',
    'OUT_OF_KZ': 'Заказ тек Қазақстан ішінде болуы керек.',
    'NO_FIELDS': 'Қай құжатты жаңарту керегін таңдаңыз.',
    // --- хабарландырулар тақтасы (0043) ---
    'BOARD_OFF':
        'Хабарландырулар тақтасы әзірге қосылмаған. Кейінірек көріңіз.',
    // --- қос рөл / такси (0046) ---
    'TAXI_OFF': 'Такси бөлімі әзірге қосылмаған. Кейінірек көріңіз.',
    // --- көп мекенжай (0047) ---
    'TOO_MANY_STOPS': 'Аялдама саны шектен асты. Біреуін алып тастаңыз.',
    'BAD_STOPS': 'Аялдама мекенжайы дұрыс емес. Қайта таңдаңыз.',
    'FORBIDDEN_COLUMN': 'Бұл өрісті өзгертуге рұқсат жоқ.',
    'TOO_MANY_PHOTOS': 'Бір хабарландыруға ең көбі 4 сурет салуға болады.',
    'TOO_MANY_LISTINGS':
        'Белсенді хабарландыру саны шектен асты (5). Жаңасын беру үшін '
            'ескісінің бірін лентадан алып тастаңыз.',
    'LISTING_ACTIVE': 'Бұл хабарландыру әлі лентада тұр.',
    'ALREADY_REPORTED':
        'Сіз бұл хабарландыруға шағым бердіңіз. Модератор қарап жатыр.',
    // --- жаттыққа шақыру коды (0060–0064) ---
    // Бұл кодтардың аудармасы ЖОҚ болатын: код қате енгізілсе, пайдаланушы
    // «PostgrestException(message: BAD_CODE …)» деген түсініксіз жолды
    // көретін де, өрісті «жұмыс істемейді» деп ойлайтын.
    'ALREADY_REFERRED':
        'Сіз шақыру кодын бұрын енгізгенсіз — ол тек бір рет енгізіледі.',
    'SELF_REFERRAL':
        'Бұл — өзіңіздің кодыңыз. Сізді шақырған адамның кодын енгізіңіз.',
    'REFERRAL_TOO_LATE':
        'Кодты бірінші заказды аяқтағанға дейін енгізу керек еді — енді '
            'кеш. Бірақ өз кодыңызды таратып, бонус жинай бересіз.',
    'BAD_CODE': 'Мұндай код жоқ. Тексеріп, қайта енгізіңіз (мыс. F591C6).',
    'DISABLED': 'Бұл мүмкіндік әзірге қосылмаған.',
    'TOO_FAR_FROM_A': 'Сіз алу нүктесінен тым алыссыз. Жақындаңыз.',
    'TOO_FAR_FROM_B': 'Сіз жеткізу нүктесінен тым алыссыз. Жақындаңыз.',
    'LOCATION_OFF': 'Геолокацияны қосыңыз — ол міндетті.',
    'BAD_RATING': 'Бағаны таңдаңыз (1–5).',
    'BAD_TRANSITION': 'Қадамды өткізу мүмкін емес.',
    'EMPTY': 'Хабарлама бос.',
    'BAD_PRICE': 'Баға дұрыс емес (кемінде 100 ₸).',
    'BAD_AMOUNT': 'Сома тым аз.',
    'BAD_INPUT': 'Деректер толық емес.',
    'FORBIDDEN': 'Рұқсат жоқ.',
    'EMAIL_TAKEN': 'Бұл нөмір тіркелген. Кіріп көріңіз.',
    'PHONE_TAKEN': 'Бұл нөмір тіркелген. Кіріп көріңіз.',
    'PHONE_NOT_FOUND': 'Бұл нөмір тіркелмеген. Алдымен тіркеліңіз.',
    'WEAK_PASSWORD': 'Құпиясөз тым қысқа (кемінде 6 таңба).',
    'BAD_EMAIL': 'Email дұрыс емес.',
    'BAD_PHONE': 'Телефон нөмірі дұрыс емес.',
    'BAD_NAME': 'Атыңызды толық жазыңыз.',
    'BAD_ROLE': 'Рөл дұрыс емес.',
    'RATE_LIMITED': 'Тым жиі сұраныс. Сәл күтіп, қайталаңыз.',
    'TG_NOT_VERIFIED':
        'Алдымен нөміріңізді Telegram арқылы растаңыз.',
    'SERVER_ERROR': 'Сервер қатесі. Қайталап көріңіз.',
    'AUTH': 'Қайта кіріңіз.',
    'NOT_FOUND': 'Жазба табылмады.',
    'Invalid login credentials': 'Телефон немесе құпиясөз қате.',
    'User already registered': 'Бұл email тіркелген. Кіріп көріңіз.',
    'already been registered': 'Бұл email тіркелген. Кіріп көріңіз.',
    'Password should be': 'Құпиясөз тым әлсіз (кемінде 6 таңба).',
    'rate limit': 'Тым жиі әрекет. Сәл күтіп, қайталаңыз.',
    'invalid format': 'Email форматы дұрыс емес.',
    'Signups not allowed': 'Тіркелу уақытша жабық.',
    'Email not confirmed':
        'Email расталмаған. Поштаңыздағы сілтемені басыңыз немесе '
            'Supabase-те Confirm email-ді өшіріңіз.',
    'EMAIL_CONFIRM_REQUIRED':
        'Тіркелу өтті, бірақ Supabase-те "Confirm email" қосулы тұр. '
            'Dashboard → Authentication → Sign In / Providers → Email → '
            '"Confirm email" өшіріп, қайта тіркеліңіз.',
    'JWSError': 'API кілті қате (env.dart тексеріңіз).',
    'Invalid API key': 'API кілті қате (env.dart тексеріңіз).',
  };
  for (final k in map.keys) {
    if (raw.contains(k)) return t(map[k]!);
  }
  if (raw.contains('SocketException') ||
      raw.contains('Failed host lookup') ||
      raw.contains('XMLHttpRequest')) {
    return t('Интернет байланысы жоқ. Қайталап көріңіз.');
  }
  // Белгісіз қате — себебін көрсетеміз (диагностикаға көмек)
  var s = raw.replaceFirst('Exception: ', '').trim();
  if (s.length > 140) s = '${s.substring(0, 140)}…';
  return '${t('Қате')}: $s';
}
