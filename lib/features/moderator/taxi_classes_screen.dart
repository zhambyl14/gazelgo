/// Такси САНАТТАРЫН басқару экраны (0098): Эконом / Комфорт / Бизнес.
///
/// Модератор:
///   • санаттарды ҚОСАДЫ/ӨШІРЕДІ (өшірулі болса барлық таксист бір түр);
///   • «марка (+модель) (+жылдан бастап) → санат» ережелерін енгізеді;
///   • қосқанда санаты жоқ ескі таксистер ережеге сай АВТОМАТ бөлінеді
///     (сәйкес ереже жоқ болса — Эконом);
///   • қажет болса барлығын қайта есептейді.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/lang.dart';
import '../../core/repo.dart';
import '../../core/taxi_class.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';

class TaxiClassesScreen extends ConsumerStatefulWidget {
  const TaxiClassesScreen({super.key});

  @override
  ConsumerState<TaxiClassesScreen> createState() => _TaxiClassesScreenState();
}

class _TaxiClassesScreenState extends ConsumerState<TaxiClassesScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  bool get _enabled => _data?['enabled'] == true;

  List<Map<String, dynamic>> get _rules => [
    for (final r in (_data?['rules'] as List? ?? const []))
      Map<String, dynamic>.from(r as Map),
  ];

  int _count(String key) =>
      ((_data?['counts'] as Map?)?[key] as num?)?.toInt() ?? 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _data = await Repo.modTaxiClasses();
    } catch (e) {
      _error = errText(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Әрекетті орындап, экранды жаңартады; қатені snackbar-мен көрсетеді.
  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, errText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggle(bool on) => _run(() async {
    final n = await Repo.modSetTaxiClassesEnabled(on);
    ref.invalidate(taxiClassesEnabledProvider);
    if (!mounted) return;
    showSnack(
      context,
      on
          ? '${t('Санаттар қосылды')}. ${t('Автомат бөлінген таксист')}: $n'
          : t('Санаттар өшірілді'),
    );
  });

  Future<void> _reassign() async {
    final ok = await confirmDialog(
      context,
      icon: Icons.sync_rounded,
      title: t('Барлығын қайта бөлу?'),
      message: t(
        'Барлық таксистің санаты ережелерге сай қайта есептеледі. '
        'Қолмен қойылған санаттар да өзгереді.',
      ),
      confirmLabel: t('Қайта бөлу'),
      confirmColor: Gz.blue,
    );
    if (!ok) return;
    await _run(() async {
      final n = await Repo.modReassignTaxiClasses();
      if (mounted) showSnack(context, '${t('Қайта бөлінді')}: $n');
    });
  }

  Future<void> _delete(Map<String, dynamic> r) =>
      _run(() => Repo.modDeleteTaxiClassRule(r['id'] as String));

  Future<void> _editRule([Map<String, dynamic>? rule]) async {
    final res = await showDialog<_RuleDraft>(
      context: context,
      builder: (_) => _RuleDialog(rule: rule),
    );
    if (res == null) return;
    await _run(
      () => Repo.modSaveTaxiClassRule(
        id: rule?['id'] as String?,
        brand: res.brand,
        model: res.model,
        minYear: res.minYear,
        taxiClass: res.taxiClass.code,
      ),
    );
  }

  // -------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t('Такси санаттары'))),
      floatingActionButton: _enabled && !_loading
          ? FloatingActionButton.extended(
              onPressed: _busy ? null : () => _editRule(),
              icon: const Icon(Icons.add),
              label: Text(t('Ереже қосу')),
            )
          : null,
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading && _data == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _data == null) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          EmptyState(icon: Icons.wifi_off, title: _error!),
          const SizedBox(height: 16),
          Center(
            child: OutlinedButton(onPressed: _load, child: Text(t('Қайталау'))),
          ),
        ],
      );
    }
    final rules = _rules;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
        children: [
          SectionCard(
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _enabled,
              onChanged: _busy ? null : _toggle,
              title: Text(
                t('Таксист түрлерін бөлу'),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                t(
                  'Қосулы болса — таксист тіркелгенде Эконом / Комфорт / '
                  'Бизнес санатын таңдайды, бұрын тіркелгендер көлігінің '
                  'маркасы мен жылы бойынша ережеге сай автомат бөлінеді. '
                  'Өшірулі болса — барлығы бір такси түрі.',
                ),
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
          if (_enabled) ...[
            const SizedBox(height: 12),
            _countsRow(),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    t('Ережелер'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _busy ? null : _reassign,
                  icon: const Icon(Icons.sync_rounded, size: 18),
                  label: Text(t('Барлығын қайта бөлу')),
                ),
              ],
            ),
            Text(
              t(
                'Марканы (міндетті), моделін және ең ерте жылын жазасыз. '
                'Нақтырақ ереже басым: модельді ереже маркалық ережеден, '
                'үлкен жыл кіші жылдан бұрын тексеріледі. Ешқайсысына '
                'сәйкес келмесе — Эконом.',
              ),
              style: TextStyle(color: Gz.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 10),
            if (rules.isEmpty)
              SectionCard(
                child: Text(
                  t('Ереже жоқ — барлық таксист Эконом санатында.'),
                  style: TextStyle(color: Gz.textSecondary),
                ),
              )
            else
              for (final r in rules) _ruleTile(r),
          ],
        ],
      ),
    );
  }

  Widget _countsRow() {
    Widget chip(TaxiClass c) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: c.color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(c.icon, color: c.color, size: 20),
            const SizedBox(height: 2),
            Text(
              '${_count(c.code)}',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 18,
                color: c.color,
              ),
            ),
            Text(c.label, style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
    return Row(
      children: [
        for (final c in TaxiClass.values) ...[
          chip(c),
          if (c != TaxiClass.values.last) const SizedBox(width: 8),
        ],
      ],
    );
  }

  Widget _ruleTile(Map<String, dynamic> r) {
    final cls = TaxiClass.from(r['class'] as String?) ?? TaxiClass.economy;
    final model = (r['model'] as String?) ?? '';
    final year = (r['min_year'] as num?)?.toInt() ?? 0;
    final title = [
      (r['brand'] as String? ?? '').toUpperCase(),
      if (model.isNotEmpty) model,
    ].join(' · ');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Gz.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Gz.border),
      ),
      child: ListTile(
        onTap: _busy ? null : () => _editRule(r),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
        ),
        subtitle: Text(
          year > 0 ? '$year ${t('жылдан бастап')}' : t('Кез келген жыл'),
          style: TextStyle(color: Gz.textSecondary, fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _classChip(cls),
            IconButton(
              tooltip: t('Жою'),
              onPressed: _busy ? null : () => _delete(r),
              icon: Icon(Icons.delete_outline, color: Gz.red, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _classChip(TaxiClass c) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
  decoration: BoxDecoration(
    color: c.color.withValues(alpha: 0.12),
    borderRadius: BorderRadius.circular(20),
  ),
  child: Text(
    c.label,
    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: c.color),
  ),
);

class _RuleDraft {
  final String brand;
  final String model;
  final int minYear;
  final TaxiClass taxiClass;
  const _RuleDraft(this.brand, this.model, this.minYear, this.taxiClass);
}

class _RuleDialog extends StatefulWidget {
  final Map<String, dynamic>? rule;
  const _RuleDialog({this.rule});

  @override
  State<_RuleDialog> createState() => _RuleDialogState();
}

class _RuleDialogState extends State<_RuleDialog> {
  late final _brand = TextEditingController(
    text: widget.rule?['brand'] as String? ?? '',
  );
  late final _model = TextEditingController(
    text: widget.rule?['model'] as String? ?? '',
  );
  late final _year = TextEditingController(
    text: ((widget.rule?['min_year'] as num?)?.toInt() ?? 0) > 0
        ? '${widget.rule!['min_year']}'
        : '',
  );
  late TaxiClass _class =
      TaxiClass.from(widget.rule?['class'] as String?) ?? TaxiClass.comfort;
  String? _error;

  @override
  void dispose() {
    _brand.dispose();
    _model.dispose();
    _year.dispose();
    super.dispose();
  }

  void _submit() {
    final brand = _brand.text.trim();
    if (brand.isEmpty) {
      setState(() => _error = t('Марканы жазыңыз'));
      return;
    }
    final yearText = _year.text.trim();
    final year = yearText.isEmpty ? 0 : int.tryParse(yearText);
    if (year == null || (year != 0 && (year < 1980 || year > 2100))) {
      setState(() => _error = t('Жылын дұрыс жазыңыз'));
      return;
    }
    Navigator.of(
      context,
    ).pop(_RuleDraft(brand, _model.text.trim(), year, _class));
  }

  @override
  Widget build(BuildContext context) {
    return GzDialogFrame(
      icon: Icons.workspace_premium_outlined,
      color: Gz.blue,
      title: widget.rule == null ? t('Жаңа ереже') : t('Ережені өзгерту'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _brand,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: t('Маркасы'),
                hintText: 'Toyota',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _model,
              decoration: InputDecoration(
                labelText: t('Моделі (міндетті емес)'),
                hintText: 'Camry',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _year,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: t('Ең ерте жыл (міндетті емес)'),
                hintText: '2015',
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              children: [
                for (final c in TaxiClass.values)
                  ChoiceChip(
                    label: Text(c.label),
                    selected: _class == c,
                    onSelected: (_) => setState(() => _class = c),
                  ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: TextStyle(color: Gz.red, fontSize: 13)),
            ],
          ],
        ),
      ),
      actions: [
        gzDialogCancel(context, t('Болдырмау')),
        gzDialogPrimary(t('Сақтау'), onPressed: _submit),
      ],
    );
  }
}
