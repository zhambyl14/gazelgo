import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import 'executor_apply_screen.dart';

/// Орындаушы өтінімінің күйі: қаралуда / қабылданбады / бұғатталды.
class PendingScreen extends ConsumerWidget {
  final ExecutorProfile profile;
  const PendingScreen({super.key, required this.profile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (icon, color, title, text) = switch (profile.status) {
      'rejected' => (
          Icons.cancel_outlined,
          Gz.red,
          t('Өтінім қабылданбады'),
          profile.moderationComment?.isNotEmpty == true
              ? '${t('Себебі:')} ${profile.moderationComment}'
              : t('Деректерді түзетіп, қайта жіберіңіз.')
        ),
      'blocked' => (
          Icons.block,
          Gz.red,
          t('Аккаунт бұғатталған'),
          profile.moderationComment?.isNotEmpty == true
              ? '${t('Себебі:')} ${profile.moderationComment}'
              : t('Қолдау қызметіне хабарласыңыз.')
        ),
      _ => (
          Icons.hourglass_top,
          Gz.blue,
          t('Өтінім қаралуда'),
          t('Модератор құжаттарыңызды тексеруде. Әдетте бұл 24 сағатқа дейін уақыт алады.')
        ),
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tasu'),
        actions: [
          IconButton(
            tooltip: t('Жаңарту'),
            onPressed: () => ref.invalidate(myExecutorProfileProvider),
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
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 52, color: color),
              ),
              const SizedBox(height: 20),
              Text(title,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Gz.textSecondary, fontSize: 14.5),
              ),
              const SizedBox(height: 28),
              if (profile.status == 'rejected')
                SizedBox(
                  width: 260,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            ExecutorApplyScreen(existing: profile),
                      ),
                    ),
                    icon: const Icon(Icons.edit),
                    label: Text(t('Қайта толтыру')),
                  ),
                ),
              if (profile.status == 'pending')
                SizedBox(
                  width: 260,
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        ref.invalidate(myExecutorProfileProvider),
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
