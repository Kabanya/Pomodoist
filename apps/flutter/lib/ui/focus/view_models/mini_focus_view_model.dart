import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/focus_dependencies.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/domain/models/focus/focus_models.dart';
import 'package:pomodoist/domain/models/focus/focus_view_mode.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';

final class MiniFocusState {
  const MiniFocusState({
    this.interval,
    this.run,
    this.remaining,
    this.preset,
    this.task,
    this.viewMode = FocusViewMode.full,
  });

  final FocusIntervalItem? interval;
  final FocusRunItem? run;
  final Duration? remaining;
  final FocusPresetItem? preset;
  final TaskItem? task;
  final FocusViewMode viewMode;

  bool get visible =>
      interval != null &&
      run != null &&
      remaining != null &&
      interval!.runId == run!.id;
}

final miniFocusViewModelProvider =
    NotifierProvider.autoDispose<MiniFocusViewModel, MiniFocusState>(
      MiniFocusViewModel.new,
    );

class MiniFocusViewModel extends Notifier<MiniFocusState> {
  var _busy = false;

  @override
  MiniFocusState build() {
    final interval = ref.watch(activeFocusIntervalProvider).value;
    final run = ref.watch(activeFocusRunProvider).value;
    final presets = ref.watch(focusPresetsProvider).value ?? const [];
    FocusPresetItem? preset;
    for (final item in presets) {
      if (item.id == run?.presetId) {
        preset = item;
        break;
      }
    }
    final task = run?.taskId == null
        ? null
        : ref.watch(taskProvider(run!.taskId!)).value;
    return MiniFocusState(
      interval: interval,
      run: run,
      remaining: ref.watch(activeFocusRemainingProvider),
      preset: preset,
      task: task,
      viewMode: ref.watch(focusViewModeProvider),
    );
  }

  Future<void> start() => _run(
    () async => (await ref.read(focusRepositoryProvider).startReadyInterval())
        .getOrThrow(),
  );

  Future<void> togglePause() => _run(() async {
    final paused = state.interval?.status == 'paused';
    final result = paused
        ? await ref.read(focusRepositoryProvider).resumeActiveInterval()
        : await ref.read(focusRepositoryProvider).pauseActiveInterval();
    result.getOrThrow();
  });

  Future<void> stop() => _run(
    () async =>
        (await ref
                .read(focusRepositoryProvider)
                .stopActiveRun(reason: StopFocusReason.stopped))
            .getOrThrow(),
  );

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    _busy = true;
    try {
      await action();
    } finally {
      _busy = false;
    }
  }
}
