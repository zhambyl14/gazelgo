import 'package:flutter_test/flutter_test.dart';
import 'package:tasu/core/models.dart';

/// Ұмай такси (0086): жолаушы тасымалы белгісі және кірістірілген әдепкі
/// жазба (сервер жауап бермесе / миграция әлі қолданылмаса).
void main() {
  test('isPassenger: такси мен Ұмай ғана жолаушы тасымалы', () {
    expect(VehicleType.taxi.isPassenger, isTrue);
    expect(VehicleType.umay.isPassenger, isTrue);
    // Доставка такси санатында, бірақ жүк тасиды.
    expect(VehicleType.delivery.isPassenger, isFalse);
    expect(VehicleType.gazelle.isPassenger, isFalse);
  });

  test('isUmay тек umay кодына ғана тиесілі', () {
    expect(VehicleType.umay.isUmay, isTrue);
    expect(VehicleType.taxi.isUmay, isFalse);
    expect(vehicleTypeFrom('umay'), VehicleType.umay);
  });

  test('кірістірілген umay жазбасы: такси санаты, әдепкіде өшік', () {
    final s = VehicleCatalog.spec('umay');
    expect(s.code, 'umay');
    expect(s.isTaxi, isTrue);
    expect(s.sortOrder, 15);
    expect(s.emoji, '🌸');
    expect(s.labelKk, 'Ұмай такси');
    expect(s.labelRu, 'Умай такси');
    expect(s.builtIn, isTrue);
    // Каталог жүктелмей тұрғанда клиентке көрінбейді.
    expect(s.active, isFalse);
    expect(kTaxiVehicleTypes.contains(VehicleType.umay), isFalse);
  });

  test('withoutUmay орындаушы тізімінен Ұмайды алып тастайды', () {
    final list = [VehicleType.taxi, VehicleType.umay, VehicleType.gazelle];
    expect(list.withoutUmay(), [VehicleType.taxi, VehicleType.gazelle]);
  });

  test('ExecutorProfile.isUmay: баған жоқ болса false', () {
    final base = {'user_id': 'u1'};
    expect(ExecutorProfile.fromMap(base).isUmay, isFalse);
    expect(ExecutorProfile.fromMap({...base, 'is_umay': true}).isUmay, isTrue);
  });
}
