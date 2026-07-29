import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/vehicle_picker.dart';
import '../../shared/widgets.dart';
import '../auth/executor_apply_screen.dart' show CityPickerSheet;

/// Хабарландыру беру экраны.
///
/// Түрі СҰРАЛМАЙДЫ — рөлден шығады, сол себепті шатасу жоқ:
///   клиент   → ЖҰМЫС жариялайды («Маған КамАЗ керек…»)
///   орындаушы → ҚЫЗМЕТ жариялайды («КамАЗым бар, топырақ тасимын…»)
///
/// [repost] берілсе — архивтегі хабарландыру қайта жарияланады: мәтіні
/// алдын ала толтырылып тұрады, бірақ СУРЕТТЕР қайта салынуы керек (мерзімі
/// біткенде олар біздің базадан өшірілген).
class CreateListingScreen extends ConsumerStatefulWidget {
  final Listing? repost;
  const CreateListingScreen({super.key, this.repost});

  @override
  ConsumerState<CreateListingScreen> createState() =>
      _CreateListingScreenState();
}

class _CreateListingScreenState extends ConsumerState<CreateListingScreen> {
  final _body = TextEditingController();
  final _price = TextEditingController();
  final _picker = ImagePicker();

  VehicleType _vehicle = VehicleType.gazelle;
  String? _city;
  bool _longTerm = false;
  int _days = 3;
  final List<Uint8List> _photos = [];

  bool get _isRepost => widget.repost != null;

  @override
  void initState() {
    super.initState();
    final r = widget.repost;
    if (r != null) {
      _body.text = r.body;
      _price.text = r.priceText;
      _vehicle = r.vehicleType;
      _city = r.city;
      _longTerm = r.durationDays > 0;
      _days = r.durationDays > 0 ? r.durationDays : 3;
    }
  }

  @override
  void dispose() {
    _body.dispose();
    _price.dispose();
    super.dispose();
  }

  /// Клиент жұмыс жариялайды, орындаушы — қызмет.
  bool _isExecutor(WidgetRef ref) =>
      (ref.read(myProfileProvider).value?.role ?? 'client') == 'executor';

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

  Future<void> _addPhoto() async {
    if (_photos.length >= kListingMaxPhotos) {
      showSnack(
        context,
        '${t('Ең көбі')} $kListingMaxPhotos ${t('фото')}',
        error: true,
      );
      return;
    }
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: Text(t('Камерамен түсіру')),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: Text(t('Галереядан таңдау')),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final f = await _picker.pickImage(
      source: source,
      imageQuality: 65,
      maxWidth: 1400,
    );
    if (f == null) return;
    final bytes = await f.readAsBytes();
    if (mounted) setState(() => _photos.add(bytes));
  }

  /// Жариялауға дайын емес болса — НЕ жетпейтіні (батырманың астында бір
  /// қатармен), дайын болса null. `_submit` ішіндегі тексерулер орнында
  /// қалады — олар сервер қатесін де ұстайды.
  String? get _missing {
    if (_city == null || _city!.isEmpty) return t('Қаланы таңдаңыз');
    if (_body.text.trim().length < 10) {
      return t('Сипаттаманы толығырақ жазыңыз (кемінде 10 таңба)');
    }
    return null;
  }

