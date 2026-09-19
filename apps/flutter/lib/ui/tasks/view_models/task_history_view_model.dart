import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/config/collaboration_dependencies.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/domain/models/focus/focus_models.dart';
import 'package:pomodoist/domain/models/collaboration/collaboration_models.dart';

class TaskFocusHistoryEntry {
  const TaskFocusHistoryEntry({
    required this.key,
    required this.type,
    required this.status,
    required this.startedAt,
    required this.seconds,
    this.authorId,
  });
  final String key, type, status;
  final DateTime startedAt;
  final int seconds;
  final String? authorId;
}

typedef TaskHistoryState = ({
  SharedScope? scope,
  List<TaskFocusHistoryEntry> entries,
});
final _localTaskIntervalsProvider = StreamProvider.autoDispose
    .family<List<FocusIntervalItem>, String>(
      (ref, id) => ref.watch(focusRepositoryProvider).watchIntervalsForTask(id),
    );
final taskHistoryViewModelProvider = NotifierProvider.autoDispose
    .family<TaskHistoryViewModel, TaskHistoryState, TaskItem>(
      TaskHistoryViewModel.new,
    );

class TaskHistoryViewModel extends Notifier<TaskHistoryState> {
  TaskHistoryViewModel(this.task);
  final TaskItem task;
  @override
  TaskHistoryState build() {
    final scopeId = task.scopeId;
    final scope = scopeId == null
        ? null
        : ref.watch(sharedScopeProvider(scopeId));
    final contributions = scopeId == null
        ? const <Map<String, dynamic>>[]
        : ref
                  .watch(
                    collaborationEntitiesProvider((
                      scopeId: scopeId,
                      type: 'focus_interval',
                      taskId: task.id,
                    )),
                  )
                  .value ??
              const <Map<String, dynamic>>[];
    final local =
        ref.watch(_localTaskIntervalsProvider(task.id)).value ??
        const <FocusIntervalItem>[];
    final localIds = {for (final interval in local) interval.id};
    final entries = <TaskFocusHistoryEntry>[
      for (final interval in local)
        TaskFocusHistoryEntry(
          key: 'focus-history-interval-${interval.id}',
          type: interval.type,
          status: interval.status,
          startedAt: interval.startedAt,
          seconds: interval.plannedSeconds,
        ),
      for (final contribution in contributions)
        if (!localIds.contains(contribution['id'])) ?_sharedEntry(contribution),
    ]..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return (
      scope: scope,
      entries: List<TaskFocusHistoryEntry>.unmodifiable(entries.take(20)),
    );
  }
}

TaskFocusHistoryEntry? _sharedEntry(Map<String, dynamic> contribution) {
  final startedAt = switch (contribution['startedAt']) {
    final String text => DateTime.tryParse(text)?.toUtc(),
    final num milliseconds => DateTime.fromMillisecondsSinceEpoch(
      milliseconds.toInt(),
      isUtc: true,
    ),
    _ => null,
  };
  if (startedAt == null) return null;
  return TaskFocusHistoryEntry(
    key: 'focus-history-shared-${contribution['id']}',
    type: contribution['type'] as String? ?? 'work',
    status: contribution['status'] as String? ?? 'completed',
    startedAt: startedAt,
    authorId:
        (contribution['createdBy'] ?? contribution['userId'])?.toString() ?? '',
    seconds:
        (contribution['durationSeconds'] as num?)?.toInt() ??
        (contribution['plannedSeconds'] as num?)?.toInt() ??
        0,
  );
}
