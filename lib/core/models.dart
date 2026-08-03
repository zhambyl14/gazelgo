/// GazelGo модельдері — Supabase кестелерінің Dart көрінісі.
library;

import 'geo.dart';
import 'lang.dart';
import 'vehicle_catalog.dart';

/// Көлік түрлері 0050-ден бастап БӨЛЕК файлда (модератор басқаратын
/// динамикалық каталог). Ескі `import 'models.dart'` жазған экрандардың
/// бәрі баяғыдай жұмыс істеуі үшін осы жерден қайта экспортталады.
export 'vehicle_catalog.dart';

DateTime? _dt(dynamic v) =>
    v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

/// Дисплейге арналған адрес: қала белгілі болса «Қала, көше» түрінде.
String _cityAddr(String? city, String addr) =>
    (city == null || city.isEmpty) ? addr : '$city, $addr';

/// Realtime numeric мәндерді string түрінде жіберуі мүмкін — екеуіне де төзімді.
int _i(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toInt();
  return num.tryParse(v.toString())?.toInt() ?? 0;
}

double _d(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return num.tryParse(v.toString())?.toDouble() ?? 0;
}

// ---------- Order status ----------
const kActiveOrderStatuses = [
  'searching',
  'accepted',
  'arrived',
  'loading',
  'in_transit',
];

/// [vehicleType] тек 'loading' статусын нақтылау үшін қажет: такси
/// (жолаушы тасымалы) заказында «Тиеу» орнына «Отырғызу» дұрысырақ —
/// жолаушы жүк емес. Қалған түрлерге (жеткізу, спецтехника) әсер етпейді.
String statusLabel(String s, {VehicleType? vehicleType}) => switch (s) {
  'searching' => t('Іздеуде'),
  'accepted' => t('Қабылданды · жолда'),
  'arrived' => t('Орындаушы келді'),
  'loading' => vehicleType == VehicleType.taxi
      ? t('Отырғызу жүріп жатыр')
      : t('Тиеу жүріп жатыр'),
  'in_transit' => t('Тасымалдауда'),
  'completed' => t('Аяқталды'),
  'cancelled' => t('Бас тартылды'),
  'expired' => t('Мерзімі өтті'),
  _ => s,
};

// ---------- Profile ----------
class Profile {
  final String id;

  /// БЕЛСЕНДІ рөл: client | executor | moderator. Қос рөлде (0046) бұл —
  /// қазір қай режимде отырғаны; [hasClientRole]/[hasExecutorRole] қандай
  /// рөлдер ашылғанын көрсетеді.
  final String role;
  final String fullName;
  final String phone;
  final String? avatarUrl;

  /// БЕЛСЕНДІ рөлдің рейтингі (сервер айна ретінде ұстайды).
  final double rating;
  final int ratingCount;
  final int trips;
  final int trustScore;
  final DateTime? blockedAt;
  final String? blockReason;

  // ---- қос рөл (0046) ----
  final bool hasClientRole;
  final bool hasExecutorRole;
  final double clientRating;
  final int clientRatingCount;
  final int clientTrips;
  final double executorRating;
  final int executorRatingCount;
  final int executorTrips;

  /// 0046 миграциясы қолданылған ба (рөлге бөлінген бағандар келді ме).
  /// Қолданылмаған болса [ratingAs] ескі жалғыз рейтингті қайтарады — ескі
  /// backend-пен қосымша «жаңа» деп бос рейтинг көрсетіп қалмайды.
  final bool _dualRole;

  Profile.fromMap(Map<String, dynamic> m)
    : id = m['id'] as String,
      role = m['role'] as String? ?? 'client',
      fullName = m['full_name'] as String? ?? '',
      phone = m['phone'] as String? ?? '',
      avatarUrl = m['avatar_url'] as String?,
      rating = _d(m['rating']),
      ratingCount = _i(m['rating_count']),
      trips = _i(m['trips']),
      trustScore = m['trust_score'] == null ? 100 : _i(m['trust_score']),
      blockedAt = _dt(m['blocked_at']),
      blockReason = m['block_reason'] as String?,
      // Миграция әлі қолданылмаған болса — ағымдағы рөлден шығарамыз
      // (қосымша ескі backend-пен де сынбай жұмыс істейді).
      hasClientRole =
          m['has_client_role'] as bool? ?? (m['role'] as String?) != 'executor',
      hasExecutorRole =
          m['has_executor_role'] as bool? ?? (m['role'] as String?) == 'executor',
      clientRating = _d(m['client_rating']),
      clientRatingCount = _i(m['client_rating_count']),
      clientTrips = _i(m['client_trips']),
      executorRating = _d(m['executor_rating']),
      executorRatingCount = _i(m['executor_rating_count']),
      executorTrips = _i(m['executor_trips']),
      _dualRole = m.containsKey('client_rating');

