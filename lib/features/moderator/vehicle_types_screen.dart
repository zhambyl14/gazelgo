/// Көлік түрлерін БАСҚАРУ экраны (0050) — модератордың «Көліктер» бөлімі.
///
/// Осында модератор SQL-сыз, қосымшаны қайта шығармай:
///   • жаңа көлік түрін ҚОСАДЫ (коды, атауы, анықтамасы, иконкасы);
///   • керексізін ӨШІРЕДІ (қолданыста болса — жойылмайды, жасырылады);
///   • тізімнің РЕТІН сүйреп ауыстырады (клиенттегі карусель дәл сол ретте);
///   • иконканы PNG етіп жүктейді — суреттің керек жерін ӨЗІ КЕСІП алады,
///     өлшемі автоматты келтіріледі (512×512, мөлдір фон).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/icon_crop.dart';
import '../../shared/widgets.dart';

class VehicleTypesScreen extends ConsumerStatefulWidget {
  const VehicleTypesScreen({super.key});

  @override
  ConsumerState<VehicleTypesScreen> createState() => _VehicleTypesScreenState();
}

class _VehicleTypesScreenState extends ConsumerState<VehicleTypesScreen> {
  List<VehicleSpec> _items = const [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await Repo.modVehicleTypes();
      _items = [for (final r in rows) VehicleSpec.fromMap(r)];
    } catch (e) {
      _error = errText(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Өзгерістен КЕЙІН: модератор тізімін де, қосымшаның каталогын да
  /// жаңартамыз — клиенттегі карусель сол мезетте жаңа тізімді көрсетеді.
  Future<void> _refreshAll() async {
    await _load();
    await VehicleCatalog.load(Repo.vehicleCatalog);
    ref.invalidate(taxiEnabledProvider);
  }

  // ---------------------------------------------------------------- әрекеттер

  /// [ReorderableListView.onReorder] жаңа орынды элемент ӘЛІ тізімде тұрған
  /// күйде береді — сол себепті төмен қарай жылжытқанда бір саты түзетеміз
  /// (қосымшадағы басқа сүйрелетін тізімдер де осылай жасайды).
  Future<void> _reorder(int from, int to) async {
    if (to > from) to -= 1;
    final list = [..._items];
    list.insert(to, list.removeAt(from));
    setState(() => _items = list);
    try {
      await Repo.modReorderVehicleTypes([for (final s in list) s.code]);
      await VehicleCatalog.load(Repo.vehicleCatalog);
    } catch (e) {
      if (!mounted) return;
      showSnack(context, errText(e), error: true);
      await _load();
    }
  }

  Future<void> _toggleActive(VehicleSpec s, bool v) async {
    setState(() => _saving = true);
    try {
      await Repo.modSaveVehicleType(code: s.code, active: v);
      await _refreshAll();
    } catch (e) {
      if (mounted) showSnack(context, errText(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _edit({VehicleSpec? spec}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _VehicleTypeEditor(
          spec: spec,
          existingCodes: [for (final s in _items) s.code],
        ),
      ),
    );
    if (saved == true) await _refreshAll();
  }

  Future<void> _delete(VehicleSpec s) async {
    final ok = await confirmDialog(
      context,
      icon: Icons.delete_outline,
      title: '${s.labelKk} — ${t('жою')}?',
      message: t('Бұл түр қолданыста болса (заказ, орындаушы, хабарландыру) '
          'ол ЖОЙЫЛМАЙДЫ — тек жасырылады, ескі заказдар бұзылмайды.'),
      confirmLabel: t('Иә, жою'),
      confirmColor: Gz.red,
    );
    if (!ok) return;
    setState(() => _saving = true);
    try {
      final res = await Repo.modDeleteVehicleType(s.code);
      await _refreshAll();
      if (!mounted) return;
      showSnack(
        context,
        res == 'deleted'
            ? t('Көлік түрі жойылды')
            : t('Түр қолданыста — тізімнен жасырылды'),
      );
    } catch (e) {
      if (mounted) showSnack(context, errText(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // -------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          EmptyState(icon: Icons.wifi_off, title: _error!),
          const SizedBox(height: 16),
          Center(
            child: OutlinedButton(
              onPressed: _load,
              child: Text(t('Қайталау')),
            ),
          ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving ? null : () => _edit(),
        icon: const Icon(Icons.add),
        label: Text(t('Жаңа түр')),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ReorderableListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
          itemCount: _items.length,
          header: _intro(),
          // Тақырып (header) — жылжымайтын элемент, сол себепті сүйреу
          // индекстері бірге жылжымайды: тізім өзі 0-ден басталады.
          onReorder: _reorder,
          itemBuilder: (context, i) => _tile(_items[i], i),
        ),
      ),
    );
  }

  Widget _intro() => Padding(
        key: const ValueKey('__intro__'),
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t('Клиент пен орындаушы көретін көлік түрлері'),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
            const SizedBox(height: 6),
            Text(
              t('Тізімді сүйреп РЕТІН ауыстырыңыз — каруселде дәл осы ретпен '
                  'тұрады. Қосқыш өшірулі түр клиентке КӨРІНБЕЙДІ. Түрді '
                  'басып атауын, анықтамасын және иконкасын өзгертесіз.'),
              style: const TextStyle(color: Gz.textSecondary, fontSize: 12.5),
            ),
          ],
        ),
      );

  Widget _tile(VehicleSpec s, int index) {
    final dim = !s.active;
    return Container(
      key: ValueKey(s.code),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Gz.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Gz.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 8, 8, 8),
        child: Row(
          children: [
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.drag_indicator, color: Gz.textSecondary),
              ),
            ),
            Opacity(opacity: dim ? 0.4 : 1, child: specIcon(s, size: 34)),
            const SizedBox(width: 10),
            Expanded(
              child: InkWell(
                onTap: _saving ? null : () => _edit(spec: s),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              s.labelKk,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                color: dim ? Gz.textSecondary : Gz.ink,
                              ),
                            ),
                          ),
                          if (s.isTaxi) ...[
                            const SizedBox(width: 6),
                            _chip(t('Такси'), Gz.blue),
                          ],
                        ],
                      ),
                      if (s.descKk.isNotEmpty)
                        Text(
                          s.descKk,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Gz.textSecondary, fontSize: 11.5),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Switch(
              value: s.active,
              onChanged: _saving ? null : (v) => _toggleActive(s, v),
            ),
            IconButton(
              tooltip: t('Жою'),
              onPressed: _saving ? null : () => _delete(s),
              icon: const Icon(Icons.delete_outline, color: Gz.red, size: 20),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          text,
          style: TextStyle(
              fontSize: 9.5, fontWeight: FontWeight.w800, color: color),
        ),
      );
}

