import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, TextInputFormatter, TextEditingValue;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/vehicle_picker.dart' show vehicleIcon;
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

  void _open(Widget page) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  /// «Менің» тізімінің жолдары — рөлге қарай. Орындаушының табыс пен
  /// балансы мұнда емес, табыс блогының ішінде (жылдам өту батырмалары).
  List<Widget> _menuRows(Profile p, bool isExec) {
    final reviews = _NavRow(
      icon: Icons.star_rounded,
      color: const Color(0xFFF59E0B),
      title: t('Пікірлер'),
      onTap: () => _open(
        ReviewsScreen(
          userId: p.id,
          name: p.fullName,
          rating: p.rating,
          ratingCount: p.ratingCount,
        ),
      ),
    );
    final support = _NavRow(
      icon: Icons.support_agent,
      color: Gz.blue,
      title: t('Қолдау'),
      onTap: () => _open(const SupportScreen()),
    );
    if (p.isModerator || isExec) return [reviews, support];
    return [
      _NavRow(
        icon: Icons.receipt_long,
        color: Gz.ink,
        title: t('Тапсырыстар'),
        onTap: () => _open(const MyOrdersScreen()),
      ),
      _NavRow(
        icon: Icons.bookmark_rounded,
        color: Gz.green,
        title: t('Мекенжайлар'),
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
                // ---------- 1. АВАТАР, АТЫ, СТАТУСЫ ----------
                _ProfileHero(
                  profile: p,
                  ep: isExec ? ep : null,
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
                const SizedBox(height: 16),

                // ---------- Модератордың құжат сұранымы ----------
                if (isExec &&
                    ep != null &&
                    (ep.docsUpdateRequested || ep.docsReviewPending)) ...[
                  ExecutorDocsBanner(ep: ep),
                  const SizedBox(height: 14),
                ],

                // ---------- 2. ОРЫНДАУШЫ: табыс (басты) + көлік ----------
                if (isExec) ...[
                  _ExecEarningsCard(
                    onHistory: () => _open(const EarningsScreen()),
                    onBalance: () => _open(const BalanceScreen()),
                  ),
                  if (ep != null) ...[
                    const SizedBox(height: 12),
                    _VehicleCard(
                      ep: ep,
                      onChangeCity: () => _changeCity(context),
                    ),
                  ],
                  // Бонус бағдарламасы өшірулі болса — көрінбейді (0059).
                  const SizedBox(height: 12),
                  const BonusProfileCard(),
                  const SizedBox(height: 14),
                ],

                // ---------- 3. МЕНІҢ ----------
                _GroupCard(children: _menuRows(p, isExec)),
                const SizedBox(height: 14),

                // ---------- Жаттыққа шақыру бонусы (0060) ----------
                // Тек ұпай/санақ — балансқа/ақшаға ешбір әсері жоқ.
                if (_referralEnabled(ref)) ...[
                  _ReferralCard(profile: p),
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
                      onTap: () => _open(
                        _AccountSettingsScreen(onDelete: _deleteAccount),
                      ),
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
// ТАҚЫРЫП (Clean Minimal)
// ============================================================
/// Профильдің басы — АШЫҚ фонда, ортада: аватар (сары жиекпен, түртсе
/// ауыстырылады), аты, телефоны, рөлі мен (орындаушыда) аккаунт мәртебесі;
/// астында үш көрсеткіш (рейтинг · заказ · сенім) бір ақ карточкада.
class _ProfileHero extends StatelessWidget {
  final Profile profile;

  /// Орындаушы профилі — аккаунт мәртебесін көрсету үшін (клиентте null).
  final ExecutorProfile? ep;
  final bool uploading;
  final VoidCallback? onAvatarTap;
  final VoidCallback onReviewsTap;

  const _ProfileHero({
    required this.profile,
    required this.ep,
    required this.uploading,
    required this.onAvatarTap,
    required this.onReviewsTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final status = ep == null ? null : _accountStatus(ep!.status);
    return Column(
      children: [
        GestureDetector(
          onTap: onAvatarTap,
          child: Stack(
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: Gz.brandGradient,
                ),
                child: Container(
                  padding: const EdgeInsets.all(2.5),
                  decoration: const BoxDecoration(
                    color: Gz.surface,
                    shape: BoxShape.circle,
                  ),
                  child: InitialsAvatar(
                    p.fullName,
                    radius: 42,
                    imageUrl: p.avatarUrl,
                  ),
                ),
              ),
              if (uploading)
                const Positioned.fill(
                  child: Padding(
                    padding: EdgeInsets.all(6),
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
                  right: 2,
                  bottom: 2,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Gz.ink,
                      shape: BoxShape.circle,
                      border: Border.all(color: Gz.surface, width: 2),
                    ),
                    child: const Icon(
                      Icons.camera_alt_rounded,
                      size: 13,
                      color: Gz.yellow,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          p.fullName,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.4,
            color: Gz.ink,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          p.phone,
          style: const TextStyle(color: Gz.textSecondary, fontSize: 13.5),
        ),
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 6,
          runSpacing: 6,
          children: [
            if (!p.isModerator)
              _Chip(
                text: p.isExecutor ? t('Орындаушы') : t('Клиент'),
                bg: Gz.ink,
                fg: Gz.yellow,
              ),
            if (status != null)
              _Chip(
                text: status.$1,
                bg: status.$2.withValues(alpha: 0.12),
                fg: status.$2,
                icon: status.$3,
              ),
          ],
        ),
        const SizedBox(height: 16),
        // Үш көрсеткіш — рейтингті бассаң пікірлер ашылады.
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: Gz.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Gz.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: _HeroStat(
                  value: p.ratingCount == 0 ? '—' : p.rating.toStringAsFixed(1),
                  label: '${p.ratingCount} ${t('пікір')}',
                  icon: Icons.star_rounded,
                  color: const Color(0xFFF59E0B),
                  onTap: onReviewsTap,
                ),
              ),
              _divider(),
              Expanded(
                child: _HeroStat(
                  value: '${p.trips}',
                  label: t('заказ'),
                  icon: Icons.local_shipping_rounded,
                  color: Gz.ink,
                ),
              ),
              _divider(),
              Expanded(
                child: _HeroStat(
                  value: '${p.trustScore}',
                  label: t('сенім'),
                  icon: Icons.verified_user_rounded,
                  color: p.trustScore >= 80
                      ? Gz.green
                      : (p.trustScore >= 50 ? Gz.yellowDark : Gz.red),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _divider() => Container(width: 1, height: 30, color: Gz.border);
}

/// Орындаушы аккаунтының мәртебесі: (жазу, түс, иконка).
(String, Color, IconData) _accountStatus(String status) => switch (status) {
  'approved' => (t('Расталған'), Gz.green, Icons.verified_rounded),
  'pending' => (t('Тексерілуде'), Gz.blue, Icons.hourglass_top_rounded),
  'rejected' => (t('Қабылданбаған'), Gz.red, Icons.cancel_outlined),
  _ => (t('Бұғатталған'), Gz.red, Icons.block_rounded),
};

/// Шағын дөңгелек белгі (рөл, мәртебе).
class _Chip extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;
  final IconData? icon;
  const _Chip({
    required this.text,
    required this.bg,
    required this.fg,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
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
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 5),
            Text(
              value,
              style: const TextStyle(
                color: Gz.ink,
                fontWeight: FontWeight.w900,
                fontSize: 17,
                height: 1.15,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        // Астыңғы жазу — БАС ӘРІППЕН, әріп аралығы кеңейтілген микро-белгі:
        // үстіндегі ірі саннан айқын ажырайды, үшеуі бір «көрсеткіш
        // тақтасы» болып оқылады.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label.toUpperCase(),
            maxLines: 1,
            style: const TextStyle(
              color: Gz.textSecondary,
              fontSize: 9.5,
              height: 1.2,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
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
                if (i > 0) const Divider(height: 1, indent: 56, endIndent: 12),
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

  @override
  Widget build(BuildContext context) {
    final meta = [
      if (ep.vehiclePlate.isNotEmpty) ep.vehiclePlate,
      ?ep.city,
    ].join(' · ');
    return SectionCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Gz.tint(Gz.yellow, 0.2),
              shape: BoxShape.circle,
            ),
            child: vehicleIcon(ep.vehicleType, size: 30),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ep.vehicleTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Gz.textSecondary,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (ep.city != null)
            TextButton(
              onPressed: onChangeCity,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              // «Ауыстыру» → орысша «Заменить» ұзынырақ — BtnLabel сыйғызады.
              child: BtnLabel(
                t('Қаланы ауыстыру'),
                style: const TextStyle(fontSize: 12.5),
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

/// Орындаушының ТАБЫС блогы (Driver Pro) — профильдің басты элементі:
/// бүгінгі табыс ірі санмен, астында осы ай мен барлығы, және тарих пен
/// балансқа жылдам өту батырмалары.
class _ExecEarningsCard extends ConsumerWidget {
  final VoidCallback onHistory;
  final VoidCallback onBalance;
  const _ExecEarningsCard({required this.onHistory, required this.onBalance});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(executorStatsStreamProvider).value;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        gradient: Gz.heroGradient,
        borderRadius: BorderRadius.circular(Gz.radius),
        boxShadow: Gz.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            t('Бүгінгі табыс'),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.65),
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              fmtT(s?.today),
              maxLines: 1,
              style: const TextStyle(
                color: Gz.yellow,
                fontSize: 32,
                height: 1.15,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.8,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _mini(t('Осы ай'), fmtT(s?.month))),
              const SizedBox(width: 8),
              Expanded(child: _mini(t('Барлығы'), fmtT(s?.totalEarned))),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _action(Icons.bar_chart_rounded, t('Тарих'), onHistory),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _action(
                  Icons.account_balance_wallet_rounded,
                  '${t('Баланс')} · ${fmtT(s?.balance)}',
                  onBalance,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _mini(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 11.5,
              ),
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              softWrap: false,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _action(IconData icon, String label, VoidCallback onTap) {
    return Material(
      color: Colors.white.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          height: 42,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 17, color: Gz.yellow),
              const SizedBox(width: 6),
              Flexible(
                child: BtnLabel(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
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
/// Шақыру кодын теру өрісінің форматтауышы: бос орын мен қызмет
/// таңбаларын алып тастап, ЕРІКСІЗ БАС ӘРІПКЕ айналдырады. Пайдаланушы
/// кодты хабарламадан көшіргенде («F591C6 » немесе «f591c6») сервер оны
/// таппай қалмауы үшін керек — енгізген бойда көзге де дұрыс көрінеді.
class _CodeFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue _, TextEditingValue v) {
    final clean = v.text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    return TextEditingValue(
      text: clean,
      selection: TextSelection.collapsed(offset: clean.length),
    );
  }
}

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
    await SharePlus.instance.share(
      ShareParams(
        text:
            '${t('Tasu қосымшасына менің кодыммен тіркеліңіз')}: $code. '
            '${t('Play Market немесе App Store-дан «Tasu» деп іздеп табыңыз.')}',
      ),
    );
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
              Text(
                t('Досыңды шақыр'),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            p.isExecutor
                ? t(
                    'Досыңыз кодыңызды енгізіп, БІРІНШІ заказын аяқтаса — '
                    'балансыңызға бонус қосылады',
                  )
                : t(
                    'Досыңыз кодыңызды енгізіп, БІРІНШІ заказын аяқтаса — '
                    'шақыру санағыңыз өседі',
                  ),
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
                      color: Gz.textSecondary,
                      fontSize: 12.5,
                    ),
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
                      horizontal: 12,
                      vertical: 12,
                    ),
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
                          letterSpacing: 1.5,
                        ),
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
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              t(
                'Тіркелу кезінде енгізуді ұмытсаңыз — осы жерден енгізіңіз. '
                'Бірінші заказыңызды аяқтағанға ДЕЙІН үлгеру керек.',
              ),
              style: const TextStyle(color: Gz.textSecondary, fontSize: 11.5),
            ),
            const SizedBox(height: 8),
            // Өріс пен батырма БІР ҚАТАРДА тұрған: тар экранда өріс
            // қысылып, жазу да, «Қолдану» да қолжетімсіз болып қалатын.
            // Енді екеуі де ТОЛЫҚ ЕНМЕН, бірінің астына бірі қойылды.
            TextField(
              controller: _codeCtrl,
              enabled: !_busy,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.done,
              // Код — 6 таңбалы HEX (мыс. F591C6). Кіші әріппен терсе де,
              // бос орынмен көшірсе де сервер таппай қалмауы үшін өрістің
              // ӨЗІНДЕ тазаланады (сервер де upper/trim жасайды).
              inputFormatters: [_CodeFormatter()],
              onSubmitted: (_) => _redeem(),
              // Батырманың қосулы/өшірулі күйі теру барысында жаңарады.
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: '${t('Мысалы')}: F591C6',
                prefixIcon: const Icon(Icons.redeem, size: 20),
              ),
            ),
            const SizedBox(height: 8),
            BusyButton(
              label: t('Қолдану'),
              enabled: !_busy && _codeCtrl.text.trim().isNotEmpty,
              onPressed: _redeem,
            ),
          ],
        ],
      ),
    );
  }
}