  bool get isBlocked => blockedAt != null;
  bool get isExecutor => role == 'executor';
  bool get isModerator => role == 'moderator';

  /// БАСҚА адамның рейтингін НАҚТЫ РӨЛ бойынша алу.
  ///
  /// Бұл маңызды: `rating` — сол адамның ҚАЗІР белсенді рөліндегі бағасы.
  /// Ал экранда контекст басқа болуы мүмкін: орындаушы лентада КЛИЕНТТІҢ
  /// бағасын көреді, клиент заказ бетінде ОРЫНДАУШЫНЫҢ бағасын көреді.
  /// Егер клиент сол уақытта орындаушы режиміне ауысып кетсе, `rating`
  /// орындаушылық бағаны көрсетіп, шатастыратын — сол себепті осы жерде
  /// әрқашан рөлі айқын аталады.
  double ratingAs(String role) {
    if (!_dualRole) return rating; // ескі backend — жалғыз рейтинг
    return role == 'executor' ? executorRating : clientRating;
  }

  int ratingCountAs(String role) {
    if (!_dualRole) return ratingCount;
    return role == 'executor' ? executorRatingCount : clientRatingCount;
  }

  /// Аяқталған заказ саны — сол РӨЛ бойынша ([ratingAs] сияқты).
  int tripsAs(String role) {
    if (!_dualRole) return trips;
    return role == 'executor' ? executorTrips : clientTrips;
  }

  /// Қарсы рөл (ауысу батырмасы үшін). Модераторда — null.
  String? get otherRole => switch (role) {
    'client' => 'executor',
    'executor' => 'client',
    _ => null,
  };
}

// ---------- Order report ----------
class OrderReport {
  final String id;
  final String orderId;
  final String reporterId;
  final String reporterRole; // client | executor
  final String reason;
  final String status; // open | reviewed | dismissed
  final DateTime? createdAt;

  OrderReport.fromMap(Map<String, dynamic> m)
    : id = m['id'] as String,
      orderId = m['order_id'] as String,
      reporterId = m['reporter_id'] as String,
      reporterRole = m['reporter_role'] as String? ?? 'client',
      reason = m['reason'] as String? ?? '',
      status = m['status'] as String? ?? 'open',
      createdAt = _dt(m['created_at']);
}

// ---------- Executor profile ----------
class ExecutorProfile {
  final String userId;
  final String status; // pending | approved | rejected | blocked
  final VehicleType vehicleType;
  final String vehicleBrand;
  final String vehicleModel;
  final int? vehicleYear;
  final String vehiclePlate;
  final List<String> vehiclePhotos;
  final String? idDocPath;
  final String? licensePath;
  final String? techPassportPath;
  final String? techPassportSelfiePath;
  final String? idSelfiePath;
  final String? licenseSelfiePath;
  final String? passportPath;
  final String? passportSelfiePath;
  final bool isForeignCitizen;
  final String? moderationComment;
  final int balance;
  final int totalEarned;
  final String? busyOrderId;
  final String? city;
  final bool docsUpdateRequested;
  final String? docsUpdateComment;
  final List<String> docsUpdateFields;
  final bool docsReviewPending;
  final bool orderPushEnabled;
  final DateTime? createdAt;

