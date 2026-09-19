import 'package:pomodoist/domain/models/planning/task_decomposition.dart';
import 'package:pomodoist/domain/use_cases/quick_add/quick_add_use_case.dart';

Future<List<String>> createVoiceQuickAddTasks(
  QuickAddUseCase quickAdd,
  Iterable<DecomposedTaskDraft> tasks, {
  int? defaultPriority,
  DateTime? defaultDate,
  String? projectId,
  String? kanbanStatusId,
  String? labelId,
}) async {
  Future<List<String>> createAll(
    Iterable<DecomposedTaskDraft> drafts, {
    String? parentId,
    String? projectId,
    String? sectionId,
  }) async {
    final createdIds = <String>[];
    for (final draft in drafts) {
      final input = draft.quickAdd.trim();
      if (input.isEmpty) {
        continue;
      }
      final task = await quickAdd
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
        await createAll(
          draft.subtasks,
          parentId: task.id,
          projectId: task.projectId ?? projectId,
          sectionId: task.sectionId ?? sectionId,
        ),
      );
    }
    return createdIds;
  }

  return createAll(tasks, projectId: projectId);
}
