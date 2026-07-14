import 'dart:async';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
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
  bool _noTg = false; // Telegram орнатылмаған (мобильде анықталса)
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
    // `t.me` доменін МҮЛДЕМ пайдаланбайды → ҚР-дағы `t.me` DNS-бұғаттауын
    // айналып өтеді. Қосымша ЖОҚ болса — бұзылған `t.me` браузер-сілтемесіне
    // ЛАҚТЫРМАЙ, «Telegram орнату» экранын көрсетеміз (тұйыққа тіремейміз).
    final tg = Uri.parse('tg://resolve?domain=$bot&start=$t');
    () async {
      var installed = false;
      try {
        installed = await canLaunchUrl(tg);
      } catch (_) {/* қате — орнатылмаған деп есептейміз */}
      if (!mounted) return;
      if (installed) {
        if (_noTg) setState(() => _noTg = false);
        await launchUrl(tg, mode: LaunchMode.externalApplication);
      } else {
        setState(() => _noTg = true); // → «Telegram орнату» экраны
      }
    }();
  }

  /// Telegram қосымшасын дүкеннен орнату бетін ашу (құрылғыда Telegram жоқ
  /// болса). Play Store / App Store домендері бұғатталмайды.
  void _openStore() {
    final url = defaultTargetPlatform == TargetPlatform.iOS
        ? 'https://apps.apple.com/app/id686449807'
        : 'https://play.google.com/store/apps/details?id=org.telegram.messenger';
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
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

    // Telegram орнатылмаған — тұйық сілтеме орнына орнату экраны.
    if (_noTg) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF4E5),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: const Color(0xFFF0C088)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline,
                    size: 18, color: Color(0xFFB26A00)),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    t('Құрылғыда Telegram жоқ. Нөмірді растау Telegram арқылы '
                        'жүреді (SMS-сіз, тегін). Telegram-ды орнатып, «Қайта '
                        'тексеру» түймесін басыңыз.'),
                    style: const TextStyle(
                        color: Color(0xFF8A5200), fontSize: 12.5, height: 1.4),
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
              onPressed: _openStore,
              icon: const Icon(Icons.download),
              label: Text(t('Telegram орнату')),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _busy ? null : _open, // қайта тексереміз
              child: Text(t('Қайта тексеру')),
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
            // Веб-те t.me DNS-пен бұғатталуы мүмкін (кейбір желілерде) —
            // толық DNS-сыз балама: Telegram-ды қолмен ашып, ботты іздеу
            // (Telegram-ның ішкі іздеуі t.me доменін пайдаланбайды).
            if (kIsWeb) ...[
              const SizedBox(height: 12),
              const Divider(height: 1, color: Color(0xFF9DCBF5)),
              const SizedBox(height: 10),
              Text(
                t('Сілтеме ашылмаса (Telegram веб-те бұғатталған желілерде '
                    'болады): Telegram қолданбасын қолмен ашып, төмендегі '
                    'ботты іздеп, кодты жіберіңіз.'),
                style: const TextStyle(
                    color: Color(0xFF1C5A91), fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 8),
              _CopyRow(label: t('Бот'), value: '@${Env.telegramBot}'),
              const SizedBox(height: 6),
              _CopyRow(label: t('Код'), value: '/start ${_token!}'),
            ],
          ],
        ],
      ),
    );
  }
}

/// Мәтінді көрсетіп, түртсе Clipboard-қа көшіретін жол (веб DNS-fallback).
class _CopyRow extends StatelessWidget {
  final String label;
  final String value;
  const _CopyRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        Clipboard.setData(ClipboardData(text: value));
        showSnack(context, t('Көшірілді'));
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF9DCBF5)),
        ),
        child: Row(
          children: [
            Text('$label: ',
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1C5A91))),
            Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontFamily: 'monospace',
                      color: Color(0xFF0F1720))),
            ),
            const Icon(Icons.copy, size: 15, color: Color(0xFF2B7DC4)),
          ],
        ),
      ),
    );
  }
}
