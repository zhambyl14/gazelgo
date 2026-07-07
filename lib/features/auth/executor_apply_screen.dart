import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';

/// Газелист өтінімі: көлік деректері + құжат фотолары.
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
  late VehicleSize _size = widget.existing?.vehicleSize ?? VehicleSize.small;

  final _idDoc = _PickedDoc();
  final _license = _PickedDoc();
  final _techPassport = _PickedDoc();
  final List<_PickedDoc> _vehiclePhotos = [];

  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _idDoc.existingPath = e.idDocPath;
      _license.existingPath = e.licensePath;
      _techPassport.existingPath = e.techPassportPath;
      for (final p in e.vehiclePhotos) {
        _vehiclePhotos.add(_PickedDoc()..existingPath = p);
      }
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

  Future<void> _addVehiclePhoto() async {
    if (_vehiclePhotos.length >= 4) return;
    final bytes = await _pick();
    if (bytes != null) {
      setState(() => _vehiclePhotos.add(_PickedDoc()..bytes = bytes));
    }
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (!_idDoc.isSet || !_license.isSet || !_techPassport.isSet) {
      showSnack(context, 'Барлық құжат фотосын жүктеңіз', error: true);
      return;
    }
    if (_vehiclePhotos.isEmpty) {
      showSnack(context, 'Көліктің кемінде 1 фотосын қосыңыз', error: true);
      return;
    }
    try {
      Future<String?> up(_PickedDoc d, String name) async {
        if (d.bytes != null) return Repo.uploadDoc('$name.jpg', d.bytes!);
        return d.existingPath;
      }

      final idPath = await up(_idDoc, 'id');
      final licPath = await up(_license, 'license');
      final techPath = await up(_techPassport, 'tech');
      final photos = <String>[];
      for (var i = 0; i < _vehiclePhotos.length; i++) {
        final p = await up(_vehiclePhotos[i], 'vehicle_$i');
        if (p != null) photos.add(p);
      }

      final e = widget.existing;
      final isDocsResponse =
          e != null && e.status == 'approved' && e.docsUpdateRequested;

      if (isDocsResponse) {
        // Тек құжат жаңарту — модератор ревьюіне түседі
        await Repo.submitDocsUpdate(
          idDocPath: idPath,
          licensePath: licPath,
          techPath: techPath,
          photos: photos,
        );
        // ескі, ауысқан құжаттарды өшіру
        final oldPaths = <String>[];
        for (final (oldP, newP) in [
          (e.idDocPath, idPath),
          (e.licensePath, licPath),
          (e.techPassportPath, techPath),
        ]) {
          if (oldP != null && oldP != newP) oldPaths.add(oldP);
        }
        for (final oldPh in e.vehiclePhotos) {
          if (!photos.contains(oldPh)) oldPaths.add(oldPh);
        }
        if (oldPaths.isNotEmpty) {
          try {
            await Repo.c.storage.from('docs').remove(oldPaths);
          } catch (_) {}
        }
      } else {
        await Repo.submitExecutorApplication(
          size: _size,
          brand: _brand.text,
          model: _model.text,
          year: int.tryParse(_year.text),
          plate: _plate.text,
          vehiclePhotos: photos,
          idDocPath: idPath,
          licensePath: licPath,
          techPassportPath: techPath,
          isResubmit: widget.existing != null,
        );
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

  Widget _docTile(String title, _PickedDoc doc) {
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
                Text(
                  doc.isSet ? 'Жүктелді' : 'Фото қажет',
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
              onPressed: Repo.signOut,
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
                          Text('Модератор мынаны жаңартуды сұрады:',
                              style: TextStyle(fontWeight: FontWeight.w800)),
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
                const Text('Көлік туралы',
                    style:
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 10),
                VehicleSizeSelector(
                  value: _size,
                  onChanged: (s) => setState(() => _size = s),
                ),
                const SizedBox(height: 12),
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
                      decoration: const InputDecoration(hintText: 'Жылы'),
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
                const SizedBox(height: 20),
                const Text('Құжаттар',
                    style:
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 10),
                _docTile('Жеке куәлік', _idDoc),
                const SizedBox(height: 8),
                _docTile('Жүргізуші куәлігі', _license),
                const SizedBox(height: 8),
                _docTile('Техпаспорт', _techPassport),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Expanded(
                      child: Text('Көлік фотолары',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 16)),
                    ),
                    TextButton.icon(
                      onPressed: _addVehiclePhoto,
                      icon: const Icon(Icons.add),
                      label: const Text('Қосу'),
                    ),
                  ],
                ),
                if (_vehiclePhotos.isNotEmpty)
                  SizedBox(
                    height: 90,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _vehiclePhotos.length,
                      separatorBuilder: (_, i) => const SizedBox(width: 8),
                      itemBuilder: (_, i) {
                        final d = _vehiclePhotos[i];
                        return Stack(
                          children: [
                            Container(
                              width: 110,
                              height: 90,
                              decoration: BoxDecoration(
                                color: Gz.bg,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: d.bytes != null
                                  ? Image.memory(d.bytes!, fit: BoxFit.cover)
                                  : const Icon(Icons.image,
                                      color: Gz.textSecondary),
                            ),
                            Positioned(
                              top: 2,
                              right: 2,
                              child: GestureDetector(
                                onTap: () => setState(
                                    () => _vehiclePhotos.removeAt(i)),
                                child: const CircleAvatar(
                                  radius: 12,
                                  backgroundColor: Colors.black54,
                                  child: Icon(Icons.close,
                                      size: 14, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 24),
                BusyButton(
                  label: resubmit ? 'Қайта жіберу' : 'Өтінім жіберу',
                  onPressed: _submit,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Өтінімді модератор 24 сағат ішінде қарайды.',
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
