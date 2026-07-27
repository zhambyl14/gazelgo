import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import '../auth/executor_apply_screen.dart' show CityPickerSheet;
import 'create_listing_screen.dart';
import 'listing_card.dart';
import 'listing_detail.dart';

/// Хабарландырулар тақтасы — логотип батырмасындағы sidebar-дан ашылады.
///
/// Екі таб бар, екеуі де рөлге БЕЙІМДЕЛГЕН (сол себепті ешкім «қай бөлім
/// маған арналған?» деп ойланбайды):
///
///   ОРЫНДАУШЫДА  1) «Жұмыстар»        — клиенттер жариялаған жұмыстар
///                2) «Менің қызметтерім» — өзі жариялағандары + көру саны
///
///   КЛИЕНТТЕ     1) «Қызметтер»       — орындаушылар жариялаған қызметтер
///                2) «Менің жұмыстарым» — өзі жариялағандары + көру саны
///
/// Көру саны ӘРҚАШАН тек авторға көрінеді (сервер басқаға null қайтарады).
class BoardScreen extends ConsumerStatefulWidget {
  const BoardScreen({super.key});

  @override
  ConsumerState<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends ConsumerState<BoardScreen> {
  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(boardEnabledProvider);
    return enabled.when(
      loading: () => Scaffold(
        appBar: AppBar(title: Text(t('Хабарландырулар'))),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, st) => Scaffold(
        appBar: AppBar(title: Text(t('Хабарландырулар'))),
        body: EmptyState(icon: Icons.wifi_off, title: errText(e)),
      ),
      data: (on) => on ? const _BoardTabs() : const _BoardDisabled(),
    );
  }
}

/// Модератор тақтаны әлі ҚОСПАҒАН күй. Тармақтың өзі sidebar-да «Жаңа»
/// белгісімен көрініп тұрады — басқанда осы экран ашылады.
class _BoardDisabled extends StatelessWidget {
  const _BoardDisabled();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t('Хабарландырулар'))),
      body: EmptyState(
        icon: Icons.lock_clock,
        title: t('Бұл бөлім әлі қосылмаған'),
        subtitle: t(
          'Хабарландырулар тақтасы жақында іске қосылады. Ол қосылған соң '
          'осы жерден орындаушылардың қызметтері мен клиенттердің жұмыстарын '
          'көріп, тікелей хабарласа аласыз.',
        ),
      ),
    );
  }
}

class _BoardTabs extends ConsumerStatefulWidget {
  const _BoardTabs();

  @override
  ConsumerState<_BoardTabs> createState() => _BoardTabsState();
}

class _BoardTabsState extends ConsumerState<_BoardTabs> {
  /// null = барлық қала
  String? _city;
  /// null = барлық көлік түрі
  VehicleType? _vehicle;

  late Future<List<Listing>> _feed;
  late Future<List<Listing>> _mine;

  @override
  void initState() {
    super.initState();
    // Орындаушының тіркелген қаласы белгілі — лентаны сол қаладан бастаймыз.
    _city = ref.read(myExecutorProfileProvider).value?.city;
    _feed = Repo.boardFeed(city: _city, vehicle: _vehicle);
    _mine = Repo.myListings();
  }

  void _reloadFeed() =>
      setState(() => _feed = Repo.boardFeed(city: _city, vehicle: _vehicle));

  void _reloadMine() => setState(() => _mine = Repo.myListings());

  void _reloadAll() {
    _reloadFeed();
    _reloadMine();
  }

  Future<void> _pickCity() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Gz.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const CityPickerSheet(),
    );
    if (picked == null || !mounted) return;
    _city = picked;
    _reloadFeed();
  }

  Future<void> _create() async {
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CreateListingScreen()),
    );
    if (done == true) _reloadAll();
  }

  @override
  Widget build(BuildContext context) {
    final isExecutor =
        (ref.watch(myProfileProvider).value?.role ?? 'client') == 'executor';
    final feedTab = isExecutor ? t('Жұмыстар') : t('Қызметтер');
    final mineTab =
        isExecutor ? t('Менің қызметтерім') : t('Менің жұмыстарым');

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t('Хабарландырулар')),
          bottom: TabBar(tabs: [Tab(text: feedTab), Tab(text: mineTab)]),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _create,
          backgroundColor: Gz.yellow,
          foregroundColor: Gz.ink,
          icon: const Icon(Icons.add),
          label: Text(
            isExecutor ? t('Қызмет беру') : t('Жұмыс беру'),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        body: TabBarView(
          children: [
            _FeedTab(
              future: _feed,
              city: _city,
              vehicle: _vehicle,
              isExecutor: isExecutor,
              onPickCity: _pickCity,
              onClearCity: () {
                _city = null;
                _reloadFeed();
              },
              onVehicle: (v) {
                _vehicle = v;
                _reloadFeed();
              },
              onRefresh: _reloadFeed,
            ),
            _MineTab(
              future: _mine,
              isExecutor: isExecutor,
              onRefresh: _reloadMine,
              onCreate: _create,
            ),
          ],
        ),
      ),
    );
  }
}

/// 1-таб: қарсы рөлдің хабарландырулары (сүзгілермен).
class _FeedTab extends StatelessWidget {
  final Future<List<Listing>> future;
  final String? city;
  final VehicleType? vehicle;
  final bool isExecutor;
  final VoidCallback onPickCity;
  final VoidCallback onClearCity;
  final ValueChanged<VehicleType?> onVehicle;
  final VoidCallback onRefresh;

