/// «Жаңалықтар» бөлімін БАСҚАРУ экраны (0066) — модератордың жаңа табы.
///
/// Осында модератор SQL-сыз, қосымшаны қайта шығармай:
///   • жаңа сторис ҚОСАДЫ: сурет · қысқа видео · таза мәтін;
///   • үстіне фонда ойнайтын ӘУЕН қоя алады;
///   • «Толығырақ» түймесіне сілтеме береді;
///   • сторис экранда неше СЕКУНД тұратынын қояды;
///   • қашан ШЫҒАТЫНЫН және қашан ЖОҒАЛАТЫНЫН (мерзімін) белгілейді;
///   • КІМГЕ көрінетінін таңдайды: клиент · орындаушы · гест (бірге де);
///   • тізімнің РЕТІН сүйреп ауыстырады (қолданушыда дәл сол ретте);
///   • қосады/өшіреді, өшіреді (медиасы Storage-тан да тазаланады).
///
/// Бөлімнің ӨЗІН қосу және картадағы «Жаңа» жапсырмасы — «Баптаулар»
/// табында (0058 тәртібімен бірдей).
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import '../news/news_story_screen.dart';

/// Аудитория кілттері мен олардың адамға түсінікті атаулары.
const _audienceKeys = ['client', 'executor', 'guest'];

String _audienceLabel(String key) => switch (key) {
  'client' => t('Клиент'),
  'executor' => t('Орындаушы'),
  _ => t('Гест'),
};

/// Мерзім (қанша тұрады) — дайын нұсқалар. null = мерзімсіз.
const _lifetimeHours = <int?>[6, 24, 72, 168, 720, null];

String _lifetimeLabel(int? hours) => switch (hours) {
  6 => '6 ${t('сағат')}',
  24 => '1 ${t('күн')}',
  72 => '3 ${t('күн')}',
  168 => '7 ${t('күн')}',
  720 => '30 ${t('күн')}',
  _ => t('Мерзімсіз'),
};

class NewsAdminScreen extends ConsumerStatefulWidget {
  const NewsAdminScreen({super.key});

  @override
  ConsumerState<NewsAdminScreen> createState() => _NewsAdminScreenState();
}

