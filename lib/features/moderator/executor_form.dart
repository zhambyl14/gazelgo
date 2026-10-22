import 'package:flutter/material.dart';

import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/phone.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import '../auth/executor_apply_screen.dart' show CityPickerSheet;

/// Модератор: орындаушыны қолмен қосу ([ep] == null) не оның деректерін
/// (аты, телефоны, қаласы, көлігі) өзгерту. Сақталса `true` қайтарады.
Future<bool> showExecutorForm(
  BuildContext context, {
  ExecutorProfile? ep,
  Profile? profile,
}) async {
  final ok = await showGzSheet<bool>(
    context,
    builder: (_) => _ExecutorFormSheet(ep: ep, profile: profile),
  );
  return ok == true;
}

class _ExecutorFormSheet extends StatefulWidget {
  final ExecutorProfile? ep;
  final Profile? profile;
  const _ExecutorFormSheet({this.ep, this.profile});

  @override
  State<_ExecutorFormSheet> createState() => _ExecutorFormSheetState();
}

class _ExecutorFormSheetState extends State<_ExecutorFormSheet> {
  late final _name = TextEditingController(text: widget.profile?.fullName);
  late final _phone = TextEditingController(
    text: widget.profile == null ? '' : widget.profile!.phone,
  );
  late final _brand = TextEditingController(text: widget.ep?.vehicleBrand);
  late final _model = TextEditingController(text: widget.ep?.vehicleModel);
  late final _year = TextEditingController(
    text: widget.ep?.vehicleYear?.toString() ?? '',
  );
  late final _plate = TextEditingController(text: widget.ep?.vehiclePlate);
  late String? _city = widget.ep?.city;
  late VehicleType _type = widget.ep?.vehicleType ?? VehicleType.gazelle;
  bool _busy = false;

  bool get _isEdit => widget.ep != null;

  /// Түр тізімі: белсенді түрлер (Ұмайсыз) + қазіргі түр (өшірілген болса да).
  List<VehicleType> get _types {
    final list = VehicleType.values.withoutUmay();
    return list.contains(_type) ? list : [_type, ...list];
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _brand, _model, _year, _plate]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickCity() async {
    final picked = await showGzSheet<String>(
      context,
      builder: (_) => const CityPickerSheet(),
    );
    if (picked != null && mounted) setState(() => _city = picked);
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final phone = Phone.normalize(_phone.text);
    final year = _year.text.trim();
    if (name.length < 2) {
      showSnack(context, t('Аты-жөнін жазыңыз'), error: true);
      return;
    }
    if (phone == null) {
      showSnack(context, t('Телефон нөмірі дұрыс емес.'), error: true);
      return;
    }
    if (_brand.text.trim().isEmpty) {
      showSnack(context, t('Көлік маркасын жазыңыз.'), error: true);
      return;
    }
    if (_plate.text.trim().isEmpty) {
      showSnack(context, t('Мемлекеттік нөмірді жазыңыз.'), error: true);
      return;
    }
    if (year.isNotEmpty && int.tryParse(year) == null) {
      showSnack(context, t('Шыққан жылы дұрыс емес.'), error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await Repo.executorAdmin(_isEdit ? 'update' : 'create', {
        if (_isEdit) 'user_id': widget.ep!.userId,
        'full_name': name,
        'phone': phone,
        'city': _city ?? '',
        'vehicle_type': _type.db,
        'vehicle_brand': _brand.text.trim(),
        'vehicle_model': _model.text.trim(),
        'vehicle_year': year.isEmpty ? null : int.parse(year),
        'vehicle_plate': _plate.text.trim(),
      });
      if (!mounted) return;
      showSnack(
        context,
        _isEdit ? t('Деректер сақталды') : t('Орындаушы қосылды'),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showSnack(
        context,
        e.toString().contains('PHONE_TAKEN')
            ? t('Бұл нөмірмен аккаунт бар. Басқа нөмір жазыңыз.')
            : errText(e),
        error: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      child: GzSheetBody(
        title: _isEdit ? t('Деректерді өзгерту') : t('Жаңа орындаушы'),
        showClose: true,
        child: ListView(
          shrinkWrap: true,
          children: [
            if (!_isEdit) ...[
              GzNotice(
                tone: NoticeTone.info,
                icon: Icons.info_outline_rounded,
                message: t(
                  'Орындаушы бірден расталады. Ол осы нөмірмен Telegram '
                  'арқылы кіреді; құжаттарды кейін жүктей алады.',
                ),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: t('Аты-жөні'),
                prefixIcon: const Icon(Icons.person_outline_rounded),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: t('Телефон'),
                hintText: '+7 7XX XXX XX XX',
                prefixIcon: const Icon(Icons.phone_outlined),
              ),
            ),
            const SizedBox(height: 10),
            InkWell(
              onTap: _pickCity,
              borderRadius: BorderRadius.circular(Gz.radius),
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: t('Қала'),
                  prefixIcon: const Icon(Icons.location_city_outlined),
                  suffixIcon: const Icon(Icons.arrow_drop_down_rounded),
                ),
                child: Text(_city ?? t('Таңдаңыз')),
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<VehicleType>(
              initialValue: _type,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: t('Көлік түрі'),
                prefixIcon: const Icon(Icons.local_shipping_outlined),
              ),
              items: [
                for (final v in _types)
                  DropdownMenuItem(value: v, child: Text(v.label)),
              ],
              onChanged: (v) => setState(() => _type = v ?? _type),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _brand,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: t('Маркасы'),
                prefixIcon: const Icon(Icons.directions_car_outlined),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _model,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(labelText: t('Моделі')),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: _year,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    decoration: InputDecoration(
                      labelText: t('Жылы'),
                      counterText: '',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _plate,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: t('Мемлекеттік нөмір'),
                prefixIcon: const Icon(Icons.pin_outlined),
              ),
            ),
            const SizedBox(height: 16),
            GzPrimaryButton(
              label: _busy
                  ? t('Күте тұрыңыз…')
                  : (_isEdit ? t('Сақтау') : t('Орындаушы қосу')),
              icon: Icons.check_rounded,
              onPressed: _busy ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}
