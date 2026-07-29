import 'package:flutter/material.dart';

import '../../core/lang.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/telegram_verify.dart';
import '../../shared/widgets.dart';

/// Құпиясөзді қалпына келтіру — SMS-сіз, Telegram арқылы: пайдаланушы
/// нөмірін Telegram-мен растайды, сосын жаңа құпиясөз орнатады (екі рет),
/// автоматты кіреді.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _password2 = TextEditingController();
  bool _obscure = true;

  String? _tgToken;
  String? _verifiedPhone;

  @override
  void dispose() {
    _password.dispose();
    _password2.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_verifiedPhone == null || _tgToken == null) {
      showSnack(context, t('Алдымен нөміріңізді Telegram арқылы растаңыз'),
          error: true);
      return;
    }
    if (!_form.currentState!.validate()) return;
    try {
      await Repo.resetPasswordViaTelegram(
        tgToken: _tgToken!,
        newPassword: _password.text,
        phone: _verifiedPhone!,
      );
      if (mounted) {
        showSnack(context, t('Құпиясөз жаңартылды — кіріп жатырсыз'));
        Navigator.of(context).popUntil((r) => r.isFirst);
      }
    } catch (e) {
      if (mounted) showSnack(context, errText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final verified = _verifiedPhone != null;
    return Scaffold(
      backgroundColor: Gz.surface,
      appBar: AppBar(
          title: Text(t('Құпиясөзді қалпына келтіру')),
          backgroundColor: Gz.surface),
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
                    Container(
                      width: 66,
                      height: 66,
                      decoration: BoxDecoration(
                        color: Gz.bg,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(Icons.lock_reset,
                          size: 32, color: Gz.ink),
                    ),
                    const SizedBox(height: 20),
                    Text(t('Құпиясөзді ұмыттыңыз ба?'),
                        style: const TextStyle(
                            fontSize: 23, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 10),
                    Text(
                      t('Нөміріңізді Telegram арқылы растап, жаңа құпиясөз '
                          'орнатыңыз — SMS қажет емес.'),
                      style: const TextStyle(
                          color: Gz.textSecondary, fontSize: 14.5, height: 1.5),
                    ),
                    const SizedBox(height: 20),
                    TelegramVerify(
                      onVerified: (token, phone) => setState(() {
                        _tgToken = token;
                        _verifiedPhone = phone;
                      }),
                    ),
                    if (verified) ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _password,
                        obscureText: _obscure,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: t('Жаңа құпиясөз (кемінде 6 таңба)'),
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
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: t('Жаңа құпиясөзді қайталаңыз'),
                          prefixIcon: const Icon(Icons.lock_outline),
                        ),
                        validator: (v) => v != _password.text
                            ? t('Құпиясөздер сәйкес емес')
                            : null,
                      ),
                      const SizedBox(height: 16),
                      // Екі құпиясөз сәйкес келмейінше батырма СҰР күйде
                      // (қосымшадағы ортақ ереже).
                      BusyButton(
                          label: t('Құпиясөзді жаңарту'),
                          enabled: _password.text.length >= 6 &&
                              _password.text == _password2.text,
                          onPressed: _submit),
                    ],
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(t('Артқа')),
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
