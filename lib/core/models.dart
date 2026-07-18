/// GazelGo модельдері — Supabase кестелерінің Dart көрінісі.
library;

import 'geo.dart';
import 'lang.dart';

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

// ---------- Vehicle type (көлік түрі) ----------
/// Заказ бен орындаушы осы түр бойынша сәйкестендіріледі: клиент газельге
/// заказ берсе — оны тек газелист көреді (indriver-дегі көлік таңдау сияқты).
enum VehicleType {
  gazelle,
  furgon,
  kamaz,
  fura,
  crane,
  manipulator,
  assenizator,
  excavator,
  loader,
  minivan,
  tractor,
}

VehicleType vehicleTypeFrom(String? s) => switch (s) {
      'furgon' => VehicleType.furgon,
      'kamaz' => VehicleType.kamaz,
      'fura' => VehicleType.fura,
      'crane' => VehicleType.crane,
      'manipulator' => VehicleType.manipulator,
      'assenizator' => VehicleType.assenizator,
      'excavator' => VehicleType.excavator,
      'loader' => VehicleType.loader,
      'minivan' => VehicleType.minivan,
      'tractor' => VehicleType.tractor,
      _ => VehicleType.gazelle,
    };

extension VehicleTypeX on VehicleType {
  String get db => name;
  String get label => switch (this) {
        VehicleType.gazelle => t('Газель'),
        VehicleType.furgon => t('Фургон'),
        VehicleType.kamaz => t('КамАЗ'),
        VehicleType.fura => t('Фура'),
        VehicleType.crane => t('Кран'),
        VehicleType.manipulator => t('Манипулятор'),
        VehicleType.assenizator => t('Ассенизатор'),
        VehicleType.excavator => t('Экскаватор'),
        VehicleType.loader => t('Погрузчик'),
        VehicleType.minivan => t('Мини вэн'),
        VehicleType.tractor => t('Трактор 3в1'),
      };
  /// Түрлі-түсті PNG иконкасы бар түрлер (`assets/vehicles/<name>.png`) —
  /// қалғандары ([emoji] арқылы) эмодзимен көрсетіледі. UI жағында
  /// [vehicleIcon] екеуін бір өлшемге сәйкестендіріп рендерлейді.
  String? get pngAsset => switch (this) {
        VehicleType.kamaz => 'assets/vehicles/kamaz.png',
        VehicleType.fura => 'assets/vehicles/fura.png',
        VehicleType.crane => 'assets/vehicles/crane.png',
        VehicleType.manipulator => 'assets/vehicles/manipulator.png',
        VehicleType.assenizator => 'assets/vehicles/assenizator.png',
        VehicleType.excavator => 'assets/vehicles/excavator.png',
        VehicleType.loader => 'assets/vehicles/loader.png',
        VehicleType.minivan => 'assets/vehicles/minivan.png',
        _ => null,
      };

  /// PNG иконкасы жоқ түрлерге арналған эмодзи (gazelle/furgon/tractor).
  String get emoji => switch (this) {
        VehicleType.gazelle => '🚚',
        VehicleType.furgon => '🚐',
        VehicleType.tractor => '🚜',
        _ => '🚚',
      };

  /// Көлік түрінің қысқа түсініктемесі (сыйымдылық/жүктеме). Бос жол болса —
  /// UI бұл жолды көрсетпейді. Каруселде таңдалған түрдің астында шығады.
  String get description => switch (this) {
        VehicleType.fura => t('Ауыр жүк көлігі · 5–20 тонна'),
        _ => '',
      };
}

// ---------- Order status ----------
const kActiveOrderStatuses = ['searching', 'accepted', 'arrived', 'loading', 'in_transit'];

String statusLabel(String s) => switch (s) {
      'searching' => t('Іздеуде'),
      'accepted' => t('Қабылданды · жолда'),
      'arrived' => t('Орындаушы келді'),
      'loading' => t('Тиеу жүріп жатыр'),
      'in_transit' => t('Тасымалдауда'),
      'completed' => t('Аяқталды'),
      'cancelled' => t('Бас тартылды'),
      'expired' => t('Мерзімі өтті'),
      _ => s,
    };

// ---------- Profile ----------
class Profile {
  final String id;
  final String role; // client | executor | moderator
  final String fullName;
  final String phone;
  final String? avatarUrl;
  final double rating;
  final int ratingCount;
  final int trips;
  final int trustScore;
  final DateTime? blockedAt;
  final String? blockReason;

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
        blockReason = m['block_reason'] as String?;

  bool get isBlocked => blockedAt != null;
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
        vehiclePhotos = (m['vehicle_photos'] as List?)?.cast<String>() ?? const [],
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

  String get vehicleTitle =>
      [vehicleBrand, vehicleModel, if (vehicleYear != null) '$vehicleYear']
          .where((e) => e.trim().isNotEmpty)
          .join(' ');
}

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
        cancelledBy = m['cancelled_by'] as String?;

  bool get isActive => kActiveOrderStatuses.contains(status);
  bool get isVip => tariff == 'vip';
  int? get displayPrice => finalPrice ?? systemPrice ?? clientPrice;

  /// Қалалар аралық (межгород) заказ ба — қала аттары белгілі болса ғана есептеледі.
  bool get intercity =>
      fromCity != null && toCity != null && !Geo.sameCity(fromCity, toCity);

  String get fromDisplay => _cityAddr(fromCity, fromAddress);
  String get toDisplay => _cityAddr(toCity, toAddress);
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

  TopupRequest.fromMap(Map<String, dynamic> m)
      : id = m['id'] as String,
        executorId = m['executor_id'] as String,
        amount = _i(m['amount']),
        receiptPath = m['receipt_path'] as String?,
        status = m['status'] as String? ?? 'pending',
        note = m['note'] as String?,
        createdAt = _dt(m['created_at']);
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
/// Тариф = 1 ауысым (12 сағ), сол ауысымда макс 10 заказ. Тариф бірыңғай:
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
        hasTariff = m['has_tariff'] as bool? ??
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

// ---------- App settings ----------
class AppConfig {
  final String kaspiNumber;
  final String kaspiName;
  final int minTopup;

  AppConfig({
    this.kaspiNumber = '+7 777 000 0000',
    this.kaspiName = 'Tasu',
    this.minTopup = 500,
  });

  factory AppConfig.fromSettings(Map<String, dynamic>? payment) {
    if (payment == null) return AppConfig();
    return AppConfig(
      kaspiNumber: payment['kaspi_number'] as String? ?? '+7 777 000 0000',
      kaspiName: payment['kaspi_name'] as String? ?? 'Tasu',
      minTopup: _i(payment['min_topup'] ?? 500),
    );
  }
}
