import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/lang.dart';
import '../../core/name_guard.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/telegram_verify.dart';
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

  // Telegram верификация күйі (TelegramVerify виджеті толтырады)
  String? _tgToken; // ағымдағы сессия токені
  String? _verifiedPhone; // расталған нөмір (7XXXXXXXXXX)

  late final TapGestureRecognizer _termsTap = TapGestureRecognizer()
    ..onTap = () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const LegalScreen(initialTab: 0)));
  late final TapGestureRecognizer _privacyTap = TapGestureRecognizer()
    ..onTap = () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const LegalScreen(initialTab: 1)));

  @override
  void dispose() {
    _name.dispose();
    _password.dispose();
    _password2.dispose();
    _termsTap.dispose();
    _privacyTap.dispose();
    super.dispose();
  }

  /// Тіркелу — нөмір Telegram-мен расталған соң ғана.
  Future<void> _register() async {
    if (!_form.currentState!.validate()) return;
    if (_verifiedPhone == null || _tgToken == null) {
      showSnack(context, t('Алдымен нөміріңізді Telegram арқылы растаңыз'),
          error: true);
      return;
    }
    if (!_agree) {
      showSnack(context,
          t('Пайдаланушы келісімі мен Құпиялылық саясатына келісу қажет'),
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
              Text(t(title),
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 14.5)),
              const SizedBox(height: 3),
              Text(t(subtitle),
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
      appBar: AppBar(title: Text(t('Тіркелу')), backgroundColor: Gz.surface),
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
                    Text(t('Кім ретінде тіркелесіз?'),
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 15)),
                    const SizedBox(height: 10),
                    Row(children: [
                      _roleCard('client', Icons.person_outline,
                          'Тапсырыс беруші', 'Жүк тасымалдатамын'),
                      const SizedBox(width: 10),
                      _roleCard('executor', Icons.local_shipping_outlined,
                          'Тапсырыс орындаушы', 'Заказ орындаймын'),
                    ]),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        hintText: t('Аты-жөніңіз'),
                        prefixIcon: const Icon(Icons.badge_outlined),
                      ),
                      validator: (v) => NameGuard.validate(v ?? ''),
                    ),
                    const SizedBox(height: 12),
                    TelegramVerify(
                      onVerified: (token, phone) => setState(() {
                        _tgToken = token;
                        _verifiedPhone = phone;
                      }),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        hintText: t('Құпиясөз (кемінде 6 таңба)'),
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
                          ? t('Кемінде 6 таңба')
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password2,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        hintText: t('Құпиясөзді қайталаңыз'),
                        prefixIcon: const Icon(Icons.lock_outline),
                      ),
                      validator: (v) =>
                          v != _password.text ? t('Құпиясөздер сәйкес емес') : null,
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
                                    TextSpan(text: t('Мен ')),
                                    TextSpan(
                                      text: t('Пайдаланушы келісімімен'),
                                      recognizer: _termsTap,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          color: Gz.ink,
                                          decoration:
                                              TextDecoration.underline),
                                    ),
                                    TextSpan(text: t(' және ')),
                                    TextSpan(
                                      text: t('Құпиялылық саясатымен'),
                                      recognizer: _privacyTap,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          color: Gz.ink,
                                          decoration:
                                              TextDecoration.underline),
                                    ),
                                    TextSpan(
                                        text: t(
                                            ' таныстым, дербес деректерімді өңдеуге келісемін.')),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    BusyButton(label: t('Тіркелу'), onPressed: _register),
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
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.info_outline,
                                size: 17, color: Color(0xFFB58900)),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                t('Тапсырыс орындаушы тіркелген соң көлік '
                                'деректері мен құжаттарды толтырады — '
                                'өтінімді модератор тексереді.'),
                                style: const TextStyle(
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
