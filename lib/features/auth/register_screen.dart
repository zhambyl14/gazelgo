import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/lang.dart';
import '../../core/name_guard.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/telegram_verify.dart';
import '../../shared/widgets.dart';
import '../legal/legal_screen.dart';

/// Тіркелу — 3 қадамдық wizard:
/// 1) рөл + аты-жөні
/// 2) құпиясөз (2 рет) + келісім
/// 3) телефонды Telegram арқылы растау → тіркелу
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  int _step = 0;
  static const _stepCount = 3;

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

  bool _validateStep1() {
    final err = NameGuard.validate(_name.text);
    if (err != null) {
      showSnack(context, err, error: true);
      return false;
    }
    return true;
  }

  /// 2-қадам дайын ба (батырманың сары/сұр күйі осыған қарайды).
  bool get _step2Ready =>
      _password.text.length >= 6 && _password.text == _password2.text && _agree;

  bool _validateStep2() {
    if (_password.text.length < 6) {
      showSnack(context, t('Кемінде 6 таңба'), error: true);
      return false;
    }
    if (_password.text != _password2.text) {
      showSnack(context, t('Құпиясөздер сәйкес емес'), error: true);
      return false;
    }
    if (!_agree) {
      showSnack(context,
          t('Пайдаланушы келісімі мен Құпиялылық саясатына келісу қажет'),
          error: true);
      return false;
    }
    return true;
  }

  void _next() {
    final ok = switch (_step) {
      0 => _validateStep1(),
      1 => _validateStep2(),
      _ => true,
    };
    if (ok && _step < _stepCount - 1) setState(() => _step++);
  }

  bool _back() {
    if (_step == 0) return true; // экраннан шығуға рұқсат
    setState(() => _step--);
    return false;
  }

  /// Тіркелу — нөмір Telegram-мен расталған соң ғана.
  Future<void> _register() async {
    if (_verifiedPhone == null || _tgToken == null) {
      showSnack(context, t('Алдымен нөміріңізді Telegram арқылы растаңыз'),
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

  Widget _stepDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < _stepCount; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: i == _step ? 22 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i <= _step ? Gz.ink : Gz.border,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ],
    );
  }

  Widget _step1() {
    return Column(
      key: const ValueKey('step1'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t('Кім ретінде тіркелесіз?'),
            style:
                const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        const SizedBox(height: 10),
        Row(children: [
          _roleCard('client', Icons.person_outline, 'Клиент',
              'Көлік шақырамын'),
          const SizedBox(width: 10),
          _roleCard('executor', Icons.local_shipping_outlined, 'Орындаушы',
              'Көлігіммен жұмыс істеймін'),
        ]),
        const SizedBox(height: 10),
        // Қос рөл (0046): таңдау «мәңгілік» емес екенін бірден айтамыз —
        // адамдар осы қадамда ұзақ ойланып қалмауы үшін.
        Row(
          children: [
            const Icon(Icons.swap_horiz, size: 15, color: Gz.textSecondary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                t('Екінші рөлді кейін де қосасыз'),
                style: const TextStyle(
                    fontSize: 12, color: Gz.textSecondary),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        TextFormField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: t('Аты-жөніңіз'),
            prefixIcon: const Icon(Icons.badge_outlined),
          ),
          onFieldSubmitted: (_) => _next(),
        ),
        const SizedBox(height: 20),
        // Аты жазылмайынша батырма СҰР — қосымшадағы ортақ ереже.
        FilledButton(
          onPressed: _name.text.trim().length < 2 ? null : _next,
          child: BtnLabel(t('Келесі')),
        ),
      ],
    );
  }

  Widget _step2() {
    return Column(
      key: const ValueKey('step2'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t('Құпиясөз орнатыңыз'),
            style:
                const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        const SizedBox(height: 10),
        TextFormField(
          controller: _password,
          obscureText: _obscure,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: t('Құпиясөз (кемінде 6 таңба)'),
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(
                  _obscure ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _password2,
          obscureText: _obscure,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: t('Құпиясөзді қайталаңыз'),
            prefixIcon: const Icon(Icons.lock_outline),
          ),
          onFieldSubmitted: (_) => _next(),
        ),
        const SizedBox(height: 12),
        // ҚР 94-V Заңы: дербес деректерді жинауға айқын келісім.
        // Белгі — жасыл құсбелгі (бұрынғы қара шаршы Checkbox орнына).
        ConfirmCheck(
          value: _agree,
          onChanged: (v) => setState(() => _agree = v),
          label: Text.rich(
            TextSpan(
              style: const TextStyle(
                  fontSize: 12.5, height: 1.45, color: Gz.textSecondary),
              children: [
                TextSpan(
                  text: t('Пайдаланушы келісімі'),
                  recognizer: _termsTap,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Gz.ink,
                      decoration: TextDecoration.underline),
                ),
                TextSpan(text: t(' және ')),
                TextSpan(
                  text: t('Құпиялылық саясаты'),
                  recognizer: _privacyTap,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Gz.ink,
                      decoration: TextDecoration.underline),
                ),
                TextSpan(text: t(' — таныстым, келісемін')),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(
            child: OutlinedButton(
                onPressed: () => setState(() => _step--),
                child: BtnLabel(t('Артқа'))),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: FilledButton(
              onPressed: _step2Ready ? _next : null,
              child: BtnLabel(t('Келесі')),
            ),
          ),
        ]),
      ],
    );
  }

  Widget _step3() {
    return Column(
      key: const ValueKey('step3'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t('Телефоныңызды растаңыз'),
            style:
                const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        const SizedBox(height: 10),
        TelegramVerify(
          onVerified: (token, phone) => setState(() {
            _tgToken = token;
            _verifiedPhone = phone;
          }),
        ),
        const SizedBox(height: 20),
        // Нөмір Telegram арқылы РАСТАЛМАЙ тұрып «Тіркелу» батырмасы СҰР әрі
        // басылмайтын күйде тұрады (расталса — сары): назар алдымен
        // жоғарыдағы растауға аударылады.
        BusyButton(
          label: t('Тіркелу'),
          enabled: _verifiedPhone != null && _tgToken != null,
          onPressed: _register,
        ),
        if (_role == 'executor') ...[
          const SizedBox(height: 12),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
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
                    t('Тіркелген соң көлік деректері мен құжаттарды '
                        'толтырасыз — модератор тексереді.'),
                    style: const TextStyle(
                        color: Color(0xFF8A6D00), fontSize: 12, height: 1.45),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: () => setState(() => _step--),
            child: Text(t('Артқа')),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: Gz.surface,
        appBar: AppBar(
          title: Text(t('Тіркелу')),
          backgroundColor: Gz.surface,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (_back()) Navigator.of(context).maybePop();
            },
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _stepDots(),
                    const SizedBox(height: 24),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween<Offset>(
                                  begin: const Offset(0.04, 0),
                                  end: Offset.zero)
                              .animate(anim),
                          child: child,
                        ),
                      ),
                      child: switch (_step) {
                        0 => _step1(),
                        1 => _step2(),
                        _ => _step3(),
                      },
                    ),
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
