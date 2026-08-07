import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';

/// Модератордың жалпы баптау экраны: тариф бағасы, Kaspi деректері,
/// мәжбүрлі жаңарту талабы — бәрі осында, SQL Editor-сыз (0030 миграциясы).
class AppSettingsScreen extends StatefulWidget {
  const AppSettingsScreen({super.key});

  @override
  State<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends State<AppSettingsScreen> {
  bool _loading = true;
  String? _error;

  /// Хабарландырулар тақтасы қосулы ма (0043). Бүкіл жаңа фича осының
  /// қолында: false болса, клиент те, орындаушы да «әлі қосылмады» дегенді
  /// ғана көреді.
  bool _boardEnabled = false;
  bool _boardSaving = false;

  /// «Такси» бөлімі қосулы ма (0046). ӨШУЛІ болса клиенттің басты бетінде
  /// «Такси / Жүк·Спецтехника» санаттары МҮЛДЕМ көрінбейді (баяғы қалып),
  /// орындаушы да такси түрін таңдай алмайды.
  bool _taxiEnabled = false;
  bool _taxiSaving = false;

  /// «ЖАҢА» белгілері (0058) — фичаның ӨЗІНЕН бөлек. Фича қосулы қалады,
  /// тек «жаңа» деген жапсырма алынады (уақыт өте ол ескіреді).
  /// `mod_update_setting` мәнді БҮТІНДЕЙ ауыстыратындықтан, әр қосқыш
  /// екеуін де (`enabled` + `new_badge`) бірге жазады.
  bool _boardNewBadge = true;
  bool _boardBadgeSaving = false;
  bool _taxiNewBadge = true;
  bool _taxiBadgeSaving = false;

  /// Чекті тексеретін бот қосулы ма (0051). Өшірулі болса ештеңе өзгермейді —
  /// толтырулар баяғыдай толық қолмен қаралады.
  bool _botEnabled = false;
  bool _botSaving = false;

  /// `topup_bot` баптауының ТОЛЫҚ көшірмесі. `mod_update_setting` мәнді
  /// БҮТІНДЕЙ АУЫСТЫРАДЫ (merge жасамайды), ал бұл экранда 9 кілттің тек 3-еуі
  /// көрінеді — қалғаны жоғалып кетпеуі үшін бастапқы мәнді сақтап қоямыз.
  Map<String, dynamic> _botRaw = {};

  /// Қолдау чатының авто-жауап боты қосулы ма (0054). ЖАСЫРЫН жұмыс
  /// істейді — қосулы болса, пайдаланушыға жазған адам мен бот арасында
  /// айырмашылық көрінбейді. Әдепкіде ӨШІРУЛІ.
  bool _supportBotEnabled = false;
  bool _supportBotSaving = false;

  final _tariffPrice = TextEditingController();
  final _durationHours = TextEditingController();
  final _ordersPerShift = TextEditingController();

  // ---------- Бонус бағдарламасы (0059) ----------
  /// Орындаушы кезеңде N заказ аяқтаса — балансына бонус түседі.
  /// Қосқыш бірден сақталады, ал сандар «Сақтау» түймесімен.
  BonusConfig _bonus = const BonusConfig();
  bool _bonusSaving = false;
  final _bonusTarget = TextEditingController();
  final _bonusAmount = TextEditingController();
  String _bonusPeriod = 'week';
  bool _bonusRepeat = true;

  /// Модератордың бонус есебі (қанша берілді, кімге) — тек көрсетуге.
  Map<String, dynamic>? _bonusStats;

  // ---------- Клиент фичалары (0060) ----------
  bool _repeatOrderEnabled = true;
  bool _repeatOrderSaving = false;
  bool _scheduledOrdersEnabled = false;
  bool _scheduledOrdersSaving = false;
  final _schedMinHours = TextEditingController();
  final _schedMaxDays = TextEditingController();
  bool _liveTrackingEnabled = false;
  bool _liveTrackingSaving = false;
  bool _shareTripEnabled = false;
  bool _shareTripSaving = false;
  bool _referralEnabled = false;
  bool _referralSaving = false;
  Map<String, dynamic> _referralRaw = {};
  final _referralBonusAmount = TextEditingController();

  /// Ауысым терезесінің түрі (0055): `fixed` — сағатқа тіркелген циклдік
  /// терезе (08:00-ден бастап, ұзындығы [_durationHours]); `rolling` —
  /// сатып алған СӘТТЕН бастап +[_durationHours] сағат.
  String _durationMode = 'fixed';
  final _botMax = TextEditingController();
  final _botMerchants = TextEditingController();
  final _botAgeHours = TextEditingController();
  final _kaspiNumber = TextEditingController();
  final _kaspiName = TextEditingController();
  final _kaspiTopupUrl = TextEditingController();
  final _minTopup = TextEditingController();
  final _minBuildAndroid = TextEditingController();
  final _minBuildIos = TextEditingController();
  final _androidUrl = TextEditingController();
  final _iosUrl = TextEditingController();
  final _updateMessage = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tariffPrice.dispose();
    _durationHours.dispose();
    _ordersPerShift.dispose();
    _bonusTarget.dispose();
    _bonusAmount.dispose();
    _botMax.dispose();
    _botMerchants.dispose();
    _botAgeHours.dispose();
    _kaspiNumber.dispose();
    _kaspiName.dispose();
    _kaspiTopupUrl.dispose();
    _minTopup.dispose();
    _minBuildAndroid.dispose();
    _minBuildIos.dispose();
    _androidUrl.dispose();
    _iosUrl.dispose();
    _updateMessage.dispose();
    _schedMinHours.dispose();
    _schedMaxDays.dispose();
    _referralBonusAmount.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await Repo.settings();
      final tariffs = (s['tariffs'] as Map?) ?? {};
      final payment = (s['payment'] as Map?) ?? {};
      final gate = (s['version_gate'] as Map?) ?? {};
      final board = (s['listings'] as Map?) ?? {};
      _boardEnabled = board['enabled'] == true;
      // Кілт мүлдем жоқ болса — белгі КӨРІНЕДІ (сервердегі `new_badges()`
      // де солай әдепкіленеді, екеуі бір-бірімен сәйкес болуы шарт).
      _boardNewBadge = board['new_badge'] != false;
      final taxi = (s['taxi'] as Map?) ?? {};
      _taxiEnabled = taxi['enabled'] == true;
      _taxiNewBadge = taxi['new_badge'] != false;
      final bot = (s['topup_bot'] as Map?) ?? {};
      _botRaw = Map<String, dynamic>.from(bot);
      _botEnabled = bot['enabled'] == true;
      final supportBot = (s['support_bot'] as Map?) ?? {};
      _supportBotEnabled = supportBot['enabled'] == true;
      _botMax.text = '${bot['auto_approve_max'] ?? 0}';
      _botAgeHours.text = '${bot['max_receipt_age_hours'] ?? 24}';
      _botMerchants.text =
          ((bot['merchant_names'] as List?) ?? const []).join(', ');
      _tariffPrice.text = '${tariffs['simple_day'] ?? 300}';
      _durationMode =
          tariffs['duration_mode'] == 'rolling' ? 'rolling' : 'fixed';
      _durationHours.text = '${tariffs['duration_hours'] ?? 12}';
      _ordersPerShift.text = '${tariffs['orders_per_shift'] ?? 10}';
      // ---- бонус бағдарламасы (0059) ----
      final bonusRaw = s['bonus'];
      _bonus = BonusConfig.fromMap(
        bonusRaw is Map ? Map<String, dynamic>.from(bonusRaw) : null,
      );
      _bonusTarget.text = '${_bonus.target}';
      _bonusAmount.text = '${_bonus.amount}';
      _bonusPeriod = _bonus.period;
      _bonusRepeat = _bonus.repeat;
      // Есеп жеке жүктеледі — қатесі баптау экранын бұғаттамауы керек.
      _loadBonusStats();
      _kaspiNumber.text = '${payment['kaspi_number'] ?? ''}';
      _kaspiName.text = '${payment['kaspi_name'] ?? ''}';
      _kaspiTopupUrl.text = '${payment['kaspi_topup_url'] ?? ''}';
      _minTopup.text = '${payment['min_topup'] ?? 500}';
      // Ескі жалғыз min_build бар болса — екі өріске де көшіріледі.
      _minBuildAndroid.text =
          '${gate['min_build_android'] ?? gate['min_build'] ?? 0}';
      _minBuildIos.text = '${gate['min_build_ios'] ?? gate['min_build'] ?? 0}';
      _androidUrl.text = '${gate['android_url'] ?? ''}';
      _iosUrl.text = '${gate['ios_url'] ?? ''}';
      _updateMessage.text = '${gate['message'] ?? ''}';
      // ---- клиент фичалары (0060) ----
      final repeatOrder = (s['repeat_order'] as Map?) ?? {};
      _repeatOrderEnabled = repeatOrder['enabled'] != false;
      final sched = (s['scheduled_orders'] as Map?) ?? {};
      _scheduledOrdersEnabled = sched['enabled'] == true;
      _schedMinHours.text = '${sched['min_hours_ahead'] ?? 2}';
      _schedMaxDays.text = '${sched['max_days_ahead'] ?? 14}';
      final live = (s['live_tracking'] as Map?) ?? {};
      _liveTrackingEnabled = live['enabled'] == true;
      final share = (s['share_trip'] as Map?) ?? {};
      _shareTripEnabled = share['enabled'] == true;
      final referral = (s['referral'] as Map?) ?? {};
      _referralRaw = Map<String, dynamic>.from(referral);
      _referralEnabled = referral['enabled'] == true;
      _referralBonusAmount.text = '${referral['executor_bonus_amount'] ?? 200}';
    } catch (e) {
      _error = errText(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int? _int(TextEditingController c) => int.tryParse(c.text.trim());

  Future<void> _saveTariff() async {
    final price = _int(_tariffPrice);
    if (price == null || price < 0) {
      showSnack(context, t('Бағаны дұрыс жазыңыз'), error: true);
      return;
    }
    final hours = _int(_durationHours);
    if (hours == null || hours < 1 || hours > 24) {
      showSnack(context, t('Ұзақтығын 1-24 сағат аралығында жазыңыз'),
          error: true);
      return;
    }
    final orders = _int(_ordersPerShift);
    if (orders == null || orders < 1) {
      showSnack(context, t('Заказ санын дұрыс жазыңыз'), error: true);
      return;
    }
    await Repo.modUpdateSetting('tariffs', {
      'simple_day': price,
      'simple_night': price,
      'duration_mode': _durationMode,
      'duration_hours': hours,
      'orders_per_shift': orders,
    });
    if (mounted) showSnack(context, t('Сақталды'));
  }

  // ---------- Бонус бағдарламасы (0059) ----------
  /// Есеп жеке жүктеледі: желі қатесі болса баптау экраны бәрібір ашылады
  /// (есеп жай ғана көрінбейді).
  Future<void> _loadBonusStats() async {
    try {
      final st = await Repo.modBonusStats();
      if (mounted) setState(() => _bonusStats = st);
    } catch (_) {
      /* есеп — қосымша мәлімет, қатесі елеусіз */
    }
  }

  /// Қосу/өшіру — бірден сақталады. Өшірулі болса орындаушыда бонус
  /// жолағы МҮЛДЕМ көрінбейді және ешбір бонус берілмейді.
  Future<void> _toggleBonus(bool v) async {
    final next = BonusConfig(
      enabled: v,
      target: _bonus.target,
      amount: _bonus.amount,
      period: _bonus.period,
      repeat: _bonus.repeat,
    );
    setState(() {
      _bonus = next;
      _bonusSaving = true;
    });
    try {
      await Repo.modUpdateSetting('bonus', next.toMap());
      if (mounted) {
        showSnack(
          context,
          v ? t('Бонус бағдарламасы қосылды') : t('Бонус бағдарламасы өшірілді'),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _bonus = BonusConfig(
            enabled: !v,
            target: next.target,
            amount: next.amount,
            period: next.period,
            repeat: next.repeat,
          ),
        );
        showSnack(context, errText(e), error: true);
      }
    } finally {
      if (mounted) setState(() => _bonusSaving = false);
    }
  }

  Future<void> _saveBonus() async {
    final target = _int(_bonusTarget);
    if (target == null || target < 1) {
      showSnack(context, t('Заказ санын дұрыс жазыңыз'), error: true);
      return;
    }
    final amount = _int(_bonusAmount);
    if (amount == null || amount < 1) {
      showSnack(context, t('Бонус сомасын дұрыс жазыңыз'), error: true);
      return;
    }
    final next = BonusConfig(
      enabled: _bonus.enabled,
      target: target,
      amount: amount,
      period: _bonusPeriod,
      repeat: _bonusRepeat,
    );
    await Repo.modUpdateSetting('bonus', next.toMap());
    if (mounted) {
      setState(() => _bonus = next);
      showSnack(context, t('Сақталды'));
    }
  }

  Future<void> _savePayment() async {
    final minTopup = _int(_minTopup) ?? 500;
    await Repo.modUpdateSetting('payment', {
      'kaspi_number': _kaspiNumber.text.trim(),
      'kaspi_name': _kaspiName.text.trim(),
      'kaspi_topup_url': _kaspiTopupUrl.text.trim(),
      'min_topup': minTopup,
    });
    if (mounted) showSnack(context, t('Сақталды'));
  }

  // ---------- Чекті тексеретін бот (0051) ----------
  /// Ботты қосу/өшіру — бірден сақталады. Өшірулі болса ешбір өтінім
  /// автоматты тексерілмейді де, расталмайды да.
  Future<void> _toggleBot(bool v) async {
    setState(() {
      _botEnabled = v;
      _botSaving = true;
    });
    try {
      await Repo.modUpdateSetting('topup_bot', {..._botRaw, 'enabled': v});
      _botRaw['enabled'] = v;
      if (mounted) {
        showSnack(context, v ? t('Бот қосылды') : t('Бот өшірілді'));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _botEnabled = !v);
        showSnack(context, errText(e), error: true);
      }
    } finally {
      if (mounted) setState(() => _botSaving = false);
    }
  }

  // ---------- Қолдау чатының авто-жауап боты (0054) ----------
  /// Қосу/өшіру — бірден сақталады. Қосулы болса, пайдаланушы жазған
  /// хабарламаға бот өзі жауап береді (модератордан ажыратылмайды);
  /// заказ статусына қатысты сұрақ не «оператор» деген сұраныс келсе,
  /// бот тиіспейді — Telegram-ге модераторға ескерту жіберіледі.
  Future<void> _toggleSupportBot(bool v) async {
    setState(() {
      _supportBotEnabled = v;
      _supportBotSaving = true;
    });
    try {
      await Repo.modUpdateSetting(
        'support_bot',
        {'enabled': v, 'max_auto_replies_per_thread': 5},
      );
      if (mounted) {
        showSnack(
          context,
          v ? t('Қолдау боты қосылды') : t('Қолдау боты өшірілді'),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _supportBotEnabled = !v);
        showSnack(context, errText(e), error: true);
      }
    } finally {
      if (mounted) setState(() => _supportBotSaving = false);
    }
  }

  Future<void> _saveBot() async {
    final max = _int(_botMax) ?? 0;
    final ageH = _int(_botAgeHours) ?? 24;
    final merchants = _botMerchants.text
        .split(RegExp(r'[,\n;]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final next = {
      ..._botRaw,
      'enabled': _botEnabled,
      'auto_approve_max': max < 0 ? 0 : max,
      'max_receipt_age_hours': ageH < 1 ? 1 : ageH,
      'merchant_names': merchants,
    };
    await Repo.modUpdateSetting('topup_bot', next);
    _botRaw = next;
    if (mounted) showSnack(context, t('Сақталды'));
  }

  /// Kaspi Pay выпискасын жүктеу. Бұл авто-растауды БӨГЕМЕЙДІ — выписка
  /// әдетте растаудан кейін келеді. Рөлі: расталған толтырулардың нақты
  /// түскен ақшамен сәйкестігін ТЕКСЕРУ.
  /// `BusyButton` спиннерді өзі басқарады, сондықтан бөлек «жүктелуде» күйі
  /// қажет емес.
  Future<void> _uploadStatement() async {
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['xlsx', 'xls', 'csv'],
        withData: true,
      );
      final file = picked?.files.firstOrNull;
      final bytes = file?.bytes;
      if (bytes == null) return;

      final path = await Repo.uploadStatement(file!.name, bytes);
      final res = await Repo.importKaspiStatement(path);
      if (!mounted) return;

      if (res['ok'] != true) {
        showSnack(
          context,
          '${t('Выписка оқылмады')}: ${res['hint'] ?? res['error'] ?? ''}',
          error: true,
        );
        return;
      }

      final missing = (res['missing'] as num?)?.toInt() ?? 0;
      final checked = (res['checked'] as num?)?.toInt() ?? 0;
      final inserted = (res['inserted'] as num?)?.toInt() ?? 0;
      showSnack(
        context,
        missing == 0
            ? '${t('Выписка жүктелді')} · $inserted ${t('жол')} · '
                '$checked ${t('толтырудың бәрі сәйкес')}'
            : '⚠️ $checked ${t('толтырудың')} $missing-${t('і выпискада ЖОҚ')}',
        error: missing > 0,
      );
    } catch (e) {
      if (mounted) showSnack(context, errText(e), error: true);
    }
  }

