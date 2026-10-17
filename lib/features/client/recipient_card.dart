import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/env.dart';
import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/phone.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';

/// АЛУШЫ және ЖЕТКІЗУ КОДЫ (0076) — клиенттің заказ бетіндегі блок.
///
/// Жүкті көбіне басқа адам қабылдайды. Клиент оны (аты + телефон) қосады,
/// сервер 4 таңбалы код жасайды. Алушыға WhatsApp арқылы жеке сілтеме
/// барады: картада көлік, келу уақыты және КОД. Орындаушы кодты алушыдан
/// сұрап енгізгенде ғана заказ аяқталады.
///
/// Сервер 0076-сіз болса — блок мүлдем көрінбейді.
class RecipientSection extends StatefulWidget {
  final Order order;
  const RecipientSection({super.key, required this.order});

  @override
  State<RecipientSection> createState() => _RecipientSectionState();
}

class _RecipientSectionState extends State<RecipientSection> {
  bool _available = false;
  bool _loaded = false;
  OrderRecipient? _r;

  static const _editable = {
    'searching',
    'accepted',
    'arrived',
    'loading',
    'in_transit',
  };

  @override
  void initState() {
    super.initState();
    Repo.recipientsAvailable().then((v) {
      if (!mounted || !v) return;
      setState(() => _available = true);
      _load();
    });
  }

  @override
  void didUpdateWidget(RecipientSection old) {
    super.didUpdateWidget(old);
    // Код расталуы статус ауысқанда ғана маңызды (аяқтау кезінде).
    if (_available && old.order.status != widget.order.status) _load();
  }

