import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/geo.dart';
import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/map_widgets.dart';
import '../../shared/widgets.dart';
import 'address_picker.dart';
import 'city_street_sheet.dart';
import 'order_detail_screen.dart';

/// Заказ құру: жүк детальдары, өлшем, режим (өз бағам / жедел).
/// Адрестерді осы экранда өзгертуге болады — опциялар жоғалмайды.
class CreateOrderScreen extends StatefulWidget {
  final PickedAddress from;
  final PickedAddress to;
  const CreateOrderScreen({super.key, required this.from, required this.to});

  @override
  State<CreateOrderScreen> createState() => _CreateOrderScreenState();
}

class _CreateOrderScreenState extends State<CreateOrderScreen> {
  final _cargo = TextEditingController();
  final _comment = TextEditingController();
  final _price = TextEditingController();

  VehicleSize _size = VehicleSize.small;
  String _mode = 'bidding'; // bidding | instant
  GeoRoute? _route;
  int? _quote;
  bool _quoteLoading = false;
  final List<Uint8List> _photos = [];
  final _picker = ImagePicker();

  late PickedAddress _from = widget.from;
  late PickedAddress _to = widget.to;

  /// Қайдан/қайда қалалары әртүрлі болса — межгород.
  /// (Әкімшілік жұрнақтарын алып тастап салыстырады: «Тараз қаласы» мен
  /// «Тараз қалалық әкімшілігі» бір қала болып есептеледі.)
  bool get _intercity =>
      _from.city != null &&
      _to.city != null &&
      !Geo.sameCity(_from.city, _to.city);

  @override
  void initState() {
    super.initState();
    _loadRoute();
  }

  Future<void> _editFrom() async {
    final res = await CityStreetSheet.show(context,
        title: 'Қайдан аламыз?', initial: _from);
    if (res != null && mounted) {
      setState(() {
        _from = res;
        _route = null;
      });
      _loadRoute();
    }
  }

  Future<void> _editTo() async {
    final res = await CityStreetSheet.show(context,
        title: 'Қайда жеткіземіз?', initial: _to);
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
    super.dispose();
  }

  Future<void> _loadRoute() async {
    final r = await Geo.route(_from.point, _to.point);
    if (mounted) {
      setState(() => _route = r);
      _loadQuote();
    }
  }

  Future<void> _loadQuote() async {
    final r = _route;
    if (r == null) return;
    setState(() => _quoteLoading = true);
    try {
      final q = await Repo.instantQuote(_size, r.distanceKm);
      if (mounted) setState(() => _quote = q);
    } catch (_) {
      if (mounted) setState(() => _quote = null);
    } finally {
      if (mounted) setState(() => _quoteLoading = false);
    }
  }

  Future<void> _addPhoto() async {
    if (_photos.length >= 5) {
      showSnack(context, 'Ең көбі 5 фото', error: true);
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
    if (source == null) return;
    final f =
        await _picker.pickImage(source: source, imageQuality: 65, maxWidth: 1400);
    if (f == null) return;
    final bytes = await f.readAsBytes();
    setState(() => _photos.add(bytes));
  }

  Future<void> _submit() async {
    final route = _route;
    if (route == null) {
      showSnack(context, 'Маршрут әлі есептелуде…', error: true);
      return;
    }
    if (_cargo.text.trim().isEmpty) {
      showSnack(context, 'Не таситыныңызды жазыңыз', error: true);
      return;
    }
    if (!Geo.inKazakhstan(_from.point) || !Geo.inKazakhstan(_to.point)) {
      showSnack(context, 'Заказ тек Қазақстан ішінде болуы керек', error: true);
      return;
    }
    int? clientPrice;
    if (_mode == 'bidding') {
      clientPrice = int.tryParse(_price.text.replaceAll(RegExp(r'\D'), ''));
      if (clientPrice == null || clientPrice < 100) {
        showSnack(context, 'Бағаңызды жазыңыз (кемінде 100 ₸)', error: true);
        return;
      }
    }
    try {
      // фотоларды алдын ала жүктейміз
      final photoPaths = <String>[];
      for (var i = 0; i < _photos.length; i++) {
        photoPaths.add(await Repo.uploadOrderPhoto(_photos[i], i));
      }
      final id = await Repo.createOrder(
        type: _mode,
        fromAddress: _from.address,
        fromLat: _from.point.latitude,
        fromLng: _from.point.longitude,
        toAddress: _to.address,
        toLat: _to.point.latitude,
        toLng: _to.point.longitude,
        distanceKm: double.parse(route.distanceKm.toStringAsFixed(2)),
        cargo: _cargo.text,
        comment: _comment.text,
        size: _size,
        clientPrice: clientPrice,
        photos: photoPaths,
        fromCity: _from.city,
        toCity: _to.city,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => OrderDetailScreen(orderId: id)));
    } catch (e) {
      if (mounted) showSnack(context, errText(e), error: true);
    }
  }

