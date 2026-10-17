import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';

/// Орындаушы өтінімдері (pending) тізімі.
class ApplicationsScreen extends StatefulWidget {
  const ApplicationsScreen({super.key});

  @override
  State<ApplicationsScreen> createState() => _ApplicationsScreenState();
}

class _ApplicationsScreenState extends State<ApplicationsScreen> {
  late Future<List<List<ExecutorProfile>>> _future = _load();

  Future<List<List<ExecutorProfile>>> _load() => Future.wait([
    Repo.executorsByStatus('pending'),
    Repo.docsReviewPending(),
  ]);

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: FutureBuilder<List<List<ExecutorProfile>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final pending = snap.data?[0] ?? [];
          final docsReview = snap.data?[1] ?? [];
          if (pending.isEmpty && docsReview.isEmpty) {
            return ListView(
              children: [
                const SizedBox(height: 120),
                EmptyState(
                  icon: Icons.inbox_outlined,
                  title: t('Жаңа өтінім жоқ'),
                  subtitle: t('Барлық өтінімдер қаралған.'),
                ),
              ],
            );
          }
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              if (docsReview.isNotEmpty) ...[
                _SectionLabel(t('Құжат жаңартулары (ревью)')),
                for (final ep in docsReview) ...[
                  _DocsReviewTile(ep: ep, onChanged: _reload),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 8),
              ],
              if (pending.isNotEmpty) ...[
                _SectionLabel(t('Жаңа өтінімдер')),
                for (final ep in pending) ...[
                  _ApplicationTile(ep: ep, onChanged: _reload),
                  const SizedBox(height: 8),
                ],
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
    child: Text(
      text,
      style: const TextStyle(
        fontWeight: FontWeight.w800,
        fontSize: 13,
        color: Gz.textSecondary,
      ),
    ),
  );
}

