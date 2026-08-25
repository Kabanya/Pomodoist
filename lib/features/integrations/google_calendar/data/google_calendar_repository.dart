import 'package:drift/drift.dart';

import '../../../../core/db/app_database.dart';
import '../../../../core/sync/sync_queue_repository.dart';
import 'google_calendar_config.dart';

abstract interface class CalendarIntegrationRepository {
  Stream<GoogleCalendarConnectionRow?> watchConnection();
  Stream<GoogleCalendarEventLinkRow?> watchLinkForTask(String taskId);
  Future<GoogleCalendarConnectionRow?> getConnection();
  Future<GoogleCalendarConnectionRow> ensureConnection();
  Future<void> saveConnected({
    String? accountEmail,
    required String calendarId,
    required String calendarName,
    String? ownerDeviceId,
  });
  Future<void> claimOwnerDevice(String ownerDeviceId);
  Future<void> markSyncStarted();
  Future<void> markSyncFinished({String? syncToken, String? warning});
  Future<void> markError(Object error);
  Future<void> disconnect();
  Future<GoogleCalendarEventLinkRow?> linkForTask(String taskId);
  Future<GoogleCalendarEventLinkRow?> linkForEvent(String eventId);
  Future<List<GoogleCalendarEventLinkRow>> links();
  Future<void> upsertLink({
    required String taskId,
    required String calendarId,
    required String eventId,
    String? etag,
    DateTime? googleUpdatedAt,
    DateTime? lastSyncedLocalUpdatedAt,
    String? unsupportedReason,
  });
  Future<void> deleteLink(String taskId);
}

