import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import 'dashboard_charts.dart';
import 'listings_admin_screen.dart';
import 'moderator_shell.dart';
import 'overview_extras.dart';

/// Модератордың «Шолу» беті: бүкіл платформаның бір беттегі суреті.
///
/// РЕТІ: ең жоғарыда — «Бүгін не істеу керек» (модератордың ісі күтіп
/// тұрған бөлімдер; әр жолды басса сол бөлім ашылады). Бұрын бұл тізім
/// беттің ЕҢ АСТЫНДА тұратын әрі басылмайтын. Одан кейін — заказдар,
/// графиктер, пайдаланушылар, хабарландырулар көрсеткіштері.
class ModeratorOverviewScreen extends StatefulWidget {
  const ModeratorOverviewScreen({super.key});

  @override
  State<ModeratorOverviewScreen> createState() =>
      _ModeratorOverviewScreenState();
}

class _ModeratorOverviewScreenState extends State<ModeratorOverviewScreen> {
  Map<String, dynamic>? _s;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await Repo.modOverviewStats();
      if (mounted) {
        setState(() {
          _s = s;
          _error = null;
        });
      }
    } catch (e) {
      // Бірінші жүктеу сәтсіз болса ғана қате көрсетеміз — кейінгі
      // периодты жаңартулар үзілсе, экрандағы соңғы дерек қалады.
      if (mounted && _s == null) setState(() => _error = errText(e));
    }
  }

  int _n(String key) {
    final v = _s?[key];
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          LoadErrorState(onRetry: _load, subtitle: _error),
        ],
      );
    }
    if (_s == null) return const Center(child: CircularProgressIndicator());

    final boardOn = _s?['board_enabled'] == true;
    final waitingByVehicle = (_s?['waiting_by_vehicle'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final waitingByCity = (_s?['waiting_by_city'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final todos = <(String, int, IconData, Color, int)>[
      (
        t('Жаңа өтінімдер'),
        _n('applications_pending'),
        Icons.assignment_ind_outlined,
        Gz.blue,
        ModeratorShell.tabApplications,
      ),
      (
        t('Құжат жаңартулары'),
        _n('docs_review_pending'),
        Icons.description_outlined,
        Gz.violet,
        ModeratorShell.tabApplications,
      ),
      (
        t('Баланс толтырулары'),
        _n('topups_pending'),
        Icons.account_balance_wallet_outlined,
        Gz.yellowDeep,
        ModeratorShell.tabTopups,
      ),
      (
        t('Ашық қолдау чаттары'),
        _n('support_open'),
        Icons.support_agent_rounded,
        Gz.green,
        ModeratorShell.tabSupport,
      ),
      (
        t('Ашық шағымдар'),
        _n('reports_open'),
        Icons.flag_outlined,
        Gz.red,
        ModeratorShell.tabReports,
      ),
      (
        t('Хабарландыруға шағымдар'),
        _n('listing_reports_open'),
        Icons.report_gmailerrorred_outlined,
        Gz.red,
        ModeratorShell.tabReports,
      ),
    ];
    final pending = todos.where((e) => e.$2 > 0).toList();

    return RefreshIndicator(
      color: Gz.ink,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          // ================= БҮГІН НЕ ІСТЕУ КЕРЕК =================
          SectionTitle(
            t('Бүгін не істеу керек'),
            subtitle: t('Модератордың назарын күтіп тұрған істер'),
          ),
          if (pending.isEmpty)
            GzNotice(
              tone: NoticeTone.success,
              title: t('Барлық жұмыс орындалды'),
              message: t('Жаңа өтінім, толтыру, чат не шағым жоқ.'),
            )
          else
            SectionCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < pending.length; i++) ...[
                    if (i > 0) const Divider(height: 1, indent: 60),
                    GzListRow(
                      icon: pending[i].$3,
                      color: pending[i].$4,
                      title: pending[i].$1,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CountBadge(pending[i].$2, urgent: true),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: Gz.textTertiary,
                          ),
                        ],
                      ),
                      onTap: () => ModeratorShell.openTab(pending[i].$5),
                    ),
                  ],
                ],
              ),
            ),

          // ================= ЗАКАЗДАР =================
          const SizedBox(height: 20),
          SectionTitle(t('Заказдар'), subtitle: t('Дәл қазіргі жағдай')),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  label: t('Онлайн'),
                  value: '${_n('orders_online')}',
                  hint: t('тірі заказ'),
                  icon: Icons.bolt_rounded,
                  onTap: () => ModeratorShell.openTab(ModeratorShell.tabLine),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(
                  label: t('Күтуде'),
                  value: '${_n('orders_waiting')}',
                  hint: t('орындаушы іздеп жатыр'),
                  icon: Icons.hourglass_empty_rounded,
                  color: Gz.blue,
                  onTap: () => ModeratorShell.openTab(ModeratorShell.tabLine),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(
                  label: t('Орындалуда'),
                  value: '${_n('orders_in_progress')}',
                  hint: t('орындаушыда'),
                  icon: Icons.local_shipping_outlined,
                  color: Gz.green,
                  onTap: () => ModeratorShell.openTab(ModeratorShell.tabOrders),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  label: t('Бүгін берілді'),
                  value: '${_n('orders_today')}',
                  hint: t('заказ'),
                  icon: Icons.today_outlined,
                  color: Gz.violet,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(
                  label: t('Бүгін аяқталды'),
                  value: '${_n('orders_completed_today')}',
                  hint: t('заказ'),
                  icon: Icons.check_circle_outline_rounded,
                  color: Gz.green,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(
                  label: t('Бүгін тоқтады'),
                  value: '${_n('orders_cancelled_today')}',
                  hint: t('бас тартылды'),
                  icon: Icons.cancel_outlined,
                  color: Gz.red,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 7/30 күндік графиктер мен түсім (сервердегі функция әлі
          // қолданылмаса — көрінбейді, бет сынбайды).
          const DashboardCharts(),
          if (waitingByVehicle.isNotEmpty) ...[
            const SizedBox(height: 8),
            _breakdown(t('Күтіп тұрғандар — көлік түрі бойынша'), [
              for (final e in waitingByVehicle)
                (
                  vehicleTypeFrom(e['vehicle_type'] as String?).label,
                  (e['count'] as num).toInt(),
                ),
            ]),
          ],
          if (waitingByCity.isNotEmpty) ...[
            const SizedBox(height: 8),
            _breakdown(t('Күтіп тұрғандар — қала бойынша'), [
              for (final e in waitingByCity)
                ('${e['city']}', (e['count'] as num).toInt()),
            ]),
          ],
          const CityStatsSection(),
          const StatusChangesSection(),

          // ================= ПАЙДАЛАНУШЫЛАР =================
          const SizedBox(height: 20),
          SectionTitle(
            t('Пайдаланушылар'),
            subtitle: t('Тіркелгендер мен жұмысқа дайындар'),
          ),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  label: t('Клиенттер'),
                  value: '${_n('clients_total')}',
                  hint: '+${_n('clients_new_7d')} ${t('осы аптада')}',
                  icon: Icons.people_outline_rounded,
                  color: Gz.blue,
                  onTap: () =>
                      ModeratorShell.openTab(ModeratorShell.tabClients),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(
                  label: t('Орындаушылар'),
                  value: '${_n('executors_total')}',
                  hint: '${_n('executors_approved')} ${t('расталған')}',
                  icon: Icons.local_shipping_outlined,
                  onTap: () =>
                      ModeratorShell.openTab(ModeratorShell.tabExecutors),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  label: t('Линияда'),
                  value: '${_n('executors_on_line')}',
                  hint: t('жұмысқа дайын'),
                  icon: Icons.wifi_rounded,
                  color: Gz.green,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(
                  label: t('Бос емес'),
                  value: '${_n('executors_busy')}',
                  hint: t('заказда'),
                  icon: Icons.hourglass_bottom_rounded,
                  color: Gz.red,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(
                  label: t('Тарифте'),
                  value: '${_n('executors_on_tariff')}',
                  hint: t('белсенді тариф'),
                  icon: Icons.bolt_rounded,
                  color: Gz.yellowDeep,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _breakdown(t('Орындаушылардың мәртебесі'), [
            (t('Расталған'), _n('executors_approved')),
            (t('Тексерілуде'), _n('executors_pending')),
            (t('Қабылданбаған'), _n('executors_rejected')),
            (t('Бұғатталған'), _n('executors_blocked')),
          ]),

          // ================= ХАБАРЛАНДЫРУЛАР =================
          const SizedBox(height: 20),
          SectionTitle(
            t('Хабарландырулар'),
            subtitle: boardOn
                ? t('Тақта ҚОСУЛЫ — клиент те, орындаушы да қолдана алады')
                : t('Тақта ӨШУЛІ — мәзірде көрінбейді'),
          ),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  label: t('Лентада'),
                  value: '${_n('listings_active')}',
                  hint: t('белсенді'),
                  icon: Icons.storefront_outlined,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(
                  label: t('Жұмыстар'),
                  value: '${_n('listings_jobs')}',
                  hint: t('клиенттерден'),
                  icon: Icons.campaign_outlined,
                  color: Gz.blue,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(
                  label: t('Қызметтер'),
                  value: '${_n('listings_services')}',
                  hint: t('орындаушылардан'),
                  icon: Icons.handyman_outlined,
                  color: Gz.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  label: t('Бүгін берілді'),
                  value: '${_n('listings_today')}',
                  hint: t('хабарландыру'),
                  icon: Icons.today_outlined,
                  color: Gz.violet,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(
                  label: t('Архивте'),
                  value: '${_n('listings_expired')}',
                  hint: t('мерзімі бітті'),
                  icon: Icons.history_rounded,
                  color: Gz.textSecondary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(
                  label: t('Көрулер'),
                  value: '${_n('listings_views')}',
                  hint: t('барлығы'),
                  icon: Icons.visibility_outlined,
                  color: Gz.yellowDeep,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SectionCard(
            padding: EdgeInsets.zero,
            child: GzListRow(
              icon: Icons.list_alt_rounded,
              title: t('Хабарландырулар тізімі'),
              subtitle: t('Толығырақ көру · күдіктісін өшіру'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ListingsAdminScreen()),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Атау → сан жолдарының шағын тізімі (бөліністер үшін).
  Widget _breakdown(String title, List<(String, int)> rows) {
    final total = rows.fold<int>(0, (a, r) => a + r.$2);
    return SectionCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
          const SizedBox(height: 8),
          if (rows.isEmpty || total == 0)
            Text(t('Дерек жоқ'), style: Gz.caption)
          else
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        r.$1,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    // Пропорционалды жолақ — бір қарағанда салыстыруға оңай.
                    SizedBox(
                      width: 90,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: total == 0 ? 0 : r.$2 / total,
                          minHeight: 6,
                          backgroundColor: Gz.bg,
                          valueColor: const AlwaysStoppedAnimation(Gz.yellow),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 34,
                      child: Text(
                        '${r.$2}',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
