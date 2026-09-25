import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/data/repositories/focus/focus_repository.dart';
import 'package:pomodoist/config/focus_dependencies.dart';
import 'package:pomodoist/domain/models/focus/focus_models.dart';
import 'package:pomodoist/domain/models/focus/focus_view_mode.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';

class FocusState {
  const FocusState({
    required this.run,
    required this.interval,
    required this.presets,
    required this.intervals,
    required this.remaining,
    required this.viewMode,
    required this.timerVisualStyle,
    required this.sessionDisplay,
    required this.effectivePreset,
    required this.activePreset,
    required this.loading,
    required this.loadError,
  });
  final FocusRunItem? run;
  final FocusIntervalItem? interval;
  final List<FocusPresetItem> presets;
  final List<FocusIntervalItem> intervals;
  final Duration? remaining;
  final FocusViewMode viewMode;
  final FocusTimerVisualStyle timerVisualStyle;
  final FocusSessionDisplay sessionDisplay;
  final FocusPresetItem? effectivePreset;
  final FocusPresetItem? activePreset;
  final bool loading;
  final Object? loadError;
}

final focusViewModelProvider =
    NotifierProvider.autoDispose<FocusViewModel, FocusState>(
      FocusViewModel.new,
    );

class FocusViewModel extends Notifier<FocusState> {
  late FocusRepository _repository;
  String? _selectedPresetId;
  String? _activePresetOverrideRunId;
  String? _activePresetOverridePresetId;
  @override
  FocusState build() {
    _repository = ref.watch(focusRepositoryProvider);
    final runValue = ref.watch(activeFocusRunProvider);
    final intervalValue = ref.watch(activeFocusIntervalProvider);
    final presetsValue = ref.watch(focusPresetsProvider);
    final remaining = ref.watch(activeFocusRemainingProvider);
    final FocusViewMode viewMode = ref.watch(focusViewModeProvider);
    final timerVisualStyle = ref.watch(focusTimerVisualStyleProvider);
    final lastPresetId = ref.watch(lastFocusPresetIdProvider);
    final runForIntervals = runValue.value;
    final intervalsValue = runForIntervals == null
        ? null
        : ref.watch(focusIntervalsForRunProvider(runForIntervals.id));
    final loadError = presetsValue.hasError
        ? presetsValue.error
        : runValue.hasError
        ? runValue.error
        : intervalValue.hasError
        ? intervalValue.error
        : intervalsValue?.hasError ?? false
        ? intervalsValue?.error
        : null;
    final loading =
        presetsValue.isLoading ||
        runValue.isLoading ||
        intervalValue.isLoading ||
        (intervalsValue?.isLoading ?? false);

    final run = runValue.value;
    final interval = intervalValue.value;
    final presets = presetsValue.value ?? const [];
    final intervals = _mergeActiveInterval(
      run: run,
      activeInterval: interval,
      history: intervalsValue?.value ?? const <FocusIntervalItem>[],
    );
    final selectedPreset = _findPreset(
      presets,
      run?.presetId ?? _selectedPresetId ?? lastPresetId,
    );
    final effectivePreset = selectedPreset ?? _defaultPreset(presets);
    final activePreset = run == null
        ? null
        : _findPreset(presets, _activePresetId(run)) ?? _defaultPreset(presets);

    return FocusState(
      run: run,
      interval: interval,
      presets: List.unmodifiable(presets),
      intervals: List.unmodifiable(intervals),
      remaining: remaining,
      viewMode: viewMode,
      timerVisualStyle: timerVisualStyle,
      sessionDisplay: ref.watch(focusPreferencesStateProvider).sessionDisplay,
      effectivePreset: effectivePreset,
      activePreset: activePreset,
      loading: loading,
      loadError: loadError,
    );
  }

  Future<String> createPreset(CreateFocusPresetInput input) async =>
      (await _repository.createPreset(input)).getOrThrow();
  Future<void> updatePreset(String id, UpdateFocusPresetInput input) async =>
      (await _repository.updatePreset(id, input)).getOrThrow();
  Future<void> deletePreset(String id) async {
    (await _repository.deletePreset(id)).getOrThrow();
    if (!ref.mounted) return;
    if (_selectedPresetId == id) _selectedPresetId = null;
    if (ref.read(lastFocusPresetIdProvider) == id) {
      await _rememberPresetBestEffort(null);
    }
    if (ref.mounted) ref.invalidateSelf();
  }

  Future<void> setDefaultPreset(String id) async =>
      (await _repository.setDefaultPreset(id)).getOrThrow();
  Future<void> startFocus(FocusPresetItem preset) async {
    (await _repository.startRun(
      StartFocusRunInput(presetId: preset.id),
    )).getOrThrow();
    await _rememberPresetBestEffort(preset.id);
  }

