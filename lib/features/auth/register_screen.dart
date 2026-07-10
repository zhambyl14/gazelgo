import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/env.dart';
import '../../core/name_guard.dart';
import '../../core/phone.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import '../legal/legal_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _password = TextEditingController();
  final _password2 = TextEditingController();
  String _role = 'client';
  bool _obscure = true;
  bool _agree = false;

  // Telegram верификация күйі
  String? _tgToken; // ағымдағы сессия токені
  String? _verifiedPhone; // расталған нөмір (7XXXXXXXXXX)
  bool _tgWaiting = false; // ботты ашып, растауды күтудеміз
  Timer? _pollTimer;

  late final TapGestureRecognizer _termsTap = TapGestureRecognizer()
    ..onTap = () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const LegalScreen(initialTab: 0)));
  late final TapGestureRecognizer _privacyTap = TapGestureRecognizer()
    ..onTap = () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const LegalScreen(initialTab: 1)));

  @override
  void dispose() {
    _pollTimer?.cancel();
    _name.dispose();
    _password.dispose();
    _password2.dispose();
    _termsTap.dispose();
    _privacyTap.dispose();
    super.dispose();
  }

  /// «Telegram арқылы растау»: токен алып, ботты ашады да, статусты
  /// (расталды ма) 2,5 секунд сайын сұрап отырады.
  Future<void> _startTelegram() async {
    try {
      final token = await Repo.tgStartVerification();
      if (!mounted) return;
      setState(() {
        _tgToken = token;
        _tgWaiting = true;
        _verifiedPhone = null;
      });
      final uri = Uri.parse('https://t.me/${Env.telegramBot}?start=$token');
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(
          const Duration(milliseconds: 2500), (_) => _pollTelegram());
    } catch (e) {
      if (mounted) showSnack(context, errText(e), error: true);
    }
  }

  Future<void> _pollTelegram() async {
    final token = _tgToken;
    if (token == null) return;
    try {
      final res = await Repo.tgCheckVerification(token);
      if (res['verified'] == true && res['phone'] != null) {
        _pollTimer?.cancel();
        if (!mounted) return;
        setState(() {
          _verifiedPhone = res['phone'] as String;
          _tgWaiting = false;
        });
      }
    } catch (_) {
      // желі қатесі — келесі тикте қайталаймыз
    }
  }

  /// Тіркелу — нөмір Telegram-мен расталған соң ғана.
  Future<void> _register() async {
    if (!_form.currentState!.validate()) return;
    if (_verifiedPhone == null || _tgToken == null) {
      showSnack(context, 'Алдымен нөміріңізді Telegram арқылы растаңыз',
          error: true);
      return;
    }
    if (!_agree) {
      showSnack(context,
          'Пайдаланушы келісімі мен Құпиялылық саясатына келісу қажет',
          error: true);
      return;
    }
    try {
      await Repo.signUpPhone(
        phone: _verifiedPhone!,
        password: _password.text,
        fullName: _name.text,
        role: _role,
        tgToken: _tgToken!,
      );
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (mounted) showSnack(context, errText(e), error: true);
    }
  }

  Widget _roleCard(String role, IconData icon, String title, String subtitle) {
    final selected = _role == role;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _role = role),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected ? Gz.yellow : Gz.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: selected ? Gz.yellowDark : Gz.border, width: 1.4),
          ),
          child: Column(
            children: [
              Icon(icon, size: 30, color: Gz.ink),
              const SizedBox(height: 8),
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 14.5)),
              const SizedBox(height: 3),
              Text(subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 11.5, color: Gz.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Gz.surface,
      appBar: AppBar(title: const Text('Тіркелу'), backgroundColor: Gz.surface),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Кім ретінде тіркелесіз?',
                        style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 15)),
                    const SizedBox(height: 10),
                    Row(children: [
                      _roleCard('client', Icons.person_outline, 'Клиент',
                          'Жүк тасымалдатамын'),
                      const SizedBox(width: 10),
                      _roleCard('executor', Icons.local_shipping_outlined,
                          'Газелист', 'Заказ орындаймын'),
                    ]),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        hintText: 'Аты-жөніңіз',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                      validator: (v) => NameGuard.validate(v ?? ''),
                    ),
                    const SizedBox(height: 12),
                    _TelegramVerifyCard(
                      verifiedPhone: _verifiedPhone,
                      waiting: _tgWaiting,
                      onStart: _startTelegram,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        hintText: 'Құпиясөз (кемінде 6 таңба)',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_obscure
                              ? Icons.visibility_off
                              : Icons.visibility),
                          onPressed: () =>
                              setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) => (v == null || v.length < 6)
                          ? 'Кемінде 6 таңба'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password2,
                      obscureText: _obscure,
                      decoration: const InputDecoration(
                        hintText: 'Құпиясөзді қайталаңыз',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                      validator: (v) =>
                          v != _password.text ? 'Құпиясөздер сәйкес емес' : null,
                    ),
                    const SizedBox(height: 16),
                    // ҚР 94-V Заңы: дербес деректерді жинауға айқын келісім
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => setState(() => _agree = !_agree),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 28,
                              height: 28,
                              child: Checkbox(
                                value: _agree,
                                activeColor: Gz.ink,
                                onChanged: (v) =>
                                    setState(() => _agree = v ?? false),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text.rich(
                                TextSpan(
                                  style: const TextStyle(
                                      fontSize: 12.5,
                                      height: 1.45,
                                      color: Gz.textSecondary),
                                  children: [
                                    const TextSpan(text: 'Мен '),
                                    TextSpan(
                                      text: 'Пайдаланушы келісімімен',
                                      recognizer: _termsTap,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          color: Gz.ink,
                                          decoration:
                                              TextDecoration.underline),
                                    ),
                                    const TextSpan(text: ' және '),
                                    TextSpan(
                                      text: 'Құпиялылық саясатымен',
                                      recognizer: _privacyTap,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          color: Gz.ink,
                                          decoration:
                                              TextDecoration.underline),
                                    ),
                                    const TextSpan(
                                        text:
                                            ' таныстым, дербес деректерімді өңдеуге келісемін.'),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    BusyButton(label: 'Тіркелу', onPressed: _register),
                    if (_role == 'executor') ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 13, vertical: 11),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF8DE),
                          borderRadius: BorderRadius.circular(13),
                          border: Border.all(color: const Color(0xFFF2DE8A)),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline,
                                size: 17, color: Color(0xFFB58900)),
                            SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                'Газелист тіркелген соң көлік деректері мен '
                                'құжаттарды толтырады — өтінімді модератор '
                                'тексереді.',
                                style: TextStyle(
                                    color: Color(0xFF8A6D00),
                                    fontSize: 12,
                                    height: 1.45),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Telegram арқылы нөмір растау картасы. Үш күй: (1) басталмаған — «Telegram