  /// Тақтаны қосу/өшіру — бірден сақталады (бөлек «Сақтау» батырмасы жоқ,
  /// себебі бұл бір ғана қосқыш).
  Future<void> _toggleBoard(bool v) async {
    setState(() {
      _boardEnabled = v;
      _boardSaving = true;
    });
    try {
      await Repo.modUpdateSetting(
        'listings',
        {'enabled': v, 'new_badge': _boardNewBadge},
      );
      if (mounted) {
        showSnack(
          context,
          v
              ? t('Хабарландырулар тақтасы ҚОСЫЛДЫ')
              : t('Хабарландырулар тақтасы ӨШІРІЛДІ'),
        );
      }
    } catch (e) {
      // Сәтсіз болса — қосқышты кері қайтарамыз (жалған күй қалмауы үшін).
      if (mounted) {
        setState(() => _boardEnabled = !v);
        showSnack(context, errText(e), error: true);
      }
    } finally {
      if (mounted) setState(() => _boardSaving = false);
    }
  }

  /// «Такси» бөлімін қосу/өшіру — бірден сақталады (жалғыз қосқыш).
  Future<void> _toggleTaxi(bool v) async {
    setState(() {
      _taxiEnabled = v;
      _taxiSaving = true;
    });
    try {
      await Repo.modUpdateSetting(
        'taxi',
        {'enabled': v, 'new_badge': _taxiNewBadge},
      );
      if (mounted) {
        showSnack(
          context,
          v ? t('Такси бөлімі ҚОСЫЛДЫ') : t('Такси бөлімі ӨШІРІЛДІ'),
        );
      }
    } catch (e) {
      // Сәтсіз болса — қосқышты кері қайтарамыз (жалған күй қалмауы үшін).
      if (mounted) {
        setState(() => _taxiEnabled = !v);
        showSnack(context, errText(e), error: true);
      }
    } finally {
      if (mounted) setState(() => _taxiSaving = false);
    }
  }

