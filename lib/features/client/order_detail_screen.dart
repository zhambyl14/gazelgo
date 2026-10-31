import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/car_colors.dart';
import '../../core/env.dart';
import '../../core/geo.dart';
import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/map_widgets.dart';
import '../../shared/order_live.dart';
import '../../shared/ui/kz_plate.dart';
import '../../shared/widgets.dart';
import '../chat/order_chat_screen.dart';
import '../support/support_screen.dart';
import 'address_picker.dart';
import 'create_order_screen.dart';
import 'executor_sheet.dart';
import 'order_extras_editor.dart';
import 'recipient_card.dart';
import 'searching_view.dart';

/// Клиенттің заказ экраны: ұсыныстар → көліктің тірі картасы мен келу
/// уақыты → барыс → пікір.
class OrderDetailScreen extends StatefulWidget {
  final String orderId;
  const OrderDetailScreen({super.key, required this.orderId});

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  /// Заказ стримі БІР рет құрылады: экран қайта салынғанда (мыс. баптау
  /// жүктелгенде) жаңа сұрау тізбегі басталып кетпеуі үшін.
  late final Stream<Order?> _orderStream = Repo.orderStream(widget.orderId);

  /// Көліктің тірі орны — тек белсенді кезеңде, БІР РЕТ құрылады.
  Stream<Map<String, dynamic>?>? _locStream;

  bool _photosCleaned = false;
  bool _reviewShown = false;

  /// Жаңа клиент фичалары (0060) қосулы ма — модератор баптауынан бір рет
  /// оқылады (ауыстырса, экранды қайта ашқанда көрінеді).
  bool _liveTrackingEnabled = false;
  bool _shareTripEnabled = false;
  bool _repeatOrderEnabled = true;

  /// Таңдаулы/бұғатталған орындаушылар (0079).
  ExecutorPrefs _prefs = const ExecutorPrefs();

  /// Іздеу кезінде заказды өңдеу серверде бар ма (0077
  /// `update_order_details`). Жоқ болса «Заказды өңдеу» көрінбейді.
  bool _editAvailable = false;

  static const _liveStatuses = {'accepted', 'arrived', 'loading', 'in_transit'};

  @override
  void initState() {
    super.initState();
    _loadFeatureFlags();
    _loadPrefs();
    Repo.orderExtrasAvailable().then((v) {
      if (mounted && v != _editAvailable) setState(() => _editAvailable = v);
    });
  }

  Future<void> _loadPrefs() async {
    try {
      final p = await ExecutorPrefs.load();
      if (mounted) setState(() => _prefs = p);
    } catch (_) {
      // Сервер 0079-сіз не желі қатесі — таңдаулылар жай ғана көрінбейді.
    }
  }

  Future<void> _loadFeatureFlags() async {
    try {
      final s = await Repo.settings();
      final live = s['live_tracking'];
      final share = s['share_trip'];
      final repeat = s['repeat_order'];
      if (!mounted) return;
      setState(() {
        _liveTrackingEnabled = live is Map && live['enabled'] == true;
        _shareTripEnabled = share is Map && share['enabled'] == true;
        // Кілт жоқ болса ӘДЕПКІ ҚОСУЛЫ (0060 миграциясында солай жазылған).
        _repeatOrderEnabled = repeat is! Map || repeat['enabled'] != false;
      });
    } catch (_) {
      // Желі қатесінде — бәрі өшулі қалады, экран сынбайды.
    }
  }

  Future<void> _shareTrip(Order o) async {
    try {
      final token = await Repo.getOrderShareToken(o.id);
      final url = '${Env.webBaseUrl}/track/$token';
      await SharePlus.instance.share(
        ShareParams(
          text:
              '${t('Менің тапсырысымның барысын осы сілтемеден қадағалауға болады')}: $url',
        ),
      );
    } catch (e) {
      if (mounted) showSnack(context, errText(e), error: true);
    }
  }

  /// Аяқталған заказдың қысқаша «чегі» — бөлісуге (бухгалтерия, есеп).
  Future<void> _shareReceipt(Order o) async {
    String executor = '';
    if (o.executorId != null) {
      final p = await Repo.profileOf(o.executorId!);
      executor = p?.fullName ?? '';
    }
    final lines = [
      'Tasu · ${t('Заказ')} #${o.id.substring(0, 8).toUpperCase()}',
      '${t('Күні')}: ${fmtDate(o.completedAt ?? o.createdAt)}',
      '${t('Қайдан')}: ${o.fromDisplay}',
      for (var i = 0; i < o.stops.length; i++)
        '${t('Аялдама')} ${i + 1}: ${o.stops[i].display}',
      '${t('Қайда')}: ${o.toDisplay}',
      if (o.distanceKm > 0)
        '${t('Қашықтық')}: ${Geo.formatDistance(o.distanceKm)}',
      '${t('Көлік')}: ${o.vehicleType.label}',
      if (executor.isNotEmpty) '${t('Орындаушы')}: $executor',
      '${t('Баға')}: ${fmtT(o.displayPrice)}',
    ];
    try {
      await SharePlus.instance.share(ShareParams(text: lines.join('\n')));
    } catch (_) {}
  }

