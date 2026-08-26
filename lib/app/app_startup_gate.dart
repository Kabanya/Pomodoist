import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'account_providers.dart';
import 'app_l10n.dart';
import 'providers.dart';
import 'watch_companion.dart';

final appStartupLifecycleProvider = Provider<void>((ref) {
  ref.watch(accountSyncLifecycleProvider);
  ref.watch(recurringTaskMaterializationProvider);
  ref.watch(taskStartNotificationCoordinatorProvider);
  ref.watch(reengagementNotificationCoordinatorProvider);
  ref.watch(watchCompanionControllerProvider);
  ref.watch(quickAddHintControllerProvider);
});

class AppStartupGate extends ConsumerWidget {
  const AppStartupGate({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final startup = ref.watch(appStartupProvider);
    return startup.when(
      data: (_) {
        final accountStartup = ref.watch(accountSyncStartupProvider);
        return accountStartup.when(
          data: (_) {
            ref.watch(appStartupLifecycleProvider);
            return child;
          },
          loading: () => const _StartupLoading(),
          error: (error, _) => _StartupError(
            error: error,
            onRetry: () => ref.invalidate(accountSyncStartupProvider),
          ),
        );
      },
      loading: () => const _StartupLoading(),
      error: (error, _) => _StartupError(
        error: error,
        onRetry: () => ref.invalidate(appStartupProvider),
      ),
    );
  }
}

const _startupSlowThreshold = Duration(seconds: 30);

class _StartupLoading extends StatefulWidget {
  const _StartupLoading();

  @override
  State<_StartupLoading> createState() => _StartupLoadingState();
}

class _StartupLoadingState extends State<_StartupLoading> {
  Timer? _timer;
  var _takingLonger = false;

  @override
  void initState() {
    super.initState();
    _scheduleWarning();
  }

  void _scheduleWarning() {
    _timer?.cancel();
    _timer = Timer(_startupSlowThreshold, () {
      if (mounted) setState(() => _takingLonger = true);
    });
  }

  void _continueWaiting() {
    setState(() => _takingLonger = false);
    _scheduleWarning();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_takingLonger)
              const Icon(
                Icons.hourglass_top,
                key: Key('app-startup-slow'),
                size: 32,
              )
            else
              const CircularProgressIndicator(key: Key('app-startup-loading')),
            const SizedBox(height: 16),
            Semantics(
              liveRegion: true,
              child: Text(
                _takingLonger
                    ? context.l10n.operationTakingLonger
                    : context.l10n.startupPreparingTasks,
                textAlign: TextAlign.center,
              ),
            ),
            if (_takingLonger) ...[
              const SizedBox(height: 8),
              TextButton(
                key: const Key('app-startup-continue-waiting'),
                onPressed: _continueWaiting,
                child: Text(context.l10n.commonContinueWaiting),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Could not start Pomodoist',
                key: const Key('app-startup-error-title'),
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                '$error',
                key: const Key('app-startup-error-message'),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const Key('app-startup-retry-button'),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
