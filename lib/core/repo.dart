import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';
import 'phone.dart';

/// Барлық дерек-қатынас осы жерде: Supabase RPC, стримдер, storage.
class Repo {
  static SupabaseClient get c => Supabase.instance.client;
  static String? get uid => c.auth.currentUser?.id;

  // ================= AUTH (телефон + құпиясөз, SMS-сыз) =================
  /// Телефон + құпиясөзбен кіру. Ішкі жағынан синтетикалық email қолданылады.
  static Future<void> signInPhone(String phone, String password) async {
    final email = Phone.emailOf(phone);
    if (email == null) throw Exception('BAD_PHONE');
    await c.auth.signInWithPassword(email: email, password: password);
  }

  /// Тіркелу — SMS растаусыз, бірден аккаунт құрылып, автоматты кіреді.
  /// Алдымен `signup` edge function (email растауын айналып өтеді),
  /// ол қолжетімсіз болса — тікелей auth.signUp арқылы.
  /// Telegram верификация сессиясын бастайды (0026) — токен қайтарады.
  static Future<String> tgStartVerification() async {
    final res = await c.rpc('tg_start_verification');
    return res as String;
  }

  /// Telegram верификация статусын сұрайды (0026) — {verified, phone}.
  static Future<Map<String, dynamic>> tgCheckVerification(String token) async {
    final res =
        await c.rpc('tg_check_verification', params: {'p_token': token});
    return Map<String, dynamic>.from(res as Map);
  }

  /// Құпиясөзді Telegram растауымен қалпына келтіру: `reset-password` edge
  /// функциясы нөмір иесіне жаңа құпиясөз қояды, сосын автоматты кіреміз.
  static Future<void> resetPasswordViaTelegram({
    required String tgToken,
    required String newPassword,
    required String phone,
  }) async {
    try {
      final res = await c.functions.invoke('reset-password', body: {
        'tg_token': tgToken,
        'new_password': newPassword,
      });
      final data = res.data;
      if (data is Map && data['error'] != null) {
        throw Exception(data['error'].toString());
      }
    } on FunctionException catch (e) {
      final d = e.details;
      if (d is Map && d['error'] != null) throw Exception(d['error'].toString());
      throw Exception('SERVER_ERROR');
    }
    final n = Phone.normalize(phone);
    if (n != null) await signInPhone(n, newPassword);
  }

  static Future<void> signUpPhone({
    required String phone,
    required String password,
    required String fullName,
    required String role, // client | executor
    required String tgToken, // Telegram-мен расталған сессия токені
  }) async {
    final n = Phone.normalize(phone);
    final email = Phone.emailOf(phone);
    if (n == null || email == null) throw Exception('BAD_PHONE');
    try {
      await c.functions.invoke('signup', body: {
        'password': password,
        'full_name': fullName.trim(),
        'role': role,
        'tg_token': tgToken,
      });
    } on FunctionException catch (e) {
      final d = e.details;
      if (d is Map && d['error'] != null) {
        // функция жетті, бірақ валидация қатесін қайтарды
        final code = d['error'].toString();
        throw Exception(code == 'EMAIL_TAKEN' ? 'PHONE_TAKEN' : code);
      }
      // функция табылмады/рұқсат жоқ (404, 401...) — тікелей тіркелеміз
      await _directSignUp(
          email: email, password: password, fullName: fullName,
          phone: n, role: role);
    } catch (e) {
      if (e.toString().contains('EMAIL_CONFIRM_REQUIRED')) rethrow;
      // желі қатесі т.б. — тікелей тіркелуді көреміз
      await _directSignUp(
          email: email, password: password, fullName: fullName,
          phone: n, role: role);
    }
    await signInPhone(n, password);
  }

  static Future<void> _directSignUp({
    required String email,
    required String password,
    required String fullName,
    required String phone,
    required String role,
  }) async {
    final res = await c.auth.signUp(
      email: email,
      password: password,
      data: {
        'full_name': fullName.trim(),
        'phone': phone,
        'role': role,
      },
    );
    if (res.session == null) {
      // Supabase-те "Confirm email" қосулы — сессия берілмеді
      throw Exception('EMAIL_CONFIRM_REQUIRED');
    }
  }

  static Future<void> signOut() => c.auth.signOut();

