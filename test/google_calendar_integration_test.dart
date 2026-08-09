import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/core/db/app_database.dart';
import 'package:pomodoist/core/sync/sync_queue_repository.dart';
import 'package:pomodoist/features/integrations/google_calendar/data/auth/google_calendar_auth_contract.dart';
import 'package:pomodoist/features/integrations/google_calendar/data/google_calendar_api_client.dart';
import 'package:pomodoist/features/integrations/google_calendar/data/google_calendar_repository.dart';
import 'package:pomodoist/features/integrations/google_calendar/data/google_calendar_sync_controller.dart';
import 'package:pomodoist/features/integrations/google_calendar/domain/google_calendar_event.dart';
import 'package:pomodoist/features/tasks/data/task_repository_impl.dart';
import 'package:pomodoist/features/tasks/domain/task_models.dart';

void main() {
  group('task schedule', () {
    test('parses legacy date due json as all-day schedule', () {
      final schedule = TaskSchedule.fromJsonString(
        '{"type":"date","date":"2026-04-28T00:00:00.000"}',
      );

      expect(schedule, isNotNull);
      expect(schedule!.isAllDay, isTrue);
      expect(schedule.displayDate, DateTime(2026, 4, 28));
    });

    test('serializes and parses timed schedules', () {
      final schedule = TaskSchedule.timed(
        start: DateTime.utc(2026, 4, 28, 4),
        end: DateTime.utc(2026, 4, 28, 5),
        timeZone: 'UTC',
      );

      final parsed = TaskSchedule.fromJsonString(schedule.toJsonString());

      expect(parsed, schedule);
    });
  });

  group('google calendar event mapping', () {
    test('maps all-day tasks and completion marker idempotently', () {
      final now = DateTime.utc(2026, 4, 28);
      final task = TaskItem(
        id: 'task-1',
        userId: localUserId,
        content: '[Done] Write plan',
        projectId: inboxProjectId,
        priority: 4,
        dueJson: TaskSchedule.allDay(now).toJsonString(),
        status: 'completed',
        completedFocusIntervals: 0,
        totalFocusSeconds: 0,
        orderKey: 'a',
        isDeleted: false,
        createdAt: now,
        updatedAt: now,
      );

      final event = eventFromTask(task);

      expect(event.summary, '[Done] Write plan');
      expect(event.toJson()['colorId'], googleCalendarCompletedColorId);
      expect(event.start!.toJson(), {'date': '2026-04-28'});
      expect(event.end!.toJson(), {'date': '2026-04-29'});
      expect(stripDonePrefix(event.summary!), 'Write plan');
    });

    test('active task insert leaves Google Calendar color default', () {
      final now = DateTime.utc(2026, 4, 28);
      final task = TaskItem(
        id: 'task-1',
        userId: localUserId,
        content: 'Write plan',
        projectId: inboxProjectId,
        priority: 4,
        dueJson: TaskSchedule.allDay(now).toJsonString(),
        status: 'active',
        completedFocusIntervals: 0,
        totalFocusSeconds: 0,
        orderKey: 'a',
        isDeleted: false,
        createdAt: now,
        updatedAt: now,
      );

      expect(eventFromTask(task).toJson(), isNot(contains('colorId')));
    });

    test('active task patch clears a previous Google Calendar color', () {
      final now = DateTime.utc(2026, 4, 28);
      final task = TaskItem(
        id: 'task-1',
        userId: localUserId,
        content: 'Write plan',
        projectId: inboxProjectId,
        priority: 4,
        dueJson: TaskSchedule.allDay(now).toJsonString(),
        status: 'active',
        completedFocusIntervals: 0,
        totalFocusSeconds: 0,
        orderKey: 'a',
        isDeleted: false,
        createdAt: now,
        updatedAt: now,
      );

      expect(
        eventFromTask(task, clearActiveColor: true).toJson()['colorId'],
        isNull,
      );
      expect(
        eventFromTask(task, clearActiveColor: true).toJson(),
        contains('colorId'),
      );
    });

    test('omits non-IANA timed task zones for Google Calendar', () {
      final time = GoogleCalendarEventTime.timed(
        DateTime.utc(2026, 5, 1, 12),
        timeZone: 'MSK',
      );

      expect(time.toJson(), {'dateTime': '2026-05-01T12:00:00.000Z'});
    });

    test('maps timed task start and end to Google Calendar', () {
      final now = DateTime.utc(2026, 5, 1);
      final task = TaskItem(
        id: 'task-1',
        userId: localUserId,
        content: 'Call',
        projectId: inboxProjectId,
        priority: 4,
        dueJson: TaskSchedule.timed(
          start: DateTime.utc(2026, 5, 1, 16),
          end: DateTime.utc(2026, 5, 1, 16, 30),
          timeZone: 'UTC',
        ).toJsonString(),
        status: 'active',
        completedFocusIntervals: 0,
        totalFocusSeconds: 0,
        orderKey: 'a',
        isDeleted: false,
        createdAt: now,
        updatedAt: now,
      );

      final event = eventFromTask(task);

      expect(event.start!.toJson(), {
        'dateTime': '2026-05-01T16:00:00.000Z',
        'timeZone': 'UTC',
      });
      expect(event.end!.toJson(), {
        'dateTime': '2026-05-01T16:30:00.000Z',
        'timeZone': 'UTC',
      });
    });
  });

  group('google calendar sync', () {
    late AppDatabase db;
    late DriftTaskRepository taskRepository;
    late DriftCalendarIntegrationRepository integrationRepository;
    late _FakeGoogleCalendarApiClient api;
    late GoogleCalendarSyncController controller;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await db.ensureSeedData();
      taskRepository = DriftTaskRepository(db, DriftSyncQueueRepository(db));
      integrationRepository = DriftCalendarIntegrationRepository(db);
      api = _FakeGoogleCalendarApiClient();
      controller = GoogleCalendarSyncController(
        db: db,
        taskRepository: taskRepository,
        integrationRepository: integrationRepository,
        authService: const _FakeGoogleCalendarAuthService(),
        apiClient: api,
        deviceId: () async => 'device-1',
      );
      await integrationRepository.saveConnected(
        calendarId: 'calendar-1',
        calendarName: 'Pomodoist',
      );
    });

    tearDown(() => db.close());

    test('unowned connection is claimed by the local device', () async {
      await controller.syncNow(interactive: true);

      final connection = await integrationRepository.getConnection();
      expect(connection?.ownerDeviceId, 'device-1');
      expect(api.seenSyncTokens, [null]);
    });

    test('non-owner device does not call Google Calendar API', () async {
      await integrationRepository.claimOwnerDevice('device-2');

      await controller.syncNow(interactive: true);

      final connection = await integrationRepository.getConnection();
      expect(connection?.ownerDeviceId, 'device-2');
      expect(api.seenSyncTokens, isEmpty);
      expect(api.patchedEvents, isEmpty);
    });

    test('connect takes ownership on the local device', () async {
      await integrationRepository.claimOwnerDevice('device-2');

      await controller.connect();

      final connection = await integrationRepository.getConnection();
      expect(connection?.accountEmail, 'user@example.com');
      expect(connection?.ownerDeviceId, 'device-1');
      expect(api.seenSyncTokens, [null]);
    });

    test('non-interactive auth error does not enqueue sync storm', () async {
      final syncQueue = DriftSyncQueueRepository(db);
      final ownedRepository = DriftCalendarIntegrationRepository(
        db,
        syncQueue: syncQueue,
      );
      final ownedController = GoogleCalendarSyncController(
        db: db,
        taskRepository: taskRepository,
        integrationRepository: ownedRepository,
        authService: const _AuthRequiredGoogleCalendarAuthService(),
        apiClient: api,
        deviceId: () async => 'device-1',
      );
      await ownedRepository.saveConnected(
        calendarId: 'calendar-1',
        calendarName: 'Pomodoist',
        ownerDeviceId: 'device-1',
      );
      await ownedRepository.markError(
        const GoogleCalendarAuthRequiredException(),
      );
      await db.delete(db.syncCommands).go();

      await ownedController.syncNow();

      final commands = await db.select(db.syncCommands).get();
      final connection = await ownedRepository.getConnection();
      expect(commands, isEmpty);
      expect(api.seenSyncTokens, isEmpty);
      expect(connection?.status, 'error');
    });

    test('auth timeout records error and releases syncing for retry', () async {
      final auth = _ControllableGoogleCalendarAuthService()..hang = true;
      final timeoutController = GoogleCalendarSyncController(
        db: db,
        taskRepository: taskRepository,
        integrationRepository: integrationRepository,
        authService: auth,
        apiClient: api,
        deviceId: () async => 'device-1',
        requestTimeout: const Duration(milliseconds: 10),
      );

      await expectLater(
        timeoutController.syncNow(interactive: false),
        throwsA(isA<TimeoutException>()),
      );
      expect((await integrationRepository.getConnection())?.status, 'error');

      auth.hang = false;
      await timeoutController.syncNow(interactive: true);
      expect(
        (await integrationRepository.getConnection())?.status,
        'connected',
      );
      expect(api.seenSyncTokens, [null]);
    });

    test('connect auth timeout is persisted on the connection', () async {
      final auth = _ControllableGoogleCalendarAuthService()..hangSignIn = true;
      final timeoutController = GoogleCalendarSyncController(
        db: db,
        taskRepository: taskRepository,
        integrationRepository: integrationRepository,
        authService: auth,
        apiClient: api,
        deviceId: () async => 'device-1',
        interactiveAuthTimeout: const Duration(milliseconds: 10),
      );

      await expectLater(
        timeoutController.connect(),
        throwsA(isA<TimeoutException>()),
      );

      final connection = await integrationRepository.getConnection();
      expect(connection?.status, 'error');
      expect(connection?.lastError, contains('TimeoutException'));
    });

    test('disconnect timeout is persisted on the connection', () async {
      final auth = _ControllableGoogleCalendarAuthService()
        ..hangDisconnect = true;
      final timeoutController = GoogleCalendarSyncController(
        db: db,
        taskRepository: taskRepository,
        integrationRepository: integrationRepository,
        authService: auth,
        apiClient: api,
        deviceId: () async => 'device-1',
        requestTimeout: const Duration(milliseconds: 10),
      );

      await expectLater(
        timeoutController.disconnect(),
        throwsA(isA<TimeoutException>()),
      );

      final connection = await integrationRepository.getConnection();
      expect(connection?.status, 'error');
      expect(connection?.lastError, contains('TimeoutException'));
    });

    test(
      'repeated page token fails instead of looping and permits retry',
      () async {
        api.nextPageToken = 'same-page';

        await expectLater(
          controller.syncNow(interactive: true),
          throwsStateError,
        );
        expect(api.listCalls, 2);
        expect((await integrationRepository.getConnection())?.status, 'error');

        api.nextPageToken = null;
        await controller.syncNow(interactive: true);
        expect(
          (await integrationRepository.getConnection())?.status,
          'connected',
        );
      },
    );

    test('API timeout records error and releases syncing for retry', () async {
      api.pendingList = Completer<GoogleCalendarListResult>().future;
      final timeoutController = GoogleCalendarSyncController(
        db: db,
        taskRepository: taskRepository,
        integrationRepository: integrationRepository,
        authService: const _FakeGoogleCalendarAuthService(),
        apiClient: api,
        deviceId: () async => 'device-1',
        requestTimeout: const Duration(milliseconds: 10),
      );

      await expectLater(
        timeoutController.syncNow(interactive: true),
        throwsA(isA<TimeoutException>()),
      );
      expect((await integrationRepository.getConnection())?.status, 'error');

      api.pendingList = null;
      await timeoutController.syncNow(interactive: true);
      expect(
        (await integrationRepository.getConnection())?.status,
        'connected',
      );
    });

    test(
      'initial full sync creates a task for a Google-created event',
      () async {
        api.events['event-1'] = GoogleCalendarEvent(
          id: 'event-1',
          status: 'confirmed',
          summary: 'Plan launch',
          description: 'Draft checklist',
          start: GoogleCalendarEventTime.allDay(DateTime(2026, 5, 1)),
          end: GoogleCalendarEventTime.allDay(DateTime(2026, 5, 2)),
          updated: DateTime.utc(2026, 4, 30, 10),
        );

        await controller.syncNow(interactive: true);

        final tasks = await db.select(db.tasks).get();
        final created = tasks.singleWhere(
          (task) => task.content == 'Plan launch',
        );
        final link = await integrationRepository.linkForTask(created.id);
        final connection = await integrationRepository.getConnection();

        expect(created.description, 'Draft checklist');
        expect(
          TaskSchedule.fromJsonString(created.dueJson)!.displayDate,
          DateTime(2026, 5),
        );
        expect(link?.eventId, 'event-1');
        expect(connection?.syncToken, 'sync-token-1');
        expect(api.patchedEvents, contains('event-1'));
      },
    );

    test(
      'Google-created completed event snapshots Backlog and enters Done',
      () async {
        api.events['event-done'] = GoogleCalendarEvent(
          id: 'event-done',
          status: 'confirmed',
          summary: '[Done] Calendar complete',
          start: GoogleCalendarEventTime.allDay(DateTime(2026, 5, 1)),
          end: GoogleCalendarEventTime.allDay(DateTime(2026, 5, 2)),
          updated: DateTime.utc(2026, 4, 30, 10),
        );

        await controller.syncNow(interactive: true);

        final task = (await db.select(db.tasks).get()).singleWhere(
          (row) => row.content == 'Calendar complete',
        );
        final assignment =
            (await (db.select(
              db.taskLabels,
            )..where((row) => row.taskId.equals(task.id))).get()).singleWhere(
              (row) => row.kind == labelKindKanbanStatus,
            );
        final completion = await (db.select(
          db.taskCompletions,
        )..where((row) => row.taskId.equals(task.id))).getSingle();
        expect(task.status, 'completed');
        expect(assignment.labelId, kanbanStatusDoneId);
        expect(
          completion.snapshotJson,
          '{"version":1,"kanban":{"previousStatusLabelId":'
          '"$kanbanStatusBacklogId"}}',
        );
      },
    );

    test('local scheduled task creates a Google event', () async {
      final taskId = await taskRepository.createTask(
        CreateTaskInput(
          content: 'Write sync tests',
          schedule: TaskSchedule.timed(
            start: DateTime.utc(2026, 5, 1, 1),
            end: DateTime.utc(2026, 5, 1, 2),
            timeZone: 'UTC',
          ),
        ),
      );

      await controller.syncNow(interactive: true);

      final link = await integrationRepository.linkForTask(taskId);
      final created = api.events[link!.eventId]!;

      expect(created.summary, 'Write sync tests');
      expect(created.colorId, isNull);
      expect(created.start!.dateTime, DateTime.utc(2026, 5, 1, 1));
      expect(created.end!.dateTime, DateTime.utc(2026, 5, 1, 2));
    });

    test('completed linked task patches Google event gray', () async {
      final taskId = await taskRepository.createTask(
        CreateTaskInput(
          content: 'Ship marker',
          schedule: TaskSchedule.allDay(DateTime(2026, 5, 1)),
        ),
      );
      final task = await taskRepository.watchTask(taskId).first;
      await integrationRepository.upsertLink(
        taskId: taskId,
        calendarId: 'calendar-1',
        eventId: 'event-5',
        lastSyncedLocalUpdatedAt: task!.updatedAt.subtract(
          const Duration(minutes: 1),
        ),
      );
      api.events['event-5'] = const GoogleCalendarEvent(
        id: 'event-5',
        status: 'confirmed',
        summary: 'Ship marker',
      );
      await taskRepository.completeTask(taskId);

      await controller.syncNow(interactive: true);

      final patched = api.events['event-5']!;
      expect(patched.summary, '[Done] Ship marker');
      expect(patched.colorId, googleCalendarCompletedColorId);
    });

    test('reopened linked task clears Google event color', () async {
      final taskId = await taskRepository.createTask(
        CreateTaskInput(
          content: 'Reopen marker',
          schedule: TaskSchedule.allDay(DateTime(2026, 5, 1)),
        ),
      );
      await taskRepository.completeTask(taskId);
      final task = await taskRepository.watchTask(taskId).first;
      await integrationRepository.upsertLink(
        taskId: taskId,
        calendarId: 'calendar-1',
        eventId: 'event-6',
        lastSyncedLocalUpdatedAt: task!.updatedAt.subtract(
          const Duration(minutes: 1),
        ),
      );
      api.events['event-6'] = GoogleCalendarEvent(
        id: 'event-6',
        status: 'confirmed',
        summary: '[Done] Reopen marker',
        colorId: googleCalendarCompletedColorId,
        updated: task.updatedAt,
      );
      await taskRepository.uncompleteTask(taskId);

      await controller.syncNow(interactive: true);

      final patched = api.events['event-6']!;
      expect(patched.summary, 'Reopen marker');
      expect(patched.colorId, isNull);
    });

    test(
      'linked task recreates Google event when patch start time is invalid',
      () async {
        final taskId = await taskRepository.createTask(
          CreateTaskInput(
            content: 'Recover invalid event',
            schedule: TaskSchedule.timed(
              start: DateTime.utc(2026, 5, 1, 6, 30),
              end: DateTime.utc(2026, 5, 1, 7, 30),
            ),
          ),
        );
        final task = await taskRepository.watchTask(taskId).first;
        await integrationRepository.upsertLink(
          taskId: taskId,
          calendarId: 'calendar-1',
          eventId: 'event-bad-start',
          lastSyncedLocalUpdatedAt: task!.updatedAt.subtract(
            const Duration(minutes: 1),
          ),
        );
        api.events['event-bad-start'] = const GoogleCalendarEvent(
          id: 'event-bad-start',
          status: 'confirmed',
          summary: 'Recover invalid event',
        );
        api.patchFailures['event-bad-start'] = const GoogleCalendarApiException(
          'Google Calendar API failed: Invalid start time.',
        );

        await controller.syncNow(interactive: true);

        final link = await integrationRepository.linkForTask(taskId);
        expect(link!.eventId, isNot('event-bad-start'));
        expect(api.events[link.eventId]!.summary, 'Recover invalid event');
        expect(api.events.containsKey('event-bad-start'), isFalse);
      },
    );

    test('newer Google event moves and renames a linked task', () async {
      final taskId = await taskRepository.createTask(
        CreateTaskInput(
          content: 'Old title',
          schedule: TaskSchedule.allDay(DateTime(2026, 5, 1)),
        ),
      );
      final task = await taskRepository.watchTask(taskId).first;
      await integrationRepository.upsertLink(
        taskId: taskId,
        calendarId: 'calendar-1',
        eventId: 'event-2',
        lastSyncedLocalUpdatedAt: task!.updatedAt,
      );
      api.events['event-2'] = GoogleCalendarEvent(
        id: 'event-2',
        status: 'confirmed',
        summary: 'New title',
        start: GoogleCalendarEventTime.allDay(DateTime(2026, 5, 3)),
        end: GoogleCalendarEventTime.allDay(DateTime(2026, 5, 4)),
        updated: task.updatedAt.add(const Duration(minutes: 5)),
        privateExtendedProperties: {'pomodoistTaskId': taskId},
      );

      await controller.syncNow(interactive: true);

      final updated = await taskRepository.watchTask(taskId).first;
      expect(updated!.content, 'New title');
      expect(updated.dueDate, DateTime(2026, 5, 3));
    });

    test('expired sync token falls back to a full sync', () async {
      await integrationRepository.markSyncFinished(syncToken: 'expired');
      api.throwExpiredTokenOnce = true;
      api.events['event-3'] = GoogleCalendarEvent(
        id: 'event-3',
        status: 'confirmed',
        summary: 'Recovered event',
        start: GoogleCalendarEventTime.allDay(DateTime(2026, 5, 4)),
        end: GoogleCalendarEventTime.allDay(DateTime(2026, 5, 5)),
        updated: DateTime.utc(2026, 4, 30, 10),
      );

      await controller.syncNow(interactive: true);

      expect(api.seenSyncTokens, ['expired', null]);
      final tasks = await db.select(db.tasks).get();
      expect(
        tasks.where((task) => task.content == 'Recovered event'),
        hasLength(1),
      );
    });

    test('recurring events are skipped with a warning', () async {
      api.events['event-4'] = GoogleCalendarEvent(
        id: 'event-4',
        status: 'confirmed',
        summary: 'Daily standup',
        start: GoogleCalendarEventTime.allDay(DateTime(2026, 5, 4)),
        end: GoogleCalendarEventTime.allDay(DateTime(2026, 5, 5)),
        updated: DateTime.utc(2026, 4, 30, 10),
        recurrence: const ['RRULE:FREQ=DAILY'],
      );

      await controller.syncNow(interactive: true);

      final connection = await integrationRepository.getConnection();
      final tasks = await db.select(db.tasks).get();

      expect(connection!.warning, contains('Recurring'));
      expect(tasks.where((task) => task.content == 'Daily standup'), isEmpty);
    });
  });
}