  /// Заказ аяқталғанда бағалау терезесін (тегтерімен) бір рет ашамыз.
  void _maybeShowReview(Order o) {
    if (_reviewShown || o.status != 'completed') return;
    _reviewShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      maybeShowReviewDialog(
        context,
        orderId: o.id,
        title: t(
          o.vehicleType.isPassenger
              ? 'Жүргізушіні бағалаңыз'
              : 'Орындаушыны бағалаңыз',
        ),
        tags: o.vehicleType.isPassenger ? kTaxiReviewTags : kExecutorReviewTags,
      );
    });
  }

  /// Заказ аяқталса/бас тартылса — тіркелген фотоларды өшіру (жадты үнемдеу).
  void _maybeCleanupPhotos(Order o) {
    const terminal = ['completed', 'cancelled', 'expired'];
    if (!_photosCleaned && terminal.contains(o.status) && o.photos.isNotEmpty) {
      _photosCleaned = true;
      Repo.deleteOrderPhotos(o.photos);
    }
  }

  /// Дәл осы маршрутпен ЖАҢА заказ ашады (Yandex Go/InDrive-тегі «Тағы да
  /// тапсырыс беру»). Клиент адрестерді қайта іздемейді — «қайдан»/«қайда»/
  /// аралық аялдамалар мен көлік түрі дайын күйде Заказ құру экранына
  /// беріледі, тек бағаны мен жүк сипаттамасын өзі растайды.
  void _reorder(Order o) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CreateOrderScreen(
          from: PickedAddress(
            o.fromAddress,
            LatLng(o.fromLat, o.fromLng),
            o.fromCity,
          ),
          to: PickedAddress(o.toAddress, LatLng(o.toLat, o.toLng), o.toCity),
          stops: [
            for (final s in o.stops)
              PickedAddress(s.address, LatLng(s.lat, s.lng), s.city),
          ],
          vehicleType: o.vehicleType,
        ),
      ),
    );
  }

  /// Іздеу кезінде заказды өңдеу: жүк, түсініктеме, қосымша талаптар (0077).
  Future<void> _edit(Order o) async {
    final res = await showEditOrderSheet(context, o);
    if (res == null || !mounted) return;
    final (cargo, comment, extras) = res;
    final isTaxi = o.vehicleType.isPassenger;
    try {
      await Repo.updateOrderDetails(
        o.id,
        cargo: cargo,
        comment: comment,
        loaders: isTaxi ? null : extras.loaders,
        floorFrom: isTaxi ? null : extras.floorFrom,
        floorTo: isTaxi ? null : extras.floorTo,
        elevator: isTaxi ? null : extras.elevator,
      );
      Repo.orderStream(o.id, fresh: true);
      if (mounted) showSnack(context, t('Заказ жаңартылды'));
    } catch (e) {
      if (mounted) showSnack(context, errText(e), error: true);
    }
  }

  /// Орындаушының профилі (пікірлер, тегтер, ❤ таңдаулы / бұғаттау).
  Future<void> _openExecutor(String executorId) async {
    final kind = await showExecutorSheet(
      context,
      executorId: executorId,
      prefs: _prefs,
    );
    if (kind != null) _loadPrefs();
  }

  static const _clientCancelReasons = [
    'Ойымды өзгерттім',
    'Бағаны қымбат көрдім',
    'Орындаушы тым баяу жауап берді',
    'Қате адрес/жүк енгіздім',
    'Басқа орындаушы таптым',
  ];

  Future<void> _cancel() async {
    final reason = await pickCancelReason(
      context,
      title: t('Заказды тоқтату'),
      presets: [for (final r in _clientCancelReasons) t(r)],
    );
    if (reason == null || !mounted) return;
    try {
      await Repo.cancelOrder(widget.orderId, reason);
      // Экранда қалдырмаймыз — басты бетке қайтамыз (адрестер сол жерде сақталған)
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
        showSnack(context, t('Заказ тоқтатылды'));
      }
    } catch (e) {
      if (mounted) showSnack(context, errText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Order?>(
      stream: _orderStream,
      builder: (context, snap) {
        final o = snap.data;
        if (o == null) {
          return Scaffold(
            appBar: AppBar(title: Text(t('Заказ'))),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        _maybeCleanupPhotos(o);
        _maybeShowReview(o);
        // Іздеу кезінде — толық экранды карта + сүйретілетін панель.
        // Орындаушы табылған сәтте стрим жаңа статус әкеледі де, экран өзі
        // төмендегі әдеттегі түрге ауысады.
        if (o.status == 'searching') {
          return _SearchingScreen(
            order: o,
            prefs: _prefs,
            onCancel: _cancel,
            onShare: _shareTripEnabled ? () => _shareTrip(o) : null,
            onEdit: _editAvailable ? () => _edit(o) : null,
            onOpenExecutor: _openExecutor,
          );
        }
        return Scaffold(
          appBar: AppBar(title: Text(t('Заказ'))),
          body: _details(o),
        );
      },
    );
  }

  /// Іздеуден КЕЙІНГІ барлық статустың (accepted … expired) экраны.
  /// Белсенді кезеңде көліктің тірі орны бір стримнен оқылады.
  Widget _details(Order o) {
    if (_liveTrackingEnabled && _liveStatuses.contains(o.status)) {
      _locStream ??= Repo.orderExecutorLocationStream(o.id);
      return StreamBuilder<Map<String, dynamic>?>(
        stream: _locStream,
        builder: (context, snap) => _detailsBody(o, snap.data),
      );
    }
    return _detailsBody(o, null);
  }

  Widget _detailsBody(Order o, Map<String, dynamic>? loc) {
    final live = _liveStatuses.contains(o.status);
    final lat = (loc?['lat'] as num?)?.toDouble();
    final lng = (loc?['lng'] as num?)?.toDouble();
    final vehicle = lat == null || lng == null ? null : LatLng(lat, lng);
    final at = DateTime.tryParse(loc?['updated_at'] as String? ?? '');

    final info = <Widget>[
      // Тірі карта: көлік өз түрінің белгісімен, бағытымен жайлап жылжиды,
      // камера көлік пен мақсат нүктесін өзі кадрлайды.
      if (live && _liveTrackingEnabled)
        LiveTrackMap(
          order: o,
          vehicle: vehicle,
          heading: (loc?['heading'] as num?)?.toDouble(),
          ageSec: at == null
              ? null
              : DateTime.now().difference(at.toLocal()).inSeconds,
        )
      else
        RouteMap(
          from: LatLng(o.fromLat, o.fromLng),
          to: LatLng(o.toLat, o.toLng),
          stops: o.stops.map((s) => LatLng(s.lat, s.lng)).toList(),
          height: 175,
          fromLabel: o.fromDisplay,
          toLabel: o.toDisplay,
          stopLabels: o.stops.map((s) => s.display).toList(),
          distanceKm: o.distanceKm,
        ),
      const SizedBox(height: 10),
      SectionCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RouteLine(
              from: o.fromDisplay,
              to: o.toDisplay,
              stops: o.stops.map((s) => s.display).toList(),
            ),
            const Divider(height: 20),
            InfoRow(t('Жүк'), o.cargoDesc),
            if (o.comment.isNotEmpty) InfoRow(t('Түсініктеме'), o.comment),
            InfoRow(t('Көлік'), o.vehicleType.label),
            if (o.distanceKm > 0)
              InfoRow(t('Қашықтық'), Geo.formatDistance(o.distanceKm)),
            InfoRow(
              t('Бағыты'),
              o.intercity ? t('Қалааралық (межгород)') : t('Қала ішінде'),
            ),
            if (o.createdAt != null)
              InfoRow(t('Құрылды'), fmtDate(o.createdAt)),
            if (o.hasExtras) ...[
              const SizedBox(height: 6),
              OrderExtrasChips(order: o),
            ],
          ],
        ),
      ),
      if (o.photos.isNotEmpty &&
          !['completed', 'cancelled', 'expired'].contains(o.status)) ...[
        const SizedBox(height: 10),
        OrderPhotosStrip(paths: o.photos),
      ],
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(fmtT(o.displayPrice), style: Gz.moneyXl)),
              if (_shareTripEnabled &&
                  !['cancelled', 'expired'].contains(o.status))
                IconButton(
                  tooltip: t('Сапарды бөлісу'),
                  icon: const Icon(Icons.ios_share_rounded),
                  onPressed: () => _shareTrip(o),
                ),
              StatusChip(o.status, vehicleType: o.vehicleType),
            ],
          ),
          const SizedBox(height: 12),
          // Сапар жүріп жатқанда (орындаушы жолда/келді/тиеу/жолда) ЕҢ
          // маңыздысы — кім келе жатыр, қоңырау/чат, келу уақыты, «Тиеу
          // басталды» растауы: олар картадан ЖОҒАРЫ тұрады.
          // Карта мен маршрут картасы «Келуіне дейін» (ETA) блогының дәл
          // астында, сапар барысы (timeline) алдында тұрады.
          if (live) ...[
            ..._statusSection(o, vehicle, mid: info),
          ] else ...[
            ...info,
            const SizedBox(height: 14),
            ..._statusSection(o, vehicle),
          ],
          const SizedBox(height: 14),
          // Бас тарту: accepted/arrived — процесте болмаса (іздеу кезінде
          // «Заказды тоқтату» — [_SearchingScreen] ішінде).
          if (['accepted', 'arrived'].contains(o.status))
            OutlinedButton.icon(
              onPressed: _cancel,
              style: OutlinedButton.styleFrom(
                foregroundColor: Gz.red,
                side: BorderSide(color: Gz.red),
              ),
              icon: const Icon(Icons.close),
              label: Text(t('Заказды тоқтату')),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// [vehicle] — көліктің тірі орны (бар болса): «N км қалды» үшін.
  ///
  /// [mid] — белсенді сапарда ETA/күту блогынан кейін, барыс (timeline)
  /// алдына қойылатын виджеттер (карта және маршрут картасы).
  List<Widget> _statusSection(
    Order o,
    LatLng? vehicle, {
    List<Widget> mid = const [],
  }) {
    switch (o.status) {
      // Іздеу күйінің өз экраны бар — [_SearchingScreen].
      case 'searching':
        return const [];
      case 'accepted':
      case 'arrived':
      case 'loading':
      case 'in_transit':
        return [
          _ExecutorCard(
            order: o,
            prefs: _prefs,
            onOpen: () => _openExecutor(o.executorId!),
          ),
          // «Орындаушы жолда» кері санағы (уәде еткен минут) + қалған км.
          if (o.status == 'accepted' && o.arriveBy != null) ...[
            const SizedBox(height: 10),
            EtaCountdownCard(
              order: o,
              kmLeft: vehicle == null
                  ? null
                  : Geo.haversineKm(vehicle, LatLng(o.fromLat, o.fromLng)),
            ),
          ],
          // Орындаушы «Келдім» дегенде — күту таймері және клиент тиеуді
          // растайды (0027). Расталмайынша орындаушы «Жолға шықтық» дей
          // алмайды.
          if (o.status == 'arrived') ...[
            const SizedBox(height: 10),
            WaitingTimerCard(
              order: o,
              child: _ConfirmLoadingButton(
                orderId: o.id,
                vehicleType: o.vehicleType,
              ),
            ),
          ],
          if (mid.isNotEmpty) ...[const SizedBox(height: 14), ...mid],
          const SizedBox(height: 14),
          _Timeline(status: o.status, vehicleType: o.vehicleType),
          // Алушы — тек жүк заказына (такси жолаушысында жүк қабылдаушы жоқ).
          if (!o.vehicleType.isPassenger) ...[
            const SizedBox(height: 10),
            RecipientSection(order: o),
          ],
          const SizedBox(height: 10),
          SupportOrderButton(orderId: o.id),
          const SizedBox(height: 10),
          ReportSuspiciousButton(orderId: o.id),
        ];
      case 'completed':
        final favorite = _prefs.favorites.contains(o.executorId);
        return [
          // Аяқталған заказда орындаушының телефоны көрсетілмейді
          // (хабарласу батырмасы жоқ) — тарихта байланыс сақталмайды.
          _ExecutorCard(
            order: o,
            prefs: _prefs,
            showCall: false,
            onOpen: () => _openExecutor(o.executorId!),
          ),
          if (!o.vehicleType.isPassenger) ...[
            const SizedBox(height: 10),
            RecipientSection(order: o),
          ],
          ReviewPrompt(
            orderId: o.id,
            title: t(
              o.vehicleType.isPassenger
                  ? 'Жүргізушіні бағалаңыз'
                  : 'Орындаушыны бағалаңыз',
            ),
            tags: o.vehicleType.isPassenger
                ? kTaxiReviewTags
                : kExecutorReviewTags,
          ),
          if (_prefs.available && !favorite) ...[
            const SizedBox(height: 10),
            GzNotice(
              tone: NoticeTone.accent,
              icon: Icons.favorite_border_rounded,
              title: t('Орындаушы ұнады ма?'),
              message: t(
                'Таңдаулыға қосыңыз — келесі заказыңыз туралы оған '
                'бірінші болып хабар барады.',
              ),
              actionLabel: t('Таңдаулыға қосу'),
              onAction: () async {
                try {
                  await Repo.setExecutorPref(o.executorId!, 'favorite');
                  await _loadPrefs();
                  if (mounted) {
                    showSnack(context, t('Таңдаулыларға қосылды ❤'));
                  }
                } catch (e) {
                  if (mounted) showSnack(context, errText(e), error: true);
                }
              },
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              if (_repeatOrderEnabled) ...[
                Expanded(child: _ReorderButton(onPressed: () => _reorder(o))),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _shareReceipt(o),
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: Text(t('Чек')),
                ),
              ),
            ],
          ),
        ];
      case 'cancelled':
        return [
          GzNotice(
            tone: NoticeTone.danger,
            message: (o.cancelReason?.isNotEmpty ?? false)
                ? '${t('Себебі:')} ${o.cancelReason}'
                : t('Заказ тоқтатылды'),
          ),
          const SizedBox(height: 10),
          if (_repeatOrderEnabled) _ReorderButton(onPressed: () => _reorder(o)),
        ];
      default:
        return [
          GzNotice(
            tone: NoticeTone.neutral,
            icon: Icons.schedule,
            message: t('Заказдың мерзімі өтті — ешкім қабылдамады.'),
          ),
          const SizedBox(height: 10),
          if (_repeatOrderEnabled) _ReorderButton(onPressed: () => _reorder(o)),
        ];
    }
  }
}