  Future<void> selectPreset(String id) async {
    (await ref.read(focusPreferencesRepositoryProvider).setPresetId(id))
        .getOrThrow();
    if (!ref.mounted) return;
    _selectedPresetId = id;
    state = _withSelection(
      effectivePreset: _findPreset(state.presets, id),
      activePreset: state.activePreset,
    );
  }

  Future<void> setViewMode(FocusViewMode mode) async =>
      (await ref.read(focusPreferencesRepositoryProvider).setViewMode(mode))
          .getOrThrow();
  Future<void> setSessionDisplay(FocusSessionDisplay value) async =>
      (await ref
              .read(focusPreferencesRepositoryProvider)
              .setSessionDisplay(value))
          .getOrThrow();

  Future<void> changeActiveRunPreset(FocusRunItem run, String presetId) async {
    (await _repository.changeActiveRunPreset(presetId)).getOrThrow();
    if (!ref.mounted) return;
    _activePresetOverrideRunId = run.id;
    _activePresetOverridePresetId = presetId;
    await _rememberPresetBestEffort(presetId);
    state = _withSelection(
      effectivePreset: state.effectivePreset,
      activePreset: _findPreset(state.presets, presetId),
    );
  }

  Future<void> _rememberPresetBestEffort(String? id) async {
    try {
      (await ref.read(focusPreferencesRepositoryProvider).setPresetId(id))
          .getOrThrow();
    } catch (_) {
      // The Focus mutation is committed; remembering the next default is
      // advisory and must not report the completed action as failed.
    }
  }

  Future<void> startReadyInterval() async =>
      (await _repository.startReadyInterval()).getOrThrow();
  Future<void> pauseActiveInterval() async =>
      (await _repository.pauseActiveInterval()).getOrThrow();
  Future<void> resumeActiveInterval() async =>
      (await _repository.resumeActiveInterval()).getOrThrow();
  Future<void> completeActiveInterval() async =>
      (await _repository.completeActiveInterval()).getOrThrow();
  Future<void> skipActiveInterval() async =>
      (await _repository.skipActiveInterval()).getOrThrow();
  Future<void> stopActiveRun({required StopFocusReason reason}) async =>
      (await _repository.stopActiveRun(reason: reason)).getOrThrow();
  FocusPresetItem? _findPreset(List<FocusPresetItem> presets, String? id) {
    if (id == null) {
      return null;
    }
    for (final preset in presets) {
      if (preset.id == id) {
        return preset;
      }
    }
    return null;
  }

  FocusPresetItem? _defaultPreset(List<FocusPresetItem> presets) {
    for (final preset in presets) {
      if (preset.isDefault) {
        return preset;
      }
    }
    return presets.isEmpty ? null : presets.first;
  }

  String _activePresetId(FocusRunItem run) {
    final overrideId = _activePresetOverridePresetId;
    if (_activePresetOverrideRunId == run.id &&
        overrideId != null &&
        overrideId != run.presetId) {
      return overrideId;
    }
    return run.presetId;
  }

  FocusState _withSelection({
    required FocusPresetItem? effectivePreset,
    required FocusPresetItem? activePreset,
  }) => FocusState(
    run: state.run,
    interval: state.interval,
    presets: state.presets,
    intervals: state.intervals,
    remaining: state.remaining,
    viewMode: state.viewMode,
    timerVisualStyle: state.timerVisualStyle,
    sessionDisplay: state.sessionDisplay,
    effectivePreset: effectivePreset,
    activePreset: activePreset,
    loading: state.loading,
    loadError: state.loadError,
  );
}

List<FocusIntervalItem> _mergeActiveInterval({
  required FocusRunItem? run,
  required FocusIntervalItem? activeInterval,
  required List<FocusIntervalItem> history,
}) {
  if (run == null || activeInterval == null || activeInterval.runId != run.id) {
    return history;
  }
  return [
    for (final interval in history)
      if (interval.id != activeInterval.id &&
          (interval.runId != activeInterval.runId ||
              interval.sequenceNumber != activeInterval.sequenceNumber))
        interval,
    activeInterval,
  ];
}

class FocusLinkedTaskState {
  const FocusLinkedTaskState(this.task, this.project);
  final TaskItem? task;
  final ProjectItem? project;
}

final focusLinkedTaskViewModelProvider = NotifierProvider.autoDispose
    .family<FocusLinkedTaskViewModel, FocusLinkedTaskState, (String, String?)>(
      FocusLinkedTaskViewModel.new,
    );

class FocusLinkedTaskViewModel extends Notifier<FocusLinkedTaskState> {
  FocusLinkedTaskViewModel(this.ids);
  final (String, String?) ids;
  @override
  FocusLinkedTaskState build() {
    final task = ref.watch(taskProvider(ids.$1)).value;
    final projects = ref.watch(projectsProvider).value ?? const <ProjectItem>[];
    final projectId = ids.$2 ?? task?.projectId;
    final project = projects
        .where((item) => item.id == projectId && !item.isDeleted)
        .firstOrNull;
    return FocusLinkedTaskState(task, project);
  }
}
