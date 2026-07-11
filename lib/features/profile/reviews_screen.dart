import 'package:flutter/material.dart';

import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';

/// Бір адам туралы барлық пікірлер (жеке экран).
class ReviewsScreen extends StatelessWidget {
  final String userId;
  final String name;
  final double rating;
  final int ratingCount;
  const ReviewsScreen({
    super.key,
    required this.userId,
    required this.name,
    this.rating = 0,
    this.ratingCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t('Пікірлер'))),
      body: FutureBuilder<List<Review>>(
        future: Repo.reviewsOf(userId),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final reviews = snap.data ?? [];
          return Column(
            children: [
              Container(
                width: double.infinity,
                color: Gz.surface,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  children: [
                    Text(rating <= 0 ? '—' : rating.toStringAsFixed(1),
                        style: const TextStyle(
                            fontSize: 40, fontWeight: FontWeight.w900)),
                    RatingStars(rating, count: ratingCount, size: 18),
                    const SizedBox(height: 2),
                    Text('$ratingCount ${t('пікір')}',
                        style: const TextStyle(
                            color: Gz.textSecondary, fontSize: 13)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: reviews.isEmpty
                    ? EmptyState(
                        icon: Icons.rate_review_outlined,
                        title: t('Әзірге пікір жоқ'))
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: reviews.length,
                        separatorBuilder: (_, i) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final r = reviews[i];
                          return SectionCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    RatingStars(r.rating.toDouble(), size: 14),
                                    const Spacer(),
                                    Text(
                                      r.authorRole == 'executor'
                                          ? t('Орындаушыдан')
                                          : t('Клиенттен'),
                                      style: const TextStyle(
                                          fontSize: 11.5,
                                          color: Gz.textSecondary),
                                    ),
                                  ],
                                ),
                                if (r.comment.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(r.comment,
                                      style: const TextStyle(fontSize: 14)),
                                ],
                                const SizedBox(height: 4),
                                Text(fmtDate(r.createdAt),
                                    style: const TextStyle(
                                        fontSize: 11.5,
                                        color: Gz.textSecondary)),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