/// «Тағы да тапсырыс беру» — дәл осы маршрутпен жаңа заказ ашады
/// (Yandex Go/InDrive-тегі «Заказать снова»). Аяқталған, тоқтатылған және
/// мерзімі өткен заказдарда көрсетіледі — адрестерді қайта іздеудің
/// қажеті жоқ.
class _ReorderButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _ReorderButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: Gz.ink,
        side: const BorderSide(color: Gz.yellowDark, width: 1.6),
      ),
      icon: const Icon(Icons.replay_rounded),
      label: Text(t('Тағы да тапсырыс беру')),
    );
  }
}

/// Орындаушы келгенін клиент растайды: «Тиеу басталды» → status=loading.
/// Осыдан кейін ғана орындаушы «Жолға шықтық» дей алады (0027). Такси
/// заказында (жолаушы тасымалы) «тиеу» орнына «отыру» сөздігі қолданылады —
/// жолаушы жүк емес. Түсіндірмесі мен күту таймері — [WaitingTimerCard].
class _ConfirmLoadingButton extends StatelessWidget {
  final String orderId;
  final VehicleType vehicleType;
  const _ConfirmLoadingButton({
    required this.orderId,
    required this.vehicleType,
  });

  @override
  Widget build(BuildContext context) {
    final isTaxi = vehicleType.isPassenger;
    return BusyButton(
      label: t(isTaxi ? 'Отырғызу басталды' : 'Тиеу басталды'),
      icon: Icons.check_circle,
      color: Gz.green,
      onPressed: () async {
        try {
          await Repo.orderAdvance(orderId, 'loading');
          Repo.orderStream(orderId, fresh: true);
        } catch (e) {
          if (context.mounted) showSnack(context, errText(e), error: true);
        }
      },
    );
  }
}

