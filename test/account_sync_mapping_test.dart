import 'package:app_account/app_account.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/core/db/app_database.dart';
import 'package:pomodoist/core/sync/account_sync_engine.dart';
import 'package:pomodoist/features/tasks/domain/task_models.dart';
import 'package:uuid/uuid.dart';

void main() {
  test('remote Google Calendar deletion removes the stale local row', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.ensureSeedData();
    final now = DateTime.utc(2026, 9, 1, 12);
    await db
        .into(db.googleCalendarConnections)
        .insert(
          GoogleCalendarConnectionRow(
            id: 'primary',
            accountEmail: 'user@example.com',
            calendarId: 'legacy-calendar',
            ownerDeviceId: 'legacy-device',
            calendarName: 'Pomodoist',
            syncToken: null,
            status: 'error',
            lastError: 'DioException: 404',
            warning: null,
            lastSyncStartedAt: now,
            lastSyncFinishedAt: now,
            createdAt: now,
            updatedAt: now,
          ),
        );
    final engine = AccountSyncEngine(
      db: db,
      account: _PullOnlyAccountClient(
        AccountSyncPullResult(
          nextCursor: 1,
          hasMore: false,
          changes: [
            AccountSyncEntity(
              entityType: 'google_calendar_connection',
              entityId: 'primary',
              serverRevision: 1,
              deletedAt: now.add(const Duration(minutes: 1)),
              data: const {},
            ),
          ],
        ),
      ),
      uuid: const Uuid(),
    );

    await engine.pullLatest();

    expect(
      await db.select(db.googleCalendarConnections).getSingleOrNull(),
      isNull,
    );
  });

  test('legacy label payloads default missing kinds to user', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.ensureSeedData();
    final now = DateTime.utc(2026, 7, 10, 12);
    final account = _PullOnlyAccountClient(
      AccountSyncPullResult(
        nextCursor: 2,
        hasMore: false,
        changes: [
          AccountSyncEntity(
            entityType: 'label',
            entityId: 'legacy-label',
            serverRevision: 1,
            data: {
              'id': 'legacy-label',
              'userId': localUserId,
              'name': 'Legacy',
              'orderKey': 'legacy',
              'isFavorite': false,
              'isDeleted': false,
              'createdAt': now.toIso8601String(),
              'updatedAt': now.toIso8601String(),
            },
          ),
          AccountSyncEntity(
            entityType: 'task_label',
            entityId: 'legacy-task:legacy-label',
            serverRevision: 2,
            data: {
              'taskId': 'legacy-task',
              'labelId': 'legacy-label',
              'createdAt': now.toIso8601String(),
            },
          ),
        ],
      ),
    );
    final engine = AccountSyncEngine(
      db: db,
      account: account,
      uuid: const Uuid(),
    );

    final entityTypes = await engine.pullLatest();

    expect(entityTypes, {'label', 'task_label'});

    final label = await (db.select(
      db.labels,
    )..where((row) => row.id.equals('legacy-label'))).getSingle();
    final link =
        await (db.select(db.taskLabels)..where(
              (row) =>
                  row.taskId.equals('legacy-task') &
                  row.labelId.equals('legacy-label'),
            ))
            .getSingle();
    expect(label.kind, labelKindUser);
    expect(label.systemKey, isNull);
    expect(link.kind, labelKindUser);
  });

  test('ordinary task_label payload cannot target a Kanban status', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.ensureSeedData();
    final now = DateTime.utc(2026, 7, 10, 12);
    final account = _PullOnlyAccountClient(
      AccountSyncPullResult(
        nextCursor: 1,
        hasMore: false,
        changes: [
          AccountSyncEntity(
            entityType: 'task_label',
            entityId: 'legacy-task:$kanbanStatusTodoId',
            serverRevision: 1,
            data: {
              'taskId': 'legacy-task',
              'labelId': kanbanStatusTodoId,
              'kind': labelKindKanbanStatus,
              'createdAt': now.toIso8601String(),
            },
          ),
        ],
      ),
    );
    final engine = AccountSyncEngine(
      db: db,
      account: account,
      uuid: const Uuid(),
    );

    await engine.pullLatest();

    final links =
        await (db.select(db.taskLabels)..where(
              (row) =>
                  row.taskId.equals('legacy-task') &
                  row.labelId.equals(kanbanStatusTodoId),
            ))
            .get();
    expect(links, isEmpty);
  });

  test(
    'remote calendar pull clears task schedule and nullable sync state',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.ensureSeedData();
      final now = DateTime.utc(2026, 9, 3, 10);
      final later = now.add(const Duration(minutes: 1));
      final task = TaskRow(
        id: 'task-1',
        userId: localUserId,
        content: 'Calendar task',
        description: null,
        projectId: inboxProjectId,
        sectionId: null,
        parentId: null,
        priority: 1,
        status: 'open',
        dueJson: TaskSchedule.timed(
          start: DateTime.utc(2026, 9, 3, 12),
          end: DateTime.utc(2026, 9, 3, 13),
          timeZone: 'Europe/Moscow',
        ).toJsonString(),
        durationSeconds: 3600,
        estimatedFocusIntervals: null,
        completedFocusIntervals: 0,
        totalFocusSeconds: 0,
        completedAt: null,
        orderKey: 'task-1',
        isCollapsed: false,
        isDeleted: false,
        createdAt: now,
        updatedAt: now,
      );
      await db.into(db.tasks).insert(task);
      await db
          .into(db.googleCalendarConnections)
          .insert(
            GoogleCalendarConnectionRow(
              id: 'primary',
              accountEmail: 'user@example.com',
              calendarId: 'calendar-1',
              ownerDeviceId: 'google-calendar-server',
              calendarName: 'Pomodoist',
              syncToken: 'stale-token',
              status: 'error',
              lastError: 'Invalid start time.',
              warning: 'stale warning',
              lastSyncStartedAt: now,
              lastSyncFinishedAt: now,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db
          .into(db.googleCalendarEventLinks)
          .insert(
            GoogleCalendarEventLinkRow(
              taskId: task.id,
              calendarId: 'calendar-1',
              eventId: 'event-1',
              etag: 'stale-etag',
              googleUpdatedAt: now,
              lastSyncedLocalUpdatedAt: now,
              unsupportedReason: 'stale warning',
              createdAt: now,
              updatedAt: now,
            ),
          );
      final clearedTask = task.toJson()
        ..['dueJson'] = null
        ..['durationSeconds'] = null
        ..['updatedAt'] = later.toIso8601String();
      final account = _PullOnlyAccountClient(
        AccountSyncPullResult(
          nextCursor: 1,
          hasMore: false,
          changes: [
            AccountSyncEntity(
              entityType: 'task',
              entityId: task.id,
              serverRevision: 1,
              data: clearedTask,
            ),
            AccountSyncEntity(
              entityType: 'google_calendar_connection',
              entityId: 'primary',
              serverRevision: 2,
              data: {
                'id': 'primary',
                'lastError': null,
                'warning': null,
                'syncToken': null,
                'updatedAt': later.toIso8601String(),
              },
            ),
            AccountSyncEntity(
              entityType: 'google_calendar_event_link',
              entityId: task.id,
              serverRevision: 3,
              data: {
                'taskId': task.id,
                'etag': null,
                'googleUpdatedAt': null,
                'unsupportedReason': null,
                'updatedAt': later.toIso8601String(),
              },
            ),
          ],
        ),
      );
      final engine = AccountSyncEngine(
        db: db,
        account: account,
        uuid: const Uuid(),
      );
      final watched =
          (db.select(db.tasks)..where((row) => row.id.equals(task.id)))
              .watchSingle()
              .firstWhere((row) => row.dueJson == null);

      await engine.pullLatest();

      expect((await watched).durationSeconds, isNull);
      final connection = await db
          .select(db.googleCalendarConnections)
          .getSingle();
      expect(connection.lastError, isNull);
      expect(connection.warning, isNull);
      expect(connection.syncToken, isNull);
      final eventLink = await db
          .select(db.googleCalendarEventLinks)
          .getSingle();
      expect(eventLink.etag, isNull);
      expect(eventLink.googleUpdatedAt, isNull);
      expect(eventLink.unsupportedReason, isNull);
    },
  );
}

class _PullOnlyAccountClient implements AccountClient {
  _PullOnlyAccountClient(this.result);

  final AccountSyncPullResult result;

  @override
  Future<AccountSyncPullResult> pullChanges({
    required String appId,
    required String deviceId,
    required int sinceRevision,
    int limit = 500,
  }) async {
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