  Future<void> _load() async {
    try {
      final r = await Repo.orderRecipient(widget.order.id);
      if (mounted) {
        setState(() {
          _r = r;
          _loaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  String _link(OrderRecipient r) => '${Env.webBaseUrl}/track/${r.token}';

  String _message(OrderRecipient r) {
    final name = r.name.trim();
    return '${name.isEmpty ? t('Сәлеметсіз бе!') : '${t('Сәлеметсіз бе,')} $name!'} '
        '${t('Сізге Tasu арқылы жүк келе жатыр')} 🚚\n'
        '${t('Көлік қайда екенін осы сілтемеден көріңіз:')} ${_link(r)}\n'
        '${t('Жүкті қабылдағанда жүргізушіге осы кодты айтыңыз:')} ${r.code}';
  }

  Future<void> _sendWhatsApp(OrderRecipient r) =>
      openWhatsApp(context, r.phone, text: _message(r));

  Future<void> _share(OrderRecipient r) async {
    try {
      await SharePlus.instance.share(ShareParams(text: _message(r)));
    } catch (_) {}
  }

  Future<void> _edit() async {
    final first = _r == null;
    final res = await showGzSheet<(String, String)>(
      context,
      builder: (_) => _RecipientForm(initial: _r),
    );
    if (res == null || !mounted) return;
    try {
      final r = await Repo.setOrderRecipient(widget.order.id, res.$1, res.$2);
      if (!mounted) return;
      setState(() => _r = r);
      // Бірінші қосқанда — бірден WhatsApp ашамыз (келесі қадам бәрібір сол).
      if (first && r != null && r.code != null) {
        showSnack(context, t('Алушы қосылды — енді оған сілтеме жіберіңіз'));
        await _sendWhatsApp(r);
      } else {
        showSnack(context, t('Сақталды'));
      }
    } catch (e) {
      if (mounted) showSnack(context, errText(e), error: true);
    }
  }

  Future<void> _remove() async {
    final ok = await confirmDialog(
      context,
      title: t('Алушыны алып тастау керек пе?'),
      message: t('Жеткізу коды өшеді, заказды орындаушы кодсыз аяқтайды.'),
      confirmLabel: t('Алып тастау'),
      confirmColor: Gz.red,
      icon: Icons.person_remove_alt_1_outlined,
    );
    if (!ok || !mounted) return;
    try {
      await Repo.setOrderRecipient(widget.order.id, '', '');
      if (mounted) setState(() => _r = null);
    } catch (e) {
      if (mounted) showSnack(context, errText(e), error: true);
    }
  }

  Future<void> _confirmDelivered() async {
    final ok = await confirmDialog(
      context,
      title: t('Жүк алушыға жетті ме?'),
      message: t('Алушы кодты таба алмаса — жеткізуді өзіңіз растаңыз. '
          'Сонда орындаушы заказды кодсыз аяқтай алады.'),
      confirmLabel: t('Иә, жүк жетті'),
      confirmColor: Gz.green,
      icon: Icons.inventory_rounded,
    );
    if (!ok || !mounted) return;
    try {
      await Repo.clientConfirmDelivery(widget.order.id);
      await _load();
      if (mounted) showSnack(context, t('Расталды — орындаушы заказды аяқтай алады'));
    } catch (e) {
      if (mounted) showSnack(context, errText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_available || !_loaded) return const SizedBox.shrink();
    final o = widget.order;
    final editable = _editable.contains(o.status);
    final r = _r;
    if (r == null) {
      if (!editable) return const SizedBox.shrink();
      return GzNotice(
        tone: NoticeTone.accent,
        icon: Icons.person_pin_circle_outlined,
        title: t('Жүкті басқа адам қабылдай ма?'),
        message: t('Алушыны қосыңыз: оған WhatsApp арқылы көліктің қайда '
            'екені көрінетін сілтеме мен 4 таңбалы код барады. Жүк тек '
            'кодпен тапсырылады.'),
        actionLabel: t('Алушыны қосу'),
        onAction: _edit,
      );
    }
    final code = r.code ?? '';
    return SectionCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Gz.tint(Gz.violet, 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.person_pin_circle_rounded,
                  color: Gz.violet,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t('Алушы'), style: Gz.caption),
                    Text(
                      r.name.isEmpty ? Phone.pretty(r.phone) : r.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Gz.h3,
                    ),
                    if (r.name.isNotEmpty)
                      Text(Phone.pretty(r.phone), style: Gz.caption),
                  ],
                ),
              ),
              if (editable && !r.verified)
                IconButton(
                  tooltip: t('Өзгерту'),
                  onPressed: _edit,
                  icon: const Icon(Icons.edit_outlined),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (r.verified)
            GzNotice(
              tone: NoticeTone.success,
              icon: Icons.verified_rounded,
              dense: true,
              message: t('Жүк тапсырылды — жеткізу расталды.'),
            )
          else if (code.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Gz.bg,
                borderRadius: BorderRadius.circular(Gz.rMd),
                border: Border.all(color: Gz.border),
              ),
              child: Column(
                children: [
                  Text(t('Жеткізу коды'), style: Gz.caption),
                  const SizedBox(height: 2),
                  Text(
                    code.split('').join(' '),
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 4,
                      color: Gz.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      t('Алушы осы кодты жүргізушіге айтқанда ғана заказ '
                          'аяқталады.'),
                      textAlign: TextAlign.center,
                      style: Gz.caption,
                    ),
                  ),
                ],
              ),
            ),
            if (editable) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Gz.success,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(46),
                      ),
                      onPressed: () => _sendWhatsApp(r),
                      icon: const Icon(Icons.send_rounded, size: 18),
                      label: Text(t('WhatsApp-қа жіберу')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    tooltip: t('Бөлісу'),
                    onPressed: () => _share(r),
                    icon: const Icon(Icons.ios_share_rounded),
                  ),
                ],
              ),
            ],
          ],
          if (!r.verified &&
              const {'arrived', 'loading', 'in_transit'}.contains(o.status)) ...[
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: _confirmDelivered,
              icon: const Icon(Icons.inventory_rounded, size: 18),
              label: Text(t('Алушы кодты таппады ма? «Жүк жетті» деп растау')),
            ),
          ],
          if (editable && !r.verified)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Gz.red),
              onPressed: _remove,
              child: Text(t('Алушыны алып тастау')),
            ),
        ],
      ),
    );
  }
}

/// Алушының аты мен телефоны. Қайтарады: (аты, телефон).
class _RecipientForm extends StatefulWidget {
  final OrderRecipient? initial;
  const _RecipientForm({this.initial});

  @override
  State<_RecipientForm> createState() => _RecipientFormState();
}

class _RecipientFormState extends State<_RecipientForm> {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _phone = TextEditingController(
    text: widget.initial == null ? '+7' : Phone.pretty(widget.initial!.phone),
  );
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _save() {
    if (!Phone.isValid(_phone.text)) {
      setState(() => _error = t('Телефон нөмірі дұрыс емес.'));
      return;
    }
    Navigator.pop(context, (_name.text.trim(), _phone.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return GzSheetBody(
      title: widget.initial == null ? t('Алушыны қосу') : t('Алушыны өзгерту'),
      subtitle: t('Жүкті қабылдайтын адамның аты мен WhatsApp нөмірі.'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            maxLength: 80,
            decoration: InputDecoration(
              labelText: t('Аты (міндетті емес)'),
              prefixIcon: const Icon(Icons.person_outline_rounded),
              counterText: '',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            autofocus: widget.initial == null,
            decoration: InputDecoration(
              labelText: t('Телефон'),
              hintText: '+7 7XX XXX XX XX',
              prefixIcon: const Icon(Icons.phone_outlined),
              errorText: _error,
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 14),
          GzPrimaryButton(label: t('Сақтау'), onPressed: _save),
        ],
      ),
    );
  }
}
