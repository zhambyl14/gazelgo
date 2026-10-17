// Аударма аудиті: lib ішіндегі барлық t('...') кілттерін жинап,
// ru_*.dart сөздіктерімен салыстырады. Жетіспейтін аудармаларды шығарады.
// Іске қосу: dart run tool/i18n_audit.dart
//
// Сөздіктер тізімі lib/core/lang.dart ішіндегі _kkToRu-мен БІРДЕЙ болуы
// керек (әйтпесе аудармасы бар мәтін «жетіспейді» болып көрінеді).
import 'dart:io';

import 'package:tasu/core/i18n/ru_auth.dart';
import 'package:tasu/core/i18n/ru_board.dart';
import 'package:tasu/core/i18n/ru_bonus.dart';
import 'package:tasu/core/i18n/ru_client.dart';
import 'package:tasu/core/i18n/ru_dual_role.dart';
import 'package:tasu/core/i18n/ru_executor.dart';
import 'package:tasu/core/i18n/ru_merge.dart';
import 'package:tasu/core/i18n/ru_moderator.dart';
import 'package:tasu/core/i18n/ru_news.dart';
import 'package:tasu/core/i18n/ru_redesign.dart';
import 'package:tasu/core/i18n/ru_shared.dart';

void main() {
  final dict = <String, String>{
    ...ruShared,
    ...ruAuth,
    ...ruClient,
    ...ruExecutor,
    ...ruModerator,
    ...ruBoard,
    ...ruDualRole,
    ...ruBonus,
    ...ruNews,
    ...ruRedesign,
    ...ruMerge,
  };

  // t('...') — жанасқан литералдар да қосылады: t('a' 'b')
  final call = RegExp(
    // `dart format` ұзын мәтіннен кейін үтір қояды: t('…',) — ол да кіреді.
    r"""\bt\(\s*((?:'(?:[^'\\]|\\.)*'\s*)+),?\s*\)""",
    multiLine: true,
  );
  final lit = RegExp(r"""'((?:[^'\\]|\\.)*)'""");

  final keys = <String, String>{}; // key -> қай файлда кездескені
  final libDir = Directory('lib');
  for (final f in libDir.listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('.dart')) continue;
    if (f.path.replaceAll('\\', '/').contains('/i18n/')) continue;
    final src = f.readAsStringSync();
    for (final m in call.allMatches(src)) {
      final joined = lit
          .allMatches(m.group(1)!)
          .map((x) => x.group(1)!)
          .join()
          .replaceAll(r"\'", "'")
          .replaceAll(r'\n', '\n');
      if (joined.trim().isEmpty) continue;
      keys.putIfAbsent(joined, () => f.path);
    }
  }

  final missing = keys.entries.where((e) => !dict.containsKey(e.key)).toList()
    ..sort((a, b) => a.value.compareTo(b.value));

  stdout.writeln('Барлық t() кілті: ${keys.length}');
  stdout.writeln('Сөздікте бар: ${keys.length - missing.length}');
  stdout.writeln('ЖЕТІСПЕЙДІ: ${missing.length}\n');
  for (final e in missing) {
    stdout.writeln('[${e.value}]');
    stdout.writeln("  '${e.key.replaceAll('\n', r'\n')}'");
  }

  // Сөздікте бар, бірақ кодта енді қолданылмайтын кілттер (ақпарат үшін)
  final unused = dict.keys.where((k) => !keys.containsKey(k)).length;
  stdout.writeln('\nЕскірген (қолданылмайтын) сөздік жазбалары: $unused');
}
