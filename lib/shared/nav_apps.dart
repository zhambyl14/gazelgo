import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:url_launcher/url_launcher.dart';

import '../core/lang.dart';
import '../core/prefs.dart';
import '../core/theme.dart';
import 'widgets.dart';

/// Орындаушы жол салатын навигатор. ҚР-да ең көп қолданылатыны — 2GIS,
/// бірақ көп жүргізуші Яндекс Навигатор не Google Maps-ке үйренген —
/// сол себепті бірінші басқанда СҰРАЛАДЫ да, таңдау есте сақталады.
enum NavApp { dgis, yandex, google }

extension NavAppX on NavApp {
  String get label => switch (this) {
    NavApp.dgis => '2GIS',
    NavApp.yandex => t('Яндекс Навигатор'),
    NavApp.google => 'Google Maps',
  };

  Color get color => switch (this) {
    NavApp.dgis => Gz.green,
    NavApp.yandex => Gz.red,
    NavApp.google => Gz.blue,
  };
}

class NavApps {
  NavApps._();

  static Future<NavApp?> saved() async {
    final v = await Prefs.navApp();
    for (final a in NavApp.values) {
      if (a.name == v) return a;
    }
    return null;
  }

  /// Нүктеге жол салу: сақталған навигатормен, ал таңдалмаған болса —
  /// алдымен таңдау терезесі.
  static Future<void> open(
    BuildContext context,
    double lat,
    double lng,
  ) async {
    var app = await saved();
    if (app == null) {
      if (!context.mounted) return;
      app = await pick(context);
    }
    if (app == null) return;
    await launch(app, lat, lng);
  }

  /// Навигатор таңдау терезесі (таңдау сақталады).
  static Future<NavApp?> pick(BuildContext context) async {
    final current = await saved();
    if (!context.mounted) return null;
    final app = await showGzSheet<NavApp>(
      context,
      builder: (ctx) => GzSheetBody(
        title: t('Қай навигатормен жүресіз?'),
        subtitle: t('Таңдауыңыз есте қалады — кейін «⋯» мәзірінен '
            'өзгертуге болады.'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final a in NavApp.values)
              GzListRow(
                icon: Icons.navigation_rounded,
                color: a.color,
                title: a.label,
                trailing: a == current
                    ? const Icon(Icons.check_circle_rounded, color: Gz.green)
                    : null,
                onTap: () => Navigator.pop(ctx, a),
              ),
          ],
        ),
      ),
    );
    if (app != null) await Prefs.setNavApp(app.name);
    return app;
  }

  /// Алдымен навигатордың ӨЗ қосымшасы; ол орнатылмаса не платформа
  /// қолдамаса — сол сервистің веб-бағыттар беті (кез келген құрылғыда).
  static Future<void> launch(NavApp app, double lat, double lng) async {
    if (!kIsWeb) {
      final ios = defaultTargetPlatform == TargetPlatform.iOS;
      final natives = switch (app) {
        NavApp.dgis => [
          'dgis://2gis.ru/routeSearch/rsType/car/to/$lng,$lat',
        ],
        NavApp.yandex => [
          'yandexnavi://build_route_on_map?lat_to=$lat&lon_to=$lng',
          'yandexmaps://maps.yandex.ru/?rtext=~$lat,$lng&rtt=auto',
        ],
        NavApp.google => [
          ios
              ? 'comgooglemaps://?daddr=$lat,$lng&directionsmode=driving'
              : 'google.navigation:q=$lat,$lng&mode=d',
        ],
      };
      for (final u in natives) {
        try {
          if (await launchUrl(
            Uri.parse(u),
            mode: LaunchMode.externalApplication,
          )) {
            return;
          }
        } catch (_) {
          // қосымша жоқ — келесі нұсқаға / вебке
        }
      }
    }
    final web = switch (app) {
      NavApp.dgis => 'https://2gis.kz/routeSearch/rsType/car/to/$lng,$lat',
      NavApp.yandex => 'https://yandex.kz/maps/?rtext=~$lat,$lng&rtt=auto',
      NavApp.google =>
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng'
            '&travelmode=driving',
    };
    await launchUrl(Uri.parse(web), mode: LaunchMode.externalApplication);
  }
}

/// Мекенжайды буферге көшіру (жүргізуші оны басқа қосымшаға қоя алады).
Future<void> copyAddress(BuildContext context, String address) async {
  await Clipboard.setData(ClipboardData(text: address));
  if (context.mounted) showSnack(context, t('Мекенжай көшірілді'));
}
