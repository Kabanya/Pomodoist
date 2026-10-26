import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';

/// Shared Focus owns the adopted run's writes. Keep its local history until the
/// authoritative history arrives, without retrying superseded outbox writes.
Future<void> acknowledgeAdoptedFocusRun(AppDatabase db, String runId) async {
  if (runId.isEmpty) throw ArgumentError.value(runId, 'runId');
  await db.transaction(() async {
    final intervals =
        (await (db.select(
              db.focusIntervals,
            )..where((row) => row.runId.equals(runId))).get())
            .map((row) => row.id)
            .toSet();
    final events =
        (await (db.select(
              db.focusEvents,
            )..where((row) => row.runId.equals(runId))).get())
            .map((row) => row.id)
            .toSet();

    bool belongs(String type, Object? id, Map payload) {
      if (type == 'focus_run') return id == runId;
      if (type != 'focus_interval' && type != 'focus_event') return false;
      if (payload.containsKey('runId')) return payload['runId'] == runId;
      if (type == 'focus_interval') return intervals.contains(id);
      return events.contains(id) || intervals.contains(payload['intervalId']);
    }

    bool lifecycle(SyncCommandRow command, Map payload) {
      if (command.type.startsWith('focus.run.')) {
        return belongs(
          'focus_run',
          payload['id'] ?? payload['runId'] ?? command.clientId,
          payload,
        );
      }
      if (command.type.startsWith('focus.interval.')) {
        return belongs(
          'focus_interval',
          payload['id'] ?? payload['intervalId'] ?? command.clientId,
          payload,
        );
      }
      if (command.type != 'focus.distraction.log') return false;
      if (payload.containsKey('runId')) return payload['runId'] == runId;
      if (payload.containsKey('id')) {
        return belongs('focus_event', payload['id'], payload);
      }
      return command.clientId == runId ||
          belongs('focus_event', command.clientId, payload);
    }

    final commands = await (db.select(
      db.syncCommands,
    )..where((row) => row.status.isNotIn(['synced', 'compacted']))).get();
    final now = DateTime.now().toUtc();
    for (final command in commands) {
      Object? decoded;
      try {
        decoded = jsonDecode(command.payloadJson);
      } on FormatException {
        continue;
      }
      if (decoded is! Map) continue;
      final payload = Map<String, dynamic>.from(decoded);
      var retire = false;
      if (payload.containsKey('_syncOperationsV1')) {
        final operations = payload['_syncOperationsV1'];
        if (operations is! List) continue;
        final retained = operations.where((operation) {
          if (operation is! Map ||
              operation['entityType'] is! String ||
              operation['payload'] is! Map) {
            return true;
          }
          return !belongs(
            operation['entityType'] as String,
            operation['entityId'],
            operation['payload'] as Map,
          );
        }).toList();
        if (retained.length == operations.length) continue;
        retire = retained.isEmpty;
        if (!retire) {
          await (db.update(
            db.syncCommands,
          )..where((row) => row.id.equals(command.id))).write(
            SyncCommandsCompanion(
              payloadJson: Value(
                jsonEncode({...payload, '_syncOperationsV1': retained}),
              ),
            ),
          );
        }
      } else {
        retire = lifecycle(command, payload);
      }
      if (retire) {
        await (db.update(
          db.syncCommands,
        )..where((row) => row.id.equals(command.id))).write(
          SyncCommandsCompanion(
            status: const Value('synced'),
            lastError: const Value(null),
            updatedAt: Value(now),
          ),
        );
      }
    }
  });
}

/// Export terminal history before the server takes ownership of a local run.
Future<Map<String, dynamic>> exportFocusAdoptionHistory(
  AppDatabase db,
  String runId,
  String currentIntervalId,
) => db.transaction(() async {
  final intervals =
      await (db.select(db.focusIntervals)
            ..where(
              (r) =>
                  r.runId.equals(runId) & r.id.equals(currentIntervalId).not(),
            )
            ..orderBy([(r) => OrderingTerm.asc(r.sequenceNumber)]))
          .get();
  final events =
      await (db.select(db.focusEvents)
            ..where((r) => r.runId.equals(runId))
            ..orderBy([
              (r) => OrderingTerm.asc(r.occurredAt),
              (r) => OrderingTerm.asc(r.id),
            ]))
          .get();
  return {
    'intervals': [
      for (final r in intervals)
        {
          ...r.toJson(),
          'startedAt': r.startedAt.toUtc().toIso8601String(),
          'pausedAt': r.pausedAt?.toUtc().toIso8601String(),
          'completedAt': r.completedAt?.toUtc().toIso8601String(),
          'stoppedAt': r.stoppedAt?.toUtc().toIso8601String(),
          'createdAt': r.createdAt.toUtc().toIso8601String(),
          'updatedAt': r.updatedAt.toUtc().toIso8601String(),
        },
    ],
    'events': [
      for (final r in events)
        {
          ...r.toJson(),
          'occurredAt': r.occurredAt.toUtc().toIso8601String(),
          'createdAt': r.createdAt.toUtc().toIso8601String(),
        },
    ],
  };
});
