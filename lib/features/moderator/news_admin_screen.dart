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
/// ҚҰРАСТЫРҒЫШ ([NewsStoryComposer]) — Instagram/WhatsApp үлгісінде: форма
/// емес, ТОЛЫҚ ЭКРАНДЫ сторис. Модератор нақ сол экранның үстінен жазады,
/// түсін ауыстырады, сурет/видео/әуен қосады — көріп тұрғаны қолданушыға
/// баратынымен ДӘЛ БІРДЕЙ (екеуі де `NewsStoryCanvas`/`NewsStoryCaption`
/// виджеттерін қолданады).
///
/// Бөлімнің ӨЗІН қосу және картадағы «Жаңа» жапсырмасы — «Баптаулар»
/// табында (0058 тәртібімен бірдей).
library;

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

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

/// Жазудың түс палитрасы (ARGB). Ақ суреттің үстінде ақ жазу жоғалып
/// кетпеуі үшін модератор ЖАЗЫП ТҰРЫП, көзбен көріп таңдайды.
const _textColors = <int>[
  0xFFFFFFFF, // ақ
  0xFF0F1720, // қара (бренд)
  0xFFFFC400, // сары (бренд)
  0xFF16A34A, // жасыл
  0xFFDC2626, // қызыл
  0xFF2563EB, // көк
];

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
      MaterialPageRoute(builder: (_) => NewsStoryComposer(story: story)),
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
        // `mod_news_save` жазбаны БҮТІНДЕЙ жазады — қалған өрістерді де
        // бергені міндетті, әйтпесе фон түсі мен жазудың орны әдепкіге
        // түсіп кетер еді.
        bgIndex: s.bgIndex,
        layout: s.layout,
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
        // Фоны — стористің ӨЗ түсі: тізімде де қайсысы қандай екені
        // бірден көрініп тұрады.
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: newsStoryGradient(s.bgIndex),
        ),
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
// ҚҰРАСТЫРҒЫШ — Instagram / WhatsApp үлгісіндегі толық экранды редактор
// ============================================================
/// Жаңа сторис жасау (`story == null`) немесе барын өңдеу.
///
/// НЕГЕ ФОРМА ЕМЕС: жаңалық — көзге арналған дүние. Форма толтырғанда
/// модератор нәтижені тек САҚТАҒАН СОҢ көретін де, «жазуым суреттің қай
/// жеріне түсті? түсі оқыла ма?» деген сұрақ жауапсыз қалатын. Мұнда
/// экранның ӨЗІ — сторис: жазу тікелей сол жерде теріледі, түс/сурет/әуен
/// қосылған сәтте көрінеді.
///
/// Оң жақтағы дөңгелек түймелер (Instagram-дағыдай) — қосымша баптаулар:
/// медиа, түс, әуен, сілтеме, ұзақтық, мерзім, аудитория. Әрқайсысы
/// астыңғы парақшаны ашады, жабылған соң өзгеріс дереу экранға түседі.
///
/// Экран `Navigator.pop(true)` арқылы «сақталды» дегенді қайтарады —
/// тізім соны көріп жаңарады.
class NewsStoryComposer extends StatefulWidget {
  final NewsStory? story;
  const NewsStoryComposer({super.key, this.story});

  @override
  State<NewsStoryComposer> createState() => _NewsStoryComposerState();
}

