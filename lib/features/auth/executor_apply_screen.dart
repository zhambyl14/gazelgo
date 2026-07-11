import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/kz_cities.dart';
import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/vehicle_picker.dart';
import '../../shared/widgets.dart';

/// Орындаушы өтінімі: КӨЛІК ТҮРІ (газель, фургон, КамАЗ…), құжаттар
/// (права + селфі, азаматтыққа қарай жеке куәлік/шетел паспорты + селфі,
/// техпаспорт + селфі), көлік деректері (маркасы, моделі, ЖЫЛЫ, гос нөмір)
/// және 4 таңбаланған көлік фотосы. Заказдар көлік түріне қарай бөлінеді.
class ExecutorApplyScreen extends ConsumerStatefulWidget {
  final ExecutorProfile? existing; // қайта жіберу кезінде
  const ExecutorApplyScreen({super.key, this.existing});

  @override
  ConsumerState<ExecutorApplyScreen> createState() =>
      _ExecutorApplyScreenState();
}

class _PickedDoc {
  Uint8List? bytes;
  String? existingPath;
  bool get isSet => bytes != null || existingPath != null;
}

class _ExecutorApplyScreenState extends ConsumerState<ExecutorApplyScreen> {
  final _form = GlobalKey<FormState>();
  late final _brand =
      TextEditingController(text: widget.existing?.vehicleBrand ?? 'ГАЗель');
  late final _model =
      TextEditingController(text: widget.existing?.vehicleModel ?? '');
  late final _year = TextEditingController(
      text: widget.existing?.vehicleYear?.toString() ?? '');
  late final _plate =
      TextEditingController(text: widget.existing?.vehiclePlate ?? '');
  late String? _city = widget.existing?.city;
  late bool _isForeign = widget.existing?.isForeignCitizen ?? false;
  late VehicleType _vehicleType =
      widget.existing?.vehicleType ?? VehicleType.gazelle;

  // Профиль селфиі — тіркелу кезінде түсіріледі, кейін профильде көрсетіледі
  final _selfie = _PickedDoc();

  // Құжаттар
  final _license = _PickedDoc();          // жүргізуші куәлігі (права)
  final _licenseSelfie = _PickedDoc();     // правамен селфи
  final _idDoc = _PickedDoc();             // жеке куәлік (ҚР азаматына)
  final _idSelfie = _PickedDoc();          // куәлікпен селфи
  final _passport = _PickedDoc();          // шетел паспорты (шетел азаматына)
  final _passportSelfie = _PickedDoc();    // паспортпен селфи
  final _techPassport = _PickedDoc();      // көліктің техпаспорты (міндетті)
  final _techPassportSelfie = _PickedDoc(); // техпаспортпен фото (міндетті)

