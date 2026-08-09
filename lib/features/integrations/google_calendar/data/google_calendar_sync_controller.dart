import '../../../../core/db/app_database.dart';
import '../../../tasks/domain/task_models.dart';
import '../../../tasks/data/task_repository_impl.dart';
import '../domain/google_calendar_event.dart';
import 'auth/google_calendar_auth_contract.dart';
import 'google_calendar_api_client.dart';
import 'google_calendar_config.dart';
import 'google_calendar_repository.dart';

class GoogleCalendarSyncController {
  GoogleCalendarSyncController({
    required AppDatabase db,
    required DriftTaskRepository taskRepository,
    required CalendarIntegrationRepository integrationRepository,
    required GoogleCalendarAuthService authService,
    required GoogleCalendarApiClient apiClient,
    required Future<String> Function() deviceId,
    Duration requestTimeout = googleCalendarRequestTimeout,
    Duration interactiveAuthTimeout = googleCalendarInteractiveAuthTimeout,
  }) : _db = db,
       _taskRepository = taskRepository,
       _integrationRepository = integrationRepository,
       _authService = authService,
       _apiClient = apiClient,
       _deviceId = deviceId,
       _requestTimeout = requestTimeout,
       _interactiveAuthTimeout = interactiveAuthTimeout;

  final AppDatabase _db;
  final DriftTaskRepository _taskRepository;
  final CalendarIntegrationRepository _integrationRepository;
  final GoogleCalendarAuthService _authService;
  final GoogleCalendarApiClient _apiClient;
  final Future<String> Function() _deviceId;
  final Duration _requestTimeout;
  final Duration _interactiveAuthTimeout;

  bool _syncing = false;

  Future<void> connect() async {
    final existing = await _integrationRepository.ensureConnection();
    try {
      final deviceId = await _deviceId();
      final account = await _authService.signIn().timeout(
        _interactiveAuthTimeout,
      );
      final calendarId = existing.calendarId;
      final calendar = calendarId == null
          ? await _remote(
              _apiClient.createCalendar(GoogleCalendarConfig.calendarName),
            )
          : await _remote(_apiClient.getCalendar(calendarId));
      await _integrationRepository.saveConnected(
        accountEmail: account.email,
        calendarId: calendar.id,
        calendarName: calendar.summary,
        ownerDeviceId: deviceId,
      );
      await syncNow(interactive: false);
    } catch (error) {
      await _integrationRepository.markError(error);
      rethrow;
    }
  }

  Future<void> disconnect() async {
    final connection = await _integrationRepository.getConnection();
    final deviceId = await _deviceId();
    if (connection?.ownerDeviceId != null &&
        connection?.ownerDeviceId != deviceId) {
      return;
    }
    try {
      await _authService.disconnect().timeout(_requestTimeout);
      await _integrationRepository.disconnect();
    } catch (error) {
      await _integrationRepository.markError(error);
      rethrow;
    }
  }

  Future<void> syncNow({bool interactive = false}) async {
    if (_syncing) {
      return;
    }
    final connection = await _integrationRepository.getConnection();
    if (connection?.calendarId == null ||
        connection?.status == 'disconnected') {
      return;
    }
    if (!interactive &&
        connection?.status == 'error' &&
        _isAuthRequiredError(connection?.lastError)) {
      return;
    }
    final deviceId = await _deviceId();
    if (connection?.ownerDeviceId != null &&
        connection?.ownerDeviceId != deviceId) {
      return;
    }
    if (connection?.ownerDeviceId == null) {
      await _integrationRepository.claimOwnerDevice(deviceId);
    }
    _syncing = true;
    String? warning;
    try {
      await _integrationRepository.markSyncStarted();
      final token = await _authService
          .accessToken(interactive: interactive)
          .timeout(interactive ? _interactiveAuthTimeout : _requestTimeout);
      if (token == null) {
        throw const GoogleCalendarAuthRequiredException();
      }
      final calendarId = connection!.calendarId!;
      String? nextSyncToken;
      try {
        nextSyncToken = await _pullChanges(
          calendarId: calendarId,
          syncToken: connection.syncToken,
          warningSink: (value) => warning = _mergeWarning(warning, value),
        );
      } on GoogleCalendarSyncTokenExpiredException {
        nextSyncToken = await _pullChanges(
          calendarId: calendarId,
          syncToken: null,
          warningSink: (value) => warning = _mergeWarning(warning, value),
        );
      }
      warning = _mergeWarning(warning, await _pushLocalChanges(calendarId));
      await _integrationRepository.markSyncFinished(
        syncToken: nextSyncToken ?? connection.syncToken,
        warning: warning,
      );
    } catch (error) {
      await _integrationRepository.markError(error);
      rethrow;
    } finally {
      _syncing = false;
    }
  }

