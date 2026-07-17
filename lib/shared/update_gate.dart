import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/lang.dart';
import '../core/repo.dart';
import '../core/theme.dart';
import 'widgets.dart';

/// Мәжбүрлі жаңарту («force update») қақпасы: қосымшаның ағымдағы build
/// нөмірін сервердегі `version_gate.min_build`-пен салыстырады. Ескі болса —
/// толық экранды жабады, тек «Жаңарту» батырмасы дүкенге апарады (сессия
/// болмаса да, кіру экранына дейін тексереді). Сервермен байланыс болмаса
/// (офлайн, әлі бапталмаған) — ЖАБЫҚ ЕТПЕЙ, қосымшаны жіберіп жібереді
/// (fail-open — жобадағы басқа сенімділік-маңызды тексерулермен бірдей тәсіл).
class UpdateGate extends StatefulWidget {
  final Widget child;
  const UpdateGate({super.key, required this.child});

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> {
  bool _checked = false;
  Map<String, dynamic>? _blockInfo; // null = бұғатталмаған

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      final gate = await Repo.appVersionGate();
      final minBuild = _minBuildFor(gate);
      if (minBuild <= 0) {
        if (mounted) setState(() => _checked = true);
        return;
      }
      final info = await PackageInfo.fromPlatform();
      final myBuild = int.tryParse(info.buildNumber) ?? 0;
      if (myBuild > 0 && myBuild < minBuild) {
        if (mounted) {
          setState(() {
            _blockInfo = gate;
            _checked = true;
          });
        }
        return;
      }
    } catch (_) {
      // сервермен байланыс жоқ не бапталмаған — жібере береміз
    }
    if (mounted) setState(() => _checked = true);
  }

  /// Осы платформаға тиесілі минималды build. Android мен iOS дүкенде әр
  /// нұсқада болатындықтан (App Store шолуы Play-ден кеш) — әр платформаға
  /// ЖЕКЕ шек. Платформаға арналған мән толмаса, ескі жалпы `min_build`-ке
  /// қайтады (кері үйлесімділік). Бұл: Android-та жаңа нұсқа шыққанда, iOS
  /// App Store-да ол әлі жоқ болса, iPhone соңғы нұсқада отырса да қате
  /// бұғатталатын багты жояды.
  int _minBuildFor(Map<String, dynamic> gate) {
    final generic = int.tryParse('${gate['min_build'] ?? 0}') ?? 0;
    if (!kIsWeb && Platform.isIOS) {
      return int.tryParse('${gate['min_build_ios'] ?? ''}') ?? generic;
    }
    if (!kIsWeb && Platform.isAndroid) {
      return int.tryParse('${gate['min_build_android'] ?? ''}') ?? generic;
    }
    return generic;
  }

  Future<void> _openStore() async {
    final gate = _blockInfo;
    if (gate == null) return;
    final url = kIsWeb
        ? null
        : (Platform.isIOS ? gate['ios_url'] : gate['android_url']) as String?;
    if (url == null || url.isEmpty) return;
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) {
      return const Scaffold(
        backgroundColor: Gz.surface,
        body: Center(child: CircularProgressIndicator(color: Gz.ink)),
      );
    }
    final gate = _blockInfo;
    if (gate == null) return widget.child;
    return Scaffold(
      backgroundColor: Gz.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const GazelGoLogo(size: 32),
                const SizedBox(height: 24),
                const Icon(Icons.system_update, size: 56, color: Gz.yellowDark),
                const SizedBox(height: 16),
                Text(t('Жаңарту қажет'),
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Text(
                  (gate['message'] as String?)?.trim().isNotEmpty == true
                      ? gate['message'] as String
                      : t('Жаңа нұсқа шықты. Жалғастыру үшін қосымшаны '
                          'жаңартыңыз.'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Gz.textSecondary),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _openStore,
                  child: Text(t('Жаңарту')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
