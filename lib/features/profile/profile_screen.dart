import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/lang.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import '../auth/executor_apply_screen.dart' show CityPickerSheet;
import '../client/my_orders_screen.dart';
import '../executor/docs_banner.dart';
import '../executor/earnings_screen.dart';
import '../legal/legal_screen.dart';
import '../support/support_screen.dart';
import 'reviews_screen.dart';

/// Ортақ профиль экраны (клиент те, орындаушы да қолданады).
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _uploadingAvatar = false;

  Future<void> _changeAvatar() async {
    final f = await ImagePicker().pickImage(
        source: ImageSource.gallery, imageQuality: 70, maxWidth: 1000);
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
      message: t('Аккаунтыңыз және онымен байланысты барлық деректер (заказ '
          'тарихы, пікірлер, баланс, құжаттар) БІРЖОЛА жойылады. Бұл '
          'әрекетті кері қайтару МҮМКІН ЕМЕС.\n\nБелсенді заказыңыз болса, '
          'алдымен оны аяқтаңыз.'),
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
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SectionCard(
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: _uploadingAvatar ? null : _changeAvatar,
                      child: Stack(
                        children: [
                          InitialsAvatar(p.fullName,
                              radius: 30, imageUrl: p.avatarUrl),
                          if (_uploadingAvatar)
                            const Positioned.fill(
                              child: CircleAvatar(
                                backgroundColor: Colors.black38,
                                child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white)),
                              ),
                            )
                          else
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                    color: Gz.yellow, shape: BoxShape.circle),
                                child: const Icon(Icons.camera_alt,
                                    size: 13, color: Gz.ink),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.fullName,
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w800)),
                          Text(p.phone,
                              style: const TextStyle(
                                  color: Gz.textSecondary, fontSize: 13.5)),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              RatingStars(p.rating,
                                  count: p.ratingCount, size: 14),
                              const SizedBox(width: 10),
                              const Icon(Icons.local_shipping,
                                  size: 13, color: Gz.textSecondary),
                              const SizedBox(width: 3),
                              Text('${p.trips} ${t('рейс')}',
                                  style: const TextStyle(
                                      fontSize: 12, color: Gz.textSecondary)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              if (p.role == 'executor' &&
                  ep != null &&
                  (ep.docsUpdateRequested || ep.docsReviewPending)) ...[
                ExecutorDocsBanner(ep: ep),
                const SizedBox(height: 10),
              ],
              if (p.role == 'executor') ...[
                const _ExecEarningsCard(),
                const SizedBox(height: 10),
              ],
              if (p.role == 'executor' && ep != null) ...[
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t('Көлігім'),
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 15)),
                      const SizedBox(height: 8),
                      InfoRow(t('Көлік'), ep.vehicleTitle),
                      if (ep.city != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 130,
                                child: Text(t('Қала'),
                                    style: const TextStyle(
                                        color: Gz.textSecondary,
                                        fontSize: 13.5)),
                              ),
                              Expanded(
                                child: Text(ep.city!,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13.5)),
                              ),
                              TextButton(
                                onPressed: () => _changeCity(context),
                                style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap),
                                child: Text(t('Ауыстыру'),
                                    style: const TextStyle(fontSize: 12.5)),
                              ),
                            ],
                          ),
                        ),
                      InfoRow(t('Мемлекеттік нөмір'), ep.vehiclePlate),
                      InfoRow(t('Статус'), switch (ep.status) {
                        'approved' => t('Расталған'),
                        'pending' => t('Тексерілуде'),
                        'rejected' => t('Қабылданбаған'),
                        _ => t('Бұғатталған'),
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (p.role == 'client') ...[
                SectionCard(
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    leading: const Icon(Icons.receipt_long, color: Gz.blue),
                    title: Text(t('Тапсырыстар'),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(t('Белсенді және өткен заказдар')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const MyOrdersScreen())),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              SectionCard(
                padding: EdgeInsets.zero,
                child: ListTile(
                  leading: const Icon(Icons.star_rounded, color: Color(0xFFF59E0B)),
                  title: Text(t('Пікірлер'),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(p.ratingCount == 0
                      ? t('Әзірге пікір жоқ')
                      : '${p.rating.toStringAsFixed(1)} · ${p.ratingCount} ${t('пікір')}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ReviewsScreen(
                      userId: p.id,
                      name: p.fullName,
                      rating: p.rating,
                      ratingCount: p.ratingCount,
                    ),
                  )),
                ),
              ),
              const SizedBox(height: 10),
              SectionCard(
                padding: EdgeInsets.zero,
                child: ListTile(
                  leading: const Icon(Icons.support_agent, color: Gz.ink),
                  title: Text(t('Қолдау қызметі'),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(t('Сұрақ, шағым, көмек')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const SupportScreen())),
                ),
              ),
              const SizedBox(height: 10),
              SectionCard(
                padding: EdgeInsets.zero,
                child: ListTile(
                  leading: const Icon(Icons.language, color: Gz.blue),
                  title: Text(t('Тіл'),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  trailing: const LanguageSwitcher(),
                  onTap: null,
                ),
              ),
              const SizedBox(height: 10),
              SectionCard(
                padding: EdgeInsets.zero,
                child: ListTile(
                  leading: const Icon(Icons.description_outlined,
                      color: Gz.textSecondary),
                  title: Text(t('Заңдық құжаттар'),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle:
                      Text(t('Пайдаланушы келісімі · Құпиялылық саясаты')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const LegalScreen())),
                ),
              ),
              const SizedBox(height: 10),
              SectionCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.logout, color: Gz.red),
                      title: Text(t('Шығу'),
                          style: const TextStyle(
                              color: Gz.red, fontWeight: FontWeight.w700)),
                      onTap: () => confirmSignOut(context),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.manage_accounts_outlined,
                          color: Gz.textSecondary),
                      title: Text(t('Есептік жазба баптаулары'),
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => _AccountSettingsScreen(
                              onDelete: _deleteAccount))),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Center(
                child: Text('GazelGo v1.0',
                    style: TextStyle(color: Gz.textSecondary, fontSize: 12)),
              ),
            ],
          );
        },
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
              title: Text(t('Аккаунтты өшіру'),
                  style: const TextStyle(
                      color: Gz.red, fontWeight: FontWeight.w700)),
              subtitle: Text(t('Барлық деректер біржола жойылады'),
                  style: const TextStyle(fontSize: 12)),
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
              Text(t('Табыс'),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const EarningsScreen())),
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                child: Text(t('Толық тарих')),
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
              Expanded(child: _mini(t('Барлығы'), fmtT(s?.totalEarned), Gz.ink)),
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
          Text(label,
              style: const TextStyle(color: Gz.textSecondary, fontSize: 11.5)),
          const SizedBox(height: 3),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 15.5, fontWeight: FontWeight.w900, color: color)),
        ],
      ),
    );
  }
}
