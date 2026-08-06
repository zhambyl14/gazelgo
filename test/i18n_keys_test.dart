import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tasu/core/i18n/ru_bonus.dart';
import 'package:tasu/core/i18n/ru_dual_role.dart';

/// Аударма сөздігі КОДПЕН СӘЙКЕС ПЕ — детерминирленген тексеру.
///
/// `t('...')` сөздіктен ДӘЛ мәтін бойынша іздейді: бір таңба айырмашылық
/// болса аударма үнсіз жоғалады да, орыс тілінде қазақша мәтін көрінеді
/// (қате шықпайды — сол себепті мұны тест ұстауы керек).
///
/// Dart-та қатар тұрған жол литералдары компиляция кезінде БІРІГЕДІ
/// (`'a' 'b'` == `'ab'`), сондықтан салыстыру алдында кодтағы сол
/// біріктіруді қолмен қайталаймыз.
void main() {
  final joinAdjacent = RegExp(r"'\s*'", multiLine: true, dotAll: true);

  String joined(String src) {
    var text = src;
    String? prev;
    while (prev != text) {
      prev = text;
      text = text.replaceAll(joinAdjacent, '');
    }
    return text;
  }

  // Кодтың бүкіл мәтіні (i18n сөздіктерінің өзінен басқа) — бір рет
  // оқылады да, барлық сөздікке ортақ қолданылады.
  late final String code = () {
    final buf = StringBuffer();
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      // i18n сөздіктерінің өзін қоспаймыз (әйтпесе кілт өз-өзін «табады»).
      if (entity.path.replaceAll(r'\', '/').contains('lib/core/i18n/')) {
        continue;
      }
      buf.writeln(joined(entity.readAsStringSync()));
    }
    return buf.toString();
  }();

  /// Сөздіктің ӘР КІЛТІ кодта нақты `t('...')` литералы болып тұр ма.
  ///
  /// БАРЛЫҚ сөздік тексерілмейді — тек жаңа әрі таза күйде ұсталатындары.
  /// Ескі сөздіктерде (ru_client, ru_executor…) уақыт өте ескірген кілттер
  /// жиналған, оларды бірден тазалау бұл тестің мақсаты емес.
  void checkDict(String name, Map<String, String> dict) {
    test('$name кілттерінің бәрі кодта бар', () {
      final missing = <String>[];
      for (final key in dict.keys) {
        // Кілттің кодтағы литерал түрі: `\n` escape болып жазылады.
        final literal = key.replaceAll('\n', r'\n');
        if (!code.contains("'$literal'")) missing.add(key);
      }
      expect(
        missing,
        isEmpty,
        reason: 'Бұл кілттер кодтағы t() шақыруымен сәйкес келмейді '
            '(аудармасы қолданылмайды):\n${missing.join('\n---\n')}',
      );
    });

    test('$name ішінде бос аударма жоқ', () {
      final empty =
          dict.entries.where((e) => e.value.trim().isEmpty).map((e) => e.key);
      expect(empty, isEmpty);
    });
  }

  checkDict('ruDualRole', ruDualRole);
  // Бонус бағдарламасы / sidebar нұсқауы / жаңа профиль (0059).
  checkDict('ruBonus', ruBonus);
}
