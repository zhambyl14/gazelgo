import 'package:flutter/material.dart';

import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController(text: '+7');
  final _email = TextEditingController();
  final _password = TextEditingController();
  String _role = 'client';
  bool _obscure = true;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_form.currentState!.validate()) return;
    try {
      await Repo.signUp(
        email: _email.text,
        password: _password.text,
        fullName: _name.text,
        phone: _phone.text,
        role: _role,
      );
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
      // AuthGate рөлге қарай бағыттайды (орындаушы → өтінім экраны)
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
                      validator: (v) => (v == null || v.trim().length < 2)
                          ? 'Атыңызды жазыңыз'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        hintText: 'Телефон (+7 ...)',
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                      validator: (v) {
                        final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
                        return digits.length < 10 ? 'Нөмір толық емес' : null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
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
                    const SizedBox(height: 20),
                    BusyButton(label: 'Тіркелу', onPressed: _register),
                    const SizedBox(height: 10),
                    if (_role == 'executor')
                      const Text(
                        'Тіркелген соң көлік деректері мен құжаттарды толтырасыз. '
                        'Өтінімді модератор тексереді.',
                        textAlign: TextAlign.center,
                        style:
                            TextStyle(color: Gz.textSecondary, fontSize: 12.5),
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
