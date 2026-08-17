import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'database_directory.dart';

part 'app_database.g.dart';

const localUserId = 'local-user';
const localWorkspaceId = 'local-workspace';
const inboxProjectId = 'inbox';
const defaultPresetId = 'classic';
const deepWorkPresetId = 'deep-work';
const shortSprintPresetId = 'short-sprint';
const flowPresetId = 'flow';
const kanbanSettingsPrimaryId = 'kanban-settings-primary-v1';
const kanbanStatusBacklogId = 'kanban-status-backlog-v1';
const kanbanStatusTodoId = 'kanban-status-todo-v1';
const kanbanStatusInProgressId = 'kanban-status-in-progress-v1';
const kanbanStatusDoneId = 'kanban-status-done-v1';
const labelKindUser = 'user';
const labelKindKanbanStatus = 'kanbanStatus';
const kanbanSystemKeyBacklog = 'backlog';
const kanbanSystemKeyTodo = 'todo';
const kanbanSystemKeyInProgress = 'inProgress';
const kanbanSystemKeyDone = 'done';

const _kanbanBacklogOrderKey = '00000000000000000000';
const _kanbanTodoOrderKey = '00000000000000001000';
const _kanbanInProgressOrderKey = '00000000000000002000';
const _kanbanDoneOrderKey = '00004503599627370496';

