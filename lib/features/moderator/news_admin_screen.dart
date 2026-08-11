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

