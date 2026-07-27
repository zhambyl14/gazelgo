import 'package:flutter/material.dart';

import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import '../board/listing_card.dart';

/// Модератордың хабарландырулар тізімі («Шолу» табындағы «толығырақ»).
/// Белсенді және архивтегі хабарландыруларды көріп, ережені бұзғанын
/// біржола өшіре алады.
class ListingsAdminScreen extends StatefulWidget {
  const ListingsAdminScreen({super.key});

  @override
  State<ListingsAdminScreen> createState() => _ListingsAdminScreenState();
}

class _ListingsAdminScreenState extends State<ListingsAdminScreen> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t('Хабарландырулар')),
          bottom: TabBar(
            tabs: [Tab(text: t('Лентада')), Tab(text: t('Архив'))],
          ),
        ),
        body: const TabBarView(
          children: [
            _ListingsList(status: 'active'),
            _ListingsList(status: 'expired'),
          ],
        ),
      ),
    );
  }
}

class _ListingsList extends StatefulWidget {
  final String status;
  const _ListingsList({required this.status});

  @override
  State<_ListingsList> createState() => _ListingsListState();
}

class _ListingsListState extends State<_ListingsList> {
  late Future<List<Listing>> _future = Repo.modListings(widget.status);

  void _reload() => setState(() => _future = Repo.modListings(widget.status));

  Future<void> _delete(Listing l) async {
    final ok = await confirmDialog(
      context,
      title: t('Хабарландыруды өшіру'),
      message: t(
        'Хабарландыру мен оның суреттері біржола жойылады. Автор өз '
        'тізімінен де көрмейді.',
      ),
      confirmLabel: t('Өшіру'),
      confirmColor: Gz.red,
      icon: Icons.delete_forever_outlined,
    );
    if (!ok || !mounted) return;
    try {
      await Repo.deleteListing(l.id);
      _reload();
      if (mounted) showSnack(context, t('Өшірілді'));
    } catch (e) {
      if (mounted) showSnack(context, errText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Listing>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return EmptyState(icon: Icons.wifi_off, title: errText(snap.error!));
        }
        final items = snap.data ?? const <Listing>[];
        if (items.isEmpty) {
          return RefreshIndicator(
            color: Gz.ink,
            onRefresh: () async => _reload(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 80),
                EmptyState(
                  icon: Icons.storefront_outlined,
                  title: t('Хабарландыру жоқ'),
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          color: Gz.ink,
          onRefresh: () async => _reload(),
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            separatorBuilder: (_, i) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final l = items[i];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // showViews: true — модератор көру санын да көреді
                  // (қай хабарландыру шынымен жұмыс істеп тұрғанын бағалау
                  // үшін). Автордың аты төмендегі жолақта көрсетіледі.
                  ListingCard(listing: l, showViews: true),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
                    child: Row(
                      children: [
                        InitialsAvatar(
                          l.authorName.isEmpty ? '?' : l.authorName,
                          radius: 11,
                          imageUrl: l.authorAvatar,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${l.authorName} · '
                            '${l.authorRole == 'executor' ? t('Орындаушы') : t('Клиент')}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Gz.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => _delete(l),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          icon: const Icon(
                            Icons.delete_outline,
                            size: 17,
                            color: Gz.red,
                          ),
                          label: Text(
                            t('Өшіру'),
                            style: const TextStyle(
                              color: Gz.red,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