// ===================== ІЗДЕУ (Tasu стилі) =====================

/// Ұсыныстарды сұрыптау: ұсынылған (таңдаулылар жоғарыда, сосын арзаны),
/// арзанырақ, тез келеді (орындаушы уәде еткен минут), рейтинг.
enum _OfferSort { best, cheap, fast, rating }

/// Заказ «Іздеуде» тұрғанда: толық экранды карта (алу нүктесінде Tasu
/// логотип-пині мен сары толқындар, маршрут жолмен салынған) және
/// сүйретілетін ақ панель — сары күй карточкасы (өткен уақыт, жол бойымен
/// жүріп келе жатқан көлік), ұсыныстар, баға карточкасы, маршрут, жүк,
/// алушы, «Заказды тоқтату».
///
/// Логика: ұсынысты қабылдау/қабылдамау — [_OfferCard], бағаны көтеру —
/// [_RaisePriceHint] (автоматты кеңес те, баға карточкасындағы батырма да),
/// бас тарту — ата-экранның себеп таңдайтын `_cancel` ағыны. Орындаушы
/// табылған сәтте заказ стримі жаңа статус әкеледі де, бұл виджет алынып,
/// әдеттегі экран көрінеді (таймер, ұсыныстар жазылымы `dispose`-та
/// жабылады).
class _SearchingScreen extends StatefulWidget {
  final Order order;
  final ExecutorPrefs prefs;
  final VoidCallback onCancel;

  /// `null` — «Бөлісу» фичасы өшулі (модератор баптауы).
  final VoidCallback? onShare;

  /// Жүк, түсініктеме, қосымша талаптарды өңдеу. `null` — сервер 0077-сіз
  /// (өңдеу RPC-і жоқ), батырма көрінбейді.
  final VoidCallback? onEdit;

  /// Орындаушының профилі терезесі (❤ / бұғаттау).
  final ValueChanged<String> onOpenExecutor;

  const _SearchingScreen({
    required this.order,
    required this.prefs,
    required this.onCancel,
    required this.onOpenExecutor,
    this.onEdit,
    this.onShare,
  });

  @override
  State<_SearchingScreen> createState() => _SearchingScreenState();
}

class _SearchingScreenState extends State<_SearchingScreen> {
  /// Панельді төмен түсіргенде тек сары күй карточкасы қалады — карта
  /// толық дерлік ашылады.
  static const _minSize = 0.24;
  static const _initialSize = 0.47;

  /// Алғашқы ұсыныс келгенде панель осы биіктікке дейін өзі көтеріледі.
  static const _offersSize = 0.64;

  final _sheet = DraggableScrollableController();
  final _map = MapController();

  /// Панельдің ағымдағы биіктігі (үлесі) — OSM жазуын панельдің дәл
  /// үстінде ұстау үшін.
  final _extent = ValueNotifier<double>(_initialSize);

  /// Іздеу басталғаннан бергі секунд. Секунд сайын тек таймер мәтіні
  /// қайта салынады — бүкіл экран емес.
  final _elapsed = ValueNotifier<int>(0);

  /// Заказдың БАРЛЫҚ ұсынысы (pending + rejected) — бас тарту санын
  /// «бағаны көтеріңіз» кеңесі үшін де білу керек.
  final _allOffers = ValueNotifier<List<Offer>>(const []);

  _OfferSort _sort = _OfferSort.best;

  /// Ұсыныс иелерінің профильдері (рейтинг бойынша сұрыптау үшін).
  final Map<String, Profile> _profiles = {};
  final Set<String> _requested = {};

  /// Маршруттың нақты жол геометриясы (бос — әзірге доға).
  List<LatLng> _road = const [];

  /// Клиент картаны өзі жылжытты ма — жылжытса, жол келгенде камераны
  /// қайта кадрлап, оның қарап тұрған жерін «тартып» әкетпейміз.
  bool _userMoved = false;
  bool _mapReady = false;
  double _screenH = 0;

  final DateTime _openedAt = DateTime.now();
  Timer? _ticker;
  StreamSubscription<List<Offer>>? _offersSub;

  List<LatLng> get _waypoints {
    final o = widget.order;
    return [
      LatLng(o.fromLat, o.fromLng),
      for (final st in o.stops) LatLng(st.lat, st.lng),
      LatLng(o.toLat, o.toLng),
    ];
  }

