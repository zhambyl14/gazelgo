import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/phone.dart';
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
  final _password = TextEditingController();
  final _password2 = TextEditingController();
  String _role = 'client';
  bool _obscure = true;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _password.dispose();
    _password2.dispose();
    super.dispose();
  }

  /// Тіркелу — SMS-сыз: аккаунт бірден құрылып, автоматты кіреді
  /// (AuthGate өзі бағыттайды).
  Future<void> _register() async {
    if (!_form.currentState!.validate()) return;
    try {
      await Repo.signUpPhone(
        phone: _phone.text,
        password: _password.text,
        fullName: _name.text,
        role: _role,
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
                      validator: (v) => (v == null || v.trim().length < 2)
                          ? 'Атыңызды жазыңыз'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
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
                    const SizedBox(height: 20),
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