class _FakeGoogleCalendarAuthService implements GoogleCalendarAuthService {
  const _FakeGoogleCalendarAuthService();

  @override
  Future<void> initialize() async {}

  @override
  Future<String?> accessToken({bool interactive = false}) async => 'token';

  @override
  Future<void> disconnect() async {}

  @override
  Future<GoogleCalendarAuthAccount> signIn() async {
    return const GoogleCalendarAuthAccount(email: 'user@example.com');
  }
}

class _AuthRequiredGoogleCalendarAuthService
    implements GoogleCalendarAuthService {
  const _AuthRequiredGoogleCalendarAuthService();

  @override
  Future<void> initialize() async {}

  @override
  Future<String?> accessToken({bool interactive = false}) async => null;

  @override
  Future<void> disconnect() async {}

  @override
  Future<GoogleCalendarAuthAccount> signIn() async {
    return const GoogleCalendarAuthAccount();
  }
}

class _ControllableGoogleCalendarAuthService
    implements GoogleCalendarAuthService {
  bool hang = false;
  bool hangSignIn = false;
  bool hangDisconnect = false;

  @override
  Future<void> initialize() async {}

  @override
  Future<String?> accessToken({bool interactive = false}) {
    return hang ? Completer<String?>().future : Future.value('token');
  }

  @override
  Future<void> disconnect() {
    return hangDisconnect ? Completer<void>().future : Future.value();
  }

  @override
  Future<GoogleCalendarAuthAccount> signIn() {
    return hangSignIn
        ? Completer<GoogleCalendarAuthAccount>().future
        : Future.value(
            const GoogleCalendarAuthAccount(email: 'user@example.com'),
          );
  }
}

