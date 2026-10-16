import 'package:flutter/material.dart';

import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';

/// Заказдың қосымша талаптары (0075): тиеушілер, қабат, лифт.
class OrderExtras {
  final int loaders;
  final int? floorFrom;
  final int? floorTo;
  final bool? elevator;

  const OrderExtras({
    this.loaders = 0,
    this.floorFrom,
    this.floorTo,
    this.elevator,
  });

  factory OrderExtras.of(Order o) => OrderExtras(
    loaders: o.loaders,
    floorFrom: o.floorFrom,
    floorTo: o.floorTo,
    elevator: o.hasElevator,
  );

  bool get isEmpty =>
      loaders == 0 && floorFrom == null && floorTo == null && elevator == null;

  /// Лифт сұрағының мәні бар ма (кемінде бір жақта 2+ қабат).
  bool get needsElevator => (floorFrom ?? 0) > 1 || (floorTo ?? 0) > 1;

  OrderExtras copyWith({
    int? loaders,
    int? Function()? floorFrom,
    int? Function()? floorTo,
    bool? Function()? elevator,
  }) => OrderExtras(
    loaders: loaders ?? this.loaders,
    floorFrom: floorFrom == null ? this.floorFrom : floorFrom(),
    floorTo: floorTo == null ? this.floorTo : floorTo(),
    elevator: elevator == null ? this.elevator : elevator(),
  );

  /// Сервер 0075-сіз болса — талаптар түсініктемеге мәтін болып қосылады.
  String asText() {
    String floor(int? f) => f == null ? '—' : '$f';
    return [
      if (loaders > 0) '${t('Тиеуші')}: $loaders',
      if (floorFrom != null || floorTo != null)
        '${t('Қабат')}: A ${floor(floorFrom)} → B ${floor(floorTo)}',
      if (elevator != null) elevator! ? t('Лифт бар') : t('Лифт жоқ'),
    ].join(', ');
  }
}

/// «Қосымша талаптар» — МІНДЕТТІ ЕМЕС, әдепкіде жиналған блок. Көп
/// клиентке керек емес, сондықтан форманы ауырлатпайды: ашқан адам ғана
/// толтырады.
class OrderExtrasEditor extends StatefulWidget {
  final OrderExtras value;
  final ValueChanged<OrderExtras> onChanged;
  final bool initiallyExpanded;
  final bool isTaxi;

  const OrderExtrasEditor({
    super.key,
    required this.value,
    required this.onChanged,
    this.initiallyExpanded = false,
    this.isTaxi = false,
  });

  @override
  State<OrderExtrasEditor> createState() => _OrderExtrasEditorState();
}

class _OrderExtrasEditorState extends State<OrderExtrasEditor> {
  late bool _open = widget.initiallyExpanded || !widget.value.isEmpty;

  OrderExtras get _v => widget.value;

  void _set(OrderExtras v) {
    // 2+ қабат жоқ болса, лифт сұрағы мағынасыз — тазалаймыз.
    widget.onChanged(
      v.needsElevator ? v : v.copyWith(elevator: () => null),
    );
  }

