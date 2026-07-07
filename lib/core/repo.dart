import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';

/// Барлық дерек-қатынас осы жерде: Supabase RPC, стримдер, storage.
class Repo {
  static SupabaseClient get c => Supabase.instance.client;
  static String? get uid => c.auth.currentUser?.id;

  // ================= AUTH =================
  static Future<void> signIn(String email, String password) =>
      c.auth.signInWithPassword(email: email.trim(), password: password);

  /// Тіркелу: алдымен edge function (email растауын айналып өтеді),
  /// ол қолжетімсіз болса — тікелей auth.signUp арқылы.
  static Future<void> signUp({
    required String email,
    required String password,
    required String fullName,
    required String phone,
    required String role, // client | executor
  }) async {
    try {
      await c.functions.invoke('signup', body: {
        'email': email.trim(),
        'password': password,
        'full_name': fullName.trim(),
        'phone': phone.trim(),
        'role': role,
      });
    } on FunctionException catch (e) {
      final d = e.details;
      if (d is Map && d['error'] != null) {
        // функция жетті, бірақ валидация қатесін қайтарды
        throw Exception(d['error'].toString());
      }
      // функция табылмады/рұқсат жоқ (404, 401...) — тікелей тіркелеміз
      await _directSignUp(
          email: email, password: password, fullName: fullName,
          phone: phone, role: role);
    } catch (e) {
      if (e.toString().contains('EMAIL_CONFIRM_REQUIRED')) rethrow;
      // желі қатесі т.б. — тікелей тіркелуді көреміз
      await _directSignUp(
          email: email, password: password, fullName: fullName,
          phone: phone, role: role);
    }
    await signIn(email, password);
  }

  static Future<void> _directSignUp({
    required String email,
    required String password,
    required String fullName,
    required String phone,
    required String role,
  }) async {
    final res = await c.auth.signUp(
      email: email.trim(),
      password: password,
      data: {
        'full_name': fullName.trim(),
        'phone': phone.trim(),
        'role': role,
      },
    );
    if (res.session == null) {
      // Supabase-те "Confirm email" қосулы — сессия берілмеді
      throw Exception('EMAIL_CONFIRM_REQUIRED');
    }
  }

  static Future<void> signOut() => c.auth.signOut();

  // ================= PROFILES =================
  static Future<Profile?> myProfile() async {
    final id = uid;
    if (id == null) return null;
    final m =
        await c.from('profiles').select().eq('id', id).maybeSingle();
    return m == null ? null : Profile.fromMap(m);
  }

  static Future<Profile?> profileOf(String id) async {
    final m = await c.from('profiles').select().eq('id', id).maybeSingle();
    return m == null ? null : Profile.fromMap(m);
  }

  static Future<void> updateProfile({String? fullName, String? phone}) async {
    final id = uid;
    if (id == null) return;
    await c.from('profiles').update({
      if (fullName != null) 'full_name': fullName.trim(),
      if (phone != null) 'phone': phone.trim(),
    }).eq('id', id);
  }

