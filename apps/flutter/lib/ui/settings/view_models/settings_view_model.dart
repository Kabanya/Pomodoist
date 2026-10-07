import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/account_providers.dart';
import 'package:pomodoist/config/account_management_dependencies.dart';
import 'package:pomodoist/config/app_language.dart';
import 'package:pomodoist/config/focus_dependencies.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/config/task_preferences_dependencies.dart';
import 'package:pomodoist/config/voice_preferences_dependencies.dart';
import 'package:pomodoist/domain/models/focus/focus_view_mode.dart';
import 'package:pomodoist/domain/models/settings/app_language.dart';
import 'package:pomodoist/domain/models/account/sync_status.dart';
export 'package:pomodoist/domain/models/account/sync_status.dart';

final syncRestartViewModelProvider =
    NotifierProvider.autoDispose<SyncRestartViewModel, SyncRestartPhase>(
      SyncRestartViewModel.new,
    );

class SyncRestartViewModel extends Notifier<SyncRestartPhase> {
  int _generation = 0;
  Future<void>? _running;
  @override
  SyncRestartPhase build() {
    ref.watch(localSyncOwnerProvider);
    _generation++;
    _running = null;
    return SyncRestartPhase.idle;
  }

  Future<void> restart() {
    final generation = _generation;
    return _running ??= _restart().whenComplete(() {
      if (generation == _generation) _running = null;
    });
  }

  Future<void> _restart() async {
    final generation = _generation;
    state = SyncRestartPhase.running;
    try {
      await ref.read(accountSyncRestartProvider)();
      if (!ref.mounted || generation != _generation) return;
      final subscription = ref.listen(syncQueueStatusProvider, (_, _) {});
      ref.invalidate(syncQueueStatusProvider);
      final status = await ref
          .read(syncQueueStatusProvider.future)
          .whenComplete(subscription.close);
      if (!ref.mounted || generation != _generation) return;
      state =
          status.pending + status.rejected + status.repair > 0 ||
              status.recovering
          ? SyncRestartPhase.pending
          : SyncRestartPhase.complete;
    } catch (_) {
      if (ref.mounted && generation == _generation) {
        state = SyncRestartPhase.failed;
      }
    }
  }
}

final class SettingsViewState {
  const SettingsViewState({
    required this.language,
    required this.voiceModeSupported,
    required this.reengagementEnabled,
    required this.timerStyle,
    required this.celebrationEnabled,
    required this.accountConfigured,
    required this.accountLoading,
    required this.accountAvailable,
    required this.signedIn,
    this.accountError,
    this.overviewError,
    this.userId,
    this.displayName,
    this.avatarEmoji,
    this.email,
    this.syncPrepared = false,
  });

  final AppLanguage language;
  final bool voiceModeSupported;
  final bool reengagementEnabled;
  final FocusTimerVisualStyle timerStyle;
  final bool celebrationEnabled;
  final bool accountConfigured;
  final bool accountLoading;
  final bool accountAvailable;
  final bool signedIn;
  final Object? accountError;
  final Object? overviewError;
  final String? userId;
  final String? displayName;
  final String? avatarEmoji;
  final String? email;
  final bool syncPrepared;
}

final settingsViewModelProvider =
    NotifierProvider<SettingsViewModel, SettingsViewState>(
      SettingsViewModel.new,
    );

class SettingsViewModel extends Notifier<SettingsViewState> {
  @override
  SettingsViewState build() {
    final availability = ref.watch(accountAvailabilityProvider);
    final session = ref.watch(accountSessionProvider).value;
    final signedIn = ref.watch(accountSignedInProvider);
    final overview = ref.watch(accountOverviewProvider);
    final profile = ref.watch(accountProfileProvider);
    final userId = session?.userId;
    return SettingsViewState(
      language: ref.watch(appLanguageProvider),
      voiceModeSupported: ref.watch(
        voiceTranscriptionModeSelectionSupportedProvider,
      ),
      reengagementEnabled: ref.watch(reengagementNotificationsEnabledProvider),
      timerStyle: ref.watch(focusTimerVisualStyleProvider),
      celebrationEnabled: ref.watch(focusCompletionCelebrationEnabledProvider),
      accountConfigured: availability.configured,
      accountLoading: availability.loading || overview.isLoading,
      accountAvailable: availability.available,
      signedIn: signedIn,
      accountError: availability.error,
      overviewError: overview.error,
      userId: userId,
      displayName: profile?.displayName,
      avatarEmoji: profile?.avatarEmoji,
      email: profile?.email,
      syncPrepared:
          userId != null && ref.watch(localSyncOwnerProvider).value == userId,
    );
  }

  Future<void> setLanguage(AppLanguage language) async =>
      (await ref.read(languageRepositoryProvider).setLanguage(language))
          .getOrThrow();

  Future<void> setReengagement(bool enabled) async {
    (await ref
            .read(taskPreferencesRepositoryProvider)
            .setReengagementEnabled(enabled))
        .getOrThrow();
    if (!enabled) {
      await ref
          .read(notificationRepositoryProvider)
          .cancelReengagementReminder();
    }
  }

  Future<void> setTimerStyle(FocusTimerVisualStyle style) async =>
      (await ref.read(focusPreferencesRepositoryProvider).setTimerStyle(style))
          .getOrThrow();

  Future<void> setCelebration(bool enabled) async =>
      (await ref
              .read(focusPreferencesRepositoryProvider)
              .setCelebrationEnabled(enabled))
          .getOrThrow();

  Future<void> retryAccount() async {
    await ref.read(accountBootstrapProvider.notifier).retry();
    if (ref.mounted) ref.invalidate(accountOverviewProvider);
  }

  void refreshAccount() => ref.invalidate(accountOverviewProvider);

  Future<void> saveNickname(String name) async {
    final repository = ref.read(accountManagementRepositoryProvider);
    if (repository == null || !repository.isCurrent) {
      throw StateError('The account session has changed.');
    }
    (await repository.updateNickname(name)).getOrThrow();
    if (ref.mounted) ref.invalidate(accountOverviewProvider);
  }

  Future<void> saveAvatarEmoji(String userId, String? emoji) async {
    final repository = ref.read(accountManagementRepositoryProvider);
    if (repository == null ||
        !repository.isCurrent ||
        repository.userId != userId) {
      throw StateError('The account session has changed.');
    }
    (await repository.updateAvatarEmoji(emoji)).getOrThrow();
    if (ref.mounted && repository.isCurrent) {
      ref.invalidate(accountOverviewProvider);
    }
  }

  Future<void> signOut() async {
    final repository = ref.read(accountManagementRepositoryProvider);
    if (repository != null) {
      (await repository.signOut()).getOrThrow();
    }
  }
}
