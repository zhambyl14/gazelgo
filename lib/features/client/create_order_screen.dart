import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/geo.dart';
import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/map_widgets.dart';
import '../../shared/vehicle_picker.dart';
import '../../shared/widgets.dart';
import '../auth/login_screen.dart';
import '../legal/legal_screen.dart';
import 'address_picker.dart';
import 'city_street_sheet.dart';
import 'draft_order.dart';
import 'order_detail_screen.dart';

/// Заказ құру: жүк детальдары, көлік түрі, баға.
/// Адрестерді осы экранда өзгертуге болады — опциялар жоғалмайды.
class CreateOrderScreen extends ConsumerStatefulWidget {
  final PickedAddress from;
  final PickedAddress to;
  final VehicleType vehicleType;

  /// Гест режимі: «Заказ жариялау» жарияламай, деректі сақтап, кіру экранына
  /// жібереді (кіргеннен кейін [draft] арқылы жалғасады).
  final bool isGuest;

  /// Кіргеннен кейін жалғасатын жоба заказ — өрістер осыдан толтырылады.
  final DraftOrder? draft;

  /// Экран ашылып, маршрут есептелген соң автоматты жариялау (кіргеннен кейін).
  final bool autoSubmit;

  const CreateOrderScreen({
    super.key,
    required this.from,
    required this.to,
    this.vehicleType = VehicleType.gazelle,
    this.isGuest = false,
    this.draft,
    this.autoSubmit = false,
  });

  @override
  ConsumerState<CreateOrderScreen> createState() => _CreateOrderScreenState();
}

class _CreateOrderScreenState extends ConsumerState<CreateOrderScreen> {
  final _cargo = TextEditingController();
  final _comment = TextEditingController();
  final _price = TextEditingController();

