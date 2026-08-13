import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:tasu/shared/map_widgets.dart';

/// «Картаны ашу» дегенде карта БОС шығатын ақаудың РЕГРЕССИЯ ҚОРҒАУЫ.
///
/// СЕБЕБІ (Flutter-дің жиі кездесетін тұзағы). `Scaffold` өз `body`-іне
/// БОС (loose) биіктік шектеуін береді: `minHeight = 0`. `Stack` мұндай
/// шектеуде өз өлшемін ПОЗИЦИЯЛАНБАҒАН балаларынан алады. [RouteMapScreen]-де
/// картаның өзі `Positioned.fill` ішінде тұрғандықтан, позицияланбаған жалғыз
/// бала — жоғарғы жолақ болатын. Нәтижесінде бүкіл экран сол жолақтың
/// биіктігіне (≈100 px) жиырылып, карта жіңішке жолаққа айналатын да,
/// `bottom: 10` деп қойылған маршрут панелі экранның ЖОҒАРЫСЫНА шығып кететін.
/// Қалған бөлікті Scaffold фоны толтыратын — қолданушы «бос экран» көретін.
///
/// ТЕКСЕРУ: карта экранның ТОЛЫҚ биіктігін алуы керек, ал маршрут панелі
/// экранның ТӨМЕНГІ жартысында тұруы керек.
void main() {
  const from = LatLng(51.0900, 71.4200);
  const to = LatLng(51.1300, 71.4700);

  Future<Size> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: RouteMapScreen(
          from: from,
          to: to,
          // Дайын геометрия беріледі — тестте желіге сұрау кетпейді.
          routePoints: [from, to],
          fromLabel: 'Абай даңғылы, 10',
          toLabel: 'улица Асан Кайгы, 1/1',
          distanceKm: 8.4,
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
    final screen = await pumpScreen(tester);
    final map = tester.getSize(find.byType(FlutterMap));

    expect(map.height, screen.height,
        reason: 'Карта Scaffold-тың бос шектеуінен жиырылып қалмауы керек');
    expect(map.width, screen.width);
  });

  testWidgets('маршрут панелі экранның ТӨМЕНІНДЕ тұрады', (tester) async {
    final screen = await pumpScreen(tester);
    final sheet = find.text('улица Асан Кайгы, 1/1');

    expect(sheet, findsOneWidget);
    final y = tester.getTopLeft(sheet).dy;
    expect(y, greaterThan(screen.height / 2),
        reason: 'Панель жоғарыға шығып кетпеуі керек');
  });
}
