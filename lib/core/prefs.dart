import 'package:shared_preferences/shared_preferences.dart';

/// Құрылғыдағы жеңіл баптаулар (SharedPreferences). Қазір: орындаушының
/// жаңа заказ уведомлениелерін қосу/өшіру таңдауы.
class Prefs {
  static const _kOrderNotify = 'executor_order_notify';

  /// Орындаушыға жаңа заказ уведомлениелері қосулы ма? (әдепкі — қосулы)
  static Future<bool> orderNotify() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kOrderNotify) ?? true;
  }

  static Future<void> setOrderNotify(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kOrderNotify, v);
  }

  static const _kLanguage = 'app_language';

  /// Қосымша тілі: 'kk' (әдепкі) не 'ru'.
  static Future<String> language() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kLanguage) ?? 'kk';
  }

  static Future<void> setLanguage(String v) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kLanguage, v);
  }

  static const _kLegalConfirms = 'client_legal_confirms';

  /// «Жүгім заңды» белгісін клиент қанша рет ҚОЛМЕН қойды. Алғашқы
  /// [kLegalAutoAfter] реттен кейін белгі автоматты қойылып тұрады — әр
  /// заказда бір әрекет үнемделеді (қолданушы оны алып тастай алады).
  static const kLegalAutoAfter = 3;

  static Future<int> legalConfirms() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt(_kLegalConfirms) ?? 0;
  }

  /// Заказ сәтті жарияланғанда шақырылады (белгі қолмен қойылған болса).
  static Future<void> bumpLegalConfirms() async {
    final p = await SharedPreferences.getInstance();
    final n = p.getInt(_kLegalConfirms) ?? 0;
    if (n >= kLegalAutoAfter) return;
    await p.setInt(_kLegalConfirms, n + 1);
  }

  static const _kDrawerHint = 'drawer_hint_seen';

  /// Бүйір панель (sidebar) туралы НҰСҚАУ қанша рет көрсетілді.
  /// Адамдар сол жақ шеттен тартып панель ашуға болатынын білмей
  /// қалатын — сол себепті алғашқы [kDrawerHintTimes] ашылуда қысқа
  /// қалқыма нұсқау шығады, сосын мәңгіге тоқтайды.
  static const kDrawerHintTimes = 4;

  static Future<int> drawerHintSeen() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt(_kDrawerHint) ?? 0;
  }

  static Future<void> bumpDrawerHint() async {
    final p = await SharedPreferences.getInstance();
    final n = p.getInt(_kDrawerHint) ?? 0;
    if (n >= kDrawerHintTimes) return;
    await p.setInt(_kDrawerHint, n + 1);
  }

  /// «Түсіндім» деп өзі жапса — енді мүлдем көрсетпейміз.
  static Future<void> dismissDrawerHint() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kDrawerHint, kDrawerHintTimes);
  }

  static const _kLastLat = 'client_last_lat';
  static const _kLastLng = 'client_last_lng';

  /// Клиенттің соңғы қолданған карта орталығы. GPS рұқсаты болмаса, келесі
  /// ашылуда карта осы жерден (өткен рет қалдырған қаласынан) ашылады —
  /// әдепкі Алматының орнына. null — әлі сақталмаған (алғашқы ашылу).
  static Future<(double, double)?> lastLocation() async {
    final p = await SharedPreferences.getInstance();
    final lat = p.getDouble(_kLastLat);
    final lng = p.getDouble(_kLastLng);
    if (lat == null || lng == null) return null;
    return (lat, lng);
  }

  static Future<void> setLastLocation(double lat, double lng) async {
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_kLastLat, lat);
    await p.setDouble(_kLastLng, lng);
  }
}
