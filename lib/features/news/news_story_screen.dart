/// «Жаңалықтар» — толық экранды сторис қарау беті (0066).
///
/// Instagram Stories / WhatsApp Status тәртібі:
///   · жоғарыда әр сторис үшін бір прогресс жолағы, ағымдағысы толып барады;
///   · экранның ОҢ жағын түртсе — келесі, СОЛ жағын түртсе — алдыңғы;
///   · басып ұстап тұрса — тоқтайды (мәтінді оқып үлгеру үшін);
///   · төмен қарай сырғытса — жабылады;
///   · соңғысы біткенде бет өзі жабылады.
///
/// Медиа түрлері: сурет, ҚЫСҚА видео, таза мәтін (градиент фон). Кез келген
/// түрдің үстінен фонда әуен ойнауы мүмкін.
library;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/prefs.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';

/// Стористің фон градиенттері (WhatsApp статусындағыдай палитра).
///
/// Қайсысы қолданылатынын МОДЕРАТОР таңдайды (`NewsStory.bgIndex`) — сол
/// себепті құрастырғыштағы алдын ала көрініс қолданушы көретін экранмен
/// ДӘЛ КЕЛЕДІ. Барлығында ақ жазу анық оқылады.
const newsStoryGradients = <List<Color>>[
  [Color(0xFF1B2836), Color(0xFF0F1720)], // қара-көк (бренд)
  [Color(0xFF3730A3), Color(0xFF1E1B4B)], // күлгін
  [Color(0xFF0E8A3E), Color(0xFF064E28)], // жасыл
  [Color(0xFFE6AC00), Color(0xFF8A6400)], // сары (бренд)
  [Color(0xFFB91C1C), Color(0xFF6B1010)], // қызыл
  [Color(0xFF0E7490), Color(0xFF083344)], // көгілдір
];

/// [NewsStory.bgIndex] тізімнен шығып кетпеуін қамтамасыз етеді (сервер де
/// қысады, бірақ ескі жазба/бұзылған дерек келсе қосымша құламауы керек).
List<Color> newsStoryGradient(int index) =>
    newsStoryGradients[index.clamp(0, newsStoryGradients.length - 1)];

class NewsStoryScreen extends ConsumerStatefulWidget {
  final List<NewsStory> stories;
  final int initialIndex;
  const NewsStoryScreen({
    super.key,
    required this.stories,
    this.initialIndex = 0,
  });

  @override
  ConsumerState<NewsStoryScreen> createState() => _NewsStoryScreenState();
}

