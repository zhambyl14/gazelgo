import 'package:flutter/material.dart';

import 'lang.dart';

/// GazelGo дизайн-жүйесі.
class Gz {
  // Бренд түстері
  static const yellow = Color(0xFFFFC400);
  static const yellowDark = Color(0xFFE6AC00);
  static const ink = Color(0xFF0F1720);
  static const inkSoft = Color(0xFF1D2733);
  static const bg = Color(0xFFF4F6F8);
  static const surface = Colors.white;
  static const border = Color(0xFFE4E8EC);
  static const textSecondary = Color(0xFF5B6B7B);
  static const green = Color(0xFF16A34A);
  static const red = Color(0xFFDC2626);
  static const blue = Color(0xFF2563EB);
  static const violet = Color(0xFF7C3AED);
  static const night = Color(0xFF3730A3);

  static const radius = 20.0;

  /// Негізгі қаріп (assets/fonts — Rubik, қазақ әліпбиін толық қолдайды).
  static const fontFamily = 'Rubik';

  /// Қара-көк hero-карталарға арналған градиент.
  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1B2836), Color(0xFF0F1720)],
  );

  /// Карталарға жұмсақ көлеңке.
  static const cardShadow = [
    BoxShadow(
      color: Color(0x0F0F1720),
      blurRadius: 14,
      offset: Offset(0, 4),
    ),
  ];

  static ThemeData theme() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: yellow,
        primary: yellow,
        onPrimary: ink,
        surface: surface,
        error: red,
      ),
      scaffoldBackgroundColor: bg,
      fontFamily: fontFamily,
      fontFamilyFallback: const ['Roboto', 'Arial'],
    );
    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: ink,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          fontFamily: fontFamily,
          letterSpacing: -0.2,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: yellow,
          foregroundColor: ink,
          minimumSize: const Size.fromHeight(54),
          elevation: 4,
          shadowColor: const Color(0x66FFC400),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          textStyle: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.w700, fontFamily: fontFamily),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          minimumSize: const Size.fromHeight(54),
          side: const BorderSide(color: border, width: 1.4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          textStyle: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.w700, fontFamily: fontFamily),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: ink,
          textStyle:
              const TextStyle(fontWeight: FontWeight.w700, fontFamily: fontFamily),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: border, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: border, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: ink, width: 1.6),
        ),
        hintStyle: const TextStyle(color: textSecondary),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: const BorderSide(color: border),
        ),
        shadowColor: const Color(0x0D0F1720),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shadowColor: const Color(0x330F1720),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: const TextStyle(
            color: ink,
            fontSize: 18,
            fontWeight: FontWeight.w900,
            fontFamily: fontFamily),
        contentTextStyle: const TextStyle(
            color: textSecondary,
            fontSize: 13.5,
            height: 1.5,
            fontFamily: fontFamily),
      ),
      dividerTheme: const DividerThemeData(color: border, thickness: 1),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: ink,
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: ink,
        unselectedItemColor: textSecondary,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        elevation: 3,
        height: 68,
        indicatorColor: yellow.withValues(alpha: 0.9),
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black26,
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
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w800
                : FontWeight.w600,
            color: states.contains(WidgetState.selected)
                ? ink
                : textSecondary,
          ),
        ),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: ink,
        unselectedLabelColor: textSecondary,
        indicatorColor: yellow,
        indicatorSize: TabBarIndicatorSize.tab,
        labelStyle: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
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

void showSnack(BuildContext context, String text, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(text),
    backgroundColor: error ? Gz.red : Gz.ink,
  ));
}

/// Backend қате кодтарын қазақшаға аудару.
String errText(Object e) {
  final raw = e.toString();
  const map = {
    'INSUFFICIENT_BALANCE': 'Балансыңыз жеткіліксіз. Алдымен баланс толтырыңыз.',
    'ALREADY_ACTIVE':
        'Бұл тариф әлі белсенді. Ауысым бітсін не 10 заказ бітсін — сосын қайта аласыз.',
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
    'TOO_MANY_PHOTOS': 'Бір хабарландыруға ең көбі 4 сурет салуға болады.',
    'TOO_MANY_LISTINGS':
        'Белсенді хабарландыру саны шектен асты (5). Жаңасын беру үшін '
            'ескісінің бірін лентадан алып тастаңыз.',
    'LISTING_ACTIVE': 'Бұл хабарландыру әлі лентада тұр.',
    'ALREADY_REPORTED':
        'Сіз бұл хабарландыруға шағым бердіңіз. Модератор қарап жатыр.',
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
