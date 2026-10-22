import 'package:flutter/material.dart';

import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import '../profile/reviews_screen.dart';
import 'applications_screen.dart' show DocGallery;
import 'executor_form.dart';
import 'order_admin.dart';
import 'overview_extras.dart' show ExecutorHistoryCard;
import 'staff_screen.dart' show StaffAccess;
import 'trust_actions.dart' show kBlockReasonPresets;

/// Барлық орындаушылар: іздеу, қарау, бұғаттау, баланс түзету.
class ExecutorsScreen extends StatefulWidget {
  const ExecutorsScreen({super.key});

  @override
  State<ExecutorsScreen> createState() => _ExecutorsScreenState();
}

/// Тізім жолы: орындаушы профилі + оның жалпы профилі (аты, телефоны).
typedef _Row = (ExecutorProfile, Profile?);

class _ExecutorsScreenState extends State<ExecutorsScreen> {
  String? _status;
  final _search = TextEditingController();
  late Future<List<_Row>> _future = _load();
  late Future<List<Map<String, dynamic>>> _drafts =
      Repo.modRegistrationDrafts();

  bool get _showDrafts => _status == 'drafts';

  /// Орындаушылар + олардың профильдері БІР сұраумен (бұрын әр карточка
  /// профилін бөлек сұрайтын — 100 орындаушы = 100 сұрау).
  Future<List<_Row>> _load() async {
    final eps = await Repo.executorsByStatus(_status);
    final profiles = await Repo.profilesByIds([for (final e in eps) e.userId]);
    return [for (final e in eps) (e, profiles[e.userId])];
  }

  void _reload() {
    setState(() {
      if (_showDrafts) {
        _drafts = Repo.modRegistrationDrafts();
      } else {
        _future = _load();
      }
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(_Row r, String q) {
    if (q.isEmpty) return true;
    final (e, p) = r;
    final hay = [
      p?.fullName,
      p?.phone,
      e.vehiclePlate,
      e.vehicleTitle,
      e.city,
      e.vehicleType.label,
    ].whereType<String>().join(' ').toLowerCase();
    // Мемлекеттік нөмірді бос орынсыз да табу үшін («123ABC02»).
    final compact = hay.replaceAll(' ', '');
    return hay.contains(q) || compact.contains(q.replaceAll(' ', ''));
  }

  Future<void> _add() async {
    if (await showExecutorForm(context)) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: StaffAccess.can('executors_edit')
          ? FloatingActionButton.extended(
              onPressed: _add,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: Text(t('Орындаушы қосу')),
            )
          : null,
      body: _body(),
    );
  }

  Widget _body() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: t('Аты, телефон немесе көлік нөмірі бойынша іздеу'),
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () => setState(_search.clear),
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Row(
            children: [
              for (final (s, label) in <(String?, String)>[
                (null, t('Барлығы')),
                ('approved', t('Расталған')),
                ('pending', t('Күтуде')),
                ('rejected', t('Қабылданбаған')),
                ('blocked', t('Бұғатталған')),
                ('drafts', t('Тіркелуді аяқтамағандар')),
              ]) ...[
                ChoiceChip(
                  label: Text(label),
                  selected: _status == s,
                  onSelected: (v) {
                    _status = s;
                    _reload();
                  },
                ),
                const SizedBox(width: 6),
              ],
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            color: Gz.ink,
            onRefresh: () async => _reload(),
            child: _showDrafts ? _draftsList() : _executorsList(),
          ),
        ),
      ],
    );
  }

  Widget _executorsList() {
    return FutureBuilder<List<_Row>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return ListView(
            children: [
              const SizedBox(height: 100),
              LoadErrorState(onRetry: _reload),
            ],
          );
        }
        final q = _search.text.trim().toLowerCase();
        final rows = (snap.data ?? const <_Row>[])
            .where((r) => _matches(r, q))
            .toList();
        if (rows.isEmpty) {
          return ListView(
            children: [
              const SizedBox(height: 100),
              EmptyState(
                icon: Icons.people_outline,
                title: q.isEmpty
                    ? t('Тізім бос')
                    : t('Сәйкес орындаушы табылмады'),
              ),
            ],
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
          itemCount: rows.length,
          separatorBuilder: (_, i) => const SizedBox(height: 8),
          itemBuilder: (_, i) => _ExecutorTile(
            ep: rows[i].$1,
            profile: rows[i].$2,
            onChanged: _reload,
          ),
        );
      },
    );
  }

  Widget _draftsList() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _drafts,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return ListView(
            children: [
              const SizedBox(height: 100),
              LoadErrorState(onRetry: _reload),
            ],
          );
        }
        final q = _search.text.trim().toLowerCase();
        final rows = (snap.data ?? const <Map<String, dynamic>>[])
            .where(
              (row) => row['role'] == 'executor' && row['completed_at'] == null,
            )
            .where(
              (row) =>
                  q.isEmpty ||
                  '${row['full_name'] ?? ''} ${row['phone'] ?? ''}'
                      .toLowerCase()
                      .contains(q),
            )
            .toList();
        if (rows.isEmpty) {
          return ListView(
            children: [
              const SizedBox(height: 100),
              EmptyState(
                icon: Icons.how_to_reg_outlined,
                title: t('Аяқталмаған тіркелу жоқ'),
              ),
            ],
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
          itemCount: rows.length,
          separatorBuilder: (_, i) => const SizedBox(height: 8),
          itemBuilder: (_, i) => ExecutorDraftTile(row: rows[i]),
        );
      },
    );
  }
}

