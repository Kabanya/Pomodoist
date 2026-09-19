import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/focus_dependencies.dart';
import 'package:pomodoist/data/services/local/preferences_service.dart';
import 'package:pomodoist/data/repositories/settings/preferences_repository.dart';
import 'package:pomodoist/data/repositories/settings/task_preferences_repository.dart';
import 'package:pomodoist/data/repositories/settings/task_preferences_repository_impl.dart';
import 'package:pomodoist/domain/models/settings/task_preferences.dart';

final preferencesServiceProvider = Provider<PreferencesService>(
  (ref) => PreferencesService(() => ref.read(sharedPreferencesProvider.future)),
);
final preferencesRepositoryProvider = Provider<PreferencesRepository>(
  (ref) => PreferencesRepository(ref.watch(preferencesServiceProvider)),
);
final taskPreferencesRepositoryProvider = Provider<TaskPreferencesRepository>((
  ref,
) {
  final repository = LocalTaskPreferencesRepository(
    ref.watch(preferencesServiceProvider),
  );
  unawaited(repository.load());
  ref.onDispose(repository.dispose);
  return repository;
});
final taskPreferencesStateProvider = Provider<TaskPreferences>((ref) {
  final repository = ref.watch(taskPreferencesRepositoryProvider);
  repository.addListener(ref.invalidateSelf);
  ref.onDispose(() => repository.removeListener(ref.invalidateSelf));
  return repository.state;
});
final reengagementNotificationsEnabledProvider = Provider(
  (ref) => ref.watch(taskPreferencesStateProvider).reengagementEnabled,
);
final quickAddDefaultTimedBlockMinutesProvider = Provider(
  (ref) => ref.watch(taskPreferencesStateProvider).quickAddMinutes,
);
final taskTimeDisplayModeProvider = Provider(
  (ref) => ref.watch(taskPreferencesStateProvider).timeDisplayMode,
);
final taskListStyleProvider = Provider(
  (ref) => ref.watch(taskPreferencesStateProvider).listStyle,
);
final taskRowSpacingProvider = Provider(
  (ref) => ref.watch(taskPreferencesStateProvider).rowSpacing,
);
final timelineVisibleHoursProvider = Provider(
  (ref) => ref.watch(taskPreferencesStateProvider).visibleHours,
);
final timelineHourWidthProvider = Provider(
  (ref) => ref.watch(taskPreferencesStateProvider).hourWidth,
);
final timelineCollapsedProjectIdsProvider = Provider(
  (ref) => ref.watch(taskPreferencesStateProvider).collapsedProjectIds,
);
