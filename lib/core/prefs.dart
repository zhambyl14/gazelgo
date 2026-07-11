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
}