@DataClassName('UserRow')
class Users extends Table {
  TextColumn get id => text()();
  TextColumn get email => text().nullable()();
  TextColumn get displayName =>
      text().withDefault(const Constant('Local User'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('WorkspaceRow')
class Workspaces extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get name => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('ProjectRow')
class Projects extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get name => text()();
  TextColumn get color => text().nullable()();
  TextColumn get parentId => text().nullable()();
  TextColumn get viewStyle => text().withDefault(const Constant('list'))();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  TextColumn get orderKey => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('SectionRow')
class Sections extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text()();
  TextColumn get name => text()();
  TextColumn get orderKey => text()();
  BoolColumn get isCollapsed => boolean().withDefault(const Constant(false))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@TableIndex.sql(
  'CREATE INDEX tasks_kanban_open_roots_by_project '
  'ON tasks (project_id, order_key, id) '
  "WHERE parent_id IS NULL AND is_deleted = 0 AND status = 'open'",
)
@TableIndex.sql(
  'CREATE INDEX tasks_kanban_done_roots_by_project '
  'ON tasks (project_id, COALESCE(completed_at, updated_at) DESC, id DESC) '
  "WHERE parent_id IS NULL AND is_deleted = 0 AND status = 'completed'",
)
@TableIndex.sql(
  'CREATE INDEX tasks_active_children_by_parent '
  'ON tasks (parent_id, status, id) '
  'WHERE parent_id IS NOT NULL AND is_deleted = 0',
)
@DataClassName('TaskRow')
class Tasks extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get content => text()();
  TextColumn get description => text().nullable()();
  TextColumn get projectId => text()();
  TextColumn get sectionId => text().nullable()();
  TextColumn get parentId => text().nullable()();
  IntColumn get priority => integer().withDefault(const Constant(4))();
  TextColumn get dueJson => text().nullable()();
  TextColumn get deadlineJson => text().nullable()();
  IntColumn get durationSeconds => integer().nullable()();
  TextColumn get status => text().withDefault(const Constant('open'))();
  IntColumn get estimatedFocusIntervals => integer().nullable()();
  IntColumn get completedFocusIntervals =>
      integer().withDefault(const Constant(0))();
  IntColumn get totalFocusSeconds => integer().withDefault(const Constant(0))();
  TextColumn get orderKey => text()();
  IntColumn get dayOrder => integer().nullable()();
  BoolColumn get isCollapsed => boolean().withDefault(const Constant(false))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get completedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('TaskCompletionRow')
class TaskCompletions extends Table {
  TextColumn get id => text()();
  TextColumn get taskId => text()();
  TextColumn get userId => text()();
  DateTimeColumn get completedAt => dateTime()();
  TextColumn get snapshotJson => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@TableIndex.sql(
  'CREATE UNIQUE INDEX labels_unique_kanban_system_key '
  'ON labels (system_key) '
  "WHERE kind = 'kanbanStatus' AND system_key IS NOT NULL",
)
@DataClassName('LabelRow')
class Labels extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get name => text()();
  TextColumn get color => text().nullable()();
  TextColumn get kind => text()
      .withDefault(const Constant(labelKindUser))
      .check(
        const CustomExpression<bool>("kind IN ('user', 'kanbanStatus')"),
      )();
  TextColumn get systemKey => text().nullable().check(
    const CustomExpression<bool>(
      "system_key IS NULL OR system_key IN "
      "('backlog', 'todo', 'inProgress', 'done')",
    ),
  )();
  TextColumn get orderKey => text()();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@TableIndex.sql(
  "CREATE UNIQUE INDEX task_labels_one_kanban_status_per_task "
  "ON task_labels (task_id) WHERE kind = 'kanbanStatus'",
)
@DataClassName('TaskLabelRow')
class TaskLabels extends Table {
  TextColumn get taskId => text()();
  TextColumn get labelId => text()();
  TextColumn get kind => text()
      .withDefault(const Constant(labelKindUser))
      .check(
        const CustomExpression<bool>("kind IN ('user', 'kanbanStatus')"),
      )();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {taskId, labelId};
}

@DataClassName('KanbanSettingsRow')
class KanbanSettings extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get selectedProjectIdsJson => text()();
  TextColumn get focusStatusLabelId => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('FilterRow')
class Filters extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get name => text()();
  TextColumn get query => text()();
  TextColumn get color => text().nullable()();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  TextColumn get orderKey => text()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('ReminderRow')
class Reminders extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get taskId => text()();
  TextColumn get type => text()();
  TextColumn get specJson => text()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('FocusPresetRow')
class FocusPresets extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get name => text()();
  IntColumn get workSeconds => integer()();
  IntColumn get shortBreakSeconds => integer()();
  IntColumn get longBreakSeconds => integer()();
  IntColumn get intervalsBeforeLongBreak => integer()();
  BoolColumn get autoStartBreaks =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get autoStartWork =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get allowPause => boolean().withDefault(const Constant(true))();
  BoolColumn get strictMode => boolean().withDefault(const Constant(false))();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('FocusRunRow')
class FocusRuns extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get taskId => text().nullable()();
  TextColumn get projectId => text().nullable()();
  TextColumn get presetId => text()();
  TextColumn get status => text()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime().nullable()();
  IntColumn get targetWorkIntervals => integer()();
  IntColumn get completedWorkIntervals =>
      integer().withDefault(const Constant(0))();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('FocusIntervalRow')
class FocusIntervals extends Table {
  TextColumn get id => text()();
  TextColumn get runId => text()();
  TextColumn get taskId => text().nullable()();
  TextColumn get projectId => text().nullable()();
  TextColumn get type => text()();
  TextColumn get status => text()();
  IntColumn get plannedSeconds => integer()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get pausedAt => dateTime().nullable()();
  IntColumn get pausedTotalSeconds =>
      integer().withDefault(const Constant(0))();
  DateTimeColumn get completedAt => dateTime().nullable()();
  DateTimeColumn get stoppedAt => dateTime().nullable()();
  IntColumn get sequenceNumber => integer()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('FocusEventRow')
class FocusEvents extends Table {
  TextColumn get id => text()();
  TextColumn get runId => text()();
  TextColumn get intervalId => text().nullable()();
  TextColumn get type => text()();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get payloadJson => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('FocusDailyStatRow')
class FocusDailyStats extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get localDate => text()();
  IntColumn get completedTasks => integer().withDefault(const Constant(0))();
  IntColumn get completedFocusIntervals =>
      integer().withDefault(const Constant(0))();
  IntColumn get totalFocusSeconds => integer().withDefault(const Constant(0))();
  IntColumn get interruptedIntervals =>
      integer().withDefault(const Constant(0))();
  IntColumn get plannedFocusIntervals =>
      integer().withDefault(const Constant(0))();
  DateTimeColumn get calculatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('SyncCommandRow')
class SyncCommands extends Table {
  TextColumn get id => text()();
  TextColumn get uuid => text().unique()();
  TextColumn get type => text()();
  TextColumn get clientId => text().nullable()();
  TextColumn get payloadJson => text()();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get lastError => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('SyncStateRow')
class SyncState extends Table {
  TextColumn get id => text()();
  TextColumn get deviceId => text()();
  TextColumn get cursor => text().nullable()();
  DateTimeColumn get lastPulledAt => dateTime().nullable()();
  DateTimeColumn get lastPushedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('GoogleCalendarConnectionRow')
class GoogleCalendarConnections extends Table {
  TextColumn get id => text()();
  TextColumn get accountEmail => text().nullable()();
  TextColumn get calendarId => text().nullable()();
  TextColumn get ownerDeviceId => text().nullable()();
  TextColumn get calendarName =>
      text().withDefault(const Constant('Pomodoist'))();
  TextColumn get syncToken => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('disconnected'))();
  TextColumn get lastError => text().nullable()();
  TextColumn get warning => text().nullable()();
  DateTimeColumn get lastSyncStartedAt => dateTime().nullable()();
  DateTimeColumn get lastSyncFinishedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('GoogleCalendarEventLinkRow')
class GoogleCalendarEventLinks extends Table {
  TextColumn get taskId => text()();
  TextColumn get calendarId => text()();
  TextColumn get eventId => text()();
  TextColumn get etag => text().nullable()();
  DateTimeColumn get googleUpdatedAt => dateTime().nullable()();
  DateTimeColumn get lastSyncedLocalUpdatedAt => dateTime().nullable()();
  TextColumn get unsupportedReason => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {taskId};
}

@DataClassName('IdMappingRow')
class IdMappings extends Table {
  TextColumn get localId => text()();
  TextColumn get serverId => text()();
  TextColumn get entityType => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {localId, entityType};
}

@DriftDatabase(
  tables: [
    Users,
    Workspaces,
    Projects,
    Sections,
    Tasks,
    TaskCompletions,
    Labels,
    TaskLabels,
    KanbanSettings,
    Filters,
    Reminders,
    FocusPresets,
    FocusRuns,
    FocusIntervals,
    FocusEvents,
    FocusDailyStats,
    SyncCommands,
    SyncState,
    GoogleCalendarConnections,
    GoogleCalendarEventLinks,
    IdMappings,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(
        executor ??
            driftDatabase(
              name: 'pomodoist',
              native: const DriftNativeOptions(
                shareAcrossIsolates: true,
                databaseDirectory: pomodoistDatabaseDirectory,
              ),
              web: DriftWebOptions(
                sqlite3Wasm: Uri.parse('/assets/web/sqlite3.wasm'),
                driftWorker: Uri.parse('/assets/web/drift_worker.js'),
              ),
            ),
      );

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(googleCalendarConnections);
        await m.createTable(googleCalendarEventLinks);
      }
      if (from < 3) {
        await m.addColumn(
          googleCalendarConnections,
          googleCalendarConnections.ownerDeviceId,
        );
      }
      if (from < 4) {
        await _runResumableMigrationStep(
          () => m.addColumn(labels, labels.kind),
          alreadyAppliedMessage: 'duplicate column name: kind',
        );
        await _runResumableMigrationStep(
          () => m.addColumn(labels, labels.systemKey),
          alreadyAppliedMessage: 'duplicate column name: system_key',
        );
        await _runResumableMigrationStep(
          () => m.addColumn(taskLabels, taskLabels.kind),
          alreadyAppliedMessage: 'duplicate column name: kind',
        );
        await _runResumableMigrationStep(
          () => m.createTable(kanbanSettings),
          alreadyAppliedMessage: 'already exists',
        );
        await customStatement(
          "CREATE UNIQUE INDEX IF NOT EXISTS "
          "task_labels_one_kanban_status_per_task "
          "ON task_labels (task_id) WHERE kind = 'kanbanStatus'",
        );
        await customStatement(
          'CREATE UNIQUE INDEX IF NOT EXISTS labels_unique_kanban_system_key '
          'ON labels (system_key) '
          "WHERE kind = 'kanbanStatus' AND system_key IS NOT NULL",
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS tasks_kanban_open_roots_by_project '
          'ON tasks (project_id, order_key, id) '
          "WHERE parent_id IS NULL AND is_deleted = 0 AND status = 'open'",
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS tasks_kanban_done_roots_by_project '
          'ON tasks '
          '(project_id, COALESCE(completed_at, updated_at) DESC, id DESC) '
          "WHERE parent_id IS NULL AND is_deleted = 0 AND status = 'completed'",
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS tasks_active_children_by_parent '
          'ON tasks (parent_id, status, id) '
          'WHERE parent_id IS NOT NULL AND is_deleted = 0',
        );
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  Future<void> _runResumableMigrationStep(
    Future<void> Function() action, {
    required String alreadyAppliedMessage,
  }) async {
    try {
      await action();
    } catch (error) {
      if (!error.toString().contains(alreadyAppliedMessage)) {
        rethrow;
      }
    }
  }

  Future<void> ensureSeedData() async {
    final existingUser = await (select(users)..limit(1)).getSingleOrNull();
    final now = DateTime.now().toUtc();
    if (existingUser == null) {
      await transaction(() async {
        await into(users).insert(
          UsersCompanion.insert(
            id: localUserId,
            displayName: const Value('Local User'),
            createdAt: now,
            updatedAt: now,
          ),
        );
        await into(workspaces).insert(
          WorkspacesCompanion.insert(
            id: localWorkspaceId,
            userId: localUserId,
            name: 'Personal',
            createdAt: now,
            updatedAt: now,
          ),
        );
        await into(projects).insert(
          ProjectsCompanion.insert(
            id: inboxProjectId,
            userId: localUserId,
            name: 'Inbox',
            color: const Value('#6B7280'),
            isFavorite: const Value(true),
            orderKey: 'a',
            createdAt: now,
            updatedAt: now,
          ),
        );
        await into(syncState).insert(
          SyncStateCompanion.insert(
            id: 'primary',
            deviceId: 'local-device',
            createdAt: now,
            updatedAt: now,
          ),
        );
      });
    }

    await _ensureSeedFocusPresets(now);
    await ensureKanbanData(now: now);
  }

  Future<void> resetAccountData() async {
    await transaction(() async {
      await delete(googleCalendarEventLinks).go();
      await delete(googleCalendarConnections).go();
      await delete(idMappings).go();
      await delete(syncCommands).go();
      await delete(syncState).go();
      await delete(focusEvents).go();
      await delete(focusIntervals).go();
      await delete(focusRuns).go();
      await delete(focusDailyStats).go();
      await delete(reminders).go();
      await delete(taskLabels).go();
      await delete(taskCompletions).go();
      await delete(tasks).go();
      await delete(sections).go();
      await delete(kanbanSettings).go();
      await delete(labels).go();
      await delete(filters).go();
      await delete(focusPresets).go();
      await delete(projects).go();
      await delete(workspaces).go();
      await delete(users).go();
    });
    await ensureSeedData();
  }

  Future<void> ensureKanbanData({DateTime? now}) async {
    final timestamp = (now ?? DateTime.now()).toUtc();
    await transaction(() async {
      await _ensureKanbanDefaultStatus(
        const _SeedKanbanStatus(
          id: kanbanStatusBacklogId,
          name: 'Backlog',
          systemKey: kanbanSystemKeyBacklog,
          orderKey: _kanbanBacklogOrderKey,
          isProtected: true,
        ),
        timestamp,
      );
      await _ensureKanbanDefaultStatus(
        const _SeedKanbanStatus(
          id: kanbanStatusTodoId,
          name: 'To do',
          systemKey: kanbanSystemKeyTodo,
          orderKey: _kanbanTodoOrderKey,
        ),
        timestamp,
      );
      await _ensureKanbanDefaultStatus(
        const _SeedKanbanStatus(
          id: kanbanStatusInProgressId,
          name: 'In progress',
          systemKey: kanbanSystemKeyInProgress,
          orderKey: _kanbanInProgressOrderKey,
        ),
        timestamp,
      );
      await _ensureKanbanDefaultStatus(
        const _SeedKanbanStatus(
          id: kanbanStatusDoneId,
          name: 'Done',
          systemKey: kanbanSystemKeyDone,
          orderKey: _kanbanDoneOrderKey,
          isProtected: true,
        ),
        timestamp,
      );

      await _repairKanbanTaskAssignments(timestamp);
      await repairKanbanSettings(now: timestamp);
    });
  }

  Future<void> _ensureKanbanDefaultStatus(
    _SeedKanbanStatus seed,
    DateTime now,
  ) async {
    final existing = await (select(
      labels,
    )..where((row) => row.id.equals(seed.id))).getSingleOrNull();
    if (existing == null) {
      await into(labels).insert(
        LabelsCompanion.insert(
          id: seed.id,
          userId: localUserId,
          name: seed.name,
          kind: const Value(labelKindKanbanStatus),
          systemKey: Value(seed.systemKey),
          orderKey: seed.orderKey,
          createdAt: now,
          updatedAt: now,
        ),
      );
      return;
    }
    if (!seed.isProtected && existing.isDeleted) {
      return;
    }

    final needsRepair =
        existing.kind != labelKindKanbanStatus ||
        existing.systemKey != seed.systemKey ||
        (seed.isProtected &&
            (existing.name.trim().isEmpty ||
                existing.orderKey != seed.orderKey ||
                existing.isDeleted));
    if (!needsRepair) {
      return;
    }
    await (update(labels)..where((row) => row.id.equals(seed.id))).write(
      LabelsCompanion(
        name: seed.isProtected && existing.name.trim().isEmpty
            ? Value(seed.name)
            : const Value.absent(),
        kind: const Value(labelKindKanbanStatus),
        systemKey: Value(seed.systemKey),
        orderKey: seed.isProtected
            ? Value(seed.orderKey)
            : const Value.absent(),
        isDeleted: seed.isProtected ? const Value(false) : const Value.absent(),
        updatedAt: Value(now),
      ),
    );
  }

  Future<void> _repairKanbanTaskAssignments(DateTime now) async {
    final activeStatusIds =
        (await (select(labels)..where(
                  (row) =>
                      row.kind.equals(labelKindKanbanStatus) &
                      row.isDeleted.equals(false),
                ))
                .get())
            .map((row) => row.id)
            .toSet();
    final tasksToRepair = await (select(
      tasks,
    )..where((row) => row.isDeleted.equals(false))).get();
    final statusLinks = await (select(
      taskLabels,
    )..where((row) => row.kind.equals(labelKindKanbanStatus))).get();
    final statusByTask = {
      for (final link in statusLinks) link.taskId: link.labelId,
    };

    for (final task in tasksToRepair) {
      final currentStatusId = statusByTask[task.id];
      final expectedStatusId = task.status == 'completed'
          ? kanbanStatusDoneId
          : currentStatusId == kanbanStatusDoneId ||
                !activeStatusIds.contains(currentStatusId)
          ? kanbanStatusBacklogId
          : currentStatusId!;
      if (currentStatusId == expectedStatusId) {
        continue;
      }
      await (delete(taskLabels)..where(
            (row) =>
                row.taskId.equals(task.id) &
                row.kind.equals(labelKindKanbanStatus),
          ))
          .go();
      await into(taskLabels).insert(
        TaskLabelsCompanion.insert(
          taskId: task.id,
          labelId: expectedStatusId,
          kind: const Value(labelKindKanbanStatus),
          createdAt: now,
        ),
      );
    }
  }

  Future<void> repairKanbanSettings({DateTime? now}) async {
    final timestamp = (now ?? DateTime.now()).toUtc();
    final activeProjects =
        await (select(projects)
              ..where(
                (row) =>
                    row.isDeleted.equals(false) & row.isArchived.equals(false),
              )
              ..orderBy([
                (row) => OrderingTerm.asc(row.orderKey),
                (row) => OrderingTerm.asc(row.id),
              ]))
            .get();
    final activeProjectIds = activeProjects.map((row) => row.id).toSet();
    final existing =
        await (select(kanbanSettings)
              ..where((row) => row.id.equals(kanbanSettingsPrimaryId)))
            .getSingleOrNull();
    final selectedProjectIds = _decodeProjectIds(
      existing?.selectedProjectIdsJson,
    ).where(activeProjectIds.contains).toSet().toList()..sort();
    if (selectedProjectIds.isEmpty) {
      selectedProjectIds.add(
        activeProjects.isEmpty ? inboxProjectId : activeProjects.first.id,
      );
    }
    final selectedProjectIdsJson = jsonEncode(selectedProjectIds);

    final activeStatuses =
        await (select(labels)
              ..where(
                (row) =>
                    row.kind.equals(labelKindKanbanStatus) &
                    row.isDeleted.equals(false),
              )
              ..orderBy([
                (row) => OrderingTerm.asc(row.orderKey),
                (row) => OrderingTerm.asc(row.id),
              ]))
            .get();
    final activeStatusIds = activeStatuses.map((row) => row.id).toSet();
    final middleStatuses = activeStatuses.where(
      (row) =>
          row.systemKey != kanbanSystemKeyBacklog &&
          row.systemKey != kanbanSystemKeyDone,
    );
    final currentFocusId = existing?.focusStatusLabelId;
    final hasValidCurrentFocus =
        activeStatusIds.contains(currentFocusId) &&
        currentFocusId != kanbanStatusDoneId;
    final focusStatusId = hasValidCurrentFocus
        ? currentFocusId!
        : existing == null && activeStatusIds.contains(kanbanStatusInProgressId)
        ? kanbanStatusInProgressId
        : middleStatuses.isNotEmpty
        ? middleStatuses.first.id
        : kanbanStatusBacklogId;

    if (existing == null) {
      await into(kanbanSettings).insert(
        KanbanSettingsCompanion.insert(
          id: kanbanSettingsPrimaryId,
          userId: localUserId,
          selectedProjectIdsJson: selectedProjectIdsJson,
          focusStatusLabelId: focusStatusId,
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
      );
      return;
    }
    if (existing.userId == localUserId &&
        existing.selectedProjectIdsJson == selectedProjectIdsJson &&
        existing.focusStatusLabelId == focusStatusId) {
      return;
    }
    await (update(
      kanbanSettings,
    )..where((row) => row.id.equals(kanbanSettingsPrimaryId))).write(
      KanbanSettingsCompanion(
        userId: const Value(localUserId),
        selectedProjectIdsJson: Value(selectedProjectIdsJson),
        focusStatusLabelId: Value(focusStatusId),
        updatedAt: Value(timestamp),
      ),
    );
  }

  List<String> _decodeProjectIds(String? value) {
    if (value == null) {
      return const [];
    }
    try {
      final decoded = jsonDecode(value);
      if (decoded is! List) {
        return const [];
      }
      return decoded.whereType<String>().toList();
    } on FormatException {
      return const [];
    }
  }

  Future<void> _ensureSeedFocusPresets(DateTime now) async {
    final existing = await select(focusPresets).get();
    final existingIds = existing.map((row) => row.id).toSet();
    final hasDefault = existing.any((row) => row.isDefault && !row.isDeleted);

    await transaction(() async {
      Future<void> insertMissing(_SeedFocusPreset preset) async {
        if (existingIds.contains(preset.id)) {
          return;
        }
        await into(focusPresets).insert(
          FocusPresetsCompanion.insert(
            id: preset.id,
            userId: localUserId,
            name: preset.name,
            workSeconds: preset.workSeconds,
            shortBreakSeconds: preset.shortBreakSeconds,
            longBreakSeconds: preset.longBreakSeconds,
            intervalsBeforeLongBreak: preset.intervalsBeforeLongBreak,
            isDefault: Value(preset.id == defaultPresetId && !hasDefault),
            createdAt: now,
            updatedAt: now,
          ),
        );
      }

      await insertMissing(
        const _SeedFocusPreset(
          id: defaultPresetId,
          name: 'Classic',
          workSeconds: 25 * 60,
          shortBreakSeconds: 5 * 60,
          longBreakSeconds: 15 * 60,
          intervalsBeforeLongBreak: 4,
        ),
      );
      await insertMissing(
        const _SeedFocusPreset(
          id: deepWorkPresetId,
          name: 'Deep Work',
          workSeconds: 50 * 60,
          shortBreakSeconds: 10 * 60,
          longBreakSeconds: 25 * 60,
          intervalsBeforeLongBreak: 4,
        ),
      );
      await insertMissing(
        const _SeedFocusPreset(
          id: shortSprintPresetId,
          name: 'Short Sprint',
          workSeconds: 15 * 60,
          shortBreakSeconds: 3 * 60,
          longBreakSeconds: 10 * 60,
          intervalsBeforeLongBreak: 4,
        ),
      );
      await insertMissing(
        const _SeedFocusPreset(
          id: flowPresetId,
          name: 'Flow',
          workSeconds: 45 * 60,
          shortBreakSeconds: 8 * 60,
          longBreakSeconds: 20 * 60,
          intervalsBeforeLongBreak: 4,
        ),
      );

      final hasDefaultAfterInsert =
          hasDefault ||
          (await (select(focusPresets)
                    ..where(
                      (row) =>
                          row.isDefault.equals(true) &
                          row.isDeleted.equals(false),
                    )
                    ..limit(1))
                  .getSingleOrNull()) !=
              null;
      if (!hasDefaultAfterInsert) {
        await (update(
          focusPresets,
        )..where((row) => row.id.equals(defaultPresetId))).write(
          FocusPresetsCompanion(
            isDefault: const Value(true),
            updatedAt: Value(now),
          ),
        );
      }
    });
  }
}

class _SeedFocusPreset {
  const _SeedFocusPreset({
    required this.id,
    required this.name,
    required this.workSeconds,
    required this.shortBreakSeconds,
    required this.longBreakSeconds,
    required this.intervalsBeforeLongBreak,
  });

  final String id;
  final String name;
  final int workSeconds;
  final int shortBreakSeconds;
  final int longBreakSeconds;
  final int intervalsBeforeLongBreak;
}

class _SeedKanbanStatus {
  const _SeedKanbanStatus({
    required this.id,
    required this.name,
    required this.systemKey,
    required this.orderKey,
    this.isProtected = false,
  });

  final String id;
  final String name;
  final String systemKey;
  final String orderKey;
  final bool isProtected;
}
