/// Көлік түрлерінің КАТАЛОГЫ (0050).
///
/// Бұрын көлік түрі қатып қалған `enum` болатын: жаңа түр қосу үшін код
/// жазып, миграция жасап, қосымшаны қайта шығару керек еді. Енді каталог
/// СЕРВЕРДЕН келеді (`public.vehicle_types`) — модератор өз панелінен түр
/// қоса алады, өшіре алады, ретін ауыстыра алады, иконка жүктей алады және
/// анықтамасын жаза алады. Қосымшаны жаңартудың қажеті жоқ.
///
/// [VehicleType] — жай ғана `code` (мыс. `kamaz`) айналасындағы қабық:
/// ескі `enum`-мен бірдей жазылады (`VehicleType.kamaz`, `v.label`,
/// `v.db`), бірақ мәні жоқ кодтарды да ұстай алады — сол себепті модератор
/// қосқан жаңа түрі бар заказ ЕСКІ қосымшада да дұрыс (тек әдепкі атаумен)
/// көрінеді, `gazelle`-ге айналып кетпейді.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'lang.dart';

// ---------------------------------------------------------------------------
// VehicleType — көлік түрінің КОДЫ
// ---------------------------------------------------------------------------

/// Көлік түрі. Ішінде тек `code` бар; атауы/иконкасы/анықтамасы
/// [VehicleCatalog]-тан ізделеді, демек серверден жаңарып отырады.
@immutable
class VehicleType {
  final String code;
  const VehicleType(this.code);

  // ---- Қосымшамен бірге жеткен түрлер (сервер жауап бермесе де жұмыс
  // істейтін әдепкі тізім). Кодта аты-жөнімен қолданылады. ----
  static const taxi = VehicleType('taxi');
  static const delivery = VehicleType('delivery');
  static const gazelle = VehicleType('gazelle');
  static const manipulator = VehicleType('manipulator');
  static const avtovyshka = VehicleType('avtovyshka');
  static const tractor = VehicleType('tractor');
  static const zil = VehicleType('zil');
  static const kamaz = VehicleType('kamaz');
  static const fura = VehicleType('fura');
  static const tral = VehicleType('tral');
  static const crane = VehicleType('crane');
  static const excavator = VehicleType('excavator');
  static const assenizator = VehicleType('assenizator');
  static const minivan = VehicleType('minivan');
  static const furgon = VehicleType('furgon');
  static const loader = VehicleType('loader');

  /// БАРЛЫҚ белсенді түр (такси санаты + спецтехника), каталог реті бойынша.
  /// Бұрынғы `enum.values`-тың орнында тұр — шақыру орындары өзгермеді.
  static List<VehicleType> get values => VehicleCatalog.active;

  /// `enum.name`-мен үйлесімділік үшін (кейбір жерде `.name` жазылған).
  String get name => code;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is VehicleType && other.code == code);

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => 'VehicleType($code)';
}

/// «Такси» САНАТЫНЫҢ түрлері (такси + доставка) — модератор «Такси»
/// бөлімін қоспайынша клиентке де, орындаушыға да көрінбейді.
List<VehicleType> get kTaxiVehicleTypes => VehicleCatalog.taxiTypes;

/// «Спецтехника» санаты — такси санатына кірмейтіндердің бәрі әрі такси
/// өшулі кездегі әдепкі тізім.
List<VehicleType> get kCargoVehicleTypes => VehicleCatalog.cargoTypes;

/// Дерекқордағы мәтіндік кодты түрге айналдыру. Таныс емес код та
/// САҚТАЛАДЫ (әдепкі `gazelle`-ге айналмайды) — модератор жаңа түр қосқанда
/// ескі қосымша заказды бөтен түрмен шатастырмауы үшін.
VehicleType vehicleTypeFrom(String? s) {
  final code = s?.trim() ?? '';
  return code.isEmpty ? VehicleType.gazelle : VehicleType(code);
}

// ---------------------------------------------------------------------------
// VehicleSpec — түрдің КӨРІНІСІ (атауы, иконкасы, анықтамасы)
// ---------------------------------------------------------------------------

@immutable
class VehicleSpec {
  final String code;
  final String labelKk;
  final String labelRu;
  final String descKk;
  final String descRu;

  /// Модератор жүктеген иконка (Supabase storage сілтемесі). Болса —
  /// [assetIcon]-нан БАСЫМ: модератор кірістірілген суретті де ауыстыра алады.
  final String? iconUrl;

  /// Қосымшамен бірге келген PNG (`assets/vehicles/<code>.png`).
  final String? assetIcon;

