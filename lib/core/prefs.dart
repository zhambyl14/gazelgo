import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Құрылғыдағы жеңіл баптаулар (SharedPreferences). Қазір: орындаушының
/// жаңа заказ уведомлениелерін қосу/өшіру таңдауы.
class Prefs {
  // ── Профиль кэші (тек СУЫҚ ІСКЕ ҚОСУ үшін) ───────────────────────────
  // Қосымша ашылғанда соңғы белгілі профиль бірден көрсетіледі де, сервер
  // жауабы фонда келіп, оны жаңартады. Кілтке uid қосылады — бір құрылғыда
  // аккаунт ауысса, бөтен профиль ешқашан көрсетілмейді.
  static String _kProfile(String uid) => 'cache_profile_$uid';
  static String _kExecProfile(String uid) => 'cache_exec_profile_$uid';

  static Future<Map<String, dynamic>?> cachedProfile(String uid) =>
      _readJson(_kProfile(uid));
  static Future<void> setCachedProfile(String uid, Map<String, dynamic>? m) =>
      _writeJson(_kProfile(uid), m);
  static Future<Map<String, dynamic>?> cachedExecProfile(String uid) =>
      _readJson(_kExecProfile(uid));
  static Future<void> setCachedExecProfile(
    String uid,
    Map<String, dynamic>? m,
  ) => _writeJson(_kExecProfile(uid), m);

  static Future<Map<String, dynamic>?> _readJson(String key) async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(key);
      if (raw == null) return null;
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeJson(String key, Map<String, dynamic>? m) async {
    try {
      final p = await SharedPreferences.getInstance();
      if (m == null) {
        await p.remove(key);
      } else {
        await p.setString(key, jsonEncode(m));
      }
    } catch (_) {}
  }

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

  static const _kOrderSound = 'executor_order_sound';

  /// Лентада жаңа заказ шыққанда дыбыс ойнасын ба? (әдепкі — қосулы)
  static Future<bool> orderSound() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kOrderSound) ?? true;
  }

  static Future<void> setOrderSound(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kOrderSound, v);
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

  static const _kThemeMode = 'app_theme_mode';

  /// Интерфейс режимі: 'light' (әдепкі), 'dark' не 'system'.
  static Future<String> themeMode() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kThemeMode) ?? 'light';
  }

  static Future<void> setThemeMode(String v) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kThemeMode, v);
  }

  static const _kRegistrationDraft = 'registration_draft_key';

  static Future<String?> registrationDraftKey() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kRegistrationDraft);
  }

  static Future<void> setRegistrationDraftKey(String value) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kRegistrationDraft, value);
  }

  static Future<void> clearRegistrationDraftKey() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kRegistrationDraft);
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

  static const _kNavApp = 'executor_nav_app';

  /// Орындаушы таңдаған навигатор ('dgis' | 'yandex' | 'google'); null —
  /// әлі таңдалмаған (бірінші рет басқанда сұралады).
  static Future<String?> navApp() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kNavApp);
  }

  static Future<void> setNavApp(String v) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kNavApp, v);
  }

  static const _kFeedSort = 'executor_feed_sort';
  static const _kFeedScope = 'executor_feed_scope';
  static const _kHiddenOrders = 'executor_hidden_orders';

  /// Орындаушы лентасының сұрыптауы мен сүзгісі (соңғы таңдау есте қалады).
  static Future<(String?, String?)> feedView() async {
    final p = await SharedPreferences.getInstance();
    return (p.getString(_kFeedSort), p.getString(_kFeedScope));
  }

  static Future<void> setFeedView(String sort, String scope) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kFeedSort, sort);
    await p.setString(_kFeedScope, scope);
  }

  /// Орындаушы лентадан ЖАСЫРҒАН заказдар (қызық емес) — ең көбі 200.
  static Future<Set<String>> hiddenOrders() async {
    final p = await SharedPreferences.getInstance();
    return (p.getStringList(_kHiddenOrders) ?? const <String>[]).toSet();
  }

  static Future<void> hideOrder(String id) async {
    final p = await SharedPreferences.getInstance();
    final list = p.getStringList(_kHiddenOrders) ?? <String>[];
    if (list.contains(id)) return;
    list.add(id);
    if (list.length > 200) list.removeRange(0, list.length - 200);
    await p.setStringList(_kHiddenOrders, list);
  }

  static Future<void> unhideAllOrders() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kHiddenOrders);
  }

  static const _kSeenNews = 'seen_news_ids';

  /// Тізімде сақталатын ең көп сторис id-і. Ескілері шетінен шығып отырады
  /// — әйтпесе тізім жылдар бойы шексіз өсер еді (жаңалық серверде ондаған
  /// күннен кейін мүлдем жойылады, сол себепті 200-і жеткілікті).
  static const _kSeenNewsMax = 200;

  /// Құрылғыда «көрілген» деп белгіленген стористер (0066).
  ///
  /// ГЕСТ үшін МІНДЕТТІ: кірмеген адамның uid-і жоқ, сол себепті сервер
  /// оның көргенін тіркей алмайды. Кірген адамда бұл серверлік белгінің
  /// ҮСТІНЕ қосылады — интернет үзілсе де сақина жыпылықтап тұрмайды.
  static Future<Set<String>> seenNews() async {
    final p = await SharedPreferences.getInstance();
    return (p.getStringList(_kSeenNews) ?? const <String>[]).toSet();
  }

  static Future<void> markNewsSeen(String id) async {
    final p = await SharedPreferences.getInstance();
    final list = p.getStringList(_kSeenNews) ?? <String>[];
    if (list.contains(id)) return;
    list.add(id);
    // Ең ескілерін (тізімнің басындағыларын) қиямыз.
    if (list.length > _kSeenNewsMax) {
      list.removeRange(0, list.length - _kSeenNewsMax);
    }
    await p.setStringList(_kSeenNews, list);
  }
}
