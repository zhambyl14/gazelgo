import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/notify.dart';
import '../../core/repo.dart';
import 'home_screen.dart';

/// Клиенттің қабығы: төменгі навбар жоқ — тек Басты бет (профиль/тапсырыстар
/// енді сонда, оң жақ жоғарғы бұрыштағы профиль батырмасы арқылы қолжетімді).
class ClientShell extends StatefulWidget {
  const ClientShell({super.key});

  @override
  State<ClientShell> createState() => _ClientShellState();
}

class _ClientShellState extends State<ClientShell> {
  final Map<String, String> _lastStatus = {};
  bool _primed = false;

  /// Заказ статусы өзгергенде клиентке хабарлау.
  void _watchStatuses(List<Order> orders) {
    for (final o in orders) {
      final prev = _lastStatus[o.id];
      _lastStatus[o.id] = o.status;
      if (!_primed || prev == null || prev == o.status) continue;
      final msg = switch (o.status) {
        'accepted' => 'Орындаушы табылды! Жолға шықты 🚚',
        'arrived' => 'Орындаушы келді — қарсы алыңыз',
        'in_transit' => 'Жүгіңіз жолда',
        'completed' => 'Заказ аяқталды. Орындаушыны бағалаңыз ⭐',
        'cancelled' => 'Заказ тоқтатылды',
        _ => null,
      };
      if (msg != null) {
        Notify.show('GazelGo', msg, id: o.id.hashCode & 0x7fffffff);
      }
    }
    _primed = true;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Order>>(
      stream: Repo.myOrdersStream(),
      builder: (context, snap) {
        if (snap.hasData) _watchStatuses(snap.data!);
        return const ClientHomeScreen();
      },
    );
  }
}