// ---------------------------------------------------------------------------
// Иконка (каталогқа тәуелсіз — тікелей жазбадан)
// ---------------------------------------------------------------------------

/// Түрдің суретін көрсету: жүктелген сілтеме → кірістірілген PNG → эмодзи.
/// [vehicleIcon]-нан айырмашылығы — каталогтан емес, БЕРІЛГЕН жазбадан
/// оқиды: модератор экранында әлі сақталмаған өзгеріс те көрінеді.
Widget specIcon(VehicleSpec s, {double size = 34}) {
  Widget fallback() => s.assetIcon != null
      ? Image.asset(s.assetIcon!, width: size, height: size, fit: BoxFit.contain)
      : Text(s.emoji, style: TextStyle(fontSize: size * 0.8, height: 1));

  return SizedBox(
    width: size,
    height: size,
    child: Center(
      child: s.iconUrl == null
          ? fallback()
          // Жүктелген PNG 512×512-ге дейін болуы мүмкін (icon_crop.dart) —
          // мұнда тек [size] пиксельге керек, экран тығыздығына сай
          // ДЕКОДТАП аламыз (жад үнемдеу, flutter-performance §3).
          : Builder(
              builder: (context) {
                final px =
                    (size * MediaQuery.devicePixelRatioOf(context)).round();
                return Image.network(
                  s.iconUrl!,
                  width: size,
                  height: size,
                  fit: BoxFit.contain,
                  cacheWidth: px,
                  cacheHeight: px,
                  loadingBuilder: (_, child, p) =>
                      p == null ? child : fallback(),
                  errorBuilder: (_, _, _) => fallback(),
                );
              },
            ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Қосу / өзгерту экраны
// ---------------------------------------------------------------------------

class _VehicleTypeEditor extends StatefulWidget {
  /// `null` болса — ЖАҢА түр қосылып жатыр.
  final VehicleSpec? spec;
  final List<String> existingCodes;

  const _VehicleTypeEditor({this.spec, required this.existingCodes});

  @override
  State<_VehicleTypeEditor> createState() => _VehicleTypeEditorState();
}

class _VehicleTypeEditorState extends State<_VehicleTypeEditor> {
  late final _code = TextEditingController(text: widget.spec?.code ?? '');
  late final _labelKk = TextEditingController(text: widget.spec?.labelKk ?? '');
  late final _labelRu = TextEditingController(text: widget.spec?.labelRu ?? '');
  late final _descKk = TextEditingController(text: widget.spec?.descKk ?? '');
  late final _descRu = TextEditingController(text: widget.spec?.descRu ?? '');

  late bool _isTaxi = widget.spec?.isTaxi ?? false;
  late bool _active = widget.spec?.active ?? true;

  /// Жаңа жүктелген иконканың сілтемесі (әлі сақталмаған).
  String? _iconUrl;
  bool _uploading = false;

  bool get _isNew => widget.spec == null;

  @override
  void initState() {
    super.initState();
    _iconUrl = widget.spec?.iconUrl;
  }

  @override
  void dispose() {
    _code.dispose();
    _labelKk.dispose();
    _labelRu.dispose();
    _descKk.dispose();
    _descRu.dispose();
    super.dispose();
  }

  /// Коды — латын әріптерімен, тек бір рет қойылады: дерекқордағы ескі
  /// заказдар осы кодқа сүйенеді, сол себепті КЕЙІН ӨЗГЕРТІЛМЕЙДІ.
  String? _codeError() {
    final v = _code.text.trim().toLowerCase();
    if (!_isNew) return null;
    if (!RegExp(r'^[a-z][a-z0-9_]{1,30}$').hasMatch(v)) {
      return t('Код латынша, кіші әріппен: мыс. tral, kran_25t');
    }
    if (widget.existingCodes.contains(v)) return t('Мұндай код бар');
    return null;
  }

  Future<void> _pickIcon() async {
    // Жаңа түрге сурет жүктеу үшін коды алдын ала белгілі болуы керек
    // (файл сол папкаға жазылады).
    final code = _code.text.trim().toLowerCase();
    final err = _codeError();
    if (err != null) {
      showSnack(context, err, error: true);
      return;
    }
    final png = await pickAndCropIcon(context);
    if (png == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      final url = await Repo.uploadVehicleIcon(
          code.isEmpty ? (widget.spec?.code ?? 'icon') : code, png);
      if (mounted) setState(() => _iconUrl = url);
    } catch (e) {
      if (mounted) showSnack(context, errText(e), error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    final err = _codeError();
    if (err != null) {
      showSnack(context, err, error: true);
      return;
    }
    if (_labelKk.text.trim().isEmpty) {
      showSnack(context, t('Атауын жазыңыз'), error: true);
      return;
    }
    await Repo.modSaveVehicleType(
      code: _isNew ? _code.text.trim().toLowerCase() : widget.spec!.code,
      labelKk: _labelKk.text.trim(),
      labelRu: _labelRu.text.trim(),
      descKk: _descKk.text.trim(),
      descRu: _descRu.text.trim(),
      iconUrl: _iconUrl,
      isTaxi: _isTaxi,
      active: _active,
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    // Алдын ала қарау — тізімдегідей етіп көрсетеді.
    final preview = VehicleSpec(
      code: _isNew ? _code.text.trim() : widget.spec!.code,
      labelKk: _labelKk.text.trim(),
      iconUrl: _iconUrl,
      assetIcon: widget.spec?.assetIcon,
      emoji: widget.spec?.emoji ?? '🚚',
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isNew ? t('Жаңа көлік түрі') : widget.spec!.labelKk,
          style: const TextStyle(fontSize: 16),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ---- Иконка ----
          Center(
            child: Column(
              children: [
                GestureDetector(
                  onTap: _uploading ? null : _pickIcon,
                  child: Container(
                    width: 108,
                    height: 108,
                    decoration: BoxDecoration(
                      color: Gz.bg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Gz.border, width: 1.5),
                    ),
                    child: _uploading
                        ? const Center(child: CircularProgressIndicator())
                        : Center(child: specIcon(preview, size: 72)),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _uploading ? null : _pickIcon,
                  icon: const Icon(Icons.image_outlined, size: 18),
                  label: Text(_iconUrl == null
                      ? t('Сурет жүктеу')
                      : t('Суретті ауыстыру')),
                ),
                Text(
                  t('PNG таңдағанда керек жерін өзіңіз кесесіз — '
                      'өлшемі автоматты келтіріледі.'),
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(color: Gz.textSecondary, fontSize: 11.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ---- Коды ----
          if (_isNew) ...[
            TextField(
              controller: _code,
              autocorrect: false,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: t('Коды (латынша)'),
                hintText: 'tral',
                helperMaxLines: 3,
                helperText: t('Дерекқордағы белгісі — кейін ӨЗГЕРТІЛМЕЙДІ. '
                    'Кіші латын әрпі, сан және «_» ғана.'),
                prefixIcon: const Icon(Icons.tag),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // ---- Атауы ----
          TextField(
            controller: _labelKk,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: t('Атауы (қазақша)'),
              hintText: 'Трал',
              prefixIcon: const Icon(Icons.local_shipping_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _labelRu,
            decoration: InputDecoration(
              labelText: t('Атауы (орысша)'),
              helperText: t('Бос болса — қазақша атауы қолданылады.'),
              prefixIcon: const Icon(Icons.translate),
            ),
          ),
          const SizedBox(height: 20),

          // ---- Анықтамасы ----
          Text(
            t('Қысқа анықтама'),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text(
            t('Каруселде таңдалған түрдің АСТЫНДА бір жол болып шығады — '
                'сол себепті ҚЫСҚА жазыңыз (мыс. «Ауыр жүк»).'),
            style: const TextStyle(color: Gz.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _descKk,
            maxLength: 90,
            decoration: InputDecoration(
              labelText: t('Анықтама (қазақша)'),
              hintText: 'Ауыр әрі ірі габаритті техниканы тасымалдау',
              prefixIcon: const Icon(Icons.info_outline),
            ),
          ),
          TextField(
            controller: _descRu,
            maxLength: 90,
            decoration: InputDecoration(
              labelText: t('Анықтама (орысша)'),
              hintText: 'Перевозка тяжёлой и негабаритной техники',
              prefixIcon: const Icon(Icons.translate),
            ),
          ),
          const SizedBox(height: 8),

          // ---- Қосқыштар ----
          SectionCard(
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                  title: Text(t('Көрінеді'),
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14)),
                  subtitle: Text(
                    t('Өшірулі болса клиент те, орындаушы да бұл түрді таппайды.'),
                    style: const TextStyle(fontSize: 11.5),
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _isTaxi,
                  onChanged: (v) => setState(() => _isTaxi = v),
                  title: Text(t('«Такси» санатына жатады'),
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14)),
                  subtitle: Text(
                    t('Қосулы болса — спецтехника каруселінде емес, «Такси» '
                        'санатында тұрады және такси бөлімі өшірулі кезде '
                        'мүлдем көрінбейді.'),
                    style: const TextStyle(fontSize: 11.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          BusyButton(label: t('Сақтау'), onPressed: _save),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