class _NewsStoryComposerState extends State<NewsStoryComposer> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _linkUrl = TextEditingController();
  final _linkLabel = TextEditingController();
  final _musicTitle = TextEditingController();
  final _titleFocus = FocusNode();
  final _bodyFocus = FocusNode();

  String _mediaType = 'text';

  /// Серверде САҚТАУЛЫ жол (өңдеуде — ескісі, жаңа файл жүктелсе — жаңасы).
  String? _mediaPath;
  String? _musicPath;

  /// Жаңа таңдалған файлдың АТЫ — парақшада көрсету үшін.
  String? _mediaName;
  String? _musicName;

  Set<String> _audiences = {'client', 'executor'};
  int _durationSec = 6;
  int _bgIndex = 0;
  bool _active = true;

  /// Жазу мен суреттің экрандағы ОРНЫ, мөлшері және жазудың түсі
  /// (саусақпен сүйрегенде осы өзгереді).
  NewsLayout _layout = const NewsLayout();

  /// Жазу режимі: true — өрістер ашық, пернетақта шығады, сүйреу өшірулі;
  /// false — жазу тек көрінеді әрі саусақпен жылжытылады.
  bool _textEditing = false;

  /// Мерзімі сағатпен: null — мерзімсіз, -1 — «өз мерзімі» ([_customExpires]).
  int? _lifetime = 24;

  /// Дайын нұсқаға дәл келмейтін мерзім (өңдеуде өзгертілмесе сол күйі
  /// сақталады) — әйтпесе модератор жазуын ғана түзеткенде мерзім
  /// байқаусыз ұзарып/қысқарып кетер еді.
  DateTime? _customExpires;

  /// Кейінге жоспарланған шығу уақыты (null — дереу).
  DateTime? _startsAt;

  bool _busy = false;

  /// Видеоның АЛДЫН АЛА КӨРІНІСІ — құрастырғышта да нақты ойнап тұрады
  /// (қолданушы көретін экранмен дәл бірдей болуы үшін).
  VideoPlayerController? _video;
  bool _videoLoading = false;

  /// Видео ашылмағанда — НЕ болғаны. Бұрын қате үнсіз жұтылатын да, экран
  /// жай ғана бос көк фон болып тұратын: модератор видеосының жүктелгенін
  /// де, ойналмағанын да білмейтін.
  String? _videoError;

  /// Әуенді ТЫҢДАП КӨРУ. Автоматты ойнамайды: модератор өзі басады —
  /// әйтпесе әр өңдеуде күтпеген жерден дыбыс шығып кетер еді.
  AudioPlayer? _audio;
  bool _musicPlaying = false;

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
    _bgIndex = s.bgIndex;
    _layout = s.layout;
    _active = s.active;
    _startsAt = s.startsAt;
    _customExpires = s.expiresAt;
    _lifetime = _matchLifetime(s.startsAt, s.expiresAt);
    if (s.isVideo && s.mediaPath != null) _loadVideo(s.mediaPath!);
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _linkUrl.dispose();
    _linkLabel.dispose();
    _musicTitle.dispose();
    _titleFocus.dispose();
    _bodyFocus.dispose();
    _video?.dispose();
    _audio?.dispose();
    super.dispose();
  }

  int? _matchLifetime(DateTime? from, DateTime? to) {
    if (to == null) return null;
    final base = from ?? DateTime.now();
    final hours = to.difference(base).inHours;
    for (final h in _lifetimeHours) {
      if (h != null && (hours - h).abs() <= 1) return h;
    }
    return -1;
  }

  // ---------------------------------------------------------- алдын ала көру

  /// Экранда көрінетін сторис — өрістердің АҒЫМДАҒЫ мәнінен құралады.
  /// Дәл осындай нысанды қолданушы да алады, сол себепті көрініс шындықпен
  /// сәйкес келеді.
  NewsStory get _preview => NewsStory(
    id: widget.story?.id ?? 'preview',
    title: _title.text,
    body: _body.text,
    mediaType: _mediaType,
    mediaPath: _mediaPath,
    musicPath: _musicPath,
    musicTitle: _musicTitle.text,
    linkUrl: _linkUrl.text,
    linkLabel: _linkLabel.text,
    durationSec: _durationSec,
    bgIndex: _bgIndex,
    // ЖАЗУ РЕЖИМІНДЕ жазуды уақытша жоғарырақ көтереміз: әйтпесе ол
    // экранның төменгі жартысында тұрса, пернетақта оны жауып қалып,
    // модератор не жазып жатқанын көрмей қалар еді (Instagram да солай
    // істейді). САҚТАЛАТЫНЫ — өзгермеген `_layout`.
    layout: _textEditing
        ? _layout.copyWith(textX: 0.5, textY: 0.3)
        : _layout,
    audiences: _audiences.toList(),
    active: _active,
    startsAt: _startsAt,
    expiresAt: _expiresAt,
  );

  DateTime? get _expiresAt {
    if (_lifetime == null) return null;
    if (_lifetime == -1) return _customExpires;
    final base = _startsAt ?? DateTime.now();
    return base.add(Duration(hours: _lifetime!));
  }

  Future<void> _loadVideo(String path) async {
    await _video?.dispose();
    final v = VideoPlayerController.networkUrl(
      Uri.parse(Repo.newsMediaUrl(path)),
    );
    if (!mounted) return;
    setState(() {
      _video = v;
      _videoLoading = true;
      _videoError = null;
    });
    try {
      await v.initialize();
      if (!mounted || _video != v) return;
      await v.setLooping(true);
      await v.setVolume(0); // құрастырғышта дыбыс керек емес
      await v.play();
    } catch (e) {
      // Видео ашылмаса да құрастырғыш жұмысын жалғастырады — сақтауға
      // кедергі емес (файл серверде тұр, тек алдын ала көрсете алмадық).
      // Бірақ МОЛЫҚ ҮНСІЗ қалдырмаймыз: экранда неге бос тұрғаны жазылады,
      // әйтпесе «видео қойдым, бірақ көк экран» болып шығады.
      if (mounted && _video == v) {
        _videoError =
            '${t('Бұл видеоны құрылғы ойната алмады. MP4 (H.264) пішіміне '
                'ауыстырып көріңіз.')}\n${errText(e)}';
      }
    } finally {
      if (mounted && _video == v) setState(() => _videoLoading = false);
    }
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
      if (!mounted) return;
      setState(() => _busy = true);
      final path = await Repo.uploadNewsMedia('story.jpg', bytes);
      await _video?.dispose();
      if (!mounted) return;
      setState(() {
        _video = null;
        _videoError = null;
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
      if (!mounted) return;
      setState(() => _busy = true);
      final path = await Repo.uploadNewsMedia(file.name, bytes);
      if (!mounted) return;
      setState(() {
        _mediaPath = path;
        _mediaName = file.name;
        _mediaType = 'video';
        _busy = false;
      });
      await _loadVideo(path);
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
      if (!mounted) return;
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

  /// Әуенді тыңдап көру (парақшадағы ▶/⏹ түймесі).
  Future<void> _toggleMusicPreview() async {
    final path = _musicPath;
    if (path == null) return;
    try {
      if (_musicPlaying) {
        await _audio?.stop();
        if (mounted) setState(() => _musicPlaying = false);
        return;
      }
      final player = _audio ??= AudioPlayer();
      await player.play(UrlSource(Repo.newsMediaUrl(path)));
      if (mounted) setState(() => _musicPlaying = true);
    } catch (e) {
      if (mounted) showSnack(context, errText(e), error: true);
    }
  }

  Future<void> _stopMusicPreview() async {
    if (!_musicPlaying) return;
    await _audio?.stop();
    if (mounted) setState(() => _musicPlaying = false);
  }

  // ---------------------------------------------------------------- сақтау

  /// Жариялауға дайын емес болса — НЕ жетпейтіні, дайын болса null.
  String? get _missing {
    if (_audiences.isEmpty) return t('Кемінде бір аудитория таңдаңыз');
    if (_mediaType != 'text' && (_mediaPath ?? '').isEmpty) {
      return _mediaType == 'video' ? t('Видео жүктеңіз') : t('Сурет жүктеңіз');
    }
    if (_mediaType == 'text' &&
        _title.text.trim().isEmpty &&
        _body.text.trim().isEmpty) {
      return t('Мәтін жазыңыз');
    }
    return null;
  }

  Future<void> _save() async {
    final miss = _missing;
    if (miss != null) {
      showSnack(context, miss, error: true);
      return;
    }
    await _stopMusicPreview();
    if (!mounted) return;
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
        bgIndex: _bgIndex,
        layout: _layout,
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

  /// Шығар алдында: жазғаны болса растатамыз (бір басқанда бәрін жоғалтып
  /// алмауы үшін). Жүйенің «артқа» түймесі де осында түседі ([PopScope]).
  Future<void> _close() async {
    await _stopMusicPreview();
    if (!mounted) return;
    final hasContent =
        _title.text.trim().isNotEmpty ||
        _body.text.trim().isNotEmpty ||
        _mediaPath != null;
    if (!hasContent) {
      Navigator.of(context).pop(false);
      return;
    }
    final ok = await confirmDialog(
      context,
      title: t('Шығу'),
      message: t('Сақталмаған өзгерістер жоғалады.'),
      cancelLabel: t('Қалу'),
      confirmLabel: t('Шығу'),
      confirmColor: Gz.red,
      icon: Icons.close,
    );
    if (ok && mounted) Navigator.of(context).pop(false);
  }

  // ------------------------------------------------------------- орналастыру

  /// Қимыл БАСЫНДАҒЫ масштаб — `onScaleUpdate` масштабты қимылдың басынан
  /// бері есептейді, сол себепті бастапқы мәнді есте сақтап тұрамыз.
  double _scaleBase = 1;

  void _textMoveStart() => _scaleBase = _layout.textScale;

  /// Жазуды сүйреу. `textX`/`textY` — блоктың ОРТАСЫ (экран үлесімен), сол
  /// себепті шеті экраннан асып кетпеуі үшін аздап шектеп қоямыз — бірақ
  /// жазу экранның ЖОҒАРЫСЫНА да, АСТЫНА да, шеттеріне де толық барады.
  void _textMove(double dx, double dy, double scale) {
    setState(() {
      _layout = _layout.copyWith(
        textX: (_layout.textX + dx).clamp(0.10, 0.90),
        textY: (_layout.textY + dy).clamp(0.08, 0.92),
        textScale: (_scaleBase * scale).clamp(0.4, 3.0),
      );
    });
  }

  void _mediaMoveStart() => _scaleBase = _layout.mediaScale;

  void _mediaMove(double dx, double dy, double scale) {
    setState(() {
      _layout = _layout.copyWith(
        mediaX: (_layout.mediaX + dx).clamp(-1.0, 1.0),
        mediaY: (_layout.mediaY + dy).clamp(-1.0, 1.0),
        mediaScale: (_scaleBase * scale).clamp(0.5, 5.0),
      );
    });
  }

  /// Жазуды түрту — ЖАЗУ РЕЖИМІНЕ ауысу (Instagram-дағыдай: сүйреу мен
  /// теру араласып кетпеуі үшін екеуі БӨЛЕК режим).
  void _startTextEdit() {
    setState(() => _textEditing = true);
    // Өріс салынып болған соң фокус береміз, әйтпесе пернетақта ашылмайды.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _titleFocus.requestFocus();
    });
  }

  void _stopTextEdit() {
    FocusScope.of(context).unfocus();
    setState(() => _textEditing = false);
  }

  // ---------------------------------------------------------------- көрініс

  @override
  Widget build(BuildContext context) {
    final s = _preview;
    return PopScope(
      // Жүйенің «артқа» қимылы да растаудан өтуі керек.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _busy) return;
        // Жазу режимінде «артқа» — алдымен сол режимнен шығады.
        if (_textEditing) {
          _stopTextEdit();
          return;
        }
        _close();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        // Пернетақтаны өзіміз есептейміз, әйтпесе фон қысылып, жазудың
        // орны «жылжып» кеткендей көрінер еді.
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            // 1) Стористің ӨЗІ — қолданушы көретін ДӘЛ сол виджет.
            Positioned.fill(
              child: NewsStoryCanvas(
                story: s,
                video: _video,
                loading: _videoLoading,
                error: _videoError,
                showTextFrame: !_textEditing,
                // Жазу режимінде ғана өрістер шығады.
                titleEdit: _textEditing ? _title : null,
                bodyEdit: _textEditing ? _body : null,
                titleFocus: _textEditing ? _titleFocus : null,
                bodyFocus: _textEditing ? _bodyFocus : null,
                // Сүйреу тек ҚАРАУ режимінде (теріп жатқанда емес).
                onTextMoveStart: _textEditing ? null : _textMoveStart,
                onTextMove: _textEditing ? null : _textMove,
                onTextTap: _textEditing ? null : _startTextEdit,
                onMediaMoveStart: _textEditing ? null : _mediaMoveStart,
                onMediaMove: _textEditing ? null : _mediaMove,
                onBackgroundTap: _textEditing ? _stopTextEdit : null,
              ),
            ),

            // 2) Астыңғы жолақ: әуен/сілтеме — қолданушыдағыдай.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(child: NewsStoryCaption(story: s)),
            ),

            // 3) Жоғарғы жолақ: прогресс «үлгісі», жабу, құралдар бағаны.
            if (!_textEditing)
              SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: const LinearProgressIndicator(
                          // Тек ҮЛГІ: қолданушыда осы жерде толып бара
                          // жатқан жолақ тұрады.
                          value: 0.35,
                          minHeight: 2.5,
                          backgroundColor: Colors.white24,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        _roundBtn(
                          Icons.close,
                          onTap: _busy ? null : _close,
                        ),
                        const SizedBox(width: 8),
                        if (_busy)
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                        const Spacer(),
                      ],
                    ),
                    _toolbar(),
                  ],
                ),
              ),

            // 4) ЖАЗУ РЕЖИМІНДЕ: жоғарыда «Дайын», астында түс палитрасы.
            if (_textEditing) _textEditBars(),

            // 5) Ең асты: «Жариялау» (жазу режимінде жасырылады — пернетақта
            //    оны бәрібір жауып тұрар еді).
            if (!_textEditing)
              Positioned(left: 0, right: 0, bottom: 0, child: _publishBar()),
          ],
        ),
      ),
    );
  }

  /// Жазу режиміндегі жолақтар: «Дайын» түймесі мен жазу түсінің палитрасы.
  /// Түсті ДӘЛ ТЕРІП ЖАТҚАНДА таңдау керек — «жазуымның түсі көрінбейді»
  /// деген жағдай сол сәтте, көзбен көріп тұрып шешіледі.
  Widget _textEditBars() {
    return SafeArea(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 10, top: 4),
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Gz.yellow,
                    foregroundColor: Gz.ink,
                    shape: const StadiumBorder(),
                  ),
                  onPressed: _stopTextEdit,
                  child: Text(
                    t('Дайын'),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          // Пернетақтаның ҮСТІНДЕ тұратын түс палитрасы.
          Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 10,
            ),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 14),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(30),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.format_color_text,
                      color: Colors.white70, size: 18),
                  const SizedBox(width: 10),
                  for (final c in _textColors) _colorDot(c),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _colorDot(int argb) {
    final on = _layout.textColor == argb;
    return GestureDetector(
      onTap: () => setState(
        () => _layout = _layout.copyWith(textColor: argb),
      ),
      child: Container(
        width: 26,
        height: 26,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: Color(argb),
          shape: BoxShape.circle,
          border: Border.all(
            color: on ? Gz.yellow : Colors.white38,
            width: on ? 3 : 1,
          ),
        ),
      ),
    );
  }

  Widget _roundBtn(IconData icon, {VoidCallback? onTap}) => GestureDetector(
    onTap: onTap,
    behavior: HitTestBehavior.opaque,
    child: Container(
      margin: const EdgeInsets.only(left: 10, top: 6),
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Colors.black45,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: Colors.white, size: 20),
    ),
  );

  /// Оң жақтағы дөңгелек түймелер — әрқайсысы бір баптауды ашады.
  /// Астындағы кішкене жазу ағымдағы мәнді көрсетеді, сол себепті
  /// парақшаны ашпай-ақ бәрі көрініп тұрады.
  ///
  /// Ені ӘДЕЙІ шектелген (84px): бағанның астындағы аймақ бос қалуы керек —
  /// әйтпесе ол суретті сүйреуді бөгеп қояр еді.
  Widget _toolbar() {
    return Expanded(
      child: Align(
        alignment: Alignment.topRight,
        child: SizedBox(
          width: 84,
          child: SingleChildScrollView(
            // Астыңғы бос орын ӘДЕЙІ үлкен: тізімнің соңғы түймелері
            // «Жариялау» жолағының астына тығылып қалмауы керек (кіші
            // экранда тоғыз құрал сол жолаққа дейін жетеді).
            padding: const EdgeInsets.only(right: 4, top: 4, bottom: 130),
            child: Column(
              children: [
                _tool(
                  icon: Icons.text_fields,
                  label: t('Жазу'),
                  active: _title.text.isNotEmpty || _body.text.isNotEmpty,
                  onTap: _startTextEdit,
                ),
                _tool(
                  icon: _mediaType == 'video'
                      ? Icons.videocam
                      : _mediaType == 'image'
                      ? Icons.image
                      : Icons.wallpaper,
                  label: _mediaType == 'video'
                      ? t('Видео')
                      : _mediaType == 'image'
                      ? t('Сурет')
                      : t('Медиа'),
                  active: _mediaType != 'text',
                  onTap: _mediaSheet,
                ),
                _tool(
                  icon: Icons.palette_outlined,
                  label: t('Түс'),
                  color: newsStoryGradient(_bgIndex).first,
                  onTap: _colorSheet,
                ),
                if (_mediaType != 'text')
                  _tool(
                    icon: Icons.center_focus_strong_outlined,
                    label: t('Ортаға'),
                    onTap: () => setState(
                      () => _layout = _layout.copyWith(
                        mediaX: 0,
                        mediaY: 0,
                        mediaScale: 1,
                      ),
                    ),
                  ),
                _tool(
                  icon: Icons.music_note,
                  label: _musicPath == null ? t('Әуен') : t('Әуен қосулы'),
                  active: _musicPath != null,
                  onTap: _musicSheet,
                ),
                _tool(
                  icon: Icons.link,
                  label: _linkUrl.text.trim().isEmpty
                      ? t('Сілтеме')
                      : t('Сілтеме бар'),
                  active: _linkUrl.text.trim().isNotEmpty,
                  onTap: _linkSheet,
                ),
                _tool(
                  icon: Icons.timer_outlined,
                  label: '$_durationSec ${t('сек')}',
                  onTap: _durationSheet,
                ),
                _tool(
                  icon: Icons.schedule,
                  label: _lifetimeLabel(_lifetime),
                  onTap: _scheduleSheet,
                ),
                _tool(
                  icon: Icons.groups_outlined,
                  label: _audiences.length == _audienceKeys.length
                      ? t('Барлығы')
                      : _audiences.map(_audienceLabel).join(', '),
                  active: true,
                  onTap: _audienceSheet,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tool({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool active = false,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: _busy ? null : onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color ?? Colors.black45,
                shape: BoxShape.circle,
                border: Border.all(
                  color: active ? Gz.yellow : Colors.white24,
                  width: active ? 1.8 : 1,
                ),
              ),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const SizedBox(height: 3),
            // Жазу тар — сыймаса қиылады (суретті жаппауы керек).
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Ең астыңғы жолақ: эфир/жоба қосқышы және «Жариялау» түймесі.
  ///
  /// Түйме ЭКРАННЫҢ БҮКІЛ ЕНІН алады әрі әрқашан басылады — дайын болмаса,
  /// басқанда НЕ жетпейтіні қалқымамен айтылады. Бұрын ол оң жақ бұрышта,
  /// құралдар бағанының қасында кішкене тұрғандықтан модератор оны мүлдем
  /// байқамай, «жариялау түймесі жоқ» деп жүретін.
  Widget _publishBar() {
    final miss = _missing;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Color(0xF2000000)],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 30, 14, 8),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                // Өшірулі күйде де сақтауға болады — «жоба» (тек модератор
                // көреді).
                GestureDetector(
                  onTap: () => setState(() => _active = !_active),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _active ? Icons.visibility : Icons.visibility_off,
                          color: _active ? Gz.green : Colors.white54,
                          size: 18,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          _active ? t('Эфирде') : t('Жоба'),
                          style: TextStyle(
                            color: _active ? Gz.green : Colors.white54,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                if (miss != null)
                  Expanded(
                    child: Text(
                      miss,
                      maxLines: 2,
                      style: const TextStyle(
                        color: Gz.yellow,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Gz.yellow,
                foregroundColor: Gz.ink,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: const StadiumBorder(),
              ),
              onPressed: _busy ? null : _save,
              icon: Icon(_isNew ? Icons.send : Icons.check, size: 19),
              label: Text(
                _isNew ? t('ЖАРИЯЛАУ') : t('САҚТАУ'),
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15.5,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------- парақшалар

  /// Барлық баптау парақшасы БІРДЕЙ көрінеді. Жабылған соң `setState` —
  /// өзгеріс дереу стористің өзіне түседі.
  ///
  /// `setSheet` — парақшаның ІШІН қайта салуға (қосқыш басылғаны сол
  /// жерде көрінуі үшін); `setState` — АРТЫНДАҒЫ стористі жаңартуға.
  Future<void> _sheet(String title, Widget Function(StateSetter) body) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Gz.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
            left: 18,
            right: 18,
            top: 16,
            bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 12),
                body(setSheet),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _mediaSheet() => _sheet(
    t('Түрі'),
    (setSheet) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.image_outlined),
          title: Text(t('Сурет')),
          subtitle: Text(
            _mediaType == 'image' && _mediaPath != null
                ? (_mediaName ?? t('Файл жүктелген'))
                : t('Галереядан таңдау'),
          ),
          trailing: _mediaType == 'image'
              ? const Icon(Icons.check_circle, color: Gz.green)
              : null,
          onTap: () async {
            Navigator.pop(context);
            await _pickImage();
          },
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.videocam_outlined),
          title: Text(t('Видео')),
          subtitle: Text(
            _mediaType == 'video' && _mediaPath != null
                ? (_mediaName ?? t('Файл жүктелген'))
                : t('Қысқа видео (40 МБ-қа дейін)'),
          ),
          trailing: _mediaType == 'video'
              ? const Icon(Icons.check_circle, color: Gz.green)
              : null,
          onTap: () async {
            Navigator.pop(context);
            await _pickVideo();
          },
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.text_fields),
          title: Text(t('Мәтін')),
          subtitle: Text(t('Медиасыз — түсті фонға жазу')),
          trailing: _mediaType == 'text'
              ? const Icon(Icons.check_circle, color: Gz.green)
              : null,
          onTap: () async {
            // Жүктелген файл серверде қалады, бірақ САҚТАҒАНДА мәтіндік
            // сторис файлсыз жазылады да, ескісі өшіру кезегіне түседі.
            await _video?.dispose();
            if (!mounted) return;
            setState(() {
              _video = null;
              _videoError = null;
              _mediaType = 'text';
            });
            Navigator.pop(context);
          },
        ),
      ],
    ),
  );

  Future<void> _colorSheet() => _sheet(
    t('Фон түсі'),
    (setSheet) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t('Мәтіндік стористе — бүкіл фон. Суретте/видеода — айналасындағы '
              'жиек түсі.'),
          style: const TextStyle(color: Gz.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (var i = 0; i < newsStoryGradients.length; i++)
              GestureDetector(
                onTap: () {
                  setState(() => _bgIndex = i);
                  setSheet(() {});
                },
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: newsStoryGradients[i],
                    ),
                    border: Border.all(
                      color: _bgIndex == i ? Gz.yellow : Gz.border,
                      width: _bgIndex == i ? 3 : 1,
                    ),
                  ),
                  child: _bgIndex == i
                      ? const Icon(Icons.check, color: Colors.white, size: 20)
                      : null,
                ),
              ),
          ],
        ),
      ],
    ),
  );

  Future<void> _musicSheet() async {
    await _sheet(
      t('Әуен'),
      (setSheet) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.music_note, color: Gz.violet),
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
              if (_musicPath != null) ...[
                IconButton(
                  tooltip: t('Тыңдап көру'),
                  onPressed: () async {
                    await _toggleMusicPreview();
                    setSheet(() {});
                  },
                  icon: Icon(
                    _musicPlaying ? Icons.stop_circle : Icons.play_circle_fill,
                    color: Gz.violet,
                  ),
                ),
                IconButton(
                  tooltip: t('Алып тастау'),
                  onPressed: () async {
                    await _stopMusicPreview();
                    if (!mounted) return;
                    setState(() {
                      _musicPath = null;
                      _musicName = null;
                      _musicTitle.clear();
                    });
                    setSheet(() {});
                  },
                  icon: const Icon(Icons.close, color: Gz.red),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              Navigator.pop(context);
              await _pickMusic();
            },
            icon: const Icon(Icons.library_music_outlined, size: 18),
            label: Text(
              _musicPath == null ? t('Әуен таңдау') : t('Басқасын таңдау'),
            ),
          ),
          if (_musicPath != null) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _musicTitle,
              onChanged: (_) => setSheet(() {}),
              decoration: InputDecoration(
                labelText: t('Әуеннің атауы (экранда көрінеді)'),
              ),
            ),
          ],
        ],
      ),
    );
    // Парақша жабылды — тыңдап көру де тоқтасын.
    await _stopMusicPreview();
  }

  Future<void> _linkSheet() => _sheet(
    t('«Толығырақ» түймесі'),
    (setSheet) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          t('Бос болса — түйме мүлдем шықпайды.'),
          style: const TextStyle(color: Gz.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _linkUrl,
          keyboardType: TextInputType.url,
          onChanged: (_) => setSheet(() {}),
          decoration: const InputDecoration(
            labelText: 'https://…',
            prefixIcon: Icon(Icons.link, size: 19),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _linkLabel,
          onChanged: (_) => setSheet(() {}),
          decoration: InputDecoration(
            labelText: t('Түйменің жазуы («Толығырақ»)'),
          ),
        ),
      ],
    ),
  );

  Future<void> _durationSheet() => _sheet(
    t('Экранда тұру уақыты'),
    (setSheet) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                onChanged: (v) {
                  setState(() => _durationSec = v.round());
                  setSheet(() {});
                },
              ),
            ),
            SizedBox(
              width: 58,
              child: Text(
                '$_durationSec ${t('сек')}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Future<void> _scheduleSheet() => _sheet(
    t('Қанша уақыт тұрады'),
    (setSheet) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          t('Мерзімі өткенде сторис қолданушыға МҮЛДЕМ көрінбейді (сіз оны '
              'осында өңдей бересіз).'),
          style: const TextStyle(color: Gz.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          children: [
            for (final h in _lifetimeHours)
              ChoiceChip(
                label: Text(_lifetimeLabel(h)),
                selected: _lifetime == h,
                onSelected: (_) {
                  setState(() => _lifetime = h);
                  setSheet(() {});
                },
              ),
            if (_lifetime == -1)
              ChoiceChip(
                label: Text(t('Өз мерзімі')),
                selected: true,
                onSelected: (_) {},
              ),
          ],
        ),
        const Divider(height: 24),
        Row(
          children: [
            const Icon(Icons.schedule, size: 19, color: Gz.textSecondary),
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
              onPressed: () async {
                await _pickStart();
                setSheet(() {});
              },
              child: Text(t('Уақыт қою')),
            ),
            if (_startsAt != null)
              IconButton(
                tooltip: t('Дереу шығарту'),
                onPressed: () {
                  setState(() => _startsAt = null);
                  setSheet(() {});
                },
                icon: const Icon(Icons.close, size: 18),
              ),
          ],
        ),
      ],
    ),
  );

  Future<void> _audienceSheet() => _sheet(
    t('Кімге көрінеді'),
    (setSheet) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t('Кемінде біреуін таңдаңыз. «Гест» — қосымшаға әлі кірмеген '
              'қолданушы.'),
          style: const TextStyle(color: Gz.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          children: [
            for (final key in _audienceKeys)
              FilterChip(
                label: Text(_audienceLabel(key)),
                selected: _audiences.contains(key),
                onSelected: (v) {
                  setState(() {
                    if (v) {
                      _audiences.add(key);
                    } else {
                      _audiences.remove(key);
                    }
                  });
                  setSheet(() {});
                },
              ),
          ],
        ),
      ],
    ),
  );

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

  String _fmtFull(DateTime d) {
    two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}.${d.year} ${two(d.hour)}:'
        '${two(d.minute)}';
  }
}
