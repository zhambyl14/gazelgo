import 'package:flutter/material.dart';

import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/phone.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';

/// Модератор панелінің бір бөліміне рұқсат (0084). [key] — сервердегі
/// `staff_perm_keys()`-пен бірдей.
class StaffPerm {
  final String key;
  final IconData icon;
  final String Function() label;

  /// Дәл не істей алатынын түсіндіретін жол — қызметкерге рұқсат
  /// бергенде модератор нені ашып жатқанын көрсін.
  final String Function() hint;

  /// Тәуелді рұқсат: бұл белгіленсе, [requires] да автоматты белгіленеді
  /// (мыс. бұғаттау үшін орындаушылар тізімін ашу керек).
  final String? requires;
  const StaffPerm(this.key, this.icon, this.label, this.hint, {this.requires});
}

/// Рұқсаттар тобы (экранда тақырыппен бөлінеді).
class StaffPermGroup {
  final String Function() title;
  final List<StaffPerm> perms;
  const StaffPermGroup(this.title, this.perms);
}

final List<StaffPermGroup> kStaffPermGroups = [
  StaffPermGroup(() => t('Қолдау'), [
    StaffPerm(
      'support',
      Icons.support_agent_rounded,
      () => t('Қолдау чаты'),
      () => t('Клиент пен орындаушылардың қолдау чатына жауап береді'),
    ),
    StaffPerm(
      'order_chats',
      Icons.forum_outlined,
      () => t('Заказ чаттары'),
      () => t('Клиент пен орындаушы арасындағы заказ чаттарын оқиды'),
    ),
    StaffPerm(
      'reports',
      Icons.flag_outlined,
      () => t('Шағымдар'),
      () => t('Шағымдарды қарап, шешеді (мәртебесін өзгертеді)'),
    ),
  ]),
  StaffPermGroup(() => t('Орындаушылар'), [
    StaffPerm(
      'executors',
      Icons.local_shipping_outlined,
      () => t('Орындаушыларды қарау'),
      () => t(
        'Тізім, іздеу, карточка, құжаттар. Құжат жаңартуды сұрай алады. '
        'Өзгерте де, бұғаттай да алмайды',
      ),
    ),
    StaffPerm(
      'executors_edit',
      Icons.edit_outlined,
      () => t('Орындаушыны қосу және өзгерту'),
      () => t(
        'Жаңа орындаушыны қолмен қосады; атын, телефонын, қаласын, '
        'көлігін өзгертеді; Ұмай белгісін қояды',
      ),
      requires: 'executors',
    ),
    StaffPerm(
      'executors_block',
      Icons.block_rounded,
      () => t('Орындаушыны бұғаттау'),
      () => t(
        'Орындаушыны бұғаттайды және бұғаттан шығарады. '
        'Жоя алмайды — жою тек бас модераторға',
      ),
      requires: 'executors',
    ),
    StaffPerm(
      'applications',
      Icons.assignment_ind_outlined,
      () => t('Өтінімдер'),
      () => t('Жаңа орындаушылардың құжаттарын қарап, растайды не қабылдамайды'),
    ),
    StaffPerm(
      'balance',
      Icons.tune_rounded,
      () => t('Баланс түзету'),
      () => t('Орындаушы балансына қолмен қосады не шегереді'),
    ),
    StaffPerm(
      'topups',
      Icons.account_balance_wallet_outlined,
      () => t('Толтырулар'),
      () => t('Баланс толтыру сұранымдарын растайды не қабылдамайды'),
    ),
  ]),
  StaffPermGroup(() => t('Заказдар мен бақылау'), [
    StaffPerm(
      'orders',
      Icons.receipt_long_outlined,
      () => t('Заказдар'),
      () => t('Барлық заказды қарайды, қажет болса тоқтатады не қайта ашады'),
    ),
    StaffPerm(
      'line',
      Icons.sensors_rounded,
      () => t('Линия'),
      () => t('Қазір желідегі орындаушылар мен күтіп тұрған заказдар'),
    ),
    StaffPerm(
      'live_map',
      Icons.map_outlined,
      () => t('Тірі карта'),
      () => t('Орындаушылар мен заказдарды картада нақты уақытта көреді'),
    ),
    StaffPerm(
      'clients',
      Icons.people_outline_rounded,
      () => t('Клиенттер'),
      () => t('Клиенттер тізімі, карточкасы, аккаунтын бұғаттау'),
    ),
  ]),
  StaffPermGroup(() => t('Жүйе'), [
    StaffPerm(
      'overview',
      Icons.space_dashboard_outlined,
      () => t('Шолу'),
      () => t('Статистика, графиктер, түсім'),
    ),
    StaffPerm(
      'broadcast',
      Icons.campaign_outlined,
      () => t('Жаппай хабарлама'),
      () => t('Барлық пайдаланушыға push-хабарлама жібереді'),
    ),
    StaffPerm(
      'news',
      Icons.auto_stories_outlined,
      () => t('Жаңалықтар'),
      () => t('Жаңалықтарды қосады, өзгертеді, өшіреді'),
    ),
    StaffPerm(
      'vehicles',
      Icons.directions_car_outlined,
      () => t('Көліктер'),
      () => t('Көлік түрлерінің каталогын өзгертеді'),
    ),
    StaffPerm(
      'settings',
      Icons.tune_rounded,
      () => t('Баптаулар'),
      () => t('Қосымша баптаулары: бағалар, тарифтер, байланыс'),
    ),
    StaffPerm(
      'audit',
      Icons.history_rounded,
      () => t('Әрекеттер журналы'),
      () => t('Барлық модератор мен қызметкердің әрекеттер тарихын көреді'),
    ),
  ]),
];

