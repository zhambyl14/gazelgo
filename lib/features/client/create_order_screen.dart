import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/geo.dart';
import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/phone.dart';
import '../../core/prefs.dart';
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
import 'order_extras_editor.dart';
import 'saved_addresses.dart';

/// Заказ құру: жүк детальдары, көлік түрі, баға.
/// Адрестерді осы экранда өзгертуге болады — опциялар жоғалмайды.
class CreateOrderScreen extends ConsumerStatefulWidget {
  final PickedAddress from;
  final PickedAddress to;

  /// Аралық аялдамалар (0047) — «қайдан» мен «қайда» АРАСЫНДА, ретімен.
  final List<PickedAddress> stops;
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
    this.stops = const [],
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

  /// «Заказ туралы толығырақ» өрісі — экран ашылған бойда ОСЫҒАН фокус
  /// беріледі: клиенттер бұл жолды байқамай, бос қалдырып жіберетін.
  final _cargoFocus = FocusNode();
  final _cargoKey = GlobalKey();
  final _scroll = ScrollController();

  late VehicleType _vehicle = widget.vehicleType; // қажет көлік түрі
  bool _legalOk = false;

  /// Заңдылық белгісі АВТОМАТТЫ қойылды ма (алғашқы бірнеше заказдан кейін).
  bool _legalAuto = false;

