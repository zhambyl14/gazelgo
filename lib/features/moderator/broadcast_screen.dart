import 'package:flutter/material.dart';

import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../core/vehicle_catalog.dart';
import '../../shared/widgets.dart';

/// Модератор: ЖАППАЙ ХАБАРЛАМА (0082) — барлық орындаушыға / клиентке
/// push (мыс. «Ертең Алматыда сұраныс көп», «Жаңа тариф», «Мерекемен!»).
/// Хабар әр адамның «Хабарламалар» тізімінде де сақталады.
class BroadcastScreen extends StatefulWidget {
  const BroadcastScreen({super.key});

  @override
  State<BroadcastScreen> createState() => _BroadcastScreenState();
}

class _BroadcastScreenState extends State<BroadcastScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _city = TextEditingController();
  String _audience = 'executors';
  VehicleType? _vehicle;
  int? _lastSent;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _city.dispose();
    super.dispose();
  }

  String get _audienceText => switch (_audience) {
    'executors' => t('Орындаушылар'),
    'clients' => t('Клиенттер'),
    _ => t('Барлығы'),
  };

  Future<void> _send() async {
    final title = _title.text.trim();
    final body = _body.text.trim();
    if (title.isEmpty || body.isEmpty) {
      showSnack(context, t('Тақырып пен мәтінді жазыңыз'), error: true);
      return;
    }
    final city = _city.text.trim();
    final filters = [
      if (_audience == 'executors' && city.isNotEmpty) city,
      if (_audience == 'executors' && _vehicle != null) _vehicle!.label,
    ];
    final ok = await confirmDialog(
      context,
      title: t('Хабарламаны жіберу керек пе?'),
      message:
          '${t('Кімге')}: $_audienceText'
          '${filters.isEmpty ? '' : ' (${filters.join(', ')})'}\n'
          '${t('Жіберілген хабарды қайтарып алу мүмкін емес.')}',
      confirmLabel: t('Жіберу'),
      icon: Icons.campaign_outlined,
    );
    if (!ok || !mounted) return;
    try {
      final n = await Repo.modBroadcast(
        audience: _audience,
        title: title,
        body: body,
        city: _audience == 'executors' && city.isNotEmpty ? city : null,
        vehicle: _audience == 'executors' ? _vehicle : null,
      );
      if (!mounted) return;
      setState(() => _lastSent = n);
      showSnack(context, '${t('Жіберілді:')} $n ${t('адам')}');
      _title.clear();
      _body.clear();
    } catch (e) {
      if (mounted) showSnack(context, errText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: [
        GzNotice(
          tone: NoticeTone.info,
          icon: Icons.campaign_outlined,
          message: t(
            'Хабар push болып барады және әр адамның «Хабарламалар» '
            'тізімінде сақталады. Сирек әрі пайдалы жіберіңіз — жиі '
            'хабарлама адамдарды мазалайды.',
          ),
        ),
        const SizedBox(height: 14),
        SectionTitle(t('Кімге')),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          children: [
            for (final a in const ['executors', 'clients', 'all'])
              ChoiceChip(
                label: Text(switch (a) {
                  'executors' => t('Орындаушылар'),
                  'clients' => t('Клиенттер'),
                  _ => t('Барлығы'),
                }),
                selected: _audience == a,
                onSelected: (_) => setState(() => _audience = a),
              ),
          ],
        ),
        if (_audience == 'executors') ...[
          const SizedBox(height: 10),
          TextField(
            controller: _city,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: t('Қала (міндетті емес)'),
              prefixIcon: const Icon(Icons.location_city_outlined),
            ),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<VehicleType?>(
            initialValue: _vehicle,
            decoration: InputDecoration(
              labelText: t('Көлік түрі (міндетті емес)'),
              prefixIcon: const Icon(Icons.local_shipping_outlined),
            ),
            items: [
              DropdownMenuItem(value: null, child: Text(t('Барлық көлік'))),
              for (final v in [...kCargoVehicleTypes, ...kTaxiVehicleTypes])
                DropdownMenuItem(value: v, child: Text(v.label)),
            ],
            onChanged: (v) => setState(() => _vehicle = v),
          ),
        ],
        const SizedBox(height: 16),
        SectionTitle(t('Хабарлама')),
        const SizedBox(height: 6),
        TextField(
          controller: _title,
          maxLength: 80,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: t('Тақырып')),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _body,
          maxLength: 300,
          minLines: 3,
          maxLines: 6,
          onChanged: (_) => setState(() {}),
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: t('Мәтін')),
        ),
        if (_title.text.trim().isNotEmpty || _body.text.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(t('Телефонда осылай көрінеді'), style: Gz.caption),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Gz.surface,
              borderRadius: BorderRadius.circular(Gz.rMd),
              boxShadow: Gz.cardShadow,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Push-тағы қосымша белгісі: мөлдір Tasu логотипі
                // (assets/icon/icon.png бандлға кірмейді).
                SizedBox(
                  width: 36,
                  height: 36,
                  child: Image.asset(
                    'assets/icon/tasu_logo.png',
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_title.text.trim(), style: Gz.h3),
                      Text(_body.text.trim(), style: Gz.bodyMuted),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        BusyButton(
          label: t('Жіберу'),
          icon: Icons.send_rounded,
          onPressed: _send,
        ),
        if (_lastSent != null) ...[
          const SizedBox(height: 10),
          GzNotice(
            tone: NoticeTone.success,
            dense: true,
            message:
                '${t('Соңғы хабарлама жіберілді:')} $_lastSent ${t('адам')}',
          ),
        ],
      ],
    );
  }
}
