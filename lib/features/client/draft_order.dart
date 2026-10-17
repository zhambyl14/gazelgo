import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import 'address_picker.dart';
import 'order_extras_editor.dart';

/// Гест (кірмеген қолданушы) толтырған, бірақ әлі жарияланбаған заказ.
/// «Шақыру» батырмасы басылғанда осы толтырылған дерек сақталады да,
/// қолданушы кіргеннен/тіркелгеннен кейін жоғалмай, автоматты жарияланады.
/// Фотолар байт күйінде сақталады — Storage-қа жүктеу тек кіргеннен кейін
/// (uid қажет) жүреді.
class DraftOrder {
  final PickedAddress from;
  final PickedAddress to;

  /// Аралық аялдамалар (0047) — гест қосқан мекенжайлар да жоғалмауы керек.
  final List<PickedAddress> stops;
  final VehicleType vehicle;
  final String cargo;
  final String comment;
  final String priceText;
  final List<Uint8List> photos;
  final bool legalOk;

  /// Такси заказындағы жолаушы саны — гест таңдағаны сақталады (әйтпесе
  /// кіргеннен кейін әдепкі мәнмен жарияланып кететін).
  final int passengers;

  /// Қосымша талаптар (0077) мен алушы (0076) — гест толтырғаны да
  /// кіргеннен кейін жоғалмауы керек.
  final OrderExtras extras;
  final String recipientName;
  final String recipientPhone;

  DraftOrder({
    required this.from,
    required this.to,
    this.stops = const [],
    required this.vehicle,
    required this.cargo,
    required this.comment,
    required this.priceText,
    required this.photos,
    required this.legalOk,
    this.passengers = 2,
    this.extras = const OrderExtras(),
    this.recipientName = '',
    this.recipientPhone = '',
  });
}

/// Кіру аралығында сақталатын жоба заказ (гесттен → кіргеннен кейін жалғасады).
final draftOrderProvider = StateProvider<DraftOrder?>((ref) => null);
