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

  group('Geo.isJunkLabel', () {
    test('coordinates and letterless text are junk', () {
      expect(Geo.isJunkLabel('43.23890, 76.88970ндю'), isTrue);
      expect(Geo.isJunkLabel('43.2389, 76.8897'), isTrue);
      expect(Geo.isJunkLabel('15'), isTrue);
    });
    test('real addresses are kept', () {
      expect(Geo.isJunkLabel('Абай даңғылы, 15'), isFalse);
      expect(Geo.isJunkLabel('13 мкр 21 дом'), isFalse);
      expect(Geo.isJunkLabel('Europharma'), isFalse);
    });
  });

  group('Geo.formatDistance', () {
    test('metres under 1 km, rounded to 10 m', () {
      expect(Geo.formatDistance(0.853), '850 м');
      expect(Geo.formatDistance(0.001), '10 м');
    });
    test('one decimal with a comma under 100 km', () {
      expect(Geo.formatDistance(12.46), '12,5 км');
      expect(Geo.formatDistance(4), '4,0 км');
    });
    test('whole km from 100 km', () {
      expect(Geo.formatDistance(125.4), '125 км');
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
