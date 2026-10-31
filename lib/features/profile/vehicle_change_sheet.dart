import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/ui/kz_plate.dart';
import '../../shared/vehicle_picker.dart';
import '../../shared/widgets.dart';

/// Орындаушы көлігінің деректерін (түрі, маркасы, моделі, жылы, түсі,
/// нөмірі) ӨЗІ өзгерте алмайды — осы парақ арқылы модераторға ӨТІНІШ
/// жібереді. Модератор растаған соң ғана профиль жаңарады (0097).
class VehicleChangeSheet extends ConsumerStatefulWidget {
  final ExecutorProfile ep;
  const VehicleChangeSheet({super.key, required this.ep});

  @override
  ConsumerState<VehicleChangeSheet> createState() => _VehicleChangeSheetState();
}

class _VehicleChangeSheetState extends ConsumerState<VehicleChangeSheet> {
  late VehicleType _type = widget.ep.vehicleType;
  late final _brand = TextEditingController(text: widget.ep.vehicleBrand);
  late final _model = TextEditingController(text: widget.ep.vehicleModel);
  late final _year = TextEditingController(
    text: widget.ep.vehicleYear?.toString() ?? '',
  );
  late final _plate = TextEditingController(text: widget.ep.vehiclePlate);
  late final _note = TextEditingController();
  late String? _color = widget.ep.vehicleColor.isEmpty
      ? null
      : widget.ep.vehicleColor;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_brand, _model, _year, _plate, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _send() async {
    final year = int.tryParse(_year.text.trim());
    if (_brand.text.trim().isEmpty ||
        _plate.text.trim().length < 4 ||
        year == null ||
        year < 1980 ||
        year > DateTime.now().year + 1 ||
        _color == null) {
      showSnack(
        context,
        t('Маркасы, жылы, түсі және нөмірін дұрыс толтырыңыз'),
        error: true,
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await Repo.requestVehicleChange(
        type: _type,
        brand: _brand.text,
        model: _model.text,
        year: year,
        color: _color!,
        plate: _plate.text,
        note: _note.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showSnack(context, errText(e), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final taxiOn = ref.watch(taxiEnabledProvider).value ?? false;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t('Көлік деректерін өзгерту'),
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
            const SizedBox(height: 4),
            Text(
              t(
                'Өзгерістер модератор растағаннан кейін ғана күшіне енеді. '
                'Дұрыс емес болса — ескі деректер қалады.',
              ),
              style: TextStyle(color: Gz.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 14),
            Text(
              t('Көлік түрі'),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            VehicleTypeCarousel(
              selected: _type,
              types: taxiOn
                  ? VehicleType.values.withoutUmay()
                  : kCargoVehicleTypes,
              onChanged: (v) => setState(() => _type = v),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _brand,
                    decoration: InputDecoration(labelText: t('Маркасы')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _model,
                    decoration: InputDecoration(labelText: t('Моделі')),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _year,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: t('Көлік шығарылған жыл')),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _plate,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: t('Мемлекеттік нөмір'),
                hintText: '123 ABC 02',
              ),
            ),
            const SizedBox(height: 14),
            Text(
              t('Көлік түсі'),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            CarColorPicker(
              value: _color,
              onChanged: (c) => setState(() => _color = c),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: t('Түсініктеме (міндетті емес)'),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _send,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    )
                  : BtnLabel(t('Өтініш жіберу')),
            ),
          ],
        ),
      ),
    );
  }
}