  Future<void> _submit() async {
    final city = _city;
    if (city == null || city.isEmpty) {
      showSnack(context, t('Қаланы таңдаңыз'), error: true);
      return;
    }
    final body = _body.text.trim();
    if (body.length < 10) {
      showSnack(
        context,
        t('Сипаттаманы толығырақ жазыңыз (кемінде 10 таңба)'),
        error: true,
      );
      return;
    }
    final isExecutor = _isExecutor(ref);
    // Расталмаған орындаушыға сервер NOT_APPROVED береді — суреттерді бекер
    // жүктеп қоймас үшін оны АЛДЫН АЛА тексереміз.
    if (isExecutor) {
      final ep = ref.read(myExecutorProfileProvider).value;
      if (ep == null || ep.status != 'approved') {
        showSnack(
          context,
          t('Қызмет жариялау үшін алдымен аккаунтыңыз модерациядан өтуі керек.'),
          error: true,
        );
        return;
      }
    }
    try {
      // Суреттерді алдымен Storage-ке жүктейміз (заказ фотоларындағыдай).
      final paths = <String>[];
      for (var i = 0; i < _photos.length; i++) {
        paths.add(await Repo.uploadListingPhoto(_photos[i], i));
      }
      final duration = (!isExecutor && _longTerm) ? _days : 0;
      final r = widget.repost;
      if (r != null) {
        await Repo.repostListing(
          id: r.id,
          photos: paths,
          body: body,
          priceText: _price.text.trim(),
          vehicleType: _vehicle,
          city: city,
          durationDays: duration,
        );
      } else {
        await Repo.createListing(
          vehicleType: _vehicle,
          city: city,
          body: body,
          priceText: _price.text.trim(),
          durationDays: duration,
        photos: paths,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
      showSnack(
        context,
        '${t('Хабарландыру жарияланды')} · $kListingDays ${t('күн лентада тұрады')}',
      );
    } catch (e) {
      if (mounted) showSnack(context, errText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isExecutor = (ref.watch(myProfileProvider).value?.role ?? 'client') ==
        'executor';
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isRepost
              ? t('Қайта жариялау')
              : (isExecutor ? t('Қызмет жариялау') : t('Жұмыс жариялау')),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            // Не жарияланатынын БІРДЕН түсіндіретін карточка — қолданушы
            // «түрін» таңдамайды, бәрі рөлден шығады.
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Gz.yellow.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Gz.yellow),
              ),
              child: Row(
                children: [
                  Icon(
                    isExecutor ? Icons.local_shipping : Icons.campaign,
                    color: Gz.ink,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isExecutor
                              ? t('Сіз қызметіңізді жариялайсыз')
                              : t('Сіз жұмысыңызды жариялайсыз'),
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 14.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isExecutor
                              ? t('Оны клиенттер «Қызметтер» бөлімінен көреді '
                                  'де, өздері хабарласады.')
                              : t('Оны орындаушылар «Жұмыстар» бөлімінен көреді '
                                  'де, өздері хабарласады.'),
                          style: const TextStyle(
                            fontSize: 12.5,
                            height: 1.35,
                            color: Gz.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            _label(t('Көлік түрі')),
            const SizedBox(height: 8),
            // «Такси» түрі модератор сол бөлімді қосқанда ғана тізімде
            // болады (0046) — әйтпесе таксист/клиент такси хабарландыруын
            // жариялап, оны ешкім көрмей қалатын.
            VehicleTypeCarousel(
              selected: _vehicle,
              types: (ref.watch(taxiEnabledProvider).value ?? false)
                  ? VehicleType.values
                  : kCargoVehicleTypes,
              onChanged: (v) => setState(() => _vehicle = v),
            ),
            const SizedBox(height: 18),

            _label(t('Қала')),
            const SizedBox(height: 8),
            InkWell(
              onTap: _pickCity,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 15,
                ),
                decoration: BoxDecoration(
                  color: Gz.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _city == null ? Gz.border : Gz.ink,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.location_city_outlined,
                      size: 20,
                      color: Gz.green,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _city ?? t('Қаланы таңдаңыз'),
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: _city == null
                              ? FontWeight.w500
                              : FontWeight.w700,
                          color: _city == null ? Gz.textSecondary : Gz.ink,
                        ),
                      ),
                    ),
                    const Icon(Icons.expand_more, color: Gz.textSecondary),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),

            _label(t('Сипаттама')),
            const SizedBox(height: 4),
            Text(
              isExecutor
                  ? t('мыс: КамАЗым бар, топырақ пен қиыршық тас тасимын. '
                      'Қала ішінде және маңайға шығамын.')
                  : t('мыс: Құрылыс алаңына 10 күн бойы құм тасу керек. '
                      'Ұзақ мерзімге фура іздеймін.'),
              style: const TextStyle(color: Gz.textSecondary, fontSize: 12.5),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _body,
              maxLines: 5,
              maxLength: 600,
              textCapitalization: TextCapitalization.sentences,
              // «Жариялау» батырмасының сары/сұр күйі осы өріске байланысты.
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: t('Не ұсынасыз / не керек — қысқаша жазыңыз'),
              ),
            ),
            const SizedBox(height: 6),

            _label(t('Баға')),
            const SizedBox(height: 4),
            Text(
              t('Бос қалдырсаңыз — «Келісім бойынша» деп көрсетіледі.'),
              style: const TextStyle(color: Gz.textSecondary, fontSize: 12.5),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _price,
              maxLength: 60,
              decoration: InputDecoration(
                hintText: t('мыс: 15 000 ₸ немесе 12 000 ₸/сағат'),
                prefixIcon: const Icon(Icons.payments_outlined),
                counterText: '',
              ),
            ),
            const SizedBox(height: 16),

            // Ұзақ мерзімді жұмыс — тек КЛИЕНТКЕ (орындаушының қызметінде
            // «неше күн» деген мағына жоқ).
            if (!isExecutor) ...[
              Container(
                padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
                decoration: BoxDecoration(
                  color: Gz.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Gz.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t('Ұзақ мерзімді жұмыс'),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            t('мыс: «10 күнге фура керек»'),
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: Gz.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _longTerm,
                      activeThumbColor: Gz.green,
                      onChanged: (v) => setState(() => _longTerm = v),
                    ),
                  ],
                ),
              ),
              if (_longTerm) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: Gz.bg,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _stepBtn(
                        Icons.remove,
                        () => setState(() => _days = (_days - 1).clamp(1, 90)),
                      ),
                      SizedBox(
                        width: 110,
                        child: Text(
                          '$_days ${t('күн')}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      _stepBtn(
                        Icons.add,
                        () => setState(() => _days = (_days + 1).clamp(1, 90)),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
            ],

            Row(
              children: [
                Expanded(
                  child: _label(
                    '${t('Сурет')} · ${_photos.length}/$kListingMaxPhotos',
                  ),
                ),
                TextButton.icon(
                  onPressed: _addPhoto,
                  icon: const Icon(Icons.add_a_photo, size: 18),
                  label: Text(t('Қосу')),
                ),
              ],
            ),
            Text(
              '${t('Суреттер')} $kListingDays ${t('күн сақталады, содан кейін '
                  'автоматты өшіріледі.')}',
              style: const TextStyle(color: Gz.textSecondary, fontSize: 12),
            ),
            if (_isRepost) ...[
              const SizedBox(height: 6),
              Text(
                t('Мерзімі біткенде ескі суреттер өшірілген — қайта салыңыз.'),
                style: const TextStyle(
                  color: Gz.red,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (_photos.isNotEmpty) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 88,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _photos.length,
                  separatorBuilder: (_, i) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final px =
                        (88 * MediaQuery.devicePixelRatioOf(context)).round();
                    return Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.memory(
                            _photos[i],
                            width: 88,
                            height: 88,
                            fit: BoxFit.cover,
                            cacheWidth: px,
                            cacheHeight: px,
                          ),
                        ),
                        Positioned(
                          top: 2,
                          right: 2,
                          child: GestureDetector(
                            onTap: () => setState(() => _photos.removeAt(i)),
                            child: const CircleAvatar(
                              radius: 11,
                              backgroundColor: Colors.black54,
                              child: Icon(
                                Icons.close,
                                size: 13,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 22),

            // Қала таңдалмай / сипаттама жазылмай тұрып батырма СҰР күйде
            // (қосымшадағы ортақ ереже), астында не жетпейтіні тұрады.
            BusyButton(
              label: _isRepost ? t('Қайта жариялау') : t('Жариялау'),
              enabled: _missing == null,
              onPressed: _submit,
            ),
            const SizedBox(height: 10),
            Text(
              _missing ??
                  '${t('Хабарландыру')} $kListingDays ${t('күн лентада '
                      'тұрады, сосын архивке кетеді — кейін қайта жариялай '
                      'аласыз.')}',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _missing == null ? Gz.textSecondary : Gz.red,
                fontWeight:
                    _missing == null ? FontWeight.w400 : FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String s) => Text(
    s,
    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
  );

  Widget _stepBtn(IconData icon, VoidCallback onTap) => InkWell(
    customBorder: const CircleBorder(),
    onTap: onTap,
    child: Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Gz.surface,
        shape: BoxShape.circle,
        border: Border.all(color: Gz.border, width: 1.4),
      ),
      child: Icon(icon, size: 20, color: Gz.ink),
    ),
  );
}
