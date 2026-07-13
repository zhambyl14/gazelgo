import 'package:flutter_test/flutter_test.dart';
import 'package:tasu/core/phone.dart';

// Backend-ке тәуелсіз, детерминирленген тесттер (CI-де әрқашан жасыл).
// Бұрынғы boot-тест env-тің «бапталмаған» күйіне сүйенетін, ол енді
// нақты anon key қосылғандықтан жарамсыз болды.
void main() {
  group('Phone.normalize', () {
    test('accepts +7 / 8 / 10-digit forms', () {
      expect(Phone.normalize('+7 700 123 45 67'), '77001234567');
      expect(Phone.normalize('8 (700) 123-45-67'), '77001234567');
      expect(Phone.normalize('7001234567'), '77001234567');
    });

    test('rejects non-KZ and malformed numbers', () {
      expect(Phone.normalize('+7 900 123 45 67'), isNull); // ресейлік 79...
      expect(Phone.normalize('123'), isNull);
      expect(Phone.normalize(''), isNull);
    });
  });

  test('Phone.pretty formats a valid number', () {
    expect(Phone.pretty('87001234567'), '+7 700 123 45 67');
  });

  test('Phone.emailOf builds the synthetic email', () {
    expect(Phone.emailOf('7001234567'), '77001234567@phone.gazelgo.kz');
    expect(Phone.emailOf('bad'), isNull);
  });

  test('Phone.isValid mirrors normalize', () {
    expect(Phone.isValid('+7 700 123 45 67'), isTrue);
    expect(Phone.isValid('+7 900 123 45 67'), isFalse);
  });
}