/// Құжат жаңартуын ревьюлеу тайлы (қабылдау / қайтару).
class _DocsReviewTile extends StatelessWidget {
  final ExecutorProfile ep;
  final VoidCallback onChanged;
  const _DocsReviewTile({required this.ep, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Profile?>(
      future: Repo.profileOf(ep.userId),
      builder: (context, snap) {
        final p = snap.data;
        final fields = ep.docsUpdateFields
            .map(ExecutorProfile.docFieldLabel)
            .join(', ');
        return SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  InitialsAvatar(
                    p?.fullName ?? '?',
                    radius: 20,
                    imageUrl: p?.avatarUrl,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      p?.fullName ?? '…',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
              if (fields.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  '${t('Жаңартылды')}: $fields',
                  style: const TextStyle(fontSize: 13, color: Gz.textSecondary),
                ),
              ],
              const SizedBox(height: 10),
              // Жаңартылған құжаттар
              SizedBox(
                height: 110,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    if (ep.docsUpdateFields.contains('id')) ...[
                      _doc(ep.idDocPath, t('Жеке куәлік')),
                      _doc(ep.idSelfiePath, t('Куәлікпен селфи')),
                    ],
                    if (ep.docsUpdateFields.contains('passport')) ...[
                      _doc(ep.passportPath, t('Шетел паспорты')),
                      _doc(ep.passportSelfiePath, t('Паспортпен селфи')),
                    ],
                    if (ep.docsUpdateFields.contains('license')) ...[
                      _doc(ep.licensePath, t('Жүргізуші')),
                      _doc(ep.licenseSelfiePath, t('Правамен селфи')),
                    ],
                    if (ep.docsUpdateFields.contains('tech')) ...[
                      _doc(ep.techPassportPath, t('Техпаспорт')),
                      _doc(ep.techPassportSelfiePath, t('Техпаспортпен фото')),
                    ],
                    if (ep.docsUpdateFields.contains('photos'))
                      for (final ph in ep.vehiclePhotos) _doc(ph, t('Көлік')),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: BusyButton(
                      label: t('Қайтару'),
                      outlined: true,
                      onPressed: () => _reject(context),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: BusyButton(
                      label: t('Қабылдау ✓'),
                      onPressed: () => _approve(context),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _doc(String? path, String label) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: SizedBox(
      width: 150,
      child: DocImage(path: path, label: label),
    ),
  );

  Future<void> _approve(BuildContext context) async {
    try {
      await Repo.modApproveDocs(ep.userId);
      if (context.mounted) showSnack(context, t('Құжаттар қабылданды'));
      onChanged();
    } catch (e) {
      if (context.mounted) showSnack(context, errText(e), error: true);
    }
  }

  Future<void> _reject(BuildContext context) async {
    final reason = await gzInputDialog(
      context,
      icon: Icons.undo_rounded,
      confirmColor: Gz.red,
      title: t('Қайтару себебі'),
      hint: t('Мыс: техпаспорт фотосы анық емес'),
      presets: [for (final p in kDocRejectPresets) t(p)],
      confirmLabel: t('Қайтару'),
    );
    if (reason == null) return;
    try {
      await Repo.modRejectDocs(ep.userId, reason);
      if (context.mounted) showSnack(context, t('Қайтарылды'));
      onChanged();
    } catch (e) {
      if (context.mounted) showSnack(context, errText(e), error: true);
    }
  }
}

class _ApplicationTile extends StatelessWidget {
  final ExecutorProfile ep;
  final VoidCallback onChanged;
  const _ApplicationTile({required this.ep, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Profile?>(
      future: Repo.profileOf(ep.userId),
      builder: (context, snap) {
        final p = snap.data;
        return Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 6,
            ),
            leading: InitialsAvatar(p?.fullName ?? '?', imageUrl: p?.avatarUrl),
            title: Text(
              p?.fullName ?? '…',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              '${ep.vehicleTitle} · ${ep.vehiclePlate}\n'
              '${ep.city ?? '—'} · ${fmtDate(ep.createdAt)}',
              style: const TextStyle(fontSize: 13),
            ),
            isThreeLine: true,
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final changed = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => ApplicationDetailScreen(ep: ep, profile: p),
                ),
              );
              if (changed == true) onChanged();
            },
          ),
        );
      },
    );
  }
}

/// Өтінім детальдары: құжаттар, фотолар, растау/қабылдамау.
class ApplicationDetailScreen extends StatelessWidget {
  final ExecutorProfile ep;
  final Profile? profile;
  const ApplicationDetailScreen({super.key, required this.ep, this.profile});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t('Өтінім'))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      InitialsAvatar(
                        profile?.fullName ?? '?',
                        radius: 24,
                        imageUrl: profile?.avatarUrl,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              profile?.fullName ?? '…',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              profile?.phone ?? '',
                              style: const TextStyle(
                                color: Gz.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  // Өтінімде сұрақ туса — модератор иесімен бірден
                  // хабарласады (бұрын нөмірді қолмен теру керек еді).
                  if (profile?.phone.isNotEmpty == true) ...[
                    const SizedBox(height: 12),
                    ContactButtons(phone: profile!.phone),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionTitle(t('Көлік')),
                  _DuplicatePlateWarning(ep: ep),
                  InfoRow(t('Көлік түрі'), ep.vehicleType.label),
                  InfoRow(t('Маркасы'), ep.vehicleTitle),
                  if (ep.city != null) InfoRow(t('Қала'), ep.city!),
                  InfoRow(t('Мемлекеттік нөмір'), ep.vehiclePlate),
                  InfoRow(t('Өтінім күні'), fmtDate(ep.createdAt)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SectionTitle(
              t('Құжаттар'),
              subtitle: t(
                'Басса — толық экранда ашылады, сырғытып қарауға болады',
              ),
              trailing: InfoChip(
                text: ep.isForeignCitizen
                    ? t('Шетел азаматы')
                    : t('ҚР азаматы'),
              ),
            ),
            DocGallery(
              docs: [
                (ep.licensePath, t('Жүргізуші куәлігі')),
                (ep.licenseSelfiePath, t('Правамен селфи')),
                if (!ep.isForeignCitizen) ...[
                  (ep.idDocPath, t('Жеке куәлік')),
                  (ep.idSelfiePath, t('Куәлікпен селфи')),
                ] else ...[
                  (ep.passportPath, t('Шетел паспорты')),
                  (ep.passportSelfiePath, t('Паспортпен селфи')),
                ],
                (ep.techPassportPath, t('Техпаспорт')),
                (ep.techPassportSelfiePath, t('Техпаспортпен фото')),
                for (var i = 0; i < ep.vehiclePhotos.length; i++)
                  (ep.vehiclePhotos[i], '${t('Фото')} ${i + 1}'),
              ],
            ),
            const SizedBox(height: 16),
            // Модератордың өзін тексеру парағы — өтінімді растамас бұрын
            // не қарау керегін еске салады (тек көмекші, серверге жіберілмейді).
            const _ReviewChecklist(),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: BusyButton(
                    label: t('Қабылдамау'),
                    outlined: true,
                    onPressed: () => _reject(context),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: BusyButton(
                    label: t('Растау ✓'),
                    onPressed: () => _approve(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Future<void> _approve(BuildContext context) async {
    try {
      await Repo.modSetExecutorStatus(ep.userId, 'approved', '');
      if (context.mounted) {
        showSnack(context, t('Орындаушы расталды'));
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (context.mounted) showSnack(context, errText(e), error: true);
    }
  }

  Future<void> _reject(BuildContext context) async {
    final reason = await gzInputDialog(
      context,
      icon: Icons.cancel_outlined,
      confirmColor: Gz.red,
      title: t('Қабылдамау себебі'),
      message: t(
        'Себебі орындаушыға көрсетіледі — нені түзету керегін '
        'нақты жазыңыз.',
      ),
      hint: t('Мыс: техпаспорт фотосы анық емес'),
      presets: [for (final p in kDocRejectPresets) t(p)],
      required: true,
      confirmLabel: t('Қабылдамау'),
    );
    if (reason == null || !context.mounted) return;
    try {
      await Repo.modSetExecutorStatus(ep.userId, 'rejected', reason);
      if (context.mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (context.mounted) showSnack(context, errText(e), error: true);
    }
  }
}

/// Модератордың өтінімді тексеру парағы — растамас бұрын НЕ қарау керегін
/// еске салады. Тек көмекші құрал: белгілер серверге жіберілмейді.
class _ReviewChecklist extends StatefulWidget {
  const _ReviewChecklist();

  @override
  State<_ReviewChecklist> createState() => _ReviewChecklistState();
}

class _ReviewChecklistState extends State<_ReviewChecklist> {
  static const _items = [
    'Аты-жөні құжаттармен сәйкес',
    'Селфидегі адам құжаттағы адам',
    'Құжаттардың мерзімі өтпеген',
    'Көлік нөмірі фотода анық көрінеді',
    'Көлік түрі фотомен сәйкес',
  ];
  final _done = <int>{};

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionTitle(
            t('Тексеру парағы'),
            trailing: CountBadge(_items.length - _done.length),
          ),
          for (var i = 0; i < _items.length; i++)
            ConfirmCheck(
              value: _done.contains(i),
              onChanged: (v) => setState(() {
                if (v) {
                  _done.add(i);
                } else {
                  _done.remove(i);
                }
              }),
              label: Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(t(_items[i]), style: const TextStyle(fontSize: 14)),
              ),
            ),
        ],
      ),
    );
  }
}

/// Бұл көлік нөмірі БАСҚА орындаушыда да тіркелген бе — тіркелгенде
/// модераторға ескерту (бір көлікпен бірнеше аккаунт ашу — алаяқтық
/// белгісі). Сервер өзгерісі керек емес: модератор барлық өтінімді оқи алады.
class _DuplicatePlateWarning extends StatelessWidget {
  final ExecutorProfile ep;
  const _DuplicatePlateWarning({required this.ep});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<String>>(
      future: Repo.modPlateDuplicates(ep.userId, ep.vehiclePlate),
      builder: (context, snap) {
        final dups = snap.data ?? const <String>[];
        if (dups.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: GzNotice(
            tone: NoticeTone.danger,
            icon: Icons.content_copy_rounded,
            title: t('Бұл көлік нөмірі басқа аккаунтта да бар'),
            message:
                '${t('Сәйкес аккаунттар саны')}: ${dups.length}. '
                '${t('Бір көлікпен бірнеше аккаунт ашылмағанын тексеріңіз.')}',
          ),
        );
      },
    );
  }
}

/// Өтінімді/құжатты қабылдамау себептерінің ДАЙЫН тізімі — модератор әр
/// жолы қолмен термейді (диалогта чип болып шығады, біреуін басса өріс
/// толады, қаласа түзетеді).
const kDocRejectPresets = [
  'Фото анық емес — қайта түсіріңіз',
  'Селфиде бет анық көрінбейді',
  'Құжат мерзімі өткен',
  'Аты-жөні құжатпен сәйкес емес',
  'Көлік нөмірі фотода көрінбейді',
  'Құжаттың бір беті жоқ',
];

/// Қорғалған құжат суреті (signed URL арқылы). Басқанда — [onTap] берілсе
/// сол (галерея), әйтпесе толық экранды көрсеткіш бір құжатпен ашылады.
class DocImage extends StatelessWidget {
  final String? path;
  final String label;
  final VoidCallback? onTap;
  final double height;

  const DocImage({
    super.key,
    required this.path,
    required this.label,
    this.onTap,
    this.height = 110,
  });

  @override
  Widget build(BuildContext context) {
    final box = BoxDecoration(
      color: Gz.surfaceAlt,
      borderRadius: BorderRadius.circular(Gz.rSm),
      border: Border.all(color: Gz.border),
    );
    Widget caption() => Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );

    if (path == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: height,
            width: double.infinity,
            decoration: box,
            child: Center(
              child: Text(
                t('жоқ'),
                style: const TextStyle(color: Gz.textTertiary, fontSize: 12),
              ),
            ),
          ),
          caption(),
        ],
      );
    }
    // Kaspi кейде скриншот түсіруге тыйым салады (қаржы қауіпсіздігі) —
    // сол кезде орындаушы чекті PDF ретінде «Поделиться» арқылы жүктейді.
    final isPdf = path!.toLowerCase().endsWith('.pdf');

