/// Телефон нөмірін біркелкі пішінге келтіру (Қазақстан).
///
/// Аутентификация телефон + құпиясөзбен жүреді, бірақ Supabase-те аккаунт
/// «синтетикалық email» арқылы құрылады: `7XXXXXXXXXX@phone.gazelgo.kz`.
/// Осылай телефон провайдерін бөлек баптамай-ақ, бар email/құпиясөз ағыны
/// қайта қолданылады. Пайдаланушы бұл email-ді ешқашан көрмейді.
class Phone {
  /// Синтетикалық email домені (сервермен бірдей болуы шарт!).
  static const emailDomain = 'phone.gazelgo.kz';

  /// Кез келген енгізуден 11 таңбалы `7XXXXXXXXXX` пішінін шығарады.
  /// Дұрыс емес болса — null. Тек ҚАЗАҚСТАНДЫҚ нөмір қабылданады: екінші
  /// таңба да «7» болуы шарт (`+77...`) — ресейлік нөмірлер `+79...` болып
  /// басталады, сол екеуін осылай ажыратамыз (екеуі де +7 ел кодын бөліседі).
  static String? normalize(String raw) {
    var d = raw.replaceAll(RegExp(r'\D'), '');
    // 8XXXXXXXXXX → 7XXXXXXXXXX
    if (d.length == 11 && d.startsWith('8')) d = '7${d.substring(1)}';
    // XXXXXXXXXX (10) → 7XXXXXXXXXX
    if (d.length == 10) d = '7$d';
    if (d.length == 11 && d.startsWith('77')) return d;
    return null;
  }

  /// Дұрыс қазақстандық нөмір бе?
  static bool isValid(String raw) => normalize(raw) != null;

  /// Көрсету пішіні: `+7 700 123 45 67`.
  static String pretty(String raw) {
    final d = normalize(raw);
    if (d == null) return raw;
    return '+7 ${d.substring(1, 4)} ${d.substring(4, 7)} '
        '${d.substring(7, 9)} ${d.substring(9, 11)}';
  }

  /// Supabase-тегі синтетикалық email (нормаланған нөмірден).
  static String? emailOf(String raw) {
    final d = normalize(raw);
    return d == null ? null : '$d@$emailDomain';
  }
}
