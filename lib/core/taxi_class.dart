/// Такси САНАТТАРЫ (0098): Эконом / Комфорт / Бизнес.
///
/// Модератор «Баптаулар → Такси бөлімі → Такси санаттары» қосқышын қосқанда
/// таксистер санатқа бөлінеді: жаңа жүргізуші тіркелгенде өзі таңдайды, ал
/// бұрын тіркелгендер көлігінің маркасы/моделі/жылы бойынша модератор
/// енгізген ережелерге сай автомат бөлінеді. Қосқыш өшірулі кезде барлығы
/// бір такси түрі болып қала береді.
library;

import 'package:flutter/material.dart';

import 'lang.dart';
import 'theme.dart';

enum TaxiClass {
  economy('economy', Icons.directions_car_outlined),
  comfort('comfort', Icons.airline_seat_recline_extra_rounded),
  business('business', Icons.workspace_premium_outlined);

  final String code;
  final IconData icon;
  const TaxiClass(this.code, this.icon);

  String get label => switch (this) {
    TaxiClass.economy => t('Эконом'),
    TaxiClass.comfort => t('Комфорт'),
    TaxiClass.business => t('Бизнес'),
  };

  String get hint => switch (this) {
    TaxiClass.economy => t('Қарапайым көлік, қолжетімді баға'),
    TaxiClass.comfort => t('Жайлы, жаңа көлік'),
    TaxiClass.business => t('Жоғары класты көлік'),
  };

  Color get color => switch (this) {
    TaxiClass.economy => Gz.green,
    TaxiClass.comfort => Gz.blue,
    TaxiClass.business => Gz.violet,
  };

  /// Дерекқордағы мәтіннен санат; белгісіз/бос болса — null.
  static TaxiClass? from(String? code) {
    for (final c in TaxiClass.values) {
      if (c.code == code) return c;
    }
    return null;
  }
}