  late VehicleType _vehicle = widget.vehicleType; // қажет көлік түрі
  bool _legalOk = false;
  late final TapGestureRecognizer _legalListTap = TapGestureRecognizer()
    ..onTap = () => Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const LegalScreen(initialTab: 0)));
  GeoRoute? _route;
  final List<Uint8List> _photos = [];
  final _picker = ImagePicker();
  bool _autoSubmitted = false;

  late PickedAddress _from = widget.from;
  late PickedAddress _to = widget.to;

  /// Қайдан/қайда қалалары әртүрлі болса — межгород.
  /// (Әкімшілік жұрнақтарын алып тастап салыстырады: «Тараз қаласы» мен
  /// «Тараз қалалық әкімшілігі» бір қала болып есептеледі.)
  bool get _intercity =>
      _from.city != null &&
      _to.city != null &&
      !Geo.sameCity(_from.city, _to.city);

  /// §2 Минимум баға: қала ішінде 100 ₸, межгород 1000 ₸.
  int get _minPrice => _intercity ? 1000 : 100;

  @override
  void initState() {
    super.initState();
    // Кіргеннен кейін жалғасатын жоба заказ болса — өрістерді толтырамыз.
    final d = widget.draft;
    if (d != null) {
      _cargo.text = d.cargo;
      _comment.text = d.comment;
      _price.text = d.priceText;
      _vehicle = d.vehicle;
      _legalOk = d.legalOk;
      _photos.addAll(d.photos);
    }
    _loadRoute();
  }

  Future<void> _editFrom() async {
    final res = await CityStreetSheet.show(
      context,
      title: t('Қайдан аламыз?'),
      initial: _from,
    );
    if (res != null && mounted) {
      setState(() {
        _from = res;
        _route = null;
      });
      _loadRoute();
    }
  }

  Future<void> _editTo() async {
    final res = await CityStreetSheet.show(
      context,
      title: t('Қайда жеткіземіз?'),
      initial: _to,
    );
    if (res != null && mounted) {
      setState(() {
        _to = res;
        _route = null;
      });
      _loadRoute();
    }
  }

  @override
  void dispose() {
    _cargo.dispose();
    _comment.dispose();
    _price.dispose();
    _legalListTap.dispose();
    super.dispose();
  }

  Future<void> _loadRoute() async {
    final r = await Geo.route(_from.point, _to.point);
    if (!mounted) return;
    setState(() => _route = r);
    // Кіргеннен кейінгі автоматты жариялау — маршрут дайын болғанда бір рет.
    if (widget.autoSubmit && !_autoSubmitted) {
      _autoSubmitted = true;
      _submit();
    }
  }

  Future<void> _addPhoto() async {
    if (_photos.length >= 5) {
      showSnack(context, t('Ең көбі 5 фото'), error: true);
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
    setState(() => _photos.add(bytes));
  }

  Future<void> _submit() async {
    final route = _route;
    if (route == null) {
      showSnack(context, t('Маршрут әлі есептелуде…'), error: true);
      return;
    }
    if (_cargo.text.trim().isEmpty) {
      showSnack(context, t('Не таситыныңызды жазыңыз'), error: true);
      return;
    }
    if (!Geo.inKazakhstan(_from.point) || !Geo.inKazakhstan(_to.point)) {
      showSnack(
        context,
        t('Заказ тек Қазақстан ішінде болуы керек'),
        error: true,
      );
      return;
    }
    if (!_legalOk) {
      showSnack(
        context,
        t(
          'Жүктің заңды екеніне растау белгісін қойыңыз (тыйым салынған заттар тізімі — Келісімде)',
        ),
        error: true,
      );
      return;
    }
    // §2/§3: барлық заказ — клиент бағасын өзі қояды (bidding).
    final clientPrice = int.tryParse(_price.text.replaceAll(RegExp(r'\D'), ''));
    if (clientPrice == null || clientPrice < _minPrice) {
      showSnack(
        context,
        _intercity
            ? '${t('Межгород бағасы кемінде')} ${fmtT(_minPrice)} ${t('болуы керек')}'
            : '${t('Бағаңызды жазыңыз (кемінде')} ${fmtT(_minPrice)})',
        error: true,
      );
      return;
    }
    // Гест: заказды жарияламай, толтырылған деректі сақтап, кіру экранына
    // жібереміз. Кіргеннен/тіркелгеннен кейін ClientShell осы жобаны ашып,
    // автоматты жариялайды — ешбір дерек жоғалмайды.
    if (widget.isGuest) {
      ref.read(draftOrderProvider.notifier).state = DraftOrder(
        from: _from,
        to: _to,
        vehicle: _vehicle,
        cargo: _cargo.text,
        comment: _comment.text,
        priceText: _price.text,
        photos: List.of(_photos),
        legalOk: _legalOk,
      );
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const LoginScreen()));
      // Кіру сәтті болса — popUntil бұл экранды жауып, ClientShell жобаны
      // жалғастырады (мұнда жетпейміз). Ал қолданушы кірмей артқа қайтса —
      // жобаны тазалаймыз (кейін басқа кезде кенеттен жарияланбауы үшін).
      if (!mounted) return;
      if (Repo.uid == null) {
        ref.read(draftOrderProvider.notifier).state = null;
      }
      return;
    }
    try {
      // фотоларды алдын ала жүктейміз
      final photoPaths = <String>[];
      for (var i = 0; i < _photos.length; i++) {
        photoPaths.add(await Repo.uploadOrderPhoto(_photos[i], i));
      }
      final id = await Repo.createOrder(
        vehicleType: _vehicle,
        fromAddress: _from.address,
        fromLat: _from.point.latitude,
        fromLng: _from.point.longitude,
        toAddress: _to.address,
        toLat: _to.point.latitude,
        toLng: _to.point.longitude,
        distanceKm: double.parse(route.distanceKm.toStringAsFixed(2)),
        cargo: _cargo.text,
        comment: _comment.text,
        clientPrice: clientPrice,
        photos: photoPaths,
        fromCity: _from.city,
        toCity: _to.city,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: id)));
    } catch (e) {
      if (mounted) showSnack(context, errText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final route = _route;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Container(
            decoration: const BoxDecoration(
              color: Gz.bg,
              borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Gz.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 10, 8, 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          t('Заказ құру'),
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_from.city != null && _to.city != null)
                          Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: (_intercity ? Gz.violet : Gz.green)
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _intercity
                                      ? Icons.alt_route
                                      : Icons.location_city_outlined,
                                  size: 18,
                                  color: _intercity ? Gz.violet : Gz.green,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _intercity
                                        ? '${t('Сіз қалалар аралық (межгород) заказ бересіз:')} '
                                              '${_from.city} → ${_to.city}'
                                        : t('Қала ішіндегі тасымал'),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12.5,
                                      color: _intercity ? Gz.violet : Gz.green,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        RouteMap(
                          from: _from.point,
                          to: _to.point,
                          routePoints: route?.points ?? const [],
                          height: 170,
                        ),
                        const SizedBox(height: 10),
                        SectionCard(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            children: [
                              // Адрестерді осында өзгертуге болады
                              _EditableAddr(
                                icon: Icons.trip_origin,
                                color: Gz.green,
                                label: t('Қайдан'),
                                value: _from.address,
                                onTap: _editFrom,
                              ),
                              const SizedBox(height: 6),
                              _EditableAddr(
                                icon: Icons.location_on,
                                color: Gz.red,
                                label: t('Қайда'),
                                value: _to.address,
                                onTap: _editTo,
                              ),
                              if (route != null) ...[
                                const Divider(height: 20),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.route,
                                      size: 17,
                                      color: Gz.textSecondary,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '${route.distanceKm.toStringAsFixed(1)} км',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    const Icon(
                                      Icons.schedule,
                                      size: 17,
                                      color: Gz.textSecondary,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '~${route.durationMin.round()} ${t('мин')}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          t('Көлік түрі'),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          t('Заказды тек осы түрдегі орындаушылар көреді.'),
                          style: const TextStyle(
                            color: Gz.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 8),
                        VehicleTypeCarousel(
                          selected: _vehicle,
                          onChanged: (v) => setState(() => _vehicle = v),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _cargo,
                          decoration: InputDecoration(
                            labelText: t('Заказ туралы толығырақ'),
                            hintText: t('мыс: диван, тоңазытқыш, көшу'),
                            prefixIcon: const Icon(Icons.inventory_2_outlined),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _comment,
                          maxLines: 2,
                          decoration: InputDecoration(
                            hintText: t(
                              'Қосымша түсініктеме (қабат, лифт, көмек керек пе…)',
                            ),
                            prefixIcon: const Icon(Icons.notes),
                          ),
                        ),
                        const SizedBox(height: 14),
                        // Жүк фотолары
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                t('Жүк фотосы (міндетті емес, макс 5)'),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _addPhoto,
                              icon: const Icon(Icons.add_a_photo, size: 18),
                              label: Text(t('Қосу')),
                            ),
                          ],
                        ),
                        if (_photos.isNotEmpty)
                          SizedBox(
                            height: 84,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: _photos.length,
                              separatorBuilder: (_, i) =>
                                  const SizedBox(width: 8),
                              itemBuilder: (_, i) => Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.memory(
                                      _photos[i],
                                      width: 84,
                                      height: 84,
                                      fit: BoxFit.cover,
                                      cacheWidth:
                                          (84 *
                                                  MediaQuery.devicePixelRatioOf(
                                                    context,
                                                  ))
                                              .round(),
                                      cacheHeight:
                                          (84 *
                                                  MediaQuery.devicePixelRatioOf(
                                                    context,
                                                  ))
                                              .round(),
                                    ),
                                  ),
                                  Positioned(
                                    top: 2,
                                    right: 2,
                                    child: GestureDetector(
                                      onTap: () =>
                                          setState(() => _photos.removeAt(i)),
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
                              ),
                            ),
                          ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Text(
                              t('Бағаңызды ұсыныңыз'),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: (_intercity ? Gz.violet : Gz.green)
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '${t('мин.')} ${fmtT(_minPrice)}',
                                style: TextStyle(
                                  color: _intercity ? Gz.violet : Gz.green,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _intercity
                              ? '${t('Қалааралық заказ — бағаны өзіңіз қоясыз (кемінде')} '
                                    '${fmtT(_minPrice)}). ${t('Газелисттер келіседі не өз бағасын ұсынады.')}'
                              : '${t('Қала ішіндегі заказ — бағаны өзіңіз қоясыз (кемінде')} '
                                    '${fmtT(_minPrice)}). ${t('Газелисттер келіседі не өз бағасын ұсынады.')}',
                          style: const TextStyle(
                            color: Gz.textSecondary,
                            fontSize: 12.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _price,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setState(() {}),
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                          decoration: InputDecoration(
                            hintText: '${t('Бағаңыз (мин.')} $_minPrice)',
                            hintStyle: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Gz.textSecondary,
                            ),
                            prefixIcon: const Icon(Icons.payments_outlined),
                            suffixText: '₸ ',
                            suffixStyle: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: Gz.textSecondary,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(15),
                              borderSide: const BorderSide(
                                color: Gz.ink,
                                width: 1.6,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => setState(() => _legalOk = !_legalOk),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 28,
                                  height: 28,
                                  child: Checkbox(
                                    value: _legalOk,
                                    activeColor: Gz.ink,
                                    onChanged: (v) =>
                                        setState(() => _legalOk = v ?? false),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text.rich(
                                    TextSpan(
                                      style: const TextStyle(
                                        fontSize: 12,
                                        height: 1.4,
                                        color: Gz.textSecondary,
                                      ),
                                      children: [
                                        TextSpan(
                                          text:
                                              '${t('Жүгімнің заңды екеніне және тыйым '
                                              'салынған заттар')} ',
                                        ),
                                        TextSpan(
                                          text: t('тізіміне'),
                                          recognizer: _legalListTap,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            color: Gz.ink,
                                            decoration:
                                                TextDecoration.underline,
                                          ),
                                        ),
                                        TextSpan(
                                          text:
                                              ' ${t('кірмейтініне кепілдік беремін.')}',
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        BusyButton(
                          label: t('Заказ жариялау'),
                          onPressed: _submit,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          t(
                            'Төлем клиент пен орындаушы арасында қолма-қол/аударыммен шешіледі.',
                          ),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Gz.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Басуға болатын адрес жолы (заказ құру экранында өзгерту үшін).
class _EditableAddr extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final VoidCallback onTap;
  const _EditableAddr({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Gz.textSecondary,
                    ),
                  ),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.edit, size: 16, color: Gz.textSecondary),
          ],
        ),
      ),
    );
  }
}
