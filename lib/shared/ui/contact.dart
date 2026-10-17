import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/lang.dart';
import '../../core/phone.dart';
import '../../core/theme.dart';

/// Нөмірге қоңырау шалу (жүйелік «Телефон» қосымшасы).
Future<void> callPhone(BuildContext context, String phone) async {
  var ok = false;
  try {
    ok = await launchUrl(Uri(scheme: 'tel', path: Phone.dial(phone)));
  } catch (_) {}
  if (!ok && context.mounted) {
    showSnack(context, '${t('Қоңырау шалу мүмкін болмады')}: ${Phone.pretty(phone)}',
        error: true);
  }
}

/// WhatsApp-та сол нөмірмен чат ашу ([text] — алдын ала толтырылған хабар).
Future<bool> openWhatsApp(
  BuildContext context,
  String phone, {
  String? text,
}) async {
  final digits = Phone.normalize(phone) ?? phone.replaceAll(RegExp(r'\D'), '');
  final uri = Uri.parse(
    'https://wa.me/$digits'
    '${text == null ? '' : '?text=${Uri.encodeComponent(text)}'}',
  );
  var ok = false;
  try {
    ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {}
  if (!ok && context.mounted) {
    showSnack(context, '${t('WhatsApp ашылмады. Нөмір:')} ${Phone.pretty(phone)}',
        error: true);
  }
  return ok;
}

/// «Қоңырау» + «WhatsApp» — екі шағын батырма бір қатарда.
/// Модератор (өтінім иесі, тіркелуді аяқтамаған адам), клиент пен
/// орындаушы бір-бірімен — бәрі осы бір үлгімен байланысады.
class ContactButtons extends StatelessWidget {
  final String phone;
  final String? whatsappText;

  const ContactButtons({super.key, required this.phone, this.whatsappText});

  @override
  Widget build(BuildContext context) {
    ButtonStyle style(Color c) => OutlinedButton.styleFrom(
          foregroundColor: c,
          minimumSize: const Size.fromHeight(44),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          side: BorderSide(color: Gz.tint(c, 0.45), width: 1.4),
        );
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            style: style(Gz.green),
            onPressed: () => callPhone(context, phone),
            icon: const Icon(Icons.call_rounded, size: 18),
            label: Text(t('Қоңырау')),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            style: style(Gz.success),
            onPressed: () => openWhatsApp(context, phone, text: whatsappText),
            icon: const Icon(Icons.chat_rounded, size: 18),
            label: const Text('WhatsApp'),
          ),
        ),
      ],
    );
  }
}
