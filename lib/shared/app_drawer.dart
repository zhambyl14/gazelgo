import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/lang.dart';
import '../core/models.dart';
import '../core/repo.dart';
import '../core/theme.dart';
import '../features/auth/login_screen.dart';
import '../features/board/board_screen.dart';
import '../features/client/my_addresses_screen.dart';
import '../features/executor/balance_screen.dart';
import '../features/executor/bonus_widgets.dart';
import '../features/executor/earnings_screen.dart';
import '../features/legal/legal_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/support/support_screen.dart';
import 'widgets.dart';

/// Логотип батырмасынан ашылатын sidebar (клиент те, орындаушы да).
///
/// Профиль ЕНДІ ОСЫ ЖЕРДЕ — сол себепті клиентте оң жақ жоғарғы бұрышта
/// профиль батырмасы, орындаушыда екінші таб керек емес.
///
/// [isGuest] — кірмеген қолданушы: барлық тармақ кіру экранына апарады.
class AppDrawer extends ConsumerWidget {
  final bool isGuest;
  const AppDrawer({super.key, this.isGuest = false});

  void _go(BuildContext context, Widget screen) {
    Navigator.of(context).pop(); // sidebar-ды жабамыз
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  /// Гест кез келген тармақты түртсе — алдымен кіру экраны.
  void _open(BuildContext context, Widget screen) =>
      _go(context, isGuest ? const LoginScreen() : screen);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(myProfileProvider).value;
    final isExecutor = profile?.role == 'executor';

    return Drawer(
      backgroundColor: Gz.surface,
      child: SafeArea(
        child: Column(
          children: [
            // ---- тақырып ----
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset(
                      'assets/icon/icon.png',
                      width: 42,
                      height: 42,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isGuest ? 'Tasu' : (profile?.fullName ?? 'Tasu'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 15.5,
                          ),
                        ),
                        // Белсенді рөл + СОЛ РӨЛДЕГІ рейтинг (қос рөлде
                        // клиенттік пен орындаушылық баға бөлек жүреді).
                        if (isGuest)
                          const Text(
                            'Tasu',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Gz.textSecondary,
                            ),
                          )
                        else
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Gz.yellow.withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  isExecutor ? t('Орындаушы') : t('Клиент'),
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    color: Gz.ink,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              RatingStars(
                                profile?.rating ?? 0,
                                count: profile?.ratingCount ?? 0,
                                size: 11,
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Gz.ink),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 10),
                children: [
                  // ---- ЖАҢА: хабарландырулар тақтасы ----
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
                    child: _BoardCard(
                      isExecutor: isExecutor,
                      showNew:
                          ref.watch(newBadgesProvider).value?.board ?? true,
                      onTap: () {
                        // Модератор тақтаны жаңа ғана қосқан/өшірген болуы
                        // мүмкін — қосымшаны қайта ашуды талап етпей, әр
                        // ашқан сайын күйін серверден қайта сұраймыз.
                        ref.invalidate(boardEnabledProvider);
                        _open(context, const BoardScreen());
                      },
                    ),
                  ),

                  _item(
                    context,
                    Icons.person_outline,
                    t('Профиль'),
                    () => _open(context, const ProfileScreen()),
                  ),

                  // Гестте тізім ҚЫСҚА: кірмей тұрып мәні бар тармақтар ғана
                  // (хабарландырулар, профиль, заңдық құжаттар, тіл, кіру).
                  if (isGuest)
                    _item(
                      context,
                      Icons.description_outlined,
                      t('Заңдық құжаттар'),
                      // Сторлар талабы: келісімді кірмей тұрып оқи алу керек,
                      // сол себепті бұл тармақ кіру экранына бұрылмайды.
                      () => _go(context, const LegalScreen()),
                    )
                  else ...[
                    if (isExecutor) ...[
                      _item(
                        context,
                        Icons.account_balance_wallet_outlined,
                        t('Баланс'),
                        () => _open(context, const BalanceScreen()),
                      ),
                      _item(
                        context,
                        Icons.payments_outlined,
                        t('Табыс'),
                        () => _open(context, const EarningsScreen()),
                      ),
                      // Бонус бағдарламасы (0059) — модератор ӨШІРІП қойса
                      // тармақ мүлдем көрінбейді (бос бет ашылмайды).
                      if (ref
                              .watch(executorBonusStreamProvider)
                              .value
                              ?.visible ??
                          false)
                        _item(
                          context,
                          Icons.card_giftcard_outlined,
                          t('Бонустар'),
                          () => _open(context, const BonusHistoryScreen()),
                        ),
                    ] else
                      _item(
                        context,
                        Icons.bookmark_outline,
                        t('Менің мекенжайларым'),
                        () => _open(context, const MyAddressesScreen()),
                      ),
                    _item(
                      context,
                      Icons.support_agent,
                      t('Қолдау қызметі'),
                      () => _open(context, const SupportScreen()),
                    ),
                  ],

                  const Divider(height: 24),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.language,
                          size: 21,
                          color: Gz.textSecondary,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            t('Тіл'),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14.5,
                            ),
                          ),
                        ),
                        const LanguageSwitcher(),
                      ],
                    ),
                  ),

                  // ---- РӨЛ АУЫСТЫРУ (0046) — тілдің ТУРА АСТЫНДА ----
                  // Модератордың рөлі ауыспайды, гест алдымен кіруі керек.
                  if (!isGuest && profile != null && !profile.isModerator) ...[
                    const SizedBox(height: 14),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                      child: _RoleSwitchCard(profile: profile),
                    ),
                  ],
                ],
              ),
            ),

            // «Шығу» ӘДЕЙІ жоқ: ол тек Профильде тұрады — sidebar-дың соңында
            // тұрғанда кездейсоқ басылып қалу қаупі бар еді.
            if (isGuest) ...[
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.login, color: Gz.ink),
                title: Text(
                  t('Кіру / Тіркелу'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                onTap: () => _go(context, const LoginScreen()),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _item(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap,
  ) {
    return ListTile(
      leading: Icon(icon, size: 21, color: Gz.textSecondary),
      title: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
      ),
      onTap: onTap,
    );
  }
}