  /// «Тізім» — тыйым салынған заттардың НАҚТЫ тізіміне апарады: құжат
  /// ашылған бойда сол бөлімге автоматты скролл жасалып, ол қысқа уақыт
  /// белгіленеді. Бұрын жай ғана келісімнің басы ашылатын да, қолданушы
  /// тізімді 5-бөлімнен өзі іздеуге мәжбүр болатын.
  late final TapGestureRecognizer _legalListTap = TapGestureRecognizer()
    ..onTap = () => Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const LegalScreen(
          initialTab: 0,
          scrollToSection: kProhibitedCargoSection,
        ),
      ),
    );
  GeoRoute? _route;
  final List<Uint8List> _photos = [];
  final _picker = ImagePicker();
  bool _autoSubmitted = false;

  /// Алдын ала тапсырыс (0060) — таңдалса, заказ дәл осы уақытта ғана
  /// орындаушыға көрінеді. `null` — әдеттегідей «дәл қазір».
  DateTime? _scheduledAt;

  late PickedAddress _from = widget.from;
  late PickedAddress _to = widget.to;
  late final List<PickedAddress> _stops = List.of(widget.stops);

  /// ТАКСИ заказы ма (жолаушы тасымалы) — форма мүлдем басқаша: жүк
  /// сипаттамасы да, фото да, заңдылық белгісі де қажет емес, орнына
  /// ЖОЛАУШЫ САНЫ сұралады.
  ///
  /// МАҢЫЗДЫ: «Доставка» ({@link VehicleType.delivery}) такси САНАТЫНДА
  /// болғанымен, ол ЖҮК жеткізу — сол себепті формасы кәдімгі жүк заказы
  /// сияқты (не жеткізу керек + фото). Тек осы `_isTaxi` таксиге тән.
  bool get _isTaxi => _vehicle.isPassenger;

  /// Доставка заказы ма — жүк формасы, бірақ жеңіл көлікпен.
  bool get _isDelivery => _vehicle == VehicleType.delivery;

  /// Такси заказындағы жолаушы саны (сервер `cargo_desc`-ті бос қалдырмауды
  /// талап етеді, сол себепті осыдан мәтін құрылады).
  int _passengers = 2;

  /// Қосымша талаптар (0077): тиеушілер, қабат, лифт — міндетті емес.
  OrderExtras _extras = const OrderExtras();

  /// Жүкті басқа адам қабылдаса (0076) — аты мен телефоны.
  bool _withRecipient = false;
  final _recipName = TextEditingController();
  final _recipPhone = TextEditingController(text: '+7');

  /// Ұқсас заказдардың бағасы (0077) — клиентке «қанша қою керек» бағдары.
  PriceHint? _hint;

  /// Сервер алушыны қолдай ма (0076) — жоқ болса блок көрінбейді.
  bool _recipAvailable = false;

  /// Маршруттың барлық нүктесі: алу → аялдамалар → жеткізу.
  List<PickedAddress> get _points => [_from, ..._stops, _to];

  /// Маршруттағы қалалар әртүрлі болса — межгород. АРАЛЫҚ АЯЛДАМАЛАР да
  /// ескеріледі (0047): аялдама басқа қалада болса заказ қалааралық болады
  /// әрі минимум баға да соған сай көтеріледі — серверде `create_order`
  /// дәл осылай есептейді, сол себепті екеуі айырылып қалмайды.
  ///
  /// (Әкімшілік жұрнақтарын алып тастап салыстырады: «Тараз қаласы» мен
  /// «Тараз қалалық әкімшілігі» бір қала болып есептеледі.)
  bool get _intercity => distinctCities(_points.map((p) => p.city)).length > 1;

  /// §2 Минимум баға: қала ішінде 100 ₸, межгород 1000 ₸. Модератор бұл
  /// көлік түріне «км-ге минималды сома» қосқан болса (0092) — маршрут
  /// қашықтығына сай есептелген сома да ескеріледі, екеуінің үлкені алынады.
  int get _minPrice => _minPriceFor(_route?.distanceKm);

  int _minPriceFor(double? km) {
    final base = _intercity ? 1000 : 100;
    if (km == null) return base;
    // Серверге дәл осы дөңгелектелген қашықтық кетеді (createOrder).
    final perKm = _vehicle.spec.minPriceFor(double.parse(km.toStringAsFixed(2)));
    return perKm > base ? perKm : base;
  }

  /// Минимум км-ге байланысты көтерілген бе (чипте түсіндіру үшін).
  bool get _minByDistance =>
      _minPrice > (_intercity ? 1000 : 100) && _vehicle.spec.minPerKmEnabled;

  int? get _priceValue =>
      int.tryParse(_price.text.replaceAll(RegExp(r'\D'), ''));

  /// Жарияларға дайын емес болса — НЕ жетпейтіні (батырманың астында бір
  /// қатармен көрсетіледі). Дайын болса null.
  ///
  /// Батырма өзі СҰР күйде тұрады: бұрын сары батырманы басқанда ғана
  /// «мынау жетпейді» деген қызыл snackbar шығатын — енді неге басылмайтыны
  /// алдын ала көрініп тұрады.
  String? get _missing {
    if (_route == null) return t('Маршрут есептелуде…');
    // Таксиде жүк сипаттамасы жоқ (жолаушы саны автоматты толтырылады),
    // заңдылық белгісі де қажет емес — ол ЖҮККЕ қатысты.
    if (!_isTaxi && _cargo.text.trim().isEmpty) {
      return t('Заказ туралы жазыңыз');
    }
    final p = _priceValue;
    if (p == null || p < _minPrice) {
      return '${t('Бағаңыз кемінде')} ${fmtT(_minPrice)}';
    }
    if (!_isTaxi && !_legalOk) return t('Заңдылық белгісін қойыңыз');
    if (_withRecipient && !Phone.isValid(_recipPhone.text)) {
      return t('Алушының телефонын тексеріңіз');
    }
    return null;
  }

  bool get _canSubmit => _missing == null;

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
      _passengers = d.passengers;
      _photos.addAll(d.photos);
      _extras = d.extras;
      if (d.recipientPhone.isNotEmpty) {
        _withRecipient = true;
        _recipName.text = d.recipientName;
        _recipPhone.text = d.recipientPhone;
      }
    }
    _loadRoute();
    _restoreLegalPreference();
    Repo.recipientsAvailable().then((v) {
      if (mounted && v) setState(() => _recipAvailable = true);
    });
    // Экран ашылған соң «Заказ туралы» өрісіне фокус береміз (маршрут
    // транзициясы бітсін деп сәл кідіреміз). Таксиде ол өріс жоқ.
    if (!_isTaxi) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusCargo());
    }
  }

  /// Алғашқы [Prefs.kLegalAutoAfter] заказда клиент заңдылық белгісін
  /// ҚОЛМЕН қояды — содан кейін ол автоматты қойылып тұрады (белгіні алып
  /// тастауға болады). Мақсаты: әр заказда бір артық түрту болмасын.
  Future<void> _restoreLegalPreference() async {
    if (_legalOk) return;
    final n = await Prefs.legalConfirms();
    if (!mounted || n < Prefs.kLegalAutoAfter) return;
    setState(() {
      _legalOk = true;
      _legalAuto = true;
    });
  }

  /// Жүк сипаттамасы өрісін көрінетін жерге шығарып, пернетақтаны ашамыз.
  Future<void> _focusCargo() async {
    // Slide-up транзициясы аяқталмай тұрып ensureVisible дұрыс есептемейді.
    await Future.delayed(const Duration(milliseconds: 420));
    if (!mounted) return;
    // Жоба заказ жалғасып жатса (гесттен кейінгі автожариялау) не өріс
    // толтырылған болса — араласпаймыз.
    if (widget.autoSubmit || _cargo.text.trim().isNotEmpty) return;
    final ctx = _cargoKey.currentContext;
    if (ctx != null && ctx.mounted) {
      await Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        alignment: 0.12,
      );
    }
    if (mounted) _cargoFocus.requestFocus();
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

  /// Аралық аялдаманы өзгерту не алып тастау (0047). Екеуінде де маршрут
  /// қайта есептеледі: қашықтық пен межгород күйі өзгеруі мүмкін.
  Future<void> _editStop(int index) async {
    final res = await CityStreetSheet.show(
      context,
      title: t('Мекенжайды өзгерту'),
      initial: _stops[index],
      origin: _from.point,
    );
    if (res != null && mounted) {
      setState(() {
        _stops[index] = res;
        _route = null;
      });
      _loadRoute();
    }
  }

  /// Жаңа мекенжай қосу. Ол маршруттың СОҢҒЫ нүктесі болады, бұрынғы соңғы
  /// нүкте аралық аялдамаға айналады — клиент әдетте «жол бойымен тағы бір
  /// жер» қосады. Басты беттегі логика да ДӘЛ СОЛАЙ (екі экранда бірдей).
  Future<void> _addStop() async {
    final res = await CityStreetSheet.show(
      context,
      title: t('Мекенжай қосу'),
      origin: _from.point,
    );
    if (res != null && mounted) {
      setState(() {
        _stops.add(_to);
        _to = res;
        _route = null;
      });
      _loadRoute();
    }
  }

  void _removeStop(int index) {
    setState(() {
      _stops.removeAt(index);
      _route = null;
    });
    _loadRoute();
  }

  Future<void> _editTo() async {
    final res = await CityStreetSheet.show(
      context,
      title: t('Қайда жеткіземіз?'),
      initial: _to,
      origin: _from.point,
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
    _cargoFocus.dispose();
    _scroll.dispose();
    _legalListTap.dispose();
    _recipName.dispose();
    _recipPhone.dispose();
    super.dispose();
  }

  /// Ұқсас заказдардың бағасы — маршрут не көлік түрі өзгерген сайын.
  Future<void> _loadHint() async {
    final r = _route;
    if (r == null || r.distanceKm <= 0) return;
    final vehicle = _vehicle;
    final h = await Repo.orderPriceHint(
      vehicle: vehicle,
      distanceKm: r.distanceKm,
      city: _from.city,
      intercity: _intercity,
    );
    if (!mounted || vehicle != _vehicle) return;
    setState(() => _hint = h);
  }

  /// «Ұқсас заказдар бағасы» — үш чип: төмен / әдетте / жоғары. Басса —
  /// баға өрісіне қойылады.
  Widget _priceHint(PriceHint h) {
    Widget chip(int v, String label, {bool main = false}) => Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(Gz.rSm),
        onTap: () => setState(() => _price.text = '$v'),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          decoration: BoxDecoration(
            color: main ? Gz.tint(Gz.yellow, 0.25) : Gz.surface,
            borderRadius: BorderRadius.circular(Gz.rSm),
            border: Border.all(
              color: main ? Gz.yellowDark : Gz.border,
              width: main ? 1.4 : 1,
            ),
          ),
          child: Column(
            children: [
              Text(
                fmtT(v),
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
              Text(label, style: Gz.caption),
            ],
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.insights_rounded, size: 16, color: Gz.textSecondary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${t('Ұқсас заказдар бағасы')} (${h.samples})',
                style: Gz.caption,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            chip(h.low, t('арзан')),
            const SizedBox(width: 6),
            chip(h.typical, t('әдетте'), main: true),
            const SizedBox(width: 6),
            chip(h.high, t('тез табылады')),
          ],
        ),
      ],
    );
  }

  /// «Жүкті басқа адам қабылдайды» — аты + телефон (0076). Заказ
  /// жарияланған соң алушыға WhatsApp арқылы сілтеме мен код жіберіледі.
  Widget _recipientSection() {
    return SectionCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            value: _withRecipient,
            onChanged: (v) => setState(() => _withRecipient = v),
            secondary: Icon(Icons.person_pin_circle_outlined, color: Gz.violet),
            title: Text(t('Жүкті басқа адам қабылдайды'), style: Gz.h3),
            subtitle: Text(
              t(
                'Оған көлік қайда екені көрінетін сілтеме мен 4 таңбалы код '
                'барады',
              ),
              style: Gz.caption,
            ),
          ),
          if (_withRecipient)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                children: [
                  TextField(
                    controller: _recipName,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      hintText: t('Аты (міндетті емес)'),
                      prefixIcon: const Icon(Icons.person_outline_rounded),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _recipPhone,
                    keyboardType: TextInputType.phone,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: '+7 7XX XXX XX XX',
                      prefixIcon: const Icon(Icons.phone_outlined),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _loadRoute() async {
    // Маршрут БАРЛЫҚ нүкте арқылы есептеледі (аралық аялдамалармен) —
    // қашықтық та, көрсетілетін сызық та солай, әйтпесе клиент қосымша
    // аялдама үшін төлемейтін болып қалатын.
    final points = _points.map((p) => p.point).toList();
    final r = await Geo.routeVia(points);
    if (!mounted) return;
    setState(() => _route = r);
    unawaited(_loadHint());
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
    final source = await pickImageSource(context);
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

  /// Алдын ала тапсырыс уақытын таңдау (0060) — күн, сосын уақыт.
  /// [minHours]/[maxDays] модератор баптауынан келеді.
  Future<void> _pickScheduledAt(int minHours, int maxDays) async {
    final now = DateTime.now();
    final earliest = now.add(Duration(hours: minHours));
    final last = now.add(Duration(days: maxDays));
    final initial = _scheduledAt != null && _scheduledAt!.isAfter(earliest)
        ? _scheduledAt!
        : earliest;
    final date = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(earliest) ? earliest : initial,
      firstDate: earliest,
      lastDate: last,
      helpText: t('Қай күнге?'),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      helpText: t('Қай уақытқа?'),
    );
    if (time == null || !mounted) return;
    var picked = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (picked.isBefore(earliest)) picked = earliest;
    setState(() => _scheduledAt = picked);
  }

  /// Алдын ала тапсырыс бөлімі (0060): «Қазір» / «Жоспарлы» чиптері,
  /// таңдалса — уақыт көрсетіледі әрі өзгертуге/тазалауға болады.
  Widget _scheduleSection(int minHours, int maxDays) {
    final picked = _scheduledAt;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Gz.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Gz.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.schedule_rounded, size: 18, color: Gz.textSecondary),
              const SizedBox(width: 7),
              Text(
                t('Қашан керек?'),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: Text(t('Дәл қазір')),
                selected: picked == null,
                onSelected: (_) => setState(() => _scheduledAt = null),
              ),
              ChoiceChip(
                label: Text(
                  picked == null ? t('Алдын ала жоспарлау') : fmtDate(picked),
                ),
                selected: picked != null,
                onSelected: (_) => _pickScheduledAt(minHours, maxDays),
              ),
            ],
          ),
          if (picked != null) ...[
            const SizedBox(height: 6),
            Text(
              t('Заказ дәл сол уақытқа дейін орындаушыларға көрінбейді.'),
              style: TextStyle(color: Gz.textSecondary, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final route = _route;
    if (route == null) {
      showSnack(context, t('Маршрут әлі есептелуде…'), error: true);
      return;
    }
    // Таксиде жүк сипаттамасы сұралмайды — оның орнына жолаушы саны
    // (сервер `cargo_desc`-ті бос қалдырмауды талап етеді).
    final cargoText = _isTaxi
        ? '${_passengers > 4 ? '4+' : _passengers} ${t('жолаушы')}'
        : _cargo.text;
    if (cargoText.trim().isEmpty) {
      showSnack(context, t('Не таситыныңызды жазыңыз'), error: true);
      return;
    }
    // Қазақстан шекарасы — БАРЛЫҚ нүкте бойынша (аялдамалар да).
    if (_points.any((p) => !Geo.inKazakhstan(p.point))) {
      showSnack(
        context,
        t('Заказ тек Қазақстан ішінде болуы керек'),
        error: true,
      );
      return;
    }
    if (!_isTaxi && !_legalOk) {
      showSnack(context, t('Жүктің заңды екеніне белгі қойыңыз'), error: true);
      return;
    }
    // §2/§3: барлық заказ — клиент бағасын өзі қояды (bidding).
    final clientPrice = _priceValue;
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
        stops: List.of(_stops),
        vehicle: _vehicle,
        cargo: _cargo.text,
        comment: _comment.text,
        priceText: _price.text,
        photos: List.of(_photos),
        legalOk: _legalOk,
        passengers: _passengers,
        extras: _isTaxi ? const OrderExtras() : _extras,
        recipientName: _withRecipient ? _recipName.text.trim() : '',
        recipientPhone: _withRecipient ? _recipPhone.text.trim() : '',
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
      // Маршрут шамамен ғана есептелген болса (OSRM уақытша жауап бермеді —
      // түзу қашықтық × 1.3), жарияламас бұрын НАҚТЫ жолды бір рет қайта
      // сұраймыз: заказдың қашықтығы мен бағасы шамалау емес, нақты болсын.
      var finalRoute = route;
      if (!route.onRoad) {
        final retry = await Geo.routeVia(_points.map((p) => p.point).toList());
        if (retry.onRoad) {
          finalRoute = retry;
          if (mounted) setState(() => _route = retry);
        }
      }
      // Нақты жол шамалаудан ұзағырақ шықса, км бойынша минимум да өседі —
      // серверден қате алмай тұрып клиентке айтамыз.
      final finalMin = _minPriceFor(finalRoute.distanceKm);
      if (clientPrice < finalMin) {
        if (mounted) {
          showSnack(
            context,
            '${t('Бағаңыз кемінде')} ${fmtT(finalMin)}',
            error: true,
          );
        }
        return;
      }
      // фотоларды алдын ала жүктейміз
      final photoPaths = <String>[];
      for (var i = 0; i < _photos.length; i++) {
        photoPaths.add(await Repo.uploadOrderPhoto(_photos[i], i));
      }
      // Қосымша талаптар: сервер 0077-сіз болса — түсініктемеге мәтін болып
      // қосылады (орындаушы бәрібір оқиды).
      final extras = _isTaxi ? const OrderExtras() : _extras;
      final extrasViaRpc = !extras.isEmpty && await Repo.orderExtrasAvailable();
      var comment = _comment.text.trim();
      if (!extras.isEmpty && !extrasViaRpc) {
        comment = [
          comment,
          extras.asText(),
        ].where((s) => s.isNotEmpty).join('. ');
      }
      final id = await Repo.createOrder(
        vehicleType: _vehicle,
        fromAddress: _from.address,
        fromLat: _from.point.latitude,
        fromLng: _from.point.longitude,
        toAddress: _to.address,
        toLat: _to.point.latitude,
        toLng: _to.point.longitude,
        distanceKm: double.parse(finalRoute.distanceKm.toStringAsFixed(2)),
        cargo: cargoText,
        comment: comment,
        clientPrice: clientPrice,
        photos: photoPaths,
        fromCity: _from.city,
        toCity: _to.city,
        // Аралық аялдамалар (0047) — қосылған РЕТПЕН.
        stops: _stops
            .map(
              (s) => OrderStop(
                address: s.address,
                lat: s.point.latitude,
                lng: s.point.longitude,
                city: s.city,
              ),
            )
            .toList(),
        scheduledAt: _scheduledAt,
      );
      // Заказ ЖАРИЯЛАНДЫ — қосымшалардың қатесі оны тоқтатпайды (клиент
      // заказ бетінде қайта қоса алады).
      if (extrasViaRpc) {
        try {
          await Repo.updateOrderDetails(
            id,
            loaders: extras.loaders,
            floorFrom: extras.floorFrom,
            floorTo: extras.floorTo,
            elevator: extras.elevator,
          );
        } catch (_) {}
      }
      if (_withRecipient && Phone.isValid(_recipPhone.text)) {
        try {
          await Repo.setOrderRecipient(
            id,
            _recipName.text.trim(),
            _recipPhone.text.trim(),
          );
        } catch (_) {}
      }
      // Заказ берілген мекенжайларды тарихқа қосамыз («Соңғы» тізімі үшін):
      // маршрут ретімен — соңғысы тізімде бірінші тұрады.
      for (final p in _points) {
        unawaited(AddressBook.pushRecent(p));
      }
      // Заңдылық белгісін ҚОЛМЕН қойған заказды санаймыз: 3-еуінен кейін
      // белгі келесі заказдарда автоматты қойылып тұрады. Таксиде ол белгі
      // мүлдем сұралмайды, сол себепті санамаймыз.
      if (!_isTaxi && !_legalAuto) unawaited(Prefs.bumpLegalConfirms());
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
    final settingsMap = ref.watch(appSettingsProvider).value;
    final schedCfg = settingsMap?['scheduled_orders'];
    final schedEnabled =
        !widget.isGuest && schedCfg is Map && schedCfg['enabled'] == true;
    final schedMinHours = schedCfg is Map
        ? ((schedCfg['min_hours_ahead'] as num?)?.toInt() ?? 2)
        : 2;
    final schedMaxDays = schedCfg is Map
        ? ((schedCfg['max_days_ahead'] as num?)?.toInt() ?? 14)
        : 14;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Container(
            decoration: BoxDecoration(
              color: Gz.bg,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Gz.disabledBg,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 8, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: BtnLabel(
                            _isTaxi
                                ? t('Такси шақыру')
                                : (_isDelivery
                                      ? t('Доставка тапсыру')
                                      : t('Заказ құру')),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ),
                      ),
                      // Жабу түймесі — жұмсақ дөңгелек фонда: жалаң «✕»
                      // тақырыппен бір салмақта тұрып, көзді бөліп тұратын.
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: IconButton.styleFrom(
                          backgroundColor: Gz.surface,
                          foregroundColor: Gz.textSecondary,
                        ),
                        icon: const Icon(Icons.close_rounded, size: 20),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _scroll,
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
                              color: Gz.tint(
                                _intercity ? Gz.violet : Gz.green,
                                0.10,
                              ),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Gz.tint(
                                  _intercity ? Gz.violet : Gz.green,
                                  0.25,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _intercity
                                      ? Icons.alt_route_rounded
                                      : Icons.location_city_rounded,
                                  size: 18,
                                  color: _intercity ? Gz.violet : Gz.green,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _intercity
                                        ? '${t('Қалааралық')}: '
                                              '${_from.city} → ${_to.city}'
                                        : t('Қала ішінде'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      letterSpacing: -0.1,
                                      color: _intercity ? Gz.violet : Gz.green,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        // Маршрут картасы — заказ берер алдындағы СОҢҒЫ
                        // тексеру. Түртсе толық экранда ашылады: клиент
                        // еркін жылжытып, жақындатып, «бағыт дұрыс па?»
                        // дегенге көз жеткізеді.
                        RouteMap(
                          from: _from.point,
                          to: _to.point,
                          stops: _stops.map((s) => s.point).toList(),
                          // Тек НАҚТЫ жол геометриясы беріледі; шамалау
                          // (түзу) болса RouteMap жолды өзі қайта сұрайды.
                          routePoints: (route?.onRoad ?? false)
                              ? route!.points
                              : const [],
                          height: 190,
                          fromLabel: _from.address,
                          toLabel: _to.address,
                          stopLabels: _stops.map((s) => s.address).toList(),
                          distanceKm: route?.distanceKm,
                        ),
                        const SizedBox(height: 10),
                        SectionCard(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            children: [
                              // ---- Маршрут: барлық мекенжай осында ----
                              // Жеткізу нүктелері НӨМІРЛЕНЕДІ (1, 2 …),
                              // соңғысы — ФИНИШ: сол себепті клиент қайсысы
                              // бірінші, қайсысы соңғы екенін бірден оқиды.
                              // Әрқайсысын түртіп өзгертуге, аралығын ✕
                              // арқылы алып тастауға болады.
                              _EditableAddr(
                                mark: const RoutePointMark.origin(),
                                label: t('Қайдан'),
                                value: _from.address,
                                onTap: _editFrom,
                              ),
                              for (var i = 0; i < _stops.length; i++) ...[
                                const SizedBox(height: 6),
                                _EditableAddr(
                                  mark: RoutePointMark.stop(i + 1),
                                  label: '${t('Аялдама')} ${i + 1}',
                                  value: _stops[i].address,
                                  onTap: () => _editStop(i),
                                  onRemove: () => _removeStop(i),
                                ),
                              ],
                              const SizedBox(height: 6),
                              _EditableAddr(
                                mark: const RoutePointMark.finish(),
                                label: _stops.isEmpty
                                    ? t('Қайда')
                                    : t('Соңғы нүкте'),
                                value: _to.address,
                                onTap: _editTo,
                              ),
                              if (_stops.length < kMaxExtraStops) ...[
                                const SizedBox(height: 10),
                                AddAddressButton(onPressed: _addStop),
                              ],
                              if (route != null) ...[
                                const Divider(height: 20),
                                Row(
                                  children: [
                                    Icon(
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
                                    Icon(
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
                        const SizedBox(height: 8),
                        // Карусель ӨЗ САНАТЫНЫҢ түрлерін ғана көрсетеді:
                        // такси/доставка заказында — сол екеуі, жүк
                        // заказында — жүк көліктері. Әйтпесе доставка
                        // заказында жүк каруселі шығып, клиент кездейсоқ
                        // «Газель» таңдап, форма да ауысып кететін.
                        VehicleTypeCarousel(
                          selected: _vehicle,
                          types: kTaxiVehicleTypes.contains(_vehicle)
                              ? kTaxiVehicleTypes
                              : kCargoVehicleTypes,
                          onChanged: (v) {
                            setState(() {
                              _vehicle = v;
                              _hint = null;
                            });
                            _loadHint();
                          },
                        ),
                        const SizedBox(height: 18),
                        // ================= ТАКСИ ФОРМАСЫ =================
                        // Таксиде жүк сипаттамасы да, фото да, заңдылық
                        // белгісі де МАҒЫНАСЫЗ (олар ЖҮККЕ қатысты) —
                        // оның орнына тек ЖОЛАУШЫ САНЫ сұралады.
                        if (_isTaxi) ...[
                          // Ұмай такси: жүргізуші тек әйел адам.
                          if (_vehicle.isUmay) ...[
                            GzNotice(
                              tone: NoticeTone.accent,
                              icon: Icons.favorite_rounded,
                              message: t(
                                'Жүргізуші — әйел адам. Әйелдер мен балаларға арналған.',
                              ),
                              dense: true,
                            ),
                            const SizedBox(height: 14),
                          ],
                          Text(
                            t('Жолаушы саны'),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              for (final n in [1, 2, 3, 4])
                                Expanded(
                                  child: Padding(
                                    padding: EdgeInsets.only(
                                      right: n == 4 ? 0 : 8,
                                    ),
                                    child: _CountChip(
                                      label: n == 4 ? '4+' : '$n',
                                      selected: _passengers == n,
                                      onTap: () =>
                                          setState(() => _passengers = n),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _comment,
                            maxLines: 2,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: InputDecoration(
                              hintText: t('Қосымша: подъезд, багаж…'),
                              prefixIcon: const Icon(Icons.notes),
                            ),
                          ),
                        ] else ...[
                          // ---- НЕГІЗГІ ӨРІС: заказ сипаттамасы ----
                          // Экран ашылған бойда фокус ОСЫҒАН беріледі
                          // (`_focusCargo`): клиенттер бұл жолды толтыруды
                          // ұмытып, бос заказ жіберуге тырысатын.
                          //
                          // ДОСТАВКА да осы тармақта (жүк жеткізіледі), тек
                          // жазулары доставкаға сай — жеңіл көлікпен ұсақ
                          // зат тасымалдайды, «диван/көшу» деген мысал
                          // орынсыз болатын.
                          Row(
                            key: _cargoKey,
                            children: [
                              Text(
                                _isDelivery
                                    ? t('Не жеткізу керек?')
                                    : t('Заказ туралы'),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                '*',
                                style: TextStyle(
                                  color: Gz.red,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _cargo,
                            focusNode: _cargoFocus,
                            textInputAction: TextInputAction.next,
                            textCapitalization: TextCapitalization.sentences,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              hintText: _isDelivery
                                  ? t('мыс: құжат, дәрі, кішкене қап')
                                  : t('мыс: диван, тоңазытқыш, көшу'),
                              prefixIcon: const Icon(
                                Icons.inventory_2_outlined,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _comment,
                            maxLines: 2,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: InputDecoration(
                              hintText: _isDelivery
                                  ? t('Қосымша: подъезд, қабат, кімге беру…')
                                  : t('Қосымша: қабат, лифт, көмек…'),
                              prefixIcon: const Icon(Icons.notes),
                            ),
                          ),
                          const SizedBox(height: 10),
                          OrderExtrasEditor(
                            value: _extras,
                            onChanged: (v) => setState(() => _extras = v),
                          ),
                          const SizedBox(height: 14),
                          // Жүк фотолары
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  t('Фото (міндетті емес)'),
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
                        ],
                        if (!_isTaxi && _photos.isNotEmpty)
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
                        if (!_isTaxi && _recipAvailable) ...[
                          const SizedBox(height: 14),
                          _recipientSection(),
                        ],
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
                          t('Орындаушылар келіседі не өз бағасын ұсынады'),
                          style: TextStyle(
                            color: Gz.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                        if (_minByDistance) ...[
                          const SizedBox(height: 4),
                          Text(
                            '${t('Ең төменгі баға қашықтыққа байланысты')}: '
                            '${fmtT(_vehicle.spec.minPerKm)}/${t('км')}',
                            style: TextStyle(
                              color: Gz.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        if (_hint != null) ...[
                          _priceHint(_hint!),
                          const SizedBox(height: 10),
                        ],
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
                            hintStyle: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Gz.textSecondary,
                            ),
                            prefixIcon: const Icon(Icons.payments_outlined),
                            suffixText: '₸ ',
                            suffixStyle: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: Gz.textSecondary,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(color: Gz.ink, width: 1.6),
                            ),
                          ),
                        ),
                        if (schedEnabled) ...[
                          const SizedBox(height: 14),
                          _scheduleSection(schedMinHours, schedMaxDays),
                        ],
                        const SizedBox(height: 12),
                        // Заңдылық белгісі — ЖАСЫЛ ҚҰСБЕЛГІ (бұрын қара
                        // шаршы Checkbox еді, «қойылмаған» болып көрінетін).
                        // Алғашқы 3 заказдан кейін автоматты қойылады.
                        // ТАКСИДЕ мүлдем көрінбейді: ол ЖҮККЕ қатысты.
                        if (!_isTaxi)
                          ConfirmCheck(
                            value: _legalOk,
                            auto: _legalAuto,
                            onChanged: (v) => setState(() {
                              _legalOk = v;
                              // Қолмен алып тастаса — «автоматты» белгісі
                              // кетеді (қайта қойса қолмен саналады).
                              _legalAuto = false;
                            }),
                            label: Text.rich(
                              TextSpan(
                                style: TextStyle(
                                  fontSize: 13,
                                  height: 1.4,
                                  color: Gz.textSecondary,
                                ),
                                children: [
                                  TextSpan(
                                    text: t(
                                      'Жүгім заңды, тыйым салынған зат жоқ',
                                    ),
                                  ),
                                  const TextSpan(text: '  ·  '),
                                  TextSpan(
                                    text: t('Тізім'),
                                    recognizer: _legalListTap,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: Gz.ink,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        const SizedBox(height: 10),
                        // Шарттар толмайынша батырма СҰР (сары = дайын), ал
                        // астында НЕ жетпейтіні тұрады — қолданушы басып
                        // көріп, қызыл қатеге тірелмейді.
                        BusyButton(
                          label: t('Заказ жариялау'),
                          enabled: _canSubmit,
                          onPressed: _submit,
                        ),
                        const SizedBox(height: 8),
                        Center(
                          child: Text(
                            _missing ??
                                t(
                                  'Төлем — қолма-қол не аударыммен, тікелей '
                                  'орындаушыға',
                                ),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _canSubmit ? Gz.textSecondary : Gz.red,
                              fontWeight: _canSubmit
                                  ? FontWeight.w400
                                  : FontWeight.w700,
                              fontSize: 12,
                            ),
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

/// Сан таңдау чипі (такси заказындағы жолаушы саны). Барлығы бірдей
/// биіктікте (44) әрі бір-бірімен тең енде — қатар әрқашан тегіс.
class _CountChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _CountChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? Gz.inkFill : Gz.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? Gz.yellow : Gz.border,
            width: selected ? 1.8 : 1.2,
          ),
        ),
        child: BtnLabel(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: selected ? Colors.white : Gz.ink,
          ),
        ),
      ),
    );
  }
}

/// Басуға болатын адрес жолы (заказ құру экранында өзгерту үшін).
/// [onRemove] берілсе — оң жақта ✕ шығады (аралық аялдаманы алып тастау).
class _EditableAddr extends StatelessWidget {
  /// Сол жақтағы белгі — [RoutePointMark] (алу / нөмір / финиш).
  final Widget mark;
  final String label;
  final String value;
  final VoidCallback onTap;
  final VoidCallback? onRemove;
  const _EditableAddr({
    required this.mark,
    required this.label,
    required this.value,
    required this.onTap,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(width: 20, child: Center(child: mark)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(fontSize: 11, color: Gz.textSecondary),
                  ),
                  Text(
                    value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.edit, size: 16, color: Gz.textSecondary),
            // Аралық аялдамаға ғана — алып тастау (0047).
            if (onRemove != null)
              IconButton(
                onPressed: onRemove,
                icon: const Icon(Icons.close),
                iconSize: 16,
                color: Gz.textSecondary,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                tooltip: t('Алып тастау'),
              ),
          ],
        ),
      ),
    );
  }
}
