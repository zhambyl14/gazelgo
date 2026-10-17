import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/lang.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';

/// Алушыдан алынған 4 таңбалы ЖЕТКІЗУ КОДЫН енгізу (0076).
///
/// Код дұрыс болса `true` қайтарады — сонда ғана заказды аяқтауға болады
/// (сервер триггері кодсыз аяқтауға жібермейді). 6 рет қате енгізілсе —
/// құлыпталады: енді тек клиент қосымшадан «Жүк жетті» деп растай алады.
Future<bool> showDeliveryCodeSheet(
  BuildContext context, {
  required String orderId,
  String? recipientName,
  String? recipientPhone,
}) async {
  final ok = await showGzSheet<bool>(
    context,
    builder: (_) => _DeliveryCodeSheet(
      orderId: orderId,
      recipientName: recipientName,
      recipientPhone: recipientPhone,
    ),
  );
  return ok == true;
}

class _DeliveryCodeSheet extends StatefulWidget {
  final String orderId;
  final String? recipientName;
  final String? recipientPhone;
  const _DeliveryCodeSheet({
    required this.orderId,
    this.recipientName,
    this.recipientPhone,
  });

  @override
  State<_DeliveryCodeSheet> createState() => _DeliveryCodeSheetState();
}

class _DeliveryCodeSheetState extends State<_DeliveryCodeSheet> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _locked = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (code.length != 4 || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final (ok, left) = await Repo.verifyDeliveryCode(widget.orderId, code);
      if (!mounted) return;
      if (ok) {
        Navigator.pop(context, true);
        return;
      }
      HapticFeedback.heavyImpact();
      setState(() {
        _code.clear();
        _error = left == null
            ? t('Код қате')
            : '${t('Код қате. Қалған әрекет:')} $left';
        _locked = left == 0;
      });
    } catch (e) {
      if (!mounted) return;
      final locked = e.toString().contains('CODE_LOCKED');
      setState(() {
        _locked = locked;
        _error = locked ? null : errText(e);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.recipientName?.trim() ?? '';
    return GzSheetBody(
      title: t('Жеткізу коды'),
      subtitle: name.isEmpty
          ? t(
              'Жүкті қабылдаған адамнан 4 таңбалы кодты сұраңыз — ол '
              'кодты клиент жіберген сілтемеден көреді.',
            )
          : '${t('Алушыдан кодты сұраңыз:')} $name. '
                '${t('Ол кодты клиент жіберген сілтемеден көреді.')}',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_locked)
            GzNotice(
              tone: NoticeTone.danger,
              icon: Icons.lock_outline_rounded,
              title: t('Код құлыпталды'),
              message: t(
                'Тым көп қате әрекет. Клиент қосымшада «Жүк жетті» '
                'деп растаса, заказды аяқтай аласыз. Қиындық болса — '
                'қолдау қызметіне жазыңыз.',
              ),
            )
          else ...[
            TextField(
              controller: _code,
              autofocus: true,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 4,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                letterSpacing: 16,
              ),
              decoration: InputDecoration(
                hintText: '• • • •',
                counterText: '',
                errorText: _error,
              ),
              onChanged: (v) {
                if (_error != null) setState(() => _error = null);
                if (v.length == 4) _verify();
              },
            ),
            const SizedBox(height: 12),
            BusyButton(
              label: t('Растау және аяқтау'),
              icon: Icons.verified_rounded,
              color: Gz.green,
              onPressed: _verify,
            ),
          ],
          if (widget.recipientPhone != null &&
              widget.recipientPhone!.isNotEmpty) ...[
            const SizedBox(height: 12),
            ContactButtons(
              phone: widget.recipientPhone!,
              whatsappText: t(
                'Сәлеметсіз бе! Мен Tasu жүргізушісімін, жүкті '
                'әкелдім. Жеткізу кодын айтып жібересіз бе?',
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            t(
              'Алушы кодты таппаса — клиент өз қосымшасында «Жүк жетті» '
              'деп растай алады.',
            ),
            textAlign: TextAlign.center,
            style: Gz.caption,
          ),
        ],
      ),
    );
  }
}