  ExecutorProfile.fromMap(Map<String, dynamic> m)
    : userId = m['user_id'] as String,
      status = m['status'] as String? ?? 'pending',
      city = m['city'] as String?,
      vehicleType = vehicleTypeFrom(m['vehicle_type'] as String?),
      vehicleBrand = m['vehicle_brand'] as String? ?? '',
      vehicleModel = m['vehicle_model'] as String? ?? '',
      vehicleYear = m['vehicle_year'] == null ? null : _i(m['vehicle_year']),
      vehiclePlate = m['vehicle_plate'] as String? ?? '',
      vehiclePhotos =
          (m['vehicle_photos'] as List?)?.cast<String>() ?? const [],
      idDocPath = m['id_doc_path'] as String?,
      licensePath = m['license_path'] as String?,
      techPassportPath = m['tech_passport_path'] as String?,
      techPassportSelfiePath = m['tech_passport_selfie_path'] as String?,
      idSelfiePath = m['id_selfie_path'] as String?,
      licenseSelfiePath = m['license_selfie_path'] as String?,
      passportPath = m['passport_path'] as String?,
      passportSelfiePath = m['passport_selfie_path'] as String?,
      isForeignCitizen = m['is_foreign_citizen'] as bool? ?? false,
      moderationComment = m['moderation_comment'] as String?,
      balance = _i(m['balance']),
      totalEarned = _i(m['total_earned']),
      busyOrderId = m['busy_order_id'] as String?,
      docsUpdateRequested = m['docs_update_requested'] as bool? ?? false,
      docsUpdateComment = m['docs_update_comment'] as String?,
      docsUpdateFields =
          (m['docs_update_fields'] as List?)?.cast<String>() ?? const [],
      docsReviewPending = m['docs_review_pending'] as bool? ?? false,
      orderPushEnabled = m['order_push_enabled'] as bool? ?? true,
      createdAt = _dt(m['created_at']);

  /// Құжат өрісінің атауы (ағымдағы тілде).
  static String docFieldLabel(String f) => switch (f) {
    'id' => t('Жеке куәлік'),
    'passport' => t('Шетел паспорты'),
    'license' => t('Жүргізуші куәлігі'),
    'tech' => t('Техпаспорт'),
    'photos' => t('Көлік фотолары'),
    _ => f,
  };

  String get vehicleTitle => [
    vehicleBrand,
    vehicleModel,
    if (vehicleYear != null) '$vehicleYear',
  ].where((e) => e.trim().isNotEmpty).join(' ');
}

// ---------- Аралық аялдама (0047) ----------
/// Заказдың АРАЛЫҚ нүктесі: алу (from) мен ақырғы жеткізу (to) арасында.
///
/// Клиент бір заказбен бірнеше жерге жеткізе алады («адрес қосу»).
/// Схемада `from_*` — әрқашан БІРІНШІ, `to_*` — әрқашан СОҢҒЫ нүкте, ал
/// осылар оның арасындағылар. Сол себепті ескі код үшін маршрут
/// бұрынғыдай «A → B» болып қалады.
class OrderStop {
  final String address;
  final double lat;
  final double lng;
  final String? city;

  const OrderStop({
    required this.address,
    required this.lat,
    required this.lng,
    this.city,
  });

  factory OrderStop.fromMap(Map<String, dynamic> m) => OrderStop(
    address: m['address'] as String? ?? '',
    lat: _d(m['lat']),
    lng: _d(m['lng']),
    city: m['city'] as String?,
  );

  Map<String, dynamic> toMap() => {
    'address': address,
    'lat': lat,
    'lng': lng,
    'city': city,
  };

  /// Дисплейге: қала белгілі болса «Қала, көше».
  String get display => _cityAddr(city, address);

  static List<OrderStop> listFrom(dynamic v) {
    if (v is! List) return const [];
    return v
        .whereType<Map>()
        .map((m) => OrderStop.fromMap(Map<String, dynamic>.from(m)))
        .toList(growable: false);
  }
}

/// Тізімдегі БІР-БІРІНЕН ӨЗГЕ қалаларды қайтарады (null/бос елеусіз).
///
/// [Geo.sameCity] арқылы салыстырады — «Тараз», «Тараз қаласы», «Тараз
/// қалалық әкімшілігі» БІР қала болып саналады, сол себепті қарапайым
/// `Set` жарамайды. Маршрут қалааралық па екенін анықтауға қолданылады.
List<String> distinctCities(Iterable<String?> raw) {
  final out = <String>[];
  for (final c in raw) {
    if (c == null || c.trim().isEmpty) continue;
    if (out.any((seen) => Geo.sameCity(seen, c))) continue;
    out.add(c);
  }
  return out;
}

/// Клиент қоса алатын АРАЛЫҚ аялдамалардың макс саны. Маршрутта барлығы
/// `1 + kMaxExtraStops + 1` нүкте болады (алу + аралықтар + жеткізу).
///
/// МАҢЫЗДЫ: бұл санды өзгертсеңіз, серверде де (`clean_order_stops`
/// ішіндегі `k_max_stops` және `orders_stops_check` шектеуі) өзгертіңіз —
/// әйтпесе сервер артық аялдаманы `TOO_MANY_STOPS` деп қайтарады.
const int kMaxExtraStops = 2;

