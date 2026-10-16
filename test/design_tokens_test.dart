import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// ДИЗАЙН-ЖҮЙЕНІҢ ЕРЕЖЕЛЕРІ — кодпен тексеріледі.
///
/// Бұрын қосымшада 31 түрлі қаріп өлшемі, 23 түрлі радиус, 60-тан астам
/// «қатып қалған» түс және екі түрлі диалог стилі болатын: әр экран өз
/// «стилімен» жазылып, қосымша әр жерде әртүрлі көрінетін. Бұл тест
/// бірыңғай жүйеден ауытқуға жол бермейді — жаңа экран жазылғанда да.
void main() {
  final files = <File>[
    for (final e in Directory('lib').listSync(recursive: true))
      if (e is File &&
          e.path.endsWith('.dart') &&
          !e.path.replaceAll(r'\', '/').contains('lib/core/i18n/'))
        e,
  ];

  String rel(File f) => f.path.replaceAll(r'\', '/');

  /// Әр файлдың жолдары: (файл, жол нөмірі, мәтін). Түсініктемелер
  /// тексерілмейді — оларда ескі мысалдар («Radius.circular(50)») бар.
  Iterable<(String, int, String)> codeLines() sync* {
    for (final f in files) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trimLeft();
        if (line.startsWith('//')) continue;
        yield (rel(f), i + 1, lines[i]);
      }
    }
  }

  test('қаріп өлшемі тек сатыдан (10 · 11 · 12 · 13 · 14 · 15 · 16 · 18 · '
      '20 · 22 · 24 · 28)', () {
    const allowed = {10, 11, 12, 13, 14, 15, 16, 18, 20, 22, 24, 28};
    final re = RegExp(r'fontSize:\s*(\d+(?:\.\d+)?)\s*[,)]');
    final bad = <String>[];
    for (final (file, n, line) in codeLines()) {
      for (final m in re.allMatches(line)) {
        final v = double.parse(m.group(1)!);
        if (v != v.roundToDouble() || !allowed.contains(v.toInt())) {
          bad.add('$file:$n  fontSize: ${m.group(1)}');
        }
      }
    }
    expect(bad, isEmpty, reason: 'Сатыдан тыс қаріп өлшемі:\n${bad.join('\n')}');
  });

  test('радиус тек сатыдан (2 · 4 · 8 · 12 · 16 · 20 · 24 · 28)', () {
    const allowed = {2, 4, 8, 12, 16, 20, 24, 28};
    final re = RegExp(r'Radius\.circular\((\d+(?:\.\d+)?)\)');
    final bad = <String>[];
    for (final (file, n, line) in codeLines()) {
      for (final m in re.allMatches(line)) {
        final v = double.parse(m.group(1)!);
        if (v != v.roundToDouble() || !allowed.contains(v.toInt())) {
          bad.add('$file:$n  ${m.group(0)}');
        }
      }
    }
    expect(bad, isEmpty, reason: 'Сатыдан тыс радиус:\n${bad.join('\n')}');
  });

  test('түстер тек theme.dart-та анықталады', () {
    final re = RegExp(r'Color\(0x[0-9A-Fa-f]{8}\)');
    final bad = <String>[];
    for (final (file, n, line) in codeLines()) {
      if (file.endsWith('lib/core/theme.dart')) continue;
      if (re.hasMatch(line)) bad.add('$file:$n  ${line.trim()}');
    }
    expect(
      bad,
      isEmpty,
      reason: 'Түсті theme.dart-қа (Gz) шығарыңыз:\n${bad.join('\n')}',
    );
  });

  test('диалогтар бір үлгіде (AlertDialog емес — GzDialogFrame)', () {
    final bad = <String>[];
    for (final (file, n, line) in codeLines()) {
      if (file.contains('lib/shared/ui/')) continue;
      if (line.contains('AlertDialog(')) bad.add('$file:$n');
    }
    expect(
      bad,
      isEmpty,
      reason: 'confirmDialog / gzInfoDialog / gzInputDialog / GzDialogFrame '
          'қолданыңыз:\n${bad.join('\n')}',
    );
  });

  test('төменнен ашылатын терезелер бір үлгіде (showGzSheet)', () {
    final bad = <String>[];
    for (final (file, n, line) in codeLines()) {
      if (file.endsWith('lib/shared/ui/sheet.dart')) continue;
      if (line.contains('showModalBottomSheet')) bad.add('$file:$n');
    }
    expect(bad, isEmpty, reason: 'showGzSheet қолданыңыз:\n${bad.join('\n')}');
  });
}
