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

  final _tariffPrice = TextEditingController();
  final _kaspiNumber = TextEditingController();
  final _kaspiName = TextEditingController();
  final _minTopup = TextEditingController();
  final _minBuild = TextEditingController();
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
    _minTopup.dispose();
    _minBuild.dispose();
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
      _tariffPrice.text = '${tariffs['simple_day'] ?? 300}';
      _kaspiNumber.text = '${payment['kaspi_number'] ?? ''}';
      _kaspiName.text = '${payment['kaspi_name'] ?? ''}';
      _minTopup.text = '${payment['min_topup'] ?? 500}';
      _minBuild.text = '${gate['min_build'] ?? 0}';
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
      'vip_day': price,
      'vip_night': price,
    });
    if (mounted) showSnack(context, t('Сақталды'));
  }

  Future<void> _savePayment() async {
    final minTopup = _int(_minTopup) ?? 500;
    await Repo.modUpdateSetting('payment', {
      'kaspi_number': _kaspiNumber.text.trim(),
      'kaspi_name': _kaspiName.text.trim(),
      'min_topup': minTopup,
    });
    if (mounted) showSnack(context, t('Сақталды'));
  }

  Future<void> _saveVersionGate() async {
    final minBuild = _int(_minBuild) ?? 0;
    await Repo.modUpdateSetting('version_gate', {
      'min_build': minBuild,
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
      return ListView(children: [
        const SizedBox(height: 120),
        EmptyState(icon: Icons.wifi_off, title: _error!),
      ]);
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle(t('Тариф бағасы')),
          Text(
            t('Орындаушы 1 ауысымға (12 сағат, 10 заказға дейін) төлейтін баға. '
                'Бағасы күндіз де, түнде де бірдей.'),
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
            t('Орындаушылар балансты осы деректерге аударады.'),
            style: const TextStyle(color: Gz.textSecondary, fontSize: 12.5),
          ),
          const SizedBox(height: 10),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _kaspiNumber,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: t('Kaspi нөмірі'),
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
                    prefixIcon: const Icon(Icons.account_balance_wallet_outlined),
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
            t('App Store/Play Market-ке жаңа нұсқа шығарғанда, осы жерден '
                'минималды build нөмірін көтеріңіз — одан төмен нұсқадағы '
                'пайдаланушылар қосымшаны аша алмайды, тек «Жаңарту» '
                'батырмасын көреді. Build нөмірі — pubspec.yaml-дағы '
                '"+N" (мыс. 1.0.2+5 → 5). 0 қойсаңыз — тексеру өшеді.'),
            style: const TextStyle(color: Gz.textSecondary, fontSize: 12.5),
          ),
          const SizedBox(height: 10),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _minBuild,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: t('Минималды build нөмірі'),
                    prefixIcon: const Icon(Icons.system_update_outlined),
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

  Widget _sectionTitle(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(s,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      );
}
