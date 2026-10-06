import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/focus_dependencies.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/data/repositories/focus/focus_preferences_repository.dart';
import 'package:pomodoist/data/repositories/focus/focus_preferences_repository_impl.dart';
import 'package:pomodoist/data/repositories/focus/focus_repository.dart';
import 'package:pomodoist/data/services/local/preferences_service.dart';
import 'package:pomodoist/domain/models/focus/focus_models.dart';
import 'package:pomodoist/domain/models/focus/focus_view_mode.dart';
import 'package:pomodoist/ui/focus/view_models/focus_view_model.dart';
import 'package:pomodoist/utils/result.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(
    () => SharedPreferences.setMockInitialValues({
      focusTimerVisualStylePreferenceKey: 'bar',
      focusSessionDisplayPreferenceKey: 'icons',
      lastFocusPresetIdPreferenceKey: 'selected',
    }),
  );

  test(
    'shortcut toggles and persists modes without changing the timer',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final repository = StoredFocusPreferencesRepository(
        PreferencesService(() async => preferences),
      );
      addTearDown(repository.dispose);
      (await repository.load()).getOrThrow();
      final container = _container(repository);
      addTearDown(container.dispose);
      final subscription = container.listen(focusViewModelProvider, (_, _) {});
      addTearDown(subscription.close);
      await container.read(activeFocusRunProvider.future);
      await container.read(activeFocusIntervalProvider.future);
      await container.pump();
      final before = container.read(focusViewModelProvider);
      final viewModel = container.read(focusViewModelProvider.notifier);

      await viewModel.toggleViewMode();
      await container.pump();
      expect(
        container.read(focusViewModelProvider).viewMode,
        FocusViewMode.full,
      );
      expect(preferences.getString(focusViewModePreferenceKey), 'full');
      await viewModel.toggleViewMode();
      await container.pump();
      final after = container.read(focusViewModelProvider);
      expect(after.viewMode, FocusViewMode.minimal);
      expect(preferences.getString(focusViewModePreferenceKey), 'minimal');
      expect(after.run, same(before.run));
      expect(after.interval, same(before.interval));
      expect(after.remaining, const Duration(minutes: 12));
      expect(after.timerVisualStyle, FocusTimerVisualStyle.bar);
      expect(after.sessionDisplay, FocusSessionDisplay.icons);
      expect(repository.state.lastPresetId, 'selected');
    },
  );

  test(
    'overlapping shortcuts are ignored and failure allows a retry',
    () async {
      final preferences = _DelayedPreferences();
      final repository = StoredFocusPreferencesRepository(preferences);
      addTearDown(repository.dispose);
      final container = _container(repository);
      addTearDown(container.dispose);
      final subscription = container.listen(focusViewModelProvider, (_, _) {});
      addTearDown(subscription.close);
      final viewModel = container.read(focusViewModelProvider.notifier);
      final first = viewModel.toggleViewMode();
      final failure = expectLater(first, throwsStateError);
      await viewModel.toggleViewMode();
      expect(preferences.writes, 1);
      preferences.pending.complete(
        Failure(StateError('disk failure'), StackTrace.current),
      );
      await failure;
      expect(repository.state.viewMode, FocusViewMode.minimal);

      preferences.pending = Completer<Result<void>>();
      final retry = viewModel.toggleViewMode();
      expect(preferences.writes, 2);
      preferences.pending.complete(const Success(null));
      await retry;
      expect(repository.state.viewMode, FocusViewMode.full);
    },
  );
}

ProviderContainer _container(FocusPreferencesRepository preferences) =>
    ProviderContainer(
      overrides: [
        focusPreferencesRepositoryProvider.overrideWithValue(preferences),
        focusRepositoryProvider.overrideWithValue(_FocusRepository()),
        activeFocusRemainingProvider.overrideWithValue(
          const Duration(minutes: 12),
        ),
      ],
    );

class _DelayedPreferences extends PreferencesService {
  _DelayedPreferences() : super(() async => null);
  Completer<Result<void>> pending = Completer<Result<void>>();
  int writes = 0;
  @override
  Future<Result<void>> write(Map<String, Object?> values) {
    writes++;
    return pending.future;
  }
}

class _FocusRepository implements FocusRepository {
  final now = DateTime.utc(2026, 10, 6);
  late final run = FocusRunItem(
    id: 'run',
    userId: 'local',
    presetId: 'selected',
    status: 'active',
    startedAt: now,
    targetWorkIntervals: 4,
    completedWorkIntervals: 1,
    createdAt: now,
    updatedAt: now,
  );
  late final interval = FocusIntervalItem(
    id: 'interval',
    runId: 'run',
    type: 'work',
    status: 'paused',
    plannedSeconds: 1500,
    startedAt: now,
    pausedAt: now,
    pausedTotalSeconds: 0,
    sequenceNumber: 1,
    createdAt: now,
    updatedAt: now,
  );
  @override
  Stream<List<FocusPresetItem>> watchPresets() => Stream.value(const []);
  @override
  Stream<FocusRunItem?> watchActiveRun() => Stream.value(run);
  @override
  Stream<FocusIntervalItem?> watchActiveInterval() => Stream.value(interval);
  @override
  Stream<List<FocusIntervalItem>> watchIntervalsForRun(String runId) =>
      Stream.value([interval]);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
