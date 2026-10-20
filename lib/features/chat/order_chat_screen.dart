import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';

/// Заказ чаты (0078): клиент ↔ орындаушы. Модератор барлық чатты оқиды
/// және қажет болса өзі жазады («Модератор» белгісімен).
///
/// Чаттың басында ашық ескерту тұрады: хабарларды қауіпсіздік үшін
/// модератор көре алады — пайдаланушы мұны білуі керек.
class OrderChatScreen extends StatefulWidget {
  final String orderId;

  /// Екінші тараптың аты (тақырыпта). Push-тан ашылғанда белгісіз —
  /// заказдан өзі анықталады.
  final String? title;

  /// 'client' | 'executor' | 'moderator'. Бос болса — заказдағы рөлім
  /// бойынша (клиент/орындаушы, әйтпесе модератор).
  final String? myRole;

  const OrderChatScreen({
    super.key,
    required this.orderId,
    this.title,
    this.myRole,
  });

  @override
  State<OrderChatScreen> createState() => _OrderChatScreenState();
}

class _OrderChatScreenState extends State<OrderChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  late final Stream<List<OrderMessage>> _stream = Repo.orderMessagesStream(
    widget.orderId,
  );
  late final Stream<Order?> _orderStream = Repo.orderStream(widget.orderId);
  bool _sending = false;
  int _lastCount = -1;
  late String? _role = widget.myRole;
  late String? _title = widget.title;

  bool get _isModerator => _role == 'moderator';

  List<String> get _phrases => switch (_role) {
    'executor' => [
      t('Жолдамын'),
      t('5 минутта келемін'),
      t('Келдім, күтіп тұрмын'),
      t('Подъезд нешінші?'),
      t('Кептеліс, сәл кешігемін'),
    ],
    'client' => [
      t('Қашан келесіз?'),
      t('Жүк дайын'),
      t('Мен күтіп тұрмын'),
      t('Подъезд ашық'),
      t('Қоңырау шалыңызшы'),
    ],
    _ => [t('Сәлеметсіз бе! Модератор. Бәрі жақсы ма?')],
  };

  @override
  void initState() {
    super.initState();
    if (_role == null || _title == null) {
      _resolve();
    } else if (!_isModerator) {
      Repo.orderChatMarkRead(widget.orderId);
    }
  }

  /// Push-тан ашылғанда: заказдағы рөлім мен екінші тараптың аты.
  Future<void> _resolve() async {
    final o = await Repo.orderById(widget.orderId);
    if (o == null || !mounted) return;
    final me = Repo.uid;
    final role =
        _role ??
        (o.clientId == me
            ? 'client'
            : (o.executorId == me ? 'executor' : 'moderator'));
    var title = _title;
    if (title == null) {
      final otherId = role == 'executor' ? o.clientId : o.executorId;
      final p = otherId == null ? null : await Repo.profileOf(otherId);
      title =
          p?.fullName ?? (role == 'executor' ? t('Клиент') : t('Орындаушы'));
    }
    if (!mounted) return;
    setState(() {
      _role = role;
      _title = title;
    });
    if (role != 'moderator') Repo.orderChatMarkRead(widget.orderId);
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onMessages(int count) {
    if (count == _lastCount) return;
    final grew = count > _lastCount;
    _lastCount = count;
    if (!_isModerator && grew) Repo.orderChatMarkRead(widget.orderId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send([String? text]) async {
    final body = (text ?? _input.text).trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await Repo.orderChatSend(widget.orderId, body);
      // Жіберілген хабар келесі тікті (3–4 с) күтпей бірден көрінсін.
      Repo.orderMessagesStream(widget.orderId, fresh: true);
      if (text == null) _input.clear();
    } catch (e) {
      if (mounted) {
        showSnack(
          context,
          e.toString().contains('CHAT_CLOSED')
              ? t('Чат жабылды — заказ аяқталғанына 24 сағаттан асты.')
              : errText(e),
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_title ?? '…', maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(
              _isModerator ? t('Заказ чаты · бақылау') : t('Заказ чаты'),
              style: Gz.caption,
            ),
          ],
        ),
      ),
      body: StreamBuilder<Order?>(
        stream: _orderStream,
        builder: (context, osnap) {
          final o = osnap.data;
          final open = _isModerator || (o?.chatOpen ?? true);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: GzNotice(
                  tone: NoticeTone.neutral,
                  icon: Icons.shield_outlined,
                  dense: true,
                  message: _isModerator
                      ? t('Сілтеме не балағат сөз бар хабарлар 🚩 белгіленеді.')
                      : t(
                          'Қауіпсіздік үшін чатты модератор көре алады. '
                          'Төлем мен жеке деректерді абайлап жазыңыз.',
                        ),
                ),
              ),
              Expanded(
                child: StreamBuilder<List<OrderMessage>>(
                  stream: _stream,
                  builder: (context, snap) {
                    final msgs = snap.data ?? const <OrderMessage>[];
                    if (snap.connectionState == ConnectionState.waiting &&
                        msgs.isEmpty) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (msgs.isEmpty) {
                      return EmptyState(
                        icon: Icons.forum_outlined,
                        title: t('Хабар әзірге жоқ'),
                        subtitle: t(
                          'Төмендегі дайын фразаның бірін басыңыз '
                          'не өзіңіз жазыңыз.',
                        ),
                      );
                    }
                    _onMessages(msgs.length);
                    return ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                      itemCount: msgs.length,
                      itemBuilder: (_, i) => _Bubble(
                        msg: msgs[i],
                        mine: msgs[i].senderId == Repo.uid,
                        showRole:
                            _isModerator || msgs[i].senderRole == 'moderator',
                        showFlag: _isModerator && msgs[i].flagged,
                      ),
                    );
                  },
                ),
              ),
              if (!open)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: GzNotice(
                    tone: NoticeTone.neutral,
                    dense: true,
                    message: t(
                      'Чат жабылды. Сұрақ болса — қолдау қызметіне '
                      'жазыңыз.',
                    ),
                  ),
                )
              else ...[
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      for (final p in _phrases)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ActionChip(
                            label: Text(p),
                            onPressed: _sending ? null : () => _send(p),
                          ),
                        ),
                    ],
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _input,
                            minLines: 1,
                            maxLines: 4,
                            maxLength: 1000,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: InputDecoration(
                              hintText: t('Хабарлама…'),
                              counterText: '',
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                            ),
                            onSubmitted: (_) => _send(),
                          ),
                        ),
                        const SizedBox(width: 6),
                        _sending
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : IconButton.filled(
                                style: IconButton.styleFrom(
                                  backgroundColor: Gz.yellow,
                                  foregroundColor: Gz.onBrand,
                                ),
                                tooltip: t('Жіберу'),
                                onPressed: () => _send(),
                                icon: const Icon(Icons.send_rounded),
                              ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final OrderMessage msg;
  final bool mine;
  final bool showRole;
  final bool showFlag;
  const _Bubble({
    required this.msg,
    required this.mine,
    required this.showRole,
    required this.showFlag,
  });

  String get _roleLabel => switch (msg.senderRole) {
    'client' => t('Клиент'),
    'executor' => t('Орындаушы'),
    _ => t('Модератор'),
  };

  @override
  Widget build(BuildContext context) {
    final mod = msg.senderRole == 'moderator';
    return Align(
      alignment: mod && !mine
          ? Alignment.center
          : (mine ? Alignment.centerRight : Alignment.centerLeft),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        decoration: BoxDecoration(
          gradient: mine && !mod ? Gz.brandGradient : null,
          color: mod ? Gz.tint(Gz.violet, 0.10) : (mine ? null : Gz.surface),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(Gz.rMd),
            topRight: const Radius.circular(Gz.rMd),
            bottomLeft: Radius.circular(mine ? Gz.rMd : 4),
            bottomRight: Radius.circular(mine ? 4 : Gz.rMd),
          ),
          border: mine && !mod
              ? null
              : Border.all(color: mod ? Gz.tint(Gz.violet, 0.3) : Gz.border),
          boxShadow: mine && !mod
              ? Gz.glow(Gz.yellow, alpha: 0.2, blur: 10)
              : Gz.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showRole)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showFlag) ...[
                      Icon(Icons.flag_rounded, size: 14, color: Gz.red),
                      const SizedBox(width: 3),
                    ],
                    Text(
                      _roleLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: mod ? Gz.violet : Gz.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            Text(
              msg.body,
              style: TextStyle(
                fontSize: 15,
                height: 1.35,
                color: mine && !mod ? Gz.onBrand : Gz.ink,
              ),
            ),
            const SizedBox(height: 3),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  fmtTime(msg.createdAt),
                  style: TextStyle(
                    fontSize: 11,
                    color: mine && !mod
                        ? Gz.onBrand.withValues(alpha: 0.55)
                        : Gz.textSecondary,
                  ),
                ),
                if (mine && !mod) ...[
                  const SizedBox(width: 4),
                  Icon(
                    msg.readAt == null
                        ? Icons.done_rounded
                        : Icons.done_all_rounded,
                    size: 14,
                    color: Gz.onBrand.withValues(alpha: 0.55),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Модератор заказ чатын өшірмеген бе (`app_settings.order_chat.enabled`).
/// Чат батырмасы да, орындаушының «кешігемін» жарлығы да осы бір тексеріс
/// арқылы көрінеді — екеуі бір-бірінен ажырап кетпесін.
bool orderChatEnabled(Map<String, dynamic>? settings) {
  final setting = settings?['order_chat'];
  return setting is! Map || setting['enabled'] != false;
}

/// Заказ экрандарындағы «Чат» батырмасы — оқылмаған хабар санымен.
/// Сервер 0078-сыз болса не модератор чатты өшірсе — мүлдем көрінбейді.
class OrderChatButton extends ConsumerStatefulWidget {
  final Order order;
  final String title;
  final String myRole;
  const OrderChatButton({
    super.key,
    required this.order,
    required this.title,
    required this.myRole,
  });

  @override
  ConsumerState<OrderChatButton> createState() => _OrderChatButtonState();
}

class _OrderChatButtonState extends ConsumerState<OrderChatButton> {
  bool _available = false;
  int _unread = 0;

  /// Оқылмаған сан — [Repo.orderChatUnreadStream] ортақ циклінен (фонда
  /// тоқтайды; бір заказдың батырмалары бір сұрауды бөліседі).
  StreamSubscription<int>? _sub;

  @override
  void initState() {
    super.initState();
    Repo.orderChatAvailable().then((v) {
      if (!mounted) return;
      setState(() => _available = v);
      if (v) {
        _sub = Repo.orderChatUnreadStream(widget.order.id).listen((n) {
          if (mounted && n != _unread) setState(() => _unread = n);
        });
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = orderChatEnabled(ref.watch(appSettingsProvider).value);
    if (!_available || !enabled || !widget.order.chatOpen) {
      return const SizedBox.shrink();
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton.filledTonal(
          tooltip: t('Чат'),
          style: IconButton.styleFrom(
            backgroundColor: Gz.tint(Gz.blue, 0.12),
            foregroundColor: Gz.blue,
          ),
          onPressed: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => OrderChatScreen(
                  orderId: widget.order.id,
                  title: widget.title,
                  myRole: widget.myRole,
                ),
              ),
            );
            Repo.orderChatUnreadStream(widget.order.id, fresh: true);
          },
          icon: const Icon(Icons.chat_bubble_outline_rounded),
        ),
        if (_unread > 0)
          Positioned(
            right: -2,
            top: -2,
            child: IgnorePointer(child: CountBadge(_unread, urgent: true)),
          ),
      ],
    );
  }
}