/// арқылы растау» түймесі; (2) күтуде — ботта нөмірді бөлісуді сұрап тұрмыз;
/// (3) расталды — жасыл нөмір көрсетіледі.
class _TelegramVerifyCard extends StatelessWidget {
  final String? verifiedPhone;
  final bool waiting;
  final VoidCallback onStart;
  const _TelegramVerifyCard({
    required this.verifiedPhone,
    required this.waiting,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    if (verifiedPhone != null) {
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
                  const Text('Нөмір расталды',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                          color: Gz.green)),
                  Text(Phone.pretty(verifiedPhone!),
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14)),
                ],
              ),
            ),
          ],
        ),
      );
    }
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
              const Icon(Icons.send, size: 18, color: Color(0xFF2B7DC4)),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  waiting
                      ? 'Telegram-да «📱 Нөмірімді бөлісу» түймесін басыңыз. '
                          'Растауды күтудеміз…'
                      : 'Нөміріңіз Telegram арқылы расталады (SMS жоқ). '
                          'Түймені басып, ботта нөміріңізді бөлісіңіз.',
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
            onPressed: onStart,
            icon: waiting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.telegram),
            label: Text(waiting
                ? 'Telegram-ды қайта ашу'
                : 'Telegram арқылы растау'),
          ),
        ],
      ),
    );
  }
}