  @override
  void initState() {
    super.initState();
    _tick();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    // Стрим БІР рет тыңдалады (build ішінде құрылса, әр 3 секундтағы
    // заказ жаңартуында сұрау тізбегі қайта басталатын еді).
    _offersSub = Repo.offersStream(
      widget.order.id,
    ).listen(_onOffers, onError: (_) {});
    Geo.routeVia(_waypoints).then((r) {
      if (!mounted || !r.onRoad) return;
      setState(() => _road = r.points);
      if (!_userMoved) _fit();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _offersSub?.cancel();
    _sheet.dispose();
    _extent.dispose();
    _elapsed.dispose();
    _allOffers.dispose();
    super.dispose();
  }

  void _tick() {
    final start = widget.order.createdAt ?? _openedAt;
    final sec = DateTime.now().difference(start).inSeconds;
    // Құрылғы сағаты сервердікінен артта қалса — теріс сан шықпасын.
    _elapsed.value = sec < 0 ? 0 : sec;
  }

  /// Көрсетілетін ұсыныстар: тек күтудегілер, бұғатталған орындаушының
  /// ұсынысы жасырылады (ол бұғатқа дейін жіберілген болуы мүмкін).
  List<Offer> _pendingOf(List<Offer> all) => [
    for (final of in all)
      if (of.status == 'pending' &&
          !widget.prefs.blocks.contains(of.executorId))
        of,
  ];

  void _onOffers(List<Offer> all) {
    if (!mounted) return;
    final before = _pendingOf(_allOffers.value).length;
    _allOffers.value = all;
    final pending = _pendingOf(all);
    _ensureProfiles(pending);
    // Алғашқы ұсыныс келгенде панель өзі ашылады — ұсыныс көзден тыс
    // (панельдің төменгі жағында) қалып қоймасын.
    if (before == 0 &&
        pending.isNotEmpty &&
        _sheet.isAttached &&
        _sheet.size < _offersSize - 0.02) {
      _sheet.animateTo(
        _offersSize,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _ensureProfiles(List<Offer> offers) {
    final missing = [
      for (final of in offers)
        if (!_requested.contains(of.executorId)) of.executorId,
    ];
    if (missing.isEmpty) return;
    _requested.addAll(missing);
    Repo.profilesByIds(missing).then((m) {
      if (mounted) setState(() => _profiles.addAll(m));
    }, onError: (_) {});
  }

  List<Offer> _sorted(List<Offer> list) {
    final fav = widget.prefs.favorites;
    int byPrice(Offer a, Offer b) => a.price.compareTo(b.price);
    int byEta(Offer a, Offer b) => (a.etaMin ?? 999).compareTo(b.etaMin ?? 999);
    double rating(Offer o) =>
        _profiles[o.executorId]?.ratingAs('executor') ?? 0;
    final out = List.of(list);
    switch (_sort) {
      case _OfferSort.best:
        out.sort((a, b) {
          final fa = fav.contains(a.executorId) ? 0 : 1;
          final fb = fav.contains(b.executorId) ? 0 : 1;
          return fa != fb ? fa.compareTo(fb) : byPrice(a, b);
        });
      case _OfferSort.cheap:
        out.sort(byPrice);
      case _OfferSort.fast:
        out.sort((a, b) {
          final c = byEta(a, b);
          return c != 0 ? c : byPrice(a, b);
        });
      case _OfferSort.rating:
        out.sort((a, b) {
          final c = rating(b).compareTo(rating(a));
          return c != 0 ? c : byPrice(a, b);
        });
    }
    return out;
  }

  /// Картаның төменгі шегінісі: панельдің бастапқы биіктігі картаның
  /// астыңғы жиегінен қаншалық жоғары шығатыны + аздаған ауа.
  EdgeInsets _fitPadding() {
    final top = MediaQuery.paddingOf(context).top + 84;
    final bottom = _screenH * (_initialSize - _minSize) + 28 + 36;
    return EdgeInsets.fromLTRB(56, top, 56, bottom);
  }

  List<LatLng> get _framePoints => [..._waypoints, ..._road];

  void _fit() {
    if (!_mapReady || !mounted) return;
    final pts = _framePoints;
    if (_isPoint(pts)) {
      _map.move(pts.first, 15.5);
      return;
    }
    _map.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(pts),
        padding: _fitPadding(),
        maxZoom: 16.5,
      ),
    );
  }

  static bool _isPoint(List<LatLng> pts) {
    final b = LatLngBounds.fromPoints(pts);
    return (b.north - b.south).abs() < 1e-6 && (b.east - b.west).abs() < 1e-6;
  }

  Future<void> _openRaise(Order o) async {
    await showGzSheet<void>(
      context,
      builder: (ctx) => GzSheetBody(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: _RaisePriceHint(
          order: o,
          manual: true,
          onRaised: () => Navigator.of(ctx).maybePop(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final scheduled = o.isScheduledPending;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: Gz.bg,
        body: LayoutBuilder(
          builder: (context, box) {
            final h = box.maxHeight;
            _screenH = h;
            final topPad = MediaQuery.paddingOf(context).top;
            // Панель ең жоғары көтерілгенде де «Артқа» батырмасын жаппауы
            // керек — шегі экран биіктігінен есептеледі.
            final maxSize = ((h - topPad - 68) / h).clamp(0.6, 0.9);
            // Карта панельдің ең төменгі күйінің астына сәл кіреді (панельдің
            // дөңгелек бұрыштарының артында бос фон көрінбеуі үшін).
            final mapBottom = h * _minSize - 28;
            return Stack(
              children: [
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  bottom: mapBottom,
                  child: _mapView(o, scheduled),
                ),
                // Жоғарғы перде — батырмалар ашық тайлда да анық көрінеді.
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Container(
                      height: topPad + 64,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Gz.bg.withValues(alpha: 0.85),
                            Gz.bg.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // OSM тайлдарының дерек көзі (OSMF талабы) — панельдің үстінде.
                ValueListenableBuilder<double>(
                  valueListenable: _extent,
                  builder: (_, ext, child) => ext > 0.7
                      ? const SizedBox.shrink()
                      : Positioned(
                          left: 12,
                          bottom: h * ext + 10,
                          child: child!,
                        ),
                  child: const _OsmAttribution(),
                ),
                // «Шақыру нүктесіне оралу» — карта еркін жылжиды, клиент
                // басқа жерге кетіп қалса, бір басумен алу нүктесіне қайтады.
                ValueListenableBuilder<double>(
                  valueListenable: _extent,
                  builder: (_, ext, child) => ext > 0.7
                      ? const SizedBox.shrink()
                      : Positioned(
                          right: 12,
                          bottom: h * ext + 12,
                          child: child!,
                        ),
                  child: SearchMapButton(
                    icon: Icons.my_location_rounded,
                    tooltip: t('Шақыру нүктесіне оралу'),
                    onTap: () => _map.move(LatLng(o.fromLat, o.fromLng), 16),
                  ),
                ),
                NotificationListener<DraggableScrollableNotification>(
                  onNotification: (n) {
                    _extent.value = n.extent;
                    return false;
                  },
                  child: DraggableScrollableSheet(
                    controller: _sheet,
                    initialChildSize: _initialSize,
                    minChildSize: _minSize,
                    // Саусақты жібергенде панель үш күйдің біріне «қонады»:
                    // жиналған (тек күй) / қалыпты / толық ашық.
                    snap: true,
                    snapSizes: const [_initialSize],
                    maxChildSize: maxSize,
                    builder: (context, scroll) =>
                        _sheetBody(o, scroll, scheduled),
                  ),
                ),
                // Батырмалар ЕҢ ҮСТІНДЕ: панель ешқашан оларды жаппайды.
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: Row(
                        children: [
                          SearchMapButton(
                            icon: Icons.arrow_back_rounded,
                            tooltip: MaterialLocalizations.of(
                              context,
                            ).backButtonTooltip,
                            onTap: () => Navigator.of(context).maybePop(),
                          ),
                          const Spacer(),
                          if (widget.onShare != null)
                            SearchMapButton(
                              icon: Icons.ios_share_rounded,
                              tooltip: t('Сапарды бөлісу'),
                              onTap: widget.onShare!,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Толық экранды карта: маршрут (жолмен), аялдамалар мен соңғы нүкте
  /// (қосымшаның бірыңғай белгілері), алу нүктесінде — Tasu маягы.
  Widget _mapView(Order o, bool scheduled) {
    final pickup = LatLng(o.fromLat, o.fromLng);
    final waypoints = _waypoints;
    final single = _isPoint(waypoints);
    return FlutterMap(
      mapController: _map,
      options: gzMapOptions(
        onMapReady: () {
          _mapReady = true;
          if (_road.isNotEmpty && !_userMoved) _fit();
        },
        onPositionChanged: (_, hasGesture) {
          if (hasGesture) _userMoved = true;
        },
        initialCenter: pickup,
        initialZoom: 15.5,
        initialCameraFit: single
            ? null
            : CameraFit.bounds(
                bounds: LatLngBounds.fromPoints(waypoints),
                padding: _fitPadding(),
                maxZoom: 16.5,
              ),
      ),
      children: [
        osmTileLayer(),
        if (!single)
          PolylineLayer(
            polylines: routePolylines(
              _road.isNotEmpty ? _road : waypoints,
              onRoad: _road.isNotEmpty,
            ),
          ),
        MarkerLayer(
          markers: [
            for (var i = 0; i < o.stops.length; i++)
              pointMarker(
                LatLng(o.stops[i].lat, o.stops[i].lng),
                color: Gz.violet,
                number: i + 1,
                size: 27,
              ),
            pointMarker(LatLng(o.toLat, o.toLng), color: Gz.red, size: 32),
            // Жоспарланған тапсырыс әлі ІЗДЕЛМЕЙДІ (орындаушыларға
            // көрінбейді) — толқындар оны адастырар еді, тек тыныш пин.
            Marker(
              point: pickup,
              width: TasuPickupBeacon.width,
              height: TasuPickupBeacon.height,
              alignment: Alignment.center,
              child: TasuPickupBeacon(active: !scheduled),
            ),
          ],
        ),
      ],
    );
  }

  Widget _sheetBody(Order o, ScrollController scroll, bool scheduled) {
    return Container(
      decoration: BoxDecoration(
        color: Gz.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(Gz.rXl)),
        boxShadow: [
          BoxShadow(
            color: Gz.shadowWide,
            blurRadius: 24,
            offset: Offset(0, -4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      // SingleChildScrollView (ListView емес): ішіндегі күйлі виджеттер
      // (бағаны көтеру снузы, батырмалардың «жүктелуде» күйі) панель
      // айналдырылғанда жойылып кетпейді.
      child: SingleChildScrollView(
        controller: scroll,
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.paddingOf(context).bottom,
        ),
        child: ValueListenableBuilder<List<Offer>>(
          valueListenable: _allOffers,
          builder: (context, all, _) => _sheetContent(o, all, scheduled),
        ),
      ),
    );
  }

  Widget _sheetContent(Order o, List<Offer> all, bool scheduled) {
    final offers = _sorted(_pendingOf(all));
    final rejectedCount = all.where((of) => of.status == 'rejected').length;
    final ageMin = o.createdAt == null
        ? 0
        : DateTime.now().difference(o.createdAt!).inMinutes;
    // Кеңес: 5+ бас тарту немесе 15+ мин жауапсыз → бағаны көтеру
    final suggestRaise =
        !scheduled && (rejectedCount >= 5 || (offers.isEmpty && ageMin >= 15));
    // «Тез келеді» — тек орындаушылар келу уақытын көрсеткенде (0075).
    final hasEta = offers.any((of) => of.etaMin != null);

    final meta = [
      if (o.distanceKm > 0) Geo.formatDistance(o.distanceKm),
      o.intercity ? t('Қалааралық') : t('Қала ішінде'),
    ].join(' · ');

    final status = scheduled
        ? SearchStatusCard(
            color: Gz.violet.withValues(alpha: 0.14),
            title: t('Жоспарланған тапсырыс'),
            subtitle: t('Орындаушыларға көрінбейді'),
            bottom: Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: Row(
                children: [
                  Icon(Icons.event_rounded, size: 18, color: Gz.violet),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      fmtDate(o.scheduledAt),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: Gz.violet,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
        : SearchStatusCard(
            badge: offers.isEmpty ? null : SearchCountBadge(offers.length),
            title: offers.isEmpty
                ? t('Орындаушы іздеп жатырмыз')
                : t('Ұсыныстар келді'),
            subtitle: offers.isEmpty
                ? t(
                    'Заказыңыз сәйкес орындаушыларға жіберілді — '
                    'ұсыныстары осында шығады.',
                  )
                : t('Ең қолайлы ұсынысты таңдаңыз'),
            trailing: SearchTimerChip(seconds: _elapsed),
            bottom: SearchRoadStrip(vehicle: o.vehicleType),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SearchSheetHandle(),
        status,
        const SizedBox(height: 12),
        // ── Ұсыныстар ────────────────────────────────────────────────
        // Кілттер: тізім өзгергенде кеңестің (снуз) және батырмалардың
        // күйі басқа карточкаға «ауысып» кетпеуі үшін.
        if (suggestRaise)
          _RaisePriceHint(key: const ValueKey('raise-hint'), order: o),
        if (offers.length > 1) ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final s in _OfferSort.values)
                  if (s != _OfferSort.fast || hasEta)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(switch (s) {
                          _OfferSort.best => t('Ұсынылған'),
                          _OfferSort.cheap => t('Арзанырақ'),
                          _OfferSort.fast => t('Тез келеді'),
                          _OfferSort.rating => t('Рейтинг'),
                        }),
                        selected: _sort == s,
                        onSelected: (_) => setState(() => _sort = s),
                      ),
                    ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        for (final offer in offers) ...[
          _OfferCard(
            key: ValueKey('offer-${offer.id}'),
            offer: offer,
            clientPrice: o.clientPrice,
            favorite: widget.prefs.favorites.contains(offer.executorId),
            onOpenExecutor: () => widget.onOpenExecutor(offer.executorId),
          ),
          const SizedBox(height: 8),
        ],
        if (offers.isNotEmpty) const SizedBox(height: 4),
        // ── Баға, маршрут, жүк ───────────────────────────────────────
        SearchPriceCard(
          vehicle: o.vehicleType,
          meta: meta,
          price: fmtT(o.clientPrice ?? o.displayPrice),
          onRaise: () => _openRaise(o),
        ),
        const SizedBox(height: 10),
        SectionCard(
          padding: const EdgeInsets.all(14),
          child: RouteLine(
            from: o.fromDisplay,
            to: o.toDisplay,
            stops: o.stops.map((st) => st.display).toList(),
          ),
        ),
        // Жүк, түсініктеме, қосымша талаптар — іздеу кезінде өңделеді.
        if (o.cargoDesc.isNotEmpty ||
            o.comment.isNotEmpty ||
            o.hasExtras ||
            widget.onEdit != null) ...[
          const SizedBox(height: 10),
          SectionCard(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (o.cargoDesc.isNotEmpty) InfoRow(t('Жүк'), o.cargoDesc),
                if (o.comment.isNotEmpty) InfoRow(t('Түсініктеме'), o.comment),
                if (o.hasExtras) ...[
                  const SizedBox(height: 6),
                  OrderExtrasChips(order: o),
                  const SizedBox(height: 4),
                ],
                if (widget.onEdit != null)
                  TextButton.icon(
                    onPressed: widget.onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: Text(t('Заказды өңдеу')),
                  ),
              ],
            ),
          ),
        ],
        if (o.photos.isNotEmpty) ...[
          const SizedBox(height: 12),
          OrderPhotosStrip(paths: o.photos),
        ],
        // Алушы және жеткізу коды (0076) — сервер дайын болса ғана; такси
        // жолаушысында жүк алушы жоқ.
        if (!o.vehicleType.isPassenger) ...[
          const SizedBox(height: 10),
          RecipientSection(order: o),
        ],
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: widget.onCancel,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            foregroundColor: Gz.red,
            side: BorderSide(color: Gz.red),
          ),
          icon: const Icon(Icons.close_rounded),
          label: Text(t('Заказды тоқтату')),
        ),
      ],
    );
  }
}

/// «© OpenStreetMap» — тайлдарды пайдаланғанда сілтеме міндетті.
class _OsmAttribution extends StatelessWidget {
  const _OsmAttribution();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Gz.surface.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(Gz.rXs),
        ),
        child: Text(
          '© OpenStreetMap',
          style: TextStyle(
            fontSize: 10,
            height: 1.1,
            fontWeight: FontWeight.w700,
            color: Gz.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// «Бағаны сәл көтеріңіз» кеңесі + жылдам көтеру.
///
/// Дайын қадамдар КІШІ (100–500) — клиентке 1000/2000 деген секірістер тым
/// үлкен. Оның үстіне клиент өз қалауынша, 100-ден қадаммен, кез келген
/// сомаға көтере алады. Бір рет көтерген соң кеңес БІРАЗ УАҚЫТҚА жасырылады
/// (жаңа ұсыныс күтуге мүмкіндік беру үшін) — тек `order.createdAt`-қа
/// қарасақ, баға көтерілсе де «ескі» деп қала беретін, сол себепті жасыру
/// мерзімін осы виджеттің ӨЗІ (жергілікті `_snoozedUntil`) есептейді.
class _RaisePriceHint extends StatefulWidget {
  final Order order;

  /// `true` — клиент «Бағаны көтеру» батырмасын өзі басты (төменгі
  /// парақта ашылады): тақырып пен түсініктеме «кеңес» емес, әрекет.
  final bool manual;

  /// Баға сәтті көтерілгенде (мыс. парақты жабу үшін).
  final VoidCallback? onRaised;
  const _RaisePriceHint({
    super.key,
    required this.order,
    this.manual = false,
    this.onRaised,
  });

  @override
  State<_RaisePriceHint> createState() => _RaisePriceHintState();
}

class _RaisePriceHintState extends State<_RaisePriceHint> {
  static const _presets = [100, 200, 300, 500];
  static const _snoozeDuration = Duration(minutes: 15);

  DateTime? _snoozedUntil;
  final _customCtrl = TextEditingController(text: '100');
  bool _busy = false;

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  bool get _snoozed =>
      _snoozedUntil != null && DateTime.now().isBefore(_snoozedUntil!);

  void _stepCustom(int delta) {
    final v = (int.tryParse(_customCtrl.text.trim()) ?? 100) + delta;
    setState(() => _customCtrl.text = '${v < 100 ? 100 : v}');
  }

  /// Соңғы сәтті көтерілген баға. Заказ стримі жаңа бағаны бірнеше
  /// секундтан кейін ғана әкеледі — сол аралықта қайта басса, ескі бағаға
  /// емес, ЖАҢАСЫНА қосылуы үшін.
  int? _lastPrice;

  int? get _basePrice {
    final cur =
        _lastPrice ?? widget.order.clientPrice ?? widget.order.displayPrice;
    return (cur == null || cur <= 0) ? null : cur;
  }

  Future<void> _raise(int add) async {
    // Негіз — клиенттің ағымдағы бағасы. Бұрын `clientPrice ?? 0` еді:
    // баға бос болса «+100» бағаны 100 ₸-ге ТҮСІРІП жіберетін.
    final cur =
        _lastPrice ?? widget.order.clientPrice ?? widget.order.displayPrice;
    if (cur == null || cur <= 0) return;
    setState(() => _busy = true);
    try {
      await Repo.updateOrderPrice(widget.order.id, cur + add);
      _lastPrice = cur + add;
      Repo.orderStream(widget.order.id, fresh: true);
      if (mounted) {
        setState(() => _snoozedUntil = DateTime.now().add(_snoozeDuration));
        showSnack(context, '${t('Жаңа баға:')} ${fmtT(cur + add)}');
        widget.onRaised?.call();
      }
    } catch (e) {
      if (mounted) showSnack(context, errText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Тек виджетті «алып тастамай» тұрамыз — StreamBuilder бірнеше секунд
    // сайын қайта саламын дегендіктен, снуз мерзімі біткенде өзі қайта
    // пайда болады (бөлек Timer қажет емес).
    if (_snoozed && !widget.manual) return const SizedBox.shrink();
    final custom = int.tryParse(_customCtrl.text.trim()) ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GzNotice(
        tone: NoticeTone.warning,
        icon: widget.manual ? Icons.trending_up_rounded : Icons.lightbulb,
        title: widget.manual
            ? t('Бағаны көтеру')
            : t('Бағаны сәл көтеріп көріңіз'),
        message: widget.manual
            ? t('Баға жоғары болса, орындаушылар тезірек жауап береді.')
            : t(
                'Ұзақ уақыт жауап жоқ немесе орындаушылар келіспей жатыр. '
                'Бағаны көтерсеңіз, тезірек табыласыз.',
              ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final add in _presets)
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    onPressed: _busy ? null : () => _raise(add),
                    child: Text('+${fmtT(add)}'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              t('Немесе өзіңіз көтеріңіз'),
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: Gz.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                GzStepButton(
                  icon: Icons.remove_rounded,
                  size: 40,
                  onTap: _busy ? null : () => _stepCustom(-100),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _customCtrl,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 8,
                      ),
                      prefixText: '+ ',
                      suffixText: '₸',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GzStepButton(
                  icon: Icons.add_rounded,
                  size: 40,
                  onTap: _busy ? null : () => _stepCustom(100),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: (_busy || custom < 100)
                      ? null
                      : () => _raise(custom),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  child: Text(t('Қолдану')),
                ),
              ],
            ),
            if (custom >= 100 && _basePrice != null) ...[
              const SizedBox(height: 8),
              Text(
                '${t('Бағаға қосылады')}: +${fmtT(custom)}  ·  '
                '${fmtT(_basePrice!)} → ${fmtT(_basePrice! + custom)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OfferCard extends StatelessWidget {
  final Offer offer;
  final int? clientPrice;
  final bool favorite;
  final VoidCallback onOpenExecutor;
  const _OfferCard({
    super.key,
    required this.offer,
    required this.onOpenExecutor,
    this.clientPrice,
    this.favorite = false,
  });

  @override
  Widget build(BuildContext context) {
    final samePrice = clientPrice != null && offer.price == clientPrice;
    final note = offer.note.trim();
    return SectionCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(Gz.rSm),
                  onTap: onOpenExecutor,
                  child: _ExecutorBrief(
                    executorId: offer.executorId,
                    favorite: favorite,
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    fmtT(offer.price),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: samePrice ? Gz.green : Gz.ink,
                    ),
                  ),
                  Text(
                    samePrice ? t('Бағаңызға келісті') : t('Қарсы ұсыныс'),
                    style: TextStyle(
                      fontSize: 12,
                      color: samePrice ? Gz.green : Gz.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          // Келу уақыты — орындаушының ӨЗІ ұсыныспен бірге таңдаған минуты
          // (0075), ойдан шығарылған болжам емес.
          if (offer.etaMin != null || note.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (offer.etaMin != null)
                  InfoChip(
                    icon: Icons.timer_outlined,
                    color: Gz.blue,
                    text: '~${offer.etaMin} ${t('мин')}',
                  ),
                if (note.isNotEmpty)
                  Text(
                    '«$note»',
                    style: TextStyle(
                      color: Gz.textSecondary,
                      fontStyle: FontStyle.italic,
                      fontSize: 13,
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    // Ұзын мәтін («Отклонить») тар батырмада сынбауы үшін
                    // көлденең padding кішірейтілген.
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    foregroundColor: Gz.red,
                    side: BorderSide(color: Gz.border),
                  ),
                  onPressed: () async {
                    try {
                      await Repo.rejectOffer(offer.id);
                      Repo.offersStream(offer.orderId, fresh: true);
                    } catch (e) {
                      if (context.mounted) {
                        showSnack(context, errText(e), error: true);
                      }
                    }
                  },
                  child: BtnLabel(t('Қабылдамау')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: BusyButton(
                  label: '${t('Қабылдау')} · ${fmtT(offer.price)}',
                  onPressed: () async {
                    try {
                      await Repo.acceptOffer(offer.id);
                      Repo.orderStream(offer.orderId, fresh: true);
                    } catch (e) {
                      if (context.mounted) {
                        showSnack(context, errText(e), error: true);
                      }
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Орындаушының қысқа профилі (аты, рейтинг, көлігі). Басса — толық
/// профиль терезесі (пікірлер, тегтер, ❤).
///
/// Профиль БІР рет жүктеледі: ұсыныстар/заказ стримі әр 4 секунд сайын
/// панельді қайта салады — әр жолы желіге қайта сұрау жібермеуі үшін.
class _ExecutorBrief extends StatefulWidget {
  final String executorId;
  final bool favorite;
  const _ExecutorBrief({required this.executorId, this.favorite = false});

  @override
  State<_ExecutorBrief> createState() => _ExecutorBriefState();
}

class _ExecutorBriefState extends State<_ExecutorBrief> {
  late Future<List<Object?>> _future = _load();

  Future<List<Object?>> _load() => Future.wait<Object?>([
    Repo.profileOf(widget.executorId),
    Repo.executorProfileOf(widget.executorId),
  ]);

  @override
  void didUpdateWidget(_ExecutorBrief old) {
    super.didUpdateWidget(old);
    if (old.executorId != widget.executorId) _future = _load();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Object?>>(
      future: _future,
      builder: (context, snap) {
        final p = snap.data?[0] as Profile?;
        final ep = snap.data?[1] as ExecutorProfile?;
        return Row(
          children: [
            InitialsAvatar(
              p?.fullName ?? '?',
              radius: 20,
              imageUrl: p?.avatarUrl,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          p?.fullName ?? '…',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      if (widget.favorite) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.favorite_rounded, size: 15, color: Gz.red),
                      ],
                      const SizedBox(width: 2),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: Gz.textSecondary,
                      ),
                    ],
                  ),
                  // Клиент ОРЫНДАУШЫНЫ көреді → орындаушылық рейтинг/рейс
                  // (қос рөл, 0046: адамның клиенттік бағасы бөлек жүреді).
                  Row(
                    children: [
                      RatingStars(
                        p?.ratingAs('executor') ?? 0,
                        count: p?.ratingCountAs('executor') ?? 0,
                        size: 13,
                      ),
                      if ((p?.tripsAs('executor') ?? 0) > 0)
                        Text(
                          '  · ${p!.tripsAs('executor')} ${t('рейс')}',
                          style: Gz.caption,
                        ),
                    ],
                  ),
                  // Ұсыныс кезінде көлік нөмірі көрсетілмейді (тек маркасы)
                  if (ep != null)
                    Text(
                      ep.vehicleTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Gz.caption,
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ===================== ОРЫНДАУШЫ КАРТАСЫ =====================

/// Сапар кезіндегі орындаушы: басса — профилі (❤ / бұғаттау), оң жақта
/// чат (0078) және қоңырау.
class _ExecutorCard extends StatelessWidget {
  final Order order;
  final ExecutorPrefs prefs;
  final bool showCall;
  final VoidCallback onOpen;
  const _ExecutorCard({
    required this.order,
    required this.prefs,
    required this.onOpen,
    this.showCall = true,
  });

  @override
  Widget build(BuildContext context) {
    final executorId = order.executorId!;
    return FutureBuilder(
      future: Future.wait([
        Repo.profileOf(executorId),
        Repo.executorProfileOf(executorId),
      ]),
      builder: (context, snap) {
        final p = snap.data?[0] as Profile?;
        final ep = snap.data?[1] as ExecutorProfile?;
        final favorite = prefs.favorites.contains(executorId);
        // Нөмір мен түс — клиент көлікті көше тауып алуы үшін: тақташа
        // түрінде және түс үлгісімен (жаяу курьерде көлік жоқ).
        final showCar =
            ep != null &&
            !ep.onFoot &&
            (ep.vehiclePlate.trim().isNotEmpty ||
                carColorFor(ep.vehicleColor) != null);
        return SectionCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(Gz.rSm),
                      onTap: onOpen,
                      child: Row(
                        children: [
                          InitialsAvatar(
                            p?.fullName ?? '?',
                            radius: 24,
                            imageUrl: p?.avatarUrl,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        p?.fullName ?? t('Орындаушы'),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Gz.h3,
                                      ),
                                    ),
                                    if (favorite) ...[
                                      const SizedBox(width: 4),
                                      Icon(
                                        Icons.favorite_rounded,
                                        size: 15,
                                        color: Gz.red,
                                      ),
                                    ],
                                  ],
                                ),
                                // Орындаушының РӨЛДІК рейтингі (қос рөл, 0046).
                                Row(
                                  children: [
                                    RatingStars(
                                      p?.ratingAs('executor') ?? 0,
                                      count: p?.ratingCountAs('executor') ?? 0,
                                      size: 14,
                                    ),
                                    if ((p?.tripsAs('executor') ?? 0) > 0)
                                      Text(
                                        '  · ${p!.tripsAs('executor')} ${t('рейс')}',
                                        style: Gz.caption,
                                      ),
                                  ],
                                ),
                                if (ep != null && ep.vehicleTitle.isNotEmpty)
                                  Text(
                                    ep.vehicleTitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Gz.caption,
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  OrderChatButton(
                    order: order,
                    title: p?.fullName ?? t('Орындаушы'),
                    myRole: 'client',
                  ),
                  if (showCall && p != null && p.phone.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    IconButton.filled(
                      tooltip: t('Қоңырау'),
                      style: IconButton.styleFrom(
                        backgroundColor: Gz.green,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => callPhone(context, p.phone),
                      icon: const Icon(Icons.call),
                    ),
                  ],
                ],
              ),
              if (showCar) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    KzPlate(ep.vehiclePlate),
                    CarColorChip(ep.vehicleColor),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ===================== БАРЫС (timeline) =====================
class _Timeline extends StatelessWidget {
  final String status;
  final VehicleType vehicleType;
  const _Timeline({required this.status, required this.vehicleType});

  @override
  Widget build(BuildContext context) {
    final steps = [
      for (final s in tripSteps(taxi: vehicleType.isPassenger)) (s.$1, t(s.$2)),
    ];
    final idx = steps.indexWhere((s) => s.$1 == status);
    return SectionCard(
      child: Column(
        children: [
          for (var i = 0; i < steps.length; i++)
            Row(
              children: [
                Column(
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: i <= idx ? Gz.green : Gz.bg,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: i <= idx ? Gz.green : Gz.border,
                        ),
                      ),
                      child: i < idx
                          ? const Icon(
                              Icons.check,
                              size: 14,
                              color: Colors.white,
                            )
                          : i == idx
                          ? const Icon(
                              Icons.radio_button_checked,
                              size: 14,
                              color: Colors.white,
                            )
                          : null,
                    ),
                    if (i < steps.length - 1)
                      Container(
                        width: 2,
                        height: 18,
                        color: i < idx ? Gz.green : Gz.border,
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Text(
                    steps[i].$2,
                    style: TextStyle(
                      fontWeight: i == idx ? FontWeight.w800 : FontWeight.w500,
                      color: i <= idx ? Gz.ink : Gz.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