class _NewsStoryScreenState extends ConsumerState<NewsStoryScreen>
    with SingleTickerProviderStateMixin {
  late final PageController _pages;
  late final AnimationController _progress;
  late int _index;

  VideoPlayerController? _video;
  AudioPlayer? _audio;

  /// Ұстап тұрғанда да, видео жүктеліп жатқанда да прогресс жүрмеуі керек.
  bool _held = false;
  bool _loading = false;
  String? _mediaError;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.stories.length - 1);
    _pages = PageController(initialPage: _index);
    _progress = AnimationController(vsync: this)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) _next();
      });
    _loading = widget.stories[_index].isVideo;
    // Бірінші кадрдан КЕЙІН бастаймыз: `_start` ішіндегі `setState` build
    // фазасында шақырылып қалмауы керек.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _start(_index);
    });
  }

  @override
  void dispose() {
    _progress.dispose();
    _pages.dispose();
    _video?.dispose();
    _audio?.dispose();
    super.dispose();
  }

  NewsStory get _story => widget.stories[_index];

  // ------------------------------------------------------------ ойнату

  /// Ағымдағы стористі жүктеп, есептегішті бастайды. Алдыңғысының видеосы
  /// мен әуені МІНДЕТТІ түрде тоқтатылады — әйтпесе екеуі қатар ойнап
  /// кетер еді.
  Future<void> _start(int i) async {
    _progress.stop();
    _progress.value = 0;
    await _disposeMedia();

    final s = widget.stories[i];
    _markSeen(s);
    setState(() {
      _mediaError = null;
      _loading = s.isVideo;
    });

    if (s.hasMusic) {
      // Әуен сторис ұзақтығынан қысқа болуы мүмкін — қайталап ойнайды.
      final player = AudioPlayer();
      _audio = player;
      try {
        await player.setReleaseMode(ReleaseMode.loop);
        await player.play(UrlSource(Repo.newsMediaUrl(s.musicPath!)));
      } catch (_) {
        // Әуен ойналмаса сторис сол күйі көрсетіле береді — бұл қосымша
        // мазмұн, оның қатесі беттің өзін бұзбауы керек.
      }
    }

    if (s.isVideo) {
      final v = VideoPlayerController.networkUrl(
        Uri.parse(Repo.newsMediaUrl(s.mediaPath!)),
      );
      _video = v;
      try {
        await v.initialize();
        // Жүктеліп жатқанда бет ауысып кетуі мүмкін — сол кезде бұл
        // контроллер ЕСКІ болып қалады, ештеңе істемейміз.
        if (!mounted || _video != v) return;
        // Әуен қосылған болса видеоның өз дыбысы кедергі жасамауы керек.
        if (s.hasMusic) await v.setVolume(0);
        await v.play();
        setState(() => _loading = false);
        _progress.duration = v.value.duration.inMilliseconds > 0
            ? v.value.duration
            : Duration(seconds: s.durationSec);
        if (!_held) _progress.forward();
      } catch (e) {
        if (!mounted || _video != v) return;
        setState(() {
          _loading = false;
          _mediaError = errText(e);
        });
        _progress.duration = Duration(seconds: s.durationSec);
        if (!_held) _progress.forward();
      }
      return;
    }

    _progress.duration = Duration(seconds: s.durationSec);
    if (!_held) _progress.forward();
  }

  Future<void> _disposeMedia() async {
    final v = _video;
    final a = _audio;
    _video = null;
    _audio = null;
    await v?.pause();
    await v?.dispose();
    await a?.stop();
    await a?.dispose();
  }

  /// Серверде де, құрылғыда да белгілейміз: гесте uid жоқ (сервер үнсіз
  /// өтеді), ал желі болмаса жергілікті белгі сақина жыпылықтауын тоқтатады.
  void _markSeen(NewsStory s) {
    Repo.newsMarkSeen(s.id);
    Prefs.markNewsSeen(s.id);
  }

  // ------------------------------------------------------------ навигация

  void _next() {
    if (_index >= widget.stories.length - 1) {
      _close();
      return;
    }
    _pages.animateToPage(
      _index + 1,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _prev() {
    if (_index == 0) {
      // Бірінші стористе сол жақты түртсе — басынан бастаймыз.
      _progress.value = 0;
      _progress.forward();
      return;
    }
    _pages.animateToPage(
      _index - 1,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _close() {
    if (!mounted) return;
    // Лентадағы «оқылмаған» сақиналары жаңарсын (серверлік те, жергілікті де).
    ref.invalidate(newsFeedProvider);
    ref.invalidate(newsSeenLocalProvider);
    Navigator.of(context).maybePop();
  }

  void _onPageChanged(int i) {
    setState(() => _index = i);
    _start(i);
  }

  void _hold(bool on) {
    if (_held == on) return;
    setState(() => _held = on);
    if (on) {
      _progress.stop();
      _video?.pause();
      _audio?.pause();
    } else {
      if (!_loading) _progress.forward();
      _video?.play();
      _audio?.resume();
    }
  }

  void _onTapUp(TapUpDetails d) {
    final w = MediaQuery.of(context).size.width;
    if (d.globalPosition.dx < w * 0.32) {
      _prev();
    } else {
      _next();
    }
  }

  // ------------------------------------------------------------ көрініс

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: _onTapUp,
        onLongPressStart: (_) => _hold(true),
        onLongPressEnd: (_) => _hold(false),
        onLongPressCancel: () => _hold(false),
        // Төмен қарай сырғыту — жабу (стористердің әдеттегі қимылы).
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) > 250) _close();
        },
        child: Stack(
          children: [
            PageView.builder(
              controller: _pages,
              onPageChanged: _onPageChanged,
              itemCount: widget.stories.length,
              itemBuilder: (_, i) => NewsStoryCanvas(
                story: widget.stories[i],
                // Видео мен қате тек АҒЫМДАҒЫ бетке қатысты — көрші
                // беттер алдын ала салынғанда олардың контроллері жоқ.
                video: i == _index ? _video : null,
                loading: i == _index && _loading,
                error: i == _index ? _mediaError : null,
              ),
            ),
            _topBar(),
            _bottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 4, 0),
        child: Column(
          children: [
            Row(
              children: [
                for (var i = 0; i < widget.stories.length; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: AnimatedBuilder(
                        animation: _progress,
                        builder: (_, _) => _ProgressBar(
                          value: i < _index
                              ? 1
                              : i > _index
                              ? 0
                              : _progress.value,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const SizedBox(width: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    'assets/icon/icon.png',
                    width: 26,
                    height: 26,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    t('Жаңалықтар'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                    ),
                  ),
                ),
                if (_story.hasMusic)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(
                      _held ? Icons.pause : Icons.music_note,
                      color: Colors.white70,
                      size: 18,
                    ),
                  ),
                IconButton(
                  onPressed: _close,
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomBar() => Positioned(
    left: 0,
    right: 0,
    bottom: 0,
    child: NewsStoryCaption(story: _story, onLink: () => _openLink(_story)),
  );

  Future<void> _openLink(NewsStory s) async {
    // Сілтеме сыртқы браузерде ашылады — сол сәтте сторис тоқтап тұрсын,
    // әйтпесе адам оралғанда бет әлдеқашан жабылып қалар еді.
    _hold(true);
    try {
      await launchUrl(
        Uri.parse(s.linkUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      if (mounted) showSnack(context, errText(e), error: true);
    }
  }
}

// ============================================================
// ҚАЙТА ҚОЛДАНЫЛАТЫН БӨЛІКТЕР
// ============================================================
// Мына екі виджетті МОДЕРАТОРДЫҢ ҚҰРАСТЫРҒЫШЫ да (news_admin_screen.dart)
// пайдаланады — сол себепті ол «көріп тұрып» өңдейді әрі көргені мен
// қолданушыға баратыны ДӘЛ БІР ЭКРАН болады. Стильді екі жерде бөлек
// қайталасақ, біреуін өзгерткенде екіншісі қалып қойып, алдын ала көрініс
// «өтірік» айта бастар еді.
//
// [titleEdit] / [bodyEdit] БЕРІЛСЕ — жазулар сол ЖЕРІНДЕ өңделеді
// (құрастырғыш режимі); берілмесе — қарапайым мәтін (қарау режимі).

/// Бір стористің фоны мен медиасы. Прогресс пен түрту қимылдары
/// [NewsStoryScreen]-де — бұл виджет тек СУРЕТТЕЙДІ.
class NewsStoryCanvas extends StatelessWidget {
  final NewsStory story;
  final VideoPlayerController? video;
  final bool loading;
  final String? error;

  /// Мәтіндік стористің ортадағы жазуын өңдеуге арналған (құрастырғыш).
  final TextEditingController? titleEdit;
  final TextEditingController? bodyEdit;
  final FocusNode? titleFocus;
  final FocusNode? bodyFocus;

  const NewsStoryCanvas({
    super.key,
    required this.story,
    this.video,
    this.loading = false,
    this.error,
    this.titleEdit,
    this.bodyEdit,
    this.titleFocus,
    this.bodyFocus,
  });

  bool get _editing => titleEdit != null && bodyEdit != null;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: newsStoryGradient(story.bgIndex),
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (story.isImage && story.mediaPath != null)
            Image.network(
              Repo.newsMediaUrl(story.mediaPath!),
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => _mediaFailed(t('Сурет жүктелмеді')),
            ),
          if (story.isVideo)
            if (video != null && video!.value.isInitialized)
              Center(
                child: AspectRatio(
                  aspectRatio: video!.value.aspectRatio,
                  child: VideoPlayer(video!),
                ),
              )
            else if (loading)
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
          if (error != null) _mediaFailed(error!),
          // Таза МӘТІН стористі — жазуы ортада, ірі әрі оқуға ыңғайлы.
          if (!story.isImage && !story.isVideo)
            Padding(
              padding: const EdgeInsets.fromLTRB(26, 90, 26, 140),
              child: Center(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_editing)
                        _field(
                          controller: titleEdit!,
                          focus: titleFocus,
                          hint: t('Тақырып'),
                          style: _bigTitle,
                          maxLines: 3,
                        )
                      else if (story.title.isNotEmpty)
                        Text(story.title, style: _bigTitle),
                      if (_editing) ...[
                        const SizedBox(height: 8),
                        _field(
                          controller: bodyEdit!,
                          focus: bodyFocus,
                          hint: t('Мәтіні'),
                          style: _bigBody,
                          maxLines: 10,
                        ),
                      ] else if (story.body.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(story.body, style: _bigBody),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static const _bigTitle = TextStyle(
    color: Colors.white,
    fontWeight: FontWeight.w900,
    fontSize: 26,
    height: 1.2,
  );
  static const _bigBody = TextStyle(
    color: Colors.white,
    fontSize: 16,
    height: 1.45,
  );

  Widget _mediaFailed(String msg) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off, color: Colors.white54, size: 40),
          const SizedBox(height: 10),
          Text(
            msg,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    ),
  );
}

/// Стористің АСТЫҢҒЫ бөлігі: қараңғылатқыш градиент, жазуы (сурет/видеода),
/// әуеннің атауы және «Толығырақ» түймесі.
class NewsStoryCaption extends StatelessWidget {
  final NewsStory story;
  final VoidCallback? onLink;

  /// Берілсе — жазулар сол жерінде өңделеді (құрастырғыш режимі).
  final TextEditingController? titleEdit;
  final TextEditingController? bodyEdit;
  final FocusNode? titleFocus;
  final FocusNode? bodyFocus;

  const NewsStoryCaption({
    super.key,
    required this.story,
    this.onLink,
    this.titleEdit,
    this.bodyEdit,
    this.titleFocus,
    this.bodyFocus,
  });

  bool get _editing => titleEdit != null && bodyEdit != null;

  @override
  Widget build(BuildContext context) {
    final s = story;
    // Мәтіндік стористе жазу ортада тұрады ([NewsStoryCanvas]) — астында
    // тағы бір рет қайталанбауы керек.
    final showText = s.isImage || s.isVideo;
    // ЕСКЕРТУ: мұндағы мәтіндер мен градиент қимылды БӨГЕМЕЙДІ (Text пен
    // Container hit-test-ке қатыспайды) — түрту жоғарыдағы GestureDetector-ге
    // жетеді. Тек «Толығырақ» түймесі басылуды өзіне алады.
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 40, 18, 8),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Color(0xCC000000)],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showText && _editing)
              _field(
                controller: titleEdit!,
                focus: titleFocus,
                hint: t('Тақырып'),
                style: _capTitle,
                maxLines: 2,
              )
            else if (showText && s.title.isNotEmpty)
              Text(s.title, style: _capTitle),
            if (showText && _editing) ...[
              const SizedBox(height: 2),
              _field(
                controller: bodyEdit!,
                focus: bodyFocus,
                hint: t('Мәтіні'),
                style: _capBody,
                maxLines: 4,
              ),
            ] else if (showText && s.body.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(s.body, style: _capBody),
            ],
            if (s.musicTitle.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.music_note, size: 14, color: Colors.white60),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      s.musicTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (s.hasLink) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Gz.yellow,
                    foregroundColor: Gz.ink,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: onLink,
                  child: Text(
                    s.linkLabel.isEmpty ? t('Толығырақ') : s.linkLabel,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  static const _capTitle = TextStyle(
    color: Colors.white,
    fontWeight: FontWeight.w900,
    fontSize: 20,
    height: 1.2,
  );
  static const _capBody = TextStyle(
    color: Colors.white70,
    fontSize: 14,
    height: 1.35,
  );
}

/// Стористің ҮСТІНДЕ тұратын өңдеуге арналған өріс: рамкасы да, фоны да
/// жоқ — жазу дәл қарау режиміндегідей көрінеді, тек курсоры бар.
Widget _field({
  required TextEditingController controller,
  required FocusNode? focus,
  required String hint,
  required TextStyle style,
  required int maxLines,
}) => TextField(
  controller: controller,
  focusNode: focus,
  style: style,
  maxLines: maxLines,
  minLines: 1,
  cursorColor: Gz.yellow,
  textCapitalization: TextCapitalization.sentences,
  decoration: InputDecoration(
    isDense: true,
    contentPadding: EdgeInsets.zero,
    border: InputBorder.none,
    hintText: hint,
    hintStyle: style.copyWith(color: Colors.white38),
  ),
);

class _ProgressBar extends StatelessWidget {
  final double value;
  const _ProgressBar({required this.value});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: LinearProgressIndicator(
        value: value.clamp(0.0, 1.0),
        minHeight: 2.5,
        backgroundColor: Colors.white24,
        valueColor: const AlwaysStoppedAnimation(Colors.white),
      ),
    );
  }
}
