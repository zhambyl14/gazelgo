import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:tasu/shared/map_widgets.dart';

/// [RouteMapScreen] — толық экранды маршрут картасының РЕГРЕССИЯ ҚОРҒАУЫ.
///
/// 1) ОРНАЛАСУ. `Scaffold` өз `body`-іне БОС (loose) биіктік шектеуін
///    береді: `minHeight = 0`. `Stack` мұндай шектеуде өз өлшемін
///    ПОЗИЦИЯЛАНБАҒАН балаларынан алады. Картаның өзі `Positioned.fill`
///    ішінде тұрғандықтан, позицияланбаған жалғыз бала — жоғарғы жолақ
///    болатын. Нәтижесінде бүкіл экран сол жолақтың биіктігіне (≈100 px)
///    жиырылып, карта жіңішке жолаққа айналатын да, `bottom: 10` деп
///    қойылған панель экранның ЖОҒАРЫСЫНА шығып кететін. Қалған бөлікті
///    Scaffold фоны толтыратын — қолданушы «бос экран» көретін.
///
/// 2) ҚАЙТАЛАНБАУ. Бір беттегі бір ақпарат ЕКІ РЕТ жазылмауы керек:
///    тақырып жолағында «Маршрут» тұрса, төменгі жолақ та «Маршрут» деп
///    тұрмауы тиіс; маршрут белгісі де бір-ақ рет көрінуі керек; аялдама
///    САНЫ тізім ашық тұрғанда (аялдамалардың өзі тізіліп тұрғанда)
///    қайталанбауы керек.
void main() {
  const from = LatLng(51.0900, 71.4200);
  const to = LatLng(51.1300, 71.4700);
  const stopA = LatLng(51.1000, 71.4300);
  const stopB = LatLng(51.1150, 71.4500);

  /// Экранды нақты телефон өлшемінде тұрғызады.
  ///
  /// [routePoints] ӘРҚАШАН беріледі — сонда экран OSRM-ге сұрау жібермейді
  /// (тест желіге тәуелді болмайды).
  Future<Size> pump(
    WidgetTester tester, {
    double? distanceKm = 8.4,
    List<LatLng> stops = const [],
    List<String> stopLabels = const [],
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: RouteMapScreen(
          from: from,
          to: to,
          stops: stops,
          routePoints: const [from, to],
          fromLabel: 'Абай даңғылы, 10',
          toLabel: 'улица Асан Кайгы, 1/1',
          stopLabels: stopLabels,
          distanceKm: distanceKm,
        ),
      ),
    );
    // Панель өлшеніп, камера кадрланатын кадрларды өткіземіз.
    await tester.pump();
    await tester.pump();
    return tester.getSize(find.byType(RouteMapScreen));
  }

  testWidgets('карта экранның ТОЛЫҚ биіктігін алады (жиырылмайды)', (
    tester,
  ) async {
    final screen = await pump(tester);
    final map = tester.getSize(find.byType(FlutterMap));

    expect(
      map.height,
      screen.height,
      reason: 'Карта Scaffold-тың бос шектеуінен жиырылып қалмауы керек',
    );
    expect(map.width, screen.width);
  });

  testWidgets('маршрут панелі экранның ТӨМЕНІНДЕ тұрады', (tester) async {
    final screen = await pump(tester);
    final sheet = find.text('улица Асан Кайгы, 1/1');

    expect(sheet, findsOneWidget);
    expect(
      tester.getTopLeft(sheet).dy,
      greaterThan(screen.height / 2),
      reason: 'Панель жоғарыға шығып кетпеуі керек',
    );
  });

  testWidgets('«Маршрут» сөзі де, белгісі де бір-ақ рет көрінеді', (
    tester,
  ) async {
    // Қашықтық белгісіз — бұрын дәл осындайда төменгі жолақ та «Маршрут»
    // деп тұратын да, сөз бір бетте екі рет қайталанатын.
    await pump(tester, distanceKm: null);

    expect(find.text('Маршрут'), findsOneWidget);
    expect(find.byIcon(Icons.route_rounded), findsOneWidget);
  });

  testWidgets('аялдама САНЫ тізім ашық тұрғанда қайталанбайды', (tester) async {
    await pump(
      tester,
      stops: const [stopA, stopB],
      stopLabels: const ['Бірінші аялдама', 'Екінші аялдама'],
    );

    // Тізім АШЫҚ: аялдамалар нөмірленіп тұр — санын қайта жазудың қажеті жоқ.
    expect(find.textContaining('+2'), findsNothing);

    // Тізімді жинаймыз — енді сан ЖАЛҒЫЗ көрсеткіш, сондықтан шығуы керек.
    await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
    await tester.pumpAndSettle();

    expect(find.textContaining('+2'), findsOneWidget);
  });
}