  // ---------- «ЖАҢА» жапсырмалары (0058) ----------
  /// Белгіні қосу/өшіру фичаның ӨЗІНЕ тимейді — тек жапсырма жоғалады.
  Future<void> _toggleNewBadge(bool v, {required bool board}) async {
    setState(() {
      if (board) {
        _boardNewBadge = v;
        _boardBadgeSaving = true;
      } else {
        _taxiNewBadge = v;
        _taxiBadgeSaving = true;
      }
    });
    try {
      await Repo.modUpdateSetting(
        board ? 'listings' : 'taxi',
        {
          'enabled': board ? _boardEnabled : _taxiEnabled,
          'new_badge': v,
        },
      );
      if (mounted) {
        showSnack(
          context,
          v ? t('«ЖАҢА» белгісі қосылды') : t('«ЖАҢА» белгісі алынды'),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          if (board) {
            _boardNewBadge = !v;
          } else {
            _taxiNewBadge = !v;
          }
        });
        showSnack(context, errText(e), error: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          if (board) {
            _boardBadgeSaving = false;
          } else {
            _taxiBadgeSaving = false;
          }
        });
      }
    }
  }

  Future<void> _saveVersionGate() async {
    final android = _int(_minBuildAndroid) ?? 0;
    final ios = _int(_minBuildIos) ?? 0;
    await Repo.modUpdateSetting('version_gate', {
      'min_build_android': android,
      'min_build_ios': ios,
      // Ескі (build ≤ соңғы шыққанға дейінгі) клиенттер платформаны
      // ажыратпай тек `min_build`-ті оқиды — оларды ешбір платформада
      // ҚАТЕ бұғаттамау үшін екеуінің КІШІсін жазамыз (fail-open).
      'min_build': android < ios ? android : ios,
      'android_url': _androidUrl.text.trim(),
      'ios_url': _iosUrl.text.trim(),
      'message': _updateMessage.text.trim(),
    });
    if (mounted) showSnack(context, t('Сақталды'));
  }

  // ---------- Клиент фичалары (0060) — жалғыз қосқыштар бірден сақталады ----------
  Future<void> _toggleSimple(
    String key,
    bool value, {
    required ValueChanged<bool> apply,
    required ValueChanged<bool> setSaving,
  }) async {
    final prev = value; // қате болса кері қайтару үшін
    setState(() {
      apply(value);
      setSaving(true);
    });
    try {
      await Repo.modUpdateSetting(key, {'enabled': value});
      if (mounted) showSnack(context, value ? t('Қосылды') : t('Өшірілді'));
    } catch (e) {
      if (mounted) {
        setState(() => apply(!prev));
        showSnack(context, errText(e), error: true);
      }
    } finally {
      if (mounted) setState(() => setSaving(false));
    }
  }

  Future<void> _toggleRepeatOrder(bool v) => _toggleSimple(
        'repeat_order', v,
        apply: (v) => _repeatOrderEnabled = v,
        setSaving: (v) => _repeatOrderSaving = v,
      );

  Future<void> _toggleLiveTracking(bool v) => _toggleSimple(
        'live_tracking', v,
        apply: (v) => _liveTrackingEnabled = v,
        setSaving: (v) => _liveTrackingSaving = v,
      );

  Future<void> _toggleShareTrip(bool v) => _toggleSimple(
        'share_trip', v,
        apply: (v) => _shareTripEnabled = v,
        setSaving: (v) => _shareTripSaving = v,
      );

  /// Қосу/өшіру — `executor_bonus_amount`-ты жоғалтпау үшін генерик
  /// `_toggleSimple`-ды қолданбаймыз (ол тек `{'enabled': v}` жібереді,
  /// `mod_update_setting` мәнді толық ауыстырады).
  Future<void> _toggleReferral(bool v) async {
    setState(() {
      _referralEnabled = v;
      _referralSaving = true;
    });
    try {
      await Repo.modUpdateSetting('referral', {..._referralRaw, 'enabled': v});
      _referralRaw['enabled'] = v;
      if (mounted) showSnack(context, v ? t('Қосылды') : t('Өшірілді'));
    } catch (e) {
      if (mounted) {
        setState(() => _referralEnabled = !v);
        showSnack(context, errText(e), error: true);
      }
    } finally {
      if (mounted) setState(() => _referralSaving = false);
    }
  }

  Future<void> _saveReferralBonus() async {
    final amount = _int(_referralBonusAmount);
    if (amount == null || amount < 0) {
      showSnack(context, t('Соманы дұрыс жазыңыз'), error: true);
      return;
    }
    final next = {..._referralRaw, 'enabled': _referralEnabled,
        'executor_bonus_amount': amount};
    await Repo.modUpdateSetting('referral', next);
    _referralRaw = next;
    if (mounted) showSnack(context, t('Сақталды'));
  }

  /// Алдын ала тапсырыс (0060) — қосу/өшіру бірден, ал сағат/күн шегі
  /// «Сақтау» батырмасымен.
  Future<void> _toggleScheduledOrders(bool v) async {
    setState(() {
      _scheduledOrdersEnabled = v;
      _scheduledOrdersSaving = true;
    });
    try {
      await Repo.modUpdateSetting('scheduled_orders', {
        'enabled': v,
        'min_hours_ahead': _int(_schedMinHours) ?? 2,
        'max_days_ahead': _int(_schedMaxDays) ?? 14,
      });
      if (mounted) showSnack(context, v ? t('Қосылды') : t('Өшірілді'));
    } catch (e) {
      if (mounted) {
        setState(() => _scheduledOrdersEnabled = !v);
        showSnack(context, errText(e), error: true);
      }
    } finally {
      if (mounted) setState(() => _scheduledOrdersSaving = false);
    }
  }

  Future<void> _saveScheduledOrders() async {
    final minH = _int(_schedMinHours);
    if (minH == null || minH < 0) {
      showSnack(context, t('Сағатты дұрыс жазыңыз'), error: true);
      return;
    }
    final maxD = _int(_schedMaxDays);
    if (maxD == null || maxD < 1) {
      showSnack(context, t('Күнді дұрыс жазыңыз'), error: true);
      return;
    }
    await Repo.modUpdateSetting('scheduled_orders', {
      'enabled': _scheduledOrdersEnabled,
      'min_hours_ahead': minH,
      'max_days_ahead': maxD,
    });
    if (mounted) showSnack(context, t('Сақталды'));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          EmptyState(icon: Icons.wifi_off, title: _error!),
        ],
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ---- ЖАҢА БӨЛІМ: Такси (0046) ----
          _sectionTitle(t('Такси бөлімі')),
          Text(
            t('Қосулы болса — клиентте «Такси (ЖАҢА)» және «Спецтехника» '
                'деген екі санат шығады. «Такси» санатының ішінде ЕКІ түр '
                'бар: Такси (жолаушы) және Доставка (жеңіл көлікпен ұсақ '
                'жүк). Орындаушы да сол түрлерді таңдай алады. Өшулі болса '
                '— экран баяғы қалпында, екеуі де мүлдем көрінбейді. '
                'Астыңғы қосқыш — тек сары «ЖАҢА» жапсырмасы: бөлім '
                'ескіргенде оны бөлімнің өзін өшірмей-ақ алып тастайсыз.'),
            style: const TextStyle(color: Gz.textSecondary, fontSize: 12.5),
          ),
          const SizedBox(height: 10),
          _toggleCard(
            enabled: _taxiEnabled,
            saving: _taxiSaving,
            icon: _taxiEnabled ? Icons.local_taxi : Icons.local_taxi_outlined,
            onLabel: t('Клиентте «Такси» санаты көрінеді'),
            offLabel: t('Такси жасырылған (баяғы қалып)'),
            onChanged: _toggleTaxi,
          ),
          if (_taxiEnabled) ...[
            const SizedBox(height: 8),
            _toggleCard(
              enabled: _taxiNewBadge,
              saving: _taxiBadgeSaving,
              icon: Icons.fiber_new_outlined,
              onLabel: t('Плиткада сары «ЖАҢА» жапсырмасы тұр'),
              offLabel: t('Жапсырмасыз (бөлімнің өзі жұмыс істей береді)'),
              onChanged: (v) => _toggleNewBadge(v, board: false),
            ),
          ],
          const SizedBox(height: 24),
          _sectionTitle(t('Хабарландырулар тақтасы')),
          Text(
            t('Логотип батырмасындағы «Хабарландырулар» бөлімі: орындаушылар '
                'қызметін, клиенттер жұмысын жариялайды. Әр хабарландыру '
                '7 күн тұрады, сосын автоматты өшеді.'),
            style: const TextStyle(color: Gz.textSecondary, fontSize: 12.5),
          ),
          const SizedBox(height: 10),
          _toggleCard(
            enabled: _boardEnabled,
            saving: _boardSaving,
            icon: _boardEnabled ? Icons.storefront : Icons.storefront_outlined,
            onLabel: t('Қолданушылар хабарландыру бере алады'),
            offLabel: t('Қолданушыларға «әлі қосылмады» деп шығады'),
            onChanged: _toggleBoard,
          ),
          const SizedBox(height: 8),
          _toggleCard(
            enabled: _boardNewBadge,
            saving: _boardBadgeSaving,
            icon: Icons.fiber_new_outlined,
            onLabel: t('Мәзірдегі картада «Жаңа» жапсырмасы тұр'),
            offLabel: t('Жапсырмасыз (бөлімнің өзі орнында қалады)'),
            onChanged: (v) => _toggleNewBadge(v, board: true),
          ),
          const SizedBox(height: 24),
          _sectionTitle(t('Тариф бағасы')),
          Text(
            t('Орындаушы 1 ауысымға төлейтін баға, ауысымның қанша '
                'уақытқа созылатыны және сол ауысымда қанша заказ алуға '
                'болатыны.'),
            style: const TextStyle(color: Gz.textSecondary, fontSize: 12.5),
          ),
          const SizedBox(height: 10),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _tariffPrice,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: t('Тариф бағасы (₸)'),
                    prefixIcon: const Icon(Icons.payments_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  t('Ауысым түрі'),
                  style:
                      const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                const SizedBox(height: 8),
                RadioGroup<String>(
                  groupValue: _durationMode,
                  onChanged: (v) => setState(() => _durationMode = v!),
                  child: Column(
                    children: [
                      RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        value: 'fixed',
                        dense: true,
                        title: Text(t('Белгілі уақыт аралығында'),
                            style: const TextStyle(fontSize: 13.5)),
                        subtitle: Text(
                          t('Сағат 08:00-ден бастап циклмен қайталанады '
                              '(мыс. 12 сағат болса — 08:00–20:00 және '
                              '20:00–08:00).'),
                          style: const TextStyle(fontSize: 11.5),
                        ),
                      ),
                      RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        value: 'rolling',
                        dense: true,
                        title: Text(t('Қосқан сәттен бастап'),
                            style: const TextStyle(fontSize: 13.5)),
                        subtitle: Text(
                          t('Орындаушы тарифті қосқан уақыттан бастап '
                              'есептеледі (сағатқа қарамайды).'),
                          style: const TextStyle(fontSize: 11.5),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _durationHours,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: t('Ауысым ұзақтығы (сағат)'),
                    helperText: t('1-24 аралығында. Әдепкі — 12.'),
                    prefixIcon: const Icon(Icons.schedule_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _ordersPerShift,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: t('Бір ауысымға заказ саны (лимит)'),
                    helperMaxLines: 3,
                    helperText: t('Орындаушы осы санша заказ алған соң тариф '
                        'жабылады — жаңасын сатып алуы керек. Әдепкі — 10.'),
                    prefixIcon: const Icon(Icons.local_shipping_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                // Баптау НАҚТЫ нені білдіретінін орындаушы көретін
                // сөзбен көрсетеді — сақтамай тұрып та тексеруге болады.
                _previewBox(
                  Icons.visibility_outlined,
                  t('Орындаушы былай көреді'),
                  '${t('Тариф')} · ${_previewDuration()} · '
                      '${_previewOrders()}',
                ),
                const SizedBox(height: 12),
                BusyButton(label: t('Сақтау'), onPressed: _saveTariff),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // ---- ЖАҢА БӨЛІМ: белсенділік бонусы (0059) ----
          _sectionTitle(t('Белсенділік бонусы')),
          Text(
            t('Орындаушы белгілі кезеңде көп заказ аяқтаса — БАЛАНСЫНА бонус '
                'сомасы автоматты түседі. Прогресс («бонусқа N заказ қалды») '
                'заказдар лентасының жоғарысында тұрады. Бонус тек балансқа '
                'түседі — қолма-қол шешіп алынбайды, тариф сатып алуға '
                'жұмсалады.'),
            style: const TextStyle(color: Gz.textSecondary, fontSize: 12.5),
          ),
          const SizedBox(height: 10),
          _toggleCard(
            enabled: _bonus.enabled,
            saving: _bonusSaving,
            icon: _bonus.enabled
                ? Icons.card_giftcard
                : Icons.card_giftcard_outlined,
            onLabel: t('Бонус бағдарламасы жұмыс істеп тұр'),
            offLabel: t('Бонус берілмейді (лентада да көрінбейді)'),
            onChanged: _toggleBonus,
          ),
          const SizedBox(height: 10),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _bonusTarget,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: t('Бонусқа қажет заказ саны'),
                    helperText: t('Осынша заказ АЯҚТАЛҒАНДА бонус беріледі.'),
                    prefixIcon: const Icon(Icons.flag_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _bonusAmount,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: t('Бонус сомасы (₸)'),
                    helperText: t('Орындаушының балансына қосылады.'),
                    prefixIcon: const Icon(Icons.card_giftcard_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  t('Санақ қашан нөлденеді'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                RadioGroup<String>(
                  groupValue: _bonusPeriod,
                  onChanged: (v) => setState(() => _bonusPeriod = v!),
                  child: Column(
                    children: [
                      _periodTile(
                        'day',
                        t('Күн сайын'),
                        t('Заказ санағы әр түн ортасында нөлден басталады.'),
                      ),
                      _periodTile(
                        'week',
                        t('Апта сайын'),
                        t('Санақ әр дүйсенбіде жаңарады (әдепкі).'),
                      ),
                      _periodTile(
                        'month',
                        t('Ай сайын'),
                        t('Санақ әр айдың 1-інде жаңарады.'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: _bonusRepeat,
                  onChanged: (v) => setState(() => _bonusRepeat = v),
                  title: Text(
                    t('Кезең ішінде қайталансын'),
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    _bonusRepeat
                        ? t('Әр лимит сайын жаңа бонус беріледі (мыс. 20, 40, '
                              '60 заказ).')
                        : t('Бір кезеңде бір-ақ рет беріледі.'),
                    style: const TextStyle(fontSize: 11.5),
                  ),
                ),
                const SizedBox(height: 4),
                _previewBox(
                  Icons.card_giftcard_outlined,
                  t('Орындаушы былай көреді'),
                  _previewBonus(),
                ),
                const SizedBox(height: 12),
                BusyButton(label: t('Сақтау'), onPressed: _saveBonus),
              ],
            ),
          ),
          if (_bonusStats != null) ...[
            const SizedBox(height: 10),
            _bonusStatsCard(),
          ],
          const SizedBox(height: 24),
          _sectionTitle(t('Kaspi деректері')),
          Text(
            t('Орындаушылар балансты осыған аударады.'),
            style: const TextStyle(color: Gz.textSecondary, fontSize: 12.5),
          ),
          const SizedBox(height: 10),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _kaspiTopupUrl,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: t('Kaspi QR / төлем сілтемесі'),
                    hintText: 'https://pay.kaspi.kz/pay/...',
                    helperMaxLines: 3,
                    helperText: t(
                      'Орындаушыдағы «Kaspi-мен төлеу» түймесі осы сілтемені '
                      'ашады. Бос болса — түйме көрсетілмейді.',
                    ),
                    prefixIcon: const Icon(Icons.qr_code_2),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _kaspiNumber,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: t('Kaspi нөмірі (қосымша)'),
                    prefixIcon: const Icon(Icons.phone_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _kaspiName,
                  decoration: InputDecoration(
                    labelText: t('Алушының аты-жөні'),
                    prefixIcon: const Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _minTopup,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: t('Минималды толтыру сомасы (₸)'),
                    prefixIcon: const Icon(
                      Icons.account_balance_wallet_outlined,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                BusyButton(label: t('Сақтау'), onPressed: _savePayment),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // ---- ЖАҢА БӨЛІМ: чекті тексеретін бот (0051) ----
          _sectionTitle(t('Чек тексеретін бот')),
          Text(
            t('Жаңа толтыру өтінімі түскенде бот Kaspi чегін өзі ашып, екі '
                'тәуелсіз тәсілмен оқиды да, бәрі сәйкес келсе балансты '
                'автоматты толтырады. Күдікті болса — тиіспейді, Telegram-ға '
                'себебін жазады, шешімді сіз қабылдайсыз.'),
            style: const TextStyle(color: Gz.textSecondary, fontSize: 12.5),
          ),
          const SizedBox(height: 10),
          _toggleCard(
            enabled: _botEnabled,
            saving: _botSaving,
            icon: _botEnabled ? Icons.smart_toy : Icons.smart_toy_outlined,
            onLabel: t('Бот чектерді тексеріп тұр'),
            offLabel: t('Барлық толтыру тек қолмен қаралады'),
            onChanged: _toggleBot,
          ),
          const SizedBox(height: 10),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _botMerchants,
                  decoration: InputDecoration(
                    labelText: t('Мерчант аттары (үтірмен)'),
                    hintText: 'ЖК Tasu, Tasu',
                    helperMaxLines: 4,
                    helperText: t(
                      'Kaspi QR арқылы төлегенде ЧЕКТЕ КӨРІНЕТІН алушының аты. '
                      'Бос болса бот ештеңені автоматты растамайды. Нақты атын '
                      'бірінші чек келгенде Telegram хабарынан көресіз.',
                    ),
                    prefixIcon: const Icon(Icons.storefront_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _botMax,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: t('Авто-растау шегі (₸)'),
                    helperMaxLines: 3,
                    helperText: t(
                      '0 қойсаңыз — бот бәрін тексереді, бірақ ЕШТЕҢЕНІ '
                      'растамайды (сынау режимі). Одан жоғары сомалар әрқашан '
                      'сізге келеді.',
                    ),
                    prefixIcon: const Icon(Icons.shield_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _botAgeHours,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: t('Чектің ең үлкен жасы (сағат)'),
                    helperMaxLines: 2,
                    helperText: t(
                      'Одан ескі чек автоматты расталмайды — ескі чекті қайта '
                      'жіберуден қорғайды.',
                    ),
                    prefixIcon: const Icon(Icons.schedule_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                BusyButton(label: t('Сақтау'), onPressed: _saveBot),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  t('Kaspi выпискасын аптасына бір рет жүктеп тұрсаңыз, бот '
                      'расталған толтырулардың ақшасы ШЫН ТҮСКЕНІН тексереді. '
                      'Чек скриншоттан кейін қайтарылып алынса — тек осылай '
                      'білуге болады.'),
                  style:
                      const TextStyle(color: Gz.textSecondary, fontSize: 12.5),
                ),
                const SizedBox(height: 12),
                BusyButton(
                  label: t('Kaspi выпискасын жүктеу'),
                  outlined: true,
                  icon: Icons.upload_file_outlined,
                  onPressed: _uploadStatement,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // ---- ЖАҢА БӨЛІМ: қолдау чатының авто-жауап боты (0054) ----
          _sectionTitle(t('Қолдау чатының боты')),
          Text(
            t('Қосулы болса, пайдаланушы (клиент/орындаушы) қолдау чатына '
                'жазғанда бот өзі жауап береді — модератор жазғандай көрінеді, '
                'бот екені білінбейді. Заказ статусына қатысты сұрақ не '
                '«оператор» деген сұраныс келсе — бот тиіспейді, Telegram-ге '
                'ескерту барады, модератор өзі жалғастырады.'),
            style: const TextStyle(color: Gz.textSecondary, fontSize: 12.5),
          ),
          const SizedBox(height: 10),
          _toggleCard(
            enabled: _supportBotEnabled,
            saving: _supportBotSaving,
            icon: _supportBotEnabled
                ? Icons.support_agent
                : Icons.support_agent_outlined,
            onLabel: t('Бот қолдау чатына жауап беріп тұр'),
            offLabel: t('Барлық хабарлама тек модераторға келеді'),
            onChanged: _toggleSupportBot,
          ),
          const SizedBox(height: 24),
          // ---- ЖАҢА БӨЛІМ: клиентке пайдалы фичалар (0060) ----
          _sectionTitle(t('Тапсырысты қайталау')),
          Text(
            t('Клиент аяқталған/тоқтатылған заказды бір батырмамен қайта '
                'ашады (маршрут пен көлік түрі дайын тұрады).'),
            style: const TextStyle(color: Gz.textSecondary, fontSize: 12.5),
          ),
          const SizedBox(height: 10),
          _toggleCard(
            enabled: _repeatOrderEnabled,
            saving: _repeatOrderSaving,
            icon: Icons.replay_rounded,
            onLabel: t('Клиент «Тағы да тапсырыс беру» түймесін көреді'),
            offLabel: t('Түйме жасырылған'),
            onChanged: _toggleRepeatOrder,
          ),
          const SizedBox(height: 24),

          _sectionTitle(t('Алдын ала тапсырыс')),
          Text(
            t('Клиент заказды белгілі бір күн-уақытқа жоспарлай алады — '
                'сол уақыт келгенше орындаушыларға көрінбейді.'),
            style: const TextStyle(color: Gz.textSecondary, fontSize: 12.5),
          ),
          const SizedBox(height: 10),
          _toggleCard(
            enabled: _scheduledOrdersEnabled,
            saving: _scheduledOrdersSaving,
            icon: Icons.schedule_outlined,
            onLabel: t('Клиент алдын ала тапсырыс бере алады'),
            offLabel: t('Тек «дәл қазір» заказ'),
            onChanged: _toggleScheduledOrders,
          ),
          if (_scheduledOrdersEnabled) ...[
            const SizedBox(height: 10),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _schedMinHours,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: t('Ең аз алдын ала уақыт (сағат)'),
                      prefixIcon: const Icon(Icons.hourglass_bottom_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _schedMaxDays,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: t('Ең көп алдын ала уақыт (күн)'),
                      prefixIcon: const Icon(Icons.event_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  BusyButton(
                      label: t('Сақтау'), onPressed: _saveScheduledOrders),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),

          _sectionTitle(t('Орындаушыны картада тірі көрсету')),
          Text(
            t('Клиент белсенді заказда орындаушының ағымдағы орнын картадан '
                'көреді (орындаушы GPS-і 20 секунд сайын жіберіледі).'),
            style: const TextStyle(color: Gz.textSecondary, fontSize: 12.5),
          ),
          const SizedBox(height: 10),
          _toggleCard(
            enabled: _liveTrackingEnabled,
            saving: _liveTrackingSaving,
            icon: Icons.location_searching,
            onLabel: t('Орындаушының орны картада көрінеді'),
            offLabel: t('Тек статикалық маршрут'),
            onChanged: _toggleLiveTracking,
          ),
          const SizedBox(height: 24),

          _sectionTitle(t('Сапарды бөлісу')),
          Text(
            t('Клиент заказдың сілтемесін жақынына жібере алады — олар '
                'қосымшасыз, кірместен барысты қарайды.'),
            style: const TextStyle(color: Gz.textSecondary, fontSize: 12.5),
          ),
          const SizedBox(height: 10),
          _toggleCard(
            enabled: _shareTripEnabled,
            saving: _shareTripSaving,
            icon: Icons.ios_share,
            onLabel: t('«Бөлісу» түймесі көрінеді'),
            offLabel: t('Сілтемелер жұмыс істемейді'),
            onChanged: _toggleShareTrip,
          ),
          const SizedBox(height: 24),

          _sectionTitle(t('Жаттыққа шақыру бонусы')),
          Text(
            t('Пайдаланушылар бір-бірін өз кодымен шақырады (тіркелу '
                'экранында да, профильде де енгізуге болады). Шақырушы '
                'ОРЫНДАУШЫ болса — балансына нақты бонус түседі. Шақырушы '
                'клиент болса — тек «N адам шақырдыңыз» санағы өседі '
                '(клиентте баланс жоқ).'),
            style: const TextStyle(color: Gz.textSecondary, fontSize: 12.5),
          ),
          const SizedBox(height: 10),
          _toggleCard(
            enabled: _referralEnabled,
            saving: _referralSaving,
            icon: Icons.card_giftcard,
            onLabel: t('Шақыру коды қосулы'),
            offLabel: t('Шақыру функциясы жасырылған'),
            onChanged: _toggleReferral,
          ),
          if (_referralEnabled) ...[
            const SizedBox(height: 10),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _referralBonusAmount,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: t('Орындаушыға бонус сомасы (₸)'),
                      helperText: t(
                          'Шақырған адамы орындаушы болса, досы тіркеліп '
                          'кодты енгізген сәтте балансына қосылады. '
                          '0 қойсаңыз — бонус берілмейді, тек санақ жүреді.'),
                      helperMaxLines: 3,
                      prefixIcon: const Icon(Icons.payments_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  BusyButton(
                      label: t('Сақтау'), onPressed: _saveReferralBonus),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),

          _sectionTitle(t('Мәжбүрлі жаңарту')),
          Text(
            t('Дүкенде жаңа нұсқа ЖАРИЯЛАНҒАН соң минималды build нөмірін '
                'көтеріңіз — одан төмендегілер тек «Жаңарту» батырмасын '
                'көреді. iOS санын App Store-да шыққанша көтермеңіз. '
                'Build = pubspec.yaml-дағы "+N". 0 = тексеру өшулі.'),
            style: const TextStyle(color: Gz.textSecondary, fontSize: 12.5),
          ),
          const SizedBox(height: 10),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _minBuildAndroid,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: t('Android минималды build'),
                    prefixIcon: const Icon(Icons.android),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _minBuildIos,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: t('iOS минималды build'),
                    prefixIcon: const Icon(Icons.apple),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _androidUrl,
                  decoration: InputDecoration(
                    labelText: t('Play Market сілтемесі'),
                    prefixIcon: const Icon(Icons.android),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _iosUrl,
                  decoration: InputDecoration(
                    labelText: t('App Store сілтемесі'),
                    prefixIcon: const Icon(Icons.apple),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _updateMessage,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: t('Хабарлама мәтіні'),
                    prefixIcon: const Icon(Icons.message_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                BusyButton(label: t('Сақтау'), onPressed: _saveVersionGate),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// Бір ғана қосқыштан тұратын фича картасы (такси, хабарландырулар…) —
  /// бірден сақталады, бөлек «Сақтау» батырмасы жоқ.
  Widget _toggleCard({
    required bool enabled,
    required bool saving,
    required IconData icon,
    required String onLabel,
    required String offLabel,
    required ValueChanged<bool> onChanged,
  }) {
    return SectionCard(
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
      child: Row(
        children: [
          Icon(icon, color: enabled ? Gz.green : Gz.textSecondary),
          const SizedBox(width: 12),
          // Қосқыш пен иконка орын алады: түсініктеме жолы сыймай екінші
          // жолға түскенде картаның биіктігі «секіріп» тұратын — BtnLabel
          // сыймаса кішірейтеді де, қатар әрқашан бір биіктікте қалады.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  enabled ? t('Қосулы') : t('Өшулі'),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: enabled ? Gz.green : Gz.textSecondary,
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: BtnLabel(
                    enabled ? onLabel : offLabel,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Gz.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (saving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            Switch(
              value: enabled,
              activeThumbColor: Gz.green,
              onChanged: onChanged,
            ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String s) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      s,
      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
    ),
  );

  // ================= БАПТАУДЫҢ АЛДЫН АЛА КӨРІНІСІ =================
  /// Модератор енгізген сан НАҚТЫ нені білдіретінін орындаушының өз
  /// сөзімен көрсетеді. Сақтамай тұрып та жаңарып отырады — «12 сағат»
  /// деген не, «10 заказ» қашан бітеді деп ойланудың қажеті жоқ.
  Widget _previewBox(IconData icon, String title, String body) => Container(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
    decoration: BoxDecoration(
      color: Gz.bg,
      borderRadius: BorderRadius.circular(13),
      border: Border.all(color: Gz.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 15, color: Gz.textSecondary),
            const SizedBox(width: 6),
            Text(
              title,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: Gz.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          body,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            height: 1.4,
          ),
        ),
      ],
    ),
  );

  /// Ауысым ұзақтығының сөзбен жазылуы — орындаушыдағы мәтіннің дәл өзі.
  String _previewDuration() {
    final h = _int(_durationHours);
    if (h == null || h < 1 || h > 24) return t('ұзақтығы дұрыс емес');
    return tariffDurationLabel(
      AppConfig(durationMode: _durationMode, durationHours: h),
    );
  }

  String _previewOrders() {
    final n = _int(_ordersPerShift);
    if (n == null || n < 1) return t('заказ саны дұрыс емес');
    return tariffOrdersLabel(AppConfig(ordersPerShift: n));
  }

  String _previewBonus() {
    final target = _int(_bonusTarget);
    final amount = _int(_bonusAmount);
    if (target == null || target < 1 || amount == null || amount < 1) {
      return t('Сандарды дұрыс жазыңыз');
    }
    final repeatNote = _bonusRepeat
        ? t('Әр лимит сайын қайталанады.')
        : t('Кезеңде бір рет.');
    return '${bonusPeriodNow(_bonusPeriod)} $target ${t('заказ аяқтасаңыз')} — '
        '${fmtT(amount)} ${t('балансқа')}. $repeatNote';
  }

  /// Кезең таңдауының бір жолы.
  Widget _periodTile(String value, String title, String subtitle) =>
      RadioListTile<String>(
        contentPadding: EdgeInsets.zero,
        value: value,
        dense: true,
        title: Text(title, style: const TextStyle(fontSize: 13.5)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 11.5)),
      );

  /// Бонусқа қанша ақша кеткенінің қысқаша есебі + топ-5 орындаушы.
  Widget _bonusStatsCard() {
    final st = _bonusStats!;
    final top = (st['top'] as List?) ?? const [];
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.insights_outlined,
                size: 18,
                color: Gz.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                t('Бонус есебі'),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _statMini(
                  t('Осы айда'),
                  fmtT(st['amount_month'] as num?),
                  '${st['awards_month'] ?? 0} ${t('бонус')}',
                  Gz.violet,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _statMini(
                  t('Барлық уақытта'),
                  fmtT(st['amount_total'] as num?),
                  '${st['awards_total'] ?? 0} ${t('бонус')}',
                  Gz.ink,
                ),
              ),
            ],
          ),
          if (top.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              t('Ең көп бонус алғандар'),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Gz.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            for (final r in top.whereType<Map>())
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${r['full_name'] ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    Text(
                      '${r['awards'] ?? 0}× · ${fmtT(r['total'] as num?)}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _statMini(String label, String value, String hint, Color color) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Gz.bg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(color: Gz.textSecondary, fontSize: 11.5),
            ),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              hint,
              style: const TextStyle(color: Gz.textSecondary, fontSize: 11),
            ),
          ],
        ),
      );
}
