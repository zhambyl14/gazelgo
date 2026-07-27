import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import 'create_listing_screen.dart';
import 'listing_card.dart';

/// Хабарландыруды толық көрсететін төменгі парақ. Ашылған сәтте
/// `open_listing` шақырылады — сол жерде көру саны тіркеледі (бір адам =
/// 1 көру) және байланыс телефоны алынады.
///
/// [onChanged] — жазба өзгерсе (архивке кетті / қайта жарияланды / өшірілді)
/// шақырылады, шақырушы экран тізімін жаңартады.
Future<void> showListingSheet(
  BuildContext context,
  String listingId, {
  VoidCallback? onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Gz.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => _ListingSheet(listingId: listingId, onChanged: onChanged),
  );
}

class _ListingSheet extends StatefulWidget {
  final String listingId;
  final VoidCallback? onChanged;
  const _ListingSheet({required this.listingId, this.onChanged});

  @override
  State<_ListingSheet> createState() => _ListingSheetState();
}

class _ListingSheetState extends State<_ListingSheet> {
  Listing? _listing;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final l = await Repo.openListing(widget.listingId);
      if (mounted) setState(() => _listing = l);
    } catch (e) {
      if (mounted) setState(() => _error = errText(e));
    }
  }

  Future<void> _call(String phone) async {
    final ok = await launchUrl(Uri(scheme: 'tel', path: phone));
    if (!ok && mounted) {
      showSnack(context, t('Қоңырау шалу мүмкін болмады'), error: true);
    }
  }

  /// Күдікті хабарландыру туралы модераторға жазу — қолдау тредін ашады
  /// (бөлек механизм құрмай, бар арнаны қолданамыз).
  Future<void> _report(Listing l) async {
    final ctrl = TextEditingController();
    final send = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Хабарландыруға шағым')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t('Шағымыңыз модераторға жіберіледі. Ол хабарландыруды тексеріп, '
                  'қажет болса өшіреді.'),
              style: const TextStyle(fontSize: 12.5, color: Gz.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              maxLines: 3,
              decoration: InputDecoration(hintText: t('Не дұрыс емес?')),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t('Болдырмау')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Gz.red,
              foregroundColor: Colors.white,
              shadowColor: const Color(0x59DC2626),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t('Жіберу')),
          ),
        ],
      ),
    );
    if (send != true || !mounted) return;
    try {
      await Repo.supportSend(
        '${t('Хабарландыруға шағым')} (id: ${l.id})\n'
        '${t('Автор')}: ${l.authorName}\n'
        '${t('Мәтіні')}: ${l.body}\n\n'
        '${t('Себебі')}: ${ctrl.text.trim().isEmpty ? '—' : ctrl.text.trim()}',
      );
      if (mounted) showSnack(context, t('Шағым модераторға жіберілді'));
    } catch (e) {
      if (mounted) showSnack(context, errText(e), error: true);
    }
  }

  Future<void> _archive(Listing l) async {
    final ok = await confirmDialog(
      context,
      title: t('Хабарландыруды алып тастау'),
      message: t(
        'Хабарландыру лентадан алынып, архивке кетеді. Суреттері біздің '
        'базадан өшіріледі — қайта жарияласаңыз, оларды қайта салу керек.',
      ),
      confirmLabel: t('Алып тастау'),
      confirmColor: Gz.red,
      icon: Icons.archive_outlined,
    );
    if (!ok || !mounted) return;
    try {
      await Repo.archiveListing(l.id);
      widget.onChanged?.call();
      if (mounted) {
        Navigator.of(context).pop();
        showSnack(context, t('Хабарландыру архивке кетті'));
      }
    } catch (e) {
      if (mounted) showSnack(context, errText(e), error: true);
    }
  }

  Future<void> _delete(Listing l) async {
    final ok = await confirmDialog(
      context,
      title: t('Біржола өшіру'),
      message: t('Хабарландыру мен оның суреттері толық жойылады.'),
      confirmLabel: t('Өшіру'),
      confirmColor: Gz.red,
      icon: Icons.delete_forever_outlined,
    );
    if (!ok || !mounted) return;
    try {
      await Repo.deleteListing(l.id);
      widget.onChanged?.call();
      if (mounted) {
        Navigator.of(context).pop();
        showSnack(context, t('Өшірілді'));
      }
    } catch (e) {
      if (mounted) showSnack(context, errText(e), error: true);
    }
  }

  Future<void> _repost(Listing l) async {
    Navigator.of(context).pop();
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => CreateListingScreen(repost: l)),
    );
    if (done == true) widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.82,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scroll) {
        final l = _listing;
        return Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Gz.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: _error != null
                  ? ListView(
                      controller: scroll,
                      children: [
                        const SizedBox(height: 60),
                        EmptyState(icon: Icons.wifi_off, title: _error!),
                      ],
                    )
                  : l == null
                  ? const Center(child: CircularProgressIndicator())
                  : _body(scroll, l),
            ),
          ],
        );
      },
    );
  }

  Widget _body(ScrollController scroll, Listing l) {
    final phone = l.authorPhone;
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (l.photos.isNotEmpty) ...[
          _PhotoGallery(paths: l.photos),
          const SizedBox(height: 14),
        ],
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: listingKindColor(l.kind),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                listingKindLabel(l.kind),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l.vehicleType.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Gz.textSecondary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          l.priceDisplay,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 8),
        Text(l.body, style: const TextStyle(fontSize: 14.5, height: 1.55)),
        const SizedBox(height: 14),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _chip(Icons.location_city_outlined, l.city),
            if (l.durationDays > 0)
              _chip(Icons.event_repeat, '${l.durationDays} ${t('күндік жұмыс')}'),
            if (l.mine && l.views != null)
              _chip(
                Icons.visibility_outlined,
                '${l.views} ${t('адам көрді')}',
                color: Gz.blue,
              ),
            _chip(Icons.schedule, fmtDate(l.createdAt)),
            if (l.isActive)
              _chip(
                Icons.hourglass_bottom,
                '${t('лентада тағы')} ${l.daysLeft} ${t('күн')}',
                color: l.daysLeft <= 1 ? Gz.red : Gz.green,
              )
            else
              _chip(Icons.history, t('Мерзімі бітті'), color: Gz.textSecondary),
          ],
        ),
        const SizedBox(height: 14),

        // ---- автор ----
        if (!l.mine) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Gz.bg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                InitialsAvatar(
                  l.authorName.isEmpty ? '?' : l.authorName,
                  radius: 20,
                  imageUrl: l.authorAvatar,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.authorName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      Row(
                        children: [
                          RatingStars(
                            l.authorRating,
                            count: l.authorRatingCount,
                            size: 12,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            l.kind == ListingKind.service
                                ? t('Орындаушы')
                                : t('Клиент'),
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: Gz.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (phone != null && phone.isNotEmpty) ...[
            FilledButton.icon(
              onPressed: () => _call(phone),
              icon: const Icon(Icons.call, size: 20),
              label: Text('${t('Қоңырау шалу')} · $phone'),
            ),
            const SizedBox(height: 6),
            Text(
              t('Келісім тікелей екеуіңіздің араңызда болады — Tasu бұл '
                  'хабарландыруға делдал емес. Алдын ала ақша аудармаңыз.'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Gz.textSecondary, fontSize: 11.5),
            ),
          ] else
            Text(
              t('Байланыс нөмірі қолжетімсіз — хабарландырудың мерзімі өткен.'),
              style: const TextStyle(color: Gz.textSecondary, fontSize: 12.5),
            ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: () => _report(l),
            icon: const Icon(Icons.flag_outlined, size: 18, color: Gz.red),
            label: Text(
              t('Шағымдану'),
              style: const TextStyle(color: Gz.red),
            ),
          ),
        ],

        // ---- өз хабарландыруым ----
        if (l.mine) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Gz.blue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Gz.blue.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                const Icon(Icons.visibility_outlined, color: Gz.blue, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${l.views ?? 0} ${t('адам көрді')}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        t('Бұл санды тек сіз көресіз.'),
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Gz.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (l.isActive)
            OutlinedButton.icon(
              onPressed: () => _archive(l),
              icon: const Icon(Icons.archive_outlined, size: 20),
              label: Text(t('Лентадан алып тастау')),
            )
          else
            FilledButton.icon(
              onPressed: () => _repost(l),
              icon: const Icon(Icons.refresh, size: 20),
              label: Text(t('Қайта жариялау')),
            ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => _delete(l),
            icon: const Icon(
              Icons.delete_outline,
              size: 18,
              color: Gz.red,
            ),
            label: Text(t('Біржола өшіру'),
                style: const TextStyle(color: Gz.red)),
          ),
        ],
      ],
    );
  }

  Widget _chip(IconData icon, String text, {Color? color}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color == null ? Gz.bg : color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color ?? Gz.textSecondary),
        const SizedBox(width: 5),
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color ?? Gz.ink,
          ),
        ),
      ],
    ),
  );
}

/// Хабарландыру суреттері (макс 4) — көлденең жолақ, түртсе үлкейеді.
class _PhotoGallery extends StatelessWidget {
  final List<String> paths;
  const _PhotoGallery({required this.paths});

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return SizedBox(
      height: 170,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: paths.length,
        separatorBuilder: (_, i) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final url = Repo.listingPhotoUrl(paths[i]);
          return GestureDetector(
            onTap: () => showDialog(
              context: context,
              builder: (_) => Dialog(
                insetPadding: const EdgeInsets.all(10),
                child: InteractiveViewer(child: Image.network(url)),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.network(
                url,
                width: paths.length == 1 ? 300 : 220,
                height: 170,
                fit: BoxFit.cover,
                cacheWidth: ((paths.length == 1 ? 300 : 220) * dpr).round(),
                errorBuilder: (_, e, s) => Container(
                  width: 220,
                  height: 170,
                  color: Gz.bg,
                  child: const Icon(
                    Icons.broken_image,
                    color: Gz.textSecondary,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
