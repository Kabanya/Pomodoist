import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pomodoist/data/repositories/focus/focus_completion_repository.dart';
import 'package:pomodoist/data/repositories/focus/focus_completion_repository_impl.dart';
import 'package:pomodoist/data/repositories/focus/focus_preferences_repository.dart';
import 'package:pomodoist/data/repositories/focus/focus_preferences_repository_impl.dart';
import 'package:pomodoist/data/services/local/preferences_service.dart';
import 'package:pomodoist/domain/models/focus/focus_models.dart';

final sharedPreferencesProvider = FutureProvider<SharedPreferences?>((
  ref,
) async {
  try {
    return await SharedPreferences.getInstance();
  } on MissingPluginException {
    return null;
  }
});
final focusPreferencesRepositoryProvider = Provider<FocusPreferencesRepository>(
  (ref) {
    final repository = StoredFocusPreferencesRepository(
      PreferencesService(() => ref.read(sharedPreferencesProvider.future)),
    );
    unawaited(repository.load());
    ref.onDispose(repository.dispose);
    return repository;
  },
);
final focusPreferencesStateProvider = Provider<FocusPreferencesState>((ref) {
  final repository = ref.watch(focusPreferencesRepositoryProvider);
  final subscription = repository.watch().listen((_) => ref.invalidateSelf());
  ref.onDispose(subscription.cancel);
  return repository.state;
});
final focusViewModeProvider = Provider(
  (ref) => ref.watch(focusPreferencesStateProvider).viewMode,
);
final focusTimerVisualStyleProvider = Provider(
  (ref) => ref.watch(focusPreferencesStateProvider).timerStyle,
);
final lastFocusPresetIdProvider = Provider(
  (ref) => ref.watch(focusPreferencesStateProvider).lastPresetId,
);
final focusCompletionCelebrationEnabledProvider = Provider(
  (ref) => ref.watch(focusPreferencesStateProvider).celebrationEnabled,
);
final focusCompletionRepositoryProvider = Provider<FocusCompletionRepository>((
  ref,
) {
  final repository = DefaultFocusCompletionRepository();
  ref.onDispose(repository.dispose);
  return repository;
});
final focusCompletionEventProvider = Provider<FocusRunCompletionEvent?>((ref) {
  final repository = ref.watch(focusCompletionRepositoryProvider);
  final subscription = repository.watch().listen((_) => ref.invalidateSelf());
  ref.onDispose(subscription.cancel);
  return repository.state;
});
