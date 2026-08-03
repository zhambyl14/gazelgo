import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/lang.dart';
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
                  decoration: InputDecoration(
                    labelText: t('Бір ауысымға заказ саны'),
                    helperText: t('Ауысым осы санға жеткенде жабылады. '
                        'Әдепкі — 10.'),
                    prefixIcon: const Icon(Icons.local_shipping_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                BusyButton(label: t('Сақтау'), onPressed: _saveTariff),
              ],
            ),
          ),
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
}
