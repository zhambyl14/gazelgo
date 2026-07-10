import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/phone.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import 'forgot_password_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phone = TextEditingController(text: '+7');
  final _password = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _obscure = true;

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_form.currentState!.validate()) return;
    try {
      await Repo.signInPhone(_phone.text, _password.text);
      // AuthGate өзі бағыттайды
    } catch (e) {
      if (mounted) showSnack(context, errText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Gz.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(
                      child: GazelGoHero(
                          subtitle: 'Газель жүк тасымалы платформасы'),
                    ),
                    const SizedBox(height: 38),
                    const Text('Кіру',
                        style: TextStyle(
                            fontSize: 23, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 18),
                    TextFormField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      autofillHints: const [AutofillHints.telephoneNumber],
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
                      ],
                      decoration: const InputDecoration(
                        hintText: 'Телефон (+7 ...)',
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                      validator: (v) =>
                          Phone.isValid(v ?? '') ? null : 'Нөмір дұрыс емес',
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        hintText: 'Құпиясөз',
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
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const ForgotPasswordScreen()),
                        ),
                        style: TextButton.styleFrom(
                            foregroundColor: Gz.yellowDark),
                        child: const Text('Құпиясөзді ұмыттыңыз ба?'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    BusyButton(label: 'Кіру', onPressed: _login),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const RegisterScreen()),
                      ),
                      child: const Text.rich(TextSpan(children: [
                        TextSpan(
                            text: 'Аккаунт жоқ па?  ',
                            style: TextStyle(
                                color: Gz.textSecondary,
                                fontWeight: FontWeight.w500)),
                        TextSpan(text: 'Тіркелу'),
                      ])),
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
