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

  final _tariffPrice = TextEditingController();
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
      final taxi = (s['taxi'] as Map?) ?? {};
      _taxiEnabled = taxi['enabled'] == true;
      _tariffPrice.text = '${tariffs['simple_day'] ?? 300}';
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
    await Repo.modUpdateSetting('tariffs', {
      'simple_day': price,
      'simple_night': price,
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

  /// Тақтаны қосу/өшіру — бірден сақталады (бөлек «Сақтау» батырмасы жоқ,
  /// себебі бұл бір ғана қосқыш).
  Future<void> _toggleBoard(bool v) async {
    setState(() {
      _boardEnabled = v;
      _boardSaving = true;
    });
    try {
      await Repo.modUpdateSetting('listings', {'enabled': v});
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
      await Repo.modUpdateSetting('taxi', {'enabled': v});
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
                '— экран баяғы қалпында, екеуі де мүлдем көрінбейді.'),
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
          const SizedBox(height: 24),
          _sectionTitle(t('Тариф бағасы')),
          Text(
            t('Орындаушы 1 ауысымға (12 сағат, 10 заказ) төлейтін баға.'),
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
