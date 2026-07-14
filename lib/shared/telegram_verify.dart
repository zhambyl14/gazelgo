import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/env.dart';
import '../core/lang.dart';
import '../core/phone.dart';
import '../core/repo.dart';
import '../core/theme.dart';

/// Telegram арқылы телефон растау виджеті (тіркелу де, құпиясөз қалпына
/// келтіру де қолданады). Токен алып, ботты ашады да, растауды поллинг
/// арқылы күтеді. Расталса — [onVerified] (token, phone) шақырылады.
///
/// ВЕБ ЕСКЕРТУ: браузер `await`-тан кейінгі `launchUrl`-ды popup деп бөгейді,
/// сондықтан ботты нақты АШУ әрдайым тікелей түйме түртуімен (async алдында
/// емес) жүреді — токен алынған соң «📲 Telegram-ды ашу» түймесі көрінеді.
class TelegramVerify extends StatefulWidget {
  final void Function(String token, String phone) onVerified;
  const TelegramVerify({super.key, required this.onVerified});

  @override
  State<TelegramVerify> createState() => _TelegramVerifyState();
}

class _TelegramVerifyState extends State<TelegramVerify> {
  String? _token;
  String? _phone;
  bool _busy = false;
  Timer? _poll;

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() => _busy = true);
    try {
      final token = await Repo.tgStartVerification();
      if (!mounted) return;
      setState(() {
        _token = token;
        _busy = false;
      });
      _open(); // мобильде бірден ашылады (вебте түйме арқылы ашылады)
      _poll?.cancel();
      _poll = Timer.periodic(
          const Duration(milliseconds: 2500), (_) => _check());
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showSnack(context, errText(e), error: true);
      }
    }
  }

  /// Ботты ашу — ТІКЕЛЕЙ түйме түртуінен шақырылады (веб popup-блогынан
  /// аман болу үшін алдында `await` болмауы шарт).
  void _open() {
    final t = _token;
    if (t == null) return;
    final bot = Env.telegramBot;
    final https = Uri.parse('https://t.me/$bot?start=$t');
    // Вебте tg:// схемасы жоқ әрі await popup-ты бөгейді — тікелей https ашамыз.
    if (kIsWeb) {
      launchUrl(https, mode: LaunchMode.externalApplication);
      return;
    }
    // Мобильде алдымен Telegram қосымшасын ТІКЕЛЕЙ ашамыз: `tg://` схемасы
    // `t.me` доменін МҮЛДЕМ пайдаланбайды, сол себепті ҚР-да жиі кездесетін
    // `t.me` DNS-бұғаттауын айналып өтеді. Қосымша жоқ болса — https-ке түсеміз.
    final tg = Uri.parse('tg://resolve?domain=$bot&start=$t');
    () async {
      try {
        if (await canLaunchUrl(tg)) {
          await launchUrl(tg, mode: LaunchMode.externalApplication);
          return;
        }
      } catch (_) {/* tg:// сәтсіз — https-ке түсеміз */}
      await launchUrl(https, mode: LaunchMode.externalApplication);
    }();
  }

  Future<void> _check() async {
    final t = _token;
    if (t == null) return;
    try {
      final res = await Repo.tgCheckVerification(t);
      if (res['verified'] == true && res['phone'] != null) {
        _poll?.cancel();
        if (!mounted) return;
        setState(() => _phone = res['phone'] as String);
        widget.onVerified(t, _phone!);
      }
    } catch (_) {/* келесі тикте қайталаймыз */}
  }

  @override
  Widget build(BuildContext context) {
    if (_phone != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Gz.green.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Gz.green, width: 1.4),
        ),
        child: Row(
          children: [
            const Icon(Icons.verified, color: Gz.green),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t('Нөмір расталды'),
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                          color: Gz.green)),
                  Text(Phone.pretty(_phone!),
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final waiting = _token != null;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF4FF),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFF9DCBF5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.telegram, size: 18, color: Color(0xFF2B7DC4)),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  waiting
                      ? t('Telegram-да «📱 Нөмірімді бөлісу» түймесін басыңыз. '
                          'Ашылмаса — төмендегі түймені қайта басыңыз. '
                          'Растауды күтудеміз…')
                      : t('Нөміріңіз Telegram арқылы расталады (SMS жоқ, тегін). '
                          'Түймені басып, ботта нөміріңізді бөлісіңіз.'),
                  style: const TextStyle(
                      color: Color(0xFF1C5A91), fontSize: 12.5, height: 1.4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF2B7DC4),
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(46),
            ),
            // waiting болса — токен бар, тікелей ашамыз (веб үшін маңызды);
            // әйтпесе алдымен токен аламыз (_start), сосын ашылады.
            onPressed: _busy ? null : (waiting ? _open : _start),
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.telegram),
            label: Text(waiting
                ? t('📲 Telegram-ды ашу')
                : t('Telegram арқылы растау')),
          ),
          if (waiting) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 8),
                Text(t('Растауды күтудеміз…'),
                    style: const TextStyle(color: Color(0xFF1C5A91), fontSize: 12)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
