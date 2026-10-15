import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:tasu/core/geo.dart';

GeoPlace place(String name, {String? district}) =>
    GeoPlace(name: name, point: const LatLng(43.2, 76.9), district: district);

void main() {
  group('Geo.parseStreetQuery', () {
    test('splits street stem and house number', () {
      final q = Geo.parseStreetQuery('Абая 15');
      expect(q.number, '15');
      expect(q.key, 'аба');
      expect(q.hasStreetWord, isFalse);
    });

    test('detects street words and letter/slash house numbers', () {
      final q = Geo.parseStreetQuery('ул. Толе би 59/1');
      expect(q.number, '59/1');
      expect(q.hasStreetWord, isTrue);
      expect(q.key, 'тол');
    });

    test('no stem for a bare number', () {
      final q = Geo.parseStreetQuery('15');
      expect(q.key, isNull);
      expect(q.number, '15');
    });
  });

  group('Geo.placeMatches', () {
    test('Russian genitive matches Kazakh street name', () {
      final key = Geo.parseStreetQuery('Абая 15').key!;
      expect(Geo.placeMatches(place('Абай даңғылы, 15'), key), isTrue);
    });

    test('a different street is NOT a match (the real bug)', () {
      final key = Geo.parseStreetQuery('Абая 15').key!;
      expect(
        Geo.placeMatches(place('Әзірбайжан Мәмбетов көшесі, 15'), key),
        isFalse,
      );
    });

    test('Kazakh letters fold to Russian ones', () {
      expect(
        Geo.placeMatches(
          place('Райымбек даңғылы, 150'),
          Geo.parseStreetQuery('Райымбека 150').key!,
        ),
        isTrue,
      );
      expect(
        Geo.placeMatches(
          place('Төле би көшесі, 59'),
          Geo.parseStreetQuery('Толе би 59').key!,
        ),
        isTrue,
      );
      expect(
        Geo.placeMatches(
          place('Достық даңғылы, 5'),
          Geo.parseStreetQuery('Достык 5').key!,
        ),
        isTrue,
      );
    });
  });
}