// ---------- Order ----------
class Order {
  final String id;
  final String clientId;
  final String type; // bidding (барлығы)
  final String tariff; // simple — бірыңғай (ескі жазбаларда vip болуы мүмкін)
  final VehicleType vehicleType; // қажет көлік түрі
  final String status;
  final String fromAddress, toAddress;
  final String? fromCity, toCity;
  final double fromLat, fromLng, toLat, toLng;
  final double distanceKm;
  final String cargoDesc;
  final String comment;
  final int? clientPrice;
  final int? systemPrice;
  final int? finalPrice;
  final String? executorId;
  final List<String> photos;
  final DateTime? createdAt, acceptedAt, completedAt;
  final String? cancelReason;
  final String? cancelledBy;

  /// Аралық аялдамалар (0047) — бос болса кәдімгі «A → B» заказ.
  final List<OrderStop> stops;

  Order.fromMap(Map<String, dynamic> m)
    : id = m['id'] as String,
      clientId = m['client_id'] as String,
      type = m['type'] as String,
      tariff = m['tariff'] as String? ?? 'simple',
      vehicleType = vehicleTypeFrom(m['vehicle_type'] as String?),
      status = m['status'] as String,
      fromAddress = m['from_address'] as String? ?? '',
      toAddress = m['to_address'] as String? ?? '',
      fromCity = m['from_city'] as String?,
      toCity = m['to_city'] as String?,
      fromLat = _d(m['from_lat']),
      fromLng = _d(m['from_lng']),
      toLat = _d(m['to_lat']),
      toLng = _d(m['to_lng']),
      distanceKm = _d(m['distance_km']),
      cargoDesc = m['cargo_desc'] as String? ?? '',
      comment = m['comment'] as String? ?? '',
      clientPrice = m['client_price'] == null ? null : _i(m['client_price']),
      systemPrice = m['system_price'] == null ? null : _i(m['system_price']),
      finalPrice = m['final_price'] == null ? null : _i(m['final_price']),
      executorId = m['executor_id'] as String?,
      photos = (m['photos'] as List?)?.cast<String>() ?? const [],
      createdAt = _dt(m['created_at']),
      acceptedAt = _dt(m['accepted_at']),
      completedAt = _dt(m['completed_at']),
      cancelReason = m['cancel_reason'] as String?,
      cancelledBy = m['cancelled_by'] as String?,
      stops = OrderStop.listFrom(m['stops']);

  bool get isActive => kActiveOrderStatuses.contains(status);
  bool get isVip => tariff == 'vip';
  int? get displayPrice => finalPrice ?? systemPrice ?? clientPrice;

  /// Қалалар аралық (межгород) заказ ба. Аралық аялдамалар (0047) да
  /// ескеріледі: аялдама басқа қалада болса заказ да қалааралық болып
  /// саналады (серверде `create_order` дәл осылай есептейді).
  ///
  /// Салыстыру [Geo.sameCity] арқылы — ол әкімшілік жұрнақтарды («Тараз
  /// қаласы» / «Тараз қалалық әкімшілігі») бір қала деп таниды, сол
  /// себепті жай Set қолданылмайды.
  bool get intercity => distinctCities([
    fromCity,
    ...stops.map((s) => s.city),
    toCity,
  ]).length > 1;

  String get fromDisplay => _cityAddr(fromCity, fromAddress);
  String get toDisplay => _cityAddr(toCity, toAddress);

  /// Маршруттың БАРЛЫҚ нүктесі көрсетуге дайын күйде: алу → аялдамалар →
  /// жеткізу. Экрандар осыны айналдырып, тізім/карта салады.
  List<String> get routeDisplay =>
      [fromDisplay, ...stops.map((s) => s.display), toDisplay];

  /// Аралық аялдамасы бар ма (UI «+N аялдама» деп белгілеу үшін).
  bool get hasStops => stops.isNotEmpty;
}

// ---------- Offer ----------
class Offer {
  final String id;
  final String orderId;
  final String executorId;
  final int price;
  final String message;
  final String status; // pending | accepted | rejected | withdrawn
  final DateTime? createdAt;