  /// Сурет мүлдем жоқта көрсетілетін эмодзи.
  final String emoji;
  final int sortOrder;

  /// «Такси» санатына жата ма (такси/доставка). Спецтехника каруселінде
  /// көрінбейді, бөлек санатта тұрады.
  final bool isTaxi;
  final bool active;

  /// Қосымшамен бірге жеткен (өшіруге болмайтын) түр бе.
  final bool builtIn;

  const VehicleSpec({
    required this.code,
    required this.labelKk,
    this.labelRu = '',
    this.descKk = '',
    this.descRu = '',
    this.iconUrl,
    this.assetIcon,
    this.emoji = '🚚',
    this.sortOrder = 0,
    this.isTaxi = false,
    this.active = true,
    this.builtIn = false,
  });

  String get label =>
      (Lang.current.value == AppLang.ru && labelRu.isNotEmpty) ? labelRu : labelKk;

  String get description =>
      (Lang.current.value == AppLang.ru && descRu.isNotEmpty) ? descRu : descKk;

  factory VehicleSpec.fromMap(Map<String, dynamic> m) {
    final code = (m['code'] ?? '').toString();
    final url = (m['icon_url'] as String?)?.trim();
    return VehicleSpec(
      code: code,
      labelKk: (m['label_kk'] ?? code).toString(),
      labelRu: (m['label_ru'] ?? '').toString(),
      descKk: (m['desc_kk'] ?? '').toString(),
      descRu: (m['desc_ru'] ?? '').toString(),
      iconUrl: (url == null || url.isEmpty) ? null : url,
      // Кірістірілген суретті сервер білмейді — код бойынша табамыз.
      assetIcon: _builtInByCode[code]?.assetIcon,
      emoji: (m['emoji'] ?? '').toString().isEmpty
          ? (_builtInByCode[code]?.emoji ?? '🚚')
          : m['emoji'].toString(),
      sortOrder: (m['sort_order'] as num?)?.toInt() ?? 0,
      isTaxi: m['is_taxi'] == true,
      active: m['active'] != false,
      builtIn: m['built_in'] == true,
    );
  }

  Map<String, dynamic> toMap() => {
        'code': code,
        'label_kk': labelKk,
        'label_ru': labelRu,
        'desc_kk': descKk,
        'desc_ru': descRu,
        'icon_url': iconUrl,
        'emoji': emoji,
        'sort_order': sortOrder,
        'is_taxi': isTaxi,
        'active': active,
        'built_in': builtIn,
      };

  VehicleType get type => VehicleType(code);
}

// ---------------------------------------------------------------------------
// Қосымшамен бірге жеткен әдепкі каталог
// ---------------------------------------------------------------------------

