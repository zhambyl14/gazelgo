import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/lang.dart';
import '../../core/name_guard.dart';
import '../../core/phone.dart';
import '../../core/prefs.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/help_button.dart';
import '../../shared/telegram_verify.dart';
import '../../shared/widgets.dart';
import '../legal/legal_screen.dart';

/// Кіру беті — «Кіру» мен «Тіркелу» БІР ағын (құпиясөзсіз):
///
/// 1) адам нөмірін жазады → «Telegram арқылы растау» батырмасы сұрдан
///    көкке ауысады → Telegram-да нөмірін растайды;
/// 2) қосымшаға оралғанда сервер (`tg-login`) осы нөмірге аккаунт бар-жоғын
///    анықтайды: БАР болса — бірден кіреді (клиент — клиент, орындаушы —
///    орындаушы болып); ЖОҚ болса — тіркелу басталады:
/// 3) кім екені (клиент / орындаушы) → аты-жөні → аккаунт ашылады.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

enum _Stage { phone, role, name }

class _LoginScreenState extends State<LoginScreen> {
  _Stage _stage = _Stage.phone;

  final _phone = TextEditingController(text: '+7');
  final _name = TextEditingController();
  final _referralCode = TextEditingController();

  /// TelegramVerify-ды қайта бастау үшін (кілт ауысса — жаңа виджет).
  int _attempt = 0;

  /// Telegram растауынан кейін аккаунт бар-жоғын тексеріп жатырмыз.
  bool _resolving = false;

  String? _tgToken;
  String? _verifiedPhone; // 7XXXXXXXXXX
  String _role = 'client';
  bool _agree = false;
  bool _referralEnabled = false;
  String _draftKey = '';

  // Қызметкерлерге арналған қосалқы жол (модератор құпиясөзбен ашқан
  // аккаунттар): әдепкіде жасырын.
  bool _staffMode = false;
  final _password = TextEditingController();
  bool _obscure = true;

