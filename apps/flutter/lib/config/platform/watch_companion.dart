import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/account_providers.dart';
import 'package:pomodoist/config/app_language.dart';
import 'package:pomodoist/config/focus_dependencies.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/config/runtime_public_config.dart';
import 'package:pomodoist/data/services/platform/watch_companion_service.dart';
import 'package:pomodoist/domain/use_cases/platform/watch_companion_use_case.dart';
import 'package:pomodoist/domain/use_cases/quick_add/voice_quick_add_use_case.dart';
import 'package:pomodoist/ui/core/localization/app_locale.dart';

final watchCompanionServiceProvider = Provider<WatchCompanionService>((ref) {
  ref.watch(accountSessionProvider);
  final selectedPresetId = ref.watch(lastFocusPresetIdProvider);
  final account = ref.watch(accountClientProvider);
  final language = ref.watch(appLanguageProvider);
  final runtime = ref.watch(runtimePublicConfigProvider);
  final voiceQuickAdd = VoiceQuickAddUseCase(
    quickAdd: ref.watch(quickAddUseCaseProvider),
    runLocalTransaction: ref.watch(localTransactionProvider),
    hints: ref.watch(quickAddHintRepositoryProvider),
  );
  final actions = WatchCompanionUseCase(
    taskRepository: ref.watch(taskRepositoryProvider),
    projectRepository: ref.watch(projectRepositoryProvider),
    focusRepository: ref.watch(focusRepositoryProvider),
    quickAddService: ref.watch(quickAddUseCaseProvider),
    voiceQuickAdd: voiceQuickAdd,
    taskDecomposer: ref.watch(taskDecomposerProvider),
    localeProvider: () => resolveAppLocale(language).toLanguageTag(),
    selectedFocusPresetIdProvider: () => selectedPresetId,
  );
  final service = WatchCompanionService(
    execute: actions.execute,
    snapshot: actions.buildSnapshot,
    snapshotChanges: actions.snapshotChanges,
    accountSessionProvider: () => watchAccountSessionPayload(
      account?.currentSession,
      environment: runtime.environment.name,
      release: runtime.release,
      webAppUrl: runtime.webAppUrl.toString(),
      supabaseUrl: runtime.supabaseUrl?.toString(),
      supabaseAnonKey: runtime.supabaseAnonKey,
      turnstileSiteKey: runtime.turnstileSiteKey,
      sentryDsn: runtime.sentryDsn?.toString(),
    ),
  );
  service.start();
  ref.onDispose(service.dispose);
  return service;
});