/// ӘДЕПКІ тізім әрі РЕТ. Сервердегі `vehicle_types` кестесі осымен
/// себіледі (0050 миграциясы) және желі жоқта дәл осы тізім көрсетіледі.
///
/// РЕТ (модератор сұрағаны): Такси · Газель · Манипулятор · Автовышка ·
/// Трактор 3в1 · ЗиЛ · КамАЗ · Фура · Трал · Кран · Экскаватор ·
/// Ассенизатор · Мини вэн · Фургон · Погрузчик.
const List<VehicleSpec> kBuiltInVehicleSpecs = [
  VehicleSpec(
    code: 'taxi',
    labelKk: 'Такси',
    labelRu: 'Такси',
    descKk: 'Жолаушы тасымалы',
    descRu: 'Перевозка пассажиров',
    emoji: '🚕',
    sortOrder: 10,
    isTaxi: true,
    builtIn: true,
  ),
  VehicleSpec(
    code: 'delivery',
    labelKk: 'Доставка',
    labelRu: 'Доставка',
    descKk: 'Жеңіл көлікпен ұсақ жүк жеткізу',
    descRu: 'Доставка мелких грузов легковым авто',
    emoji: '📦',
    sortOrder: 20,
    isTaxi: true,
    builtIn: true,
  ),
  VehicleSpec(
    code: 'gazelle',
    labelKk: 'Газель',
    labelRu: 'Газель',
    descKk: 'Әмбебап жүк тасымалы',
    descRu: 'Универсальные грузоперевозки',
    emoji: '🚚',
    sortOrder: 30,
    builtIn: true,
  ),
  VehicleSpec(
    code: 'manipulator',
    labelKk: 'Манипулятор',
    labelRu: 'Манипулятор',
    descKk: 'Кран-манипулятор: тиеу және тасымалдау',
    descRu: 'Кран-манипулятор: погрузка и перевозка',
    assetIcon: 'assets/vehicles/manipulator.png',
    sortOrder: 40,
    builtIn: true,
  ),
  VehicleSpec(
    code: 'avtovyshka',
    labelKk: 'Автовышка',
    labelRu: 'Автовышка',
    descKk: 'Биіктікте жұмыс',
    descRu: 'Работы на высоте',
    assetIcon: 'assets/vehicles/avtovyshka.png',
    sortOrder: 50,
    builtIn: true,
  ),
  VehicleSpec(
    code: 'tractor',
    labelKk: 'Трактор 3в1',
    labelRu: 'Трактор 3в1',
    descKk: 'Әмбебап трактор (3в1)',
    descRu: 'Универсальный трактор (3в1)',
    emoji: '🚜',
    sortOrder: 60,
    builtIn: true,
  ),
  VehicleSpec(
    code: 'zil',
    labelKk: 'ЗиЛ',
    labelRu: 'ЗиЛ',
    descKk: 'Орташа көлемдегі жүк тасымалы: құрылыс, ауыл шаруашылығы',
    descRu: 'Перевозка средних грузов: стройка, село, быт',
    assetIcon: 'assets/vehicles/zil.png',
    sortOrder: 70,
    builtIn: true,
  ),
  VehicleSpec(
    code: 'kamaz',
    labelKk: 'КамАЗ',
    labelRu: 'КамАЗ',
    descKk: 'Ауыр жүк',
    descRu: 'Тяжёлые грузы',
    assetIcon: 'assets/vehicles/kamaz.png',
    sortOrder: 80,
    builtIn: true,
  ),
  VehicleSpec(
    code: 'fura',
    labelKk: 'Фура',
    labelRu: 'Фура',
    descKk: 'Ұзақ қашықтық',
    descRu: 'Дальние расстояния',
    assetIcon: 'assets/vehicles/fura.png',
    sortOrder: 90,
    builtIn: true,
  ),
  VehicleSpec(
    code: 'tral',
    labelKk: 'Трал',
    labelRu: 'Трал',
    descKk: 'Ауыр әрі ірі габаритті техниканы тасымалдау',
    descRu: 'Перевозка тяжёлой и негабаритной техники',
    assetIcon: 'assets/vehicles/tral.png',
    sortOrder: 100,
    builtIn: true,
  ),
  VehicleSpec(
    code: 'crane',
    labelKk: 'Кран',
    labelRu: 'Кран',
    descKk: 'Автокран: жүк көтеру',
    descRu: 'Автокран: подъём грузов',
    assetIcon: 'assets/vehicles/crane.png',
    sortOrder: 110,
    builtIn: true,
  ),
  VehicleSpec(
    code: 'excavator',
    labelKk: 'Экскаватор',
    labelRu: 'Экскаватор',
    descKk: 'Қазу, жер жұмыстары',
    descRu: 'Копка, земляные работы',
    assetIcon: 'assets/vehicles/excavator.png',
    sortOrder: 120,
    builtIn: true,
  ),
  VehicleSpec(
    code: 'assenizator',
    labelKk: 'Ассенизатор',
    labelRu: 'Ассенизатор',
    descKk: 'Сұйық қалдықтарды сору',
    descRu: 'Откачка жидких отходов',
    assetIcon: 'assets/vehicles/assenizator.png',
    sortOrder: 130,
    builtIn: true,
  ),
  VehicleSpec(
    code: 'minivan',
    labelKk: 'Мини вэн',
    labelRu: 'Мини вэн',
    descKk: 'Жолаушы және шағын жүк',
    descRu: 'Пассажиры и небольшой груз',
    assetIcon: 'assets/vehicles/minivan.png',
    sortOrder: 140,
    builtIn: true,
  ),
  VehicleSpec(
    code: 'furgon',
    labelKk: 'Фургон',
    labelRu: 'Фургон',
    descKk: 'Жабық жүк тасымалы',
    descRu: 'Закрытые грузоперевозки',
    emoji: '🚐',
    sortOrder: 150,
    builtIn: true,
  ),
  VehicleSpec(
    code: 'loader',
    labelKk: 'Погрузчик',
    labelRu: 'Погрузчик',
    descKk: 'Тиегіш: тиеу, құрылыс жұмыстары',
    descRu: 'Погрузчик: погрузка, стройработы',
    assetIcon: 'assets/vehicles/loader.png',
    sortOrder: 160,
    builtIn: true,
  ),
];

final Map<String, VehicleSpec> _builtInByCode = {
  for (final s in kBuiltInVehicleSpecs) s.code: s,
};

