import 'package:flutter/material.dart';

import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/vehicle_picker.dart';
import '../../shared/widgets.dart';

/// Хабарландырудың түрі бойынша атауы (ЖАЗБАНЫҢ өзіне қатысты, көрушінің
/// рөліне емес): орындаушының жазбасы — «Қызмет», клиенттікі — «Жұмыс».
String listingKindLabel(ListingKind k) =>
    k == ListingKind.service ? t('Қызмет') : t('Жұмыс');

Color listingKindColor(ListingKind k) =>
    k == ListingKind.service ? Gz.ink : Gz.blue;

/// Хабарландыру карточкасы — лентада да, «менікі» табында да, модератордың
/// шолуында да бір көрініс. [showViews] тек автордың өз тізімінде true
/// (көру саны басқаға ешқашан көрсетілмейді).
class ListingCard extends StatelessWidget {
  final Listing listing;
  final VoidCallback? onTap;
  final bool showViews;

  const ListingCard({
    super.key,
    required this.listing,
    this.onTap,
    this.showViews = false,
  });

  @override
  Widget build(BuildContext context) {
    final l = listing;
    final expired = !l.isActive;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(Gz.radius),
        onTap: onTap,
        child: Opacity(
          // Мерзімі өткен жазба «сөнген» болып көрінеді — белсендіден
          // бір қарағанда ажыратылады.
          opacity: expired ? 0.72 : 1,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Thumb(listing: l),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _badge(
                                listingKindLabel(l.kind),
                                listingKindColor(l.kind),
                                filled: true,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  l.vehicleType.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: Gz.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            l.priceDisplay,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            l.body,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _tag(Icons.location_city_outlined, l.city),
                    if (l.durationDays > 0)
                      _tag(
                        Icons.event_repeat,
                        '${l.durationDays} ${t('күндік жұмыс')}',
                      ),
                    if (showViews && l.views != null)
                      _tag(
                        Icons.visibility_outlined,
                        '${l.views} ${t('көрілді')}',
                        color: Gz.blue,
                      ),
                    if (expired)
                      _tag(
                        Icons.history,
                        t('Мерзімі бітті'),
                        color: Gz.textSecondary,
                      )
                    else
                      _tag(
                        Icons.schedule,
                        '${t('тағы')} ${l.daysLeft} ${t('күн')}',
                        color: l.daysLeft <= 1 ? Gz.red : null,
                      ),
                  ],
                ),
                if (!showViews) ...[
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      InitialsAvatar(
                        l.authorName.isEmpty ? '?' : l.authorName,
                        radius: 12,
                        imageUrl: l.authorAvatar,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          l.authorName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      RatingStars(
                        l.authorRating,
                        count: l.authorRatingCount,
                        size: 12,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _badge(String text, Color color, {bool filled = false}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: filled ? color : color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w800,
        color: filled ? Colors.white : color,
      ),
    ),
  );

  Widget _tag(IconData icon, String text, {Color? color}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color == null ? Gz.bg : color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color ?? Gz.textSecondary),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 11.5,
            color: color ?? Gz.ink,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

/// Карточканың сол жағындағы шағын сурет. Фото жоқ болса (не мерзімі бітіп,
/// Storage-тан тазаланса) — көлік түрінің иконкасы көрсетіледі.
class _Thumb extends StatelessWidget {
  final Listing listing;
  const _Thumb({required this.listing});

  @override
  Widget build(BuildContext context) {
    const size = 66.0;
    if (listing.photos.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Gz.bg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(child: vehicleIcon(listing.vehicleType, size: 32)),
      );
    }
    final px = (size * MediaQuery.devicePixelRatioOf(context)).round();
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        Repo.listingPhotoUrl(listing.photos.first),
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: px,
        cacheHeight: px,
        errorBuilder: (_, e, s) => Container(
          width: size,
          height: size,
          color: Gz.bg,
          child: Center(child: vehicleIcon(listing.vehicleType, size: 32)),
        ),
      ),
    );
  }
}