  Offer.fromMap(Map<String, dynamic> m)
    : id = m['id'] as String,
      orderId = m['order_id'] as String,
      executorId = m['executor_id'] as String,
      price = _i(m['price']),
      message = m['message'] as String? ?? '',
      status = m['status'] as String? ?? 'pending',
      createdAt = _dt(m['created_at']);
}

// ---------- Topup ----------
class TopupRequest {
  final String id;
  final String executorId;
  final int amount;
  final String? receiptPath;
  final String status;
  final String? note;
  final DateTime? createdAt;

  /// Чекті тексеретін боттың шешімі (0051). Мәндері:
  /// `approved` · `flagged` · `rejected` · `error` ·
  /// `manual_approved` · `manual_rejected` (Telegram түймесімен).
  /// 0051 қолданылмаса немесе бот өшірулі болса — `null`.
  final String? botVerdict;

  /// Бот неге солай шешкенінің қазақша тізімі (белгіленген жағдайда).
  final String? botSummary;

  TopupRequest.fromMap(Map<String, dynamic> m)
    : id = m['id'] as String,
      executorId = m['executor_id'] as String,
      amount = _i(m['amount']),
      receiptPath = m['receipt_path'] as String?,
      status = m['status'] as String? ?? 'pending',
      note = m['note'] as String?,
      createdAt = _dt(m['created_at']),
      botVerdict = m['bot_verdict'] as String?,
      botSummary = m['bot_summary'] as String?;
}

// ---------- Balance txn ----------
class BalanceTxn {
  final String id;
  final int amount;
  final String type;
  final String note;
  final DateTime? createdAt;

  BalanceTxn.fromMap(Map<String, dynamic> m)
    : id = m['id'] as String,
      amount = _i(m['amount']),
      type = m['type'] as String? ?? '',
      note = m['note'] as String? ?? '',
      createdAt = _dt(m['created_at']);
}

// ---------- Review ----------
class Review {
  final String id;
  final String orderId;
  final String executorId;
  final String? targetId;
  final String? authorRole; // client | executor
  final int rating;
  final String comment;
  final DateTime? createdAt;

  Review.fromMap(Map<String, dynamic> m)
    : id = m['id'] as String,
      orderId = m['order_id'] as String,
      executorId = m['executor_id'] as String,
      targetId = m['target_id'] as String?,
      authorRole = m['author_role'] as String?,
      rating = _i(m['rating']),
      comment = m['comment'] as String? ?? '',
      createdAt = _dt(m['created_at']);
}

// ---------- Support chat ----------
class SupportThread {
  final String id;
  final String userId;
  final String? orderId;
  final String status; // open | closed
  final String? lastSenderRole;
  final DateTime? lastMsgAt;
  final DateTime? createdAt;

  SupportThread.fromMap(Map<String, dynamic> m)
    : id = m['id'] as String,
      userId = m['user_id'] as String,
      orderId = m['order_id'] as String?,
      status = m['status'] as String? ?? 'open',
      lastSenderRole = m['last_sender_role'] as String?,
      lastMsgAt = _dt(m['last_msg_at']),
      createdAt = _dt(m['created_at']);

  bool get isOpen => status == 'open';
}

class SupportMessage {
  final String id;
  final String threadId;
  final String senderId;
  final String senderRole; // user | moderator
  final String body;
  final String? imagePath;
  final DateTime? createdAt;

  SupportMessage.fromMap(Map<String, dynamic> m)
    : id = m['id'] as String,
      threadId = m['thread_id'] as String,
      senderId = m['sender_id'] as String,
      senderRole = m['sender_role'] as String? ?? 'user',
      body = m['body'] as String? ?? '',
      imagePath = m['image_path'] as String?,
      createdAt = _dt(m['created_at']);
}

// ---------- Executor stats (RPC executor_stats) ----------
/// Тариф = 1 ауысым (ұзақтығын модератор баптайды, 0055), сол ауысымда
/// макс 10 заказ. Тариф бірыңғай:
/// [ordersLeft] — ағымдағы ауысымда қалған заказ, [until] — ауысымның аяқталу
/// уақыты, [price] — тариф бағасы (күндіз де, түнде де бірдей). [trialUntil] —
/// жаңа орындаушының 1 айлық тегін кезеңінің (§7) аяқталуы.
class ExecutorStats {
  final int balance;
  final int totalEarned;
  final int today;
  final int month;
  final String? busyOrderId;
  final int ordersLeft;
  final DateTime? until;
  final int? vehicleYear;
  final VehicleType vehicleType;
  final DateTime? trialUntil;
  final bool hasTariff;
  final bool isNight;
  final int price;
  final bool onLine;
  final String? city;

