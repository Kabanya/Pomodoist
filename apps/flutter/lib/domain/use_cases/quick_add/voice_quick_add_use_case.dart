import 'package:pomodoist/domain/models/planning/task_decomposition.dart';
import 'package:pomodoist/domain/use_cases/quick_add/quick_add_use_case.dart';
import 'package:pomodoist/data/repositories/planning/quick_add_hint_repository.dart';

/// Creates every voice draft and its subtasks in one local transaction.
///
/// Dependencies are injected through the constructor; the transaction runner
/// matches the data-layer `RunLocalTransaction` contract structurally, so no
/// database handle reaches domain code. The callback awaits all writes and
/// rethrows inner failures.
class VoiceQuickAddUseCase {
  const VoiceQuickAddUseCase({
    required QuickAddUseCase quickAdd,
    required Future<T> Function<T>(Future<T> Function() action)
    runLocalTransaction,
    QuickAddHintRepository? hints,
  }) : _quickAdd = quickAdd,
       _runLocalTransaction = runLocalTransaction,
       _hints = hints;

  final QuickAddUseCase _quickAdd;
  final Future<T> Function<T>(Future<T> Function() action) _runLocalTransaction;
  final QuickAddHintRepository? _hints;

  Future<List<String>> call(
    Iterable<DecomposedTaskDraft> tasks, {
    int? defaultPriority,
    DateTime? defaultDate,
    String? projectId,
    String? kanbanStatusId,
    String? labelId,
  }) async {
    final created = await _runLocalTransaction(
      () => _createAll(
        tasks,
        defaultPriority: defaultPriority,
        defaultDate: defaultDate,
        projectId: projectId,
        kanbanStatusId: kanbanStatusId,
        labelId: labelId,
      ),
    );
    try {
      for (var index = 0; index < created.length; index++) {
        await _hints?.recordUserTaskCreated();
      }
    } catch (_) {
      // Hint bookkeeping is advisory and cannot fail a committed batch.
    }
    return created;
  }

  Future<List<String>> _createAll(
    Iterable<DecomposedTaskDraft> drafts, {
    int? defaultPriority,
    DateTime? defaultDate,
    String? projectId,
    String? kanbanStatusId,
    String? labelId,
    String? parentId,
    String? sectionId,
  }) async {
    final createdIds = <String>[];
    for (final draft in drafts) {
      final input = draft.quickAdd.trim();
      if (input.isEmpty) {
        continue;
      }
      final task = await _quickAdd
          .createTaskWithContext(
            input,
            description: draft.description,
            parentId: parentId,
            projectId: projectId,
            sectionId: sectionId,
            priority: defaultPriority,
            defaultDate: defaultDate,
            kanbanStatusId: kanbanStatusId,
            labelId: labelId,
            recordCreation: false,
          )
          .then((result) => result.getOrThrow());
      createdIds.add(task.id);
      createdIds.addAll(
        await _createAll(
          draft.subtasks,
          defaultPriority: defaultPriority,
          defaultDate: defaultDate,
          parentId: task.id,
          projectId: task.projectId ?? projectId,
          sectionId: task.sectionId ?? sectionId,
          kanbanStatusId: kanbanStatusId,
          labelId: labelId,
        ),
      );
    }
    return createdIds;
  }
}
