import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart'
    show AppLifecycleState, WidgetsBinding, WidgetsBindingObserver;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'env.dart';
import 'models.dart';
import 'phone.dart';
import 'prefs.dart';

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
    final res = await c.rpc(
      'tg_check_verification',
      params: {'p_token': token},
    );
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
      final res = await c.functions.invoke(
        'reset-password',
        body: {'tg_token': tgToken, 'new_password': newPassword},
      );
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
      await c.functions.invoke(
        'signup',
        body: {
          'password': password,
          'full_name': fullName.trim(),
          'role': role,
          'tg_token': tgToken,
        },
      );
    } on FunctionException catch (e) {
      final d = e.details;
      if (d is Map && d['error'] != null) {
        // функция жетті, бірақ валидация қатесін қайтарды
        final code = d['error'].toString();
        throw Exception(code == 'EMAIL_TAKEN' ? 'PHONE_TAKEN' : code);
      }
      // функция табылмады/рұқсат жоқ (404, 401...) — тікелей тіркелеміз
      await _directSignUp(
        email: email,
        password: password,
        fullName: fullName,
        phone: n,
        role: role,
      );
    } catch (e) {
      if (e.toString().contains('EMAIL_CONFIRM_REQUIRED')) rethrow;
      // желі қатесі т.б. — тікелей тіркелуді көреміз
      await _directSignUp(
        email: email,
        password: password,
        fullName: fullName,
        phone: n,
        role: role,
      );
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
      data: {'full_name': fullName.trim(), 'phone': phone, 'role': role},
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
  static Future<void> savePushToken(String token, String platform) => c.rpc(
    'save_push_token',
    params: {'p_token': token, 'p_platform': platform},
  );

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
      c.rpc('report_order', params: {'p_order': orderId, 'p_reason': reason});

  /// Жеңіл эвристикалық «тексеру қажет» флагы (0022) — модераторға ғана.
  static Future<Map<String, dynamic>> orderFraudFlags(String orderId) async {
    final res = await c.rpc('order_fraud_flags', params: {'p_order': orderId});
    return Map<String, dynamic>.from(res as Map);
  }

  /// Модератордың «Хабарламалар» тізімі (0024) — соңғылары бірінші.
  static Stream<List<OrderReport>> openReportsStream() =>
      _poll('reports', () async {
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
      c.rpc(
        'mod_set_report_status',
        params: {'p_report': reportId, 'p_status': status},
      );

  /// Пайдаланушының сенім деңгейін қолмен түзету (0024, тек модератор).
  static Future<int> modAdjustTrustScore(
    String userId,
    int delta,
    String reason,
  ) async {
    forgetProfile(userId);
    final res = await c.rpc(
      'mod_adjust_trust_score',
      params: {'p_user': userId, 'p_delta': delta, 'p_reason': reason},
    );
    return (Map<String, dynamic>.from(res as Map)['trust_score'] as num)
        .toInt();
  }

  /// Аккаунтты қолмен блоктау/блоктан шығару (0024, тек модератор).
  static Future<void> modSetAccountBlocked(
    String userId,
    bool blocked,
    String reason,
  ) {
    forgetProfile(userId);
    return c.rpc(
      'mod_set_account_blocked',
      params: {'p_user': userId, 'p_blocked': blocked, 'p_reason': reason},
    );
  }

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
    final m = await c.from('profiles').select().eq('id', id).maybeSingle();
    unawaited(Prefs.setCachedProfile(id, m));
    return m == null ? null : Profile.fromMap(m);
  }

  /// Құрылғыда сақталған соңғы профиль (суық іске қосуда бірден көрсету
  /// үшін). Жоқ не бүлінген болса — `null`.
  ///
  /// Бұл — ӨЗ профилімнің ҚҰРЫЛҒЫДАҒЫ кэші (қосымша қайта ашылғанда да
  /// сақталады). Басқа адамдардың профилі — төмендегі [profileOf]-тың
  /// ЖАДТАҒЫ қысқа кэші; екеуі бір-бірін алмастырмайды.
  static Future<Profile?> cachedProfile(String id) async {
    final m = await Prefs.cachedProfile(id);
    if (m == null) return null;
    try {
      return Profile.fromMap(m);
    } catch (_) {
      return null;
    }
  }

  static Future<ExecutorProfile?> cachedExecutorProfile(String id) async {
    final m = await Prefs.cachedExecProfile(id);
    if (m == null) return null;
    try {
      return ExecutorProfile.fromMap(m);
    } catch (_) {
      return null;
    }
  }

  /// Басқа адамның профилі — 60 секундтық ЖАДТАҒЫ КЭШПЕН.
  ///
  /// Бұрын лентадағы, ұсыныстардағы, модератор тізімдеріндегі әр карточка
  /// `FutureBuilder(future: Repo.profileOf(id))` арқылы профильді build
  /// сайын ҚАЙТА сұрайтын — лента әр 4 секунд жаңарғанда әр карточка
  /// желіге қайта шығып, трафик пен батареяны жейтін. Енді бір id-ге бір
  /// Future қайтарылады (FutureBuilder оны «сол Future» деп таниды да,
  /// жыпылықтамайды), ал 60 секундтан кейін ғана жаңартылады.
  static Future<Profile?> profileOf(String id, {bool fresh = false}) {
    final hit = _profileCache[id];
    if (!fresh &&
        hit != null &&
        DateTime.now().difference(hit.$1) < _profileTtl) {
      return hit.$2;
    }
    final f = c
        .from('profiles')
        .select()
        .eq('id', id)
        .maybeSingle()
        .then((m) => m == null ? null : Profile.fromMap(m));
    _profileCache[id] = (DateTime.now(), f);
    // Қате болса кэште қалдырмаймыз — келесі сұрау қайта байқап көреді.
    f.catchError((Object _) {
      _profileCache.remove(id);
      return null;
    });
    return f;
  }

  /// Бірнеше профильді БІР сұраумен алу (модератор тізімдері) — кэшті де
  /// толтырады, сол себепті кейінгі `profileOf` желіге шықпайды.
  static Future<Map<String, Profile>> profilesByIds(List<String> ids) async {
    final unique = ids.toSet().toList();
    if (unique.isEmpty) return const {};
    final rows = await c.from('profiles').select().inFilter('id', unique);
    final out = <String, Profile>{};
    final now = DateTime.now();
    for (final m in rows as List) {
      final p = Profile.fromMap(Map<String, dynamic>.from(m));
      out[p.id] = p;
      _profileCache[p.id] = (now, Future.value(p));
    }
    return out;
  }

  /// Модератор әрекетінен (бұғаттау, сенім, баланс) кейін — сол адамның
  /// кэштегі профилін тастаймыз, келесі көрсетілімде жаңасы келеді.
  static void forgetProfile(String id) {
    _profileCache.remove(id);
    _execProfileCache.remove(id);
  }

  static const _profileTtl = Duration(seconds: 60);
  static final Map<String, (DateTime, Future<Profile?>)> _profileCache = {};

  // ================= MODERATOR WORKSPACE =================
  /// Барлық клиенттер. Moderator RLS policy барлық profile өрістерін оқуға
  /// рұқсат береді, сондықтан тізімде жасырын қысқартылған профиль жоқ.
  static Future<List<Profile>> modClients() async {
    final rows = await c
        .from('profiles')
        .select()
        .eq('has_client_role', true)
        .neq('role', 'moderator')
        .order('created_at', ascending: false)
        .limit(500);
    return (rows as List)
        .map((m) => Profile.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }

  /// Платформадағы барлық заказдар — архивті қоса.
  /// [since] берілсе — тек сол уақыттан бергі заказдар (модератордың
  /// «Бүгін / 7 күн / 30 күн» сүзгісі серверде қолданылады).
  static Future<List<Order>> modAllOrders({DateTime? since}) async {
    var q = c.from('orders').select();
    if (since != null) {
      q = q.gte('created_at', since.toUtc().toIso8601String());
    }
    final rows = await q.order('created_at', ascending: false).limit(1000);
    return (rows as List)
        .map((m) => Order.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }

  static Future<List<Order>> modOrdersOf(
    String userId, {
    bool asExecutor = false,
  }) async {
    final rows = await c
        .from('orders')
        .select()
        .eq(asExecutor ? 'executor_id' : 'client_id', userId)
        .order('created_at', ascending: false)
        .limit(100);
    return (rows as List)
        .map((m) => Order.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }

  static Future<List<SupportThread>> modThreadsOf(String userId) async {
    final rows = await c
        .from('support_threads')
        .select()
        .eq('user_id', userId)
        .order('last_msg_at', ascending: false)
        .limit(100);
    return (rows as List)
        .map((m) => SupportThread.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }

  /// Анонимді тіркелу draft-тері: пароль/құпия деректер ешқашан сақталмайды.
  static Future<void> saveRegistrationDraft({
    required String draftKey,
    required String role,
    required int stage,
    required String stageLabel,
    String? fullName,
    String? phone,
    Map<String, dynamic> data = const {},
    bool completed = false,
  }) => c.rpc(
    'save_registration_draft',
    params: {
      'p_draft_key': draftKey,
      'p_role': role,
      'p_stage': stage,
      'p_stage_label': stageLabel,
      'p_full_name': fullName,
      'p_phone': phone,
      'p_data': data,
      'p_completed': completed,
    },
  );

  static Future<List<Map<String, dynamic>>> modRegistrationDrafts() async {
    final rows = await c.rpc('mod_registration_drafts');
    return (rows as List)
        .map((m) => Map<String, dynamic>.from(m as Map))
        .toList();
  }

  static Future<void> updateProfile({String? fullName, String? phone}) async {
    final id = uid;
    if (id == null) return;
    await c
        .from('profiles')
        .update({
          if (fullName != null) 'full_name': fullName.trim(),
          if (phone != null) 'phone': phone.trim(),
        })
        .eq('id', id);
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
    await c.storage
        .from('avatars')
        .uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            upsert: true,
            contentType: 'image/jpeg',
          ),
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
    unawaited(Prefs.setCachedExecProfile(id, m));
    return m == null ? null : ExecutorProfile.fromMap(m);
  }

  /// Басқа орындаушының профилі (көлігі, нөмірі) — [profileOf] сияқты
  /// 60 секундтық кэшпен.
  static Future<ExecutorProfile?> executorProfileOf(
    String id, {
    bool fresh = false,
  }) {
    final hit = _execProfileCache[id];
    if (!fresh &&
        hit != null &&
        DateTime.now().difference(hit.$1) < _profileTtl) {
      return hit.$2;
    }
    final f = c
        .from('executor_profiles')
        .select()
        .eq('user_id', id)
        .maybeSingle()
        .then((m) => m == null ? null : ExecutorProfile.fromMap(m));
    _execProfileCache[id] = (DateTime.now(), f);
    f.catchError((Object _) {
      _execProfileCache.remove(id);
      return null;
    });
    return f;
  }

  static final Map<String, (DateTime, Future<ExecutorProfile?>)>
  _execProfileCache = {};

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
      'vehicle_size':
          'small', // өлшем ескерілмейді (кестеде not-null болғандықтан)
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
          .select(
            'status, id_doc_path, license_path, id_selfie_path, '
            'license_selfie_path, passport_path, passport_selfie_path, '
            'tech_passport_path, tech_passport_selfie_path, vehicle_photos',
          )
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
        for (final p
            in (old['vehicle_photos'] as List?)?.cast<String>() ?? const []) {
          if (!newPaths.contains(p)) oldPaths.add(p);
        }
      }
      // қабылданбаған болса → pending; расталған болса статус өзгермейді
      final wasRejected = old?['status'] == 'rejected';
      await c
          .from('executor_profiles')
          .update({...data, if (wasRejected) 'status': 'pending'})
          .eq('user_id', id);
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

  /// «ЖАҢА» белгілері көрінсін бе (0058, модератор баптауы). Екеуі БІР
  /// сұраныспен келеді. Желі қатесінде — екеуі де `true`, яғни белгі
  /// баяғыдай көрінеді (жаңа фичаны байқаусыз жасырып алмаймыз).
  static Future<NewBadges> newBadges() async {
    try {
      final res = await c.rpc('new_badges');
      final m = Map<String, dynamic>.from(res as Map);
      return NewBadges(
        board: m['board'] != false,
        taxi: m['taxi'] != false,
        news: m['news'] != false,
      );
    } catch (_) {
      return const NewBadges(board: true, taxi: true, news: true);
    }
  }

  /// Мәжбүрлі жаңарту баптауы (0030) — авторизациясыз да шақырылады
  /// (кіру экранында тұрған ескі нұсқаны да бұғаттау үшін).
  /// Кіру/тіркелу бетіндегі «Көмек» батырмасының WhatsApp нөмірі (0072,
  /// модератор баптауы). Авторизациясыз шақырылады. Желі қатесінде не
  /// баптау бос болса — [Env.supportWhatsApp] (кодтағы әдепкі нөмір).
  static Future<String> supportWhatsApp() async {
    try {
      final res = await c.rpc('support_contact');
      final n = (res is Map ? '${res['whatsapp'] ?? ''}' : '').replaceAll(
        RegExp(r'\D'),
        '',
      );
      if (n.length >= 10) return n;
    } catch (_) {}
    return Env.supportWhatsApp;
  }

  static Future<Map<String, dynamic>> appVersionGate() async {
    final res = await c.rpc('app_version_gate');
    return Map<String, dynamic>.from(res as Map);
  }

  /// Модератор баптауды өзгертеді (тариф бағасы, Kaspi деректері, мәжбүрлі
  /// жаңарту талабы) — SQL-сыз, 0030 миграциясы.
  static Future<void> modUpdateSetting(
    String key,
    Map<String, dynamic> value,
  ) => c.rpc('mod_update_setting', params: {'p_key': key, 'p_value': value});

  // ================= КӨЛІК ТҮРЛЕРІНІҢ КАТАЛОГЫ (0050) =================
  /// Клиент/орындаушы көретін БЕЛСЕНДІ түрлер (такси өшірулі болса —
  /// такси мен доставкасыз). [VehicleCatalog.load] осыны шақырады.
  static Future<List<Map<String, dynamic>>> vehicleCatalog() async {
    final rows = await c.rpc('vehicle_catalog');
    return [for (final r in rows as List) Map<String, dynamic>.from(r as Map)];
  }

  /// Модератордың ТОЛЫҚ тізімі — өшірулі түрлерін де қоса.
  static Future<List<Map<String, dynamic>>> modVehicleTypes() async {
    final rows = await c.rpc('mod_vehicle_types');
    return [for (final r in rows as List) Map<String, dynamic>.from(r as Map)];
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
    final res = await c.rpc(
      'mod_save_vehicle_type',
      params: {
        'p_code': code,
        'p_label_kk': labelKk,
        'p_label_ru': labelRu,
        'p_desc_kk': descKk,
        'p_desc_ru': descRu,
        'p_icon_url': iconUrl,
        'p_emoji': emoji,
        'p_is_taxi': isTaxi,
        'p_active': active,
      },
    );
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
    await c.storage
        .from('vehicle-icons')
        .uploadBinary(
          path,
          png,
          fileOptions: const FileOptions(
            upsert: true,
            contentType: 'image/png',
          ),
        );
    return c.storage.from('vehicle-icons').getPublicUrl(path);
  }

  // ================= RPC wrappers =================
  static Future<Map<String, dynamic>> buyTariff(String kind) async =>
      Map<String, dynamic>.from(
        await c.rpc('buy_tariff', params: {'p_kind': kind}) as Map,
      );

  static Future<ExecutorStats> executorStats() async => ExecutorStats.fromMap(
    Map<String, dynamic>.from(await c.rpc('executor_stats') as Map),
  );

  /// Орындаушы статистикасы — тікелей байланыс (polling, ~4с).
  static Stream<ExecutorStats> executorStatsStream({bool fresh = false}) =>
      _poll(
        'stats:$uid',
        () async => ExecutorStats.fromMap(
          Map<String, dynamic>.from(await c.rpc('executor_stats') as Map),
        ),
        every: const Duration(seconds: 4),
        fresh: fresh,
      );

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

    /// Алдын ала тапсырыс (0060) — заказ дәл осы уақытта ғана орындаушыға
    /// көрінеді. `null` — әдеттегідей «дәл қазір». Фича баптауда өшулі
    /// болса сервер бұны елеусіз қалдырады (қате шықпайды).
    DateTime? scheduledAt,
  }) async {
    final res = await c.rpc(
      'create_order',
      params: {
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
        'p_scheduled_at': scheduledAt?.toIso8601String(),
      },
    );
    return (res as Map)['id'] as String;
  }

  /// Заказ фотосын жүктеу (public 'orders' бакеті). Жолын қайтарады.
  static Future<String> uploadOrderPhoto(Uint8List bytes, int index) async {
    final id = uid;
    if (id == null) throw Exception('AUTH');
    final path = '$id/${DateTime.now().millisecondsSinceEpoch}_$index.jpg';
    await c.storage
        .from('orders')
        .uploadBinary(
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
      final r = await c.rpc(
        'nearby_address',
        params: {'p_lat': lat, 'p_lng': lng},
      );
      if (r is String && r.trim().isNotEmpty) return r;
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Клиент нүктенің атын түзетсе — сол координатаға сақтау (кейін ұсыну үшін).
  static Future<void> saveAddressCorrection(
    double lat,
    double lng,
    String label,
  ) async {
    try {
      await c.rpc(
        'save_address_correction',
        params: {'p_lat': lat, 'p_lng': lng, 'p_label': label},
      );
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

  static Future<void> updateOrderPrice(String orderId, int price) => c.rpc(
    'update_order_price',
    params: {'p_order': orderId, 'p_price': price},
  );

  /// Ұсыныс беру. [etaMin] — «неше минутта жетемін» (0075). Сервер 0075-сіз
  /// болса — ETA хабарламаның басына «~7 мин» болып жазылады (клиент оны
  /// бәрібір көреді, [Offer.etaMin] оқиды).
  static Future<void> placeOffer(
    String orderId,
    int price,
    String message, {
    int? etaMin,
  }) async {
    final base = {'p_order': orderId, 'p_price': price, 'p_message': message};
    if (etaMin == null) {
      await c.rpc('place_offer', params: base);
      return;
    }
    try {
      await c.rpc('place_offer', params: {...base, 'p_eta_min': etaMin});
    } catch (e) {
      if (!isMissingFunction(e)) rethrow;
      final msg = '~$etaMin мин${message.isEmpty ? '' : ' · $message'}';
      await c.rpc('place_offer', params: {...base, 'p_message': msg});
    }
  }

  static Future<void> withdrawOffer(String offerId) =>
      c.rpc('withdraw_offer', params: {'p_offer': offerId});

  static Future<void> acceptOffer(String offerId) =>
      c.rpc('accept_offer', params: {'p_offer': offerId});

  static Future<void> orderAdvance(String orderId, String status) =>
      c.rpc('order_advance', params: {'p_order': orderId, 'p_status': status});

  static Future<void> cancelOrder(String orderId, String reason) =>
      c.rpc('cancel_order', params: {'p_order': orderId, 'p_reason': reason});

  /// Пікір қалдыру. [tags] — бағалау тегтері (0081); сервер 0081-сыз болса
  /// тегсіз жіберіледі (пікір бәрібір сақталады).
  static Future<void> submitReview(
    String orderId,
    int rating,
    String comment, {
    List<String> tags = const [],
  }) async {
    final base = {'p_order': orderId, 'p_rating': rating, 'p_comment': comment};
    if (tags.isEmpty) {
      await c.rpc('submit_review', params: base);
      return;
    }
    try {
      await c.rpc('submit_review', params: {...base, 'p_tags': tags});
    } catch (e) {
      if (!isMissingFunction(e)) rethrow;
      await c.rpc('submit_review', params: base);
    }
  }

  static Future<void> requestTopup(int amount, String? receiptPath) => c.rpc(
    'request_topup',
    params: {'p_amount': amount, 'p_receipt_path': receiptPath},
  );

  // ================= КЛИЕНТ ФИЧАЛАРЫ (0060) =================

  /// Заказды бөлісу сілтемесінің токені (тұрақты — бірінші шақырғанда
  /// серверде жасалады, кейін сол қалпы қайтарылады).
  static Future<String> getOrderShareToken(String orderId) async =>
      (await c.rpc('get_order_share_token', params: {'p_order_id': orderId}))
          as String;

  /// Токен арқылы АВТОРИЗАЦИЯСЫЗ заказ күйін қарау (сапарды бөлісу беті).
  /// `{'error': 'DISABLED'|'NOT_FOUND'}` қайтаруы мүмкін — экран өзі
  /// тексереді.
  static Future<Map<String, dynamic>> trackOrder(String token) async =>
      Map<String, dynamic>.from(
        await c.rpc('track_order', params: {'p_token': token}) as Map,
      );

  /// Орындаушы ағымдағы GPS нүктесін жібереді (белсенді заказы болса
  /// серверде сол заказға байланады). Тыныш сәтсіздікке шыдайды — GPS
  /// уақытша жоқ болса белсенді заказ экраны сынбауы керек.
  static Future<void> updateExecutorLocation(
    double lat,
    double lng, {
    double? heading,
    double? speed,
  }) async {
    try {
      await c.rpc(
        'update_executor_location',
        params: {
          'p_lat': lat,
          'p_lng': lng,
          if (heading != null && _locationV2) 'p_heading': heading,
          if (speed != null && _locationV2) 'p_speed': speed,
        },
      );
    } catch (e) {
      // 0075 қолданылмаған — бағытсыз нұсқаға біржола ауысамыз.
      if (_locationV2 && isMissingFunction(e)) {
        _locationV2 = false;
        await updateExecutorLocation(lat, lng);
      }
    }
  }

  static bool _locationV2 = true;

  /// Клиент өз заказының орындаушысының орнын polling арқылы қадағалайды.
  static Stream<Map<String, dynamic>?> orderExecutorLocationStream(
    String orderId,
  ) => _poll('loc:$orderId', () async {
    final res = await c.rpc(
      'get_order_executor_location',
      params: {'p_order_id': orderId},
    );
    return res == null ? null : Map<String, dynamic>.from(res as Map);
  }, every: const Duration(seconds: 12));

  /// Дос шақыру кодын енгізу — ТЕК байланыс жасайды (0062, фарм-
  /// қорғаныс). Сыйақы (орындаушыға баланс/клиентке санақ) шақырылған
  /// адам ӨЗІНІҢ БІРІНШІ заказын аяқтағанда ғана беріледі. Тіркелген
  /// соң (не тіркелу экранында) БІР РЕТ шақырылады.
  static Future<void> redeemReferralCode(String code) =>
      c.rpc('redeem_referral_code', params: {'p_code': code});

  /// Дос шақыру фичасы қосулы ма (0061) — АВТОРИЗАЦИЯСЫЗ да
  /// шақырылады (тіркелу экраны әлі кірмеген қолданушыда). Желі қатесінде
  /// `false` — өріс жай ғана жасырылады.
  static Future<bool> referralEnabled() async {
    try {
      return (await c.rpc('referral_enabled')) as bool? ?? false;
    } catch (_) {
      return false;
    }
  }

  // ---- moderator ----
  /// Орындаушының балансын қолмен түзету (теріс сома — шегеру).
  static Future<void> modAdjustBalance(String userId, int amount, String note) {
    forgetProfile(userId);
    return c.rpc(
      'mod_adjust_balance',
      params: {'p_user': userId, 'p_amount': amount, 'p_note': note},
    );
  }

  static Future<void> modSetExecutorStatus(
    String userId,
    String status,
    String comment,
  ) {
    forgetProfile(userId);
    return c.rpc(
      'mod_set_executor_status',
      params: {'p_user': userId, 'p_status': status, 'p_comment': comment},
    );
  }

  static Future<void> modReviewTopup(
    String id,
    bool approve,
    String note, {
    String? receiptPath,
  }) async {
    await c.rpc(
      'mod_review_topup',
      params: {'p_topup': id, 'p_approve': approve, 'p_note': note},
    );
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
      final paths = (await c.rpc('mod_pending_support_images') as List)
          .cast<String>();
      if (paths.isNotEmpty) {
        await c.storage.from('support').remove(paths);
      }
    } catch (_) {}
  }

  static Future<void> modRequestDocs(
    String userId,
    List<String> fields,
    String comment,
  ) => c.rpc(
    'mod_request_docs',
    params: {'p_user': userId, 'p_fields': fields, 'p_comment': comment},
  );

  static Future<void> modApproveDocs(String userId) =>
      c.rpc('mod_approve_docs', params: {'p_user': userId});

  static Future<void> modRejectDocs(String userId, String comment) => c.rpc(
    'mod_reject_docs',
    params: {'p_user': userId, 'p_comment': comment},
  );

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
    final res = await c.rpc(
      'submit_docs_update',
      params: {
        'p_id_doc': idDocPath,
        'p_license': licensePath,
        'p_tech': techPassportPath,
        'p_photos': photos,
        'p_id_selfie': idSelfiePath,
        'p_license_selfie': licenseSelfiePath,
        'p_passport': passportPath,
        'p_passport_selfie': passportSelfiePath,
        'p_tech_selfie': techPassportSelfiePath,
      },
    );
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

  static Future<void> modCancelOrder(String orderId, String reason) => c.rpc(
    'mod_cancel_order',
    params: {'p_order': orderId, 'p_reason': reason},
  );

  static Future<void> modReopenOrder(String orderId) =>
      c.rpc('mod_reopen_order', params: {'p_order': orderId});

  static Future<Map<String, dynamic>> modExecutorSummary(String userId) async =>
      Map<String, dynamic>.from(
        await c.rpc('mod_executor_summary', params: {'p_user': userId}) as Map,
      );

  static Future<void> modSetOrderStatus(String orderId, String status) => c.rpc(
    'mod_set_order_status',
    params: {'p_order': orderId, 'p_status': status},
  );

  static Future<Map<String, dynamic>> modLineStats() async =>
      Map<String, dynamic>.from(await c.rpc('mod_line_stats') as Map);

  /// Модератордың тірі картасы (0083): {executors: [...], orders: [...]}.
  /// Миграция жоқ болса — null (экран тек заказдарды көрсетеді).
  static Future<Map<String, dynamic>?> modLiveMap() async {
    try {
      final res = await c.rpc('mod_live_map');
      return res == null ? null : Map<String, dynamic>.from(res as Map);
    } catch (e) {
      if (isMissingFunction(e)) return null;
      rethrow;
    }
  }

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
  static Future<String> supportSend(
    String body, {
    String? imagePath,
    String? orderId,
  }) async =>
      (await c.rpc(
            'support_send',
            params: {
              'p_body': body,
              'p_image_path': imagePath,
              'p_order_id': orderId,
            },
          ))
          as String;

  static Future<void> supportReply(
    String threadId,
    String body, {
    String? imagePath,
  }) => c.rpc(
    'support_reply',
    params: {'p_thread': threadId, 'p_body': body, 'p_image_path': imagePath},
  );

  static Future<void> supportClose(String threadId) =>
      c.rpc('support_close', params: {'p_thread': threadId});

  /// Қолдау чатына сурет жүктеу (public 'support' бакеті).
  static Future<String> uploadSupportImage(Uint8List bytes) async {
    final id = uid;
    if (id == null) throw Exception('AUTH');
    final path = '$id/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await c.storage
        .from('support')
        .uploadBinary(
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

  static Stream<List<SupportMessage>> supportMessagesStream(
    String threadId, {
    bool fresh = false,
  }) => _poll(
    'msgs:$threadId',
    () async {
      final rows = await c
          .from('support_messages')
          .select()
          .eq('thread_id', threadId)
          // МАҢЫЗДЫ: postgrest-те `order()`-дің әдепкісі `ascending: false`
          // (кемімелі). Оны жазбай қалдырсақ, чат ЖАҢАДАН ЕСКІГЕ келіп,
          // соңғы хабарлама тізімнің ЕҢ ҮСТІНДЕ тұратын. Чат әрқашан
          // ЕСКІДЕН ЖАҢАҒА болуы керек — жаңасы ең астында (WhatsApp сияқты).
          .order('created_at', ascending: true);
      return (rows as List)
          .map((m) => SupportMessage.fromMap(Map<String, dynamic>.from(m)))
          .toList();
    },
    every: const Duration(seconds: 3),
    fresh: fresh,
  );

  static Stream<List<SupportThread>> myThreadsStream() {
    final id = uid;
    if (id == null) return const Stream.empty();
    return _poll('threads:$uid', () async {
      final rows = await c
          .from('support_threads')
          .select()
          .eq('user_id', id)
          // Ең соңғы тред БІРІНШІ (postgrest әдепкісі де осы, бірақ анық
          // жазамыз — оқығанда шатаспау үшін).
          .order('last_msg_at', ascending: false);
      return (rows as List)
          .map((m) => SupportThread.fromMap(Map<String, dynamic>.from(m)))
          .toList();
    });
  }

  static Stream<List<SupportThread>> allThreadsStream() =>
      _poll('allThreads', () async {
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
  ///
  /// ОРТАҚ ([key] бойынша): бір кілтке бір ғана сұрау циклы жүреді, қанша
  /// виджет тыңдаса да. Жаңа тыңдаушы соңғы мәнді БІРДЕН алады. Бұрын көп
  /// экран `stream: Repo.xxxStream()`-ды build ішінде шақыратын — әр қайта
  /// салуда (мыс. басты бетте картаны жылжытқанда) жаңа стрим құрылып,
  /// сұрау қайта жіберілетін. Тыңдаушы қалмаса, цикл 3 секундтан кейін
  /// тоқтайды; қосымша фонда тұрғанда (телефон құлыпта, веб-қойынды
  /// жасырын) сұраулар ТОҚТАП тұрады — қараңыз: [_AppVisibility].
  ///
  /// [fresh] — цикл бұрыннан жүріп тұрса, келесі тікті КҮТПЕЙ бірден қайта
  /// сұрау. Стрим ортақ болғандықтан, `ref.invalidate(провайдер)` жаңа стрим
  /// құрғанда да тек СОҢҒЫ (ескі) мән қайталанатын — «тартып жаңарту»,
  /// тариф сатып алу, «бәрі оқылды» сияқты әрекеттерден кейін жаңа дерек
  /// келесі тікке дейін (30 с-қа дейін) көрінбейтін. Провайдерлер сол
  /// себепті `fresh: true`-мен құрылады.
  static Stream<T> _poll<T>(
    String key,
    Future<T> Function() fetch, {
    Duration every = const Duration(seconds: 4),
    bool fresh = false,
  }) {
    final existing = _polls[key];
    if (existing != null) {
      if (fresh) existing.refresh();
      return existing.stream.cast<T>();
    }
    final poll = _SharedPoll(
      fetch,
      every,
      onIdle: (sp) {
        if (identical(_polls[key], sp)) _polls.remove(key);
      },
    );
    _polls[key] = poll;
    return poll.stream.cast<T>();
  }

  static final Map<String, _SharedPoll> _polls = {};

  /// Клиенттің соңғы 60 заказы (ескіден жаңаға қарай реттелген — бұрынғы
  /// шақырушылар `.reversed` арқылы жаңасын алдына шығарады). Қосымшада
  /// бұл деректі [myOrdersStreamProvider] арқылы тыңдаңыз (бір цикл).
  static Stream<List<Order>> myOrdersStream({bool fresh = false}) {
    final id = uid;
    if (id == null) return const Stream.empty();
    return _poll(
      'myOrders:$id',
      () async {
        // Тек СОҢҒЫ 60 заказ: бұрын клиенттің бүкіл тарихы әр 4 секунд
        // сайын жүктелетін (заказы көп адамда трафик пен жүктеме өсе беретін).
        final rows = await c
            .from('orders')
            .select()
            .eq('client_id', id)
            .order('created_at', ascending: false)
            .limit(60);
        return (rows as List)
            .map((m) => Order.fromMap(Map<String, dynamic>.from(m)))
            .toList()
            .reversed
            .toList();
      },
      every: const Duration(seconds: 6),
      fresh: fresh,
    );
  }

  /// Орындаушының өзі алған заказдары (белсенді + тарих), жаңасы алдында.
  static Future<List<Order>> myExecutorOrders() async {
    final id = uid;
    if (id == null) return const [];
    final rows = await c
        .from('orders')
        .select()
        .eq('executor_id', id)
        .order('created_at', ascending: false)
        .limit(150);
    return (rows as List)
        .map((m) => Order.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }

  /// Орындаушының белсенді заказдары (accepted/arrived/loading/in_transit).
  /// §5 межгород маршрут-стектеу арқылы бір мезгілде 2 заказ болуы мүмкін —
  /// сол себепті `executor_profiles.busy_order_id` (жалғыз өріс) емес,
  /// тікелей `orders` кестесінен тізім ретінде аламыз.
  static Stream<List<Order>> myActiveExecutorOrdersStream({
    bool fresh = false,
  }) {
    final id = uid;
    if (id == null) return const Stream.empty();
    return _poll('activeExec:$id', () async {
      final rows = await c
          .from('orders')
          .select()
          .eq('executor_id', id)
          .inFilter('status', const [
            'accepted',
            'arrived',
            'loading',
            'in_transit',
          ])
          .order('accepted_at');
      return (rows as List)
          .map((m) => Order.fromMap(Map<String, dynamic>.from(m)))
          .toList();
    }, fresh: fresh);
  }

  /// Бір заказдың тірі күйі (3 с). [fresh] — әрекеттен кейін (статус,
  /// баға, өңдеу) шақырсаңыз, ашық экран келесі тікті күтпей жаңарады.
  static Stream<Order?> orderStream(String orderId, {bool fresh = false}) =>
      _poll(
        'order:$orderId',
        () async {
          final m = await c
              .from('orders')
              .select()
              .eq('id', orderId)
              .maybeSingle();
          return m == null ? null : Order.fromMap(m);
        },
        every: const Duration(seconds: 3),
        fresh: fresh,
      );

  /// §6/§5 Лента: орындаушының қаласы мен маршрутына сай заказдар (RPC).
  /// Қала фильтрі, өлшем сәйкестігі, межгород маршруты — бәрі серверде
  /// `executor_feed` ішінде (бір ғана логика көзі).
  static Stream<List<Order>> executorFeedStream({bool fresh = false}) => _poll(
    'feed:$uid',
    () async {
      final rows = await c.rpc('executor_feed');
      return (rows as List)
          .map((m) => Order.fromMap(Map<String, dynamic>.from(m)))
          .toList();
    },
    every: const Duration(seconds: 4),
    fresh: fresh,
  );

  /// §6 Орындаушының тіркелген қаласын орнату/жаңарту.
  static Future<void> setExecutorCity(String city) =>
      c.rpc('set_executor_city', params: {'p_city': city});

  /// Жаңа заказ push-хабарландыруын серверде қосу/өшіру (қосымша толық
  /// жабық болса да — трафикке осы мән әсер етеді).
  static Future<void> setOrderPushEnabled(bool enabled) =>
      c.rpc('set_order_push_enabled', params: {'p_enabled': enabled});

  static Stream<List<Offer>> offersStream(
    String orderId, {
    bool fresh = false,
  }) => _poll(
    'offers:$orderId',
    () async {
      final rows = await c
          .from('offers')
          .select()
          .eq('order_id', orderId)
          .order('created_at');
      return (rows as List)
          .map((m) => Offer.fromMap(Map<String, dynamic>.from(m)))
          .toList();
    },
    every: const Duration(seconds: 3),
    fresh: fresh,
  );

  static Stream<ExecutorProfile?> myExecutorProfileStream() {
    final id = uid;
    if (id == null) return const Stream.empty();
    return _poll('execProfile:$id', () async {
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

  /// Кезеңдегі табыс жазбалары (график үшін) — [myEarnings]-тен үлкен шек.
  static Future<List<Map<String, dynamic>>> myEarningsSince(
    DateTime since,
  ) async {
    final id = uid;
    if (id == null) return [];
    final rows = await c
        .from('earnings')
        .select('amount, created_at')
        .eq('executor_id', id)
        .gte('created_at', since.toUtc().toIso8601String())
        .order('created_at', ascending: false)
        .limit(1000);
    return (rows as List).map((m) => Map<String, dynamic>.from(m)).toList();
  }

  /// Кезеңде тарифке жұмсалған сома (оң сан) — «таза табыс» үшін.
  static Future<int> myTariffSpendSince(DateTime since) async {
    final id = uid;
    if (id == null) return 0;
    final rows = await c
        .from('balance_txns')
        .select('amount')
        .eq('executor_id', id)
        .eq('type', 'tariff_fee')
        .gte('created_at', since.toUtc().toIso8601String())
        .limit(1000);
    var sum = 0;
    for (final m in rows as List) {
      sum += ((m['amount'] as num?) ?? 0).toInt().abs();
    }
    return sum;
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

  /// Көлік нөмірін салыстыруға келтіру: бос орын/сызықша алынып, бас
  /// әріпке, кириллицадағы «ұқсас» әріптер латыншаға айналады (А→A, В→B…)
  /// — «123 АВС 02» мен «123ABC02» бір нөмір болып саналады.
  static String normPlate(String raw) {
    const map = {
      'А': 'A', 'В': 'B', 'Е': 'E', 'К': 'K', 'М': 'M', 'Н': 'H', //
      'О': 'O', 'Р': 'P', 'С': 'C', 'Т': 'T', 'Х': 'X', 'У': 'Y', //
    };
    final up = raw.toUpperCase().replaceAll(RegExp(r'[\s\-_.]'), '');
    return up.split('').map((ch) => map[ch] ?? ch).join();
  }

  /// Модератор: осы көлік нөмірімен ТАҒЫ қай орындаушылар тіркелген
  /// (өзінен басқа). Бос тізім — қайталану жоқ.
  static Future<List<String>> modPlateDuplicates(
    String userId,
    String plate,
  ) async {
    final target = normPlate(plate);
    if (target.length < 4) return const [];
    final rows = await c
        .from('executor_profiles')
        .select('user_id, vehicle_plate')
        .neq('user_id', userId);
    return [
      for (final m in rows as List)
        if (normPlate('${m['vehicle_plate'] ?? ''}') == target)
          m['user_id'] as String,
    ];
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
    final res = await c.rpc(
      'create_listing',
      params: {
        'p_vehicle_type': vehicleType.db,
        'p_city': city,
        'p_body': body,
        'p_price_text': priceText,
        'p_duration_days': durationDays,
        'p_photos': photos,
      },
    );
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
  }) => c.rpc(
    'repost_listing',
    params: {
      'p_id': id,
      'p_photos': photos,
      'p_body': body,
      'p_price_text': priceText,
      'p_vehicle_type': vehicleType.db,
      'p_city': city,
      'p_duration_days': durationDays,
    },
  );

  static Future<void> deleteListing(String id) =>
      c.rpc('delete_listing', params: {'p_id': id});

  /// Хабарландыру фотосын жүктеу (public 'listings' бакеті). Жолын қайтарады.
  static Future<String> uploadListingPhoto(Uint8List bytes, int index) async {
    final id = uid;
    if (id == null) throw Exception('AUTH');
    final path = '$id/${DateTime.now().millisecondsSinceEpoch}_$index.jpg';
    await c.storage
        .from('listings')
        .uploadBinary(
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

  /// Модератор Шолуының графиктері (0082): соңғы [days] күннің күндік
  /// көрсеткіштері (ескіден жаңаға қарай).
  static Future<List<Map<String, dynamic>>> modDashboardSeries(int days) async {
    final res = await c.rpc('mod_dashboard_series', params: {'p_days': days});
    return [
      for (final m in (res as List? ?? const []))
        Map<String, dynamic>.from(m as Map),
    ];
  }

  /// Сервердегі функция ӘЛІ ҚОЛДАНЫЛМАҒАН ба (миграция жоқ) — жаңа
  /// мүмкіндіктер мұндай қатеде экранды сындырмай, жай ғана жасырылады.
  static bool isMissingFunction(Object e) {
    final s = e.toString();
    return s.contains('PGRST202') ||
        s.contains('Could not find the function') ||
        s.contains('does not exist') ||
        s.contains('PGRST205') ||
        s.contains('42P01') ||
        s.contains('42883');
  }

  /// Модераторға хабарландырулар тізімі. [status]: active | expired | null.
  static Future<List<Listing>> modListings(String? status) async {
    final rows = await c.rpc(
      'mod_listings',
      params: {'p_status': status ?? ''},
    );
    return (rows as List)
        .map((m) => Listing.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }

  // ---- хабарландыруға шағым (0044) ----
  /// Күдікті хабарландыру туралы модераторға шағым жіберу. Бір адам бір
  /// хабарландыруға бір ғана ашық шағым бере алады ('ALREADY_REPORTED').
  static Future<String> reportListing(String listingId, String reason) async =>
      (await c.rpc(
            'report_listing',
            params: {'p_listing': listingId, 'p_reason': reason},
          ))
          as String;

  /// Модераторға шағымдар тізімі. [status]: open | closed | '' (барлығы).
  static Future<List<ListingReport>> modListingReports(String status) async {
    final rows = await c.rpc(
      'mod_listing_reports',
      params: {'p_status': status},
    );
    return (rows as List)
        .map((m) => ListingReport.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }

  /// Модератордың шешімі. [action]: 'delete' (хабарландыруды өшіру, сол
  /// хабарландырудың барлық ашық шағымы жабылады) | 'keep' (елеусіз қалдыру).
  static Future<void> modResolveListingReport(String id, String action) =>
      c.rpc(
        'mod_resolve_listing_report',
        params: {'p_id': id, 'p_action': action},
      );

  // ================= ЖАҢАЛЫҚТАР · СТОРИС (0066) =================
  /// Бөлім қосулы ма (модератор Баптаулардан басқарады). Желі қатесінде
  /// `false` — sidebar-да карта жай ғана көрінбейді, ешбір экран сынбайды.
  static Future<bool> newsEnabled() async {
    try {
      return (await c.rpc('news_enabled')) as bool? ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Қолданушыға көрінетін стористер. Сервер аудиторияны (клиент /
  /// орындаушы / гест) ӨЗІ анықтап сүзеді, сол себепті мұнда параметр жоқ.
  /// Гест те шақырады (anon кілтімен) — кірмеген адамға арналған жаңалық
  /// та болуы мүмкін.
  static Future<List<NewsStory>> newsFeed() async {
    try {
      final rows = await c.rpc('news_feed');
      return [
        for (final m in rows as List)
          NewsStory.fromMap(Map<String, dynamic>.from(m as Map)),
      ];
    } catch (_) {
      // Бөлім жаңа қосылып, миграция әлі қолданылмаған сервер де болуы
      // мүмкін — сонда карта мүлдем көрінбейді, қосымша сынбайды.
      return const [];
    }
  }

  /// «Көрдім» белгісі. Гесте (uid жоқ) сервер үнсіз өтеді — қосымша
  /// белгіні құрылғының өзінде ([Prefs.markNewsSeen]) сақтайды.
  static Future<void> newsMarkSeen(String id) async {
    if (uid == null) return;
    try {
      await c.rpc('news_mark_seen', params: {'p_id': id});
    } catch (_) {}
  }

  /// Стористің медиасы/әуені (public 'news' бакеті).
  static String newsMediaUrl(String path) =>
      c.storage.from('news').getPublicUrl(path);

  /// Модератор жүктеген файл (сурет · видео · әуен). Жолын қайтарады.
  /// Бакетке жазуға тек модератордың құқығы бар (0066 саясаты).
  static Future<String> uploadNewsMedia(String name, Uint8List bytes) async {
    final id = uid;
    if (id == null) throw Exception('AUTH');
    final safe = newsSafeFileName(name);
    final path = '$id/${DateTime.now().millisecondsSinceEpoch}_$safe';
    await c.storage
        .from('news')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: _newsContentTypeFor(safe)),
        );
    return path;
  }

  /// Файл атын Storage КІЛТІНЕ жарамды түрге келтіреді.
  ///
  /// НЕГЕ КЕРЕК: Supabase Storage кілтте тек қауіпсіз ASCII таңбаларын
  /// қабылдайды. Қазақша/орысша әріп, бос орын, жақша бар ат («Abzal
  /// Uteshov - Біз жолығамыз ( M V2026 ).m4a») жүктегенде
  /// `StorageException(Invalid key: …)` шығады да, модератор әуенін де,
  /// видеосын да қоя алмайды. Сол себепті кілтке тек `a-z0-9-_` жібереміз;
  /// адамға көрінетін АТАУ бұл жерде емес — ол `music_title` өрісінде
  /// (қазақша күйі сақталады).
  ///
  /// Кеңейтім МІНДЕТТІ ТҮРДЕ сақталады: одан Content-Type анықталады, ал ол
  /// дұрыс болмаса браузер видео/әуенді ойната алмайды.
  static String newsSafeFileName(String name) {
    final dot = name.lastIndexOf('.');
    var ext = dot > 0 ? name.substring(dot + 1).toLowerCase() : '';
    ext = ext.replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (ext.isEmpty || ext.length > 5) ext = 'bin';
    var base = (dot > 0 ? name.substring(0, dot) : name)
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (base.length > 40) base = base.substring(0, 40);
    // Кириллицадан ғана тұратын ат толығымен «қырқылып» қалуы мүмкін —
    // сонда да кілт жарамды болуы керек (алдында уақыт белгісі бар,
    // сол себепті аттар бір-бірімен соқтығыспайды).
    if (base.isEmpty) base = 'file';
    return '$base.$ext';
  }

  /// Файл кеңейтіміне қарай Content-Type. МАҢЫЗДЫ: видео мен әуен дұрыс
  /// түрмен жүктелмесе, браузер (web) оларды ойната алмайды.
  static String _newsContentTypeFor(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.mp4')) return 'video/mp4';
    if (n.endsWith('.mov')) return 'video/quicktime';
    if (n.endsWith('.webm')) return 'video/webm';
    if (n.endsWith('.mp3')) return 'audio/mpeg';
    if (n.endsWith('.m4a') || n.endsWith('.aac')) return 'audio/mp4';
    if (n.endsWith('.wav')) return 'audio/wav';
    if (n.endsWith('.ogg')) return 'audio/ogg';
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  /// Модератордың ТОЛЫҚ тізімі — өшірулісі мен мерзімі өткені де кіреді.
  static Future<List<NewsStory>> modNewsList() async {
    final rows = await c.rpc('mod_news_list');
    return [
      for (final m in rows as List)
        NewsStory.fromMap(Map<String, dynamic>.from(m as Map)),
    ];
  }

  /// Стористі қосу (id == null) немесе өңдеу. Жаңасының id-ін қайтарады.
  static Future<String> modNewsSave({
    String? id,
    required String title,
    required String body,
    required String mediaType,
    String? mediaPath,
    String? musicPath,
    String musicTitle = '',
    String linkUrl = '',
    String linkLabel = '',
    required List<String> audiences,
    required int durationSec,
    int bgIndex = 0,
    NewsLayout layout = const NewsLayout(),
    required bool active,
    DateTime? startsAt,
    DateTime? expiresAt,
  }) async {
    final res = await c.rpc(
      'mod_news_save',
      params: {
        'p_id': id,
        'p_title': title,
        'p_body': body,
        'p_media_type': mediaType,
        'p_media_path': mediaPath,
        'p_music_path': musicPath,
        'p_music_title': musicTitle,
        'p_link_url': linkUrl,
        'p_link_label': linkLabel,
        'p_audiences': audiences,
        'p_duration_sec': durationSec,
        'p_bg_index': bgIndex,
        'p_layout': layout.toMap(),
        'p_active': active,
        // Уақыттар серверде timestamptz — UTC-мен жібереміз.
        'p_starts_at': (startsAt ?? DateTime.now()).toUtc().toIso8601String(),
        'p_expires_at': expiresAt?.toUtc().toIso8601String(),
      },
    );
    return res.toString();
  }

  static Future<void> modNewsDelete(String id) =>
      c.rpc('mod_news_delete', params: {'p_id': id});

  static Future<void> modNewsReorder(List<String> ids) =>
      c.rpc('mod_news_reorder', params: {'p_ids': ids});

  // ================= STORAGE =================
  /// Файлды docs бакетіне жүктеп, жолын қайтарады. Content-type файл
  /// атының кеңейтіміне қарай анықталады — Kaspi кейде скриншотты
  /// бұғаттайды, сол кезде орындаушы чекті PDF ретінде жүктейді (0051+).
  static Future<String> uploadDoc(String name, Uint8List bytes) async {
    final id = uid;
    if (id == null) throw Exception('AUTH');
    final path = '$id/${DateTime.now().millisecondsSinceEpoch}_$name';
    await c.storage
        .from('docs')
        .uploadBinary(
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

  /// Жабық құжаттың уақытша сілтемесі (1 сағат). 50 минут бойы КЭШТЕ
  /// сақталады: құжат суреті build сайын жаңа сілтеме сұрамайды (әрі жаңа
  /// сілтеме = кэштелмеген жаңа сурет → жыпылықтау).
  static Future<String> signedDocUrl(String path) {
    final hit = _signedCache[path];
    if (hit != null &&
        DateTime.now().difference(hit.$1) < const Duration(minutes: 50)) {
      return hit.$2;
    }
    final f = c.storage.from('docs').createSignedUrl(path, 3600);
    _signedCache[path] = (DateTime.now(), f);
    f.catchError((Object _) {
      _signedCache.remove(path);
      return '';
    });
    return f;
  }

  static final Map<String, (DateTime, Future<String>)> _signedCache = {};

  // ============ ТОЛТЫРУ ЧЕГІН ТЕКСЕРЕТІН БОТ (0051) ============
  /// Kaspi Pay выпискасын `docs` бакетіне жүктейді. Бөлек bucket құрылмайды:
  /// `docs_insert_own` саясаты бойынша модератор ӨЗ папкасына жаза алады, ал
  /// edge функция оны service-role кілтімен оқиды.
  static Future<String> uploadStatement(String name, Uint8List bytes) async {
    final id = uid;
    if (id == null) throw Exception('AUTH');
    final path = '$id/${DateTime.now().millisecondsSinceEpoch}_$name';
    await c.storage
        .from('docs')
        .uploadBinary(
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
    final res = await c.functions.invoke(
      'kaspi-statement',
      body: {'path': path},
    );
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
    return [for (final r in rows as List) Map<String, dynamic>.from(r as Map)];
  }

  // ================= БОНУС БАҒДАРЛАМАСЫ (0059) =================
  /// Орындаушының бонус прогресі. Бағдарлама өшірулі болса да, желі
  /// қатесінде де — «өшірулі» күй қайтады, сол себепті лента ешқашан
  /// сынбайды (жолақ жай ғана көрінбейді).
  static Future<BonusInfo> executorBonus() async {
    try {
      final res = await c.rpc('executor_bonus');
      return BonusInfo.fromMap(Map<String, dynamic>.from(res as Map));
    } catch (_) {
      return const BonusInfo.off();
    }
  }

  /// Бонус прогресі — тікелей жаңарып отыратын стрим (лентадағы жолақ
  /// заказ аяқталған сайын өзі жаңарады). Статистикадан сирегірек —
  /// бонус әр 15 секундта тексерілсе де жеткілікті.
  static Stream<BonusInfo> executorBonusStream({bool fresh = false}) => _poll(
    'bonus:$uid',
    executorBonus,
    every: const Duration(seconds: 15),
    fresh: fresh,
  );

  /// Орындаушының бонус тарихы (соңғы 100 жазба).
  static Future<List<BonusAward>> myBonusAwards() async {
    final rows = await c.rpc('my_bonus_awards');
    return [
      for (final r in rows as List)
        BonusAward.fromMap(Map<String, dynamic>.from(r as Map)),
    ];
  }

  /// Модератордың бонус есебі: барлығы / осы айда берілген + топ-5.
  static Future<Map<String, dynamic>> modBonusStats() async =>
      Map<String, dynamic>.from(await c.rpc('mod_bonus_stats') as Map);

  // ================= ЖАҢА МҮМКІНДІКТЕР (0075–0082) =================
  // Барлығы «миграция әлі қолданылмаған» жағдайға шыдайды: оқитын
  // функциялар бос мән қайтарады, жазатындары қатені жоғары береді
  // (экран оны түсінікті мәтінмен көрсетеді).

  /// Клиенттің картасындағы жақын маңдағы бос орындаушылар (0075).
  static Future<List<NearbyExecutor>> nearbyExecutors(
    double lat,
    double lng, {
    VehicleType? vehicle,
  }) async {
    try {
      final res = await c.rpc(
        'nearby_executors',
        params: {'p_lat': lat, 'p_lng': lng, 'p_vehicle': vehicle?.db},
      );
      return [
        for (final m in (res as List? ?? const []))
          NearbyExecutor.fromMap(Map<String, dynamic>.from(m as Map)),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Жақын маңдағы бос көліктер — ортақ циклмен ([_poll], 30 с; фонда
  /// тоқтайды). Кілт ~100 м-ге дөңгелектенген нүкте + көлік түрі: картаны
  /// сәл жылжытқанда жаңа цикл ашылмайды.
  static Stream<List<NearbyExecutor>> nearbyExecutorsStream(
    double lat,
    double lng, {
    VehicleType? vehicle,
  }) => _poll(
    'nearby:${lat.toStringAsFixed(3)},${lng.toStringAsFixed(3)}:'
    '${vehicle?.db}',
    () => nearbyExecutors(lat, lng, vehicle: vehicle),
    every: const Duration(seconds: 30),
  );

  /// Алушыны қосу/өзгерту (бос телефон — алып тастау) (0076).
  static Future<OrderRecipient?> setOrderRecipient(
    String orderId,
    String name,
    String phone,
  ) async {
    final res = await c.rpc(
      'set_order_recipient',
      params: {'p_order': orderId, 'p_name': name, 'p_phone': phone},
    );
    return res == null
        ? null
        : OrderRecipient.fromMap(Map<String, dynamic>.from(res as Map));
  }

  /// Серверде алушы/жеткізу коды бар ма (0076) — сессияда бір рет.
  /// Жоқ заказға сұрау жібереміз: NOT_FOUND келсе — функция бар.
  static Future<bool> recipientsAvailable() => _recipAvailable ??= () async {
    try {
      await c.rpc(
        'get_order_recipient',
        params: {'p_order': '00000000-0000-0000-0000-000000000000'},
      );
      return true;
    } catch (e) {
      return !isMissingFunction(e);
    }
  }();

  static Future<bool>? _recipAvailable;

  /// Заказдың қосымша талаптары бар ма (0077) — сессияда бір рет. Жоқ
  /// болса, жаңа заказдың талаптары түсініктемеге мәтін болып қосылады.
  static Future<bool> orderExtrasAvailable() => _extrasAvailable ??= () async {
    try {
      await c.rpc(
        'update_order_details',
        params: {'p_order': '00000000-0000-0000-0000-000000000000'},
      );
      return true;
    } catch (e) {
      return !isMissingFunction(e);
    }
  }();

  static Future<bool>? _extrasAvailable;

  /// Таңдаулы/бұғат тізімдері бар ма (0079) — сессияда бір рет.
  static Future<bool> executorPrefsAvailable() => _prefsAvailable ??= () async {
    try {
      await c.from('client_favorites').select('executor_id').limit(1);
      return true;
    } catch (e) {
      return !isMissingFunction(e);
    }
  }();

  static Future<bool>? _prefsAvailable;

  /// Заказдың алушысы (клиентке — кодымен, орындаушыға — кодсыз).
  /// Алушы жоқ не 0076 қолданылмаған — `null`.
  static Future<OrderRecipient?> orderRecipient(String orderId) async {
    try {
      final res = await c.rpc(
        'get_order_recipient',
        params: {'p_order': orderId},
      );
      return res == null
          ? null
          : OrderRecipient.fromMap(Map<String, dynamic>.from(res as Map));
    } catch (e) {
      if (isMissingFunction(e)) return null;
      rethrow;
    }
  }

  /// Орындаушы алушыдан алған кодты тексертеді. (дұрыс па, қалған әрекет).
  static Future<(bool, int?)> verifyDeliveryCode(
    String orderId,
    String code,
  ) async {
    final res = Map<String, dynamic>.from(
      await c.rpc(
            'verify_delivery_code',
            params: {'p_order': orderId, 'p_code': code},
          )
          as Map,
    );
    final left = res['left'];
    return (res['ok'] == true, left is num ? left.toInt() : null);
  }

  /// Клиент «жүк жетті» деп өзі растайды (алушы кодты жоғалтса).
  static Future<void> clientConfirmDelivery(String orderId) =>
      c.rpc('client_confirm_delivery', params: {'p_order': orderId});

  /// Заказды іздеу кезінде өңдеу (0077). null — өзгертпе. [loaders]
  /// берілсе, қабат пен лифт те сол мәнге ауысады (null — тазалау).
  static Future<void> updateOrderDetails(
    String orderId, {
    String? cargo,
    String? comment,
    int? loaders,
    int? floorFrom,
    int? floorTo,
    bool? elevator,
  }) => c.rpc(
    'update_order_details',
    params: {
      'p_order': orderId,
      'p_cargo': cargo,
      'p_comment': comment,
      'p_loaders': loaders,
      'p_floor_from': floorFrom,
      'p_floor_to': floorTo,
      'p_elevator': elevator,
    },
  );

  /// Ұсынылатын баға (0077). Дерек аз не функция жоқ — `null`.
  static Future<PriceHint?> orderPriceHint({
    required VehicleType vehicle,
    required double distanceKm,
    String? city,
    bool intercity = false,
  }) async {
    try {
      final res = await c.rpc(
        'order_price_hint',
        params: {
          'p_vehicle': vehicle.db,
          'p_distance_km': double.parse(distanceKm.toStringAsFixed(2)),
          'p_city': city,
          'p_intercity': intercity,
        },
      );
      return res == null
          ? null
          : PriceHint.fromMap(Map<String, dynamic>.from(res as Map));
    } catch (_) {
      return null;
    }
  }

  // ---- Заказ чаты (0078) ----

  /// Серверде заказ чаты бар ма (0078 қолданылған ба) — сессияда бір рет
  /// тексеріледі. Жоқ болса чат батырмалары мүлдем көрінбейді (басқанда
  /// түсініксіз қате шықпауы үшін).
  static Future<bool> orderChatAvailable() => _chatAvailable ??= () async {
    try {
      await c.from('order_messages').select('id').limit(1);
      return true;
    } catch (e) {
      return !isMissingFunction(e);
    }
  }();

  static Future<bool>? _chatAvailable;

  /// Заказ чатының хабарлары (ескіден жаңаға). [fresh] — хабар жіберген соң
  /// шақырсаңыз, ашық чат келесі тікті күтпей бірден жаңарады.
  static Stream<List<OrderMessage>> orderMessagesStream(
    String orderId, {
    bool fresh = false,
  }) => _poll(
    'orderChat:$orderId',
    () async {
      final rows = await c
          .from('order_messages')
          .select()
          .eq('order_id', orderId)
          .order('created_at')
          .limit(300);
      return (rows as List)
          .map((m) => OrderMessage.fromMap(Map<String, dynamic>.from(m)))
          .toList();
    },
    every: const Duration(seconds: 4),
    fresh: fresh,
  );

  static Future<void> orderChatSend(String orderId, String body) =>
      c.rpc('order_chat_send', params: {'p_order': orderId, 'p_body': body});

  static Future<void> orderChatMarkRead(String orderId) async {
    try {
      await c.rpc('order_chat_mark_read', params: {'p_order': orderId});
    } catch (_) {}
  }

  /// Заказдағы оқылмаған хабар саны (маған келгендер).
  static Future<int> orderChatUnread(String orderId) async {
    final me = uid;
    if (me == null) return 0;
    try {
      final rows = await c
          .from('order_messages')
          .select('id')
          .eq('order_id', orderId)
          .neq('sender_id', me)
          .isFilter('read_at', null);
      return (rows as List).length;
    } catch (_) {
      return 0;
    }
  }

  /// Оқылмаған хабар саны — ортақ циклмен ([_poll], 15 с): бір заказдың
  /// бірнеше батырмасы бір сұрауды бөліседі, фонда тоқтайды. [fresh] —
  /// чаттан қайтқанда келесі тікті күтпей бірден жаңарту.
  static Stream<int> orderChatUnreadStream(
    String orderId, {
    bool fresh = false,
  }) => _poll(
    'chatUnread:$orderId',
    () => orderChatUnread(orderId),
    every: const Duration(seconds: 15),
    fresh: fresh,
  );

  /// Модератор: соңғы заказ чаттары.
  static Future<List<Map<String, dynamic>>> modOrderChats({
    bool flaggedOnly = false,
  }) async {
    final res = await c.rpc(
      'mod_order_chats',
      params: {'p_limit': 80, 'p_flagged_only': flaggedOnly},
    );
    return [
      for (final m in (res as List? ?? const []))
        Map<String, dynamic>.from(m as Map),
    ];
  }

  // ---- Таңдаулы / бұғатталған орындаушылар (0079) ----

  /// (таңдаулылар, бұғатталғандар) — клиенттің өз тізімдері.
  static Future<(Set<String>, Set<String>)> myExecutorPrefs() async {
    final me = uid;
    if (me == null) return (<String>{}, <String>{});
    try {
      final fav = await c.from('client_favorites').select('executor_id');
      final blk = await c.from('client_blocks').select('executor_id');
      return (
        {for (final m in fav as List) m['executor_id'] as String},
        {for (final m in blk as List) m['executor_id'] as String},
      );
    } catch (_) {
      return (<String>{}, <String>{});
    }
  }

  /// [kind]: 'favorite' | 'block' | 'none'.
  static Future<void> setExecutorPref(String executorId, String kind) => c.rpc(
    'set_executor_pref',
    params: {'p_executor': executorId, 'p_kind': kind},
  );

  // ---- Хабарламалар орталығы (0080) ----

  static Future<List<AppNotification>> myNotifications() async {
    final me = uid;
    if (me == null) return const [];
    try {
      final rows = await c
          .from('notifications')
          .select()
          .eq('user_id', me)
          .order('created_at', ascending: false)
          .limit(60);
      return (rows as List)
          .map((m) => AppNotification.fromMap(Map<String, dynamic>.from(m)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Оқылмаған хабарламалар саны — [unreadNotificationsProvider] арқылы
  /// тыңдаңыз (мәзірдегі 🔔 белгісі).
  static Stream<int> unreadNotificationsStream({bool fresh = false}) {
    final me = uid;
    if (me == null) return const Stream.empty();
    return _poll(
      'unreadNotifications:$me',
      () async {
        try {
          final rows = await c
              .from('notifications')
              .select('id')
              .eq('user_id', me)
              .isFilter('read_at', null)
              .limit(100);
          return (rows as List).length;
        } catch (_) {
          return 0;
        }
      },
      every: const Duration(seconds: 30),
      fresh: fresh,
    );
  }

  static Future<void> markAllNotificationsRead() async {
    try {
      await c.rpc('notifications_mark_all_read');
    } catch (_) {}
  }

  // ---- Бағалау тегтері (0081) ----

  /// Адамның [role] рөліндегі алған тегтері: код → саны.
  static Future<Map<String, int>> userReviewTags(
    String userId, {
    String role = 'executor',
  }) async {
    try {
      final res = await c.rpc(
        'user_review_tags',
        params: {'p_user': userId, 'p_role': role},
      );
      final m = Map<String, dynamic>.from(res as Map? ?? const {});
      return {for (final e in m.entries) e.key: (e.value as num).toInt()};
    } catch (_) {
      return const {};
    }
  }

  // ---- Модератор құралдары (0082) ----

  /// Жаппай хабарлама. Қайтарады: алушылар саны.
  static Future<int> modBroadcast({
    required String audience,
    required String title,
    required String body,
    String? city,
    VehicleType? vehicle,
  }) async {
    final res = await c.rpc(
      'mod_broadcast',
      params: {
        'p_audience': audience,
        'p_title': title,
        'p_body': body,
        'p_city': city,
        'p_vehicle': vehicle?.db,
      },
    );
    return (res as num?)?.toInt() ?? 0;
  }

  /// Модератор әрекеттерінің журналы (жаңасы алдында).
  static Future<List<Map<String, dynamic>>> modAuditLog({
    int limit = 150,
  }) async {
    final rows = await c
        .from('mod_audit_log')
        .select()
        .order('created_at', ascending: false)
        .limit(limit);
    return [for (final m in rows as List) Map<String, dynamic>.from(m)];
  }
}

// ================= RIVERPOD PROVIDERS =================
final authStateProvider = StreamProvider<AuthState>(
  (ref) => Supabase.instance.client.auth.onAuthStateChange,
);

/// Кірген пайдаланушының id-і (кірмеген — `null`).
///
/// Профиль провайдерлері [authStateProvider]-ге емес, ОСЫҒАН тәуелді.
/// Supabase токенді жаңартқан сайын (шамамен сағат сайын, қосымшаға қайта
/// оралғанда) жаңа AuthState келеді, бірақ id сол күйі қалады — Riverpod
/// бірдей мәнді тәуелділерге жібермейді. Бұрын әр токен жаңаруында профиль
/// қайта сұралып, `_RoleRouter` бүкіл қосымшаны splash-қа ауыстыратын:
/// ашық тұрған экран (лента, карта) басынан қайта салынатын.
final authUidProvider = Provider<String?>((ref) {
  final auth = ref.watch(authStateProvider);
  return auth.valueOrNull?.session?.user.id ??
      Supabase.instance.client.auth.currentUser?.id;
});

/// Суық іске қосу (қосымшаның алғашқы ашылуы) әлі өтпеді ме — тек сол
/// сәтте кэштелген профиль бірден беріледі. Кейінгі жүктеулер (invalidate,
/// аккаунт ауысуы) ӘРҚАШАН серверден: «күйін тексеру» сияқты ағындар
/// ескі мәнді алмауы керек.
bool _profileColdStart = true;
bool _execProfileColdStart = true;

/// Менің профилім. Қосымша ашылғанда — алдымен құрылғыдағы соңғы белгілі
/// профиль (желіні күтпей, бірден дұрыс экран ашылады), сосын сервердегі
/// жаңасы. Кэш болып, сервер жауап бермесе (желі жоқ) — кэш қалады.
final myProfileProvider = StreamProvider<Profile?>((ref) async* {
  final id = ref.watch(authUidProvider);
  if (id == null) {
    yield null;
    return;
  }
  if (_profileColdStart) {
    _profileColdStart = false;
    final cached = await Repo.cachedProfile(id);
    if (cached != null) {
      yield cached;
      try {
        yield await Repo.myProfile();
      } catch (_) {}
      return;
    }
  }
  yield await Repo.myProfile();
});

final myExecutorProfileProvider = StreamProvider<ExecutorProfile?>((
  ref,
) async* {
  final id = ref.watch(authUidProvider);
  if (id == null) {
    yield null;
    return;
  }
  if (_execProfileColdStart) {
    _execProfileColdStart = false;
    final cached = await Repo.cachedExecutorProfile(id);
    if (cached != null) {
      yield cached;
      try {
        yield await Repo.myExecutorProfile();
      } catch (_) {}
      return;
    }
  }
  yield await Repo.myExecutorProfile();
});

final appConfigProvider = FutureProvider<AppConfig>((ref) async {
  final s = await Repo.settings();
  final payment = s['payment'];
  final tariffs = s['tariffs'];
  return AppConfig.fromSettings(
    payment is Map ? Map<String, dynamic>.from(payment) : null,
    tariffs: tariffs is Map ? Map<String, dynamic>.from(tariffs) : null,
  );
});

final executorStatsProvider = FutureProvider<ExecutorStats>(
  (ref) => Repo.executorStats(),
);

/// Хабарландырулар тақтасы қосулы ма (0043). Модератор Баптаулардан
/// қосқанда/өшіргенде `ref.invalidate(boardEnabledProvider)` шақырылады.
final boardEnabledProvider = FutureProvider<bool>((ref) => Repo.boardEnabled());

/// «Такси» бөлімі қосулы ма (0046). Модератор Баптаулардан қосқанда/
/// өшіргенде `ref.invalidate(taxiEnabledProvider)` шақырылады.
final taxiEnabledProvider = FutureProvider<bool>((ref) => Repo.taxiEnabled());

/// «ЖАҢА» белгілері көрінсін бе (0058) — фича ескіргенде модератор
/// Баптаулардан әрқайсысын бөлек алып тастайды.
final newBadgesProvider = FutureProvider<NewBadges>((ref) => Repo.newBadges());

/// «Жаңалықтар» бөлімі қосулы ма (0066). Модератор Баптаулардан
/// қосқанда/өшіргенде `ref.invalidate(newsEnabledProvider)` шақырылады.
final newsEnabledProvider = FutureProvider<bool>((ref) => Repo.newsEnabled());

/// Қолданушыға көрінетін стористер (0066). Аудиторияны сервер өзі сүзеді,
/// сол себепті рөл ауысқанда лента да ауысуы керек — `authStateProvider`-ды
/// тыңдаймыз (кіру/шығу кезінде өзі жаңарады).
final newsFeedProvider = FutureProvider<List<NewsStory>>((ref) {
  ref.watch(authStateProvider);
  return Repo.newsFeed();
});

/// Құрылғыда «көрілген» деп белгіленген стористер (0066). Сервердегі
/// белгінің ҮСТІНЕ қосылады: гесте сервер белгісі мүлдем болмайды, ал
/// желі үзілсе де сақина жыпылықтап тұрмайды.
final newsSeenLocalProvider = FutureProvider<Set<String>>(
  (ref) => Prefs.seenNews(),
);

/// Толық app_settings карта (0060) — жаңа клиент фичаларының (алдын ала
/// тапсырыс, тірі трекинг, бөлісу, реферал, қайталау) `enabled`
/// жалаушаларын оқу үшін. `app_settings` RLS-і кез келген authenticated
/// пайдаланушыға оқуға ашық (Kaspi/тариф баптаулары да солай оқылады),
/// сол себепті бөлек RPC қажет емес — тікелей кесте оқылады.
final appSettingsProvider = FutureProvider<Map<String, dynamic>>(
  (ref) => Repo.settings(),
);

// ---- Polling провайдерлері ----
// Бәрі [Repo._poll]-дың ортақ циклінің үстінде. `fresh: true` — провайдер
// ҚАЙТА құрылғанда (`ref.invalidate` — «тартып жаңарту», тариф сатып алу,
// «бәрі оқылды») цикл келесі тікті күтпей бірден жаңа дерек сұрайды; әйтпесе
// ортақ цикл жаңа тыңдаушыға тек соңғы (ескі) мәнді қайталайтын.
// Пайдаланушыға тәуелділері [authUidProvider]-ді тыңдайды: токен жаңарғанда
// (id сол күйі) цикл қайта басталмайды, аккаунт ауысса — жаңа кілтпен басталады.

/// Клиенттің заказдары — қосымшадағы ЖАЛҒЫЗ polling-циклі.
///
/// Бұрын ClientShell, басты беттің баннері және «Тапсырыстарым» әрқайсысы
/// `Repo.myOrdersStream()`-ті ӨЗІНШЕ ашатын: бір дерек үшін қатар 2–3
/// цикл әр 4 секунд сайын желіге шығатын. Енді бәрі осы провайдерді
/// тыңдайды; ешкім тыңдамаса (`autoDispose`) цикл тоқтайды.
final myOrdersStreamProvider = StreamProvider.autoDispose<List<Order>>((ref) {
  ref.watch(authUidProvider);
  return Repo.myOrdersStream(fresh: true);
});

/// Таңдаулы/бұғат тізімдері серверде бар ма (0079) — мәзір тармағы үшін.
final executorPrefsAvailableProvider = FutureProvider<bool>(
  (ref) => Repo.executorPrefsAvailable(),
);

/// Оқылмаған хабарламалар саны (0080) — мәзірдегі 🔔 белгісі үшін.
final unreadNotificationsProvider = StreamProvider.autoDispose<int>((ref) {
  ref.watch(authUidProvider);
  return Repo.unreadNotificationsStream(fresh: true);
});

/// Орындаушының белсенді заказдары (баннер, мәзір белгісі) — бір цикл.
final myActiveExecutorOrdersProvider = StreamProvider.autoDispose<List<Order>>((
  ref,
) {
  ref.watch(authUidProvider);
  return Repo.myActiveExecutorOrdersStream(fresh: true);
});

/// Тікелей жаңарып отыратын статистика стримі. `autoDispose` — ешкім
/// тыңдамай қалса (мыс. логаут/рөл ауысу) polling тоқтап, жады босайды.
final executorStatsStreamProvider = StreamProvider.autoDispose<ExecutorStats>(
  (ref) => Repo.executorStatsStream(fresh: true),
);

/// Бонус прогресі (0059). `autoDispose` — тыңдаушы қалмаса polling тоқтайды.
/// Бағдарлама өшірулі болса стрим «off» күйін қайтарады да, ешбір экран
/// қосымша сұраныс жасамайды.
final executorBonusStreamProvider = StreamProvider.autoDispose<BonusInfo>(
  (ref) => Repo.executorBonusStream(fresh: true),
);

/// Орындаушы лентасы (§5/§6). Riverpod стримді КЭШТЕЙДІ — сондықтан статистика
/// әр 4 сек жаңарғанда бет қайта құрылса да, лента стримі қайта жазылмайды
/// (әйтпесе әр рефреште ресетке түсіп, автообновление «жоғалатын»).
/// `autoDispose` — ешкім тыңдамай қалса polling тоқтайды.
final executorFeedStreamProvider = StreamProvider.autoDispose<List<Order>>(
  (ref) => Repo.executorFeedStream(fresh: true),
);

/// Қосымша ЭКРАНДА ма (фонда емес). Фонда polling тоқтап тұрады —
/// батарея мен трафик бекер жұмсалмайды; қайта ашылғанда бірден жаңарады.
///
/// «Фонда» = `hidden` / `paused` / `detached`: телефон құлыпталған не басқа
/// қосымшаға ауысқан, ВЕБТЕ — браузер қойындысы жасырын (Flutter web оны
/// `hidden` деп береді). `inactive` (мыс. вебте терезе фокусын жоғалтты,
/// бірақ көрініп тұр) — белсенді болып саналады: экрандағы дерек жаңара береді.
class _AppVisibility with WidgetsBindingObserver {
  _AppVisibility._() {
    WidgetsBinding.instance.addObserver(this);
  }
  static final _instance = _AppVisibility._();

  Completer<void>? _waiter;

  static bool get _active {
    final s = WidgetsBinding.instance.lifecycleState;
    return s == null ||
        s == AppLifecycleState.resumed ||
        s == AppLifecycleState.inactive;
  }

  static Future<void> waitActive() async {
    if (_active) return;
    final self = _instance;
    self._waiter ??= Completer<void>();
    await self._waiter!.future;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_active) {
      _waiter?.complete();
      _waiter = null;
    }
  }
}

/// Бір кілтке ортақ периодты сұрау (қараңыз: [Repo._poll]).
class _SharedPoll {
  _SharedPoll(this._fetch, this._every, {required this.onIdle});

  final Future<Object?> Function() _fetch;
  final Duration _every;
  final void Function(_SharedPoll) onIdle;

  final _listeners = <MultiStreamController<Object?>>{};
  Object? _last;
  bool _hasLast = false;
  bool _running = false;
  int _gen = 0;
  Timer? _stopTimer;

  /// Тіктер арасындағы күту — [refresh] оны мерзімінен бұрын оятады.
  Completer<void>? _wake;

  /// Сұрау жүріп жатқанда [refresh] келді ме — келсе, жауап келген соң
  /// күтпей тағы бір рет сұраймыз (әрекетке дейін басталған ескі жауап
  /// жаңа күйдің орнына қалып қоймауы үшін).
  bool _again = false;

  Stream<Object?> get stream => Stream<Object?>.multi((c) {
    _stopTimer?.cancel();
    _stopTimer = null;
    _listeners.add(c);
    if (_hasLast) c.add(_last);
    c.onCancel = () {
      _listeners.remove(c);
      if (_listeners.isEmpty) {
        // Сәл күтеміз: StreamBuilder қайта жазылғанда (ескісінен шығып,
        // бірден жаңасына кіреді) цикл үзіліп, қайта басталмауы үшін.
        _stopTimer = Timer(const Duration(seconds: 3), _stop);
      }
    };
    if (!_running) _start();
  });

  void _start() {
    _running = true;
    _loop(++_gen);
  }

  void _stop() {
    if (_listeners.isNotEmpty) return;
    _running = false;
    _gen++;
    _wakeUp();
    onIdle(this);
  }

  /// Келесі тікті күтпей БІРДЕН қайта сұрау (қараңыз: `Repo._poll(fresh:)`).
  void refresh() {
    if (!_running) return;
    _again = true;
    _wakeUp();
  }

  void _wakeUp() {
    final w = _wake;
    if (w != null && !w.isCompleted) w.complete();
  }

  Future<void> _loop(int gen) async {
    while (_running && gen == _gen) {
      await _AppVisibility.waitActive();
      if (!_running || gen != _gen) return;
      _again = false;
      try {
        final v = await _fetch();
        if (gen != _gen) return;
        _last = v;
        _hasLast = true;
        for (final c in List.of(_listeners)) {
          c.add(v);
        }
      } catch (_) {
        // соңғы мәнде қалады, экранда loader көрсетілмейді
      }
      if (_again) continue;
      final wake = _wake = Completer<void>();
      final timer = Timer(_every, _wakeUp);
      await wake.future;
      timer.cancel();
      if (identical(_wake, wake)) _wake = null;
    }
  }
}