  bool _isAuthRequiredError(String? error) {
    return error?.contains('authorization is required') ?? false;
  }

  Future<String?> _pullChanges({
    required String calendarId,
    required String? syncToken,
    required void Function(String warning) warningSink,
  }) async {
    String? pageToken;
    String? nextSyncToken;
    final seenPageTokens = <String>{};
    do {
      final page = await _remote(
        _apiClient.listEvents(
          calendarId: calendarId,
          syncToken: syncToken,
          pageToken: pageToken,
        ),
      );
      for (final event in page.events) {
        final warning = await _applyRemoteEvent(
          calendarId: calendarId,
          event: event,
        );
        if (warning != null) {
          warningSink(warning);
        }
      }
      final nextPageToken = page.nextPageToken;
      if (nextPageToken != null && !seenPageTokens.add(nextPageToken)) {
        throw StateError(
          'Google Calendar returned the same nextPageToken more than once.',
        );
      }
      pageToken = nextPageToken;
      nextSyncToken = page.nextSyncToken ?? nextSyncToken;
    } while (pageToken != null);
    return nextSyncToken;
  }

  Future<String?> _applyRemoteEvent({
    required String calendarId,
    required GoogleCalendarEvent event,
  }) async {
    final eventId = event.id;
    if (eventId == null) {
      return null;
    }
    final linkedTaskId = event.pomodoistTaskId;
    final link = linkedTaskId == null
        ? await _integrationRepository.linkForEvent(eventId)
        : await _integrationRepository.linkForTask(linkedTaskId);

    if (event.isRecurring) {
      final taskId = link?.taskId ?? linkedTaskId;
      if (taskId != null) {
        await _integrationRepository.upsertLink(
          taskId: taskId,
          calendarId: calendarId,
          eventId: eventId,
          etag: event.etag,
          googleUpdatedAt: event.updated,
          lastSyncedLocalUpdatedAt: link?.lastSyncedLocalUpdatedAt,
          unsupportedReason: 'Recurring Google events are not supported in v1.',
        );
      }
      return 'Recurring Google Calendar events are not supported yet.';
    }

    if (link == null) {
      if (event.isCancelled) {
        return null;
      }
      final schedule = event.schedule;
      if (schedule == null) {
        return null;
      }
      final remoteUpdated = event.updated ?? DateTime.now().toUtc();
      final title = event.summary?.trim().isEmpty ?? true
          ? 'Untitled calendar task'
          : event.summary!.trim();
      final taskId = await _taskRepository.createTaskFromCalendar(
        RemoteCalendarTaskInput(
          content: stripDonePrefix(title),
          description: event.description,
          schedule: schedule,
          isCompleted: titleMarksDone(title),
          updatedAt: remoteUpdated,
        ),
      );
      final patched = await _remote(
        _apiClient.patchEvent(
          calendarId: calendarId,
          eventId: eventId,
          event: GoogleCalendarEvent(
            privateExtendedProperties: {
              'pomodoistSource': 'pomodoist',
              'pomodoistTaskId': taskId,
            },
          ),
        ),
      );
      await _integrationRepository.upsertLink(
        taskId: taskId,
        calendarId: calendarId,
        eventId: eventId,
        etag: patched.etag ?? event.etag,
        googleUpdatedAt: patched.updated ?? event.updated,
        lastSyncedLocalUpdatedAt: remoteUpdated,
      );
      return null;
    }

    final task = await _taskById(link.taskId);
    if (task == null) {
      await _integrationRepository.deleteLink(link.taskId);
      return null;
    }
    final remoteUpdated = event.updated ?? DateTime.now().toUtc();
    final remoteWins = remoteUpdated.isAfter(task.updatedAt);

    if (event.isCancelled) {
      if (remoteWins) {
        await _taskRepository.applyRemoteCalendarPatch(
          task.id,
          RemoteCalendarTaskPatch(isDeleted: true, updatedAt: remoteUpdated),
        );
      }
      await _integrationRepository.deleteLink(task.id);
      return null;
    }

    if (!remoteWins) {
      return null;
    }
    final schedule = event.schedule;
    if (schedule == null) {
      return null;
    }
    final title = event.summary?.trim().isEmpty ?? true
        ? task.content
        : event.summary!.trim();
    await _taskRepository.applyRemoteCalendarPatch(
      task.id,
      RemoteCalendarTaskPatch(
        content: stripDonePrefix(title),
        description: event.description,
        updateDescription: true,
        schedule: schedule,
        isCompleted: titleMarksDone(title),
        updatedAt: remoteUpdated,
      ),
    );
    await _integrationRepository.upsertLink(
      taskId: task.id,
      calendarId: calendarId,
      eventId: eventId,
      etag: event.etag,
      googleUpdatedAt: event.updated,
      lastSyncedLocalUpdatedAt: remoteUpdated,
    );
    return null;
  }