    return FutureBuilder<String>(
      future: Repo.signedDocUrl(path!),
      builder: (context, snap) {
        final url = snap.data;
        final tap = url == null || url.isEmpty
            ? null
            : (onTap ??
                  () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DocViewerScreen(docs: [(path, label)]),
                    ),
                  ));
        return GestureDetector(
          onTap: tap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: height,
                width: double.infinity,
                decoration: box,
                clipBehavior: Clip.antiAlias,
                child: url == null
                    ? const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : isPdf
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.picture_as_pdf_rounded,
                            color: Gz.red,
                            size: 32,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            t('PDF ашу'),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Gz.textSecondary,
                            ),
                          ),
                        ],
                      )
                    : Image.network(
                        url,
                        fit: BoxFit.cover,
                        cacheHeight:
                            (height * MediaQuery.devicePixelRatioOf(context))
                                .round(),
                        errorBuilder: (_, _, _) => const Center(
                          child: Icon(
                            Icons.broken_image_outlined,
                            color: Gz.textTertiary,
                          ),
                        ),
                      ),
              ),
              caption(),
            ],
          ),
        );
      },
    );
  }
}

/// Құжаттар торы (2 баған). Кез келгенін басса — толық экранды
/// [DocViewerScreen] сол құжаттан ашылады да, қалғандарына СЫРҒЫТЫП
/// өтуге болады (бұрын әр құжат бөлек терезеде ашылып, жабылатын).
class DocGallery extends StatelessWidget {
  final List<(String?, String)> docs;
  const DocGallery({super.key, required this.docs});