  /// Аватарды жаңарту: жаңасын жүктеп, ескісін өшіреді.
  static Future<void> updateAvatar(Uint8List bytes) async {
    final id = uid;
    if (id == null) throw Exception('AUTH');
    // ескі аватар жолын алу
    String? oldUrl;
    final prof = await c
        .from('profiles')
        .select('avatar_url')
        .eq('id', id)
        .maybeSingle();
    oldUrl = prof?['avatar_url'] as String?;

    final path = '$id/avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await c.storage.from('avatars').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'),
        );
    final publicUrl = c.storage.from('avatars').getPublicUrl(path);
    await c.from('profiles').update({'avatar_url': publicUrl}).eq('id', id);

    // ескісін өшіру (best-effort)
    if (oldUrl != null && oldUrl.contains('/avatars/')) {
      final oldPath = oldUrl.split('/avatars/').last.split('?').first;
      try {
        await c.storage.from('avatars').remove([oldPath]);
      } catch (_) {}
    }
  }

  static Future<ExecutorProfile?> myExecutorProfile() async {
    final id = uid;
    if (id == null) return null;
    final m = await c
        .from('executor_profiles')
        .select()
        .eq('user_id', id)
        .maybeSingle();
    return m == null ? null : ExecutorProfile.fromMap(m);
  }

  static Future<ExecutorProfile?> executorProfileOf(String id) async {
    final m = await c
        .from('executor_profiles')
        .select()
        .eq('user_id', id)
        .maybeSingle();
    return m == null ? null : ExecutorProfile.fromMap(m);
  }

  /// Орындаушы өтінімі (жаңа немесе қайта жіберу).
  static Future<void> submitExecutorApplication({
    required VehicleSize size,
    required String brand,
    required String model,
    int? year,
    required String plate,
    required List<String> vehiclePhotos,
    String? idDocPath,
    String? licensePath,
    String? techPassportPath,
    required bool isResubmit,
  }) async {
    final id = uid;
    if (id == null) throw Exception('AUTH');
    final data = {
      'vehicle_size': size.db,
      'vehicle_brand': brand.trim(),
      'vehicle_model': model.trim(),
      'vehicle_year': year,
      'vehicle_plate': plate.trim(),
      'vehicle_photos': vehiclePhotos,
      'id_doc_path': idDocPath,
      'license_path': licensePath,
      'tech_passport_path': techPassportPath,
    };
    if (isResubmit) {
      // ескі құжат жолдарын жинап, жаңасына сай еместерін өшіреміз
      final old = await c
          .from('executor_profiles')
          .select('status, id_doc_path, license_path, tech_passport_path, vehicle_photos')
          .eq('user_id', id)
          .maybeSingle();
      final newPaths = <String?>{
        idDocPath,
        licensePath,
        techPassportPath,
        ...vehiclePhotos,
      };
      final oldPaths = <String>[];
      if (old != null) {
        for (final k in ['id_doc_path', 'license_path', 'tech_passport_path']) {
          final p = old[k] as String?;
          if (p != null && !newPaths.contains(p)) oldPaths.add(p);
        }
        for (final p in (old['vehicle_photos'] as List?)?.cast<String>() ?? const []) {
          if (!newPaths.contains(p)) oldPaths.add(p);
        }
      }
      // қабылданбаған болса → pending; расталған болса статус өзгермейді
      final wasRejected = old?['status'] == 'rejected';
      await c.from('executor_profiles').update({
        ...data,
        if (wasRejected) 'status': 'pending',
      }).eq('user_id', id);
      // модератор сұранымын өшіру
      try {
        await c.rpc('clear_docs_request');
      } catch (_) {}
      if (oldPaths.isNotEmpty) {
        try {
          await c.storage.from('docs').remove(oldPaths);
        } catch (_) {}
      }
    } else {
      await c.from('executor_profiles').insert({...data, 'user_id': id});
    }
  }

  // ================= SETTINGS =================
  static Future<Map<String, dynamic>> settings() async {
    final rows = await c.from('app_settings').select();
    final map = <String, dynamic>{};
    for (final r in rows as List) {
      map[r['key'] as String] = r['value'];
    }
    return map;
  }

  // ================= RPC wrappers =================
  static Future<Map<String, dynamic>> buyTariff(String kind) async =>
      Map<String, dynamic>.from(
          await c.rpc('buy_tariff', params: {'p_kind': kind}) as Map);

  static Future<ExecutorStats> executorStats() async =>
      ExecutorStats.fromMap(
          Map<String, dynamic>.from(await c.rpc('executor_stats') as Map));

  /// Орындаушы статистикасы — тікелей байланыс (polling, ~4с).
  static Stream<ExecutorStats> executorStatsStream() => _poll(() async =>
      ExecutorStats.fromMap(
          Map<String, dynamic>.from(await c.rpc('executor_stats') as Map)),
      every: const Duration(seconds: 4));

  static Future<int> instantQuote(VehicleSize size, double distanceKm) async =>
      (await c.rpc('instant_quote', params: {
        'p_size': size.db,
        'p_distance_km': distanceKm,
      }) as num)
          .toInt();

  static Future<String> createOrder({
    required String type, // bidding | instant
    required String fromAddress,
    required double fromLat,
    required double fromLng,
    required String toAddress,
    required double toLat,
    required double toLng,
    required double distanceKm,
    required String cargo,
    required String comment,
    required VehicleSize size,
    int? clientPrice,
    List<String> photos = const [],
  }) async {
    final res = await c.rpc('create_order', params: {
      'p_type': type,
      'p_from_address': fromAddress,
      'p_from_lat': fromLat,
      'p_from_lng': fromLng,
      'p_to_address': toAddress,
      'p_to_lat': toLat,
      'p_to_lng': toLng,
      'p_distance_km': distanceKm,
      'p_cargo': cargo,
      'p_comment': comment,
      'p_size': size.db,
      'p_client_price': clientPrice,
      'p_photos': photos,
    });
    return (res as Map)['id'] as String;
  }

  /// Заказ фотосын жүктеу (public 'orders' бакеті). Жолын қайтарады.
  static Future<String> uploadOrderPhoto(Uint8List bytes, int index) async {
    final id = uid;
    if (id == null) throw Exception('AUTH');
    final path =
        '$id/${DateTime.now().millisecondsSinceEpoch}_$index.jpg';
    await c.storage.from('orders').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'),
        );
    return path;
  }

  static String orderPhotoUrl(String path) =>
      c.storage.from('orders').getPublicUrl(path);

  /// Аяқталған/бас тартылған заказдың фотоларын өшіру (best-effort).
  static Future<void> deleteOrderPhotos(List<String> paths) async {
    if (paths.isEmpty) return;
    try {
      await c.storage.from('orders').remove(paths);
    } catch (_) {}
  }

  static Future<void> rejectOffer(String offerId) =>
      c.rpc('reject_offer', params: {'p_offer': offerId});

  static Future<void> updateOrderPrice(String orderId, int price) =>
      c.rpc('update_order_price', params: {
        'p_order': orderId,
        'p_price': price,
      });

  static Future<void> advanceVip(String orderId) =>
      c.rpc('advance_vip', params: {'p_order': orderId});

  static Future<String> acceptVip(String dispatchId) async {
    final res = await c.rpc('accept_vip', params: {'p_dispatch': dispatchId});
    return (res as Map)['order_id'] as String;
  }

  static Future<void> declineVip(String dispatchId) =>
      c.rpc('decline_vip', params: {'p_dispatch': dispatchId});

  static Future<void> placeOffer(String orderId, int price, String message) =>
      c.rpc('place_offer', params: {
        'p_order': orderId,
        'p_price': price,
        'p_message': message,
      });

  static Future<void> withdrawOffer(String offerId) =>
      c.rpc('withdraw_offer', params: {'p_offer': offerId});

  static Future<void> acceptOffer(String offerId) =>
      c.rpc('accept_offer', params: {'p_offer': offerId});

  static Future<void> orderAdvance(String orderId, String status) =>
      c.rpc('order_advance', params: {'p_order': orderId, 'p_status': status});

  static Future<void> cancelOrder(String orderId, String reason) =>
      c.rpc('cancel_order', params: {'p_order': orderId, 'p_reason': reason});

  static Future<void> submitReview(String orderId, int rating, String comment) =>
      c.rpc('submit_review', params: {
        'p_order': orderId,
        'p_rating': rating,
        'p_comment': comment,
      });

  static Future<void> requestTopup(int amount, String? receiptPath) =>
      c.rpc('request_topup', params: {
        'p_amount': amount,
        'p_receipt_path': receiptPath,
      });

  // ---- moderator ----
  static Future<void> modSetExecutorStatus(
          String userId, String status, String comment) =>
      c.rpc('mod_set_executor_status', params: {
        'p_user': userId,
        'p_status': status,
        'p_comment': comment,
      });

  static Future<void> modReviewTopup(String id, bool approve, String note) =>
      c.rpc('mod_review_topup', params: {
        'p_topup': id,
        'p_approve': approve,
        'p_note': note,
      });

  static Future<void> modRequestDocs(
          String userId, List<String> fields, String comment) =>
      c.rpc('mod_request_docs', params: {
        'p_user': userId,
        'p_fields': fields,
        'p_comment': comment,
      });

  static Future<void> modApproveDocs(String userId) =>
      c.rpc('mod_approve_docs', params: {'p_user': userId});

  static Future<void> modRejectDocs(String userId, String comment) =>
      c.rpc('mod_reject_docs', params: {'p_user': userId, 'p_comment': comment});

  /// Орындаушының тек сұралған құжаттарды жаңартуы (ревьюге түседі).
  static Future<void> submitDocsUpdate({
    String? idDocPath,
    String? licensePath,
    String? techPath,
    List<String>? photos,
  }) =>
      c.rpc('submit_docs_update', params: {
        'p_id_doc': idDocPath,
        'p_license': licensePath,
        'p_tech': techPath,
        'p_photos': photos,
      });

  /// Ревью күтіп тұрған құжат жаңартулары (модератор үшін).
  static Future<List<ExecutorProfile>> docsReviewPending() async {
    final rows = await c
        .from('executor_profiles')
        .select()
        .eq('docs_review_pending', true)
        .order('updated_at', ascending: false)
        .limit(100);
    return (rows as List)
        .map((m) => ExecutorProfile.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }

  static Future<void> modCancelOrder(String orderId, String reason) =>
      c.rpc('mod_cancel_order', params: {
        'p_order': orderId,
        'p_reason': reason,
      });

  static Future<void> modReopenOrder(String orderId) =>
      c.rpc('mod_reopen_order', params: {'p_order': orderId});

  static Future<Map<String, dynamic>> modExecutorSummary(String userId) async =>
      Map<String, dynamic>.from(
          await c.rpc('mod_executor_summary', params: {'p_user': userId}) as Map);

  static Future<void> modSetOrderStatus(String orderId, String status) =>
      c.rpc('mod_set_order_status', params: {
        'p_order': orderId,
        'p_status': status,
      });

  static Future<Map<String, dynamic>> modLineStats() async =>
      Map<String, dynamic>.from(await c.rpc('mod_line_stats') as Map);

  /// Модератор: барлық іздеудегі заказдар (линия көрінісі үшін).
  static Future<List<Order>> searchingOrders() async {
    final rows = await c
        .from('orders')
        .select()
        .eq('status', 'searching')
        .order('created_at', ascending: false)
        .limit(50);
    return (rows as List)
        .map((m) => Order.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }

  static Future<Order?> orderById(String id) async {
    final m = await c.from('orders').select().eq('id', id).maybeSingle();
    return m == null ? null : Order.fromMap(m);
  }

  // ================= SUPPORT CHAT =================
  static Future<String> supportSend(String body,
          {String? imagePath, String? orderId}) async =>
      (await c.rpc('support_send', params: {
        'p_body': body,
        'p_image_path': imagePath,
        'p_order_id': orderId,
      })) as String;

  static Future<void> supportReply(String threadId, String body,
          {String? imagePath}) =>
      c.rpc('support_reply', params: {
        'p_thread': threadId,
        'p_body': body,
        'p_image_path': imagePath,
      });

  static Future<void> supportClose(String threadId) =>
      c.rpc('support_close', params: {'p_thread': threadId});

  /// Қолдау чатына сурет жүктеу (public 'support' бакеті).
  static Future<String> uploadSupportImage(Uint8List bytes) async {
    final id = uid;
    if (id == null) throw Exception('AUTH');
    final path = '$id/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await c.storage.from('support').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'),
        );
    return path;
  }

  static String supportImageUrl(String path) =>
      c.storage.from('support').getPublicUrl(path);

  /// Пайдаланушының ашық треді (болмаса — null).
  static Future<SupportThread?> myOpenThread() async {
    final id = uid;
    if (id == null) return null;
    final rows = await c
        .from('support_threads')
        .select()
        .eq('user_id', id)
        .order('created_at', ascending: false)
        .limit(1);
    if ((rows as List).isEmpty) return null;
    return SupportThread.fromMap(Map<String, dynamic>.from(rows.first));
  }

  static Stream<List<SupportMessage>> supportMessagesStream(String threadId) =>
      _poll(() async {
        final rows = await c
            .from('support_messages')
            .select()
            .eq('thread_id', threadId)
            .order('created_at');
        return (rows as List)
            .map((m) => SupportMessage.fromMap(Map<String, dynamic>.from(m)))
            .toList();
      }, every: const Duration(seconds: 3));

  static Stream<List<SupportThread>> myThreadsStream() {
    final id = uid;
    if (id == null) return const Stream.empty();
    return _poll(() async {
      final rows = await c
          .from('support_threads')
          .select()
          .eq('user_id', id)
          .order('last_msg_at');
      return (rows as List)
          .map((m) => SupportThread.fromMap(Map<String, dynamic>.from(m)))
          .toList();
    });
  }

  static Stream<List<SupportThread>> allThreadsStream() => _poll(() async {
        final rows = await c
            .from('support_threads')
            .select()
            .order('last_msg_at', ascending: false);
        return (rows as List)
            .map((m) => SupportThread.fromMap(Map<String, dynamic>.from(m)))
            .toList();
      });

  // ================= STREAMS (polling — realtime-ге тәуелсіз, тұрақты) =================

  /// Периодты сұраныс стримі. Қате болса соңғы мәнді сақтап, қайта сұрайды —
  /// осылайша 4G-де realtime channelError болмайды.
  static Stream<T> _poll<T>(Future<T> Function() fetch,
      {Duration every = const Duration(seconds: 4)}) async* {
    while (true) {
      try {
        yield await fetch();
      } catch (_) {
        // соңғы мәнде қалады, экранда loader көрсетілмейді
      }
      await Future.delayed(every);
    }
  }

  static Stream<List<Order>> myOrdersStream() {
    final id = uid;
    if (id == null) return const Stream.empty();
    return _poll(() async {
      final rows = await c
          .from('orders')
          .select()
          .eq('client_id', id)
          .order('created_at');
      return (rows as List)
          .map((m) => Order.fromMap(Map<String, dynamic>.from(m)))
          .toList();
    });
  }

  static Stream<Order?> orderStream(String orderId) => _poll(() async {
        final m = await c
            .from('orders')
            .select()
            .eq('id', orderId)
            .maybeSingle();
        return m == null ? null : Order.fromMap(m);
      }, every: const Duration(seconds: 3));

  /// Лента: іздеудегі bidding заказдар (өлшемі сай).
  static Stream<List<Order>> feedStream(VehicleSize mySize) => _poll(() async {
        final rows = await c
            .from('orders')
            .select()
            .eq('status', 'searching')
            .eq('type', 'bidding')
            .eq('size', mySize.db)
            .order('created_at');
        return (rows as List)
            .map((m) => Order.fromMap(Map<String, dynamic>.from(m)))
            .toList();
      }, every: const Duration(seconds: 4));

  static Stream<List<Offer>> offersStream(String orderId) => _poll(() async {
        final rows = await c
            .from('offers')
            .select()
            .eq('order_id', orderId)
            .order('created_at');
        return (rows as List)
            .map((m) => Offer.fromMap(Map<String, dynamic>.from(m)))
            .toList();
      }, every: const Duration(seconds: 3));

  static Stream<List<VipDispatch>> myDispatchesStream() {
    final id = uid;
    if (id == null) return const Stream.empty();
    return _poll(() async {
      final rows = await c
          .from('vip_dispatches')
          .select()
          .eq('executor_id', id)
          .order('created_at');
      return (rows as List)
          .map((m) => VipDispatch.fromMap(Map<String, dynamic>.from(m)))
          .toList();
    }, every: const Duration(seconds: 2));
  }

  static Stream<List<VipDispatch>> orderDispatchesStream(String orderId) =>
      _poll(() async {
        final rows = await c
            .from('vip_dispatches')
            .select()
            .eq('order_id', orderId)
            .order('created_at');
        return (rows as List)
            .map((m) => VipDispatch.fromMap(Map<String, dynamic>.from(m)))
            .toList();
      }, every: const Duration(seconds: 2));

  static Stream<ExecutorProfile?> myExecutorProfileStream() {
    final id = uid;
    if (id == null) return const Stream.empty();
    return _poll(() async {
      final m = await c
          .from('executor_profiles')
          .select()
          .eq('user_id', id)
          .maybeSingle();
      return m == null ? null : ExecutorProfile.fromMap(m);
    }, every: const Duration(seconds: 4));
  }

  // ================= QUERIES =================
  static Future<List<BalanceTxn>> myTxns() async {
    final id = uid;
    if (id == null) return [];
    final rows = await c
        .from('balance_txns')
        .select()
        .eq('executor_id', id)
        .order('created_at', ascending: false)
        .limit(50);
    return (rows as List)
        .map((m) => BalanceTxn.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }

  static Future<List<TopupRequest>> myTopups() async {
    final id = uid;
    if (id == null) return [];
    final rows = await c
        .from('topup_requests')
        .select()
        .eq('executor_id', id)
        .order('created_at', ascending: false)
        .limit(30);
    return (rows as List)
        .map((m) => TopupRequest.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }

  static Future<List<Map<String, dynamic>>> myEarnings() async {
    final id = uid;
    if (id == null) return [];
    final rows = await c
        .from('earnings')
        .select()
        .eq('executor_id', id)
        .order('created_at', ascending: false)
        .limit(60);
    return (rows as List).map((m) => Map<String, dynamic>.from(m)).toList();
  }

  /// Осы адам туралы (target) қалдырылған пікірлер — клиент те, орындаушы да.
  static Future<List<Review>> reviewsOf(String userId) async {
    final rows = await c
        .from('reviews')
        .select()
        .eq('target_id', userId)
        .order('created_at', ascending: false)
        .limit(50);
    return (rows as List)
        .map((m) => Review.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }

  // ---- moderator queries ----
  static Future<List<ExecutorProfile>> executorsByStatus(String? status) async {
    var q = c.from('executor_profiles').select();
    final rows = status == null
        ? await q.order('created_at', ascending: false).limit(100)
        : await q.eq('status', status).order('created_at').limit(100);
    return (rows as List)
        .map((m) => ExecutorProfile.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }

  static Future<List<TopupRequest>> topupsByStatus(String status) async {
    final rows = await c
        .from('topup_requests')
        .select()
        .eq('status', status)
        .order('created_at')
        .limit(100);
    return (rows as List)
        .map((m) => TopupRequest.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }

  // ================= STORAGE =================
  /// Файлды docs бакетіне жүктеп, жолын қайтарады.
  static Future<String> uploadDoc(String name, Uint8List bytes) async {
    final id = uid;
    if (id == null) throw Exception('AUTH');
    final path = '$id/${DateTime.now().millisecondsSinceEpoch}_$name';
    await c.storage.from('docs').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'),
        );
    return path;
  }

  static Future<String> signedDocUrl(String path) =>
      c.storage.from('docs').createSignedUrl(path, 3600);
}

// ================= RIVERPOD PROVIDERS =================
final authStateProvider = StreamProvider<AuthState>(
    (ref) => Supabase.instance.client.auth.onAuthStateChange);

final myProfileProvider = FutureProvider<Profile?>((ref) {
  ref.watch(authStateProvider);
  return Repo.myProfile();
});

final myExecutorProfileProvider = FutureProvider<ExecutorProfile?>((ref) {
  ref.watch(authStateProvider);
  return Repo.myExecutorProfile();
});

final appConfigProvider = FutureProvider<AppConfig>((ref) async {
  final s = await Repo.settings();
  final payment = s['payment'];
  return AppConfig.fromSettings(
      payment is Map ? Map<String, dynamic>.from(payment) : null);
});

final executorStatsProvider =
    FutureProvider<ExecutorStats>((ref) => Repo.executorStats());

/// Тікелей жаңарып отыратын статистика стримі.
final executorStatsStreamProvider =
    StreamProvider<ExecutorStats>((ref) => Repo.executorStatsStream());
