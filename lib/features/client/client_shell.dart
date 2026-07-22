import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/notify.dart';
import '../../core/repo.dart';
import 'create_order_screen.dart';
import 'draft_order.dart';
import 'home_screen.dart';

/// Клиенттің қабығы: төменгі навбар жоқ — тек Басты бет (профиль/тапсырыстар
/// енді сонда, оң жақ жоғарғы бұрыштағы профиль батырмасы арқылы қолжетімді).
///
/// [guest] — кірмеген қолданушы режимі: карта мен заказ толтыру ашық, бірақ
/// «Шақыру» мен профиль батырмасы кіру экранына бағыттайды.
class ClientShell extends ConsumerStatefulWidget {
  final bool guest;
  const ClientShell({super.key, this.guest = false});

  @override
  ConsumerState<ClientShell> createState() => _ClientShellState();
}

class _ClientShellState extends ConsumerState<ClientShell> {
  final Map<String, String> _lastStatus = {};
  bool _primed = false;

  @override
  void initState() {
    super.initState();
    // Кіргеннен кейін: гест кезінде толтырылған жоба заказ болса — жоғалтпай,
    // толтыру экранын ашып, автоматты жариялаймыз (фотолар енді жүктеледі).
    if (!widget.guest) {
      final draft = ref.read(draftOrderProvider);
      if (draft != null) {
        // Provider-ды build аяқталғанша модификациялауға болмайды (Riverpod
        // "Tried to modify a provider while the widget tree was building"
        // қатесі) — сол себепті тазалау мен навигацияны да кадр аяқталған
        // соңға қалдырамыз.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ref.read(draftOrderProvider.notifier).state = null;
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => CreateOrderScreen(
                from: draft.from,
                to: draft.to,
                vehicleType: draft.vehicle,
                draft: draft,
                autoSubmit: true,
              ),
            ),
          );
        });
      }
    }
  }

  /// Заказ статусы өзгергенде клиентке хабарлау.
  void _watchStatuses(List<Order> orders) {
    for (final o in orders) {
      final prev = _lastStatus[o.id];
      _lastStatus[o.id] = o.status;
      if (!_primed || prev == null || prev == o.status) continue;
      final msg = switch (o.status) {
        'accepted' => t('Орындаушы табылды! Жолға шықты 🚚'),
        'arrived' => t('Орындаушы келді — қарсы алыңыз'),
        'in_transit' => t('Жүгіңіз жолда'),
        'completed' => t('Заказ аяқталды. Орындаушыны бағалаңыз ⭐'),
        'cancelled' => t('Заказ тоқтатылды'),
        'searching' when prev != 'searching' => t(
          'Орындаушы бас тартты — заказыңыз қайта іздеуде 🔄',
        ),
        _ => null,
      };
      if (msg != null) {
        Notify.show('Tasu', msg, id: o.id.hashCode & 0x7fffffff);
      }
    }
    _primed = true;
  }

  @override
  Widget build(BuildContext context) {
    // Гест кезінде заказ стримі жоқ (uid жоқ) — тікелей басты бетті береміз.
    if (widget.guest) {
      return const ClientHomeScreen(isGuest: true);
    }
    return StreamBuilder<List<Order>>(
      stream: Repo.myOrdersStream(),
      builder: (context, snap) {
        if (snap.hasData) _watchStatuses(snap.data!);
        return const ClientHomeScreen();
      },
    );
  }
}