/// «Орындаушы болу» / «Клиентке ауысу» картасы (0046) — тіл ауыстырғыштың
/// астында тұрады.
///
/// Бұл — рөлді АЛМАСТЫРУ емес, ҚОСЫМША рөл алу (inDriver үлгісі): аккаунт
/// екі рөлді де ұстайды, тек қайсысы белсенді екені ауысады. Ауысқаннан
/// кейін қосымша толығымен сол рөлдің қосымшасы болады — экрандары да,
/// уведомлениелері де. Рейтинг әр рөлде БӨЛЕК жүреді.
class _RoleSwitchCard extends ConsumerStatefulWidget {
  final Profile profile;
  const _RoleSwitchCard({required this.profile});

  @override
  ConsumerState<_RoleSwitchCard> createState() => _RoleSwitchCardState();
}

class _RoleSwitchCardState extends ConsumerState<_RoleSwitchCard> {
  bool _busy = false;

  bool get _toExecutor => widget.profile.role != 'executor';

  /// Орындаушы ӨТІНІМІ бұрын толтырылған ба — жазуы соған қарай өзгереді
  /// («Орындаушы болу» бірінші рет, кейін «Орындаушыға ауысу»).
  ///
  /// Шешуші белгі — `has_executor_role` флагы ЕМЕС, нақты өтінім
  /// (`executor_profiles` жазбасы): флаг рөлге бір рет ауысқанда қойылады,
  /// ал адам өтінімді толтырмай қайтып кетуі мүмкін — сол кезде «Орындаушы
  /// болу» деген жазу дұрысырақ. Клиент өз өтінімін оқи алады (RLS).
  bool get _firstTime =>
      _toExecutor && ref.watch(myExecutorProfileProvider).value == null;

  String get _title => _toExecutor
      ? (_firstTime ? t('Орындаушы болу') : t('Орындаушыға ауысу'))
      : t('Клиентке ауысу');

  String get _subtitle => _toExecutor
      ? (_firstTime
            ? t('Көлігіңізбен ақша табыңыз')
            : t('Заказ лентасына оралу'))
      : t('Көлік шақырып, жүк жіберу');

