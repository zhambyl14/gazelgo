import 'package:flutter_test/flutter_test.dart';
import 'package:tasu/core/models.dart';

/// 0092: көлік түріне «км-ге минималды сома» және такси статус атаулары.
/// Формула серверлік `vehicle_min_price` функциясымен бірдей болуы тиіс.
void main() {
  VehicleSpec spec({bool on = true, int perKm = 100}) => VehicleSpec(
    code: 'taxi',
    labelKk: 'Такси',
    minPerKmEnabled: on,
    minPerKm: perKm,
  );

  group('VehicleSpec.minPriceFor', () {
    test('10 км × 100 ₸ = 1000 ₸', () {
      expect(spec().minPriceFor(10), 1000);
    });

    test('10 ₸-ге жоғары қарай дөңгелектенеді', () {
      // 10.33 км × 100 = 1033 → 1040
      expect(spec().minPriceFor(10.33), 1040);
      // double қатесі (10.3 × 100 = 1030.0000000000002) бағаны өсірмейді
      expect(spec().minPriceFor(10.3), 1030);
    });

    test('қосқыш өшік не мәні 0 не км жоқ — минимум жоқ', () {
      expect(spec(on: false).minPriceFor(10), 0);
      expect(spec(perKm: 0).minPriceFor(10), 0);
      expect(spec().minPriceFor(0), 0);
    });

    test('fromMap/toMap бұрынғы қатарларда да жұмыс істейді', () {
      final old = VehicleSpec.fromMap({'code': 'gazelle', 'label_kk': 'Газель'});
      expect(old.minPerKmEnabled, isFalse);
      expect(old.minPerKm, 0);
      final withMin = VehicleSpec.fromMap({
        'code': 'taxi',
        'label_kk': 'Такси',
        'min_per_km_enabled': true,
        'min_per_km': 100,
      });
      expect(withMin.minPriceFor(10), 1000);
      expect(VehicleSpec.fromMap(withMin.toMap()).minPerKm, 100);
    });
  });

  group('statusLabel: такси логикасы', () {
    test('такси заказында жүргізуші/сапар сөздігі', () {
      expect(statusLabel('accepted', vehicleType: VehicleType.taxi),
          'Жүргізуші жолда');
      expect(statusLabel('arrived', vehicleType: VehicleType.taxi),
          'Жүргізуші келді');
      expect(statusLabel('loading', vehicleType: VehicleType.umay),
          'Жолаушы отырды');
      expect(statusLabel('in_transit', vehicleType: VehicleType.taxi), 'Сапарда');
      expect(statusLabel('completed', vehicleType: VehicleType.taxi),
          'Сапар аяқталды');
    });

    test('жүк заказында бұрынғы сөздік өзгермейді', () {
      expect(statusLabel('arrived', vehicleType: VehicleType.gazelle),
          'Орындаушы келді');
      expect(statusLabel('in_transit', vehicleType: VehicleType.delivery),
          'Тасымалдауда');
      expect(statusLabel('completed'), 'Аяқталды');
    });

    test('tripSteps: екі тізім де 5 сатыдан тұрады', () {
      expect(tripSteps(taxi: true).length, 5);
      expect(tripSteps(taxi: false).length, 5);
      expect(tripSteps(taxi: true).map((s) => s.$1),
          tripSteps(taxi: false).map((s) => s.$1));
    });
  });
}
