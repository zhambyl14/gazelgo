import 'package:flutter/material.dart';

import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import 'address_picker.dart';
import 'city_street_sheet.dart';

/// «Аялдамалар» парағы — ЖЕТКІЗУ нүктелерін басқару (Яндекс үлгісі).
///
/// Клиент бірнеше мекенжайға жеткізетін болса, басты бетте олар бір жолға
/// жиналады («A → B»); сол жолды түртсе осы парақ ашылады да, мұнда:
///   • ретін СҮЙРЕП ауыстыруға болады (соңғысы = финиш нүктесі);
///   • әрқайсысын ✕ арқылы алып тастауға болады;
///   • жаңа мекенжай қосуға болады.
///
/// МАҢЫЗДЫ: тізім — ЖЕТКІЗУ нүктелері (алу нүктесі мұнда жоқ). Соңғы
/// элемент әрқашан маршруттың финишы, оның алдындағылары — аралық
/// аялдамалар. Ретті ауыстыру дәл осы мағынаны өзгертеді, сол себепті
/// нөмірлер де бірден қайта есептеледі.
class StopsSheet extends StatefulWidget {
  /// Жеткізу нүктелері: [...аралық аялдамалар, финиш]. Кемінде 1 болуы шарт.
  final List<PickedAddress> destinations;

  const StopsSheet({super.key, required this.destinations});

  /// Парақты ашады. Қайтарады: жаңа жеткізу нүктелері тізімі (бас тартса
  /// null). Тізім ӘРҚАШАН бос емес — соңғы нүктені өшіруге жол берілмейді.
  static Future<List<PickedAddress>?> show(
    BuildContext context, {
    required List<PickedAddress> destinations,
  }) {
    return showModalBottomSheet<List<PickedAddress>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Gz.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => StopsSheet(destinations: destinations),
    );
  }

  @override
  State<StopsSheet> createState() => _StopsSheetState();
}

/// Тізім элементі — ТҰРАҚТЫ id-мен.
///
/// [ReorderableListView] элементтерді Key арқылы таниды. Key ретінде
/// ИНДЕКС қолдансаң (мыс. `ValueKey(i)`) сүйреу кезінде кілт орнымен бірге
/// жылжып кетеді де, Flutter «қай элемент қайда кеткенін» шатастырады:
/// анимация бұзылады, кейде мәтін басқа жолда пайда болады. Сол себепті
/// әр мекенжайға парақ ашылғанда БІР РЕТ id беріледі.
class _Entry {
  final int id;
  PickedAddress addr;
  _Entry(this.id, this.addr);
}

class _StopsSheetState extends State<StopsSheet> {
  int _nextId = 0;
  late final List<_Entry> _dest = [
    for (final a in widget.destinations) _Entry(_nextId++, a),
  ];

  /// Тағы мекенжай қосуға болады ма (алу нүктесі де маршрутқа кіреді,
  /// сол себепті жеткізу нүктелерінің шегі = 1 + [kMaxExtraStops]).
  bool get _canAdd => _dest.length < kMaxExtraStops + 1;

  Future<void> _add() async {
    final res = await CityStreetSheet.show(
      context,
      title: t('Мекенжай қосу'),
    );
    if (res != null && mounted) {
      setState(() => _dest.add(_Entry(_nextId++, res)));
    }
  }

  Future<void> _edit(int i) async {
    final res = await CityStreetSheet.show(
      context,
      title: t('Мекенжайды өзгерту'),
      initial: _dest[i].addr,
    );
    if (res != null && mounted) setState(() => _dest[i].addr = res);
  }

  void _remove(int i) {
    // Кемінде бір жеткізу нүктесі қалуы КЕРЕК — әйтпесе заказдың баратын
    // жері болмай қалады.
    if (_dest.length <= 1) {
      showSnack(context, t('Кемінде бір мекенжай қалуы керек'), error: true);
      return;
    }
    setState(() => _dest.removeAt(i));
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      // ReorderableListView жаңа орынды ЖЫЛЖЫТУДАН БҰРЫНҒЫ индекспен
      // береді — сол себепті түзету қажет.
      if (newIndex > oldIndex) newIndex -= 1;
      _dest.insert(newIndex, _dest.removeAt(oldIndex));
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Gz.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    t('Мекенжайлар'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            Text(
              t('Сүйреп ретін ауыстырыңыз — соңғысы маршруттың финишы'),
              style: const TextStyle(color: Gz.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.42,
              ),
              child: ReorderableListView.builder(
                shrinkWrap: true,
                buildDefaultDragHandles: false,
                itemCount: _dest.length,
                onReorder: _reorder,
                itemBuilder: (context, i) {
                  final last = i == _dest.length - 1;
                  return Padding(
                    // Кілт — ТҰРАҚТЫ id (индекс емес): сүйрегенде элемент
                    // өзімен бірге «жүреді», анимация да, мәтін де бұзылмайды.
                    key: ValueKey(_dest[i].id),
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                      decoration: BoxDecoration(
                        color: Gz.bg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          // Соңғысы — финиш туы, қалғаны нөмірленген аялдама.
                          SizedBox(
                            width: 22,
                            child: Center(
                              child: last
                                  ? const RoutePointMark.finish()
                                  : RoutePointMark.stop(i + 1),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: InkWell(
                              onTap: () => _edit(i),
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 6),
                                child: Text(
                                  _dest[i].addr.address,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => _remove(i),
                            icon: const Icon(Icons.cancel),
                            iconSize: 20,
                            color: Gz.red,
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 34,
                              minHeight: 34,
                            ),
                            tooltip: t('Алып тастау'),
                          ),
                          // Сүйреу тұтқасы — тек осы жерден сүйрейді, сол
                          // себепті мекенжайды түрту «өзгерту» болып қалады.
                          ReorderableDragStartListener(
                            index: i,
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 6),
                              child: Icon(
                                Icons.drag_handle,
                                size: 20,
                                color: Gz.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 4),
            if (_canAdd)
              AddAddressButton(onPressed: _add)
            else
              Text(
                '${t('Ең көбі')} ${kMaxExtraStops + 1} ${t('мекенжай')}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Gz.textSecondary, fontSize: 12),
              ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                _dest.map((e) => e.addr).toList(),
              ),
              child: BtnLabel(t('Дайын')),
            ),
          ],
        ),
      ),
    );
  }
}