/// Аккаунт ашу не орындаушы өтінімін толтыру кезінде тоқтаған адам.
/// Бұл жолдар `executor_profiles`-ке әлі түспеген, сондықтан негізгі
/// тізімнен бөлек көрсетіледі. Модератор оған бірден ҚОҢЫРАУ шалып не
/// WhatsApp-қа жазып, тіркелуді аяқтауға көмектесе алады — жоғалған
/// орындаушыны қайтарудың ең тез жолы.
class ExecutorDraftTile extends StatelessWidget {
  final Map<String, dynamic> row;
  const ExecutorDraftTile({super.key, required this.row});

  @override
  Widget build(BuildContext context) {
    final name = (row['full_name'] as String?)?.trim();
    final phone = (row['phone'] as String?)?.trim();
    final data = row['data'] is Map
        ? Map<String, dynamic>.from(row['data'] as Map)
        : const <String, dynamic>{};
    final vehicle = data['vehicle'] is Map
        ? Map<String, dynamic>.from(data['vehicle'] as Map)
        : const <String, dynamic>{};
    final entered = <String>[
      if ((data['city'] as String?)?.isNotEmpty == true) data['city'] as String,
      if ((data['vehicle_type'] as String?)?.isNotEmpty == true)
        vehicleTypeFrom(data['vehicle_type'] as String?).label,
      if ((vehicle['brand'] as String?)?.isNotEmpty == true)
        vehicle['brand'] as String,
      if ((vehicle['plate'] as String?)?.isNotEmpty == true)
        vehicle['plate'] as String,
    ];
    final rawDate = row['last_seen_at'];
    final lastSeen = rawDate is DateTime
        ? rawDate
        : DateTime.tryParse(rawDate?.toString() ?? '');

    return SectionCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Gz.tint(Gz.yellow, 0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.pending_actions_rounded,
                  color: Gz.yellowDeep,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name?.isNotEmpty == true ? name! : t('Аты енгізілмеген'),
                      style: Gz.h3,
                    ),
                    if (phone?.isNotEmpty == true)
                      Text(phone!, style: Gz.caption),
                    const SizedBox(height: 4),
                    Text(
                      '${t('Тоқтаған жері')}: '
                      '${row['stage_label'] ?? t('Белгісіз')}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (entered.isNotEmpty)
                      Text(
                        '${t('Енгізгені')}: ${entered.join(' · ')}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Gz.caption,
                      ),
                    Text(
                      '${t('Соңғы белсенділік')}: '
                      '${lastSeen == null ? '—' : fmtDate(lastSeen)}',
                      style: Gz.caption,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (phone?.isNotEmpty == true) ...[
            const SizedBox(height: 10),
            ContactButtons(
              phone: phone!,
              whatsappText: row['role'] == 'executor'
                  ? t(
                      'Сәлеметсіз бе! Tasu-да орындаушы ретінде '
                      'тіркелуді бастапсыз. Аяқтауға көмек керек пе?',
                    )
                  : t(
                      'Сәлеметсіз бе! Tasu-да тіркелуді бастапсыз. '
                      'Аяқтауға көмек керек пе?',
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ExecutorTile extends StatelessWidget {
  final ExecutorProfile ep;
  final Profile? profile;
  final VoidCallback onChanged;
  const _ExecutorTile({
    required this.ep,
    required this.profile,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final (statusLabel, statusColor) = executorStatusLook(ep.status);
    return SectionCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(Gz.radius),
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => ExecutorDetailScreen(ep: ep)),
          );
          onChanged();
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
          child: Row(
            children: [
              InitialsAvatar(
                p?.fullName ?? '?',
                radius: 22,
                imageUrl: p?.avatarUrl,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            p?.fullName ?? '…',
                            overflow: TextOverflow.ellipsis,
                            style: Gz.h3,
                          ),
                        ),
                        const SizedBox(width: 8),
                        InfoChip(text: statusLabel, color: statusColor),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: BtnLabel(
                        '${ep.vehicleLine}'
                        '${ep.city != null ? ' · ${ep.city}' : ''}',
                        style: Gz.caption,
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: BtnLabel(
                        '${t('Баланс')}: ${fmtT(ep.balance)} · '
                        '${t('Табыс')}: ${fmtT(ep.totalEarned)}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (p != null)
                          RatingStars(
                            p.ratingAs('executor'),
                            count: p.ratingCountAs('executor'),
                            size: 12,
                          ),
                        if (ep.busyOrderId != null) ...[
                          const SizedBox(width: 8),
                          InfoChip(
                            icon: Icons.local_shipping_rounded,
                            text: t('Заказда'),
                            color: Gz.green,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (v) =>
                    ExecutorModActions.run(context, ep, v, onDone: onChanged),
                itemBuilder: (_) => ExecutorModActions.menu(ep),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Орындаушы күйінің жазуы мен түсі — тізімде де, бетте де бірдей.
(String, Color) executorStatusLook(String status) => switch (status) {
  'approved' => (t('Расталған'), Gz.success),
  'pending' => (t('Күтуде'), Gz.info),
  'rejected' => (t('Қабылданбаған'), Gz.danger),
  _ => (t('Бұғатталған'), Gz.danger),
};

/// Модератордың орындаушыға жасайтын әрекеттері — тізімдегі «⋮» мәзірінде
/// де, орындаушы бетіндегі әрекет батырмаларында да БІР логика.
class ExecutorModActions {
  static List<PopupMenuEntry<String>> menu(ExecutorProfile ep) => [
    if (ep.status == 'approved')
      PopupMenuItem(
        value: 'request_docs',
        child: Text(t('Құжат жаңартуды сұрау')),
      ),
    if (StaffAccess.can('balance'))
      PopupMenuItem(value: 'balance', child: Text(t('Баланс түзету'))),
    if (ep.status == 'approved' && StaffAccess.can('executors_block'))
      PopupMenuItem(
        value: 'block',
        child: Text(t('Бұғаттау'), style: TextStyle(color: Gz.red)),
      ),
    if (ep.status == 'blocked' && StaffAccess.can('executors_block'))
      PopupMenuItem(value: 'unblock', child: Text(t('Бұғаттан шығару'))),
    // Біржола жою — тек бас модератор.
    if (StaffAccess.isFull)
      PopupMenuItem(
        value: 'delete',
        child: Text(t('Жою'), style: TextStyle(color: Gz.red)),
      ),
  ];

  static Future<void> run(
    BuildContext context,
    ExecutorProfile ep,
    String action, {
    VoidCallback? onDone,
  }) async {
    try {
      switch (action) {
        case 'request_docs':
          final res = await showDialog<(List<String>, String)>(
            context: context,
            builder: (ctx) =>
                _RequestDocsDialog(
                  isForeign: ep.isForeignCitizen,
                  onFoot: ep.onFoot,
                ),
          );
          if (res == null) return;
          await Repo.modRequestDocs(ep.userId, res.$1, res.$2);
          if (context.mounted) showSnack(context, t('Сұраным жіберілді'));
        case 'block':
          final reason = await gzInputDialog(
            context,
            icon: Icons.block_rounded,
            confirmColor: Gz.red,
            title: t('Бұғаттау себебі'),
            presets: [for (final p in kBlockReasonPresets) t(p)],
            confirmLabel: t('Бұғаттау'),
          );
          if (reason == null) return;
          await Repo.modSetExecutorStatus(ep.userId, 'blocked', reason);
          if (context.mounted) showSnack(context, t('Орындаушы бұғатталды'));
        case 'unblock':
          final ok = await confirmDialog(
            context,
            icon: Icons.lock_open_rounded,
            confirmColor: Gz.green,
            title: t('Бұғаттан шығару'),
            message: t(
              'Орындаушы қайта заказ қабылдай алады. Жалғастырамыз ба?',
            ),
            confirmLabel: t('Бұғаттан шығару'),
          );
          if (!ok) return;
          await Repo.modSetExecutorStatus(ep.userId, 'approved', '');
          if (context.mounted) showSnack(context, t('Бұғат алынды'));
        case 'delete':
          final ok = await confirmDialog(
            context,
            icon: Icons.delete_outline_rounded,
            confirmColor: Gz.red,
            title: t('Орындаушыны жою керек пе?'),
            message: t(
              'Аккаунт пен жеке деректері біржола өшеді, нөмірі босайды. '
              'Заказ тарихы бар болса, тарих қалады, бірақ орындаушы '
              'тізімнен кетеді. Қайтару мүмкін емес.',
            ),
            confirmLabel: t('Жою'),
          );
          if (!ok) return;
          try {
            await Repo.executorAdmin('delete', {'user_id': ep.userId});
          } catch (e) {
            if (!context.mounted) return;
            showSnack(
              context,
              e.toString().contains('HAS_ACTIVE_ORDERS')
                  ? t(
                      'Орындаушыда белсенді заказ бар. Алдымен заказды '
                      'аяқтаңыз не тоқтатыңыз.',
                    )
                  : errText(e),
              error: true,
            );
            return;
          }
          if (context.mounted) showSnack(context, t('Орындаушы жойылды'));
        case 'balance':
          final res = await showDialog<(int, String)>(
            context: context,
            builder: (_) => _BalanceDialog(current: ep.balance),
          );
          if (res == null) return;
          await Repo.modAdjustBalance(ep.userId, res.$1, res.$2);
          if (context.mounted) {
            showSnack(
              context,
              '${t('Баланс түзетілді')}: ${res.$1 > 0 ? '+' : ''}${fmtT(res.$1)}',
            );
          }
      }
      onDone?.call();
    } catch (e) {
      if (context.mounted) showSnack(context, errText(e), error: true);
    }
  }
}

/// Баланс түзету: «Қосу / Шегеру» + сома + себеп (дайын нұсқалармен).
class _BalanceDialog extends StatefulWidget {
  final int current;
  const _BalanceDialog({required this.current});

  @override
  State<_BalanceDialog> createState() => _BalanceDialogState();
}

class _BalanceDialogState extends State<_BalanceDialog> {
  bool _add = true;
  final _amount = TextEditingController();
  final _note = TextEditingController();

  static const _presets = [
    'Бонус',
    'Қате толтыруды түзету',
    'Өтемақы',
    'Тариф ақысын қайтару',
  ];

  int? get _value {
    final v = int.tryParse(_amount.text.replaceAll(RegExp(r'\D'), ''));
    return (v == null || v == 0) ? null : v;
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = _value;
    return GzDialogFrame(
      icon: Icons.account_balance_wallet_outlined,
      color: _add ? Gz.green : Gz.red,
      title: t('Баланс түзету'),
      message: '${t('Қазіргі баланс')}: ${fmtT(widget.current)}',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(
                value: true,
                icon: const Icon(Icons.add_rounded),
                label: Text(t('Қосу')),
              ),
              ButtonSegment(
                value: false,
                icon: const Icon(Icons.remove_rounded),
                label: Text(t('Шегеру')),
              ),
            ],
            selected: {_add},
            onSelectionChanged: (s) => setState(() => _add = s.first),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            decoration: InputDecoration(
              hintText: t('Сома'),
              prefixIcon: Icon(_add ? Icons.add_rounded : Icons.remove_rounded),
              suffixText: '₸',
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final p in _presets)
                ChoiceChip(
                  label: Text(t(p)),
                  selected: _note.text == t(p),
                  onSelected: (_) => setState(() => _note.text = t(p)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _note,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(hintText: t('Себебі')),
          ),
        ],
      ),
      actions: [
        gzDialogCancel(context, t('Болдырмау')),
        gzDialogPrimary(
          t('Сақтау'),
          color: _add ? Gz.green : Gz.red,
          onPressed: v == null
              ? null
              : () =>
                    Navigator.pop(context, (_add ? v : -v, _note.text.trim())),
        ),
      ],
    );
  }
}

/// Құжат жаңартуды сұрау диалогы — қай құжатты + түсініктеме.
class _RequestDocsDialog extends StatefulWidget {
  final bool isForeign;
  final bool onFoot;
  const _RequestDocsDialog({required this.isForeign, this.onFoot = false});

  @override
  State<_RequestDocsDialog> createState() => _RequestDocsDialogState();
}

class _RequestDocsDialogState extends State<_RequestDocsDialog> {
  final _fields = <String>{};
  final _comment = TextEditingController();

  List<(String, String)> get _options => [
    widget.isForeign
        ? ('passport', t('Шетел паспорты'))
        : ('id', t('Жеке куәлік')),
    if (!widget.onFoot) ...[
      ('license', t('Жүргізуші куәлігі')),
      ('tech', t('Техпаспорт')),
      ('photos', t('Көлік фотолары')),
    ],
  ];

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GzDialogFrame(
      icon: Icons.assignment_late_outlined,
      color: Gz.warning,
      title: t('Қай құжатты жаңарту керек?'),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (key, label) in _options)
            ConfirmCheck(
              value: _fields.contains(key),
              onChanged: (v) => setState(() {
                if (v) {
                  _fields.add(key);
                } else {
                  _fields.remove(key);
                }
              }),
              label: Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(label, style: const TextStyle(fontSize: 15)),
              ),
            ),
          const SizedBox(height: 8),
          TextField(
            controller: _comment,
            decoration: InputDecoration(
              hintText: t('Түсініктеме (мыс: анық емес, ескірген)'),
            ),
          ),
        ],
      ),
      actions: [
        gzDialogCancel(context, t('Болдырмау')),
        gzDialogPrimary(
          t('Жіберу'),
          onPressed: _fields.isEmpty
              ? null
              : () => Navigator.pop(context, (_fields.toList(), _comment.text)),
        ),
      ],
    );
  }
}

/// Модератор: орындаушының толық картасы — байланыс, әрекеттер,
/// статистика, заказдары, көлігі, құжаттары, пікірлері.
class ExecutorDetailScreen extends StatefulWidget {
  final ExecutorProfile ep;
  const ExecutorDetailScreen({super.key, required this.ep});

  @override
  State<ExecutorDetailScreen> createState() => _ExecutorDetailScreenState();
}

class _ExecutorDetailScreenState extends State<ExecutorDetailScreen> {
  late ExecutorProfile _ep = widget.ep;
  ExecutorProfile get ep => _ep;

  /// Әрекеттен кейін (баланс, бұғаттау) орындаушыны қайта оқимыз — экранда
  /// ескі мән қалмауы үшін.
  Future<void> _refresh() async {
    final fresh = await Repo.executorProfileOf(ep.userId, fresh: true);
    if (fresh != null && mounted) setState(() => _ep = fresh);
  }

  Future<void> _act(String action) => ExecutorModActions.run(
    context,
    ep,
    action,
    // Жойылған орындаушыны қайта оқуға болмайды — тізімге қайтамыз.
    onDone: action == 'delete'
        ? () {
            if (mounted) Navigator.of(context).pop();
          }
        : _refresh,
  );

  bool _umaySaving = false;

  /// Ауыстырғыштың көрінетін күйі: сервер жауап бергенше оптимистік мән.
  bool? _umayShown;

  /// «Ұмай жүргізушісі» белгісін қою/алу. Көрінетін күй бірден ауысады
  /// (optimistic); қате болса қайтарылып, хабар шығады.
  Future<void> _toggleUmay(bool v) async {
    if (_umaySaving) return;
    setState(() {
      _umaySaving = true;
      _umayShown = v;
    });
    try {
      await Repo.modSetExecutorUmay(ep.userId, v);
      await _refresh();
      if (mounted) {
        showSnack(
          context,
          v ? t('Ұмай жүргізушісі болып белгіленді') : t('Ұмай белгісі алынды'),
        );
      }
    } catch (e) {
      if (mounted) showSnack(context, errText(e), error: true);
    } finally {
      if (mounted) {
        setState(() {
          _umaySaving = false;
          _umayShown = null;
        });
      }
    }
  }

  List<(String?, String)> get _docs => [
    if (!ep.onFoot) ...[
      (ep.licensePath, t('Жүргізуші куәлігі')),
      (ep.licenseSelfiePath, t('Правамен селфи')),
    ],
    if (!ep.isForeignCitizen) ...[
      (ep.idDocPath, t('Жеке куәлік')),
      (ep.idSelfiePath, t('Куәлікпен селфи')),
    ] else ...[
      (ep.passportPath, t('Шетел паспорты')),
      (ep.passportSelfiePath, t('Паспортпен селфи')),
    ],
    if (!ep.onFoot) ...[
      (ep.techPassportPath, t('Техпаспорт')),
      (ep.techPassportSelfiePath, t('Техпаспортпен фото')),
      for (var i = 0; i < ep.vehiclePhotos.length; i++)
        (ep.vehiclePhotos[i], '${t('Көлік')} ${i + 1}'),
    ],
  ];

  @override
  Widget build(BuildContext context) {
    final (statusLabel, statusColor) = executorStatusLook(ep.status);
    return Scaffold(
      appBar: AppBar(title: Text(t('Орындаушы'))),
      body: FutureBuilder<Profile?>(
        future: Repo.profileOf(ep.userId),
        builder: (context, psnap) {
          final p = psnap.data;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        InitialsAvatar(
                          p?.fullName ?? '?',
                          radius: 28,
                          imageUrl: p?.avatarUrl,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p?.fullName ?? '…', style: Gz.h2),
                              Text(p?.phone ?? '', style: Gz.caption),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  InfoChip(
                                    text: statusLabel,
                                    color: statusColor,
                                  ),
                                  const SizedBox(width: 8),
                                  if (p != null)
                                    RatingStars(
                                      p.ratingAs('executor'),
                                      count: p.ratingCountAs('executor'),
                                      size: 13,
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (p != null && p.phone.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      ContactButtons(phone: p.phone),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Әрекеттер — бұрын тек тізімдегі «⋮» мәзірінде болатын.
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (StaffAccess.can('executors_edit'))
                    _actionChip(
                      Icons.edit_outlined,
                      t('Өзгерту'),
                      Gz.blue,
                      () async {
                        if (await showExecutorForm(
                          context,
                          ep: ep,
                          profile: p,
                        )) {
                          await _refresh();
                          if (mounted) setState(() {});
                        }
                      },
                    ),
                  if (ep.status == 'approved')
                    _actionChip(
                      Icons.assignment_late_outlined,
                      t('Құжат сұрау'),
                      Gz.warning,
                      () => _act('request_docs'),
                    ),
                  _actionChip(
                    Icons.account_balance_wallet_outlined,
                    t('Баланс түзету'),
                    Gz.info,
                    () => _act('balance'),
                  ),
                  if (ep.status == 'approved' &&
                      StaffAccess.can('executors_block'))
                    _actionChip(
                      Icons.block_rounded,
                      t('Бұғаттау'),
                      Gz.red,
                      () => _act('block'),
                    ),
                  if (ep.status == 'blocked' &&
                      StaffAccess.can('executors_block'))
                    _actionChip(
                      Icons.lock_open_rounded,
                      t('Бұғаттан шығару'),
                      Gz.green,
                      () => _act('unblock'),
                    ),
                  if (StaffAccess.isFull)
                    _actionChip(
                      Icons.delete_outline_rounded,
                      t('Жою'),
                      Gz.red,
                      () => _act('delete'),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              FutureBuilder<Map<String, dynamic>>(
                future: Repo.modExecutorSummary(ep.userId),
                builder: (context, snap) {
                  final s = snap.data;
                  if (s == null) {
                    return const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  return Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: StatTile(
                              label: t('Бүгін'),
                              value: '${s['today']}',
                              hint: t('заказ'),
                              color: Gz.green,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: StatTile(
                              label: t('7 күн'),
                              value: '${s['week']}',
                              hint: t('заказ'),
                              color: Gz.blue,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: StatTile(
                              label: t('Барлығы'),
                              value: '${s['total']}',
                              hint: t('заказ'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: StatTile(
                              label: t('Белсенді'),
                              value: '${s['active']}',
                              color: Gz.violet,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: StatTile(
                              label: t('Бас тартқан'),
                              value: '${s['cancelled']}',
                              color: Gz.red,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: StatTile(
                              label: t('Бүгінгі табыс'),
                              value: fmtT(s['earned_today'] as num?),
                              color: Gz.green,
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
              if (ep.busyOrderId != null) ...[
                const SizedBox(height: 16),
                SectionTitle(t('Қазіргі заказы')),
                FutureBuilder<Order?>(
                  future: Repo.orderById(ep.busyOrderId!),
                  builder: (context, snap) {
                    final o = snap.data;
                    if (o == null) return const SizedBox.shrink();
                    return OrderCard(
                      order: o,
                      onTap: () => showOrderAdminSheet(
                        context,
                        o.id,
                        onChanged: () => setState(() {}),
                      ),
                    );
                  },
                ),
              ],
              const SizedBox(height: 16),
              SectionTitle(t('Заказ тарихы және қабылдағандары')),
              FutureBuilder<List<Order>>(
                future: Repo.modOrdersOf(ep.userId, asExecutor: true),
                builder: (context, snap) {
                  final orders = snap.data ?? const <Order>[];
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (orders.isEmpty) {
                    return SectionCard(
                      child: Text(
                        t('Әзірге қабылдаған заказ жоқ'),
                        style: Gz.bodyMuted,
                      ),
                    );
                  }
                  return Column(
                    children: [
                      for (final o in orders.take(10)) ...[
                        OrderCard(
                          order: o,
                          onTap: () => showOrderAdminSheet(
                            context,
                            o.id,
                            onChanged: () => setState(() {}),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ],
                  );
                },
              ),
              const SizedBox(height: 8),
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionTitle(t('Көлік')),
                    InfoRow(t('Көлік түрі'), ep.vehicleType.label),
                    InfoRow(t('Маркасы'), ep.vehicleTitle),
                    if (ep.city != null) InfoRow(t('Қала'), ep.city!),
                    if (!ep.onFoot)
                      InfoRow(t('Мемлекеттік нөмір'), ep.vehiclePlate),
                    InfoRow(t('Баланс'), fmtT(ep.balance)),
                    InfoRow(t('Жалпы табыс'), fmtT(ep.totalEarned)),
                    // Ұмай такси: әйел жүргізуші белгісі. Тек такси
                    // жүргізушісіне (немесе белгісі бар болса — алу үшін).
                    if ((ep.vehicleType == VehicleType.taxi || ep.isUmay) &&
                        StaffAccess.can('executors_edit'))
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          t('Ұмай жүргізушісі'),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          t('Әйел жүргізуші — Ұмай заказдарын да көреді'),
                        ),
                        value: _umayShown ?? ep.isUmay,
                        onChanged: _umaySaving ? null : _toggleUmay,
                      ),
                  ],
                ),
              ),
              ExecutorHistoryCard(userId: ep.userId, createdAt: ep.createdAt),
              const SizedBox(height: 16),
              SectionTitle(
                t('Құжаттар'),
                trailing: InfoChip(
                  text: ep.isForeignCitizen
                      ? t('Шетел азаматы')
                      : t('ҚР азаматы'),
                ),
              ),
              DocGallery(docs: _docs),
              const SizedBox(height: 16),
              if (p != null)
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ReviewsScreen(
                        userId: p.id,
                        name: p.fullName,
                        rating: p.ratingAs('executor'),
                        ratingCount: p.ratingCountAs('executor'),
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.star_outline_rounded),
                  label: Text(t('Пікірлерді қарау')),
                ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  Widget _actionChip(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return ActionChip(
      avatar: Icon(icon, size: 18, color: color),
      label: Text(label),
      side: BorderSide(color: Gz.tint(color, 0.4)),
      backgroundColor: Gz.tint(color, 0.07),
      onPressed: onTap,
    );
  }
}