class DriftCalendarIntegrationRepository
    implements CalendarIntegrationRepository {
  DriftCalendarIntegrationRepository(this._db, {SyncQueueRepository? syncQueue})
    : _syncQueue = syncQueue;

  final AppDatabase _db;
  final SyncQueueRepository? _syncQueue;

  @override
  Stream<GoogleCalendarConnectionRow?> watchConnection() {
    final query = _db.select(_db.googleCalendarConnections)
      ..where((row) => row.id.equals(GoogleCalendarConfig.connectionId));
    return query.watchSingleOrNull();
  }

  @override
  Stream<GoogleCalendarEventLinkRow?> watchLinkForTask(String taskId) {
    final query = _db.select(_db.googleCalendarEventLinks)
      ..where((row) => row.taskId.equals(taskId));
    return query.watchSingleOrNull();
  }

  @override
  Future<GoogleCalendarConnectionRow?> getConnection() {
    final query = _db.select(_db.googleCalendarConnections)
      ..where((row) => row.id.equals(GoogleCalendarConfig.connectionId));
    return query.getSingleOrNull();
  }

  @override
  Future<GoogleCalendarConnectionRow> ensureConnection() async {
    final existing = await getConnection();
    if (existing != null) {
      return existing;
    }
    final now = DateTime.now().toUtc();
    await _db
        .into(_db.googleCalendarConnections)
        .insert(
          GoogleCalendarConnectionsCompanion.insert(
            id: GoogleCalendarConfig.connectionId,
            createdAt: now,
            updatedAt: now,
          ),
        );
    return (await getConnection())!;
  }

  @override
  Future<void> saveConnected({
    String? accountEmail,
    required String calendarId,
    required String calendarName,
    String? ownerDeviceId,
  }) async {
    await ensureConnection();
    final now = DateTime.now().toUtc();
    await (_db.update(
      _db.googleCalendarConnections,
    )..where((row) => row.id.equals(GoogleCalendarConfig.connectionId))).write(
      GoogleCalendarConnectionsCompanion(
        accountEmail: Value(accountEmail),
        calendarId: Value(calendarId),
        ownerDeviceId: ownerDeviceId == null
            ? const Value.absent()
            : Value(ownerDeviceId),
        calendarName: Value(calendarName),
        status: const Value('connected'),
        lastError: const Value(null),
        updatedAt: Value(now),
      ),
    );
    await _enqueueConnection();
  }

  @override
  Future<void> claimOwnerDevice(String ownerDeviceId) async {
    await ensureConnection();
    final now = DateTime.now().toUtc();
    await (_db.update(
      _db.googleCalendarConnections,
    )..where((row) => row.id.equals(GoogleCalendarConfig.connectionId))).write(
      GoogleCalendarConnectionsCompanion(
        ownerDeviceId: Value(ownerDeviceId),
        updatedAt: Value(now),
      ),
    );
    await _enqueueConnection();
  }

  @override
  Future<void> markSyncStarted() async {
    await ensureConnection();
    final now = DateTime.now().toUtc();
    await (_db.update(
      _db.googleCalendarConnections,
    )..where((row) => row.id.equals(GoogleCalendarConfig.connectionId))).write(
      GoogleCalendarConnectionsCompanion(
        status: const Value('syncing'),
        lastSyncStartedAt: Value(now),
        lastError: const Value(null),
        updatedAt: Value(now),
      ),
    );
    await _enqueueConnection();
  }

  @override
  Future<void> markSyncFinished({String? syncToken, String? warning}) async {
    await ensureConnection();
    final now = DateTime.now().toUtc();
    await (_db.update(
      _db.googleCalendarConnections,
    )..where((row) => row.id.equals(GoogleCalendarConfig.connectionId))).write(
      GoogleCalendarConnectionsCompanion(
        syncToken: syncToken == null ? const Value.absent() : Value(syncToken),
        status: const Value('connected'),
        warning: Value(warning),
        lastSyncFinishedAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    await _enqueueConnection();
  }

  @override
  Future<void> markError(Object error) async {
    await ensureConnection();
    final now = DateTime.now().toUtc();
    await (_db.update(
      _db.googleCalendarConnections,
    )..where((row) => row.id.equals(GoogleCalendarConfig.connectionId))).write(
      GoogleCalendarConnectionsCompanion(
        status: const Value('error'),
        lastError: Value('$error'),
        lastSyncFinishedAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    await _enqueueConnection();
  }

  @override
  Future<void> disconnect() async {
    await ensureConnection();
    final existingLinks = await links();
    final now = DateTime.now().toUtc();
    await _db.transaction(() async {
      await _db.delete(_db.googleCalendarEventLinks).go();
      await (_db.update(_db.googleCalendarConnections)
            ..where((row) => row.id.equals(GoogleCalendarConfig.connectionId)))
          .write(
            GoogleCalendarConnectionsCompanion(
              accountEmail: const Value(null),
              calendarId: const Value(null),
              ownerDeviceId: const Value(null),
              syncToken: const Value(null),
              status: const Value('disconnected'),
              lastError: const Value(null),
              warning: const Value(null),
              updatedAt: Value(now),
            ),
          );
    });
    for (final link in existingLinks) {
      await _enqueueLinkDelete(link);
    }
    await _enqueueConnection();
  }

  @override
  Future<GoogleCalendarEventLinkRow?> linkForTask(String taskId) {
    final query = _db.select(_db.googleCalendarEventLinks)
      ..where((row) => row.taskId.equals(taskId));
    return query.getSingleOrNull();
  }

  @override
  Future<GoogleCalendarEventLinkRow?> linkForEvent(String eventId) {
    final query = _db.select(_db.googleCalendarEventLinks)
      ..where((row) => row.eventId.equals(eventId))
      ..orderBy([
        (row) => OrderingTerm.asc(row.createdAt),
        (row) => OrderingTerm.asc(row.taskId),
      ])
      ..limit(1);
    return query.getSingleOrNull();
  }

  @override
  Future<List<GoogleCalendarEventLinkRow>> links() {
    return _db.select(_db.googleCalendarEventLinks).get();
  }

  @override
  Future<void> upsertLink({
    required String taskId,
    required String calendarId,
    required String eventId,
    String? etag,
    DateTime? googleUpdatedAt,
    DateTime? lastSyncedLocalUpdatedAt,
    String? unsupportedReason,
  }) async {
    final existing = await linkForTask(taskId);
    final normalizedGoogleUpdatedAt = googleUpdatedAt?.toUtc();
    final normalizedLocalUpdatedAt = lastSyncedLocalUpdatedAt?.toUtc();
    if (existing != null &&
        existing.calendarId == calendarId &&
        existing.eventId == eventId &&
        existing.etag == etag &&
        existing.googleUpdatedAt == normalizedGoogleUpdatedAt &&
        existing.lastSyncedLocalUpdatedAt == normalizedLocalUpdatedAt &&
        existing.unsupportedReason == unsupportedReason) {
      return;
    }
    final now = DateTime.now().toUtc();
    await _db
        .into(_db.googleCalendarEventLinks)
        .insertOnConflictUpdate(
          GoogleCalendarEventLinksCompanion.insert(
            taskId: taskId,
            calendarId: calendarId,
            eventId: eventId,
            etag: Value(etag),
            googleUpdatedAt: Value(normalizedGoogleUpdatedAt),
            lastSyncedLocalUpdatedAt: Value(normalizedLocalUpdatedAt),
            unsupportedReason: Value(unsupportedReason),
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
          ),
        );
    await _enqueueLink(taskId);
  }

  @override
  Future<void> deleteLink(String taskId) async {
    final existing = await linkForTask(taskId);
    await (_db.delete(
      _db.googleCalendarEventLinks,
    )..where((row) => row.taskId.equals(taskId))).go();
    if (existing != null) {
      await _enqueueLinkDelete(existing);
    }
  }

  Future<void> _enqueueConnection() async {
    final syncQueue = _syncQueue;
    if (syncQueue == null) {
      return;
    }
    final row = await getConnection();
    if (row == null) {
      return;
    }
    await syncQueue.enqueue(
      type: 'google_calendar.connection.upsert',
      clientId: row.id,
      payload: row.toJson(),
    );
  }

  Future<void> _enqueueLink(String taskId) async {
    final syncQueue = _syncQueue;
    if (syncQueue == null) {
      return;
    }
    final row = await linkForTask(taskId);
    if (row == null) {
      return;
    }
    await syncQueue.enqueue(
      type: 'google_calendar.link.upsert',
      clientId: row.taskId,
      payload: row.toJson(),
    );
  }

  Future<void> _enqueueLinkDelete(GoogleCalendarEventLinkRow row) async {
    final syncQueue = _syncQueue;
    if (syncQueue == null) {
      return;
    }
    await syncQueue.enqueue(
      type: 'google_calendar.link.delete',
      clientId: row.taskId,
      payload: row.toJson(),
    );
  }
}
