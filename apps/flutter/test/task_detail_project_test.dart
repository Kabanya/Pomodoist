import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/focus_dependencies.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/config/calendar_dependencies.dart';
import 'package:pomodoist/config/task_preferences_dependencies.dart';
import 'package:pomodoist/data/repositories/tasks/task_repository.dart';
import 'package:pomodoist/domain/models/settings/task_preferences.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/ui/tasks/view_models/task_detail_view_model.dart';
import 'package:pomodoist/utils/result.dart';

final _now = DateTime.utc(2026, 10, 3);
TaskItem _task({String? scopeId, bool canEdit = true, String? parentId}) =>
    TaskItem(
      id: 'task',
      userId: 'user',
      content: 'Task',
      projectId: 'source',
      sectionId: 'section',
      parentId: parentId,
      scopeId: scopeId,
      canEdit: canEdit,
      priority: 4,
      status: 'open',
      completedFocusIntervals: 0,
      totalFocusSeconds: 0,
      orderKey: 'a',
      isDeleted: false,
      createdAt: _now,
      updatedAt: _now,
    );
ProjectItem _project(
  String id, {
  String? scopeId,
  bool canEdit = true,
  bool archived = false,
  bool deleted = false,
}) => ProjectItem(
  id: id,
  userId: 'user',
  name: id,
  orderKey: id,
  scopeId: scopeId,
  canEdit: canEdit,
  isArchived: archived,
  isDeleted: deleted,
  createdAt: _now,
  updatedAt: _now,
);

class _Tasks implements TaskRepository {
  _Tasks(this.task);
  TaskItem? task;
  bool fail = false;
  final moves =
      <({String id, String? projectId, bool clearSection, bool clearParent})>[];
  @override
  Stream<TaskItem?> watchTask(String id) => Stream.value(task);
  @override
  Future<Result<void>> moveTask(
    String id, {
    String? projectId,
    String? sectionId,
    bool clearSectionId = false,
    String? parentId,
    bool clearParentId = false,
    String? orderKey,
  }) => Result.capture(() async {
    if (fail) throw StateError('offline');
    moves.add((
      id: id,
      projectId: projectId,
      clearSection: clearSectionId,
      clearParent: clearParentId,
    ));
  });
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<ProviderContainer> _container(
  _Tasks tasks,
  List<ProjectItem> projects,
) async {
  final container = ProviderContainer(
    overrides: [
      taskRepositoryProvider.overrideWithValue(tasks),
      taskProvider.overrideWith((ref, id) => tasks.watchTask(id)),
      projectsProvider.overrideWith((ref) => Stream.value(projects)),
      taskDetailFileCountProvider.overrideWith((ref, id) => Stream.value(0)),
      taskPreferencesStateProvider.overrideWithValue(TaskPreferences()),
      focusPresetsProvider.overrideWith((ref) => Stream.value([])),
      activeFocusRunProvider.overrideWith((ref) => Stream.value(null)),
      activeFocusIntervalProvider.overrideWith((ref) => Stream.value(null)),
      lastFocusPresetIdProvider.overrideWithValue(null),
      calendarLinksProvider.overrideWith((ref, id) => Stream.value([])),
      googleCalendarLinkProvider.overrideWith((ref, id) => Stream.value(null)),
    ],
  );
  addTearDown(container.dispose);
  container.listen(taskDetailViewModelProvider('task'), (_, _) {});
  await pumpEventQueue();
  return container;
}

void main() {
  test(
    'project choices exclude archived, deleted, read-only and other scopes',
    () async {
      final container = await _container(_Tasks(_task()), [
        _project('source'),
        _project(inboxProjectId),
        _project('target'),
        _project('archived', archived: true),
        _project('deleted', deleted: true),
        _project('readonly', canEdit: false),
        _project('shared', scopeId: 'scope'),
      ]);
      expect(
        container
            .read(taskDetailViewModelProvider('task'))
            .projects
            .map((p) => p.id),
        ['source', inboxProjectId, 'target'],
      );
    },
  );

  test('changing project clears the old section and external parent', () async {
    final tasks = _Tasks(_task(parentId: 'parent'));
    final container = await _container(tasks, [
      _project('source'),
      _project('target'),
    ]);
    await container
        .read(taskDetailViewModelProvider('task').notifier)
        .setProject('target');
    expect(tasks.moves, [
      (id: 'task', projectId: 'target', clearSection: true, clearParent: true),
    ]);
  });

  test(
    'selecting the current project preserves hierarchy without a move',
    () async {
      final tasks = _Tasks(_task(parentId: 'parent'));
      final container = await _container(tasks, [_project('source')]);
      await container
          .read(taskDetailViewModelProvider('task').notifier)
          .setProject('source');
      expect(tasks.moves, isEmpty);
    },
  );

  test(
    'project change uses the latest task and respects revoked edit permission',
    () async {
      final tasks = _Tasks(_task());
      final container = await _container(tasks, [
        _project('source'),
        _project('target'),
      ]);
      tasks.task = _task(canEdit: false);
      await container
          .read(taskDetailViewModelProvider('task').notifier)
          .setProject('target');
      expect(tasks.moves, isEmpty);
    },
  );

  test('invalid project cannot be selected', () async {
    final tasks = _Tasks(_task());
    final container = await _container(tasks, [
      _project('source'),
      _project('shared', scopeId: 'scope'),
    ]);
    await expectLater(
      container
          .read(taskDetailViewModelProvider('task').notifier)
          .setProject('shared'),
      throwsStateError,
    );
    expect(tasks.moves, isEmpty);
  });

  test('repository failure reaches the caller for error feedback', () async {
    final tasks = _Tasks(_task())..fail = true;
    final container = await _container(tasks, [
      _project('source'),
      _project('target'),
    ]);
    await expectLater(
      container
          .read(taskDetailViewModelProvider('task').notifier)
          .setProject('target'),
      throwsStateError,
    );
  });
}
