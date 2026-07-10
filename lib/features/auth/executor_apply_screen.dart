import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/kz_cities.dart';
import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';

/// Газелист өтінімі: құжаттар (права + селфі, куәлік + селфі, шетел паспорты),
/// көлік деректері (маркасы, моделі, ЖЫЛЫ, гос нөмір) және 4 таңбаланған
/// көлік фотосы. Газель ӨЛШЕМІ сұралмайды.
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

  // Құжаттар
  final _license = _PickedDoc();          // жүргізуші куәлігі (права)
  final _licenseSelfie = _PickedDoc();     // правамен селфи
  final _idDoc = _PickedDoc();             // жеке куәлік (удостоверение)
  final _idSelfie = _PickedDoc();          // куәлікпен селфи
  final _passport = _PickedDoc();          // шетел паспорты (міндетті емес)
  final _passportSelfie = _PickedDoc();    // паспортпен селфи (міндетті емес)

  // Көлік фотолары (4 таңбаланған)
  final _vehFront = _PickedDoc();
  final _vehBack = _PickedDoc();
  final _vehRight = _PickedDoc();
  final _vehLeft = _PickedDoc();

  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _license.existingPath = e.licensePath;
      _licenseSelfie.existingPath = e.licenseSelfiePath;
      _idDoc.existingPath = e.idDocPath;
      _idSelfie.existingPath = e.idSelfiePath;
      _passport.existingPath = e.passportPath;
      _passportSelfie.existingPath = e.passportSelfiePath;
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

  Future<Uint8List?> _pick() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Камерамен түсіру'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Галереядан таңдау'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return null;
    final file = await _picker.pickImage(
        source: source, imageQuality: 70, maxWidth: 1600);
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
      builder: (_) => const _ApplyCityPicker(),
    );
    if (picked != null && mounted) setState(() => _city = picked);
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (_city == null || _city!.trim().isEmpty) {
      showSnack(context, 'Қай қалада жұмыс істейтініңізді таңдаңыз',
          error: true);
      return;
    }
    if (!_license.isSet || !_licenseSelfie.isSet || !_idDoc.isSet ||
        !_idSelfie.isSet) {
      showSnack(context, 'Права, куәлік және селфилерді толық жүктеңіз',
          error: true);
      return;
    }
    if (_passport.isSet && !_passportSelfie.isSet) {
      showSnack(context, 'Шетел паспортымен селфиді де жүктеңіз', error: true);
      return;
    }
    if (!_vehFront.isSet || !_vehBack.isSet || !_vehRight.isSet ||
        !_vehLeft.isSet) {
      showSnack(context, 'Көліктің 4 фотосын да жүктеңіз (алды, арты, оң, сол)',
          error: true);
      return;
    }
    try {
      Future<String?> up(_PickedDoc d, String name) async {
        if (d.bytes != null) return Repo.uploadDoc('$name.jpg', d.bytes!);
        return d.existingPath;
      }

      final licPath = await up(_license, 'license');
      final licSelfie = await up(_licenseSelfie, 'license_selfie');
      final idPath = await up(_idDoc, 'id');
      final idSelfie = await up(_idSelfie, 'id_selfie');
      final passportPath = _passport.isSet ? await up(_passport, 'passport') : null;
      final passportSelfie =
          _passportSelfie.isSet ? await up(_passportSelfie, 'passport_selfie') : null;
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
          photos: photos,
        );
      } else {
        await Repo.submitExecutorApplication(
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
      if (mounted) {
        showSnack(context,
            isDocsResponse ? 'Жіберілді — модератор тексереді' : 'Жіберілді');
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
                ? Image.memory(doc.bytes!, fit: BoxFit.cover)
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
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14)),
                if (hint != null)
                  Text(hint,
                      style: const TextStyle(
                          fontSize: 11.5, color: Gz.textSecondary)),
                Text(
                  doc.isSet ? 'Жүктелді ✓' : 'Фото қажет',
                  style: TextStyle(
                      fontSize: 12,
                      color: doc.isSet ? Gz.green : Gz.textSecondary),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _pickDoc(doc),
            child: Text(doc.isSet ? 'Ауыстыру' : 'Жүктеу'),
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
        title: Text(resubmit ? 'Өтінімді қайта жіберу' : 'Газелист өтінімі'),
        actions: [
          if (!resubmit)
            IconButton(
              tooltip: 'Шығу',
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
                        const Row(children: [
                          Icon(Icons.assignment_late, color: Gz.red, size: 20),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text('Модератор мынаны жаңартуды сұрады:',
                                style: TextStyle(fontWeight: FontWeight.w800)),
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
                const Text('Қай қалада жұмыс істейсіз?',
                    style:
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 6),
                const Text(
                  'Заказдарды тек осы қаладан (қала ішінде + осы қаладан '
                  'шығатын межгород) көресіз.',
                  style: TextStyle(color: Gz.textSecondary, fontSize: 12.5),
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
                            _city ?? 'Қаланы таңдаңыз',
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
                const Text('Көлік туралы',
                    style:
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _brand,
                      decoration: const InputDecoration(hintText: 'Маркасы'),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Қажет' : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _model,
                      decoration: const InputDecoration(hintText: 'Моделі'),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _year,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(hintText: 'Шығарылған жылы'),
                      validator: (v) {
                        final y = int.tryParse(v?.trim() ?? '');
                        if (y == null || y < 1980 || y > DateTime.now().year + 1) {
                          return 'Жылын дұрыс жазыңыз';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _plate,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                          hintText: 'Мемнөмір (123 ABC 02)'),
                      validator: (v) => (v == null || v.trim().length < 4)
                          ? 'Мемнөмір қажет'
                          : null,
                    ),
                  ),
                ]),
                const SizedBox(height: 6),
                const Text(
                  'Көлік жылы маңызды: VIP тарифті тек жаңарақ көлікке қосуға болады.',
                  style: TextStyle(color: Gz.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 20),
                const Text('Құжаттар',
                    style:
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 10),
                _docTile('Жүргізуші куәлігі (права)', _license),
                const SizedBox(height: 8),
                _docTile('Правамен селфи', _licenseSelfie,
                    hint: 'Правені қолыңызға ұстап, бетіңіз көрінетін селфи'),
                const SizedBox(height: 8),
                _docTile('Жеке куәлік (удостоверение)', _idDoc),
                const SizedBox(height: 8),
                _docTile('Куәлікпен селфи', _idSelfie,
                    hint: 'Куәлікті ұстап тұрған селфи'),
                const SizedBox(height: 8),
                _docTile('Шетел паспорты', _passport,
                    hint: 'ҚР азаматы болмасаңыз ғана'),
                const SizedBox(height: 8),
                _docTile('Паспортпен селфи', _passportSelfie,
                    hint: 'Шетел паспортын жүктесеңіз ғана'),
                const SizedBox(height: 20),
                const Text('Көлік фотолары',
                    style:
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 4),
                const Text(
                  'Нақ көрсетілген жақтарды түсіріңіз — шатаспаңыз.',
                  style: TextStyle(color: Gz.textSecondary, fontSize: 12.5),
                ),
                const SizedBox(height: 10),
                _docTile('Алдынан (гос нөмір көрінсін)', _vehFront,
                    hint: 'Көліктің алды, нөмірі анық көрінуі керек'),
                const SizedBox(height: 8),
                _docTile('Артынан (гос нөмір көрінсін)', _vehBack,
                    hint: 'Көліктің арты, нөмірі анық көрінуі керек'),
                const SizedBox(height: 8),
                _docTile('Оң жағынан', _vehRight,
                    hint: 'Көлікке қарап тұрсаңыз — оң бүйірі'),
                const SizedBox(height: 8),
                _docTile('Сол жағынан', _vehLeft,
                    hint: 'Көлікке қарап тұрсаңыз — сол бүйірі'),
                const SizedBox(height: 24),
                BusyButton(
                  label: resubmit ? 'Қайта жіберу' : 'Өтінім жіберу',
                  onPressed: _submit,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Өтінімді модератор 24 сағат ішінде қарайды.\n'
                  'Өтінім жіберу арқылы 18 жасқа толғаныңызды және құжат '
                  'деректерінің модерация мақсатында өңделуіне келісіміңізді '
                  'растайсыз.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Gz.textSecondary, fontSize: 12.5),
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
class _ApplyCityPicker extends StatefulWidget {
  const _ApplyCityPicker();

  @override
  State<_ApplyCityPicker> createState() => _ApplyCityPickerState();
}

class _ApplyCityPickerState extends State<_ApplyCityPicker> {
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
              decoration: const InputDecoration(
                hintText: 'Қала немесе елді мекен іздеу…',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _filtered.isEmpty
                ? const Center(
                    child: Text('Табылмады',
                        style: TextStyle(color: Gz.textSecondary)))
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