class _NewsAdminScreenState extends ConsumerState<NewsAdminScreen> {
  List<NewsStory> _items = const [];
  bool _loading = true;
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
      _items = await Repo.modNewsList();
      _error = null;
    } catch (e) {
      _error = errText(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Өзгерістен КЕЙІН: модератор тізімін де, қолданушының лентасын да
  /// жаңартамыз (модератордың өз қосымшасында да карта дұрыс көрінеді).
  Future<void> _refreshAll() async {
    await _load();
    ref.invalidate(newsFeedProvider);
    ref.invalidate(newsEnabledProvider);
  }

  Future<void> _reorder(int from, int to) async {
    // [ReorderableListView.onReorder] жаңа орынды элемент ӘЛІ тізімде
    // тұрған күйде береді — төмен жылжытқанда бір саты түзетеміз
    // (қосымшадағы басқа сүйрелетін тізімдер де осылай жасайды).
    if (to > from) to -= 1;
    final list = [..._items];
    list.insert(to, list.removeAt(from));
    setState(() => _items = list);
    try {
      await Repo.modNewsReorder([for (final s in list) s.id]);
      ref.invalidate(newsFeedProvider);
    } catch (e) {
      if (!mounted) return;
      showSnack(context, errText(e), error: true);
      await _load();
    }
  }

  Future<void> _edit([NewsStory? story]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => NewsEditScreen(story: story)),
    );
    if (saved == true) await _refreshAll();
  }

  Future<void> _toggleActive(NewsStory s, bool v) async {
    try {
      await Repo.modNewsSave(
        id: s.id,
        title: s.title,
        body: s.body,
        mediaType: s.mediaType,
        mediaPath: s.mediaPath,
        musicPath: s.musicPath,
        musicTitle: s.musicTitle,
        linkUrl: s.linkUrl,
        linkLabel: s.linkLabel,
        audiences: s.audiences,
        durationSec: s.durationSec,
        active: v,
        startsAt: s.startsAt,
        expiresAt: s.expiresAt,
      );
      await _refreshAll();
    } catch (e) {
      if (mounted) showSnack(context, errText(e), error: true);
    }
  }

  Future<void> _delete(NewsStory s) async {
    final ok = await confirmDialog(
      context,
      title: t('Жаңалықты өшіру'),
      message: t('Сторис толығымен жойылады: суреті/видеосы да, әуені де '
          'сервердегі қоймадан өшіріледі. Бұл әрекетті КЕРІ ҚАЙТАРУ мүмкін '
          'емес.'),
      cancelLabel: t('Болдырмау'),
      confirmLabel: t('Өшіру'),
      confirmColor: Gz.red,
      icon: Icons.delete_outline,
    );
    if (!ok) return;
    try {
      await Repo.modNewsDelete(s.id);
      await _refreshAll();
    } catch (e) {
      if (mounted) showSnack(context, errText(e), error: true);
    }
  }

  /// Модератордың өзі стористерді ҚОЛДАНУШЫ КӨРЕТІНДЕЙ қарап шығуы
  /// (жарияламай тұрып тексеру үшін) — өшірулісі мен мерзімі өткені де кіреді.
  void _preview(int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NewsStoryScreen(stories: _items, initialIndex: index),
      ),
    );
  }

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
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: Text(t('Жаңалық қосу')),
      ),
      body: RefreshIndicator(
        onRefresh: _refreshAll,
        child: ReorderableListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
          itemCount: _items.length,
          header: _intro(),
          onReorder: _reorder,
          itemBuilder: (context, i) => _tile(_items[i], i),
        ),
      ),
    );
  }

  Widget _intro() => Padding(
    key: const ValueKey('news-intro'),
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t('Стористер қолданушыға логотип батырмасындағы мәзірден, '
              '«Хабарландырулардың» үстінен көрінеді. Реті — осы тізімдегідей '
              '(сүйреп ауыстырыңыз). Бөлімнің ӨЗІН «Баптаулар» табынан '
              'қосасыз.'),
          style: const TextStyle(color: Gz.textSecondary, fontSize: 12.5),
        ),
        if (_items.isEmpty) ...[
          const SizedBox(height: 40),
          EmptyState(
            icon: Icons.auto_awesome,
            title: t('Әзірге жаңалық жоқ'),
            subtitle: t('Төмендегі «Жаңалық қосу» түймесінен бірінші '
                'сторисіңізді жасаңыз.'),
          ),
        ],
      ],
    ),
  );

  Widget _tile(NewsStory s, int index) {
    return Container(
      key: ValueKey(s.id),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
      decoration: BoxDecoration(
        color: Gz.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Gz.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => _preview(index),
            child: _thumb(s),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.title.isEmpty ? t('Атауы жоқ') : s.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _chip(_statusLabel(s), _statusColor(s)),
                    for (final a in s.audiences)
                      _chip(_audienceLabel(a), Gz.blue),
                    if (s.hasMusic) _chip('♪', Gz.violet),
                    _chip('${s.durationSec} ${t('сек')}', Gz.textSecondary),
                    _chip('${s.views} 👁', Gz.textSecondary),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _windowLabel(s),
                  style: const TextStyle(
                    color: Gz.textSecondary,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          Column(
            children: [
              Switch(
                value: s.active,
                activeThumbColor: Gz.green,
                onChanged: (v) => _toggleActive(s, v),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    iconSize: 19,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: t('Өңдеу'),
                    onPressed: () => _edit(s),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    iconSize: 19,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: t('Өшіру'),
                    onPressed: () => _delete(s),
                    icon: const Icon(Icons.delete_outline, color: Gz.red),
                  ),
                  const SizedBox(width: 6),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _thumb(NewsStory s) {
    Widget inner;
    if (s.isImage && s.mediaPath != null) {
      inner = Image.network(
        Repo.newsMediaUrl(s.mediaPath!),
        width: 52,
        height: 68,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) =>
            const Icon(Icons.broken_image_outlined, color: Gz.textSecondary),
      );
    } else if (s.isVideo) {
      inner = const Icon(Icons.play_circle_fill, color: Gz.yellow, size: 26);
    } else {
      inner = const Icon(Icons.article_outlined, color: Gz.yellow, size: 24);
    }
    return Container(
      width: 52,
      height: 68,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Gz.ink,
        borderRadius: BorderRadius.circular(10),
      ),
      child: inner,
    );
  }

  String _statusLabel(NewsStory s) {
    if (!s.active) return t('Өшірулі');
    if (s.isExpired) return t('Мерзімі өтті');
    if (s.isScheduled) return t('Жоспарланған');
    return t('Эфирде');
  }

  Color _statusColor(NewsStory s) {
    if (!s.active) return Gz.textSecondary;
    if (s.isExpired) return Gz.red;
    if (s.isScheduled) return Gz.blue;
    return Gz.green;
  }

  String _windowLabel(NewsStory s) {
    final from = s.startsAt;
    final to = s.expiresAt;
    final start = from == null ? '' : '${t('Басы')}: ${_fmt(from)}';
    final end = to == null ? t('мерзімсіз') : '${t('дейін')}: ${_fmt(to)}';
    return start.isEmpty ? end : '$start · $end';
  }

  String _fmt(DateTime d) {
    two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
  }

  Widget _chip(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: color,
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

// ============================================================
// Стористі ҚҰРУ / ӨҢДЕУ
// ============================================================
/// Жаңа сторис жасау (story == null) немесе барын өңдеу.
///
/// Экран `Navigator.pop(true)` арқылы «сақталды» дегенді қайтарады —
/// тізім соны көріп жаңарады.
class NewsEditScreen extends StatefulWidget {
  final NewsStory? story;
  const NewsEditScreen({super.key, this.story});

  @override
  State<NewsEditScreen> createState() => _NewsEditScreenState();
}

class _NewsEditScreenState extends State<NewsEditScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _linkUrl = TextEditingController();
  final _linkLabel = TextEditingController();
  final _musicTitle = TextEditingController();

  String _mediaType = 'text';

  /// Серверде САҚТАУЛЫ жол (өңдеуде — ескісі, жаңа файл жүктелсе — жаңасы).
  String? _mediaPath;
  String? _musicPath;

  /// Жаңа таңдалған файлдың АТЫ — әлі жүктелмеген күйде көрсету үшін.
  String? _mediaName;
  String? _musicName;

  Set<String> _audiences = {'client', 'executor'};
  int _durationSec = 6;
  bool _active = true;

  /// Мерзімі: сағатпен. null — мерзімсіз.
  int? _lifetime = 24;

  /// Кейінге жоспарланған шығу уақыты (null — дереу).
  DateTime? _startsAt;

  bool _busy = false;

  bool get _isNew => widget.story == null;

  @override
  void initState() {
    super.initState();
    final s = widget.story;
    if (s == null) return;
    _title.text = s.title;
    _body.text = s.body;
    _linkUrl.text = s.linkUrl;
    _linkLabel.text = s.linkLabel;
    _musicTitle.text = s.musicTitle;
    _mediaType = s.mediaType;
    _mediaPath = s.mediaPath;
    _musicPath = s.musicPath;
    _audiences = s.audiences.toSet();
    _durationSec = s.durationSec;
    _active = s.active;
    _startsAt = s.startsAt;
    // Бар стористің мерзімі — «басынан бері неше сағат» деп ЕМЕС, нақты
    // `expires_at` бойынша ең жақын дайын нұсқаға келтіріледі; дәл келмесе
    // «мерзімсіз» болып қалмауы үшін өз мәні сақталады ([_customExpires]).
    _customExpires = s.expiresAt;
    _lifetime = _matchLifetime(s.startsAt, s.expiresAt);
  }

  /// Дайын нұсқаға дәл келмейтін мерзім (өңдеуде өзгертілмесе сол күйі
  /// сақталады) — әйтпесе модератор атауын ғана түзеткенде мерзім
  /// байқаусыз ұзарып/қысқарып кетер еді.
  DateTime? _customExpires;

  int? _matchLifetime(DateTime? from, DateTime? to) {
    if (to == null) return null;
    final base = from ?? DateTime.now();
    final hours = to.difference(base).inHours;
    for (final h in _lifetimeHours) {
      if (h != null && (hours - h).abs() <= 1) return h;
    }
    return -1; // «өз мерзімі» — тізімде бөлек көрсетіледі
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _linkUrl.dispose();
    _linkLabel.dispose();
    _musicTitle.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- файлдар

  Future<void> _pickImage() async {
    try {
      final f = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        // Сторис толық экранға созылады — 1440px жеткілікті, ал сапасы 80
        // мәтінді анық ұстайды әрі трафикті үнемдейді.
        imageQuality: 80,
        maxWidth: 1440,
      );
      if (f == null) return;
      final bytes = await f.readAsBytes();
      setState(() => _busy = true);
      final path = await Repo.uploadNewsMedia('story.jpg', bytes);
      if (!mounted) return;
      setState(() {
        _mediaPath = path;
        _mediaName = f.name;
        _mediaType = 'image';
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showSnack(context, errText(e), error: true);
    }
  }

  Future<void> _pickVideo() async {
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['mp4', 'mov', 'webm'],
        withData: true,
      );
      final file = picked?.files.firstOrNull;
      final bytes = file?.bytes;
      if (bytes == null || file == null) return;
      // Сторис — ҚЫСҚА видео. 40 МБ-тан асқанын жүктемейміз: мобиль
      // интернетте ол ашылғанша сторис аяқталып қалады.
      if (bytes.lengthInBytes > 40 * 1024 * 1024) {
        if (mounted) {
          showSnack(
            context,
            t('Видео тым үлкен (40 МБ-қа дейін болсын)'),
            error: true,
          );
        }
        return;
      }
      setState(() => _busy = true);
      final path = await Repo.uploadNewsMedia(file.name, bytes);
      if (!mounted) return;
      setState(() {
        _mediaPath = path;
        _mediaName = file.name;
        _mediaType = 'video';
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showSnack(context, errText(e), error: true);
    }
  }

  Future<void> _pickMusic() async {
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['mp3', 'm4a', 'aac', 'wav', 'ogg'],
        withData: true,
      );
      final file = picked?.files.firstOrNull;
      final bytes = file?.bytes;
      if (bytes == null || file == null) return;
      if (bytes.lengthInBytes > 15 * 1024 * 1024) {
        if (mounted) {
          showSnack(
            context,
            t('Әуен тым үлкен (15 МБ-қа дейін болсын)'),
            error: true,
          );
        }
        return;
      }
      setState(() => _busy = true);
      final path = await Repo.uploadNewsMedia(file.name, bytes);
      if (!mounted) return;
      setState(() {
        _musicPath = path;
        _musicName = file.name;
        _busy = false;
        if (_musicTitle.text.trim().isEmpty) {
          _musicTitle.text = file.name.replaceAll(RegExp(r'\.\w+$'), '');
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showSnack(context, errText(e), error: true);
    }
  }

  // ---------------------------------------------------------------- сақтау

  /// Сақтауға дайын емес болса — НЕ жетпейтіні, дайын болса null.
  String? get _missing {
    if (_audiences.isEmpty) return t('Кемінде бір аудитория таңдаңыз');
    if (_mediaType != 'text' && (_mediaPath ?? '').isEmpty) {
      return _mediaType == 'video'
          ? t('Видео жүктеңіз')
          : t('Сурет жүктеңіз');
    }
    if (_mediaType == 'text' &&
        _title.text.trim().isEmpty &&
        _body.text.trim().isEmpty) {
      return t('Мәтін жазыңыз');
    }
    return null;
  }

  DateTime? get _expiresAt {
    if (_lifetime == null) return null;
    if (_lifetime == -1) return _customExpires;
    final base = _startsAt ?? DateTime.now();
    return base.add(Duration(hours: _lifetime!));
  }

  Future<void> _save() async {
    final miss = _missing;
    if (miss != null) {
      showSnack(context, miss, error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await Repo.modNewsSave(
        id: widget.story?.id,
        title: _title.text.trim(),
        body: _body.text.trim(),
        mediaType: _mediaType,
        // Мәтіндік стористе бұрын жүктелген файл БОСҚА тұрып қалмауы үшін
        // жолды әдейі тазалаймыз — сервер ескісін өшіру кезегіне қояды.
        mediaPath: _mediaType == 'text' ? null : _mediaPath,
        musicPath: _musicPath,
        musicTitle: _musicTitle.text.trim(),
        linkUrl: _linkUrl.text.trim(),
        linkLabel: _linkLabel.text.trim(),
        audiences: _audiences.toList(),
        durationSec: _durationSec,
        active: _active,
        startsAt: _startsAt,
        expiresAt: _expiresAt,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showSnack(context, errText(e), error: true);
    }
  }

  Future<void> _pickStart() async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: _startsAt ?? now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startsAt ?? now),
    );
    if (time == null || !mounted) return;
    setState(
      () => _startsAt = DateTime(
        day.year,
        day.month,
        day.day,
        time.hour,
        time.minute,
      ),
    );
  }

  // ---------------------------------------------------------------- көрініс

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isNew ? t('Жаңа жаңалық') : t('Жаңалықты өңдеу'),
          style: const TextStyle(fontSize: 16),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          _label(t('Түрі')),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(
                value: 'image',
                label: Text(t('Сурет')),
                icon: const Icon(Icons.image_outlined, size: 17),
              ),
              ButtonSegment(
                value: 'video',
                label: Text(t('Видео')),
                icon: const Icon(Icons.videocam_outlined, size: 17),
              ),
              ButtonSegment(
                value: 'text',
                label: Text(t('Мәтін')),
                icon: const Icon(Icons.article_outlined, size: 17),
              ),
            ],
            selected: {_mediaType},
            onSelectionChanged: (v) => setState(() => _mediaType = v.first),
          ),
          const SizedBox(height: 12),

          if (_mediaType != 'text') _mediaCard(),

          const SizedBox(height: 14),
          _label(t('Жазуы')),
          TextField(
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: t('Тақырып'),
              hintText: t('Мыс.: Жаңа тариф іске қосылды'),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _body,
            minLines: 3,
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: t('Мәтіні')),
          ),

          const SizedBox(height: 18),
          _label(t('Әуен (міндетті емес)')),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.music_note, color: Gz.violet, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _musicName ??
                            (_musicPath == null
                                ? t('Әуен қосылмаған')
                                : t('Әуен қосулы')),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    if (_musicPath != null)
                      IconButton(
                        tooltip: t('Алып тастау'),
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                _musicPath = null;
                                _musicName = null;
                                _musicTitle.clear();
                              }),
                        icon: const Icon(Icons.close, color: Gz.red),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _pickMusic,
                  icon: const Icon(Icons.library_music_outlined, size: 18),
                  label: Text(
                    _musicPath == null ? t('Әуен таңдау') : t('Басқасын таңдау'),
                  ),
                ),
                if (_musicPath != null) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: _musicTitle,
                    decoration: InputDecoration(
                      labelText: t('Әуеннің атауы (экранда көрінеді)'),
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 18),
          _label(t('Кімге көрінеді')),
          Text(
            t('Кемінде біреуін таңдаңыз. «Гест» — қосымшаға әлі кірмеген '
                'қолданушы.'),
            style: const TextStyle(color: Gz.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final key in _audienceKeys)
                FilterChip(
                  label: Text(_audienceLabel(key)),
                  selected: _audiences.contains(key),
                  onSelected: (v) => setState(() {
                    if (v) {
                      _audiences.add(key);
                    } else {
                      _audiences.remove(key);
                    }
                  }),
                ),
            ],
          ),

          const SizedBox(height: 18),
          _label(t('Экранда тұру уақыты')),
          Text(
            t('Сурет пен мәтін осынша секунд тұрады. Видеода видеоның өз '
                'ұзақтығы қолданылады.'),
            style: const TextStyle(color: Gz.textSecondary, fontSize: 12),
          ),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: _durationSec.toDouble(),
                  min: 2,
                  max: 30,
                  divisions: 28,
                  label: '$_durationSec ${t('сек')}',
                  onChanged: (v) => setState(() => _durationSec = v.round()),
                ),
              ),
              SizedBox(
                width: 54,
                child: Text(
                  '$_durationSec ${t('сек')}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),
          _label(t('Қанша уақыт тұрады')),
          Text(
            t('Мерзімі өткенде сторис қолданушыға МҮЛДЕМ көрінбейді (сіз оны '
                'осында өңдей бересіз).'),
            style: const TextStyle(color: Gz.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final h in _lifetimeHours)
                ChoiceChip(
                  label: Text(_lifetimeLabel(h)),
                  selected: _lifetime == h,
                  onSelected: (_) => setState(() => _lifetime = h),
                ),
              if (_lifetime == -1)
                ChoiceChip(
                  label: Text(t('Өз мерзімі')),
                  selected: true,
                  onSelected: (_) {},
                ),
            ],
          ),

          const SizedBox(height: 14),
          SectionCard(
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.schedule,
                      size: 19,
                      color: Gz.textSecondary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _startsAt == null
                            ? t('Дереу шығады')
                            : '${t('Шығады')}: ${_fmtFull(_startsAt!)}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    TextButton(
                      onPressed: _busy ? null : _pickStart,
                      child: Text(t('Уақыт қою')),
                    ),
                    if (_startsAt != null)
                      IconButton(
                        tooltip: t('Дереу шығарту'),
                        onPressed: () => setState(() => _startsAt = null),
                        icon: const Icon(Icons.close, size: 18),
                      ),
                  ],
                ),
                const Divider(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _active
                            ? t('Қосулы — қолданушыға көрінеді')
                            : t('Өшірулі — тек сізде тұрады'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Switch(
                      value: _active,
                      activeThumbColor: Gz.green,
                      onChanged: (v) => setState(() => _active = v),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),
          _label(t('«Толығырақ» түймесі (міндетті емес)')),
          TextField(
            controller: _linkUrl,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'https://…',
              prefixIcon: Icon(Icons.link, size: 19),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _linkLabel,
            decoration: InputDecoration(
              labelText: t('Түйменің жазуы («Толығырақ»)'),
            ),
          ),

          const SizedBox(height: 24),
          if (_missing != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _missing!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Gz.red, fontSize: 12.5),
              ),
            ),
          BusyButton(
            label: _isNew ? t('Жариялау') : t('Сақтау'),
            enabled: !_busy && _missing == null,
            onPressed: _save,
          ),
        ],
      ),
    );
  }

  Widget _mediaCard() {
    final has = (_mediaPath ?? '').isNotEmpty;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (has && _mediaType == 'image')
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                Repo.newsMediaUrl(_mediaPath!),
                height: 190,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox(
                  height: 190,
                  child: Icon(Icons.broken_image_outlined, size: 40),
                ),
              ),
            )
          else
            Container(
              height: has ? 90 : 110,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Gz.bg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _mediaType == 'video'
                        ? Icons.videocam_outlined
                        : Icons.image_outlined,
                    size: 30,
                    color: has ? Gz.green : Gz.textSecondary,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _mediaName ??
                        (has ? t('Файл жүктелген') : t('Файл таңдалмаған')),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: Gz.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _busy
                ? null
                : (_mediaType == 'video' ? _pickVideo : _pickImage),
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_outlined, size: 18),
            label: Text(
              _mediaType == 'video'
                  ? (has ? t('Басқа видео') : t('Видео жүктеу'))
                  : (has ? t('Басқа сурет') : t('Сурет жүктеу')),
            ),
          ),
          if (_mediaType == 'video') ...[
            const SizedBox(height: 6),
            Text(
              t('Қысқа видео (40 МБ-қа дейін). Әуен қосылса, видеоның өз '
                  'дыбысы өшіріледі.'),
              style: const TextStyle(color: Gz.textSecondary, fontSize: 11.5),
            ),
          ],
        ],
      ),
    );
  }

  Widget _label(String s) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      s,
      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
    ),
  );

  String _fmtFull(DateTime d) {
    two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}.${d.year} ${two(d.hour)}:'
        '${two(d.minute)}';
  }
}
