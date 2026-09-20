import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/domain/models/tasks/project_hierarchy.dart';
import 'package:pomodoist/ui/tasks/view_models/projects_view_model.dart';

void main() {
  test('drag targets use current projects and reject invalid moves', () async {
    final source = StreamController<List<ProjectItem>>();
    final container = ProviderContainer(
      overrides: [projectsProvider.overrideWith((ref) => source.stream)],
    );
    addTearDown(source.close);
    addTearDown(container.dispose);
    final subscription = container.listen(
      projectTreeViewModelProvider,
      (_, _) {},
    );
    addTearDown(subscription.close);
    final model = container.read(projectTreeViewModelProvider.notifier);
    expect(
      model.dropTarget('moving', 'root', ProjectDropPosition.inside),
      isNull,
    );
    source.add([
      project('root'),
      project('moving'),
      project('child', parentId: 'moving'),
      project('sibling', parentId: 'root'),
    ]);
    await pumpEventQueue();
    expect(
      model.dropTarget('moving', 'root', ProjectDropPosition.inside)?.parentId,
      'root',
    );
    final before = model.dropTarget(
      'moving',
      'sibling',
      ProjectDropPosition.before,
    )!;
    expect((before.parentId, before.beforeProjectId), ('root', 'sibling'));
    final after = model.dropTarget(
      'moving',
      'sibling',
      ProjectDropPosition.after,
    )!;
    expect((after.parentId, after.beforeProjectId), ('root', null));
    expect(
      model.dropTarget('moving', 'child', ProjectDropPosition.inside),
      isNull,
    );
    expect(
      model.dropTarget('moving', 'moving', ProjectDropPosition.inside),
      isNull,
    );
    source.add([project('moving'), project('root', archived: true)]);
    await pumpEventQueue();
    expect(
      model.dropTarget('moving', 'root', ProjectDropPosition.inside),
      isNull,
    );
  });

  test(
    'move targets exclude invalid branches and follow live project changes',
    () async {
      final source = StreamController<List<ProjectItem>>();
      final container = ProviderContainer(
        overrides: [projectsProvider.overrideWith((ref) => source.stream)],
      );
      addTearDown(source.close);
      addTearDown(container.dispose);
      final provider = projectMoveTargetsProvider('moving');
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      expect(container.read(provider).isLoading, isTrue);

      source.add([
        project(inboxProjectId),
        project('root'),
        project('moving', parentId: 'root'),
        project('descendant', parentId: 'moving'),
        project('sibling', parentId: 'root'),
        project('free'),
        project('archived', archived: true),
        project('archived-child', parentId: 'archived'),
        project('deleted', deleted: true),
        project('deleted-child', parentId: 'deleted'),
        project('orphan', parentId: 'missing'),
        project('cycle-a', parentId: 'cycle-b'),
        project('cycle-b', parentId: 'cycle-a'),
      ]);
      await pumpEventQueue();
      final rows = container.read(provider).requireValue;
      expect(rows.map((row) => (row.project.id, row.depth)), [
        ('root', 0),
        ('sibling', 1),
        ('free', 0),
      ]);
      expect(() => rows.clear(), throwsUnsupportedError);

      source.add([project('moving'), project('free', archived: true)]);
      await pumpEventQueue();
      expect(container.read(provider).requireValue, isEmpty);

      final failure = StateError('projects unavailable');
      source.addError(failure);
      await pumpEventQueue();
      expect(container.read(provider).error, same(failure));
    },
  );
}

ProjectItem project(
  String id, {
  String? parentId,
  bool archived = false,
  bool deleted = false,
}) => ProjectItem(
  id: id,
  userId: 'user',
  name: id,
  orderKey: id,
  parentId: parentId,
  isArchived: archived,
  isDeleted: deleted,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);
