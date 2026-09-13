import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../focus/domain/focus_models.dart';
import '../domain/task_focus_estimate.dart';
import '../domain/task_models.dart';

final taskFocusLauncherProvider = Provider(
  (ref) => TaskFocusLauncher(ref.watch(focusRepositoryProvider)),
);

/// One shared guard because all task rows control the same Focus session.
class TaskFocusLauncher {
  TaskFocusLauncher(this.repository);

  final FocusRepository repository;
  bool _starting = false;

  Future<bool> open(
    TaskItem task, {
    required FocusPresetItem? preset,
    required Future<bool> Function() confirmSwitch,
  }) async {
    if (_starting || task.isCompleted || task.isDeleted) return false;
    _starting = true;
    try {
      var active = await repository.watchActiveRun().first;
      while (active != null && active.taskId != task.id) {
        if (!await confirmSwitch()) return false;
        final latest = await repository.watchActiveRun().first;
        if (latest?.id == active.id) break;
        // A different session appeared while the confirmation was open.
        active = latest;
      }
      if (active?.taskId == task.id) return true;
      final estimate = targetFocusIntervalsForTask(task, preset);
      await repository.startRun(
        StartFocusRunInput(
          taskId: task.id,
          projectId: task.projectId,
          presetId: preset?.id,
          targetWorkIntervals: estimate == null
              ? null
              : estimate < 1
              ? 1
              : estimate,
        ),
      );
      return true;
    } finally {
      _starting = false;
    }
  }
}
