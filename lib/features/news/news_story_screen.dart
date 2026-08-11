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

/// Мәтіндік стористің фоны — брендтің қара-көк градиенті (ақ жазу анық
/// оқылады, сурет жоқ кезде экран «бос» болып көрінбейді).
const _textGradients = <List<Color>>[
  [Color(0xFF1B2836), Color(0xFF0F1720)],
  [Color(0xFF3730A3), Color(0xFF1E1B4B)],
  [Color(0xFF0E8A3E), Color(0xFF064E28)],
  [Color(0xFFE6AC00), Color(0xFF8A6400)],
];

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
              itemBuilder: (_, i) => _StoryBody(
                story: widget.stories[i],
                // Видео мен қате тек АҒЫМДАҒЫ бетке қатысты — көрші
                // беттер алдын ала салынғанда олардың контроллері жоқ.
                video: i == _index ? _video : null,
                loading: i == _index && _loading,
                error: i == _index ? _mediaError : null,
                index: i,
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

  Widget _bottomBar() {
    final s = _story;
    // Мәтіндік стористе жазу ортада тұрады ([_StoryBody]) — астында тағы
    // бір рет қайталанбауы керек.
    final showText = s.isImage || s.isVideo;
    // ЕСКЕРТУ: мұндағы мәтіндер мен градиент қимылды БӨГЕМЕЙДІ (Text пен
    // Container hit-test-ке қатыспайды) — түрту жоғарыдағы GestureDetector-ге
    // жетеді. Тек «Толығырақ» түймесі басылуды өзіне алады.
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
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
              if (showText && s.title.isNotEmpty)
                Text(
                  s.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                    height: 1.2,
                  ),
                ),
              if (showText && s.body.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  s.body,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.35,
                  ),
                ),
              ],
              if (s.musicTitle.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.music_note,
                      size: 14,
                      color: Colors.white60,
                    ),
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
                    onPressed: () => _openLink(s),
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
      ),
    );
  }

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

/// Бір стористің мазмұны (фон + медиа). Прогресс пен түрту қимылдары
/// [NewsStoryScreen]-де — бұл виджет тек СУРЕТТЕЙДІ.
class _StoryBody extends StatelessWidget {
  final NewsStory story;
  final VideoPlayerController? video;
  final bool loading;
  final String? error;
  final int index;
  const _StoryBody({
    required this.story,
    required this.video,
    required this.loading,
    required this.error,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    final grad = _textGradients[index % _textGradients.length];
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: grad,
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
                      if (story.title.isNotEmpty)
                        Text(
                          story.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 26,
                            height: 1.2,
                          ),
                        ),
                      if (story.body.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          story.body,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            height: 1.45,
                          ),
                        ),
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
