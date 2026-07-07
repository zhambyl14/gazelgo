import 'package:flutter/material.dart';

import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_form.currentState!.validate()) return;
    try {
      await Repo.signIn(_email.text, _password.text);
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
                    const Center(child: GazelGoLogo(size: 34)),
                    const SizedBox(height: 8),
                    const Center(
                      child: Text(
                        'Газель жүк тасымалы платформасы',
                        style: TextStyle(color: Gz.textSecondary, fontSize: 14),
                      ),
                    ),
                    const SizedBox(height: 36),
                    const Text('Кіру',
                        style: TextStyle(
                            fontSize: 24, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(
                        hintText: 'Email',
                        prefixIcon: Icon(Icons.mail_outline),
                      ),
                      validator: (v) =>
                          (v == null || !v.contains('@')) ? 'Email жазыңыз' : null,
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
                    const SizedBox(height: 20),
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