  late final TapGestureRecognizer _termsTap = TapGestureRecognizer()
    ..onTap = () => Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const LegalScreen(initialTab: 0)));
  late final TapGestureRecognizer _privacyTap = TapGestureRecognizer()
    ..onTap = () => Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const LegalScreen(initialTab: 1)));

  bool get _phoneValid => Phone.isValid(_phone.text);

  @override
  void initState() {
    super.initState();
    _draftKey =
        'draft-${DateTime.now().microsecondsSinceEpoch}-${identityHashCode(this)}';
    Repo.referralEnabled().then((v) {
      if (mounted) setState(() => _referralEnabled = v);
    });
  }

  @override
  void dispose() {
    _phone.dispose();
    _name.dispose();
    _referralCode.dispose();
    _password.dispose();
    _termsTap.dispose();
    _privacyTap.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- ағын

  /// Telegram нөмірді растады → аккаунт бар ма, жоқ па.
  Future<void> _onVerified(String token, String verified) async {
    // Адам жазған нөмір мен Telegram-дағы нөмір әртүрлі болса — қай
    // нөмірмен кіретінін айқын айтамыз (байқаусызда жаңа аккаунт ашып
    // алмасын). Кіру тек Telegram растаған нөмірмен мүмкін.
    final typed = Phone.normalize(_phone.text);
    if (typed != null && typed != verified) {
      final go = await confirmDialog(
        context,
        title: t('Telegram-дағы нөмір басқа'),
        message:
            '${t('Telegram нөміріңіз')}: ${Phone.pretty(verified)}\n'
            '${t('Сіз жазған нөмір')}: ${Phone.pretty(typed)}\n\n'
            '${t('Кіру тек Telegram растаған нөмірмен мүмкін. Сол нөмірмен жалғастырасыз ба?')}',
        cancelLabel: t('Артқа'),
        confirmLabel: t('Жалғастыру'),
        icon: Icons.telegram,
      );
      if (!mounted) return;
      if (!go) {
        _restart();
        return;
      }
      _phone.text = '+${verified[0]} ${verified.substring(1)}';
    }

    setState(() => _resolving = true);
    try {
      final exists = await Repo.tgLogin(token);
      if (!mounted) return;
      if (exists) {
        // Кірді. AuthGate «/» бетін кірген күйге қайта салады; бұл экран
        // стек үстіне итерілген болса (гест ағыны) — түбіне дейін жабамыз.
        Navigator.of(context).popUntil((r) => r.isFirst);
        return;
      }
      // Аккаунт жоқ — тіркелу басталады.
      setState(() {
        _tgToken = token;
        _verifiedPhone = verified;
        _resolving = false;
        _stage = _Stage.role;
      });
      _saveDraft();
    } catch (e) {
      if (!mounted) return;
      showSnack(context, errText(e), error: true);
      _restart();
    }
  }

  /// Нөмір қадамына қайту — растауды басынан бастаймыз.
  void _restart() {
    setState(() {
      _stage = _Stage.phone;
      _resolving = false;
      _tgToken = null;
      _verifiedPhone = null;
      _attempt++;
    });
  }

  void _pickRole(String role) {
    setState(() {
      _role = role;
      _stage = _Stage.name;
    });
    _saveDraft();
  }

  bool get _canCreate => _name.text.trim().length >= 2 && _agree;

  Future<void> _create() async {
    final err = NameGuard.validate(_name.text);
    if (err != null) {
      showSnack(context, err, error: true);
      return;
    }
    final token = _tgToken;
    if (token == null) {
      _restart();
      return;
    }
    _saveDraft();
    try {
      await Repo.signUpTelegram(
        tgToken: token,
        fullName: _name.text,
        role: _role,
      );
    } catch (e) {
      if (!mounted) return;
      if (e.toString().contains('TG_NOT_VERIFIED')) {
        // Растаудың мерзімі өтті (30 мин) — нөмірді қайта растатамыз.
        showSnack(
          context,
          t('Растау уақыты өтті — нөміріңізді қайта растаңыз.'),
          error: true,
        );
        _restart();
      } else {
        showSnack(context, errText(e), error: true);
      }
      return;
    }
    // Дос шақыру коды (0061) — аккаунт енді авторизацияланған. Best-effort:
    // код қате болса тіркелу бәрібір СӘТТІ, тек себебі айтылады.
    final code = _referralCode.text.trim();
    if (code.isNotEmpty) {
      try {
        await Repo.redeemReferralCode(code);
      } catch (e) {
        if (mounted) showSnack(context, errText(e), error: true);
      }
    }
    await _saveDraft(completed: true);
    await Prefs.clearRegistrationDraftKey();
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  /// Тіркелу аудиті (модератордың «тіркелу қай қадамда тоқтады» тізімі).
  Future<void> _saveDraft({bool completed = false}) async {
    if (_verifiedPhone == null) return;
    try {
      await Repo.saveRegistrationDraft(
        draftKey: _draftKey,
        role: _role,
        stage: completed ? 3 : (_stage == _Stage.role ? 1 : 2),
        stageLabel: completed
            ? 'Тіркелу аяқталды'
            : (_stage == _Stage.role ? 'Рөл таңдау' : 'Аты-жөні және келісім'),
        fullName: _name.text,
        phone: _verifiedPhone,
        data: {
          'role': _role,
          'terms_agreed': _agree,
          'referral_entered': _referralCode.text.trim().isNotEmpty,
        },
        completed: completed,
      );
    } catch (_) {
      // Аудит сервистік функция: ол тіркелудің өзіне кедергі болмауы тиіс.
    }
  }

  Future<void> _staffLogin() async {
    try {
      await Repo.signInPhone(_phone.text, _password.text);
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (mounted) showSnack(context, errText(e), error: true);
    }
  }

  /// Артқа: тіркелу қадамдарында — алдыңғы қадамға, нөмір қадамында —
  /// экраннан шығу (гест ағынында).
  bool _back() {
    switch (_stage) {
      case _Stage.name:
        setState(() => _stage = _Stage.role);
        return false;
      case _Stage.role:
        _restart();
        return false;
      case _Stage.phone:
        return true;
    }
  }

  // ---------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final canLeave = _stage == _Stage.phone;
    return PopScope(
      canPop: canLeave,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: Gz.surface,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        if (!canLeave || Navigator.canPop(context))
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () {
                              if (_back()) Navigator.of(context).maybePop();
                            },
                            icon: const Icon(Icons.arrow_back),
                          ),
                        const Spacer(),
                        const HelpButton(topic: 'кіру / Вход'),
                        const SizedBox(width: 4),
                        const ThemeSwitcher(),
                        const SizedBox(width: 6),
                        const LanguageSwitcher(),
                      ],
                    ),
                    const SizedBox(height: 6),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 240),
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0.05, 0),
                            end: Offset.zero,
                          ).animate(anim),
                          child: child,
                        ),
                      ),
                      child: switch (_stage) {
                        _Stage.phone => _phoneStage(),
                        _Stage.role => _roleStage(),
                        _Stage.name => _nameStage(),
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

  Widget _phoneStage() {
    return Column(
      key: const ValueKey('phone'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: GazelGoHero(
            subtitle: t('Жүк тасымалы және арнайы техника платформасы'),
          ),
        ),
        const SizedBox(height: 32),
        Text(t('Кіру'), style: Gz.h1),
        const SizedBox(height: 4),
        Text(
          _staffMode
              ? t('Нөміріңіз бен құпиясөзіңізді енгізіңіз')
              : t('Нөміріңізді жазып, Telegram арқылы растаңыз'),
          style: Gz.bodyMuted,
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _phone,
          enabled: !_resolving,
          keyboardType: TextInputType.phone,
          autofillHints: const [AutofillHints.telephoneNumber],
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
          ],
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: t('Телефон (+7 ...)'),
            prefixIcon: const Icon(Icons.phone_outlined),
            suffixIcon: _phoneValid
                ? Icon(Icons.check_circle_rounded, color: Gz.success)
                : null,
          ),
        ),
        const SizedBox(height: 14),
        if (_staffMode) ...[
          TextField(
            controller: _password,
            obscureText: _obscure,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: t('Құпиясөз'),
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 14),
          BusyButton(
            label: t('Кіру'),
            enabled: _phoneValid && _password.text.length >= 6,
            onPressed: _staffLogin,
          ),
        ] else if (_resolving)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 12),
                Text(
                  t('Аккаунтыңызды тексеріп жатырмыз…'),
                  style: Gz.bodyMuted,
                ),
              ],
            ),
          )
        else ...[
          TelegramVerify(
            key: ValueKey('tg-$_attempt'),
            enabled: _phoneValid,
            showVerified: false,
            onVerified: _onVerified,
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 16,
                color: Gz.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  t(
                    'Құпиясөз қажет емес. Аккаунтыңыз болса — бірден кіресіз, '
                    'болмаса — бір минутта ашамыз.',
                  ),
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: Gz.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 18),
        Center(
          child: TextButton(
            onPressed: _resolving
                ? null
                : () => setState(() => _staffMode = !_staffMode),
            style: TextButton.styleFrom(foregroundColor: Gz.textSecondary),
            child: Text(
              _staffMode
                  ? t('Telegram арқылы кіру')
                  : t('Қызметкер ме? Құпиясөзбен кіру'),
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ),
      ],
    );
  }

  /// Расталған нөмірдің жасыл белгісі (тіркелу қадамдарының басында).
  Widget _verifiedBadge() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: Gz.tint(Gz.success, 0.12),
          borderRadius: BorderRadius.circular(Gz.rLg),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.verified_rounded, size: 16, color: Gz.success),
            const SizedBox(width: 6),
            Text(
              Phone.pretty(_verifiedPhone ?? ''),
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: Gz.success,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepDots(int step) {
    return Row(
      children: [
        for (var i = 0; i < 2; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: i == step ? 22 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i <= step ? Gz.ink : Gz.border,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
        const SizedBox(width: 10),
        Text(
          '${step + 1}/2',
          style: TextStyle(
            color: Gz.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _roleStage() {
    return Column(
      key: const ValueKey('role'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        _verifiedBadge(),
        const SizedBox(height: 18),
        _stepDots(0),
        const SizedBox(height: 14),
        Text(t('Қош келдіңіз!'), style: Gz.h1),
        const SizedBox(height: 6),
        Text(
          t('Бұл нөмірге әлі аккаунт жоқ — бірге ашайық. Сіз кімсіз?'),
          style: Gz.bodyMuted,
        ),
        const SizedBox(height: 20),
        _RoleCard(
          icon: Icons.person_outline_rounded,
          title: t('Клиент'),
          subtitle: t('Көлік шақырамын'),
          selected: _role == 'client',
          onTap: () => _pickRole('client'),
        ),
        const SizedBox(height: 12),
        _RoleCard(
          icon: Icons.local_shipping_outlined,
          title: t('Орындаушы'),
          subtitle: t('Көлігіммен жұмыс істеймін'),
          selected: _role == 'executor',
          onTap: () => _pickRole('executor'),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Icon(Icons.swap_horiz, size: 15, color: Gz.textSecondary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                t('Екінші рөлді кейін де қосасыз'),
                style: TextStyle(fontSize: 12, color: Gz.textSecondary),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _nameStage() {
    return Column(
      key: const ValueKey('name'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        _verifiedBadge(),
        const SizedBox(height: 18),
        _stepDots(1),
        const SizedBox(height: 14),
        Text(t('Аты-жөніңіз'), style: Gz.h1),
        const SizedBox(height: 6),
        Text(
          _role == 'executor'
              ? t('Клиенттер сізді осы атпен көреді')
              : t('Орындаушылар сізді осы атпен көреді'),
          style: Gz.bodyMuted,
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _name,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: t('Аты-жөніңіз'),
            prefixIcon: const Icon(Icons.badge_outlined),
          ),
        ),
        if (_referralEnabled) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _referralCode,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              hintText: t('Шақыру коды (міндетті емес)'),
              prefixIcon: const Icon(Icons.card_giftcard_outlined),
            ),
          ),
        ],
        const SizedBox(height: 12),
        // ҚР 94-V Заңы: дербес деректерді жинауға айқын келісім.
        ConfirmCheck(
          value: _agree,
          onChanged: (v) => setState(() => _agree = v),
          label: Text.rich(
            TextSpan(
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: Gz.textSecondary,
              ),
              children: [
                TextSpan(
                  text: t('Пайдаланушы келісімі'),
                  recognizer: _termsTap,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Gz.ink,
                    decoration: TextDecoration.underline,
                  ),
                ),
                TextSpan(text: t(' және ')),
                TextSpan(
                  text: t('Құпиялылық саясаты'),
                  recognizer: _privacyTap,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Gz.ink,
                    decoration: TextDecoration.underline,
                  ),
                ),
                TextSpan(text: t(' — таныстым, келісемін')),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        // Аты жазылып, келісім белгіленбейінше батырма СҰР.
        BusyButton(
          label: t('Аккаунт ашу'),
          enabled: _canCreate,
          onPressed: _create,
        ),
        if (_role == 'executor') ...[
          const SizedBox(height: 12),
          GzNotice(
            tone: NoticeTone.warning,
            icon: Icons.info_outline_rounded,
            dense: true,
            message: t(
              'Тіркелген соң көлік деректері мен құжаттарды '
              'толтырасыз — модератор тексереді.',
            ),
          ),
        ],
      ],
    );
  }
}

/// Рөл таңдау карточкасы — бүкіл ені бойынша, түртсе бірден келесі қадам.
class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return PressScale(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(Gz.rLg),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: selected ? Gz.tint(Gz.yellow, 0.16) : Gz.surfaceAlt,
              borderRadius: BorderRadius.circular(Gz.rLg),
              border: Border.all(
                color: selected ? Gz.yellowDark : Gz.border,
                width: selected ? 1.8 : 1.2,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Gz.yellow,
                    borderRadius: BorderRadius.circular(Gz.rMd),
                  ),
                  child: Icon(icon, color: Gz.onBrand, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: Gz.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(fontSize: 13, color: Gz.textSecondary),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: Gz.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
