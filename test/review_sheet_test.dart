import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasu/core/lang.dart';
import 'package:tasu/core/theme.dart';
import 'package:tasu/shared/widgets.dart';

/// Заказ аяқталғандағы бағалау терезесі (төменнен ашылады) және дайын
/// хаттар/тегтер чипі ([GzPickChip]).
///
/// Тексеріс: тар телефонда (320px), орыс тілінде, ақ ТА, қара ДА режимде
/// терезе ақаусыз салынады; жұлдыз ауысқанда тегтер ауысады; таңдалған
/// чиптің мәтіні фонымен бірдей түсте болып «жоғалып» кетпейді.
void main() {
  Future<void> openSheet(WidgetTester tester, {required bool dark}) async {
    Gz.dark = dark;
    tester.view.physicalSize = const Size(320 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: Gz.theme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showGzSheet<void>(
                  context,
                  builder: (_) => const ReviewPrompt(
                    orderId: 'o1',
                    title: 'Орындаушыны бағалаңыз',
                    tags: kExecutorReviewTags,
                    asSheet: true,
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  setUp(() => Lang.current.value = AppLang.ru);
  tearDown(() {
    Lang.current.value = AppLang.kk;
    Gz.dark = false;
  });

  for (final dark in [false, true]) {
    final mode = dark ? 'қара' : 'ақ';

    testWidgets('бағалау терезесі ақаусыз ашылады ($mode режим)', (
      tester,
    ) async {
      await openSheet(tester, dark: dark);
      expect(tester.takeException(), isNull);
      expect(find.text('Отлично!'), findsOneWidget);
      // 5 жұлдызда — тек «ұнады» тегтері.
      expect(find.byType(GzPickChip), findsNWidgets(5));

      // 2 жұлдыз → «ұнамады» тегтері.
      await tester.tap(find.byIcon(Icons.star_rounded).at(1));
      await tester.pumpAndSettle();
      expect(find.text('Плохо'), findsOneWidget);
      expect(find.byType(GzPickChip), findsNWidgets(4));
      expect(tester.takeException(), isNull);
    });

    testWidgets('таңдалған чиптің мәтіні фонынан ерекшеленеді ($mode)', (
      tester,
    ) async {
      Gz.dark = dark;
      await tester.pumpWidget(
        MaterialApp(
          theme: Gz.theme(),
          home: Scaffold(
            body: Wrap(
              children: [
                GzPickChip(label: 'a', selected: true, onTap: () {}),
                GzPickChip(
                  label: 'b',
                  selected: true,
                  tone: Gz.success,
                  onTap: () {},
                ),
                GzPickChip(label: 'c', onTap: () {}),
              ],
            ),
          ),
        ),
      );
      for (final label in ['a', 'b', 'c']) {
        final text = tester.widget<Text>(find.text(label));
        final box = tester.widget<AnimatedContainer>(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(AnimatedContainer),
          ),
        );
        final bg = (box.decoration as BoxDecoration).color!;
        final scaffoldBg = Gz.surface;
        // Мөлдір фонды бет түсімен араластырып, нақты көрінетін түсті аламыз.
        final shown = Color.alphaBlend(bg, scaffoldBg);
        final ratio = _contrast(text.style!.color!, shown);
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason: '«$label» чипінің мәтіні фонында оқылмайды ($ratio:1)',
        );
      }
    });
  }
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}