  /// Кіру сәтсіз болғанда: бұл нөмір мүлдем ТІРКЕЛМЕГЕН бе, әлде тек
  /// құпиясөз қате ме? (0046). Сервер тек `true/false` қайтарады — басқа
  /// ешбір дерек ашылмайды. Желі қатесінде `null` — «білмейміз».
  static Future<bool?> phoneRegistered(String phone) async {
    final n = Phone.normalize(phone);
    if (n == null) return null;
    try {
      return (await c.rpc('phone_registered', params: {'p_phone': n})) as bool?;
    } catch (_) {
      return null;
    }
  }

  /// FCM push-токенін сақтайды (0019 миграциясы) — қосымша жабық болса да
  /// жеткізілетін хабарландырулар үшін (мыс. модераторға жаңа өтінім).
  static Future<void> savePushToken(String token, String platform) =>
      c.rpc('save_push_token', params: {
        'p_token': token,
        'p_platform': platform,
      });

  /// Аккаунттан шыққанда осы құрылғының токенін өшіреді (0045) — әйтпесе
  /// телефон ескі иесінің push-ын ала береді.
  static Future<void> deletePushToken(String token) =>
      c.rpc('delete_push_token', params: {'p_token': token});

  /// Қосымша тілін СЕРВЕРГЕ сақтайды (0045): push сол тілде БІР РЕТ келеді.
  static Future<void> setMyLang(String lang) =>
      c.rpc('set_my_lang', params: {'p_lang': lang});

  /// Күдікті жүк туралы модераторға дереу хабарлайды (0021 миграциясы) —
  /// заказдың нақты қатысушысы (клиент не орындаушы) ғана жібере алады.
  static Future<void> reportOrder(String orderId, String reason) =>
      c.rpc('report_order', params: {
        'p_order': orderId,
        'p_reason': reason,
      });

  /// Жеңіл эвристикалық «тексеру қажет» флагы (0022) — модераторға ғана.
  static Future<Map<String, dynamic>> orderFraudFlags(String orderId) async {
    final res = await c.rpc('order_fraud_flags', params: {'p_order': orderId});
    return Map<String, dynamic>.from(res as Map);
  }

  /// Модератордың «Хабарламалар» тізімі (0024) — соңғылары бірінші.
  static Stream<List<OrderReport>> openReportsStream() => _poll(() async {
        final rows = await c
            .from('order_reports')
            .select()
            .order('created_at', ascending: false)
            .limit(100);
        return (rows as List)
            .map((m) => OrderReport.fromMap(Map<String, dynamic>.from(m)))
            .toList();
      }, every: const Duration(seconds: 6));

  /// Хабарламаны «қаралды/елеусіз қалдырылды» деп белгілеу (0024).
  static Future<void> modSetReportStatus(String reportId, String status) =>
      c.rpc('mod_set_report_status',
          params: {'p_report': reportId, 'p_status': status});

  /// Пайдаланушының сенім деңгейін қолмен түзету (0024, тек модератор).
  static Future<int> modAdjustTrustScore(
      String userId, int delta, String reason) async {
    final res = await c.rpc('mod_adjust_trust_score', params: {
      'p_user': userId,
      'p_delta': delta,
      'p_reason': reason,
    });
    return (Map<String, dynamic>.from(res as Map)['trust_score'] as num)
        .toInt();
  }

  /// Аккаунтты қолмен блоктау/блоктан шығару (0024, тек модератор).
  static Future<void> modSetAccountBlocked(
          String userId, bool blocked, String reason) =>
      c.rpc('mod_set_account_blocked', params: {
        'p_user': userId,
        'p_blocked': blocked,
        'p_reason': reason,
      });

  /// Аккаунтты біржола өшіру (App Store/Play талабы + 94-V «өшіру құқығы»).
  /// Сервер белсенді заказ болса HAS_ACTIVE_ORDERS қайтарады.
  static Future<void> deleteAccount() async {
    try {
      final res = await c.functions.invoke('delete-account');
      final data = res.data;
      if (data is Map && data['error'] != null) {
        throw Exception(data['error'].toString());
      }
    } on FunctionException catch (e) {
      final d = e.details;
      if (d is Map && d['error'] != null) {
        throw Exception(d['error'].toString());
      }
      throw Exception('SERVER_ERROR');
    }
    await c.auth.signOut();
  }

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

