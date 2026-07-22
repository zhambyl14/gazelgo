import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import 'address_picker.dart';

/// Гест (кірмеген қолданушы) толтырған, бірақ әлі жарияланбаған заказ.
/// «Шақыру» батырмасы басылғанда осы толтырылған дерек сақталады да,
/// қолданушы кіргеннен/тіркелгеннен кейін жоғалмай, автоматты жарияланады.
/// Фотолар байт күйінде сақталады — Storage-қа жүктеу тек кіргеннен кейін
/// (uid қажет) жүреді.
class DraftOrder {
  final PickedAddress from;
  final PickedAddress to;
  final VehicleType vehicle;
  final String cargo;
  final String comment;
  final String priceText;
  final List<Uint8List> photos;
  final bool legalOk;

  DraftOrder({
    required this.from,
    required this.to,
    required this.vehicle,
    required this.cargo,
    required this.comment,
    required this.priceText,
    required this.photos,
    required this.legalOk,
  });
}

/// Кіру аралығында сақталатын жоба заказ (гесттен → кіргеннен кейін жалғасады).
final draftOrderProvider = StateProvider<DraftOrder?>((ref) => null);
