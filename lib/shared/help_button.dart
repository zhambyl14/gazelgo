import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/env.dart';
import '../core/lang.dart';
import '../core/repo.dart';
import '../core/theme.dart';

/// «Көмек» — КІРУ және ТІРКЕЛУ беттерінде ғана: қиындық болса, бір басумен
/// қолдау қызметінің WhatsApp-ына жазу. (Кірген пайдаланушыда қолдау чаты
/// бар, сол себепті басқа беттерде бұл батырма жоқ.)
///
/// Нөмірді модератор «Баптаулар» бетінен өзгертеді (0072). Хабар мәтіні
/// алдын ала толтырылады ([topic] — қай бетте қиналғаны).
class HelpButton extends StatefulWidget {
  final String topic;
  const HelpButton({super.key, required this.topic});

  @override
  State<HelpButton> createState() => _HelpButtonState();
}

class _HelpButtonState extends State<HelpButton> {
  /// Нөмір бет ашылғанда АЛДЫН АЛА жүктеледі: басқан сәтте желіні күтсек,
  /// Safari (web) сілтемені «пайдаланушы баспаған терезе» деп бұғаттайды.
  static String? _cached;

  @override
  void initState() {
    super.initState();
    if (_cached == null) {
      Repo.supportWhatsApp().then((n) => _cached = n);
    }
  }

  Future<void> _open() async {
    final number = _cached ?? Env.supportWhatsApp;
    final text = Lang.current.value == AppLang.ru
        ? 'Здравствуйте! Нужна помощь в Tasu: ${widget.topic}.'
        : 'Сәлеметсіз бе! Tasu-да көмек керек: ${widget.topic}.';
    final uri = Uri.parse(
      'https://wa.me/$number?text=${Uri.encodeComponent(text)}',
    );
    var ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!ok && mounted) {
      showSnack(context, '${t('WhatsApp ашылмады. Нөмір:')} +$number',
          error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: _open,
      style: TextButton.styleFrom(
        foregroundColor: Gz.green,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        minimumSize: const Size(0, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: const Icon(Icons.support_agent_rounded, size: 20),
      label: Text(
        t('Көмек'),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}
