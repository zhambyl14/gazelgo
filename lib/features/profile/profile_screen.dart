import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import '../auth/executor_apply_screen.dart' show CityPickerSheet;
import '../client/my_addresses_screen.dart';
import '../client/my_orders_screen.dart';
import '../executor/balance_screen.dart';
import '../executor/bonus_widgets.dart';
import '../executor/docs_banner.dart';
import '../executor/earnings_screen.dart';
import '../legal/legal_screen.dart';
import '../support/support_screen.dart';
import 'reviews_screen.dart';

/// Ортақ профиль экраны (клиент те, орындаушы да қолданады).
///
/// ДИЗАЙН (0059-да жаңартылды): бұрын бәрі бірдей ақ ListTile-дардың
/// ұзын тізбегі еді — керегін табу қиын, көзге бірдей көрінетін. Енді
/// үш қабатты:
///   1. HERO — қара-сары карточка: аватар, аты, рөл, рейтинг/сапар/сенім.
///   2. ЖЕДЕЛ ӘРЕКЕТТЕР — 2×2 плиткалар (рөлге қарай өзгереді).
///   3. ТІЗІМ — сирек ашылатын баптаулар, топталған карталармен.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _uploadingAvatar = false;

  Future<void> _changeAvatar() async {
    final f = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
      maxWidth: 1000,
    );
    if (f == null) return;
    setState(() => _uploadingAvatar = true);
    try {
      final bytes = await f.readAsBytes();
      await Repo.updateAvatar(bytes);
      ref.invalidate(myProfileProvider);
    } catch (e) {
      if (mounted) showSnack(context, errText(e), error: true);
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  /// Аккаунтты біржола өшіру — екі сатылы растау (кездейсоқ басудан қорғау).
  Future<void> _deleteAccount(BuildContext context) async {
    final first = await confirmDialog(
      context,
      title: t('Аккаунтты өшіру'),
      message: t(
        'Барлық деректер (заказ тарихы, пікірлер, баланс, құжаттар) '
        'БІРЖОЛА жойылады — кері қайтару мүмкін емес.',
      ),
      cancelLabel: t('Болдырмау'),
      confirmLabel: t('Жалғастыру'),
      confirmColor: Gz.red,
      icon: Icons.delete_forever_outlined,
    );
    if (!first || !context.mounted) return;

    // Соңғы қадам — қауіпті түйме әдейі БАСЫМ ЕМЕС (кездейсоқ басудан қорғау)
    final second = await confirmDialog(
      context,
      title: t('Соңғы растау'),
      message: t('Шынымен де аккаунтты біржола өшіресіз бе?'),
      cancelLabel: t('Жоқ, қалдырамын'),
      confirmLabel: t('Иә, өшіру'),
      confirmColor: Gz.red,
      icon: Icons.warning_amber_rounded,
      emphasizeCancel: true,
    );
    if (!second || !context.mounted) return;

    try {
      await Repo.deleteAccount();
      if (context.mounted) {
        Navigator.of(context).popUntil((r) => r.isFirst);
      }
    } catch (e) {
      if (context.mounted) {
        final msg = e.toString().contains('HAS_ACTIVE_ORDERS')
            ? t('Белсенді заказыңыз бар — алдымен оны аяқтаңыз не тоқтатыңыз.')
            : errText(e);
        showSnack(context, msg, error: true);
      }
    }
  }

  /// Орындаушының жұмыс қаласын қолмен ауыстыру (мыс. басқа қалаға көшсе).
  Future<void> _changeCity(BuildContext context) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Gz.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const CityPickerSheet(),
    );
    if (picked == null || !context.mounted) return;
    try {
      await Repo.setExecutorCity(picked);
      ref.invalidate(myExecutorProfileProvider);
      if (context.mounted) {
        showSnack(context, '${t('Қала')} $picked ${t('болып ауыстырылды')}');
      }
    } catch (e) {
      if (context.mounted) showSnack(context, errText(e), error: true);
    }
  }

  void _open(Widget page) => Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => page));

  /// Жедел әрекеттер торының плиткалары — рөлге қарай.
  List<_QuickTile> _quickTiles(Profile p, bool isExec) {
    final reviews = _QuickTile(
      icon: Icons.star_rounded,
      label: t('Пікірлер'),
      color: const Color(0xFFF59E0B),
      onTap: () => _open(
        ReviewsScreen(
          userId: p.id,
          name: p.fullName,
          rating: p.rating,
          ratingCount: p.ratingCount,
        ),
      ),
    );
    final support = _QuickTile(
      icon: Icons.support_agent,
      label: t('Қолдау'),
      color: isExec ? Gz.blue : Gz.violet,
      onTap: () => _open(const SupportScreen()),
    );

    if (p.isModerator) return [reviews, support];

    if (isExec) {
      return [
        _QuickTile(
          icon: Icons.payments_outlined,
          label: t('Табыс'),
          color: Gz.green,
          onTap: () => _open(const EarningsScreen()),
        ),
        _QuickTile(
          icon: Icons.account_balance_wallet_outlined,
          label: t('Баланс'),
          color: Gz.yellowDark,
          onTap: () => _open(const BalanceScreen()),
        ),
        reviews,
        support,
      ];
    }

    return [
      _QuickTile(
        icon: Icons.receipt_long,
        label: t('Тапсырыстар'),
        color: Gz.blue,
        onTap: () => _open(const MyOrdersScreen()),
      ),
      _QuickTile(
        icon: Icons.bookmark_rounded,
        label: t('Мекенжайлар'),
        color: Gz.green,
        onTap: () => _open(const MyAddressesScreen()),
      ),
      reviews,
      support,
    ];
  }

  /// Жаттыққа шақыру бонусы (0060) модератор баптауында қосулы ма.
  bool _referralEnabled(WidgetRef ref) {
    final s = ref.watch(appSettingsProvider).value;
    final cfg = s?['referral'];
    return cfg is Map && cfg['enabled'] == true;
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(myProfileProvider);
    final execAsync = ref.watch(myExecutorProfileProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t('Профиль'))),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) =>
            EmptyState(icon: Icons.error_outline, title: errText(e)),
        data: (p) {
          if (p == null) return const SizedBox.shrink();
          final ep = execAsync.value;
          final isExec = p.role == 'executor';

          return RefreshIndicator(
            color: Gz.ink,
            onRefresh: () async {
              ref.invalidate(myProfileProvider);
              ref.invalidate(myExecutorProfileProvider);
              await Future.delayed(const Duration(milliseconds: 500));
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                // ---------- 1. HERO ----------
                _ProfileHero(
                  profile: p,
                  uploading: _uploadingAvatar,
                  onAvatarTap: _uploadingAvatar ? null : _changeAvatar,
                  onReviewsTap: () => _open(
                    ReviewsScreen(
                      userId: p.id,
                      name: p.fullName,
                      rating: p.rating,
                      ratingCount: p.ratingCount,
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // ---------- Модератордың құжат сұранымы ----------
                if (isExec &&
                    ep != null &&
                    (ep.docsUpdateRequested || ep.docsReviewPending)) ...[
                  ExecutorDocsBanner(ep: ep),
                  const SizedBox(height: 14),
                ],

                // ---------- 2. ЖЕДЕЛ ӘРЕКЕТТЕР ----------
                // Рөлге қарай ӨЗГЕРЕДІ. Модератор — үшінші жағдай: оған
                // «Тапсырыстар»/«Мекенжайлар» клиенттік экрандары керек
                // емес (бос бет ашылар еді), тек пікірлер мен қолдау.
                _QuickGrid(tiles: _quickTiles(p, isExec)),
                const SizedBox(height: 14),

                // ---------- Жаттыққа шақыру бонусы (0060) ----------
                // Тек ұпай/санақ — балансқа/ақшаға ешбір әсері жоқ.
                if (_referralEnabled(ref)) ...[
                  _ReferralCard(profile: p),
                  const SizedBox(height: 14),
                ],

                // ---------- Орындаушының карталары ----------
                if (isExec) ...[
                  const _ExecEarningsCard(),
                  const SizedBox(height: 12),
                  // Бонус бағдарламасы өшірулі болса — көрінбейді (0059).
                  const BonusProfileCard(),
                  if (ep != null) ...[
                    const SizedBox(height: 12),
                    _VehicleCard(ep: ep, onChangeCity: () => _changeCity(context)),
                  ],
                  const SizedBox(height: 14),
                ],

                // ---------- 3. БАПТАУЛАР ----------
                _GroupCard(
                  title: t('Баптаулар'),
                  children: [
                    _NavRow(
                      icon: Icons.language,
                      color: Gz.blue,
                      title: t('Тіл'),
                      trailing: const LanguageSwitcher(),
                    ),
                    _NavRow(
                      icon: Icons.description_outlined,
                      color: Gz.textSecondary,
                      title: t('Заңдық құжаттар'),
                      subtitle: t('Пайдаланушы келісімі · Құпиялылық саясаты'),
                      onTap: () => _open(const LegalScreen()),
                    ),
                    _NavRow(
                      icon: Icons.manage_accounts_outlined,
                      color: Gz.textSecondary,
                      title: t('Есептік жазба баптаулары'),
                      onTap: () =>
                          _open(_AccountSettingsScreen(onDelete: _deleteAccount)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                _GroupCard(
                  children: [
                    _NavRow(
                      icon: Icons.logout,
                      color: Gz.red,
                      title: t('Шығу'),
                      danger: true,
                      onTap: () => confirmSignOut(context),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Center(
                  child: Text(
                    'Tasu v1.0',
                    style: TextStyle(
                      color: Gz.textSecondary.withValues(alpha: 0.7),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ============================================================
// HERO
// ============================================================
/// Профильдің бас картасы: қара-көк градиент, үлкен аватар, аты, рөл
/// жапсырмасы және үш көрсеткіш (рейтинг · сапар · сенім).
class _ProfileHero extends StatelessWidget {
  final Profile profile;
  final bool uploading;
  final VoidCallback? onAvatarTap;
  final VoidCallback onReviewsTap;

  const _ProfileHero({
    required this.profile,
    required this.uploading,
    required this.onAvatarTap,
    required this.onReviewsTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = profile;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        gradient: Gz.heroGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x330F1720),
            blurRadius: 22,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: onAvatarTap,
                child: Stack(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(2.5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Gz.yellow.withValues(alpha: 0.85),
                          width: 2.5,
                        ),
                      ),
                      child: InitialsAvatar(
                        p.fullName,
                        radius: 33,
                        imageUrl: p.avatarUrl,
                      ),
                    ),
                    if (uploading)
                      const Positioned.fill(
                        child: Padding(
                          padding: EdgeInsets.all(5),
                          child: CircleAvatar(
                            backgroundColor: Colors.black45,
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      )
                    else
                      Positioned(
                        right: 1,
                        bottom: 1,
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: Gz.yellow,
                            shape: BoxShape.circle,
                            border: Border.all(color: Gz.ink, width: 2),
                          ),
                          child: const Icon(
                            Icons.camera_alt,
                            size: 12,
                            color: Gz.ink,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.fullName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      p.phone,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.66),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (!p.isModerator)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 3.5,
                        ),
                        decoration: BoxDecoration(
                          color: Gz.yellow,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          p.isExecutor ? t('Орындаушы') : t('Клиент'),
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900,
                            color: Gz.ink,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Үш көрсеткіш — рейтингті бассаң пікірлер ашылады.
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _HeroStat(
                    value: p.ratingCount == 0
                        ? '—'
                        : p.rating.toStringAsFixed(1),
                    label: '${p.ratingCount} ${t('пікір')}',
                    icon: Icons.star_rounded,
                    color: Gz.yellow,
                    onTap: onReviewsTap,
                  ),
                ),
                _divider(),
                Expanded(
                  child: _HeroStat(
                    value: '${p.trips}',
                    label: t('заказ'),
                    icon: Icons.local_shipping_rounded,
                    color: Colors.white,
                  ),
                ),
                _divider(),
                Expanded(
                  child: _HeroStat(
                    value: '${p.trustScore}',
                    label: t('сенім'),
                    icon: Icons.verified_user_rounded,
                    color: p.trustScore >= 80
                        ? const Color(0xFF4ADE80)
                        : (p.trustScore >= 50
                              ? Gz.yellow
                              : const Color(0xFFF87171)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() =>
      Container(width: 1, height: 30, color: Colors.white.withValues(alpha: 0.1));
}

class _HeroStat extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _HeroStat({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final body = Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
    if (onTap == null) return body;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: body,
    );
  }
}

// ============================================================
// ЖЕДЕЛ ӘРЕКЕТТЕР
// ============================================================
class _QuickTile {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _QuickTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
}

/// Ең жиі керек 4 бөлім — екі бағанды тор. Аты ұзын болса (орысша
/// «Объявления») FittedBox кішірейтеді, ешқашан қиылмайды.
class _QuickGrid extends StatelessWidget {
  final List<_QuickTile> tiles;
  const _QuickGrid({required this.tiles});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < tiles.length; i += 2)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
            child: Row(
              children: [
                Expanded(child: _tile(tiles[i])),
                const SizedBox(width: 10),
                Expanded(
                  child: i + 1 < tiles.length
                      ? _tile(tiles[i + 1])
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _tile(_QuickTile q) => Material(
    color: Gz.surface,
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: q.onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Gz.border),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: q.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(q.icon, size: 19, color: q.color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  q.label,
                  maxLines: 1,
                  softWrap: false,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// ============================================================
// ТОПТАЛҒАН ТІЗІМ
// ============================================================
/// Бірнеше жолды БІР картаға топтайды — бұрын әрқайсысы бөлек карта
/// болып, экран «жапсырмалар қатарына» айналған еді.
class _GroupCard extends StatelessWidget {
  final String? title;
  final List<Widget> children;
  const _GroupCard({this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 7),
            child: Text(
              title!,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
                color: Gz.textSecondary,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
        SectionCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0)
                  const Divider(height: 1, indent: 56, endIndent: 12),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _NavRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool danger;

  const _NavRow({
    required this.icon,
    required this.color,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 18, color: color),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 14.5,
          color: danger ? Gz.red : Gz.ink,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, style: const TextStyle(fontSize: 12)),
      trailing:
          trailing ??
          (onTap == null
              ? null
              : const Icon(Icons.chevron_right, color: Gz.textSecondary)),
      onTap: onTap,
    );
  }
}

// ============================================================
// КӨЛІК КАРТАСЫ (орындаушыға)
// ============================================================
class _VehicleCard extends StatelessWidget {
  final ExecutorProfile ep;
  final VoidCallback onChangeCity;
  const _VehicleCard({required this.ep, required this.onChangeCity});

  (String, Color) get _status => switch (ep.status) {
    'approved' => (t('Расталған'), Gz.green),
    'pending' => (t('Тексерілуде'), Gz.blue),
    'rejected' => (t('Қабылданбаған'), Gz.red),
    _ => (t('Бұғатталған'), Gz.red),
  };

  @override
  Widget build(BuildContext context) {
    final (label, color) = _status;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.directions_car_filled_outlined,
                size: 18,
                color: Gz.ink,
              ),
              const SizedBox(width: 8),
              Text(
                t('Көлігім'),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 11.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          InfoRow(t('Көлік'), ep.vehicleTitle),
          InfoRow(t('Мемлекеттік нөмір'), ep.vehiclePlate),
          if (ep.city != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 100,
                    child: Text(
                      t('Қала'),
                      style: const TextStyle(
                        color: Gz.textSecondary,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      ep.city!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: onChangeCity,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    // «Ауыстыру» → орысша «Заменить» ұзынырақ: қала атауымен
                    // қатарда екі жолға сынып, қиылып тұратын.
                    child: BtnLabel(
                      t('Ауыстыру'),
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Есептік жазба баптаулары — «Аккаунтты өшіру» әдейі негізгі профиль
/// бетінен осында жасырылған (кездейсоқ басудан қорғау үшін), бірақ
/// табылмайтындай терең емес — «Профиль → Есептік жазба баптаулары».
class _AccountSettingsScreen extends StatelessWidget {
  final void Function(BuildContext) onDelete;
  const _AccountSettingsScreen({required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t('Есептік жазба баптаулары'))),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SectionCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.delete_forever_outlined, color: Gz.red),
              title: Text(
                t('Аккаунтты өшіру'),
                style: const TextStyle(
                  color: Gz.red,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text(
                t('Барлық деректер біржола жойылады'),
                style: const TextStyle(fontSize: 12),
              ),
              onTap: () => onDelete(context),
            ),
          ),
        ),
      ),
    );
  }
}

/// Профильдегі табыс картасы (орындаушыға): бүгін / осы ай / барлығы + тарих.
class _ExecEarningsCard extends ConsumerWidget {
  const _ExecEarningsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(executorStatsStreamProvider).value;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.payments_outlined, size: 18, color: Gz.green),
              const SizedBox(width: 8),
              Text(
                t('Табыс'),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const EarningsScreen()),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: BtnLabel(t('Толық тарих')),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _mini(t('Бүгін'), fmtT(s?.today), Gz.green)),
              const SizedBox(width: 8),
              Expanded(child: _mini(t('Осы ай'), fmtT(s?.month), Gz.blue)),
              const SizedBox(width: 8),
              Expanded(
                child: _mini(t('Барлығы'), fmtT(s?.totalEarned), Gz.ink),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _mini(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: Gz.bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Үш карточка бір қатарда тұрғандықтан ені тар: ұзын атау мен
          // үлкен сома (мыс. «548 300 ₸») бұрын «548 3…» болып ҚИЫЛЫП
          // көрінбей қалатын. FittedBox `scaleDown` — сыймаса кішірейтеді,
          // сыйса өлшемін өзгертпейді, ешқашан қиылмайды.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              style: const TextStyle(color: Gz.textSecondary, fontSize: 11.5),
            ),
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// ЖАТТЫҚҚА ШАҚЫРУ БОНУСЫ (0060)
// ============================================================
/// Тек ұпай/санақ — балансқа/ақшаға ЕШБІР әсері жоқ (пайдаланушы
/// 2026-08-07 осылай таңдады, клиентте wallet жоқ). Екі жағдай:
///   · referredBy әлі жоқ болса — код енгізу өрісі көрсетіледі;
///   · referralCode бар болса — өз кодын бөлісу + «N адам шақырдыңыз».
class _ReferralCard extends ConsumerStatefulWidget {
  final Profile profile;
  const _ReferralCard({required this.profile});

  @override
  ConsumerState<_ReferralCard> createState() => _ReferralCardState();
}

class _ReferralCardState extends ConsumerState<_ReferralCard> {
  final _codeCtrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _redeem() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) return;
    setState(() => _busy = true);
    try {
      await Repo.redeemReferralCode(code);
      ref.invalidate(myProfileProvider);
      if (mounted) showSnack(context, t('Код қабылданды!'));
    } catch (e) {
      if (mounted) showSnack(context, errText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Нақты жария домен жоқ (қосымша ТЕК iOS/Android) — сол себепті
  /// сілтеме орнына дүкенде «Tasu» деп іздеуді айтамыз.
  Future<void> _shareCode(String code) async {
    await SharePlus.instance.share(ShareParams(
      text: '${t('Tasu қосымшасына менің кодыммен тіркеліңіз')}: $code. '
          '${t('Play Market немесе App Store-дан «Tasu» деп іздеп табыңыз.')}',
    ));
  }

  Future<void> _copyCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (mounted) showSnack(context, t('Көшірілді'));
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.card_giftcard, color: Gz.violet),
              const SizedBox(width: 8),
              Text(t('Досыңды шақыр'),
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 14.5)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            p.isExecutor
                ? t('Досыңыз кодыңызды енгізіп, БІРІНШІ заказын аяқтаса — '
                    'балансыңызға бонус қосылады')
                : t('Досыңыз кодыңызды енгізіп, БІРІНШІ заказын аяқтаса — '
                    'шақыру санағыңыз өседі'),
            style: const TextStyle(color: Gz.textSecondary, fontSize: 11.5),
          ),
          const SizedBox(height: 6),
          if (p.referralCode != null) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${t('Сіз')} ${p.referralCount} '
                    '${t('адам шақырдыңыз')}',
                    style: const TextStyle(
                        color: Gz.textSecondary, fontSize: 12.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      color: Gz.bg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Gz.border),
                    ),
                    // FittedBox — тар экранда/түймеден орын тарылса, код
                    // әрбір әріптен жол ауыстырып кетпейді (Expanded ені
                    // тым кішірейгенде Text character-wrap жасайды), тек
                    // қажет болса кішірейеді.
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        p.referralCode!,
                        maxLines: 1,
                        softWrap: false,
                        style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            letterSpacing: 1.5),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => _copyCode(p.referralCode!),
                  tooltip: t('Көшіру'),
                  icon: const Icon(Icons.copy_rounded, size: 18),
                ),
                const SizedBox(width: 4),
                IconButton.filled(
                  onPressed: () => _shareCode(p.referralCode!),
                  tooltip: t('Бөлісу'),
                  icon: const Icon(Icons.ios_share, size: 18),
                ),
              ],
            ),
          ],
          if (p.referralCode != null && p.referredBy == null) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
          ],
          if (p.referredBy == null) ...[
            Text(
              t('Досыңыздың кодын енгізіңіз'),
              style: const TextStyle(
                  color: Gz.textSecondary, fontSize: 12.5),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _codeCtrl,
                    enabled: !_busy,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: t('Код'),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _busy ? null : _redeem,
                  child: Text(t('Қолдану')),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