  ExecutorStats.fromMap(Map<String, dynamic> m)
    : balance = _i(m['balance']),
      totalEarned = _i(m['total_earned']),
      today = _i(m['today']),
      month = _i(m['month']),
      busyOrderId = m['busy_order_id'] as String?,
      ordersLeft = _i(m['orders_left']),
      // жаңа RPC 'until' қайтарады; ескісінде simple_until болатын
      until = _dt(m['until'] ?? m['simple_until']),
      vehicleYear = m['vehicle_year'] == null ? null : _i(m['vehicle_year']),
      vehicleType = vehicleTypeFrom(m['vehicle_type'] as String?),
      trialUntil = _dt(m['trial_until']),
      hasTariff =
          m['has_tariff'] as bool? ??
          (_dt(m['trial_until'])?.isAfter(DateTime.now()) ?? false),
      isNight = m['is_night'] as bool? ?? false,
      price = _i(m['price'] ?? m['price_simple']),
      onLine = m['on_line'] as bool? ?? true,
      city = m['city'] as String?;

  bool get trialActive =>
      trialUntil != null && trialUntil!.isAfter(DateTime.now());

  /// Заказ көру/алу мүмкіндігі бар ма (тариф не триал).
  bool get canWork => hasTariff;
}

// ---------- Хабарландыру (board) ----------
/// Хабарландырулар тақтасының жазбасы (0043 миграциясы).
///
/// Түрі АВТОРДЫҢ РӨЛІНЕН шығады, сол себепті екі жақ бір-бірін шатастырмайды:
///   [ListingKind.service] — орындаушы жариялаған ҚЫЗМЕТ («КамАЗым бар…»).
///                           Клиент оны «Қызметтер» табынан көреді.
///   [ListingKind.job]     — клиент жариялаған ЖҰМЫС («10 күнге фура керек»).
///                           Орындаушы оны «Жұмыстар» табынан көреді.
///
/// [views] тек авторға беріледі (басқаға сервер null қайтарады).
enum ListingKind { job, service }

/// Хабарландырудың лентада тұратын мерзімі — фотолар да дәл сонша сақталады.
const int kListingDays = 7;

/// Бір хабарландыруға рұқсат етілген макс фото саны.
const int kListingMaxPhotos = 4;

/// Бір адамның бір мезгілде ұстай алатын макс белсенді хабарландыруы.
const int kListingMaxActive = 5;

class Listing {
  final String id;
  final ListingKind kind;
  final VehicleType vehicleType;
  final String city;
  final String body;
  final String priceText;

  /// >0 болса — «N күндік жұмыс» (тек [ListingKind.job] үшін).
  final int durationDays;
  final List<String> photos;

  /// Тек автордың өзіне беріледі — басқа жағдайда null.
  final int? views;
  final String status; // active | expired | archived
  final DateTime? createdAt;
  final DateTime? expiresAt;
  final bool mine;
  final String authorId;

  /// client | executor — автордың жариялау кезіндегі рөлі.
  final String authorRole;
  final String authorName;
  final String? authorAvatar;
  final double authorRating;
  final int authorRatingCount;
  final int authorTrips;

  /// Тек [Repo.openListing] қайтарған детальда толтырылады.
  final String? authorPhone;

  Listing.fromMap(Map<String, dynamic> m)
    : id = m['id'] as String,
      kind = m['kind'] == 'job' ? ListingKind.job : ListingKind.service,
      vehicleType = vehicleTypeFrom(m['vehicle_type'] as String?),
      city = m['city'] as String? ?? '',
      body = m['body'] as String? ?? '',
      priceText = m['price_text'] as String? ?? '',
      durationDays = _i(m['duration_days']),
      photos = (m['photos'] as List?)?.cast<String>() ?? const [],
      views = m['views'] == null ? null : _i(m['views']),
      status = m['status'] as String? ?? 'active',
      createdAt = _dt(m['created_at']),
      expiresAt = _dt(m['expires_at']),
      mine = m['mine'] as bool? ?? false,
      authorId = m['author_id'] as String? ?? '',
      authorRole = m['author_role'] as String? ?? 'client',
      authorName = m['author_name'] as String? ?? '',
      authorAvatar = m['author_avatar'] as String?,
      authorRating = _d(m['author_rating']),
      authorRatingCount = _i(m['author_rating_count']),
      authorTrips = _i(m['author_trips']),
      authorPhone = m['author_phone'] as String?;

