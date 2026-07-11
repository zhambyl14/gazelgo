import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';

/// Сенім деңгейі 50-ден төмен түскен не модератор қолмен бұғаттаған
/// аккаунт — қосымшаға МҮЛДЕМ кіре алмайды (0024). Жалғыз әрекет: қолдау
/// қызметіне жазу немесе шығу.
class BlockedScreen extends ConsumerWidget {
  final Profile profile;
  const BlockedScreen({super.key, required this.profile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GazelGo'),
        actions: [
          IconButton(
            tooltip: t('Жаңарту'),
            onPressed: () => ref.invalidate(myProfileProvider),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: t('Шығу'),
            onPressed: () => confirmSignOut(context),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: Gz.red.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.block, size: 52, color: Gz.red),
              ),
              const SizedBox(height: 20),
              Text(t('Аккаунт бұғатталған'),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              Text(
                profile.blockReason?.isNotEmpty == true
                    ? '${t('Себебі:')} ${profile.blockReason}'
                    : t('Қауіпсіздік себебімен аккаунтыңызға уақытша шектеу '
                        'қойылды.'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Gz.textSecondary, fontSize: 14.5),
              ),
              const SizedBox(height: 8),
              Text(
                t('Мәселені шешу үшін қолдау қызметіне хабарласыңыз.'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Gz.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: 260,
                child: OutlinedButton.icon(
                  onPressed: () => ref.invalidate(myProfileProvider),
                  icon: const Icon(Icons.refresh),
                  label: Text(t('Күйін тексеру')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
