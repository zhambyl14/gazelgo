import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/lang.dart';
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

  /// «Кіру» батырмасы дайын ба: нөмір толық әрі құпиясөз кемінде 6 таңба.
  /// Дайын емес күйде батырма СҰР болып тұрады (сары = басуға болады) —
  /// қосымшадағы барлық негізгі әрекетке ортақ ереже.
  bool get _canSubmit =>
      Phone.isValid(_phone.text) && _password.text.length >= 6;

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
      // Кіру сәтті. Бұл экран стек үстіне итерілген болса (гест ағыны) —
      // түбіне дейін жабамыз; AuthGate «/» бетін кірген күйге қайта салады,
      // ал толтырылған жоба заказ болса ClientShell оны жалғастырады.
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (!mounted) return;
      // Қосымшаны АЛҒАШ ашқан адам көбіне бірден осы бетте нөмірі мен
      // ойлаған құпиясөзін жазып «Кіру» басады да, «нөмір не құпиясөз
      // қате» деген қызыл қатеге тіреледі — шын мәнінде оның аккаунты
      // МҮЛДЕМ ЖОҚ. Сол себепті: нөмір тіркелмеген болса — қате көрсетудің
      // орнына ТІРКЕЛУГЕ бағыттаймыз.
      if (_isBadCredentials(e)) {
        final registered = await Repo.phoneRegistered(_phone.text);
        if (registered == false && mounted) {
          await _offerRegistration();
          return;
        }
      }
      if (mounted) showSnack(context, errText(e), error: true);
    }
  }

  bool _isBadCredentials(Object e) {
    final s = e.toString();
    return s.contains('Invalid login credentials') ||
        s.contains('invalid_credentials');
  }

  /// «Бұл нөмір әлі тіркелмеген» — тіркелу бетіне нұсқайтын диалог.
  Future<void> _offerRegistration() async {
    final go = await confirmDialog(
      context,
      title: t('Бұл нөмір әлі тіркелмеген'),
      message: t('Алдымен тіркелу қажет — бір минут алады: аты-жөніңіз, '
          'құпиясөз және Telegram арқылы нөмірді растау.'),
      cancelLabel: t('Артқа'),
      confirmLabel: t('Тіркелу'),
      icon: Icons.person_add_alt_1_outlined,
    );
    if (!go || !mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RegisterScreen()),
    );
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
                    Row(
                      children: [
                        // Гест ағынында бұл экран итерілген — артқа қайтуға болады.
                        if (Navigator.canPop(context))
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () => Navigator.of(context).maybePop(),
                            icon: const Icon(Icons.arrow_back),
                          ),
                        const Spacer(),
                        const LanguageSwitcher(),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Center(
                      child: GazelGoHero(
                        subtitle: t(
                          'Жүк тасымалы және арнайы техника платформасы',
                        ),
                      ),
                    ),
                    const SizedBox(height: 38),
                    Text(
                      t('Кіру'),
                      style: const TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextFormField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      autofillHints: const [AutofillHints.telephoneNumber],
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
                      ],
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: t('Телефон (+7 ...)'),
                        prefixIcon: const Icon(Icons.phone_outlined),
                      ),
                      validator: (v) =>
                          Phone.isValid(v ?? '') ? null : t('Нөмір дұрыс емес'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      obscureText: _obscure,
                      onChanged: (_) => setState(() {}),
                      onFieldSubmitted: (_) => _canSubmit ? _login() : null,
                      decoration: InputDecoration(
                        hintText: t('Құпиясөз'),
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscure ? Icons.visibility_off : Icons.visibility,
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) => (v == null || v.length < 6)
                          ? t('Кемінде 6 таңба')
                          : null,
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ForgotPasswordScreen(),
                          ),
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: Gz.yellowDark,
                        ),
                        child: Text(t('Құпиясөзді ұмыттыңыз ба?')),
                      ),
                    ),
                    const SizedBox(height: 8),
                    BusyButton(
                      label: t('Кіру'),
                      enabled: _canSubmit,
                      onPressed: _login,
                    ),
                    const SizedBox(height: 14),
                    // «Тіркелу» әдейі АЙҚЫН батырма (бұрын жіңішке сілтеме
                    // еді): қосымшаны алғаш ашқандар оны байқамай, кіру
                    // өрістерін толтырып, қызыл қатеге тірелетін.
                    Row(
                      children: [
                        const Expanded(child: Divider()),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Text(
                            t('Аккаунт жоқ па?'),
                            style: const TextStyle(
                              color: Gz.textSecondary,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                        const Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const RegisterScreen(),
                        ),
                      ),
                      icon: const Icon(Icons.person_add_alt_1_outlined,
                          size: 20),
                      label: BtnLabel(t('Тіркелу')),
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
