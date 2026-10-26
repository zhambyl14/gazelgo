import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasu/core/car_colors.dart';
import 'package:tasu/shared/ui/kz_plate.dart';

void main() {
  test('splitKzPlate: 237BLM01 → 237 BLM | 01', () {
    for (final raw in ['237BLM01', '237 blm 01', ' 237 BLM 01 ']) {
      final p = splitKzPlate(raw);
      expect(p.main, '237 BLM');
      expect(p.region, '01');
    }
  });

  test('splitKzPlate: таныс емес пішін тұтас қалады', () {
    final p = splitKzPlate('A123BC');
    expect(p.main, 'A123BC');
    expect(p.region, isNull);
  });

  test('carColorFor: код бойынша табады, бос/белгісізге null', () {
    expect(carColorFor('white')?.labelKk, 'Ақ');
    expect(carColorFor(''), isNull);
    expect(carColorFor('nope'), isNull);
    expect(kCarColors.map((c) => c.code).toSet().length, kCarColors.length);
  });

  testWidgets('KzPlate нөмір мен аймақты көрсетеді', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Center(child: KzPlate('237BLM01')))),
    );
    expect(find.text('237 BLM'), findsOneWidget);
    expect(find.text('01'), findsOneWidget);
    expect(find.text('KZ'), findsOneWidget);
  });
}
