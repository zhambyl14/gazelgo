import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../core/theme.dart';

/// Клиент/орындаушы экрандарын GPS қосулы әрі рұқсат берілгенше бұғаттайды.
/// Локация — жақын заказды табу, қаланы анықтау, навигация үшін платформаның
/// негізі, сол себепті осы екі рөлге міндетті. Модератор құрылғы орнына
/// байланысты жұмыс істемейтіндіктен бұғатталмайды.
class LocationGate extends StatefulWidget {
  final Widget child;
  const LocationGate({super.key, required this.child});

  @override
  State<LocationGate> createState() => _LocationGateState();
}

enum _LocState { checking, serviceOff, denied, deniedForever, ok }

class _LocationGateState extends State<LocationGate>
    with WidgetsBindingObserver {
  _LocState _state = _LocState.checking;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Пайдаланушы GPS/рұқсат параметрлерінен қайта оралғанда бірден тексереміз.
    if (state == AppLifecycleState.resumed && _state != _LocState.ok) {
      _check();
    }
  }

  Future<void> _check() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        if (mounted) setState(() => _state = _LocState.serviceOff);
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) {
        if (mounted) setState(() => _state = _LocState.deniedForever);
        return;
      }
      if (perm == LocationPermission.denied) {
        if (mounted) setState(() => _state = _LocState.denied);
        return;
      }
      if (mounted) setState(() => _state = _LocState.ok);
    } catch (_) {
      // платформа тексере алмаса (мыс. кейбір веб-браузерлер) — бұғаттамаймыз
      if (mounted) setState(() => _state = _LocState.ok);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_state == _LocState.checking) {
      return const Scaffold(
        backgroundColor: Gz.surface,
        body: Center(
            child: CircularProgressIndicator(strokeWidth: 3, color: Gz.ink)),
      );
    }
    if (_state == _LocState.ok) return widget.child;

    final (icon, title, desc, actionLabel, Future<void> Function() action) =
        switch (_state) {
      _LocState.serviceOff => (
          Icons.location_off_outlined,
          'GPS өшірулі',
          'GazelGo дұрыс жұмыс істеуі үшін (жақын заказдар, қаланы анықтау, '
              'навигация) құрылғының орналасу қызметі қосулы болуы керек.',
          'Параметрлерді ашу',
          () async {
            await Geolocator.openLocationSettings();
          },
        ),
      _LocState.deniedForever => (
          Icons.location_disabled_outlined,
          'Локацияға рұқсат керек',
          'Рұқсат қолданба параметрлерінде мүлдем өшірілген. Параметрлерден '
              'локацияға рұқсат беріңіз.',
          'Параметрлерді ашу',
          () async {
            await Geolocator.openAppSettings();
          },
        ),
      _ => (
          Icons.my_location_outlined,
          'Локацияға рұқсат беріңіз',
          'Жақын заказдарды көрсету және қалаңызды анықтау үшін '
              'орналасуыңызға рұқсат қажет.',
          'Рұқсат беру',
          () async {
            await Geolocator.requestPermission();
          },
        ),
    };

    return Scaffold(
      backgroundColor: Gz.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Gz.yellow.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 40, color: Gz.yellowDark),
                ),
                const SizedBox(height: 20),
                Text(title,
                    style: const TextStyle(
                        fontSize: 19, fontWeight: FontWeight.w800),
                    textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(desc,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Gz.textSecondary, fontSize: 13.5, height: 1.4)),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () async {
                      await action();
                      _check();
                    },
                    child: Text(actionLabel),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _check,
                  child: const Text('Тексеру'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
