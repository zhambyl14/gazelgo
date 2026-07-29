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

class _BoardTabsState extends ConsumerState<_BoardTabs>
    with SingleTickerProviderStateMixin {
  /// null = барлық қала
  String? _city;
  /// null = барлық көлік түрі
  VehicleType? _vehicle;

  late final TabController _tabs;

  late Future<List<Listing>> _feed;
  late Future<List<Listing>> _mine;

  @override
  void initState() {
    super.initState();
    // Таб ауысқанда FAB көрінісі өзгереді (тек «менікі» табында тұрады) —
    // сол себепті контроллерді өзіміз ұстаймыз.
    _tabs = TabController(length: 2, vsync: this)
      ..addListener(() => setState(() {}));
    // Орындаушының тіркелген қаласы белгілі — лентаны сол қаладан бастаймыз.
    _city = ref.read(myExecutorProfileProvider).value?.city;
    _feed = Repo.boardFeed(city: _city, vehicle: _vehicle);
    _mine = Repo.myListings();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _reloadFeed() =>
      setState(() => _feed = Repo.boardFeed(city: _city, vehicle: _vehicle));

  void _reloadMine() => setState(() => _mine = Repo.myListings());

  void _reloadAll() {
    _reloadFeed();
    _reloadMine();
  }

  void _applyFilter(String? city, VehicleType? vehicle) {
    _city = city;
    _vehicle = vehicle;
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
    // Жариялау батырмасы ТЕК «менің хабарландыруларым» табында тұрады:
    // қарсы рөлдің лентасында ол «мына жұмысқа жауап беру» деп қате
    // оқылатын (клиент «Қызметтер» табында «Жұмыс беру» деген түймені
    // көретін).
    final onMineTab = _tabs.index == 1;

    return Scaffold(
      appBar: AppBar(
        title: Text(t('Хабарландырулар')),
        bottom: TabBar(
          controller: _tabs,
          tabs: [Tab(text: feedTab), Tab(text: mineTab)],
        ),
      ),
      floatingActionButton: onMineTab
          ? FloatingActionButton.extended(
              onPressed: _create,
              backgroundColor: Gz.yellow,
              foregroundColor: Gz.ink,
              icon: const Icon(Icons.add),
              label: Text(
                isExecutor ? t('Қызмет беру') : t('Жұмыс беру'),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            )
          : null,
      body: TabBarView(
        controller: _tabs,
        children: [
          _FeedTab(
            future: _feed,
            city: _city,
            vehicle: _vehicle,
            isExecutor: isExecutor,
            onApply: _applyFilter,
            onRefresh: _reloadFeed,
            taxiOn: ref.watch(taxiEnabledProvider).value ?? false,
          ),
          _MineTab(
            future: _mine,
            isExecutor: isExecutor,
            onRefresh: _reloadMine,
            onCreate: _create,
          ),
        ],
      ),
    );
  }
}

/// 1-таб: қарсы рөлдің хабарландырулары. Барлық сүзгі (қала + көлік түрі)
/// ЖАЛҒЫЗ «Сүзгі» батырмасының артында — тізім жоғарысы таза тұрады.
class _FeedTab extends StatelessWidget {
  final Future<List<Listing>> future;
  final String? city;
  final VehicleType? vehicle;
  final bool isExecutor;

  /// (қала, көлік түрі) — екеуі де null болса «барлығы».
  final void Function(String? city, VehicleType? vehicle) onApply;
  final VoidCallback onRefresh;

  /// «Такси» бөлімі қосулы ма (0046) — сүзгі тізіміне такси сол кезде ғана
  /// кіреді (өшулі болса ол түрдегі хабарландыру мүлдем болмайды).
  final bool taxiOn;

  const _FeedTab({
    required this.future,
    required this.city,
    required this.vehicle,
    required this.isExecutor,
    required this.onApply,
    required this.onRefresh,
    required this.taxiOn,
  });

  int get _activeCount => (city == null ? 0 : 1) + (vehicle == null ? 0 : 1);

  Future<void> _openFilter(BuildContext context) async {
    final res = await showModalBottomSheet<_BoardFilter>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Gz.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) =>
          _FilterSheet(city: city, vehicle: vehicle, taxiOn: taxiOn),
    );
    if (res != null) onApply(res.city, res.vehicle);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ---- сүзгі жолағы ----
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
          child: Row(
            children: [
              _FilterButton(
                count: _activeCount,
                onTap: () => _openFilter(context),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _activeCount == 0
                    ? Text(
                        t('Барлық хабарландыру'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Gz.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    : SizedBox(
                        height: 32,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            if (city != null)
                              _ActiveChip(
                                icon: Icons.location_city_outlined,
                                label: city!,
                                onClear: () => onApply(null, vehicle),
                              ),
                            if (city != null && vehicle != null)
                              const SizedBox(width: 6),
                            if (vehicle != null)
                              _ActiveChip(
                                icon: Icons.local_shipping_outlined,
                                label: vehicle!.label,
                                onClear: () => onApply(city, null),
                              ),
                          ],
                        ),
                      ),
              ),
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

}

/// Сүзгі жолағының сол жағындағы жалғыз батырма. Белсенді сүзгі болса —
/// қара түске боялып, санын көрсетеді.
class _FilterButton extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  const _FilterButton({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final on = count > 0;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: on ? Gz.ink : Gz.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: on ? Gz.yellow : Gz.border,
            width: on ? 1.6 : 1.3,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.tune, size: 17, color: on ? Gz.yellow : Gz.ink),
            const SizedBox(width: 7),
            Text(
              t('Сүзгі'),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: on ? Colors.white : Gz.ink,
              ),
            ),
            if (on) ...[
              const SizedBox(width: 6),
              Container(
                width: 18,
                height: 18,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: Gz.yellow,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: Gz.ink,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Қосулы сүзгінің шағын белгісі — ✕ басқанда сол сүзгі ғана алынады.
class _ActiveChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onClear;
  const _ActiveChip({
    required this.icon,
    required this.label,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 10, right: 6),
      decoration: BoxDecoration(
        color: Gz.bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Gz.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Gz.textSecondary),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 2),
          IconButton(
            onPressed: onClear,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 24, height: 24),
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 15, color: Gz.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Сүзгі парағының нәтижесі.
class _BoardFilter {
  final String? city;
  final VehicleType? vehicle;
  const _BoardFilter(this.city, this.vehicle);
}

/// Бүкіл сүзгі бір жерде: қала + көлік түрі. «Көрсету» басылғанда ғана
/// қолданылады — қолданушы таңдап жатқанда лента бос жыпылықтамайды.
class _FilterSheet extends StatefulWidget {
  final String? city;
  final VehicleType? vehicle;
  final bool taxiOn;
  const _FilterSheet({
    required this.city,
    required this.vehicle,
    required this.taxiOn,
  });

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late String? _city = widget.city;
  late VehicleType? _vehicle = widget.vehicle;

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
    setState(() => _city = picked);
  }

  @override
  Widget build(BuildContext context) {
    final dirty = _city != null || _vehicle != null;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Gz.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    t('Сүзгі'),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (dirty)
                  TextButton(
                    onPressed: () => setState(() {
                      _city = null;
                      _vehicle = null;
                    }),
                    child: Text(t('Тазалау')),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            _label(t('Қала')),
            const SizedBox(height: 6),
            InkWell(
              onTap: _pickCity,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Gz.bg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _city == null ? Gz.border : Gz.ink,
                    width: 1.3,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.location_city_outlined,
                      size: 18,
                      color: Gz.green,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _city ?? t('Барлық қала'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                    if (_city != null)
                      GestureDetector(
                        onTap: () => setState(() => _city = null),
                        child: const Icon(
                          Icons.close,
                          size: 18,
                          color: Gz.textSecondary,
                        ),
                      )
                    else
                      const Icon(
                        Icons.expand_more,
                        size: 19,
                        color: Gz.textSecondary,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _label(t('Көлік түрі')),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.34,
              ),
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _chip(t('Барлығы'), _vehicle == null,
                        () => setState(() => _vehicle = null)),
                    // Такси өшулі болса — тізімде де болмайды (0046).
                    for (final v in (widget.taxiOn
                        ? VehicleType.values
                        : kCargoVehicleTypes))
                      _chip(v.label, _vehicle == v,
                          () => setState(() => _vehicle = v)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () =>
                    Navigator.pop(context, _BoardFilter(_city, _vehicle)),
                child: Text(t('Көрсету')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w800,
      color: Gz.textSecondary,
    ),
  );

  Widget _chip(String label, bool active, VoidCallback onTap) => InkWell(
    borderRadius: BorderRadius.circular(20),
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
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
