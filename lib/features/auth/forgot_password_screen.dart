import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/env.dart';
import '../../core/theme.dart';

/// Құпиясөзді қалпына келтіру — SMS-сыз нұсқа: қолдау қызметіне (WhatsApp)
/// жазасыз, модератор жеке басты растап, жаңа құпиясөз орнатып береді.
class ForgotPasswordScreen extends StatelessWidget {
  const ForgotPasswordScreen({super.key});

  Future<void> _openWhatsApp(BuildContext context) async {
    final text = Uri.encodeComponent(
        'Сәлеметсіз бе! GazelGo-дағы құпиясөзімді ұмытып қалдым. '
        'Қалпына келтіруге көмектесіңізші.');
    final uri =
        Uri.parse('https://wa.me/${Env.supportWhatsApp}?text=$text');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      showSnack(context, 'WhatsApp ашылмады', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Gz.surface,
      appBar: AppBar(
          title: const Text('Құпиясөзді қалпына келтіру'),
          backgroundColor: Gz.surface),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 66,
                    height: 66,
                    decoration: BoxDecoration(
                      color: Gz.bg,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(Icons.lock_reset,
                        size: 32, color: Gz.ink),
                  ),
                  const SizedBox(height: 20),
                  const Text('Құпиясөзді ұмыттыңыз ба?',
                      style: TextStyle(
                          fontSize: 23, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 10),
                  const Text(
                    'Қолдау қызметіне жазыңыз — тіркелген нөміріңізді айтасыз, '
                    'модератор жеке басыңызды растап, жаңа құпиясөз орнатып '
                    'береді.',
                    style: TextStyle(
                        color: Gz.textSecondary, fontSize: 14.5, height: 1.5),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                      foregroundColor: Colors.white,
                      shadowColor: const Color(0x5925D366),
                    ),
                    onPressed: () => _openWhatsApp(context),
                    icon: const Icon(Icons.chat),
                    label: const Text('WhatsApp арқылы жазу'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Артқа'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