// ---------------------------------------------------------------------------
// VehicleCatalog — ағымдағы каталог
// ---------------------------------------------------------------------------

/// Каталогтың ағымдағы күйі. Серверден жүктелгенше (немесе желі жоқта)
/// [kBuiltInVehicleSpecs] қолданылады, сол себепті ЕШҚАШАН бос болмайды.
///
/// [revision] — каталог жаңарғанда артатын санауыш: UI оны
/// `ValueListenableBuilder`-мен тыңдап, өзін қайта салады ([Lang] сияқты).
class VehicleCatalog {
  VehicleCatalog._();

  static const _kCacheKey = 'vehicle_catalog_v1';

  static final ValueNotifier<int> revision = ValueNotifier(0);

  static List<VehicleSpec> _all = kBuiltInVehicleSpecs;
  static Map<String, VehicleSpec> _byCode = Map.of(_builtInByCode);

  /// БАРЛЫҚ жазба — өшірулілерін қоса (тек модератор экранына керек).
  static List<VehicleSpec> get allSpecs => _all;

  /// Белсенді түрлер (такси санаты + спецтехника), рет бойынша.
  static List<VehicleType> get active => [
        for (final s in _all)
          if (s.active) s.type,
      ];

  static List<VehicleType> get taxiTypes => [
        for (final s in _all)
          if (s.active && s.isTaxi) s.type,
      ];

  static List<VehicleType> get cargoTypes => [
        for (final s in _all)
          if (s.active && !s.isTaxi) s.type,
      ];

  /// Код бойынша сипаттама. Каталогта жоқ код (мыс. модератор кейін өшірген
  /// түрмен берілген ескі заказ) үшін де БОС ЕМЕС жазба қайтарады — UI
  /// ешқашан құламайды.
  static VehicleSpec spec(String code) =>
      _byCode[code] ??
      _builtInByCode[code] ??
      VehicleSpec(code: code, labelKk: code, emoji: '🚚');

  static void _apply(List<VehicleSpec> specs) {
    if (specs.isEmpty) return;
    final sorted = [...specs]..sort((a, b) {
        final c = a.sortOrder.compareTo(b.sortOrder);
        return c != 0 ? c : a.code.compareTo(b.code);
      });
    _all = List.unmodifiable(sorted);
    _byCode = {for (final s in sorted) s.code: s};
    revision.value++;
  }

  /// Серверден жүктеу. Қате болса — соңғы сақталған (не кірістірілген)
  /// каталог қалады: экрандар ешқашан бос көлік тізімін көрмейді.
  ///
  /// [fetch] — деректі әкелетін функция (Repo-ға тәуелділік болмас үшін
  /// параметр арқылы беріледі).
  static Future<void> load(
    Future<List<Map<String, dynamic>>> Function() fetch,
  ) async {
    try {
      final rows = await fetch();
      final specs = [for (final r in rows) VehicleSpec.fromMap(r)];
      if (specs.isEmpty) return;
      _apply(specs);
      await _saveCache(specs);
    } catch (_) {
      // үнсіз: кэш/әдепкі тізіммен жұмыс жалғаса береді
    }
  }

  /// Құрылғыдағы кэштен қалпына келтіру — қосымша ашылған бойда, желі
  /// жауабын күтпей, өткен рет көрген тізімді көрсету үшін.
  static Future<void> restoreCache() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_kCacheKey);
      if (raw == null || raw.isEmpty) return;
      final list = (jsonDecode(raw) as List)
          .map((e) => VehicleSpec.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
      _apply(list);
    } catch (_) {}
  }

  static Future<void> _saveCache(List<VehicleSpec> specs) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
        _kCacheKey,
        jsonEncode([for (final s in specs) s.toMap()]),
      );
    } catch (_) {}
  }
}

// ---------------------------------------------------------------------------
// VehicleTypeX — ескі кодпен үйлесімді қысқа қатынас
// ---------------------------------------------------------------------------

extension VehicleTypeX on VehicleType {
  VehicleSpec get spec => VehicleCatalog.spec(code);

  /// Дерекқорға жазылатын мән.
  String get db => code;

  String get label => spec.label;

  String get description => spec.description;

  /// Модератор жүктеген иконканың сілтемесі (болса).
  String? get iconUrl => spec.iconUrl;

  /// Қосымшамен бірге келген PNG (болса).
  String? get pngAsset => spec.assetIcon;

  String get emoji => spec.emoji;

  /// «Такси» санатына жата ма.
  bool get isTaxiCategory => spec.isTaxi;
}