  Future<String?> _pushLocalChanges(String calendarId) async {
    final tasks = await _allTasks();
    String? warning;
    for (final task in tasks) {
      final link = await _integrationRepository.linkForTask(task.id);
      if (link?.unsupportedReason != null) {
        warning = _mergeWarning(warning, link!.unsupportedReason);
        continue;
      }
      if (task.isDeleted) {
        if (link != null) {
          await _remote(
            _apiClient.deleteEvent(
              calendarId: calendarId,
              eventId: link.eventId,
            ),
          );
          await _integrationRepository.deleteLink(task.id);
        }
        continue;
      }
      final schedule = task.schedule;
      if (schedule == null) {
        if (link != null) {
          await _remote(
            _apiClient.deleteEvent(
              calendarId: calendarId,
              eventId: link.eventId,
            ),
          );
          await _integrationRepository.deleteLink(task.id);
        }
        continue;
      }
      if (link == null) {
        final created = await _remote(
          _apiClient.insertEvent(
            calendarId: calendarId,
            event: eventFromTask(task),
          ),
        );
        await _integrationRepository.upsertLink(
          taskId: task.id,
          calendarId: calendarId,
          eventId: created.id!,
          etag: created.etag,
          googleUpdatedAt: created.updated,
          lastSyncedLocalUpdatedAt: task.updatedAt,
        );
        continue;
      }
      final lastSynced = link.lastSyncedLocalUpdatedAt;
      if (lastSynced != null && !task.updatedAt.isAfter(lastSynced)) {
        continue;
      }
      final (eventId, patched) = await _patchLinkedEvent(
        calendarId: calendarId,
        link: link,
        task: task,
      );
      await _integrationRepository.upsertLink(
        taskId: task.id,
        calendarId: calendarId,
        eventId: eventId,
        etag: patched.etag,
        googleUpdatedAt: patched.updated,
        lastSyncedLocalUpdatedAt: task.updatedAt,
      );
    }
    return warning;
  }

  Future<(String, GoogleCalendarEvent)> _patchLinkedEvent({
    required String calendarId,
    required GoogleCalendarEventLinkRow link,
    required TaskItem task,
  }) async {
    try {
      final patched = await _remote(
        _apiClient.patchEvent(
          calendarId: calendarId,
          eventId: link.eventId,
          event: eventFromTask(task, clearActiveColor: true),
        ),
      );
      return (link.eventId, patched);
    } on GoogleCalendarApiException catch (error) {
      if (!_shouldRecreateLinkedEvent(error)) {
        rethrow;
      }
      final created = await _remote(
        _apiClient.insertEvent(
          calendarId: calendarId,
          event: eventFromTask(task),
        ),
      );
      try {
        await _remote(
          _apiClient.deleteEvent(calendarId: calendarId, eventId: link.eventId),
        );
      } catch (_) {
        // Best effort cleanup: the replacement event is already linked locally.
      }
      return (created.id!, created);
    }
  }

  Future<T> _remote<T>(Future<T> operation) {
    return operation.timeout(_requestTimeout);
  }

  Future<List<TaskItem>> _allTasks() async {
    final rows = await _db.select(_db.tasks).get();
    return rows.map(_mapTask).toList();
  }

  Future<TaskItem?> _taskById(String id) async {
    final row = await (_db.select(
      _db.tasks,
    )..where((task) => task.id.equals(id))).getSingleOrNull();
    return row == null ? null : _mapTask(row);
  }

  TaskItem _mapTask(TaskRow row) => TaskItem(
    id: row.id,
    userId: row.userId,
    content: row.content,
    description: row.description,
    projectId: row.projectId,
    sectionId: row.sectionId,
    parentId: row.parentId,
    priority: row.priority,
    dueJson: row.dueJson,
    deadlineJson: row.deadlineJson,
    durationSeconds: row.durationSeconds,
    status: row.status,
    estimatedFocusIntervals: row.estimatedFocusIntervals,
    completedFocusIntervals: row.completedFocusIntervals,
    totalFocusSeconds: row.totalFocusSeconds,
    orderKey: row.orderKey,
    dayOrder: row.dayOrder,
    isCollapsed: row.isCollapsed,
    isDeleted: row.isDeleted,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    completedAt: row.completedAt,
  );

  String? _mergeWarning(String? existing, String? next) {
    if (next == null || next.trim().isEmpty) {
      return existing;
    }
    if (existing == null || existing.trim().isEmpty) {
      return next;
    }
    if (existing.contains(next)) {
      return existing;
    }
    return '$existing\n$next';
  }

  bool _shouldRecreateLinkedEvent(GoogleCalendarApiException error) {
    return error.message.toLowerCase().contains('invalid start time');
  }
}
