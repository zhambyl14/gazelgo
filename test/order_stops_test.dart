import 'package:flutter_test/flutter_test.dart';
import 'package:tasu/core/models.dart';

/// Көп мекенжай (0047) логикасының тесті.
///
/// Ең багқа бейім жері — МЕЖГОРОД анықтау: ол минимум бағаны 100 ₸ → 1000 ₸
/// қылып өзгертеді, әрі орындаушының заказды ала алуына да әсер етеді.
/// Аралық аялдама басқа қалада болса заказ да қалааралық болуы КЕРЕК —
/// әйтпесе клиент қалааралық жүкті қала бағасына бере алатын еді.
Order order({
  String? fromCity,
  String? toCity,
  List<Map<String, dynamic>> stops = const [],
}) => Order.fromMap({
  'id': 'o1',
  'client_id': 'c1',
  'type': 'bidding',
  'status': 'searching',
  'from_address': 'A',
  'to_address': 'B',
  'from_city': fromCity,
  'to_city': toCity,
  'stops': stops,
});

void main() {
  group('Order.stops талдауы', () {
    test('stops жоқ / бос / бүлінген болса — бос тізім (қосымша сынбайды)', () {
      expect(order().stops, isEmpty);
      expect(order(stops: const []).stops, isEmpty);
      // Күтпеген формат келсе де сынбауы керек.
      expect(Order.fromMap({
        'id': 'o1',
        'client_id': 'c1',
        'type': 'bidding',
        'status': 'searching',
        'stops': 'бұл массив емес',
      }).stops, isEmpty);
    });

    test('аялдамалар РЕТІМЕН оқылады', () {
      final o = order(stops: const [
        {'address': 'Абай 1', 'lat': 43.2, 'lng': 76.9, 'city': 'Алматы'},
        {'address': 'Абай 2', 'lat': 43.3, 'lng': 76.8, 'city': 'Алматы'},
      ]);
      expect(o.stops.map((s) => s.address), ['Абай 1', 'Абай 2']);
      expect(o.hasStops, isTrue);
      expect(o.stops.first.lat, 43.2);
    });

    test('routeDisplay: алу → аялдамалар → жеткізу ретімен', () {
      final o = order(
        fromCity: 'Алматы',
        toCity: 'Алматы',
        stops: const [
          {'address': 'Абай 1', 'lat': 43.2, 'lng': 76.9, 'city': 'Алматы'},
        ],
      );
      expect(o.routeDisplay, [
        'Алматы, A',
        'Алматы, Абай 1',
        'Алматы, B',
      ]);
    });
  });

  group('Межгород анықтау (аялдамаларды ескереді)', () {
    test('бір қала ішінде — межгород ЕМЕС', () {
      expect(order(fromCity: 'Алматы', toCity: 'Алматы').intercity, isFalse);
    });

    test('әкімшілік жұрнақ бір қаланы екі қылып көрсетпейді', () {
      expect(
        order(fromCity: 'Тараз', toCity: 'Тараз қаласы').intercity,
        isFalse,
      );
    });

    test('from/to әртүрлі қала — межгород', () {
      expect(order(fromCity: 'Алматы', toCity: 'Тараз').intercity, isTrue);
    });

    test('АЯЛДАМА басқа қалада болса — межгород (негізгі кейс)', () {
      final o = order(
        fromCity: 'Алматы',
        toCity: 'Алматы',
        stops: const [
          {'address': 'Орталық', 'lat': 42.9, 'lng': 71.4, 'city': 'Тараз'},
        ],
      );
      expect(o.intercity, isTrue,
          reason: 'аялдама басқа қалада — қала бағасына берілмеуі керек');
    });

    test('аялдамада қала белгісіз болса — қалғаны бойынша шешіледі', () {
      final o = order(
        fromCity: 'Алматы',
        toCity: 'Алматы',
        stops: const [
          {'address': 'Белгісіз', 'lat': 43.2, 'lng': 76.9},
        ],
      );
      expect(o.intercity, isFalse);
    });

    test('қала мүлдем белгісіз болса — межгород емес (ескі заказдар)', () {
      expect(order().intercity, isFalse);
    });
  });

  group('distinctCities', () {
    test('null/бос елеусіз қалады', () {
      expect(distinctCities([null, '', '  ', 'Алматы']), ['Алматы']);
    });

    test('жұрнақты нұсқалар бір қала болып саналады', () {
      expect(
        distinctCities(['Тараз', 'Тараз қаласы', 'город Тараз']),
        hasLength(1),
      );
    });

    test('шын мәнінде әртүрлі қалалар бөлек саналады', () {
      expect(distinctCities(['Алматы', 'Тараз', 'Астана']), hasLength(3));
    });
  });

  test('kMaxExtraStops сервердегі шектеумен сәйкес (clean_order_stops = 2)',
      () {
    // Серверде `k_max_stops = 2` және `orders_stops_check` да 2. Бұл сан
    // осында өзгерсе — сервер артық аялдаманы TOO_MANY_STOPS деп қайтарады,
    // сол себепті тест екеуін синхронда ұстайды.
    expect(kMaxExtraStops, 2);
  });
}
