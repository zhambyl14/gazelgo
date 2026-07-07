import 'package:flutter/material.dart';

/// Төменнен жоғары сырғып шығатын экран өтуі (bottom-sheet әсері).
Route<T> slideUpRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    opaque: false,
    barrierColor: Colors.black45,
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, animation, secondary) => page,
    transitionsBuilder: (context, animation, secondary, child) {
      final curved =
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(curved),
        child: FadeTransition(opacity: curved, child: child),
      );
    },
  );
}
