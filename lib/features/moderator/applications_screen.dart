import 'package:flutter/material.dart';

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
  late Future<List<ExecutorProfile>> _future = Repo.executorsByStatus('pending');

  void _reload() {
    final f = Repo.executorsByStatus('pending');
    setState(() {
      _future = f;
    });
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: FutureBuilder<List<ExecutorProfile>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snap.data ?? [];
          if (rows.isEmpty) {
            return ListView(children: const [
              SizedBox(height: 120),
              EmptyState(
                  icon: Icons.inbox_outlined,
                  title: 'Жаңа өтінім жоқ',
                  subtitle: 'Барлық өтінімдер қаралған.'),
            ]);
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: rows.length,
            separatorBuilder: (_, i) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _ApplicationTile(
              ep: rows[i],
              onChanged: _reload,
            ),
          );
        },
      ),
    );
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
              '${ep.vehicleSize.label} · ${fmtDate(ep.createdAt)}',
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
      appBar: AppBar(title: const Text('Өтінім')),
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
                  const Text('Көлік',
                      style: TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 15)),
                  const SizedBox(height: 8),
                  InfoRow('Маркасы', ep.vehicleTitle),
                  InfoRow('Өлшемі', ep.vehicleSize.label),
                  InfoRow('Мемнөмір', ep.vehiclePlate),
                  InfoRow('Өтінім күні', fmtDate(ep.createdAt)),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Text('Құжаттар',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: DocImage(path: ep.idDocPath, label: 'Жеке куәлік')),
                const SizedBox(width: 8),
                Expanded(
                    child: DocImage(
                        path: ep.licensePath, label: 'Жүргізуші куәлігі')),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                    child: DocImage(
                        path: ep.techPassportPath, label: 'Техпаспорт')),
                const SizedBox(width: 8),
                const Expanded(child: SizedBox()),
              ],
            ),
            const SizedBox(height: 14),
            const Text('Көлік фотолары',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 8),
            if (ep.vehiclePhotos.isEmpty)
              const Text('Фото жоқ',
                  style: TextStyle(color: Gz.textSecondary)),
            SizedBox(
              height: 130,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: ep.vehiclePhotos.length,
                separatorBuilder: (_, i) => const SizedBox(width: 8),
                itemBuilder: (_, i) => SizedBox(
                  width: 170,
                  child: DocImage(path: ep.vehiclePhotos[i], label: 'Фото ${i + 1}'),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: BusyButton(
                    label: 'Қабылдамау',
                    outlined: true,
                    onPressed: () => _reject(context),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: BusyButton(
                    label: 'Растау ✓',
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
        showSnack(context, 'Орындаушы расталды');
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
        title: const Text('Қабылдамау себебі'),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(
              hintText: 'Мыс: техпаспорт фотосы анық емес'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Болдырмау')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Gz.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Қабылдамау'),
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
          child: Text('$label\nжоқ',
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
