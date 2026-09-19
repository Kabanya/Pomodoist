import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/app_language.dart';
import 'package:pomodoist/config/clock_provider.dart';
import 'package:pomodoist/config/focus_dependencies.dart';
import 'package:pomodoist/config/task_preferences_dependencies.dart';
import 'package:pomodoist/domain/models/focus/focus_view_mode.dart';
import 'package:pomodoist/domain/models/settings/app_language.dart';

const onboardingCompletedPreferenceKey = 'onboarding.completed.v1';
const launchOfferStartedAtPreferenceKey = 'launchOffer.startedAt.v1';
const launchOfferDuration = Duration(hours: 24);
const launchOfferCycleDuration = Duration(days: 7);

enum OnboardingStep { language, timer, paywall, account }

class OnboardingState {
  const OnboardingState({
    this.loading = true,
    this.completed = false,
    this.step = OnboardingStep.language,
    this.launchOfferStartedAt,
    this.language = AppLanguage.system,
    this.timerStyle = FocusTimerVisualStyle.bar,
  });

  final bool loading;
  final bool completed;
  final OnboardingStep step;
  final DateTime? launchOfferStartedAt;
  final AppLanguage language;
  final FocusTimerVisualStyle timerStyle;

  OnboardingState copyWith({
    bool? loading,
    bool? completed,
    OnboardingStep? step,
    DateTime? launchOfferStartedAt,
    AppLanguage? language,
    FocusTimerVisualStyle? timerStyle,
  }) => OnboardingState(
    loading: loading ?? this.loading,
    completed: completed ?? this.completed,
    step: step ?? this.step,
    launchOfferStartedAt: launchOfferStartedAt ?? this.launchOfferStartedAt,
    language: language ?? this.language,
    timerStyle: timerStyle ?? this.timerStyle,
  );
}

final onboardingViewModelProvider =
    NotifierProvider<OnboardingViewModel, OnboardingState>(
      OnboardingViewModel.new,
    );

class OnboardingViewModel extends Notifier<OnboardingState> {
  @override
  OnboardingState build() {
    ref.listen(appLanguageProvider, (_, language) {
      if (ref.mounted) state = state.copyWith(language: language);
    });
    ref.listen(focusTimerVisualStyleProvider, (_, style) {
      if (ref.mounted) state = state.copyWith(timerStyle: style);
    });
    unawaited(_load());
    return OnboardingState(
      language: ref.read(appLanguageProvider),
      timerStyle: ref.read(focusTimerVisualStyleProvider),
    );
  }

  DateTime now() => ref.read(clockProvider).now();

  void next() {
    if (state.step == OnboardingStep.account) {
      unawaited(complete());
      return;
    }
    state = state.copyWith(step: OnboardingStep.values[state.step.index + 1]);
  }

  void back() {
    if (state.step != OnboardingStep.language) {
      state = state.copyWith(step: OnboardingStep.values[state.step.index - 1]);
    }
  }

  Future<void> setLanguage(AppLanguage language) async {
    (await ref.read(languageRepositoryProvider).setLanguage(language))
        .getOrThrow();
  }

  Future<void> setTimerStyle(FocusTimerVisualStyle style) async {
    (await ref.read(focusPreferencesRepositoryProvider).setTimerStyle(style))
        .getOrThrow();
  }

  Future<void> complete() async {
    (await ref.read(preferencesRepositoryProvider).write(const {
      onboardingCompletedPreferenceKey: true,
    })).getOrThrow();
    if (ref.mounted) state = state.copyWith(completed: true);
  }

  Future<void> _load() async {
    final preferences = ref.read(preferencesRepositoryProvider);
    final values = (await preferences.read(const [
      onboardingCompletedPreferenceKey,
      launchOfferStartedAtPreferenceKey,
    ])).getOrThrow();
    if (!ref.mounted) return;
    final completed =
        values[onboardingCompletedPreferenceKey] as bool? ?? false;
    final now = ref.read(clockProvider).now().toUtc();
    var startedAt = DateTime.tryParse(
      values[launchOfferStartedAtPreferenceKey] as String? ?? '',
    )?.toUtc();
    if (startedAt == null) {
      startedAt = now;
      (await preferences.write({
        launchOfferStartedAtPreferenceKey: startedAt.toIso8601String(),
      })).getOrThrow();
    }
    if (ref.mounted) {
      state = state.copyWith(
        loading: false,
        completed: completed,
        launchOfferStartedAt: startedAt,
      );
    }
  }
}

Duration launchOfferRemaining({
  required DateTime now,
  required DateTime? startedAt,
}) {
  if (startedAt == null) return Duration.zero;
  final elapsed = now.toUtc().difference(startedAt.toUtc());
  if (elapsed.isNegative) return Duration.zero;
  final cyclePosition = Duration(
    microseconds:
        elapsed.inMicroseconds % launchOfferCycleDuration.inMicroseconds,
  );
  return cyclePosition >= launchOfferDuration
      ? Duration.zero
      : launchOfferDuration - cyclePosition;
}

int? launchOfferCycle({required DateTime now, required DateTime? startedAt}) {
  if (startedAt == null) return null;
  final elapsed = now.toUtc().difference(startedAt.toUtc());
  if (elapsed.isNegative) return null;
  return elapsed.inMicroseconds ~/ launchOfferCycleDuration.inMicroseconds;
}

String formatLaunchOfferRemaining(Duration duration) {
  final hours = duration.inHours.toString().padLeft(2, '0');
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$hours:$minutes:$seconds';
}