/// Барлық рұқсаттар (топтарсыз, жалпақ тізім).
final List<StaffPerm> kStaffPerms = [
  for (final g in kStaffPermGroups) ...g.perms,
];

/// Панельдің ішкі экрандары (мыс. орындаушы мәзіріндегі «Баланс түзету»)
/// рұқсатсыз әрекетті жасыру үшін осыны сұрайды. Мәнін ModeratorShell
/// қояды; қойылмаса (тест, ескі ағын) — бәріне рұқсат, ал нақты шектеуді
/// бәрібір сервер ұстайды (0084).
class StaffAccess {
  static Profile? me;
  static bool can(String perm) => me?.modCan(perm) ?? true;

  /// Толық (бас) модератор ме. Профиль белгісіз болса — жоқ деп есептейміз:
  /// бұл тек қауіпті әрекеттерді (орындаушыны жою) ашады.
  static bool get isFull => me?.isFullModerator ?? false;
}

/// Жаңа қызметкерге әдепкі белгіленетін — қолдаудың негізгі жұмысы.
const kDefaultStaffPerms = [
  'support',
  'executors',
  'applications',
  'topups',
  'reports',
  'order_chats',
];

/// Модератор: ҚОЛДАУ ҚЫЗМЕТКЕРЛЕРІ (0084). Телефон + құпиясөзбен аккаунт
/// ашу, панельдің қай бөлімдері ашық болатынын белгілеу, құпиясөз
/// ауыстыру, уақытша өшіру, жою. Тек толық модераторға көрінеді.
class StaffScreen extends StatefulWidget {
  const StaffScreen({super.key});

  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> {
  late Future<List<Map<String, dynamic>>> _future = Repo.modStaffList();

  void _reload() => setState(() => _future = Repo.modStaffList());

  Future<void> _create() async {
    final ok = await showGzSheet<bool>(
      context,
      builder: (_) => const _CreateStaffSheet(),
    );
    if (ok == true) _reload();
  }

  Future<void> _open(Map<String, dynamic> s) async {
    final changed = await showGzSheet<bool>(
      context,
      builder: (_) => _StaffSheet(staff: s),
    );
    if (changed == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Gz.bg,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: Text(t('Қызметкер қосу')),
      ),
      body: FutureBuilder(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return LoadErrorState(
              onRetry: _reload,
              subtitle: Repo.isMissingFunction(snap.error!)
                  ? t('Серверде 0084 миграциясы әлі қолданылмаған.')
                  : errText(snap.error!),
            );
          }
          final list = snap.data!;
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 96),
              children: [
                GzNotice(
                  tone: NoticeTone.info,
                  icon: Icons.badge_outlined,
                  message: t(
                    'Қызметкер телефон мен құпиясөзбен кіреді де, '
                    'тек сіз белгілеген бөлімдерді көреді. Рұқсатты кез '
                    'келген уақытта өзгертуге болады.',
                  ),
                ),
                const SizedBox(height: 14),
                if (list.isEmpty)
                  EmptyState(
                    icon: Icons.support_agent_rounded,
                    title: t('Әзірге қызметкер жоқ'),
                    subtitle: t('«Қызметкер қосу» батырмасын басыңыз.'),
                  )
                else
                  for (final s in list) _tile(s),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _tile(Map<String, dynamic> s) {
    final perms = [for (final p in (s['perms'] as List? ?? const [])) '$p'];
    final disabled = s['disabled'] == true;
    final names = [
      for (final p in kStaffPerms)
        if (perms.contains(p.key)) p.label(),
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(Gz.rLg),
        onTap: () => _open(s),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InitialsAvatar('${s['full_name'] ?? ''}', radius: 21),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${s['full_name'] ?? ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Gz.h3,
                          ),
                        ),
                        if (disabled)
                          InfoChip(text: t('Өшірілген'), color: Gz.danger),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      Phone.pretty('${s['phone'] ?? ''}'),
                      style: Gz.bodyMuted,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      names.isEmpty
                          ? t('Ешбір бөлімге рұқсат жоқ')
                          : names.join(' · '),
                      style: Gz.caption,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Gz.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Рұқсаттарды белгілейтін тізім (жаңа қызметкер мен өңдеуде ортақ).
class _PermsPicker extends StatelessWidget {
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  const _PermsPicker({required this.selected, required this.onChanged});

  /// Рұқсатты қосу/алу. Тәуелділікті сақтайды: «бұғаттау/өзгерту» қосылса,
  /// «орындаушыларды қарау» да қосылады; «қарау» алынса, тәуелділері де кетеді.
  Set<String> _toggle(StaffPerm p, bool on) {
    final next = {...selected};
    if (on) {
      next.add(p.key);
      if (p.requires != null) next.add(p.requires!);
    } else {
      next.remove(p.key);
      for (final q in kStaffPerms) {
        if (q.requires == p.key) next.remove(q.key);
      }
    }
    return next;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: SectionTitle(t('Рұқсаттар'))),
            TextButton(
              onPressed: () => onChanged(
                selected.length == kStaffPerms.length
                    ? <String>{}
                    : {for (final p in kStaffPerms) p.key},
              ),
              child: Text(
                selected.length == kStaffPerms.length
                    ? t('Бәрін алу')
                    : t('Бәрін белгілеу'),
              ),
            ),
          ],
        ),
        for (final g in kStaffPermGroups) ...[
          Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 2),
            child: Text(
              g.title().toUpperCase(),
              style: Gz.caption.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
            ),
          ),
          for (final p in g.perms)
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.trailing,
              secondary: Icon(p.icon, size: 20, color: Gz.textSecondary),
              title: Text(p.label()),
              subtitle: Text(p.hint()),
              isThreeLine: true,
              value: selected.contains(p.key),
              onChanged: (v) => onChanged(_toggle(p, v == true)),
            ),
        ],
        const SizedBox(height: 10),
        GzNotice(
          tone: NoticeTone.info,
          icon: Icons.shield_outlined,
          message: t(
            'Тек бас модератор: орындаушыны толық жою, қызметкерлерді '
            'қосу және олардың рұқсатын өзгерту. Бұларды қызметкерге беру мүмкін емес.',
          ),
        ),
      ],
    );
  }
}

