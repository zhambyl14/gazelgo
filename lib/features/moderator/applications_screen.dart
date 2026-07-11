import 'package:flutter/material.dart';

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
            return ListView(children: [
              const SizedBox(height: 120),
              EmptyState(
                  icon: Icons.inbox_outlined,
                  title: t('Жаңа өтінім жоқ'),
                  subtitle: t('Барлық өтінімдер қаралған.')),
            ]);
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
        child: Text(text,
            style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: Gz.textSecondary)),
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
        final fields =
            ep.docsUpdateFields.map(ExecutorProfile.docFieldLabel).join(', ');
        return SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  InitialsAvatar(p?.fullName ?? '?',
                      radius: 20, imageUrl: p?.avatarUrl),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(p?.fullName ?? '…',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 15)),
                  ),
                ],
              ),
              if (fields.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('${t('Жаңартылды')}: $fields',
                    style: const TextStyle(
                        fontSize: 12.5, color: Gz.textSecondary)),
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
        child: SizedBox(width: 150, child: DocImage(path: path, label: label)),
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
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Қайтару себебі')),
        content: TextField(controller: c, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(t('Болдырмау'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(t('Қайтару'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Repo.modRejectDocs(ep.userId, c.text);
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
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            leading: InitialsAvatar(p?.fullName ?? '?', imageUrl: p?.avatarUrl),
            title: Text(p?.fullName ?? '…',
                style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(
              '${ep.vehicleTitle} · ${ep.vehiclePlate}\n'
              '${ep.city ?? '—'} · ${fmtDate(ep.createdAt)}',
              style: const TextStyle(fontSize: 12.5),
            ),
            isThreeLine: true,
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final changed = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) =>
                      ApplicationDetailScreen(ep: ep, profile: p),
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
              child: Row(
                children: [
                  InitialsAvatar(profile?.fullName ?? '?',
                      radius: 24, imageUrl: profile?.avatarUrl),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(profile?.fullName ?? '…',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 16)),
                        Text(profile?.phone ?? '',
                            style: const TextStyle(
                                color: Gz.textSecondary, fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t('Көлік'),
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 15)),
                  const SizedBox(height: 8),
                  InfoRow(t('Көлік түрі'), ep.vehicleType.label),
                  InfoRow(t('Маркасы'), ep.vehicleTitle),
                  if (ep.city != null) InfoRow(t('Қала'), ep.city!),
                  InfoRow(t('Мемнөмір'), ep.vehiclePlate),
                  InfoRow(t('Өтінім күні'), fmtDate(ep.createdAt)),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Text(t('Құжаттар'),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Gz.bg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    ep.isForeignCitizen ? t('Шетел азаматы') : t('ҚР азаматы'),
                    style: const TextStyle(
                        fontSize: 11.5, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                    child: DocImage(
                        path: ep.licensePath, label: t('Жүргізуші куәлігі'))),
                const SizedBox(width: 8),
                Expanded(
                    child: DocImage(
                        path: ep.licenseSelfiePath, label: t('Правамен селфи'))),
              ],
            ),
            const SizedBox(height: 8),
            if (!ep.isForeignCitizen)
              Row(
                children: [
                  Expanded(
                      child: DocImage(
                          path: ep.idDocPath, label: t('Жеке куәлік'))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: DocImage(
                          path: ep.idSelfiePath, label: t('Куәлікпен селфи'))),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                      child: DocImage(
                          path: ep.passportPath, label: t('Шетел паспорты'))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: DocImage(
                          path: ep.passportSelfiePath,
                          label: t('Паспортпен селфи'))),
                ],
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                    child: DocImage(
                        path: ep.techPassportPath, label: t('Техпаспорт'))),
                const SizedBox(width: 8),
                Expanded(
                    child: DocImage(
                        path: ep.techPassportSelfiePath,
                        label: t('Техпаспортпен фото'))),
              ],
            ),
            const SizedBox(height: 14),
            Text(t('Көлік фотолары'),
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 8),
            if (ep.vehiclePhotos.isEmpty)
              Text(t('Фото жоқ'),
                  style: const TextStyle(color: Gz.textSecondary)),
            SizedBox(
              height: 130,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: ep.vehiclePhotos.length,
                separatorBuilder: (_, i) => const SizedBox(width: 8),
                itemBuilder: (_, i) => SizedBox(
                  width: 170,
                  child: DocImage(
                      path: ep.vehiclePhotos[i],
                      label: '${t('Фото')} ${i + 1}'),
                ),
              ),
            ),
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
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Қабылдамау себебі')),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: InputDecoration(
              hintText: t('Мыс: техпаспорт фотосы анық емес')),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(t('Болдырмау'))),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Gz.red,
                foregroundColor: Colors.white,
                shadowColor: const Color(0x59DC2626)),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t('Қабылдамау')),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await Repo.modSetExecutorStatus(ep.userId, 'rejected', c.text);
      if (context.mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (context.mounted) showSnack(context, errText(e), error: true);
    }
  }
}

/// Қорғалған құжат суреті (signed URL арқылы), басқанда үлкейеді.
class DocImage extends StatelessWidget {
  final String? path;
  final String label;
  const DocImage({super.key, required this.path, required this.label});

  @override
  Widget build(BuildContext context) {
    if (path == null) {
      return Container(
        height: 110,
        decoration: BoxDecoration(
          color: Gz.bg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text('$label\n${t('жоқ')}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Gz.textSecondary, fontSize: 12)),
        ),
      );
    }
    return FutureBuilder<String>(
      future: Repo.signedDocUrl(path!),
      builder: (context, snap) {
        final url = snap.data;
        return GestureDetector(
          onTap: url == null
              ? null
              : () => showDialog(
                    context: context,
                    builder: (_) => Dialog(
                      insetPadding: const EdgeInsets.all(10),
                      child: InteractiveViewer(
                        child: Image.network(url),
                      ),
                    ),
                  ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 110,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Gz.bg,
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: url == null
                    ? const Center(
                        child: SizedBox(
                            width: 20,
                            height: 20,
                            child:
                                CircularProgressIndicator(strokeWidth: 2)))
                    : Image.network(url, fit: BoxFit.cover),
              ),
              const SizedBox(height: 4),
              Text(label,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
        );
      },
    );
  }
}
