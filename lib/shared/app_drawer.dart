import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/lang.dart';
import '../core/repo.dart';
import '../core/theme.dart';
import '../features/auth/login_screen.dart';
import '../features/board/board_screen.dart';
import '../features/client/my_addresses_screen.dart';
import '../features/client/my_orders_screen.dart';
import '../features/executor/balance_screen.dart';
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
                        Text(
                          isGuest
                              ? t('Жүк тасымалы платформасы')
                              : (isExecutor ? t('Орындаушы') : t('Клиент')),
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: Gz.textSecondary,
                          ),
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
                  ] else ...[
                    _item(
                      context,
                      Icons.receipt_long_outlined,
                      t('Менің тапсырыстарым'),
                      () => _open(context, const MyOrdersScreen()),
                    ),
                    _item(
                      context,
                      Icons.bookmark_outline,
                      t('Менің мекенжайларым'),
                      () => _open(context, const MyAddressesScreen()),
                    ),
                  ],
                  _item(
                    context,
                    Icons.support_agent,
                    t('Қолдау қызметі'),
                    () => _open(context, const SupportScreen()),
                  ),
                  _item(
                    context,
                    Icons.description_outlined,
                    t('Заңдық құжаттар'),
                    // Заңдық құжаттар гестке де ашық болуы керек (сторлар
                    // талабы: келісімді кірмей тұрып оқи алу).
                    () => _go(context, const LegalScreen()),
                  ),

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
                ],
              ),
            ),

            const Divider(height: 1),
            if (isGuest)
              ListTile(
                leading: const Icon(Icons.login, color: Gz.ink),
                title: Text(
                  t('Кіру / Тіркелу'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                onTap: () => _go(context, const LoginScreen()),
              )
            else
              ListTile(
                leading: const Icon(Icons.logout, color: Gz.red),
                title: Text(
                  t('Шығу'),
                  style: const TextStyle(
                    color: Gz.red,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  confirmSignOut(context);
                },
              ),
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

/// Sidebar-дың жоғарғы жағындағы «Хабарландырулар тақтасы» картасы —
/// прототиптегідей «Жаңа» белгісімен ерекшеленіп тұрады.
class _BoardCard extends StatelessWidget {
  final bool isExecutor;
  final VoidCallback onTap;
  const _BoardCard({required this.isExecutor, required this.onTap});

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
                Expanded(
                  child: Text(
                    t('Хабарландырулар'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 14.5,
                    ),
                  ),
                ),
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
                  ? t('Клиенттердің жұмыстарын көріңіз әрі өз қызметіңізді '
                      'жариялаңыз.')
                  : t('Орындаушылардың қызметтерін көріңіз әрі өз жұмысыңызды '
                      'жариялаңыз.'),
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