class _CreateStaffSheet extends StatefulWidget {
  const _CreateStaffSheet();

  @override
  State<_CreateStaffSheet> createState() => _CreateStaffSheetState();
}

class _CreateStaffSheetState extends State<_CreateStaffSheet> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  Set<String> _perms = {...kDefaultStaffPerms};
  bool _busy = false;
  bool _showPassword = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final phone = Phone.normalize(_phone.text);
    final password = _password.text;
    if (name.length < 2) {
      showSnack(context, t('Аты-жөнін жазыңыз'), error: true);
      return;
    }
    if (phone == null) {
      showSnack(context, t('Телефон нөмірі дұрыс емес.'), error: true);
      return;
    }
    if (password.length < 6) {
      showSnack(
        context,
        t('Құпиясөз тым қысқа (кемінде 6 таңба).'),
        error: true,
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await Repo.staffAdmin('create', {
        'full_name': name,
        'phone': phone,
        'password': password,
        'perms': _perms.toList(),
      });
      if (!mounted) return;
      showSnack(context, t('Қызметкер қосылды'));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showSnack(
        context,
        e.toString().contains('PHONE_TAKEN')
            ? t('Бұл нөмірмен аккаунт бар. Басқа нөмір жазыңыз.')
            : errText(e),
        error: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      child: GzSheetBody(
        title: t('Жаңа қызметкер'),
        showClose: true,
        child: ListView(
          shrinkWrap: true,
          children: [
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: t('Аты-жөні'),
                prefixIcon: const Icon(Icons.person_outline_rounded),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: t('Телефон'),
                hintText: '+7 7XX XXX XX XX',
                prefixIcon: const Icon(Icons.phone_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _password,
              obscureText: !_showPassword,
              decoration: InputDecoration(
                labelText: t('Құпиясөз'),
                helperText: t('Кемінде 6 таңба. Қызметкерге өзіңіз беріңіз.'),
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  onPressed: () =>
                      setState(() => _showPassword = !_showPassword),
                  icon: Icon(
                    _showPassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            _PermsPicker(
              selected: _perms,
              onChanged: (v) => setState(() => _perms = v),
            ),
            const SizedBox(height: 14),
            GzPrimaryButton(
              label: _busy ? t('Күте тұрыңыз…') : t('Аккаунт ашу'),
              icon: Icons.person_add_alt_1_rounded,
              onPressed: _busy ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}

/// Бар қызметкер: рұқсаттар, құпиясөз, өшіру/қосу, жою.
class _StaffSheet extends StatefulWidget {
  final Map<String, dynamic> staff;
  const _StaffSheet({required this.staff});

  @override
  State<_StaffSheet> createState() => _StaffSheetState();
}

class _StaffSheetState extends State<_StaffSheet> {
  late Set<String> _perms = {
    for (final p in (widget.staff['perms'] as List? ?? const [])) '$p',
  };
  late final Set<String> _initial = {..._perms};
  bool _busy = false;

  String get _id => widget.staff['id'] as String;
  bool get _disabled => widget.staff['disabled'] == true;
  bool get _dirty =>
      _perms.length != _initial.length || !_perms.containsAll(_initial);

  Future<void> _run(Future<void> Function() job, String done) async {
    setState(() => _busy = true);
    try {
      await job();
      if (!mounted) return;
      showSnack(context, done);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showSnack(context, errText(e), error: true);
    }
  }

  Future<void> _savePerms() => _run(
    () => Repo.modStaffSetPerms(_id, _perms.toList()),
    t('Рұқсаттар сақталды'),
  );

  Future<void> _password() async {
    final p = await gzInputDialog(
      context,
      title: t('Жаңа құпиясөз'),
      hint: t('Кемінде 6 таңба'),
      maxLines: 1,
      keyboardType: TextInputType.visiblePassword,
      confirmLabel: t('Сақтау'),
    );
    if (p == null || !mounted) return;
    if (p.length < 6) {
      showSnack(
        context,
        t('Құпиясөз тым қысқа (кемінде 6 таңба).'),
        error: true,
      );
      return;
    }
    await _run(
      () => Repo.staffAdmin('set_password', {'user_id': _id, 'password': p}),
      t('Құпиясөз ауыстырылды'),
    );
  }

  Future<void> _toggleDisabled() async {
    if (!_disabled) {
      final ok = await confirmDialog(
        context,
        title: t('Аккаунтты өшіру керек пе?'),
        message: t(
          'Қызметкер кіре алмайды және панельдің ешбір бөлімін '
          'көрмейді. Кейін қайта қосуға болады.',
        ),
        confirmLabel: t('Өшіру'),
        icon: Icons.block_rounded,
        confirmColor: Gz.red,
      );
      if (!ok || !mounted) return;
    }
    await _run(
      () => Repo.staffAdmin('set_disabled', {
        'user_id': _id,
        'disabled': !_disabled,
      }),
      _disabled ? t('Аккаунт қосылды') : t('Аккаунт өшірілді'),
    );
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(
      context,
      title: t('Қызметкерді жою керек пе?'),
      message: t(
        'Аккаунт біржола жойылады, нөмірі босайды. Оның әрекеттері '
        'журналда қалады.',
      ),
      confirmLabel: t('Жою'),
      icon: Icons.delete_outline_rounded,
      confirmColor: Gz.red,
    );
    if (!ok || !mounted) return;
    await _run(
      () => Repo.staffAdmin('delete', {'user_id': _id}),
      t('Қызметкер жойылды'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.staff;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      child: GzSheetBody(
        title: '${s['full_name'] ?? ''}',
        subtitle: Phone.pretty('${s['phone'] ?? ''}'),
        showClose: true,
        child: ListView(
          shrinkWrap: true,
          children: [
            _PermsPicker(
              selected: _perms,
              onChanged: (v) => setState(() => _perms = v),
            ),
            const SizedBox(height: 12),
            GzPrimaryButton(
              label: t('Рұқсаттарды сақтау'),
              icon: Icons.check_rounded,
              onPressed: _busy || !_dirty ? null : _savePerms,
            ),
            const SizedBox(height: 14),
            const Divider(height: 1),
            GzListRow(
              icon: Icons.password_rounded,
              color: Gz.blue,
              title: t('Құпиясөзді ауыстыру'),
              onTap: _busy ? null : _password,
            ),
            GzListRow(
              icon: _disabled ? Icons.lock_open_rounded : Icons.block_rounded,
              color: _disabled ? Gz.green : Gz.warning,
              title: _disabled ? t('Аккаунтты қосу') : t('Аккаунтты өшіру'),
              onTap: _busy ? null : _toggleDisabled,
            ),
            GzListRow(
              icon: Icons.delete_outline_rounded,
              color: Gz.red,
              title: t('Жою'),
              danger: true,
              onTap: _busy ? null : _delete,
            ),
          ],
        ),
      ),
    );
  }
}
