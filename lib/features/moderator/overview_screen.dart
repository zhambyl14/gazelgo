import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import 'listings_admin_screen.dart';

/// Модератордың «Шолу» табы: бүкіл платформаның бір беттегі суреті —
/// қанша клиент/орындаушы бар, қазір қанша заказ онлайн, оның нешеуін
/// орындаушылар орындап жатыр, нешеуі әлі орындаушы күтіп тұр, қанша
/// хабарландыру бар. Әр бөліктің «толығырақ» жалғасы бар.
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
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _load());
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
          EmptyState(icon: Icons.wifi_off, title: _error!),
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

    return RefreshIndicator(
      color: Gz.ink,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        children: [
          // ================= ЗАКАЗДАР =================
          _section(t('Заказдар'), t('Дәл қазіргі жағдай')),
          Row(
            children: [
              Expanded(
                child: _tile(
                  t('Онлайн'),
                  _n('orders_online'),
                  t('тірі заказ'),
                  Gz.ink,
                  Icons.bolt,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _tile(
                  t('Күтуде'),
                  _n('orders_waiting'),
                  t('орындаушы іздеп жатыр'),
                  Gz.blue,
                  Icons.hourglass_empty,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _tile(
                  t('Орындалуда'),
                  _n('orders_in_progress'),
                  t('орындаушыда'),
                  Gz.green,
                  Icons.local_shipping,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _tile(
                  t('Бүгін берілді'),
                  _n('orders_today'),
                  t('заказ'),
                  Gz.violet,
                  Icons.today,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _tile(
                  t('Бүгін аяқталды'),
                  _n('orders_completed_today'),
                  t('заказ'),
                  Gz.green,
                  Icons.check_circle_outline,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _tile(
                  t('Бүгін тоқтады'),
                  _n('orders_cancelled_today'),
                  t('бас тартылды'),
                  Gz.red,
                  Icons.cancel_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (waitingByVehicle.isNotEmpty)
            _breakdown(
              t('Күтіп тұрғандар — көлік түрі бойынша'),
              [
                for (final e in waitingByVehicle)
                  (
                    vehicleTypeFrom(e['vehicle_type'] as String?).label,
                    (e['count'] as num).toInt(),
                  ),
              ],
            ),
          if (waitingByCity.isNotEmpty) ...[
            const SizedBox(height: 8),
            _breakdown(
              t('Күтіп тұрғандар — қала бойынша'),
              [
                for (final e in waitingByCity)
                  ('${e['city']}', (e['count'] as num).toInt()),
              ],
            ),
          ],

          // ================= ПАЙДАЛАНУШЫЛАР =================
          const SizedBox(height: 20),
          _section(t('Пайдаланушылар'), t('Тіркелгендер мен жұмысқа дайындар')),
          Row(
            children: [
              Expanded(
                child: _tile(
                  t('Клиенттер'),
                  _n('clients_total'),
                  '+${_n('clients_new_7d')} ${t('осы аптада')}',
                  Gz.blue,
                  Icons.people_outline,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _tile(
                  t('Орындаушылар'),
                  _n('executors_total'),
                  '${_n('executors_approved')} ${t('расталған')}',
                  Gz.ink,
                  Icons.local_shipping_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _tile(
                  t('Линияда'),
                  _n('executors_on_line'),
                  t('жұмысқа дайын'),
                  Gz.green,
                  Icons.wifi,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _tile(
                  t('Бос емес'),
                  _n('executors_busy'),
                  t('заказда'),
                  Gz.red,
                  Icons.hourglass_bottom,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _tile(
                  t('Тарифте'),
                  _n('executors_on_tariff'),
                  t('белсенді тариф'),
                  Gz.yellowDark,
                  Icons.bolt,
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
          _section(
            t('Хабарландырулар'),
            boardOn
                ? t('Тақта ҚОСУЛЫ — клиент те, орындаушы да қолдана алады')
                : t('Тақта ӨШУЛІ — қолданушыларға «әлі қосылмады» деп шығады'),
          ),
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: (boardOn ? Gz.green : Gz.textSecondary)
                  .withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: (boardOn ? Gz.green : Gz.textSecondary)
                    .withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  boardOn ? Icons.toggle_on : Icons.toggle_off,
                  color: boardOn ? Gz.green : Gz.textSecondary,
                  size: 24,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    boardOn
                        ? t('Хабарландырулар тақтасы қосулы')
                        : t('Хабарландырулар тақтасы өшулі'),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                      color: boardOn ? Gz.green : Gz.textSecondary,
                    ),
                  ),
                ),
                Text(
                  t('Баптаулар табынан'),
                  style: const TextStyle(
                    fontSize: 11,
                    color: Gz.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              Expanded(
                child: _tile(
                  t('Лентада'),
                  _n('listings_active'),
                  t('белсенді'),
                  Gz.ink,
                  Icons.storefront,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _tile(
                  t('Жұмыстар'),
                  _n('listings_jobs'),
                  t('клиенттерден'),
                  Gz.blue,
                  Icons.campaign_outlined,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _tile(
                  t('Қызметтер'),
                  _n('listings_services'),
                  t('орындаушылардан'),
                  Gz.green,
                  Icons.handyman_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _tile(
                  t('Бүгін берілді'),
                  _n('listings_today'),
                  t('хабарландыру'),
                  Gz.violet,
                  Icons.today,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _tile(
                  t('Архивте'),
                  _n('listings_expired'),
                  t('мерзімі бітті'),
                  Gz.textSecondary,
                  Icons.history,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _tile(
                  t('Көрулер'),
                  _n('listings_views'),
                  t('барлығы'),
                  Gz.yellowDark,
                  Icons.visibility_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SectionCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.list_alt, color: Gz.ink),
              title: Text(
                t('Хабарландырулар тізімі'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(t('Толығырақ көру · күдіктісін өшіру')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ListingsAdminScreen(),
                ),
              ),
            ),
          ),

          // ================= ЖАСАЛАТЫН ЖҰМЫС =================
          const SizedBox(height: 20),
          _section(
            t('Күтіп тұрған жұмыс'),
            t('Модератордың назарын қажет ететіндер'),
          ),
          _todo(t('Жаңа өтінімдер'), _n('applications_pending'),
              Icons.assignment_outlined, Gz.blue),
          _todo(t('Құжат жаңартулары'), _n('docs_review_pending'),
              Icons.description_outlined, Gz.violet),
          _todo(t('Баланс толтырулары'), _n('topups_pending'),
              Icons.account_balance_wallet_outlined, Gz.yellowDark),
          _todo(t('Ашық шағымдар'), _n('reports_open'),
              Icons.flag_outlined, Gz.red),
          _todo(t('Ашық қолдау чаттары'), _n('support_open'),
              Icons.support_agent, Gz.green),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _section(String title, String subtitle) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
        ),
        Text(
          subtitle,
          style: const TextStyle(color: Gz.textSecondary, fontSize: 12),
        ),
      ],
    ),
  );

  Widget _tile(
    String label,
    int value,
    String hint,
    Color color,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Gz.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Gz.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 6),
          Text(
            '$value',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          Text(
            hint,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10.5, color: Gz.textSecondary),
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
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
          ),
          const SizedBox(height: 8),
          if (rows.isEmpty || total == 0)
            Text(
              t('Дерек жоқ'),
              style: const TextStyle(color: Gz.textSecondary, fontSize: 12.5),
            )
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

  Widget _todo(String label, int count, IconData icon, Color color) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: SectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: count > 0
                  ? color.withValues(alpha: 0.14)
                  : Gz.bg,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 14,
                color: count > 0 ? color : Gz.textSecondary,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