class _FakeGoogleCalendarApiClient implements GoogleCalendarApiClient {
  final events = <String, GoogleCalendarEvent>{};
  final patchedEvents = <String>[];
  final patchFailures = <String, Exception>{};
  final seenSyncTokens = <String?>[];
  bool throwExpiredTokenOnce = false;
  String? nextPageToken;
  Future<GoogleCalendarListResult>? pendingList;
  int listCalls = 0;
  int _id = 0;

  @override
  Future<GoogleCalendarApiCalendar> createCalendar(String name) async {
    return GoogleCalendarApiCalendar(id: 'calendar-1', summary: name);
  }

  @override
  Future<void> deleteEvent({
    required String calendarId,
    required String eventId,
  }) async {
    events.remove(eventId);
  }

  @override
  Future<GoogleCalendarApiCalendar> getCalendar(String calendarId) async {
    return const GoogleCalendarApiCalendar(
      id: 'calendar-1',
      summary: 'Pomodoist',
    );
  }

  @override
  Future<GoogleCalendarEvent> insertEvent({
    required String calendarId,
    required GoogleCalendarEvent event,
  }) async {
    final id = 'created-${++_id}';
    final created = GoogleCalendarEvent(
      id: id,
      status: 'confirmed',
      summary: event.summary,
      description: event.description,
      start: event.start,
      end: event.end,
      colorId: event.colorId,
      etag: 'etag-$id',
      updated: DateTime.utc(2026, 5, 1, 12, _id),
      privateExtendedProperties: event.privateExtendedProperties,
    );
    events[id] = created;
    return created;
  }

