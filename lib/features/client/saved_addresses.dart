import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/lang.dart';
import 'address_picker.dart';

/// Сақталған мекенжай түрі — иконка мен әдепкі атауды анықтайды.
enum SavedAddressKind { home, work, other }

/// Клиент сақтаған, жиі қолданылатын мекенжай (үй, жұмыс, т.б.).
/// Құрылғыда SharedPreferences-те JSON күйінде сақталады — сервер
/// миграциясы қажет емес, интернетсіз де жұмыс істейді.
class SavedAddress {
  final String id;
  final SavedAddressKind kind;

  /// «Басқа» түрі үшін клиент жазған өз атауы. Үй/жұмыс үшін бос —
  /// көрсетілетін атау [savedAddressTitle] арқылы тілге сай есептеледі.
  final String label;
  final String address; // көше, үй нөмірі
  final double lat;
  final double lng;
  final String? city;

  /// «Негізгі мекенжай» — жаңа заказ ашылғанда бірінші болып ұсынылады.
  final bool isPrimary;

  const SavedAddress({
    required this.id,
    required this.kind,
    required this.label,
    required this.address,
    required this.lat,
    required this.lng,
    this.city,
    this.isPrimary = false,
  });

  LatLng get point => LatLng(lat, lng);

  PickedAddress toPicked() => PickedAddress(address, point, city);

  SavedAddress copyWith({
    SavedAddressKind? kind,
    String? label,
    String? address,
    double? lat,
    double? lng,
    String? city,
    bool? isPrimary,
  }) => SavedAddress(
    id: id,
    kind: kind ?? this.kind,
    label: label ?? this.label,
    address: address ?? this.address,
    lat: lat ?? this.lat,
    lng: lng ?? this.lng,
    city: city ?? this.city,
    isPrimary: isPrimary ?? this.isPrimary,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'label': label,
    'address': address,
    'lat': lat,
    'lng': lng,
    'city': city,
    'primary': isPrimary,
  };

  factory SavedAddress.fromJson(Map<String, dynamic> j) => SavedAddress(
    id: j['id'] as String,
    kind: SavedAddressKind.values.firstWhere(
      (e) => e.name == j['kind'],
      orElse: () => SavedAddressKind.other,
    ),
    label: (j['label'] as String?) ?? '',
    address: (j['address'] as String?) ?? '',
    lat: (j['lat'] as num).toDouble(),
    lng: (j['lng'] as num).toDouble(),
    city: j['city'] as String?,
    isPrimary: (j['primary'] as bool?) ?? false,
  );
}

/// Түріне сай иконка.
IconData savedAddressIcon(SavedAddressKind k) => switch (k) {
  SavedAddressKind.home => Icons.home_rounded,
  SavedAddressKind.work => Icons.work_rounded,
  SavedAddressKind.other => Icons.push_pin_rounded,
};

/// Түрдің әдепкі атауы (ағымдағы тілде).
String savedAddressKindLabel(SavedAddressKind k) => switch (k) {
  SavedAddressKind.home => t('Үй'),
  SavedAddressKind.work => t('Жұмыс'),
  SavedAddressKind.other => t('Басқа'),
};

/// Мекенжайдың көрсетілетін атауы: үй/жұмыс — тілге сай, «басқа» — өз атауы.
String savedAddressTitle(SavedAddress a) =>
    a.kind == SavedAddressKind.other && a.label.trim().isNotEmpty
    ? a.label.trim()
    : savedAddressKindLabel(a.kind);

/// Клиенттің мекенжай кітапшасы: сақталған + соңғы қолданылған мекенжайлар.
/// Барлығы құрылғыда (SharedPreferences) — бэкенд өзгерісін қажет етпейді.
class AddressBook {
  static const _kSaved = 'client_saved_addresses_v1';
  static const _kRecent = 'client_recent_addresses_v1';
  static const _recentMax = 8;

  // ---------------- Сақталған мекенжайлар ----------------

  /// Барлық сақталған мекенжай. Негізгісі әрдайым бірінші тұрады.
  static Future<List<SavedAddress>> saved() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kSaved);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = (jsonDecode(raw) as List)
          .map((e) => SavedAddress.fromJson(e as Map<String, dynamic>))
          .toList();
      list.sort((a, b) => (b.isPrimary ? 1 : 0) - (a.isPrimary ? 1 : 0));
      return list;
    } catch (_) {
      return [];
    }
  }

  static Future<void> _writeSaved(List<SavedAddress> list) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _kSaved,
      jsonEncode(list.map((e) => e.toJson()).toList()),
    );
  }

  /// Мекенжай қосу не бар мекенжайды жаңарту (id бойынша).
  /// Жаңасы негізгі болса — қалғандарының негізгі белгісі өшеді.
  static Future<void> addOrUpdate(SavedAddress a) async {
    final list = await saved();
    final idx = list.indexWhere((e) => e.id == a.id);
    if (idx >= 0) {
      list[idx] = a;
    } else {
      list.add(a);
    }
    if (a.isPrimary) {
      for (var i = 0; i < list.length; i++) {
        if (list[i].id != a.id && list[i].isPrimary) {
          list[i] = list[i].copyWith(isPrimary: false);
        }
      }
    }
    await _writeSaved(list);
  }

  static Future<void> remove(String id) async {
    final list = await saved();
    list.removeWhere((e) => e.id == id);
    await _writeSaved(list);
  }

  /// Бір ғана мекенжайды негізгі етеді (қалғандары автоматты түрде өшеді).
  static Future<void> setPrimary(String id) async {
    final list = await saved();
    for (var i = 0; i < list.length; i++) {
      list[i] = list[i].copyWith(isPrimary: list[i].id == id);
    }
    await _writeSaved(list);
  }

  static Future<SavedAddress?> primary() async {
    for (final a in await saved()) {
      if (a.isPrimary) return a;
    }
    return null;
  }

  // ---------------- Соңғы (тарихтағы) мекенжайлар ----------------

  static Future<List<PickedAddress>> recent() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kRecent);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List).map((e) {
        final m = e as Map<String, dynamic>;
        return PickedAddress(
          (m['a'] as String?) ?? '',
          LatLng((m['lat'] as num).toDouble(), (m['lng'] as num).toDouble()),
          m['city'] as String?,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  static String _recentKey(PickedAddress x) =>
      '${x.address.trim().toLowerCase()}|${(x.city ?? '').trim().toLowerCase()}';

  /// Заказ берілген мекенжайды тарихқа қосады: соңғысы — бірінші,
  /// қайталанбайды, ең көбі [_recentMax] сақталады.
  static Future<void> pushRecent(PickedAddress a) async {
    if (a.address.trim().isEmpty) return;
    final list = await recent();
    list.removeWhere((e) => _recentKey(e) == _recentKey(a));
    list.insert(0, a);
    final trimmed = list.take(_recentMax).toList();
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _kRecent,
      jsonEncode(
        trimmed
            .map(
              (e) => {
                'a': e.address,
                'lat': e.point.latitude,
                'lng': e.point.longitude,
                'city': e.city,
              },
            )
            .toList(),
      ),
    );
  }
}
