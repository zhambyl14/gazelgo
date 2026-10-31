import 'package:flutter/material.dart';

import '../../core/car_colors.dart';
import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';

/// Орындаушылардың көлік деректерін өзгерту өтініштері (0097): ескі → жаңа
/// салыстырылады, модератор растайды не қабылдамайды.
class VehicleChangesScreen extends StatefulWidget {
  const VehicleChangesScreen({super.key});

  @override
  State<VehicleChangesScreen> createState() => _VehicleChangesScreenState();
}

class _VehicleChangesScreenState extends State<VehicleChangesScreen> {
  late Future<List<Map<String, dynamic>>> _future = Repo.modVehicleChanges();

  void _reload() => setState(() => _future = Repo.modVehicleChanges());

  Future<void> _resolve(Map<String, dynamic> r, bool approve) async {
    String? comment;
    if (!approve) {
      comment = await gzInputDialog(
        context,
        title: t('Өтінімді қабылдамау'),
        hint: t('Себебі (орындаушыға көрінеді)'),
        confirmLabel: t('Қабылдамау'),
        confirmColor: Gz.red,
        required: true,
      );
      if (comment == null || !mounted) return;
    }
    try {
      await Repo.modResolveVehicleChange(
        r['id'] as String,
        approve,
        comment: comment,
      );
      if (mounted) {
        showSnack(context, approve ? t('Расталды') : t('Қабылданбады'));
        _reload();
      }
    } catch (e) {
      if (mounted) showSnack(context, errText(e), error: true);
    }
  }

  String _line(Map<String, dynamic> v) {
    final color = carColorFor(v['vehicle_color'] as String?)?.label;
    return [
      VehicleType(v['vehicle_type'] as String? ?? 'taxi').label,
      '${v['vehicle_brand'] ?? ''} ${v['vehicle_model'] ?? ''}'.trim(),
      if (v['vehicle_year'] != null) '${v['vehicle_year']}',
      ?color,
      '${v['vehicle_plate'] ?? ''}',
    ].where((e) => e.trim().isNotEmpty).join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t('Көлік өзгерту өтініштері'))),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return LoadErrorState(onRetry: _reload);
          }
          final rows = snap.data ?? const [];
          if (rows.isEmpty) {
            return EmptyState(
              icon: Icons.directions_car_outlined,
              title: t('Жаңа өтініш жоқ'),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                for (final r in rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: SectionCard(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${r['full_name'] ?? ''}  ${r['phone'] ?? ''}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            t('Қазір'),
                            style: TextStyle(
                              color: Gz.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            _line(Map<String, dynamic>.from(r['old'] as Map)),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            t('Сұралған'),
                            style: TextStyle(
                              color: Gz.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            _line(Map<String, dynamic>.from(r['new'] as Map)),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          if ((r['note'] as String? ?? '').isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text('«${r['note']}»'),
                          ],
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => _resolve(r, false),
                                  child: BtnLabel(t('Қабылдамау')),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: FilledButton(
                                  onPressed: () => _resolve(r, true),
                                  child: BtnLabel(t('Растау')),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
