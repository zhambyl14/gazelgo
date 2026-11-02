import 'package:flutter_test/flutter_test.dart';
import 'package:tasu/core/models.dart';
import 'package:tasu/core/taxi_class.dart';

/// 0098: такси санаттары (Эконом / Комфорт / Бизнес).
void main() {
  test('TaxiClass.from коды бойынша табады, белгісізде null', () {
    expect(TaxiClass.from('economy'), TaxiClass.economy);
    expect(TaxiClass.from('comfort'), TaxiClass.comfort);
    expect(TaxiClass.from('business'), TaxiClass.business);
    expect(TaxiClass.from('vip'), isNull);
    expect(TaxiClass.from(null), isNull);
  });

  test('ExecutorProfile.taxiClass бағаны жоқ серверде null', () {
    final ep = ExecutorProfile.fromMap({
      'user_id': 'u1',
      'vehicle_type': 'taxi',
    });
    expect(ep.taxiClass, isNull);
    final withClass = ExecutorProfile.fromMap({
      'user_id': 'u1',
      'vehicle_type': 'taxi',
      'taxi_class': 'comfort',
    });
    expect(withClass.taxiClass, 'comfort');
  });
}
