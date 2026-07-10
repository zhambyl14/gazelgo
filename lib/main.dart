import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/env.dart';
import 'core/notify.dart';
import 'core/push.dart';
import 'core/repo.dart';
import 'core/theme.dart';
import 'features/auth/blocked_screen.dart';
import 'features/auth/executor_apply_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/pending_screen.dart';
import 'features/client/client_shell.dart';
import 'features/executor/executor_shell.dart';
import 'features/moderator/moderator_shell.dart';
import 'shared/location_gate.dart';
import 'shared/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Env.isConfigured) {
    await Supabase.initialize(
      url: Env.supabaseUrl,
      // ignore: deprecated_member_use
      anonKey: Env.supabaseAnonKey,
    );
  }
  await Notify.init();
  runApp(const ProviderScope(child: GazelGoApp()));
}

class GazelGoApp extends StatelessWidget {
  const GazelGoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GazelGo',
      debugShowCheckedModeBanner: false,
      theme: Gz.theme(),
      home: Env.isConfigured ? const AuthGate() : const _NotConfigured(),
    );
  }
}

class _NotConfigured extends StatelessWidget {
  const _NotConfigured();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GazelGoLogo(size: 32),
              SizedBox(height: 24),
              Text(
                'Backend бапталмаған',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 12),
              Text(
                'lib/core/env.dart ішіне Supabase ANON KEY қойыңыз '
                'және supabase/APPLY.md нұсқаулығын орындаңыз.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Gz.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);

    return auth.when(
      loading: () => const _Splash(),
      error: (e, st) => const LoginScreen(),
      data: (state) {
        final session = Supabase.instance.client.auth.currentSession;
        if (session == null) return const LoginScreen();
        // Push-токенді тіркеу — қосымша толық жабық тұрғанда да
        // хабарландыру жеткізілуі үшін. Firebase бапталмаса — үнсіз өтеді.
        unawaited(Push.init());
        return const _RoleRouter();
      },
    );
  }
}

class _RoleRouter extends ConsumerWidget {
  const _RoleRouter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(myProfileProvider);

    return profile.when(
      loading: () => const _Splash(),
      error: (e, st) =>
          _RetryScreen(onRetry: () => ref.invalidate(myProfileProvider)),
      data: (p) {
        if (p == null) {
          return _RetryScreen(onRetry: () => ref.invalidate(myProfileProvider));
        }
        // Сенім деңгейі бойынша бұғатталған аккаунт (0024) — модератордан
        // басқа ешкім қосымшаға мүлдем кіре алмайды.
        if (p.isBlocked && p.role != 'moderator') {
          return BlockedScreen(profile: p);
        }
        switch (p.role) {
          case 'moderator':
            return const ModeratorShell();
          case 'executor':
            return const _ExecutorRouter();
          default:
            return const LocationGate(child: ClientShell());
        }
      },
    );
  }
}

class _ExecutorRouter extends ConsumerWidget {
  const _ExecutorRouter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ep = ref.watch(myExecutorProfileProvider);

    return ep.when(
      loading: () => const _Splash(),
      error: (e, st) => _RetryScreen(
          onRetry: () => ref.invalidate(myExecutorProfileProvider)),
      data: (e) {
        if (e == null) return const ExecutorApplyScreen();
        if (e.status == 'approved') {
          return const LocationGate(child: ExecutorShell());
        }
        return PendingScreen(profile: e);
      },
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Gz.surface,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GazelGoHero(),
            SizedBox(height: 32),
            SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 3, color: Gz.ink),
            ),
          ],
        ),
      ),
    );
  }
}

class _RetryScreen extends StatelessWidget {
  final VoidCallback onRetry;
  const _RetryScreen({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off, size: 48, color: Gz.textSecondary),
              const SizedBox(height: 16),
              const Text('Жүктеу мүмкін болмады',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 20),
              SizedBox(
                width: 220,
                child: FilledButton(
                  onPressed: onRetry,
                  child: const Text('Қайталау'),
                ),
              ),
              TextButton(
                onPressed: () => confirmSignOut(context),
                child: const Text('Шығу'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
