import 'package:flutter/material.dart';

import '../core/lang.dart';
import '../core/push.dart';
import '../core/theme.dart';

/// Web нұсқасында (PWA) push-хабарландыруларды қосуды ұсынатын баннер.
///
/// Браузер рұқсатты тек пайдаланушы өзі батырманы басқанда сұратады
/// (әсіресе iPhone Safari), сол себепті push-ты кіргенде автоматты қосу
/// мүмкін емес — осы баннер арқылы бір рет «Қосу» басылады. iPhone-да
/// қосымша «Басты экранға» қосылмаса, push мүлдем жоқ — соны үйретеміз.
/// Жабылса, осы сеанста қайта көрсетілмейді. Мобиль қосымшада
/// [Push.webPrompt] әрқашан null — баннер ешқашан шықпайды.
class WebPushBanner extends StatefulWidget {
  final Widget child;
  const WebPushBanner({super.key, required this.child});

  @override
  State<WebPushBanner> createState() => _WebPushBannerState();
}

class _WebPushBannerState extends State<WebPushBanner> {
  static bool _dismissed = false;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        ValueListenableBuilder<WebPushPrompt?>(
          valueListenable: Push.webPrompt,
          builder: (context, prompt, _) {
            if (prompt == null || _dismissed) return const SizedBox.shrink();
            return Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: SafeArea(top: false, child: _card(prompt)),
            );
          },
        ),
      ],
    );
  }

  Widget _card(WebPushPrompt prompt) {
    final install = prompt == WebPushPrompt.install;
    return Material(
      color: Gz.inkFill,
      elevation: 8,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        child: Row(
          children: [
            const Icon(
              Icons.notifications_active_outlined,
              color: Gz.yellow,
              size: 26,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t('Хабарламаларды қосыңыз'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    install
                        ? t(
                            'iPhone-да хабарлама алу үшін: «Бөлісу» → '
                            '«Басты экранға қосу», сосын Tasu-ды сол '
                            'белгішеден ашыңыз.',
                          )
                        : t(
                            'Жаңа заказ, ұсыныс және хабарламалар туралы '
                            'дереу білесіз.',
                          ),
                    style: const TextStyle(
                      color: Gz.onDarkMuted,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            if (!install)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Gz.yellow,
                    foregroundColor: Gz.onBrand,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    minimumSize: const Size(0, 38),
                  ),
                  onPressed: _busy ? null : _enable,
                  child: Text(t('Іске қосу')),
                ),
              ),
            IconButton(
              icon: Icon(Icons.close, color: Gz.textTertiary),
              onPressed: () => setState(() => _dismissed = true),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _enable() async {
    setState(() => _busy = true);
    await Push.requestWebPermission();
    if (mounted) setState(() => _busy = false);
  }
}
