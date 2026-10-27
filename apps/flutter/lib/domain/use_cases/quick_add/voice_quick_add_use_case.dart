import 'package:pomodoist/domain/models/planning/task_decomposition.dart';
import 'package:pomodoist/domain/use_cases/quick_add/quick_add_use_case.dart';

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
  }) : _quickAdd = quickAdd,
       _runLocalTransaction = runLocalTransaction;

  final QuickAddUseCase _quickAdd;
  final Future<T> Function<T>(Future<T> Function() action) _runLocalTransaction;

  Future<List<String>> call(
    Iterable<DecomposedTaskDraft> tasks, {
    int? defaultPriority,
    DateTime? defaultDate,
    String? projectId,
    String? kanbanStatusId,
    String? labelId,
  }) async {
    return _runLocalTransaction(
      () => _createAll(
        tasks,
        defaultPriority: defaultPriority,
        defaultDate: defaultDate,
        projectId: projectId,
        kanbanStatusId: kanbanStatusId,
        labelId: labelId,
      ),
    );
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
