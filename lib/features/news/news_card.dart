/// Sidebar-дағы «Жаңалықтар» картасы (0066) — «Хабарландырулардың» ҮСТІНДЕ.
///
/// Ішінде стористердің дөңгелек алдын ала көріністері тұрады: ОҚЫЛМАҒАНЫ
/// сары сақинамен, оқылғаны сұр сақинамен (Instagram/WhatsApp үлгісі).
/// Түртсе — толық экранды [NewsStoryScreen] ашылады.
///
/// Карта ТЕК мына екі шарт орындалғанда көрінеді: модератор бөлімді қосқан
/// ЖӘНЕ осы қолданушының аудиториясына арналған кемінде бір жаңалық бар.
/// Сол себепті гест те, клиент те, орындаушы да ешқашан «бос» бөлім
/// көрмейді — сервер сүзгісі (`news_feed`) бәрін өзі шешеді.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import 'news_story_screen.dart';

class NewsDrawerCard extends ConsumerStatefulWidget {
  const NewsDrawerCard({super.key});

  @override
  ConsumerState<NewsDrawerCard> createState() => _NewsDrawerCardState();
}

class _NewsDrawerCardState extends ConsumerState<NewsDrawerCard> {
  @override
  void initState() {
    super.initState();
    // Sidebar АШЫЛҒАН САЙЫН лентаны қайта сұраймыз: модератор жаңа жаңалық
    // қосқан болуы мүмкін, ал Drawer әр ашылғанда қайта құрылады. Ескі
    // деректер жаңасы келгенше көрініп тұрады (жыпылықтамайды).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.invalidate(newsEnabledProvider);
      ref.invalidate(newsFeedProvider);
      ref.invalidate(newsSeenLocalProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(newsEnabledProvider).value ?? false;
    final stories = ref.watch(newsFeedProvider).value ?? const <NewsStory>[];
    if (!enabled || stories.isEmpty) return const SizedBox.shrink();

    final localSeen = ref.watch(newsSeenLocalProvider).value ?? const <String>{};
    bool unseen(NewsStory s) => !s.seen && !localSeen.contains(s.id);
    final unseenCount = stories.where(unseen).length;
    final showNew = ref.watch(newBadgesProvider).value?.news ?? true;

    void open(int index) {
      Navigator.of(context).pop(); // sidebar-ды жабамыз
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => NewsStoryScreen(stories: stories, initialIndex: index),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        decoration: BoxDecoration(
          gradient: Gz.heroGradient,
          borderRadius: BorderRadius.circular(18),
          boxShadow: Gz.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.auto_awesome_rounded,
                  size: 19,
                  color: Gz.yellow,
                ),
                const SizedBox(width: 8),
                // Жүйе шрифті үлкейтілген телефондарда жазу екі жолға
                // бөлінбеуі үшін (карта тар — 300px шамасы).
                Expanded(
                  child: SizedBox(
                    height: 19,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        t('Жаңалықтар'),
                        maxLines: 1,
                        softWrap: false,
                        // Тіркелген 19px қорап — жол биіктігі айқын
                        // берілмесе, FittedBox жазуды бекер кішірейтеді.
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 14.5,
                          height: 1.1,
                        ),
                      ),
                    ),
                  ),
                ),
                if (showNew && unseenCount > 0)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      gradient: Gz.brandGradient,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: Gz.glow(Gz.yellow, alpha: 0.35, blur: 10),
                    ),
                    child: Text(
                      unseenCount > 1 ? '$unseenCount ${t('жаңа')}' : t('Жаңа'),
                      style: const TextStyle(
                        color: Gz.ink,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 84,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(right: 6),
                itemCount: stories.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (_, i) => _StoryBubble(
                  story: stories[i],
                  unseen: unseen(stories[i]),
                  onTap: () => open(i),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Бір стористің дөңгелек алдын ала көрінісі + астындағы қысқа жазуы.
class _StoryBubble extends StatelessWidget {
  final NewsStory story;
  final bool unseen;
  final VoidCallback onTap;
  const _StoryBubble({
    required this.story,
    required this.unseen,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 62,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                // Оқылмағаны — ГРАДИЕНТТІ сақина (Instagram-дағыдай),
                // оқылғаны — солғын жіңішке жиек: не қалғанын бір қарағанда
                // көресіз.
                gradient: unseen
                    ? const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Gz.yellowLight, Gz.yellow, Gz.amber],
                      )
                    : null,
                border: unseen
                    ? null
                    : Border.all(color: Colors.white24, width: 1.4),
              ),
              child: Container(
                // Сақина мен суреттің АРАСЫНДАҒЫ қара саңылау — сақина
                // суретке жабысып қалмайды, анық көрінеді.
                padding: EdgeInsets.all(unseen ? 2 : 0),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: unseen ? Gz.ink : Colors.transparent,
                ),
                child: ClipOval(child: _preview()),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              story.title.isEmpty ? t('Жаңалық') : story.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: unseen ? Colors.white : Colors.white54,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _preview() {
    if (story.isImage && story.mediaPath != null) {
      return Image.network(
        Repo.newsMediaUrl(story.mediaPath!),
        fit: BoxFit.cover,
        width: 58,
        height: 58,
        errorBuilder: (_, _, _) => _fallback(Icons.image_not_supported),
      );
    }
    if (story.isVideo) return _fallback(Icons.play_circle_fill);
    return _fallback(Icons.article_outlined);
  }

  Widget _fallback(IconData icon) => Container(
    color: Gz.inkSoft,
    alignment: Alignment.center,
    child: Icon(icon, color: Gz.yellow, size: 22),
  );
}
