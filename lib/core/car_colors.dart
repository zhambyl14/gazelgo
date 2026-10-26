/// Көліктің түсі (0093). Дерекқорға тек КОД жазылады (`white`, `black`…) —
/// атауы тілге қарай көрсетіледі, түс үлгісі осы жерде тұр.
library;

import 'dart:ui' show Color;

import 'lang.dart';

class CarColor {
  final String code;
  final String labelKk;
  final String labelRu;
  final Color color;
  const CarColor(this.code, this.labelKk, this.labelRu, this.color);

  String get label => Lang.current.value == AppLang.ru ? labelRu : labelKk;
}

const List<CarColor> kCarColors = [
  CarColor('white', 'Ақ', 'Белый', Color(0xFFFFFFFF)),
  CarColor('black', 'Қара', 'Чёрный', Color(0xFF1A1A1A)),
  CarColor('silver', 'Күміс', 'Серебристый', Color(0xFFC0C4CA)),
  CarColor('gray', 'Сұр', 'Серый', Color(0xFF8A8F98)),
  CarColor('blue', 'Көк', 'Синий', Color(0xFF1F4FBF)),
  CarColor('lightblue', 'Көгілдір', 'Голубой', Color(0xFF5BB5F0)),
  CarColor('red', 'Қызыл', 'Красный', Color(0xFFD62828)),
  CarColor('burgundy', 'Бордо', 'Бордовый', Color(0xFF7A1B2B)),
  CarColor('green', 'Жасыл', 'Зелёный', Color(0xFF2E8B4F)),
  CarColor('yellow', 'Сары', 'Жёлтый', Color(0xFFF6C900)),
  CarColor('orange', 'Қызғылт сары', 'Оранжевый', Color(0xFFF28C1E)),
  CarColor('brown', 'Қоңыр', 'Коричневый', Color(0xFF6B4423)),
  CarColor('beige', 'Бежевый', 'Бежевый', Color(0xFFD9C7A3)),
  CarColor('purple', 'Күлгін', 'Фиолетовый', Color(0xFF7B3FA0)),
  CarColor('pink', 'Қызғылт', 'Розовый', Color(0xFFF08BB4)),
  CarColor('gold', 'Алтын', 'Золотистый', Color(0xFFC9A227)),
];

/// Код бойынша түс; белгісіз/бос код үшін `null` (UI түсті көрсетпейді).
CarColor? carColorFor(String? code) {
  if (code == null || code.isEmpty) return null;
  for (final c in kCarColors) {
    if (c.code == code) return c;
  }
  return null;
}