  @override
  Future<GoogleCalendarListResult> listEvents({
    required String calendarId,
    String? syncToken,
    String? pageToken,
  }) async {
    listCalls += 1;
    seenSyncTokens.add(syncToken);
    final pending = pendingList;
    if (pending != null) {
      return pending;
    }
    if (throwExpiredTokenOnce) {
      throwExpiredTokenOnce = false;
      throw const GoogleCalendarSyncTokenExpiredException();
    }
    return GoogleCalendarListResult(
      events: events.values.toList(),
      nextPageToken: nextPageToken,
      nextSyncToken: 'sync-token-1',
    );
  }

  @override
  Future<GoogleCalendarEvent> patchEvent({
    required String calendarId,
    required String eventId,
    required GoogleCalendarEvent event,
  }) async {
    final failure = patchFailures.remove(eventId);
    if (failure != null) {
      throw failure;
    }
    patchedEvents.add(eventId);
    final existing = events[eventId] ?? GoogleCalendarEvent(id: eventId);
    final patched = GoogleCalendarEvent(
      id: eventId,
      status: existing.status ?? 'confirmed',
      summary: event.summary ?? existing.summary,
      description: event.description ?? existing.description,
      start: event.start ?? existing.start,
      end: event.end ?? existing.end,
      colorId: event.clearColorId ? null : event.colorId ?? existing.colorId,
      etag: 'patched-$eventId',
      updated: DateTime.utc(2026, 5, 1, 13, patchedEvents.length),
      privateExtendedProperties: {
        ...existing.privateExtendedProperties,
        ...event.privateExtendedProperties,
      },
    );
    events[eventId] = patched;
    return patched;
  }
}
