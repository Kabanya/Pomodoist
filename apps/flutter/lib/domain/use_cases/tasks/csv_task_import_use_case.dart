import 'package:pomodoist/data/repositories/kanban/kanban_repository.dart';
import 'package:pomodoist/data/repositories/labels/label_repository.dart';
import 'package:pomodoist/data/repositories/projects/project_repository.dart';
import 'package:pomodoist/data/repositories/tasks/task_repository.dart';
import 'package:pomodoist/domain/models/tasks/csv_task_import.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/utils/result.dart';

typedef RunAtomically = Future<T> Function<T>(Future<T> Function() action);

final class CsvTaskImportUseCase {
  CsvTaskImportUseCase({
    required ProjectRepository projects,
    required LabelRepository labels,
    required KanbanRepository kanban,
    required TaskRepository tasks,
    required RunAtomically runAtomically,
    required Future<void> Function() ensureSeedData,
    required String Function() newId,
  }) : _projects = projects,
       _labels = labels,
       _kanban = kanban,
       _tasks = tasks,
       _runAtomically = runAtomically,
       _ensureSeedData = ensureSeedData,
       _newId = newId;

  final ProjectRepository _projects;
  final LabelRepository _labels;
  final KanbanRepository _kanban;
  final TaskRepository _tasks;
  final RunAtomically _runAtomically;
  final Future<void> Function() _ensureSeedData;
  final String Function() _newId;

  Future<Result<CsvTaskImportPreview>> prepare(List<int> bytes) {
    return Result.capture(() async {
      final document = CsvTaskImportDocument.parse(bytes);
      final (currentProjects, currentLabels, board) = await (
        _projects.watchProjects().first,
        _labels.watchLabels().first,
        _kanban.watchBoard().first,
      ).wait;
      return CsvTaskImportPreview(
        document: document,
        newProjects: _missingNames(
          document.tasks.map((task) => task.projectName).whereType<String>(),
          currentProjects.map((project) => project.name),
        ),
        newLabels: _missingNames(
          document.tasks.expand((task) => task.labelNames),
          currentLabels.map((label) => label.name),
        ),
        newKanbanStatuses: _missingNames(
          document.tasks
              .map((task) => task.kanbanStatusName)
              .whereType<String>(),
          board.statuses.map((status) => status.name),
        ),
      );
    });
  }

  Future<Result<CsvTaskImportResult>> commit(CsvTaskImportPreview preview) {
    return Result.capture(() async {
      await _ensureSeedData();
      final (currentProjects, currentLabels, board) = await (
        _projects.watchProjects().first,
        _labels.watchLabels().first,
        _kanban.watchBoard().first,
      ).wait;
      return _runAtomically(() async {
        final projectIds = <String, String>{
          for (final project in currentProjects)
            project.name.toLowerCase(): project.id,
        };
        for (final name in csvUniqueNames(
          preview.document.tasks
              .map((task) => task.projectName)
              .whereType<String>(),
        )) {
          projectIds[name.toLowerCase()] ??= (await _projects.createProject(
            name,
          )).getOrThrow();
        }

        final statusIds = <String, String>{
          for (final status in board.statuses)
            status.name.toLowerCase(): status.id,
        };
        for (final name in csvUniqueNames(
          preview.document.tasks
              .map((task) => task.kanbanStatusName)
              .whereType<String>(),
        )) {
          statusIds[name.toLowerCase()] ??= (await _kanban.createStatus(
            name,
          )).getOrThrow();
        }

        final labelNames = <String, String>{
          for (final label in currentLabels)
            label.name.toLowerCase(): label.name,
        };
        final createdByKey = <String, String>{};
        final createdIds = <String>[];
        for (final draft in preview.document.tasks) {
          var schedule = draft.schedule;
          if (draft.recurrenceUnit != null) {
            schedule = schedule!.withRecurrence(
              TaskRecurrence(
                interval: draft.recurrenceInterval,
                unit: draft.recurrenceUnit!,
                seriesId: _newId(),
              ),
            );
          }
          final statusName = draft.kanbanStatusName;
          final id = (await _tasks.createTask(
            CreateTaskInput(
              content: draft.content,
              description: draft.description,
              projectId: draft.projectName == null
                  ? inboxProjectId
                  : projectIds[draft.projectName!.toLowerCase()],
              parentId: draft.parentKey == null
                  ? null
                  : createdByKey[draft.parentKey],
              priority: draft.priority,
              labelNames: [
                for (final name in draft.labelNames)
                  labelNames.putIfAbsent(name.toLowerCase(), () => name),
              ],
              schedule: schedule,
              deadline: draft.deadline,
              estimatedFocusIntervals: draft.estimatedFocusIntervals,
              kanbanStatusId: statusName == null
                  ? null
                  : statusIds[statusName.toLowerCase()],
            ),
          )).getOrThrow();
          createdIds.add(id);
          if (draft.key != null) createdByKey[draft.key!] = id;
        }
        return CsvTaskImportResult(List.unmodifiable(createdIds));
      });
    });
  }
}

List<String> _missingNames(
  Iterable<String> requested,
  Iterable<String> existing,
) {
  final known = existing.map((name) => name.trim().toLowerCase()).toSet();
  return [
    for (final name in csvUniqueNames(requested))
      if (!known.contains(name.toLowerCase())) name,
  ];
}