  const _FeedTab({
    required this.future,
    required this.city,
    required this.vehicle,
    required this.isExecutor,
    required this.onPickCity,
    required this.onClearCity,
    required this.onVehicle,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ---- сүзгілер ----
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: onPickCity,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: Gz.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: city == null ? Gz.border : Gz.ink,
                        width: 1.3,
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.location_city_outlined,
                          size: 17,
                          color: Gz.green,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            city ?? t('Барлық қала'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        if (city != null)
                          GestureDetector(
                            onTap: onClearCity,
                            child: const Icon(
                              Icons.close,
                              size: 17,
                              color: Gz.textSecondary,
                            ),
                          )
                        else
                          const Icon(
                            Icons.expand_more,
                            size: 18,
                            color: Gz.textSecondary,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            children: [
              _vehicleChip(t('Барлығы'), vehicle == null, () => onVehicle(null)),
              for (final v in VehicleType.values) ...[
                const SizedBox(width: 6),
                _vehicleChip(v.label, vehicle == v, () => onVehicle(v)),
              ],
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Listing>>(
            future: future,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return ListView(
                  children: [
                    const SizedBox(height: 60),
                    EmptyState(
                      icon: Icons.wifi_off,
                      title: errText(snap.error!),
                    ),
                  ],
                );
              }
              final items = snap.data ?? const <Listing>[];
              if (items.isEmpty) {
                return RefreshIndicator(
                  color: Gz.ink,
                  onRefresh: () async => onRefresh(),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 40),
                      EmptyState(
                        icon: Icons.search_off,
                        title: t('Хабарландыру табылмады'),
                        subtitle: isExecutor
                            ? t('Бұл сүзгі бойынша клиенттердің жұмысы жоқ. '
                                'Қаланы не көлік түрін өзгертіп көріңіз.')
                            : t('Бұл сүзгі бойынша орындаушы қызметі жоқ. '
                                'Қаланы не көлік түрін өзгертіп көріңіз.'),
                      ),
                    ],
                  ),
                );
              }
              return RefreshIndicator(
                color: Gz.ink,
                onRefresh: () async => onRefresh(),
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 96),
                  itemCount: items.length,
                  separatorBuilder: (_, i) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => ListingCard(
                    listing: items[i],
                    onTap: () => showListingSheet(
                      context,
                      items[i].id,
                      onChanged: onRefresh,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _vehicleChip(String label, bool active, VoidCallback onTap) => InkWell(
    borderRadius: BorderRadius.circular(20),
    onTap: onTap,
    child: Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      decoration: BoxDecoration(
        color: active ? Gz.ink : Gz.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: active ? Gz.yellow : Gz.border,
          width: active ? 1.6 : 1.3,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: active ? Colors.white : Gz.ink,
        ),
      ),
    ),
  );
}

/// 2-таб: өз хабарландыруларым — көру санымен (тек өзіме көрінеді).
class _MineTab extends StatelessWidget {
  final Future<List<Listing>> future;
  final bool isExecutor;
  final VoidCallback onRefresh;
  final VoidCallback onCreate;

  const _MineTab({
    required this.future,
    required this.isExecutor,
    required this.onRefresh,
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Listing>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return ListView(
            children: [
              const SizedBox(height: 60),
              EmptyState(icon: Icons.wifi_off, title: errText(snap.error!)),
            ],
          );
        }
        final all = snap.data ?? const <Listing>[];
        final active = all.where((l) => l.isActive).toList();
        final archive = all.where((l) => !l.isActive).toList();

        return RefreshIndicator(
          color: Gz.ink,
          onRefresh: () async => onRefresh(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            children: [
              if (all.isEmpty) ...[
                const SizedBox(height: 30),
                EmptyState(
                  icon: Icons.campaign_outlined,
                  title: isExecutor
                      ? t('Әзірге қызметіңіз жоқ')
                      : t('Әзірге жұмысыңыз жоқ'),
                  subtitle: isExecutor
                      ? t('Қызметіңізді жарияласаңыз, оны клиенттер көреді. '
                          'Қанша адам көргенін осы жерден бақылайсыз.')
                      : t('Жұмысыңызды жарияласаңыз, оны орындаушылар көреді. '
                          'Қанша адам көргенін осы жерден бақылайсыз.'),
                ),
                const SizedBox(height: 16),
                Center(
                  child: SizedBox(
                    width: 240,
                    child: FilledButton(
                      onPressed: onCreate,
                      child: Text(
                        isExecutor ? t('Қызмет беру') : t('Жұмыс беру'),
                      ),
                    ),
                  ),
                ),
              ],
              if (active.isNotEmpty) ...[
                _header(
                  '${t('Лентада')} · ${active.length}/$kListingMaxActive',
                  t('Осы хабарландыруларды басқалар қазір көріп тұр.'),
                ),
                for (final l in active)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ListingCard(
                      listing: l,
                      showViews: true,
                      onTap: () => showListingSheet(
                        context,
                        l.id,
                        onChanged: onRefresh,
                      ),
                    ),
                  ),
              ],
              if (archive.isNotEmpty) ...[
                const SizedBox(height: 8),
                _header(
                  t('Архив'),
                  t('Мерзімі біткен хабарландырулар. Суреттері өшірілген — '
                      'қайта жарияласаңыз, оларды қайта салыңыз.'),
                ),
                for (final l in archive)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ListingCard(
                      listing: l,
                      showViews: true,
                      onTap: () => showListingSheet(
                        context,
                        l.id,
                        onChanged: onRefresh,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _header(String title, String subtitle) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: const TextStyle(color: Gz.textSecondary, fontSize: 12),
        ),
      ],
    ),
  );
}
