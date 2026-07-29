import 'package:flutter/foundation.dart';

import 'i18n/ru_auth.dart';
import 'i18n/ru_board.dart';
import 'i18n/ru_client.dart';
import 'i18n/ru_dual_role.dart';
import 'i18n/ru_executor.dart';
import 'i18n/ru_moderator.dart';
import 'i18n/ru_shared.dart';
import 'prefs.dart';
import 'repo.dart';

enum AppLang { kk, ru }

/// Қосымша тілі — глобалды реактивті мән (Riverpod-сыз, себебі
/// `t()` кез келген жерде — dialog/const контексте де — шақырылады).
/// main.dart `ValueListenableBuilder`-мен MaterialApp-ты осыны тыңдатып
/// орайды: тіл ауысқанда бүкіл ағаш қайта салынады.
class Lang {
  static final ValueNotifier<AppLang> current = ValueNotifier(AppLang.kk);

  static Future<void> init() async {
    final v = await Prefs.language();
    current.value = v == 'ru' ? AppLang.ru : AppLang.kk;
  }

  static Future<void> set(AppLang l) async {
    if (current.value == l) return;
    current.value = l;
    await Prefs.setLanguage(l == AppLang.ru ? 'ru' : 'kk');
    await syncToServer();
  }

  /// Тілді серверге жеткізу (0045): push-хабарландырулар сол тілде БІР РЕТ
  /// келуі үшін. Кірген сайын да, тіл ауысқанда да шақырылады. Кірмеген
  /// күйде/желі жоқта үнсіз өтеді — тіл жергілікті сақталған күйінде қалады.
  static Future<void> syncToServer() async {
    if (Repo.uid == null) return;
    try {
      await Repo.setMyLang(current.value == AppLang.ru ? 'ru' : 'kk');
    } catch (_) {}
  }
}

/// Барлық модуль сөздіктері осында бірігеді (lib/core/i18n/ru_*.dart).
final Map<String, String> _kkToRu = {
  ...ruShared,
  ...ruAuth,
  ...ruClient,
  ...ruExecutor,
  ...ruModerator,
  // Хабарландырулар тақтасы (0043) — соңында тұрады: жаңа фичаның
  // мәтіндері ескі сөздіктердегі бірдей кілттерді басып озады.
  ...ruBoard,
  // Қос рөл + такси + қысқартылған мәтіндер (0046) — ЕҢ СОҢҒЫ, сол
  // себепті жаңартылған жолдардың аудармасы басым болады.
  ...ruDualRole,
};

/// Қазақша мәтінді ағымдағы тілге аудару. Тек RU тілінде сөздіктен
/// іздейді; аудармасы жоқ болса — қазақша мәтіннің өзі қайтады
/// (аударма толмаса да қосымша ешқашан бұзылмайды).
String t(String kk) {
  if (Lang.current.value != AppLang.ru) return kk;
  return _kkToRu[kk] ?? kk;
}
