import 'package:pomodoist/data/repositories/projects/project_repository_impl.dart';
import 'dart:io';
import 'package:app_account/app_account.dart';
import 'package:uuid/uuid.dart';
import 'package:pomodoist/data/services/sync/account_sync_engine.dart';
import 'package:pomodoist/ui/tasks/widgets/project_tree_controls.dart';
import 'package:pomodoist/ui/tasks/view_models/timeline_project_layout.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/services/local/outbox_service.dart';
import 'package:pomodoist/data/repositories/tasks/task_repository_impl.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/domain/models/tasks/project_hierarchy.dart';
import 'package:pomodoist/domain/use_cases/tasks/project_list_data.dart';

void main() {
  late AppDatabase db;
  late DriftProjectRepository projects;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.ensureSeedData();
    projects = DriftProjectRepository(db, DriftOutboxService(db));
  });
  tearDown(() => db.close());

  test('cycles and missing parents cannot hide projects', () {
    final rows = projectRows([
      project('a', parentId: 'b'),
      project('b', parentId: 'a'),
      project('orphan', parentId: 'missing'),
      project('self', parentId: 'self'),
    ]);
    expect(rows.map((row) => row.project.id).toSet(), {
      'a',
      'b',
      'orphan',
      'self',
    });
    expect(rows.length, 4);
  });

  test(
    'create and move preserve the branch and reject cycles atomically',
    () async {
      final repository = projects;
      final parent = await projects
          .createProject('Parent')
          .then((result) => result.getOrThrow());
      final String child = await repository
          .createProject('Child', parentId: parent)
          .then((result) => result.getOrThrow());
      final String grandchild = await repository
          .createProject('Grandchild', parentId: child)
          .then((result) => result.getOrThrow());
      await expectLater(
        repository
            .moveProject(parent, parentId: grandchild)
            .then((result) => result.getOrThrow()),
        throwsArgumentError,
      );
      await expectLater(
        repository.createProject('Child').then((result) => result.getOrThrow()),
        throwsArgumentError,
      );
      await expectLater(
        repository
            .moveProject(child, parentId: inboxProjectId)
            .then((result) => result.getOrThrow()),
        throwsArgumentError,
      );
      await expectLater(
        repository
            .moveProject(child, parentId: 'missing')
            .then((result) => result.getOrThrow()),
        throwsArgumentError,
      );
      await repository
          .moveProject(child, parentId: null, beforeProjectId: parent)
          .then((result) => result.getOrThrow());
      final rows = await projects.watchProjects().first;
      expect(rows.singleWhere((p) => p.id == child).parentId, isNull);
      expect(rows.singleWhere((p) => p.id == grandchild).parentId, child);
      expect(
        projectRows(
          rows.where((p) => p.id != inboxProjectId).toList(),
        ).map((row) => row.project.id),
        [child, grandchild, parent],
      );
    },
  );

  test('drop positions resolve against siblings, not visible descendants', () {
    final items = [
      project('a'),
      project('b', parentId: 'a'),
      project('c'),
      project('d'),
    ];
    expect(
      projectDropTarget(items, 'd', 'a', ProjectDropPosition.inside)?.parentId,
      'a',
    );
    final after = projectDropTarget(
      items,
      'd',
      'a',
      ProjectDropPosition.after,
    )!;
    expect(after.parentId, isNull);
    expect(after.beforeProjectId, 'c');
    expect(
      projectDropTarget(items, 'a', 'b', ProjectDropPosition.inside),
      isNull,
    );
    expect(
      projectDropTarget(items, 'a', 'b', ProjectDropPosition.before),
      isNull,
    );
  });

  test('invalid changes leave projects and sync commands unchanged', () async {
    final parent = await projects
        .createProject('Parent')
        .then((result) => result.getOrThrow());
    final child = await projects
        .createProject('Child', parentId: parent)
        .then((result) => result.getOrThrow());
    final archived = await projects
        .createProject('Archived')
        .then((result) => result.getOrThrow());
    await (db.update(db.projects)..where((p) => p.id.equals(archived))).write(
      const ProjectsCompanion(isArchived: Value(true)),
    );
    final deleted = await projects
        .createProject('Deleted')
        .then((result) => result.getOrThrow());
    await projects.deleteProject(deleted).then((result) => result.getOrThrow());
    final before = (await db.select(db.projects).get())
        .map((p) => p.toJson())
        .toList();
    final queued = (await db.select(db.syncCommands).get()).length;
    for (final parentId in [
      child,
      archived,
      deleted,
      inboxProjectId,
      'missing',
    ]) {
      await expectLater(
        projects
            .moveProject(parent, parentId: parentId)
            .then((result) => result.getOrThrow()),
        throwsArgumentError,
      );
    }
    await expectLater(
      projects
          .moveProject(parent, parentId: null, beforeProjectId: child)
          .then((result) => result.getOrThrow()),
      throwsArgumentError,
    );
    await expectLater(
      projects
          .moveProject(archived, parentId: null)
          .then((result) => result.getOrThrow()),
      throwsArgumentError,
    );
    await expectLater(
      projects
          .moveProject(deleted, parentId: null)
          .then((result) => result.getOrThrow()),
      throwsArgumentError,
    );
    await expectLater(
      projects
          .moveProject(inboxProjectId, parentId: null)
          .then((result) => result.getOrThrow()),
      throwsArgumentError,
    );
    await expectLater(
      projects
          .createProject('Invalid', parentId: archived)
          .then((result) => result.getOrThrow()),
      throwsArgumentError,
    );
    await expectLater(
      projects.createProject('  ').then((result) => result.getOrThrow()),
      throwsArgumentError,
    );
    expect(
      (await db.select(db.projects).get()).map((p) => p.toJson()).toList(),
      before,
    );
    expect((await db.select(db.syncCommands).get()).length, queued);
  });

  test(
    'collapsed branches reveal ancestors after a move and cancel leaves order intact',
    () {
      final items = [
        project('a'),
        project('b', parentId: 'a'),
        project('c', parentId: 'b'),
      ];
      final tree = ProjectTreeController();
      addTearDown(tree.dispose);
      tree.toggle('a');
      tree.toggle('b');
      expect(
        projectRows(
          items,
          collapsedIds: tree.collapsedIds,
        ).map((r) => r.project.id),
        ['a'],
      );
      tree.reveal('b', items);
      expect(
        projectRows(
          items,
          collapsedIds: tree.collapsedIds,
        ).map((r) => r.project.id),
        ['a', 'b', 'c'],
      );
      tree.drag('a');
      tree.drag(null);
      expect(tree.draggedId, isNull);
      expect(projectRows(items).map((r) => r.project.id), ['a', 'b', 'c']);
    },
  );

  test('a completed operation can safely outlive its tree screen', () {
    final tree = ProjectTreeController();
    tree.dispose();
    tree.reveal('parent', [project('parent')]);
    tree.drag(null);
  });

  test('deep branches do not depend on recursive traversal', () {
    final items = [
      for (var i = 0; i < 12000; i++)
        project('$i', parentId: i == 0 ? null : '${i - 1}'),
    ];
    final rows = projectRows(items);
    expect(rows.length, 12000);
    expect(rows.last.depth, 11999);
  });

  test('timeline also displays cyclic projects once', () {
    final rows = buildTimelineProjectRows(
      projects: [
        project('a', parentId: 'b'),
        project('b', parentId: 'a'),
      ],
      tasks: [],
      collapsedProjectIds: {},
      temporarilyVisibleProjectIds: {'a'},
    );
    expect(rows.map((r) => r.project.id).toSet(), {'a', 'b'});
    expect(rows.length, 2);
  });

  test(
    'hierarchy and ordering survive sync and reopening local storage',
    () async {
      final warn = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      addTearDown(
        () => driftRuntimeOptions.dontWarnAboutMultipleDatabases = warn,
      );
      final root = await projects
          .createProject('Root')
          .then((result) => result.getOrThrow());
      final child = await projects
          .createProject('Child', parentId: root)
          .then((result) => result.getOrThrow());
      final sibling = await projects
          .createProject('Sibling')
          .then((result) => result.getOrThrow());
      final account = _SyncClient();
      final engine = AccountSyncEngine(
        db: db,
        account: account,
        uuid: const Uuid(),
        localPaidEntitlementLoader: () async => true,
      );
      await engine.pushPending();
      final directory = await Directory.systemTemp.createTemp(
        'project-hierarchy-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/test.sqlite');
      var target = AppDatabase(NativeDatabase(file));
      await target.ensureSeedData();
      await AccountSyncEngine(
        db: target,
        account: account,
        uuid: const Uuid(),
      ).pullLatest();
      expect(
        (await target.select(target.projects).get())
            .singleWhere((p) => p.id == child)
            .parentId,
        root,
      );
      await projects
          .moveProject(child, parentId: null, beforeProjectId: root)
          .then((result) => result.getOrThrow());
      await engine.pushPending();
      await AccountSyncEngine(
        db: target,
        account: account,
        uuid: const Uuid(),
      ).pullLatest();
      await target.close();
      target = AppDatabase(NativeDatabase(file));
      try {
        final remote = DriftProjectRepository(
          target,
          DriftOutboxService(target),
        );
        final rows = await remote.watchProjects().first;
        expect(rows.singleWhere((p) => p.id == child).parentId, isNull);
        expect(
          projectRows(
            rows.where((p) => p.id != inboxProjectId).toList(),
          ).map((r) => r.project.id),
          [child, root, sibling],
        );
      } finally {
        await target.close();
      }
    },
  );

  test('deletion promotes children at the deleted project position', () async {
    final a = await projects
        .createProject('Before')
        .then((result) => result.getOrThrow());
    final parent = await projects
        .createProject('Parent')
        .then((result) => result.getOrThrow());
    final b = await projects
        .createProject('After')
        .then((result) => result.getOrThrow());
    final child = await projects
        .createProject('Child')
        .then((result) => result.getOrThrow());
    final tasks = DriftTaskRepository(db, DriftOutboxService(db));
    final ownTask = await tasks
        .createTask(CreateTaskInput(content: 'Own', projectId: parent))
        .then((result) => result.getOrThrow());
    final childTask = await tasks
        .createTask(CreateTaskInput(content: 'Nested', projectId: child))
        .then((result) => result.getOrThrow());
    await (db.update(db.projects)..where((row) => row.id.equals(child))).write(
      ProjectsCompanion(parentId: Value(parent)),
    );
    await projects.deleteProject(parent).then((result) => result.getOrThrow());
    expect((await tasks.watchTask(ownTask).first)!.projectId, inboxProjectId);
    expect((await tasks.watchTask(childTask).first)!.projectId, child);
    final rows = await projects.watchProjects().first;
    expect(rows.singleWhere((row) => row.id == child).parentId, isNull);
    expect(
      projectRows(
        rows.where((p) => p.id != inboxProjectId).toList(),
      ).map((row) => row.project.id),
      [a, child, b],
    );
  });
}

ProjectItem project(String id, {String? parentId}) => ProjectItem(
  id: id,
  userId: localUserId,
  name: id,
  parentId: parentId,
  orderKey: id,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

class _SyncClient implements AccountClient {
  final changes = <AccountSyncEntity>[];
  @override
  Future<AccountSyncPushResult> pushChanges({
    required String appId,
    required String deviceId,
    required List<AccountSyncOperation> operations,
  }) async {
    for (final op in operations) {
      changes.add(
        AccountSyncEntity(
          entityType: op.entityType,
          entityId: op.entityId,
          serverRevision: changes.length + 1,
          data: op.payload,
          updatedAt: op.clientUpdatedAt,
          deletedAt: op.operation == 'delete' ? op.clientUpdatedAt : null,
        ),
      );
    }
    return AccountSyncPushResult(
      serverRevision: changes.length,
      applied: const [],
    );
  }

  @override
  Future<AccountSyncPullResult> pullChanges({
    required String appId,
    required String deviceId,
    required int sinceRevision,
    int limit = 500,
  }) async => AccountSyncPullResult(
    nextCursor: changes.length,
    hasMore: false,
    changes: changes.where((c) => c.serverRevision > sinceRevision).toList(),
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
