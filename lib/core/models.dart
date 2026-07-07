/// GazelGo модельдері — Supabase кестелерінің Dart көрінісі.
library;

DateTime? _dt(dynamic v) =>
    v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

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

// ---------- Vehicle size ----------
enum VehicleSize { small, medium, large }

VehicleSize sizeFrom(String? s) => switch (s) {
      'medium' => VehicleSize.medium,
      'large' => VehicleSize.large,
      _ => VehicleSize.small,
    };

extension VehicleSizeX on VehicleSize {
  String get db => name;
  String get label => switch (this) {
        VehicleSize.small => 'Кіші газель',
        VehicleSize.medium => 'Орта газель',
        VehicleSize.large => 'Үлкен газель',
      };
  String get hint => switch (this) {
        VehicleSize.small => '1.5 т дейін · 3 м',
        VehicleSize.medium => '3 т дейін · 4 м',
        VehicleSize.large => '5 т және одан көп',
      };
}

// ---------- Order status ----------
const kActiveOrderStatuses = ['searching', 'accepted', 'arrived', 'loading', 'in_transit'];

String statusLabel(String s) => switch (s) {
      'searching' => 'Іздеуде',
      'accepted' => 'Қабылданды · жолда',
      'arrived' => 'Орындаушы келді',
      'loading' => 'Тиеу жүріп жатыр',
      'in_transit' => 'Тасымалдауда',
      'completed' => 'Аяқталды',
      'cancelled' => 'Бас тартылды',
      'expired' => 'Мерзімі өтті',
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

  Profile.fromMap(Map<String, dynamic> m)
      : id = m['id'] as String,
        role = m['role'] as String? ?? 'client',
        fullName = m['full_name'] as String? ?? '',
        phone = m['phone'] as String? ?? '',
        avatarUrl = m['avatar_url'] as String?,
        rating = _d(m['rating']),
        ratingCount = _i(m['rating_count']),
        trips = _i(m['trips']);
}

// ---------- Executor profile ----------
class ExecutorProfile {
  final String userId;
  final String status; // pending | approved | rejected | blocked
  final VehicleSize vehicleSize;
  final String vehicleBrand;
  final String vehicleModel;
  final int? vehicleYear;
  final String vehiclePlate;
  final List<String> vehiclePhotos;
  final String? idDocPath;
  final String? licensePath;
  final String? techPassportPath;
  final String? moderationComment;
  final int balance;
  final int totalEarned;
  final String? busyOrderId;
  final bool docsUpdateRequested;
  final String? docsUpdateComment;
  final List<String> docsUpdateFields;
  final bool docsReviewPending;
  final DateTime? createdAt;

  ExecutorProfile.fromMap(Map<String, dynamic> m)
      : userId = m['user_id'] as String,
        status = m['status'] as String? ?? 'pending',
        vehicleSize = sizeFrom(m['vehicle_size'] as String?),
        vehicleBrand = m['vehicle_brand'] as String? ?? '',
        vehicleModel = m['vehicle_model'] as String? ?? '',
        vehicleYear = m['vehicle_year'] == null ? null : _i(m['vehicle_year']),
        vehiclePlate = m['vehicle_plate'] as String? ?? '',
        vehiclePhotos = (m['vehicle_photos'] as List?)?.cast<String>() ?? const [],
        idDocPath = m['id_doc_path'] as String?,
        licensePath = m['license_path'] as String?,
        techPassportPath = m['tech_passport_path'] as String?,
        moderationComment = m['moderation_comment'] as String?,
        balance = _i(m['balance']),
        totalEarned = _i(m['total_earned']),
        busyOrderId = m['busy_order_id'] as String?,
        docsUpdateRequested = m['docs_update_requested'] as bool? ?? false,
        docsUpdateComment = m['docs_update_comment'] as String?,
        docsUpdateFields =
            (m['docs_update_fields'] as List?)?.cast<String>() ?? const [],
        docsReviewPending = m['docs_review_pending'] as bool? ?? false,
        createdAt = _dt(m['created_at']);

  /// Құжат өрісінің қазақша атауы.
  static String docFieldLabel(String f) => switch (f) {
        'id' => 'Жеке куәлік',
        'license' => 'Жүргізуші куәлігі',
        'tech' => 'Техпаспорт',
        'photos' => 'Көлік фотолары',
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
  final String type; // bidding | instant
  final String status;
  final String fromAddress, toAddress;
  final double fromLat, fromLng, toLat, toLng;
  final double distanceKm;
  final String cargoDesc;
  final String comment;
  final VehicleSize size;
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
        status = m['status'] as String,
        fromAddress = m['from_address'] as String? ?? '',
        toAddress = m['to_address'] as String? ?? '',
        fromLat = _d(m['from_lat']),
        fromLng = _d(m['from_lng']),
        toLat = _d(m['to_lat']),
        toLng = _d(m['to_lng']),
        distanceKm = _d(m['distance_km']),
        cargoDesc = m['cargo_desc'] as String? ?? '',
        comment = m['comment'] as String? ?? '',
        size = sizeFrom(m['size'] as String?),
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
  int? get displayPrice => finalPrice ?? systemPrice ?? clientPrice;
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

// ---------- VIP dispatch ----------
class VipDispatch {
  final String id;
  final String orderId;
  final String executorId;
  final String status; // pending | accepted | declined | expired
  final DateTime expiresAt;

  VipDispatch.fromMap(Map<String, dynamic> m)
      : id = m['id'] as String,
        orderId = m['order_id'] as String,
        executorId = m['executor_id'] as String,
        status = m['status'] as String? ?? 'pending',
        expiresAt = _dt(m['expires_at']) ?? DateTime.now();

  bool get isLive => status == 'pending' && expiresAt.isAfter(DateTime.now());
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
class ExecutorStats {
  final int balance;
  final int totalEarned;
  final int today;
  final int month;
  final String? busyOrderId;
  final DateTime? simpleUntil;
  final DateTime? vipUntil;
  final bool isNight;
  final int priceSimple;
  final int priceVip;
  final bool onLine;
  final bool autoAcceptVip;

  ExecutorStats.fromMap(Map<String, dynamic> m)
      : balance = _i(m['balance']),
        totalEarned = _i(m['total_earned']),
        today = _i(m['today']),
        month = _i(m['month']),
        busyOrderId = m['busy_order_id'] as String?,
        simpleUntil = _dt(m['simple_until']),
        vipUntil = _dt(m['vip_until']),
        isNight = m['is_night'] as bool? ?? false,
        priceSimple = _i(m['price_simple']),
        priceVip = _i(m['price_vip']),
        onLine = m['on_line'] as bool? ?? true,
        autoAcceptVip = m['auto_accept_vip'] as bool? ?? false;

  bool get simpleActive => simpleUntil != null && simpleUntil!.isAfter(DateTime.now());
  bool get vipActive => vipUntil != null && vipUntil!.isAfter(DateTime.now());
}

// ---------- App settings ----------
class AppConfig {
  final String kaspiNumber;
  final String kaspiName;
  final int minTopup;

  AppConfig({
    this.kaspiNumber = '+7 777 000 0000',
    this.kaspiName = 'GazelGo',
    this.minTopup = 500,
  });

  factory AppConfig.fromSettings(Map<String, dynamic>? payment) {
    if (payment == null) return AppConfig();
    return AppConfig(
      kaspiNumber: payment['kaspi_number'] as String? ?? '+7 777 000 0000',
      kaspiName: payment['kaspi_name'] as String? ?? 'GazelGo',
      minTopup: _i(payment['min_topup'] ?? 500),
    );
  }
}