  Future<void> _switch() async {
    final target = _toExecutor ? 'executor' : 'client';
    final ok = await confirmDialog(
      context,
      title: _title,
      message: _toExecutor
          ? (_firstTime
                ? t('Аккаунтыңыз сақталады — үстіне орындаушы рөлі қосылады. '
                      'Көлік деректері мен құжаттарды толтырып, өтінім '
                      'жібересіз.\n\nОрындаушы рейтингі бөлек басталады.')
                : t('Орындаушы режиміне ауысасыз: заказ лентасы, баланс, '
                      'орындаушы уведомлениелері.\n\nРейтингіңіз де '
                      'орындаушылық болады.'))
          : t('Клиент режиміне ауысасыз: көлік шақыру, тапсырыстарыңыз, '
                'клиент уведомлениелері.\n\nОрындаушы деректеріңіз '
                'жоғалмайды — кез келген уақытта қайта ауыса аласыз. '
                'Бірақ белсенді тарифіңіздің уақыты жүре береді.'),
      cancelLabel: t('Болдырмау'),
      confirmLabel: _toExecutor ? t('Ауысу') : t('Клиентке ауысу'),
      icon: _toExecutor ? Icons.local_shipping_outlined : Icons.person_outline,
    );
    if (!ok || !mounted) return;

    setState(() => _busy = true);
    try {
      await Repo.switchRole(target);
      // Рөл ауысты — профильді де, орындаушы профилін де қайта сұраймыз:
      // `_RoleRouter` жаңа рөлге сай экранды өзі ашады (өтінім толтырылмаған
      // болса — «Өтінім» экраны).
      ref.invalidate(myProfileProvider);
      ref.invalidate(myExecutorProfileProvider);
      if (!mounted) return;
      // Sidebar мен үстіне ашылған беттерді жабамыз — түбірде жаңа рөлдің
      // басты беті тұрады.
      Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showSnack(context, errText(e), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: _busy ? null : _switch,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Gz.bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Gz.border, width: 1.2),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Gz.ink,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _toExecutor
                    ? Icons.local_shipping_outlined
                    : Icons.person_outline,
                size: 18,
                color: Gz.yellow,
              ),
            ),
            const SizedBox(width: 12),
            // Sidebar тар (≈300px) әрі иконка мен trailing белгі орын
            // алады: орысша жазулар («Стать исполнителем») сыймай екінші
            // жолға түсетін. BtnLabel — сыймаса кішірейтеді, ЕШҚАШАН
            // екінші жолға түспейді.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: BtnLabel(
                      _title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: BtnLabel(
                      _subtitle,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Gz.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_busy)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              const Icon(Icons.swap_horiz, color: Gz.textSecondary),
          ],
        ),
      ),
    );
  }
}

/// Sidebar-дың жоғарғы жағындағы «Хабарландырулар тақтасы» картасы —
/// прототиптегідей «Жаңа» белгісімен ерекшеленіп тұрады.
class _BoardCard extends StatelessWidget {
  final bool isExecutor;

  /// «Жаңа» белгісі көрінсін бе (0058). Модератор Баптаулардан алып
  /// тастай алады — фича ескіргенде «жаңа» болып тұрмасын.
  final bool showNew;
  final VoidCallback onTap;
  const _BoardCard({
    required this.isExecutor,
    required this.showNew,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Gz.yellow.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Gz.yellow, width: 1.4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.storefront, size: 21, color: Gz.ink),
                const SizedBox(width: 8),
                // Жүйе шрифті үлкейтілген телефондарда «Хабарландырулар»
                // рамкаға сыймай ЕКІ ЖОЛҒА бөлініп кететін («Хабарландырула»
                // + «р»). FittedBox сыймаған жағдайда жазуды кішірейтеді,
                // сол себепті ол ӘРҚАШАН бір жолда тұрады.
                Expanded(
                  child: SizedBox(
                    height: 19,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        t('Хабарландырулар'),
                        maxLines: 1,
                        softWrap: false,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14.5,
                        ),
                      ),
                    ),
                  ),
                ),
                if (showNew)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Gz.ink,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      t('Жаңа'),
                      style: const TextStyle(
                        color: Gz.yellow,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              isExecutor
                  ? t('Жұмыстарды қараңыз, қызметіңізді жариялаңыз')
                  : t('Қызметтерді қараңыз, жұмысыңызды жариялаңыз'),
              style: const TextStyle(
                fontSize: 12,
                height: 1.4,
                color: Gz.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