  Widget _floorStepper(String label, int? value, ValueChanged<int?> onSet) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: Gz.bg,
        borderRadius: BorderRadius.circular(Gz.rSm),
        border: Border.all(color: Gz.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Gz.caption),
                Text(
                  value == null ? t('Көрсетілмеген') : '$value ${t('қабат')}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          GzStepButton(
            icon: Icons.remove_rounded,
            size: 36,
            onTap: value == null
                ? null
                : () => onSet(value <= 1 ? null : value - 1),
          ),
          const SizedBox(width: 6),
          GzStepButton(
            icon: Icons.add_rounded,
            size: 36,
            onTap: (value ?? 0) >= 60 ? null : () => onSet((value ?? 0) + 1),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final v = _v;
    return SectionCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(Gz.radius),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: Row(
                children: [
                  const Icon(Icons.tune_rounded, color: Gz.violet),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t('Қосымша талаптар'), style: Gz.h3),
                        Text(
                          v.isEmpty
                              ? (widget.isTaxi
                                    ? t('Міндетті емес')
                                    : t('Тиеушілер, қабат, лифт — міндетті емес'))
                              : v.asText(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Gz.caption,
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.expand_more_rounded),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            child: !_open
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(t('Тиеушілер'), style: Gz.caption),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final n in const [0, 1, 2, 3, 4])
                              ChoiceChip(
                                label: Text(
                                  n == 0
                                      ? t('Керек емес')
                                      : (n == 4 ? '4+' : '$n'),
                                ),
                                selected: v.loaders == n,
                                onSelected: (_) =>
                                    _set(v.copyWith(loaders: n)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _floorStepper(
                                t('A қабаты'),
                                v.floorFrom,
                                (f) => _set(v.copyWith(floorFrom: () => f)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _floorStepper(
                                t('B қабаты'),
                                v.floorTo,
                                (f) => _set(v.copyWith(floorTo: () => f)),
                              ),
                            ),
                          ],
                        ),
                        if (v.needsElevator) ...[
                          const SizedBox(height: 12),
                          Text(t('Лифт'), style: Gz.caption),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            children: [
                              ChoiceChip(
                                label: Text(t('Бар')),
                                selected: v.elevator == true,
                                onSelected: (_) =>
                                    _set(v.copyWith(elevator: () => true)),
                              ),
                              ChoiceChip(
                                label: Text(t('Жоқ')),
                                selected: v.elevator == false,
                                onSelected: (_) =>
                                    _set(v.copyWith(elevator: () => false)),
                              ),
                              ChoiceChip(
                                label: Text(t('Білмеймін')),
                                selected: v.elevator == null,
                                onSelected: (_) =>
                                    _set(v.copyWith(elevator: () => null)),
                              ),
                            ],
                          ),
                        ],
                        if (!v.isEmpty) ...[
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () => _set(const OrderExtras()),
                              icon: const Icon(Icons.close_rounded, size: 18),
                              label: Text(t('Тазалау')),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Іздеу кезінде заказды өңдеу: жүк, түсініктеме, қосымша талаптар (0075).
/// Қайтарады: (жүк, түсініктеме, талаптар) не бас тартса — null.
Future<(String, String, OrderExtras)?> showEditOrderSheet(
  BuildContext context,
  Order order,
) {
  return showGzSheet<(String, String, OrderExtras)>(
    context,
    builder: (_) => _EditOrderSheet(order: order),
  );
}

class _EditOrderSheet extends StatefulWidget {
  final Order order;
  const _EditOrderSheet({required this.order});

  @override
  State<_EditOrderSheet> createState() => _EditOrderSheetState();
}

class _EditOrderSheetState extends State<_EditOrderSheet> {
  late final _cargo = TextEditingController(text: widget.order.cargoDesc);
  late final _comment = TextEditingController(text: widget.order.comment);
  late OrderExtras _extras = OrderExtras.of(widget.order);
  String? _error;

  @override
  void dispose() {
    _cargo.dispose();
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isTaxi = widget.order.vehicleType == VehicleType.taxi;
    return GzSheetBody(
      title: t('Заказды өңдеу'),
      subtitle: t('Өзгеріс орындаушыларға бірден көрінеді.'),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _cargo,
                maxLength: 500,
                minLines: 1,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: isTaxi ? t('Сапар туралы') : t('Жүк'),
                  errorText: _error,
                  counterText: '',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _comment,
                maxLength: 500,
                minLines: 1,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: t('Түсініктеме'),
                  counterText: '',
                ),
              ),
              if (!isTaxi) ...[
                const SizedBox(height: 10),
                OrderExtrasEditor(
                  value: _extras,
                  initiallyExpanded: true,
                  onChanged: (v) => setState(() => _extras = v),
                ),
              ],
              const SizedBox(height: 14),
              GzPrimaryButton(
                label: t('Сақтау'),
                onPressed: () {
                  if (_cargo.text.trim().isEmpty) {
                    setState(() => _error = t('Жүкті сипаттаңыз'));
                    return;
                  }
                  Navigator.pop(
                    context,
                    (_cargo.text.trim(), _comment.text.trim(), _extras),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
