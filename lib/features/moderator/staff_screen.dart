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
  final String Function()? hint;
  const StaffPerm(this.key, this.icon, this.label, [this.hint]);
}

/// Барлық рұқсаттар — экранда осы ретпен көрсетіледі.
final List<StaffPerm> kStaffPerms = [
  StaffPerm('support', Icons.support_agent_rounded, () => t('Қолдау чаты')),
  StaffPerm('executors', Icons.local_shipping_outlined, () => t('Орындаушылар')),
  StaffPerm('applications', Icons.assignment_ind_outlined, () => t('Өтінімдер')),
  StaffPerm('topups', Icons.account_balance_wallet_outlined, () => t('Толтырулар')),
  StaffPerm('reports', Icons.flag_outlined, () => t('Шағымдар')),
  StaffPerm('order_chats', Icons.forum_outlined, () => t('Заказ чаттары')),
  StaffPerm('orders', Icons.receipt_long_outlined, () => t('Заказдар')),
  StaffPerm('line', Icons.sensors_rounded, () => t('Линия')),
  StaffPerm('live_map', Icons.map_outlined, () => t('Тірі карта')),
  StaffPerm('clients', Icons.people_outline_rounded, () => t('Клиенттер')),
  StaffPerm(
    'balance',
    Icons.tune_rounded,
    () => t('Баланс түзету'),
    () => t('Орындаушы балансын қолмен өзгерту'),
  ),
  StaffPerm(
    'overview',
    Icons.space_dashboard_outlined,
    () => t('Шолу'),
    () => t('Статистика, графиктер, түсім'),
  ),
  StaffPerm('broadcast', Icons.campaign_outlined, () => t('Жаппай хабарлама')),
  StaffPerm('news', Icons.auto_stories_outlined, () => t('Жаңалықтар')),
  StaffPerm('vehicles', Icons.directions_car_outlined, () => t('Көліктер')),
  StaffPerm('settings', Icons.tune_rounded, () => t('Баптаулар')),
  StaffPerm('audit', Icons.history_rounded, () => t('Әрекеттер журналы')),
];

/// Панельдің ішкі экрандары (мыс. орындаушы мәзіріндегі «Баланс түзету»)
/// рұқсатсыз әрекетті жасыру үшін осыны сұрайды. Мәнін ModeratorShell
/// қояды; қойылмаса (тест, ескі ағын) — бәріне рұқсат, ал нақты шектеуді
/// бәрібір сервер ұстайды (0084).
class StaffAccess {
  static Profile? me;
  static bool can(String perm) => me?.modCan(perm) ?? true;
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
                  message: t('Қызметкер телефон мен құпиясөзбен кіреді де, '
                      'тек сіз белгілеген бөлімдерді көреді. Рұқсатты кез '
                      'келген уақытта өзгертуге болады.'),
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
        for (final p in kStaffPerms)
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.trailing,
            secondary: Icon(p.icon, size: 20, color: Gz.textSecondary),
            title: Text(p.label()),
            subtitle: p.hint == null ? null : Text(p.hint!()),
            value: selected.contains(p.key),
            onChanged: (v) => onChanged(
              v == true ? {...selected, p.key} : ({...selected}..remove(p.key)),
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
      showSnack(context, t('Құпиясөз тым қысқа (кемінде 6 таңба).'),
          error: true);
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
        child: Flexible(
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
      showSnack(context, t('Құпиясөз тым қысқа (кемінде 6 таңба).'),
          error: true);
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
        message: t('Қызметкер кіре алмайды және панельдің ешбір бөлімін '
            'көрмейді. Кейін қайта қосуға болады.'),
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
      message: t('Аккаунт біржола жойылады, нөмірі босайды. Оның әрекеттері '
          'журналда қалады.'),
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
        child: Flexible(
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
                icon: _disabled
                    ? Icons.lock_open_rounded
                    : Icons.block_rounded,
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
      ),
    );
  }
}
