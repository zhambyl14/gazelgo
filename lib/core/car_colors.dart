/// Көліктің түсі (0093). Дерекқорға тек КОД жазылады (`white`, `black`…) —
/// атауы тілге қарай көрсетіледі, түс үлгісі осы жерде тұр.
library;

import 'dart:ui' show Color;

import 'lang.dart';
import 'theme.dart';

class CarColor {
  final String code;
  final String labelKk;
  final String labelRu;
  final Color color;
  const CarColor(this.code, this.labelKk, this.labelRu, this.color);

  String get label => Lang.current.value == AppLang.ru ? labelRu : labelKk;
}

const List<CarColor> kCarColors = [
  CarColor('white', 'Ақ', 'Белый', GzCar.white),
  CarColor('black', 'Қара', 'Чёрный', GzCar.black),
  CarColor('silver', 'Күміс', 'Серебристый', GzCar.silver),
  CarColor('gray', 'Сұр', 'Серый', GzCar.gray),
  CarColor('blue', 'Көк', 'Синий', GzCar.blue),
  CarColor('lightblue', 'Көгілдір', 'Голубой', GzCar.lightBlue),
  CarColor('red', 'Қызыл', 'Красный', GzCar.red),
  CarColor('burgundy', 'Бордо', 'Бордовый', GzCar.burgundy),
  CarColor('green', 'Жасыл', 'Зелёный', GzCar.green),
  CarColor('yellow', 'Сары', 'Жёлтый', GzCar.yellow),
  CarColor('orange', 'Қызғылт сары', 'Оранжевый', GzCar.orange),
  CarColor('brown', 'Қоңыр', 'Коричневый', GzCar.brown),
  CarColor('beige', 'Бежевый', 'Бежевый', GzCar.beige),
  CarColor('purple', 'Күлгін', 'Фиолетовый', GzCar.purple),
  CarColor('pink', 'Қызғылт', 'Розовый', GzCar.pink),
  CarColor('gold', 'Алтын', 'Золотистый', GzCar.gold),
];

/// Код бойынша түс; белгісіз/бос код үшін `null` (UI түсті көрсетпейді).
CarColor? carColorFor(String? code) {
  if (code == null || code.isEmpty) return null;
  for (final c in kCarColors) {
    if (c.code == code) return c;
  }
  return null;
}