  Widget _modeCard({
    required String mode,
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required Widget content,
  }) {
    final selected = _mode == mode;
    return GestureDetector(
      onTap: () => setState(() => _mode = mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Gz.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? color : Gz.border,
            width: selected ? 1.8 : 1.2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 15)),
                      Text(subtitle,
                          style: const TextStyle(
                              color: Gz.textSecondary, fontSize: 12)),
                    ],
                  ),
                ),
                Radio<String>(
                  value: mode,
                  // ignore: deprecated_member_use
                  groupValue: _mode,
                  // ignore: deprecated_member_use
                  onChanged: (v) => setState(() => _mode = v!),
                  activeColor: color,
                ),
              ],
            ),
            if (selected) ...[const SizedBox(height: 10), content],
          ],
        ),
      ),
    );
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
                      color: Gz.border, borderRadius: BorderRadius.circular(2)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 10, 8, 2),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text('Заказ құру',
                            style: TextStyle(
                                fontSize: 19, fontWeight: FontWeight.w900)),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                          color: _intercity ? Gz.violet : Gz.green),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _intercity
                              ? 'Сіз қалалар аралық (межгород) заказ бересіз: '
                                  '${_from.city} → ${_to.city}'
                              : 'Қала ішіндегі тасымал',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                              color: _intercity ? Gz.violet : Gz.green),
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
                        label: 'Қайдан',
                        value: _from.address,
                        onTap: _editFrom),
                    const SizedBox(height: 6),
                    _EditableAddr(
                        icon: Icons.location_on,
                        color: Gz.red,
                        label: 'Қайда',
                        value: _to.address,
                        onTap: _editTo),
                    if (route != null) ...[
                      const Divider(height: 20),
                      Row(
                        children: [
                          const Icon(Icons.route,
                              size: 17, color: Gz.textSecondary),
                          const SizedBox(width: 6),
                          Text(
                            '${route.distanceKm.toStringAsFixed(1)} км',
                            style:
                                const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(width: 16),
                          const Icon(Icons.schedule,
                              size: 17, color: Gz.textSecondary),
                          const SizedBox(width: 6),
                          Text(
                            '~${route.durationMin.round()} мин',
                            style:
                                const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text('Қандай газель керек?',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(height: 8),
              VehicleSizeSelector(
                value: _size,
                onChanged: (s) {
                  setState(() => _size = s);
                  _loadQuote();
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _cargo,
                decoration: const InputDecoration(
                  hintText: 'Не тасимыз? (мыс: диван, тоңазытқыш, көшу)',
                  prefixIcon: Icon(Icons.inventory_2_outlined),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _comment,
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText: 'Қосымша түсініктеме (қабат, лифт, көмек керек пе…)',
                  prefixIcon: Icon(Icons.notes),
                ),
              ),
              const SizedBox(height: 14),
              // Жүк фотолары
              Row(
                children: [
                  const Expanded(
                    child: Text('Жүк фотосы (міндетті емес, макс 5)',
                        style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 14)),
                  ),
                  TextButton.icon(
                    onPressed: _addPhoto,
                    icon: const Icon(Icons.add_a_photo, size: 18),
                    label: const Text('Қосу'),
                  ),
                ],
              ),
              if (_photos.isNotEmpty)
                SizedBox(
                  height: 84,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _photos.length,
                    separatorBuilder: (_, i) => const SizedBox(width: 8),
                    itemBuilder: (_, i) => Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.memory(_photos[i],
                              width: 84, height: 84, fit: BoxFit.cover),
                        ),
                        Positioned(
                          top: 2,
                          right: 2,
                          child: GestureDetector(
                            onTap: () => setState(() => _photos.removeAt(i)),
                            child: const CircleAvatar(
                              radius: 11,
                              backgroundColor: Colors.black54,
                              child: Icon(Icons.close,
                                  size: 13, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              const Text('Тәсілді таңдаңыз',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(height: 8),
              _modeCard(
                mode: 'bidding',
                icon: Icons.gavel,
                color: Gz.blue,
                title: 'Өз бағамды ұсынамын',
                subtitle: 'Орындаушылар келіседі немесе өз бағасын ұсынады',
                content: TextField(
                  controller: _price,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    hintText: 'Бағаңыз, ₸',
                    prefixIcon: Icon(Icons.payments_outlined),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _modeCard(
                mode: 'instant',
                icon: Icons.flash_on,
                color: Gz.violet,
                title: 'Жедел заказ',
                subtitle: 'Баға дайын — VIP орындаушы бірден тағайындалады',
                content: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Gz.violet.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Text('Платформа бағасы:',
                          style: TextStyle(
                              color: Gz.textSecondary, fontSize: 13.5)),
                      const Spacer(),
                      _quoteLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))
                          : Text(
                              fmtT(_quote),
                              style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: Gz.violet),
                            ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              BusyButton(
                label: _mode == 'bidding'
                    ? 'Заказ жариялау'
                    : 'Жедел заказ беру${_quote != null ? ' · ${fmtT(_quote)}' : ''}',
                onPressed: _submit,
              ),
              const SizedBox(height: 8),
              const Text(
                'Төлем клиент пен орындаушы арасында қолма-қол/аударыммен шешіледі.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Gz.textSecondary, fontSize: 12),
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
                  Text(label,
                      style: const TextStyle(
                          fontSize: 11, color: Gz.textSecondary)),
                  Text(value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
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
