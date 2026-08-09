import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../db/app_database.dart';

class SyncQueueCommand {
  const SyncQueueCommand({
    required this.type,
    required this.payload,
    this.clientId,
  });

  final String type;
  final Map<String, Object?> payload;
  final String? clientId;
}

abstract interface class SyncQueueRepository {
  Future<void> enqueue({
    required String type,
    required Map<String, Object?> payload,
    String? clientId,
  });

  Future<void> enqueueBatch(
    List<SyncQueueCommand> commands, {
    DateTime? occurredAt,
  });

  Stream<List<SyncCommandRow>> watchPending();
}

class DriftSyncQueueRepository implements SyncQueueRepository {
  DriftSyncQueueRepository(this._db, {Uuid? uuid})
    : _uuid = uuid ?? const Uuid();

  final AppDatabase _db;
  final Uuid _uuid;

  @override
  Future<void> enqueue({
    required String type,
    required Map<String, Object?> payload,
    String? clientId,
  }) async {
    await enqueueBatch([
      SyncQueueCommand(type: type, payload: payload, clientId: clientId),
    ]);
  }

  @override
  Future<void> enqueueBatch(
    List<SyncQueueCommand> commands, {
    DateTime? occurredAt,
  }) async {
    if (commands.isEmpty) {
      return;
    }
    final mutationTime = (occurredAt ?? DateTime.now()).toUtc();
    final requestedStart = DateTime.fromMillisecondsSinceEpoch(
      (mutationTime.millisecondsSinceEpoch ~/ 1000) * 1000,
      isUtc: true,
    );
    final latest =
        await (_db.select(_db.syncCommands)
              ..orderBy([(row) => OrderingTerm.desc(row.createdAt)])
              ..limit(1))
            .getSingleOrNull();
    final start = latest != null && !latest.createdAt.isBefore(requestedStart)
        ? latest.createdAt.add(const Duration(seconds: 1))
        : requestedStart;
    await _db.batch((batch) {
      batch.insertAll(_db.syncCommands, [
        for (var index = 0; index < commands.length; index++)
          SyncCommandsCompanion.insert(
            id: _uuid.v4(),
            uuid: _uuid.v4(),
            type: commands[index].type,
            clientId: Value(commands[index].clientId),
            payloadJson: jsonEncode(commands[index].payload),
            createdAt: start.add(Duration(seconds: index)),
            updatedAt: mutationTime,
          ),
      ]);
    });
  }

  @override
  Stream<List<SyncCommandRow>> watchPending() {
    final query = _db.select(_db.syncCommands)
      ..where((command) => command.status.equals('pending'))
      ..orderBy([(command) => OrderingTerm.asc(command.createdAt)]);
    return query.watch();
  }
}
