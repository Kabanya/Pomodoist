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
    this.email,
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
  final String? email;
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
      email: profile?.email,
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

  Future<void> signOut() async {
    final repository = ref.read(accountManagementRepositoryProvider);
    if (repository != null) {
      (await repository.signOut()).getOrThrow();
    }
  }
}
