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