  bool get isActive =>
      status == 'active' &&
      (expiresAt == null || expiresAt!.isAfter(DateTime.now()));

  /// Бағасы жазылмаған болса — «Келісім бойынша».
  String get priceDisplay =>
      priceText.trim().isEmpty ? t('Келісім бойынша') : priceText.trim();

  /// Мерзімі бітуіне қалған күн (белсенді емес болса 0).
  int get daysLeft {
    final e = expiresAt;
    if (!isActive || e == null) return 0;
    final d = e.difference(DateTime.now()).inHours / 24;
    return d <= 0 ? 0 : d.ceil();
  }
}

/// Хабарландыруға түскен шағым (0044). Хабарландырудың өзі өшіп кетсе де
/// модератор нені қарағанын көру үшін мәтіні/қаласы/фотолары шағым жазбасына
/// СНИМОК болып сақталған — сол себепті бұл [Listing]-тен бөлек модель.
class ListingReport {
  final String id;

  /// Хабарландыру әлі бар болса — оның id-і, өшірілген болса null.
  final String? listingId;
  final bool listingAlive;
  final String reason;

  /// open | resolved | dismissed
  final String status;

  /// deleted | kept (шешім қабылданған болса)
  final String? action;
  final DateTime? createdAt;
  final DateTime? resolvedAt;

  final String reporterId;
  final String reporterName;
  final String reporterRole;

  final String? authorId;
  final String authorName;
  final String authorRole;
  final bool authorBlocked;

  // ---- хабарландырудың снимогі ----
  final String body;
  final String city;
  final VehicleType vehicleType;
  final ListingKind kind;
  final List<String> photos;

  /// Осы хабарландыруға түскен шағымдардың ЖАЛПЫ саны (қайталанса — мәселе
  /// шынымен бар деген белгі).
  final int reportsTotal;

  ListingReport.fromMap(Map<String, dynamic> m)
    : id = m['id'] as String,
      listingId = m['listing_id'] as String?,
      listingAlive = m['listing_alive'] as bool? ?? false,
      reason = m['reason'] as String? ?? '',
      status = m['status'] as String? ?? 'open',
      action = m['action'] as String?,
      createdAt = _dt(m['created_at']),
      resolvedAt = _dt(m['resolved_at']),
      reporterId = m['reporter_id'] as String? ?? '',
      reporterName = m['reporter_name'] as String? ?? '',
      reporterRole = m['reporter_role'] as String? ?? 'client',
      authorId = m['author_id'] as String?,
      authorName = m['author_name'] as String? ?? '',
      authorRole = m['author_role'] as String? ?? 'client',
      authorBlocked = m['author_blocked'] as bool? ?? false,
      body = m['body'] as String? ?? '',
      city = m['city'] as String? ?? '',
      vehicleType = vehicleTypeFrom(m['vehicle_type'] as String?),
      kind = m['kind'] == 'job' ? ListingKind.job : ListingKind.service,
      photos = (m['photos'] as List?)?.cast<String>() ?? const [],
      reportsTotal = _i(m['reports_total']);

  bool get isOpen => status == 'open';
}

// ---------- App settings ----------
class AppConfig {
  final String kaspiNumber;
  final String kaspiName;
  final int minTopup;

  /// Kaspi QR/төлем сілтемесі (модератор қоятын). Бос болмаса — балансты
  /// толтыру экранында «Kaspi-мен төлеу» түймесі шығып, Kaspi қосымшасын
  /// (QR + сома енгізу → төлеу) тікелей ашады.
  final String kaspiTopupUrl;

  AppConfig({
    this.kaspiNumber = '+7 777 000 0000',
    this.kaspiName = 'Tasu',
    this.minTopup = 500,
    this.kaspiTopupUrl = '',
  });

  factory AppConfig.fromSettings(Map<String, dynamic>? payment) {
    if (payment == null) return AppConfig();
    return AppConfig(
      kaspiNumber: payment['kaspi_number'] as String? ?? '+7 777 000 0000',
      kaspiName: payment['kaspi_name'] as String? ?? 'Tasu',
      minTopup: _i(payment['min_topup'] ?? 500),
      kaspiTopupUrl: payment['kaspi_topup_url'] as String? ?? '',
    );
  }
}