  @override
  Widget build(BuildContext context) {
    final present = [
      for (final d in docs)
        if (d.$1 != null) d,
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final w = (c.maxWidth - 8) / 2;
        return Wrap(
          spacing: 8,
          runSpacing: 10,
          children: [
            for (final d in docs)
              SizedBox(
                width: w,
                child: DocImage(
                  path: d.$1,
                  label: d.$2,
                  onTap: d.$1 == null
                      ? null
                      : () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => DocViewerScreen(
                              docs: present,
                              initial: present.indexOf(d),
                            ),
                          ),
                        ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Құжаттарды толық экранда қарау: сырғыту (келесі/алдыңғы), саусақпен
/// үлкейту, 90°-қа бұру (селфи мен құжат көбіне жанынан түсіріледі).
class DocViewerScreen extends StatefulWidget {
  final List<(String?, String)> docs;
  final int initial;
  const DocViewerScreen({super.key, required this.docs, this.initial = 0});

  @override
  State<DocViewerScreen> createState() => _DocViewerScreenState();
}

class _DocViewerScreenState extends State<DocViewerScreen> {
  late final _pages = PageController(initialPage: widget.initial);
  late int _index = widget.initial;
  final Map<int, int> _turns = {};

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final docs = widget.docs;
    return Scaffold(
      backgroundColor: Gz.ink,
      appBar: AppBar(
        backgroundColor: Gz.ink,
        foregroundColor: Colors.white,
        title: Text(
          '${_index + 1}/${docs.length} · ${docs[_index].$2}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          IconButton(
            tooltip: t('Бұру'),
            onPressed: () => setState(
              () => _turns[_index] = ((_turns[_index] ?? 0) + 1) % 4,
            ),
            icon: const Icon(Icons.rotate_90_degrees_cw_outlined),
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pages,
        itemCount: docs.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (_, i) {
          final path = docs[i].$1;
          if (path == null) return const SizedBox.shrink();
          return FutureBuilder<String>(
            future: Repo.signedDocUrl(path),
            builder: (context, snap) {
              final url = snap.data;
              if (url == null) {
                return const Center(child: CircularProgressIndicator());
              }
              if (path.toLowerCase().endsWith('.pdf')) {
                return Center(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(200, 52),
                    ),
                    onPressed: () => launchUrl(
                      Uri.parse(url),
                      mode: LaunchMode.externalApplication,
                    ),
                    icon: const Icon(Icons.picture_as_pdf_rounded),
                    label: Text(t('PDF ашу')),
                  ),
                );
              }
              return InteractiveViewer(
                maxScale: 5,
                child: Center(
                  child: RotatedBox(
                    quarterTurns: _turns[i] ?? 0,
                    child: Image.network(url, fit: BoxFit.contain),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
