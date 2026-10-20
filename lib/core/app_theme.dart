import 'package:flutter/foundation.dart';

import 'prefs.dart';
import 'theme.dart';

/// Интерфейс режимі: ақ, қара немесе құрылғыдағыдай.
enum AppThemeMode { light, dark, system }

/// Қосымшаның түс режимі — [Lang] сияқты глобалды реактивті мән.
///
/// [Gz] түстері getter: олар [Gz.dark]-қа қарап жарық не қараңғы реңкті
/// береді. Режим не құрылғы баптауы өзгергенде [refresh] [Gz.dark]-ты
/// жаңартып, [isDark]-ты хабарлайды; main.dart сонда бүкіл ағашты қайта
/// салдырады (навигация мен ашық беттер сақталады).
class AppTheme {
  static final ValueNotifier<AppThemeMode> mode =
      ValueNotifier(AppThemeMode.light);

  /// Нақты қолданылып тұрған күй (режим + құрылғы баптауы).
  static final ValueNotifier<bool> isDark = ValueNotifier(false);

  static Future<void> init() async {
    mode.value = switch (await Prefs.themeMode()) {
      'dark' => AppThemeMode.dark,
      'system' => AppThemeMode.system,
      _ => AppThemeMode.light,
    };
    refresh();
  }

  static Future<void> set(AppThemeMode m) async {
    if (mode.value == m) return;
    mode.value = m;
    refresh();
    await Prefs.setThemeMode(m.name);
  }

  /// Құрылғының жарық/қараңғы баптауы өзгергенде де шақырылады.
  static void refresh() {
    final d = switch (mode.value) {
      AppThemeMode.dark => true,
      AppThemeMode.light => false,
      AppThemeMode.system =>
        PlatformDispatcher.instance.platformBrightness == Brightness.dark,
    };
    Gz.dark = d;
    isDark.value = d;
  }
}