  // Көлік фотолары (4 таңбаланған)
  final _vehFront = _PickedDoc();
  final _vehBack = _PickedDoc();
  final _vehRight = _PickedDoc();
  final _vehLeft = _PickedDoc();

  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    final avatarUrl = ref.read(myProfileProvider).value?.avatarUrl;
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      _selfie.existingPath = avatarUrl;
    }
    final e = widget.existing;
    if (e != null) {
      _license.existingPath = e.licensePath;
      _licenseSelfie.existingPath = e.licenseSelfiePath;
      _idDoc.existingPath = e.idDocPath;
      _idSelfie.existingPath = e.idSelfiePath;
      _passport.existingPath = e.passportPath;
      _passportSelfie.existingPath = e.passportSelfiePath;
      _techPassport.existingPath = e.techPassportPath;
      _techPassportSelfie.existingPath = e.techPassportSelfiePath;
      final ph = e.vehiclePhotos;
      if (ph.isNotEmpty) _vehFront.existingPath = ph[0];
      if (ph.length > 1) _vehBack.existingPath = ph[1];
      if (ph.length > 2) _vehRight.existingPath = ph[2];
      if (ph.length > 3) _vehLeft.existingPath = ph[3];
    }
  }

  @override
  void dispose() {
    _brand.dispose();
    _model.dispose();
    _year.dispose();
    _plate.dispose();
    super.dispose();
  }

  /// Құжат/көлік фотосы ТЕК камерамен түсіріледі (галереядан таңдау жоқ) —
  /// дайын/бөгде суретті жүктеуді қиындататын анти-алаяқтық шарасы. Толық
  /// кепілдік бермейді (кадрды алдын ала басқа жерде түсіріп алуға болады),
  /// бірақ галереядан кез келген файлды таңдауды болдырмайды.
  Future<Uint8List?> _pick() async {
    final file = await _picker.pickImage(
        source: ImageSource.camera, imageQuality: 70, maxWidth: 1600);
    if (file == null) return null;
    return file.readAsBytes();
  }

  Future<void> _pickDoc(_PickedDoc doc) async {
    final bytes = await _pick();
    if (bytes != null) setState(() => doc.bytes = bytes);
  }

  Future<void> _pickCity() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Gz.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const CityPickerSheet(),
    );
    if (picked != null && mounted) setState(() => _city = picked);
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (!_selfie.isSet) {
      showSnack(context, t('Профиліңізге өз селфиіңізді түсіріңіз'),
          error: true);
      return;
    }
    if (_city == null || _city!.trim().isEmpty) {
      showSnack(context, t('Қай қалада жұмыс істейтініңізді таңдаңыз'),
          error: true);
      return;
    }
    if (!_license.isSet || !_licenseSelfie.isSet) {
      showSnack(context, t('Жүргізуші куәлігі мен онымен селфиді жүктеңіз'),
          error: true);
      return;
    }
    if (!_isForeign && (!_idDoc.isSet || !_idSelfie.isSet)) {
      showSnack(context, t('Жеке куәлік пен онымен селфиді жүктеңіз'),
          error: true);
      return;
    }
    if (_isForeign && (!_passport.isSet || !_passportSelfie.isSet)) {
      showSnack(context, t('Шетел паспорты мен онымен селфиді жүктеңіз'),
          error: true);
      return;
    }
    if (!_techPassport.isSet || !_techPassportSelfie.isSet) {
      showSnack(context, t('Көліктің техпаспорты мен онымен фотоны жүктеңіз'),
          error: true);
      return;
    }
    if (!_vehFront.isSet || !_vehBack.isSet || !_vehRight.isSet ||
        !_vehLeft.isSet) {
      showSnack(context, t('Көліктің 4 фотосын да жүктеңіз (алды, арты, оң, сол)'),
          error: true);
      return;
    }
    try {
      Future<String?> up(_PickedDoc d, String name) async {
        if (d.bytes != null) {
          final path = await Repo.uploadDoc('$name.jpg', d.bytes!);
          d.bytes = null; // жүктелген соң жадыны бірден босату
          return path;
        }
        return d.existingPath;
      }

      if (_selfie.bytes != null) {
        await Repo.updateAvatar(_selfie.bytes!);
        _selfie.bytes = null;
      }

      final licPath = await up(_license, 'license');
      final licSelfie = await up(_licenseSelfie, 'license_selfie');
      final idPath = !_isForeign ? await up(_idDoc, 'id') : null;
      final idSelfie = !_isForeign ? await up(_idSelfie, 'id_selfie') : null;
      final passportPath = _isForeign ? await up(_passport, 'passport') : null;
      final passportSelfie =
          _isForeign ? await up(_passportSelfie, 'passport_selfie') : null;
      final techPath = await up(_techPassport, 'tech_passport');
      final techSelfie = await up(_techPassportSelfie, 'tech_passport_selfie');
      final photos = <String>[];
      for (final (d, n) in [
        (_vehFront, 'veh_front'),
        (_vehBack, 'veh_back'),
        (_vehRight, 'veh_right'),
        (_vehLeft, 'veh_left'),
      ]) {
        final p = await up(d, n);
        if (p != null) photos.add(p);
      }

      final e = widget.existing;
      final isDocsResponse =
          e != null && e.status == 'approved' && e.docsUpdateRequested;

      if (isDocsResponse) {
        await Repo.submitDocsUpdate(
          idDocPath: idPath,
          licensePath: licPath,
          idSelfiePath: idSelfie,
          licenseSelfiePath: licSelfie,
          passportPath: passportPath,
          passportSelfiePath: passportSelfie,
          techPassportPath: techPath,
          techPassportSelfiePath: techSelfie,
          photos: photos,
        );
      } else {
        await Repo.submitExecutorApplication(
          vehicleType: _vehicleType,
          brand: _brand.text,
          model: _model.text,
          year: int.tryParse(_year.text),
          plate: _plate.text,
          vehiclePhotos: photos,
          idDocPath: idPath,
          licensePath: licPath,
          idSelfiePath: idSelfie,
          licenseSelfiePath: licSelfie,
          passportPath: passportPath,
          passportSelfiePath: passportSelfie,
          techPassportPath: techPath,
          techPassportSelfiePath: techSelfie,
          isForeignCitizen: _isForeign,
          city: _city,
          isResubmit: widget.existing != null,
        );
      }
      if (_city != null && _city!.trim().isNotEmpty) {
        try {
          await Repo.setExecutorCity(_city!.trim());
        } catch (_) {}
      }
      ref.invalidate(myExecutorProfileProvider);
      ref.invalidate(myProfileProvider);
      if (mounted) {
        showSnack(context,
            isDocsResponse ? t('Жіберілді — модератор тексереді') : t('Жіберілді'));
        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) showSnack(context, errText(e), error: true);
    }
  }

  Widget _docTile(String title, _PickedDoc doc, {String? hint}) {
    return SectionCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Gz.bg,
              borderRadius: BorderRadius.circular(12),
            ),
            clipBehavior: Clip.antiAlias,
            child: doc.bytes != null
                ? Image.memory(doc.bytes!,
                    fit: BoxFit.cover,
                    cacheWidth:
                        (56 * MediaQuery.devicePixelRatioOf(context)).round(),
                    cacheHeight:
                        (56 * MediaQuery.devicePixelRatioOf(context)).round())
                : Icon(
                    doc.existingPath != null
                        ? Icons.check_circle
                        : Icons.add_a_photo_outlined,
                    color: doc.existingPath != null
                        ? Gz.green
                        : Gz.textSecondary,
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t(title),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14)),
                if (hint != null)
                  Text(t(hint),
                      style: const TextStyle(
                          fontSize: 11.5, color: Gz.textSecondary)),
                Text(
                  doc.isSet ? t('Жүктелді ✓') : t('Фото қажет'),
                  style: TextStyle(
                      fontSize: 12,
                      color: doc.isSet ? Gz.green : Gz.textSecondary),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _pickDoc(doc),
            child: Text(doc.isSet ? t('Ауыстыру') : t('Жүктеу')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final resubmit = widget.existing != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(resubmit
            ? t('Өтінімді қайта жіберу')
            : t('Тапсырыс орындаушы өтінімі')),
        actions: [
          if (!resubmit)
            IconButton(
              tooltip: t('Шығу'),
              onPressed: () => confirmSignOut(context),
              icon: const Icon(Icons.logout),
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.existing?.docsUpdateRequested == true) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF0F0),
                      borderRadius: BorderRadius.circular(Gz.radius),
                      border: Border.all(color: Gz.red.withValues(alpha: 0.35)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const Icon(Icons.assignment_late, color: Gz.red, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(t('Модератор мынаны жаңартуды сұрады:'),
                                style: const TextStyle(fontWeight: FontWeight.w800)),
                          ),
                        ]),
                        const SizedBox(height: 6),
                        ...widget.existing!.docsUpdateFields.map((f) => Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                  '•  ${ExecutorProfile.docFieldLabel(f)}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                            )),
                        if (widget.existing!.docsUpdateComment?.isNotEmpty ==
                            true) ...[
                          const SizedBox(height: 6),
                          Text('«${widget.existing!.docsUpdateComment}»',
                              style: const TextStyle(
                                  color: Gz.textSecondary,
                                  fontStyle: FontStyle.italic,
                                  fontSize: 13)),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                Text(t('Қай қалада жұмыс істейсіз?'),
                    style: const
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 6),
                Text(
                  t('Заказдарды тек осы қаладан (қала ішінде + осы қаладан '
                  'шығатын межгород) көресіз.'),
                  style: const TextStyle(color: Gz.textSecondary, fontSize: 12.5),
                ),
                const SizedBox(height: 10),
                InkWell(
                  onTap: _pickCity,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      color: Gz.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: _city == null ? Gz.border : Gz.green,
                          width: _city == null ? 1.2 : 1.6),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.location_city_outlined,
                            color: _city == null ? Gz.textSecondary : Gz.green),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _city ?? t('Қаланы таңдаңыз'),
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                                color:
                                    _city == null ? Gz.textSecondary : Gz.ink),
                          ),
                        ),
                        const Icon(Icons.chevron_right,
                            color: Gz.textSecondary),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(t('Профиль суретіңіз'),
                    style: const
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 6),
                Text(
                  t('Бетіңіз анық көрінетін селфи түсіріңіз — бұл сурет '
                      'профиліңізде көрсетіледі.'),
                  style: const TextStyle(color: Gz.textSecondary, fontSize: 12.5),
                ),
                const SizedBox(height: 10),
                _docTile(t('Профиль селфиі'), _selfie,
                    hint: t('Камерамен өз бетіңізді түсіріңіз')),
                const SizedBox(height: 20),
                Text(t('Көлік түрі'),
                    style: const
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 6),
                Text(
                  t('Тек осы түрге берілген заказдарды көресіз — дұрыс таңдаңыз.'),
                  style: const TextStyle(color: Gz.textSecondary, fontSize: 12.5),
                ),
                const SizedBox(height: 10),
                VehicleTypeCarousel(
                  selected: _vehicleType,
                  onChanged: (v) => setState(() => _vehicleType = v),
                ),
                const SizedBox(height: 20),
                Text(t('Көлік туралы'),
                    style: const
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _brand,
                      decoration: InputDecoration(labelText: t('Маркасы')),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? t('Қажет') : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _model,
                      decoration: InputDecoration(labelText: t('Моделі')),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _year,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                      labelText: t('Көлік шығарылған жыл'),
                      hintText: t('Мысалы: 2015')),
                  validator: (v) {
                    final y = int.tryParse(v?.trim() ?? '');
                    if (y == null || y < 1980 || y > DateTime.now().year + 1) {
                      return t('Жылын дұрыс жазыңыз');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _plate,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                      labelText: t('Мемлекеттік нөмір'),
                      hintText: '123 ABC 02'),
                  validator: (v) => (v == null || v.trim().length < 4)
                      ? t('Мемлекеттік нөмір қажет')
                      : null,
                ),
                const SizedBox(height: 20),
                Text(t('Құжаттар'),
                    style: const
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 10),
                _docTile(t('Жүргізуші куәлігі (права)'), _license),
                const SizedBox(height: 8),
                _docTile(t('Правамен селфи'), _licenseSelfie,
                    hint: t('Правені қолыңызға ұстап, бетіңіз көрінетін селфи')),
                const SizedBox(height: 16),
                Text(t('Азаматтық'),
                    style: const
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: Text(t('ҚР азаматымын')),
                        selected: !_isForeign,
                        showCheckmark: false,
                        selectedColor: Gz.yellow,
                        labelStyle: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: !_isForeign ? Gz.ink : Gz.textSecondary,
                        ),
                        onSelected: (_) => setState(() => _isForeign = false),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ChoiceChip(
                        label: Text(t('Басқа ел азаматымын')),
                        selected: _isForeign,
                        showCheckmark: false,
                        selectedColor: Gz.yellow,
                        labelStyle: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: _isForeign ? Gz.ink : Gz.textSecondary,
                        ),
                        onSelected: (_) => setState(() => _isForeign = true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (!_isForeign) ...[
                  _docTile(t('Жеке куәлік (удостоверение)'), _idDoc),
                  const SizedBox(height: 8),
                  _docTile(t('Куәлікпен селфи'), _idSelfie,
                      hint: t('Куәлікті қолыңызға ұстап, бетіңіз көрінетін селфи')),
                ] else ...[
                  _docTile(t('Шетел паспорты'), _passport),
                  const SizedBox(height: 8),
                  _docTile(t('Паспортпен селфи'), _passportSelfie,
                      hint: t('Паспортты қолыңызға ұстап, бетіңіз көрінетін селфи')),
                ],
                const SizedBox(height: 8),
                _docTile(t('Көліктің техпаспорты'), _techPassport,
                    hint: t('Көлік құжаты (СРТС) — азаматтыққа қарамай қажет')),
                const SizedBox(height: 8),
                _docTile(t('Техпаспортпен фото'), _techPassportSelfie,
                    hint: t('Техпаспортты қолыңызға ұстап түсіріңіз')),
                const SizedBox(height: 20),
                Text(t('Көлік фотолары'),
                    style: const
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 4),
                Text(
                  t('Нақ көрсетілген жақтарды түсіріңіз — шатаспаңыз.'),
                  style: const TextStyle(color: Gz.textSecondary, fontSize: 12.5),
                ),
                const SizedBox(height: 10),
                _docTile(t('Алдынан (гос нөмір көрінсін)'), _vehFront,
                    hint: t('Көліктің алды, нөмірі анық көрінуі керек')),
                const SizedBox(height: 8),
                _docTile(t('Артынан (гос нөмір көрінсін)'), _vehBack,
                    hint: t('Көліктің арты, нөмірі анық көрінуі керек')),
                const SizedBox(height: 8),
                _docTile(t('Оң жағынан'), _vehRight,
                    hint: t('Көлікке қарап тұрсаңыз — оң бүйірі')),
                const SizedBox(height: 8),
                _docTile(t('Сол жағынан'), _vehLeft,
                    hint: t('Көлікке қарап тұрсаңыз — сол бүйірі')),
                const SizedBox(height: 24),
                BusyButton(
                  label: resubmit ? t('Қайта жіберу') : t('Өтінім жіберу'),
                  onPressed: _submit,
                ),
                const SizedBox(height: 8),
                Text(
                  t('Өтінімді модератор 24 сағат ішінде қарайды.\n'
                      'Өтінім жіберу арқылы 18 жасқа толғаныңызды және құжат '
                      'деректерінің модерация мақсатында өңделуіне келісіміңізді '
                      'растайсыз.'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Gz.textSecondary, fontSize: 12.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Қала таңдау парағы (Қазақстан қалалары тізімінен, іздеумен).
/// Өтінім бергенде де, орындаушы кейін қаласын ауыстырғанда да қолданылады.
class CityPickerSheet extends StatefulWidget {
  const CityPickerSheet({super.key});

  @override
  State<CityPickerSheet> createState() => _CityPickerSheetState();
}

class _CityPickerSheetState extends State<CityPickerSheet> {
  final _search = TextEditingController();
  List<String> _filtered = kzCities;

  void _onChanged(String q) {
    final n = q.trim().toLowerCase();
    setState(() {
      _filtered = n.isEmpty
          ? kzCities
          : kzCities.where((c) => c.toLowerCase().contains(n)).toList();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.92,
      builder: (context, scroll) => Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: Gz.border, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _search,
              autofocus: true,
              onChanged: _onChanged,
              decoration: InputDecoration(
                hintText: t('Қала немесе елді мекен іздеу…'),
                prefixIcon: const Icon(Icons.search),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _filtered.isEmpty
                ? Center(
                    child: Text(t('Табылмады'),
                        style: const TextStyle(color: Gz.textSecondary)))
                : ListView.separated(
                    controller: scroll,
                    itemCount: _filtered.length,
                    separatorBuilder: (_, i) => const Divider(height: 1),
                    itemBuilder: (_, i) => ListTile(
                      leading: const Icon(Icons.location_city_outlined,
                          color: Gz.textSecondary),
                      title: Text(_filtered[i]),
                      onTap: () => Navigator.of(context).pop(_filtered[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
