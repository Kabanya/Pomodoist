import 'quick_add_service.dart';
import 'task_decomposer.dart';

Future<List<String>> createVoiceQuickAddTasks(
  QuickAddService quickAdd,
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
      final task = await quickAdd.createTaskWithContext(
        input,
        description: draft.description,
        parentId: parentId,
        projectId: projectId,
        sectionId: sectionId,
        priority: defaultPriority,
        defaultDate: defaultDate,
        kanbanStatusId: kanbanStatusId,
        labelId: labelId,
      );
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
