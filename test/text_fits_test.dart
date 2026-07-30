import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasu/core/lang.dart';
import 'package:tasu/core/models.dart';
import 'package:tasu/shared/vehicle_picker.dart';
import 'package:tasu/shared/widgets.dart';

/// «Мәтін рамкасына сыймай ЕКІНШІ ЖОЛҒА түсіп кетеді» ақауының
/// РЕГРЕССИЯ ҚОРҒАУЫ.
///
/// Ең қатал жағдай алынады: ТАР экран (320px — шағын телефондар) + жүйе
/// шрифті 1.25× үлкейтілген + ОРЫС тілі (аудармалар қазақшадан ұзын).
/// Осы шартта да тұрақты биіктікті элементтер биіктігін ӨЗГЕРТПЕУІ керек:
/// әйтпесе қатардағы көршісі басқа биіктікте тұрып, бүкіл жол қиқы-жиқы
/// көрінеді («бір нәрсенің кесірінен екіншісі жаман көрінеді»).
///
/// Тексерудің мәні: мәтін ҰЗАРҒАНДА виджет биіктігі ӨСПЕУІ керек —
/// демек мәтін екінші жолға түспей, кішірейіп сыйған.
void main() {
  Widget harness(Widget child, {double width = 320}) => MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(1.25),
              ),
              child: Center(child: SizedBox(width: width, child: child)),
            ),
          ),
        ),
      );

  setUp(() => Lang.current.value = AppLang.ru);
  tearDown(() => Lang.current.value = AppLang.kk);

  testWidgets('BtnLabel: мәтін ұзарса биіктік ӨСПЕЙДІ (кішірейіп сыяды)',
      (tester) async {
    const short = 'Да';
    const long = 'Государственный номер автомобиля и прицепа';

    await tester.pumpWidget(harness(
      const SizedBox(width: 70, child: BtnLabel(short)),
    ));
    final hShort = tester.getSize(find.byType(BtnLabel)).height;

    await tester.pumpWidget(harness(
      const SizedBox(width: 70, child: BtnLabel(long)),
    ));
    final hLong = tester.getSize(find.byType(BtnLabel)).height;

    expect(hLong, lessThanOrEqualTo(hShort),
        reason: 'ұзын жазу екінші жолға түсіп, биіктікті өсірді');
  });

  testWidgets('Санат плиткалары ЕКЕУІ де бірдей биіктікте', (tester) async {
    await tester.pumpWidget(harness(
      VehicleCategoryTabs(
        selected: VehicleCategory.cargo,
        onChanged: (_) {},
      ),
    ));
    final heights = tester
        .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
        .map((w) => tester.getSize(find.byWidget(w)).height)
        .toList();
    expect(heights, hasLength(2));
    expect(heights.toSet(), {VehicleCategoryTabs.tileHeight});

    // ЕҢ МАҢЫЗДЫСЫ: екі жазудың ШРИФТІ БІРДЕЙ болуы керек. FittedBox
    // біреуін кішірейтіп, екіншісін толық қалдырса — қатар қиқы-жиқы
    // көрінеді. Сол себепті жазулар қысқа: екеуі де толық сыяды.
    final sizes = ['Такси', 'Спецтехника']
        .map((s) => tester.getSize(find.text(s)).height)
        .toSet();
    expect(sizes, hasLength(1),
        reason: 'плиткалардың шрифт өлшемі әртүрлі болмауы керек');
  });

  testWidgets('InfoRow: ұзын атау жолды биіктетпейді', (tester) async {
    await tester.pumpWidget(harness(
      const InfoRow('Қала', 'Тараз'),
    ));
    final hShort = tester.getSize(find.byType(InfoRow)).height;

    await tester.pumpWidget(harness(
      // Орысша «Государственный номер» — 132px атау бағанына сыймайтын.
      const InfoRow('Мемлекеттік нөмір', '123 ABC 02'),
    ));
    final hLong = tester.getSize(find.byType(InfoRow)).height;

    expect(hLong, hShort,
        reason: 'ұзын атау екінші жолға түсіп, жолды биіктетті');
  });

  testWidgets('Көлік каруселі: карточка биіктігі атауға тәуелсіз',
      (tester) async {
    await tester.pumpWidget(harness(
      VehicleTypeCarousel(
        selected: VehicleType.gazelle,
        onChanged: (_) {},
      ),
    ));
    // Каруселдегі барлық көрінетін карточка дәл бірдей биіктікте болуы
    // керек — «Ассенизатор»/«Манипулятор» сияқты ұзын атаулар да оны
    // бұзбайды.
    final heights = tester
        .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
        .map((w) => tester.getSize(find.byWidget(w)).height)
        .toSet();
    expect(heights, {VehicleTypeCarousel.cardHeight});
  });

  testWidgets('ConfirmCheck: белгі дөңгелегі мәтінге қарамай 26×26',
      (tester) async {
    await tester.pumpWidget(harness(
      ConfirmCheck(
        value: true,
        auto: true,
        onChanged: (_) {},
        label: const Text('Мой груз законный, запрещённых вещей нет'),
      ),
    ));
    final box = tester.getSize(find.byType(AnimatedContainer).first);
    expect(box, const Size(26, 26));
  });
}