  // ================= ҚОС РӨЛ (0046) =================
  /// Рөлді ауыстыру («Орындаушы болу» / «Клиентке ауысу»). Бұл — рөлді
  /// АЛМАСТЫРУ емес, ҚОСЫМША рөл алу: екеуі де аккаунтта сақталады, тек
  /// қайсысы БЕЛСЕНДІ екені өзгереді (inDriver үлгісі). Рейтинг те рөлге
  /// бөлек: клиенттік баға орындаушы режимінде көрінбейді, керісінше де.
  ///
  /// Қайтарады: `needs_application` — орындаушы профилі әлі жоқ, өтінім
  /// толтыру экраны ашылуы керек.
  static Future<bool> switchRole(String role) async {
    final res = await c.rpc('switch_role', params: {'p_role': role});
    final m = Map<String, dynamic>.from(res as Map);
    return m['needs_application'] as bool? ?? false;
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

  /// Орындаушы өтінімі (жаңа немесе қайта жіберу). Көлік ТҮРІ таңдалады.
  static Future<void> submitExecutorApplication({
    required VehicleType vehicleType,
    required String brand,
    required String model,
    int? year,
    required String plate,
    required List<String> vehiclePhotos,
    String? idDocPath,
    String? licensePath,
    String? idSelfiePath,
    String? licenseSelfiePath,
    String? passportPath,
    String? passportSelfiePath,
    String? techPassportPath,
    String? techPassportSelfiePath,
    bool isForeignCitizen = false,
    String? city,
    required bool isResubmit,
  }) async {
    final id = uid;
    if (id == null) throw Exception('AUTH');
    final data = {
      'vehicle_size': 'small', // өлшем ескерілмейді (кестеде not-null болғандықтан)
      'vehicle_type': vehicleType.db,
      'vehicle_brand': brand.trim(),
      'vehicle_model': model.trim(),
      'vehicle_year': year,
      'vehicle_plate': plate.trim(),
      'vehicle_photos': vehiclePhotos,
      'id_doc_path': idDocPath,
      'license_path': licensePath,
      'id_selfie_path': idSelfiePath,
      'license_selfie_path': licenseSelfiePath,
      'passport_path': passportPath,
      'passport_selfie_path': passportSelfiePath,
      'tech_passport_path': techPassportPath,
      'tech_passport_selfie_path': techPassportSelfiePath,
      'is_foreign_citizen': isForeignCitizen,
      if (city != null && city.trim().isNotEmpty) 'city': city.trim(),
    };
    if (isResubmit) {
      // ескі құжат жолдарын жинап, жаңасына сай еместерін өшіреміз
      final old = await c
          .from('executor_profiles')
          .select('status, id_doc_path, license_path, id_selfie_path, '
              'license_selfie_path, passport_path, passport_selfie_path, '
              'tech_passport_path, tech_passport_selfie_path, vehicle_photos')
          .eq('user_id', id)
          .maybeSingle();
      final newPaths = <String?>{
        idDocPath,
        licensePath,
        idSelfiePath,
        licenseSelfiePath,
        passportPath,
        passportSelfiePath,
        techPassportPath,
        techPassportSelfiePath,
        ...vehiclePhotos,
      };
      final oldPaths = <String>[];
      if (old != null) {
        for (final k in [
          'id_doc_path',
          'license_path',
          'id_selfie_path',
          'license_selfie_path',
          'passport_path',
          'passport_selfie_path',
          'tech_passport_path',
          'tech_passport_selfie_path',
        ]) {
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

  /// «Такси» бөлімі қосулы ма (0046, модератор баптауы). Желі қатесінде
  /// `false` — бөлім жай ғана көрінбейді, ешбір экран сынбайды.
  static Future<bool> taxiEnabled() async {
    try {
      return (await c.rpc('taxi_enabled')) as bool? ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Мәжбүрлі жаңарту баптауы (0030) — авторизациясыз да шақырылады
  /// (кіру экранында тұрған ескі нұсқаны да бұғаттау үшін).
  static Future<Map<String, dynamic>> appVersionGate() async {
    final res = await c.rpc('app_version_gate');
    return Map<String, dynamic>.from(res as Map);
  }

  /// Модератор баптауды өзгертеді (тариф бағасы, Kaspi деректері, мәжбүрлі
  /// жаңарту талабы) — SQL-сыз, 0030 миграциясы.
  static Future<void> modUpdateSetting(String key, Map<String, dynamic> value) =>
      c.rpc('mod_update_setting', params: {'p_key': key, 'p_value': value});

  // ================= КӨЛІК ТҮРЛЕРІНІҢ КАТАЛОГЫ (0050) =================
  /// Клиент/орындаушы көретін БЕЛСЕНДІ түрлер (такси өшірулі болса —
  /// такси мен доставкасыз). [VehicleCatalog.load] осыны шақырады.
  static Future<List<Map<String, dynamic>>> vehicleCatalog() async {
    final rows = await c.rpc('vehicle_catalog');
    return [
      for (final r in rows as List) Map<String, dynamic>.from(r as Map),
    ];
  }

  /// Модератордың ТОЛЫҚ тізімі — өшірулі түрлерін де қоса.
  static Future<List<Map<String, dynamic>>> modVehicleTypes() async {
    final rows = await c.rpc('mod_vehicle_types');
    return [
      for (final r in rows as List) Map<String, dynamic>.from(r as Map),
    ];
  }

  /// Түрді қосу не өзгерту. `null` берілген өріс ӨЗГЕРМЕЙДІ (жаңа түрде
  /// әдепкі мәнін алады) — сол себепті бір ғана өрісті жаңартуға да болады.
  static Future<Map<String, dynamic>> modSaveVehicleType({
    required String code,
    String? labelKk,
    String? labelRu,
    String? descKk,
    String? descRu,
    String? iconUrl,
    String? emoji,
    bool? isTaxi,
    bool? active,
  }) async {
    final res = await c.rpc('mod_save_vehicle_type', params: {
      'p_code': code,
      'p_label_kk': labelKk,
      'p_label_ru': labelRu,
      'p_desc_kk': descKk,
      'p_desc_ru': descRu,
      'p_icon_url': iconUrl,
      'p_emoji': emoji,
      'p_is_taxi': isTaxi,
      'p_active': active,
    });
    return Map<String, dynamic>.from(res as Map);
  }

  /// Тізімнің РЕТІН сақтау — кодтар берілген ретпен нөмірленеді.
  static Future<void> modReorderVehicleTypes(List<String> codes) =>
      c.rpc('mod_reorder_vehicle_types', params: {'p_codes': codes});

  /// Түрді жою. Қолданыста болса (заказ/орындаушы/хабарландыру) немесе
  /// қосымшамен бірге келген болса — ЖОЙЫЛМАЙДЫ, тек өшіріледі.
  /// Қайтарады: `'deleted'` не `'deactivated'`.
  static Future<String> modDeleteVehicleType(String code) async =>
      (await c.rpc('mod_delete_vehicle_type', params: {'p_code': code}))
          as String;

  /// Көлік түрінің иконкасын жүктеу (PNG). Ескі файл ҚАЛДЫРЫЛМАЙДЫ:
  /// сілтемеде уақыт белгісі бар, сол себепті кэштегі ескі сурет жабысып
  /// қалмайды. Қайтарады: көпшілікке ашық сілтеме.
  static Future<String> uploadVehicleIcon(String code, Uint8List png) async {
    final path = '$code/${DateTime.now().millisecondsSinceEpoch}.png';
    await c.storage.from('vehicle-icons').uploadBinary(
          path,
          png,
          fileOptions: const FileOptions(upsert: true, contentType: 'image/png'),
        );
    return c.storage.from('vehicle-icons').getPublicUrl(path);
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

  /// Орындаушы линияға кіру/шығуы (жаңа заказ хабарламалары үшін).
  static Future<void> setOnLine(bool value) =>
      c.rpc('set_on_line', params: {'p_value': value});

  static Future<String> createOrder({
    required VehicleType vehicleType, // қажет көлік түрі
    required String fromAddress,
    required double fromLat,
    required double fromLng,
    required String toAddress,
    required double toLat,
    required double toLng,
    required double distanceKm,
    required String cargo,
    required String comment,
    int? clientPrice,
    List<String> photos = const [],
    String? fromCity,
    String? toCity,
    /// Аралық аялдамалар (0047) — алу мен ақырғы жеткізу АРАСЫНДАҒЫ
    /// нүктелер, клиент қосқан РЕТПЕН. Сервер тексеріп, тазалап сақтайды
    /// (`clean_order_stops`): шектен асса `TOO_MANY_STOPS`.
    List<OrderStop> stops = const [],
  }) async {
    final res = await c.rpc('create_order', params: {
      'p_type': 'bidding',
      'p_stops': stops.map((s) => s.toMap()).toList(),
      'p_from_address': fromAddress,
      'p_from_lat': fromLat,
      'p_from_lng': fromLng,
      'p_to_address': toAddress,
      'p_to_lat': toLat,
      'p_to_lng': toLng,
      'p_distance_km': distanceKm,
      'p_cargo': cargo,
      'p_comment': comment,
      'p_size': 'small', // өлшем ескерілмейді (кері үйлесімділік үшін)
      'p_client_price': clientPrice,
      'p_photos': photos,
      'p_from_city': fromCity,
      'p_to_city': toCity,
      'p_vehicle_type': vehicleType.db,
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
          // upsert=false: жол әрқашан бірегей (timestamp), қайшылық болмайды.
          // upsert=true болса Storage "ON CONFLICT DO UPDATE" шығарады да,
          // ол UPDATE RLS саясатын талап етіп, 403 бере алады.
          fileOptions: const FileOptions(contentType: 'image/jpeg'),
        );
    return path;
  }

  static String orderPhotoUrl(String path) =>
      c.storage.from('orders').getPublicUrl(path);

  // ============ АДРЕС ТҮЗЕТУЛЕРІ (crowd-fix) ============
  /// Нүктенің маңайында клиенттер бұрын түзеткен атау бар ма (болса — соны).
  static Future<String?> nearbyAddress(double lat, double lng) async {
    try {
      final r = await c.rpc('nearby_address',
          params: {'p_lat': lat, 'p_lng': lng});
      if (r is String && r.trim().isNotEmpty) return r;
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Клиент нүктенің атын түзетсе — сол координатаға сақтау (кейін ұсыну үшін).
  static Future<void> saveAddressCorrection(
      double lat, double lng, String label) async {
    try {
      await c.rpc('save_address_correction',
          params: {'p_lat': lat, 'p_lng': lng, 'p_label': label});
    } catch (_) {}
  }

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

  static Future<void> modReviewTopup(String id, bool approve, String note,
      {String? receiptPath}) async {
    await c.rpc('mod_review_topup', params: {
      'p_topup': id,
      'p_approve': approve,
      'p_note': note,
    });
    // чек суреті қаралып біткен соң қажет емес — орынды босатамыз
    if (receiptPath != null) {
      try {
        await c.storage.from('docs').remove([receiptPath]);
      } catch (_) {}
    }
  }

  /// Жабылған қолдау тредтерінің суреттерін тазалау (модератор ғана).
  static Future<void> cleanupSupportImages() async {
    try {
      final paths =
          (await c.rpc('mod_pending_support_images') as List).cast<String>();
      if (paths.isNotEmpty) {
        await c.storage.from('support').remove(paths);
      }
    } catch (_) {}
  }

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
  /// Нақты ауыстырылған өрістердің ЕСКІ файлдары Storage-тан да өшіріледі
  /// (RPC ескі жолдарды қайтарады — тимеген өрістер жойылмайды).
  static Future<void> submitDocsUpdate({
    String? idDocPath,
    String? licensePath,
    String? idSelfiePath,
    String? licenseSelfiePath,
    String? passportPath,
    String? passportSelfiePath,
    String? techPassportPath,
    String? techPassportSelfiePath,
    List<String>? photos,
  }) async {
    final res = await c.rpc('submit_docs_update', params: {
      'p_id_doc': idDocPath,
      'p_license': licensePath,
      'p_tech': techPassportPath,
      'p_photos': photos,
      'p_id_selfie': idSelfiePath,
      'p_license_selfie': licenseSelfiePath,
      'p_passport': passportPath,
      'p_passport_selfie': passportSelfiePath,
      'p_tech_selfie': techPassportSelfiePath,
    });
    final oldPaths = (res as List?)?.cast<String>() ?? const [];
    if (oldPaths.isNotEmpty) {
      try {
        await c.storage.from('docs').remove(oldPaths);
      } catch (_) {}
    }
  }

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

  /// AI кеңесшісі (тек модератор): чат тарихын оқып, жауап жобасы мен
  /// қысқа түсінік ұсынады. ЕШҚАНДАЙ әрекет жасамайды (заказ статусын
  /// өзгертпейді, ешкімге жіберілмейді) — тек модераторға көрсетіледі,
  /// модератор өзі оқып/түзетіп жібереді.
  static Future<Map<String, dynamic>> supportAssistantSuggest(
    String threadId,
  ) async {
    final res = await c.functions
        .invoke('support-assistant', body: {'thread_id': threadId});
    final data = res.data;
    if (data is Map) return Map<String, dynamic>.from(data);
    throw Exception('SUPPORT_ASSISTANT_FAILED');
  }

  /// Қолдау чатына сурет жүктеу (public 'support' бакеті).
  static Future<String> uploadSupportImage(Uint8List bytes) async {
    final id = uid;
    if (id == null) throw Exception('AUTH');
    final path = '$id/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await c.storage.from('support').uploadBinary(
          path,
          bytes,
          // upsert=false: жол бірегей — «ON CONFLICT DO UPDATE» шақырмай,
          // тек INSERT саясатымен жұмыс істейді (403 болмайды).
          fileOptions: const FileOptions(contentType: 'image/jpeg'),
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

  /// Орындаушының белсенді заказдары (accepted/arrived/loading/in_transit).
  /// §5 межгород маршрут-стектеу арқылы бір мезгілде 2 заказ болуы мүмкін —
  /// сол себепті `executor_profiles.busy_order_id` (жалғыз өріс) емес,
  /// тікелей `orders` кестесінен тізім ретінде аламыз.
  static Stream<List<Order>> myActiveExecutorOrdersStream() {
    final id = uid;
    if (id == null) return const Stream.empty();
    return _poll(() async {
      final rows = await c
          .from('orders')
          .select()
          .eq('executor_id', id)
          .inFilter('status', const [
        'accepted',
        'arrived',
        'loading',
        'in_transit'
      ]).order('accepted_at');
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

  /// §6/§5 Лента: орындаушының қаласы мен маршрутына сай заказдар (RPC).
  /// Қала фильтрі, өлшем сәйкестігі, межгород маршруты — бәрі серверде
  /// `executor_feed` ішінде (бір ғана логика көзі).
  static Stream<List<Order>> executorFeedStream() => _poll(() async {
        final rows = await c.rpc('executor_feed');
        return (rows as List)
            .map((m) => Order.fromMap(Map<String, dynamic>.from(m)))
            .toList();
      }, every: const Duration(seconds: 4));

  /// §6 Орындаушының тіркелген қаласын орнату/жаңарту.
  static Future<void> setExecutorCity(String city) =>
      c.rpc('set_executor_city', params: {'p_city': city});

  /// Жаңа заказ push-хабарландыруын серверде қосу/өшіру (қосымша толық
  /// жабық болса да — трафикке осы мән әсер етеді).
  static Future<void> setOrderPushEnabled(bool enabled) =>
      c.rpc('set_order_push_enabled', params: {'p_enabled': enabled});

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

  // ================= ХАБАРЛАНДЫРУЛАР ТАҚТАСЫ (0043) =================
  /// Тақта қосулы ма (модератор Баптаулардан басқарады). Желі қатесінде
  /// `false` — фича «жоқ» болып қалады, ешбір экран сынбайды.
  static Future<bool> boardEnabled() async {
    try {
      return (await c.rpc('board_enabled')) as bool? ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Лента: ҚАРСЫ рөлдің хабарландырулары (сервер рөл бойынша өзі шешеді —
  /// клиентке қызметтер, орындаушыға жұмыстар). [city] бос болса — барлық
  /// қала, [vehicle] null болса — барлық көлік түрі.
  static Future<List<Listing>> boardFeed({
    String? city,
    VehicleType? vehicle,
  }) async {
    final rows = await c.rpc(
      'board_feed',
      params: {'p_city': city ?? '', 'p_vehicle': vehicle?.db ?? 'all'},
    );
    return (rows as List)
        .map((m) => Listing.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }

  /// Өз хабарландыруларым (белсенді + мерзімі өткені), көру санымен.
  static Future<List<Listing>> myListings() async {
    final rows = await c.rpc('my_listings');
    return (rows as List)
        .map((m) => Listing.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }

  /// Хабарландыруды ашу — көруді тіркейді (бір адам = 1 көру) әрі байланыс
  /// телефонын қоса қайтарады.
  static Future<Listing> openListing(String id) async {
    final m = await c.rpc('open_listing', params: {'p_id': id});
    return Listing.fromMap(Map<String, dynamic>.from(m as Map));
  }

  /// Хабарландыру жариялау. Түрі (жұмыс/қызмет) рөлден автоматты анықталады.
  static Future<String> createListing({
    required VehicleType vehicleType,
    required String city,
    required String body,
    String priceText = '',
    int durationDays = 0,
    List<String> photos = const [],
  }) async {
    final res = await c.rpc('create_listing', params: {
      'p_vehicle_type': vehicleType.db,
      'p_city': city,
      'p_body': body,
      'p_price_text': priceText,
      'p_duration_days': durationDays,
      'p_photos': photos,
    });
    return res as String;
  }

  /// Өз хабарландыруын мерзімінен бұрын алып тастау (архивке).
  static Future<void> archiveListing(String id) =>
      c.rpc('archive_listing', params: {'p_id': id});

  /// Архивтегіні қайта жариялау — мерзім жаңа [kListingDays] күнге ұзарады,
  /// көру саны нөлден басталады. Ескі фотолар Storage-тан өшіп кеткен, сол
  /// себепті [photos] қайта беріледі. Қалған өрістер де түзетілуі мүмкін.
  static Future<void> repostListing({
    required String id,
    required List<String> photos,
    required String body,
    required String priceText,
    required VehicleType vehicleType,
    required String city,
    int durationDays = 0,
  }) =>
      c.rpc('repost_listing', params: {
        'p_id': id,
        'p_photos': photos,
        'p_body': body,
        'p_price_text': priceText,
        'p_vehicle_type': vehicleType.db,
        'p_city': city,
        'p_duration_days': durationDays,
      });

  static Future<void> deleteListing(String id) =>
      c.rpc('delete_listing', params: {'p_id': id});

  /// Хабарландыру фотосын жүктеу (public 'listings' бакеті). Жолын қайтарады.
  static Future<String> uploadListingPhoto(Uint8List bytes, int index) async {
    final id = uid;
    if (id == null) throw Exception('AUTH');
    final path = '$id/${DateTime.now().millisecondsSinceEpoch}_$index.jpg';
    await c.storage.from('listings').uploadBinary(
          path,
          bytes,
          // upsert=false: жол timestamp арқылы бірегей — UPDATE саясаты
          // талап етілмейді (orders бакетіндегідей тәртіп).
          fileOptions: const FileOptions(contentType: 'image/jpeg'),
        );
    return path;
  }

  static String listingPhotoUrl(String path) =>
      c.storage.from('listings').getPublicUrl(path);

  /// Модератордың жалпы шолу статистикасы (пайдаланушылар, заказдар,
  /// хабарландырулар — бір сұраныста).
  static Future<Map<String, dynamic>> modOverviewStats() async =>
      Map<String, dynamic>.from(await c.rpc('mod_overview_stats') as Map);

  /// Модераторға хабарландырулар тізімі. [status]: active | expired | null.
  static Future<List<Listing>> modListings(String? status) async {
    final rows = await c.rpc('mod_listings', params: {'p_status': status ?? ''});
    return (rows as List)
        .map((m) => Listing.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }

  // ---- хабарландыруға шағым (0044) ----
  /// Күдікті хабарландыру туралы модераторға шағым жіберу. Бір адам бір
  /// хабарландыруға бір ғана ашық шағым бере алады ('ALREADY_REPORTED').
  static Future<String> reportListing(String listingId, String reason) async =>
      (await c.rpc('report_listing', params: {
        'p_listing': listingId,
        'p_reason': reason,
      })) as String;

  /// Модераторға шағымдар тізімі. [status]: open | closed | '' (барлығы).
  static Future<List<ListingReport>> modListingReports(String status) async {
    final rows =
        await c.rpc('mod_listing_reports', params: {'p_status': status});
    return (rows as List)
        .map((m) => ListingReport.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }

  /// Модератордың шешімі. [action]: 'delete' (хабарландыруды өшіру, сол
  /// хабарландырудың барлық ашық шағымы жабылады) | 'keep' (елеусіз қалдыру).
  static Future<void> modResolveListingReport(String id, String action) =>
      c.rpc('mod_resolve_listing_report',
          params: {'p_id': id, 'p_action': action});

  // ================= STORAGE =================
  /// Файлды docs бакетіне жүктеп, жолын қайтарады. Content-type файл
  /// атының кеңейтіміне қарай анықталады — Kaspi кейде скриншотты
  /// бұғаттайды, сол кезде орындаушы чекті PDF ретінде жүктейді (0051+).
  static Future<String> uploadDoc(String name, Uint8List bytes) async {
    final id = uid;
    if (id == null) throw Exception('AUTH');
    final path = '$id/${DateTime.now().millisecondsSinceEpoch}_$name';
    await c.storage.from('docs').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            upsert: true,
            contentType: _contentTypeFor(name),
          ),
        );
    return path;
  }

  static String _contentTypeFor(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.pdf')) return 'application/pdf';
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  static Future<String> signedDocUrl(String path) =>
      c.storage.from('docs').createSignedUrl(path, 3600);

  // ============ ТОЛТЫРУ ЧЕГІН ТЕКСЕРЕТІН БОТ (0051) ============
  /// Kaspi Pay выпискасын `docs` бакетіне жүктейді. Бөлек bucket құрылмайды:
  /// `docs_insert_own` саясаты бойынша модератор ӨЗ папкасына жаза алады, ал
  /// edge функция оны service-role кілтімен оқиды.
  static Future<String> uploadStatement(String name, Uint8List bytes) async {
    final id = uid;
    if (id == null) throw Exception('AUTH');
    final path = '$id/${DateTime.now().millisecondsSinceEpoch}_$name';
    await c.storage.from('docs').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            upsert: true,
            contentType: name.toLowerCase().endsWith('.csv')
                ? 'text/csv'
                : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          ),
        );
    return path;
  }

  /// Жүктелген выписканы талдап базаға салады және расталған толтыруларды
  /// сол тізіммен САЛЫСТЫРАДЫ. Қайтаратыны:
  /// `{parsed, inserted, skipped, checked, missing, missing_rows}`.
  static Future<Map<String, dynamic>> importKaspiStatement(String path) async {
    final res = await c.functions.invoke('kaspi-statement', body: {'path': path});
    final data = res.data;
    if (data is Map) return Map<String, dynamic>.from(data);
    throw Exception('STATEMENT_FAILED');
  }

  /// Соңғы [days] күнде расталған толтырулар — әрқайсысы выпискадан
  /// табылды ма (`matched`). Тек модератор шақыра алады.
  static Future<List<Map<String, dynamic>>> topupReconciliation({
    int days = 30,
  }) async {
    final rows = await c.rpc('topup_reconciliation', params: {'p_days': days});
    return [
      for (final r in rows as List) Map<String, dynamic>.from(r as Map),
    ];
  }
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

/// Хабарландырулар тақтасы қосулы ма (0043). Модератор Баптаулардан
/// қосқанда/өшіргенде `ref.invalidate(boardEnabledProvider)` шақырылады.
final boardEnabledProvider =
    FutureProvider<bool>((ref) => Repo.boardEnabled());

/// «Такси» бөлімі қосулы ма (0046). Модератор Баптаулардан қосқанда/
/// өшіргенде `ref.invalidate(taxiEnabledProvider)` шақырылады.
final taxiEnabledProvider = FutureProvider<bool>((ref) => Repo.taxiEnabled());

/// Тікелей жаңарып отыратын статистика стримі. `autoDispose` — ешкім
/// тыңдамай қалса (мыс. логаут/рөл ауысу) polling тоқтап, жады босайды.
final executorStatsStreamProvider =
    StreamProvider.autoDispose<ExecutorStats>(
        (ref) => Repo.executorStatsStream());

/// Орындаушы лентасы (§5/§6). Riverpod стримді КЭШТЕЙДІ — сондықтан статистика
/// әр 4 сек жаңарғанда бет қайта құрылса да, лента стримі қайта жазылмайды
/// (әйтпесе әр рефреште ресетке түсіп, автообновление «жоғалатын»).
/// `autoDispose` — ешкім тыңдамай қалса polling тоқтайды.
final executorFeedStreamProvider =
    StreamProvider.autoDispose<List<Order>>(
        (ref) => Repo.executorFeedStream());
