import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/services/local/shared_access.dart';
import 'package:pomodoist/data/services/sync/account_sync_mapping.dart';

class SyncQueueCommand {
  const SyncQueueCommand({
    required this.type,
    required this.payload,
    this.clientId,
    this.availableAt,
  });

  final String type;
  final Map<String, Object?> payload;
  final String? clientId;
  final DateTime? availableAt;
}

abstract interface class OutboxService {
  Future<void> enqueue({
    required String type,
    required Map<String, Object?> payload,
    String? clientId,
    DateTime? availableAt,
  });

  Future<void> enqueueBatch(
    List<SyncQueueCommand> commands, {
    DateTime? occurredAt,
  });

  Stream<List<SyncCommandRow>> watchPending();
}

class DriftOutboxService implements OutboxService {
  DriftOutboxService(this._db, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final AppDatabase _db;
  final Uuid _uuid;

  @override
  Future<void> enqueue({
    required String type,
    required Map<String, Object?> payload,
    String? clientId,
    DateTime? availableAt,
  }) async {
    await enqueueBatch([
      SyncQueueCommand(
        type: type,
        payload: payload,
        clientId: clientId,
        availableAt: availableAt,
      ),
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
    final latestConnectionClients = <String>{};
    final retainedCommands = commands.reversed
        .where((command) {
          final clientId = command.clientId;
          return command.type != 'google_calendar.connection.upsert' ||
              clientId == null ||
              latestConnectionClients.add(clientId);
        })
        .toList()
        .reversed
        .toList();
    await _db.transaction(() async {
      for (final clientId in latestConnectionClients) {
        await (_db.delete(_db.syncCommands)..where(
              (row) =>
                  row.type.equals('google_calendar.connection.upsert') &
                  row.clientId.equals(clientId) &
                  row.status.equals('pending'),
            ))
            .go();
      }
      final expanded = <SyncQueueCommand>[];
      for (final command in retainedCommands) {
        final scopeId = await SharedAccess(
          _db,
        ).commandScope(command.type, command.clientId, command.payload);
        if (scopeId != null &&
            {'task.update', 'project.update'}.contains(command.type)) {
          final private = <String, Object?>{
            for (final key in [
              'isFavorite',
              'isCollapsed',
              'dayOrder',
              'viewStyle',
            ])
              if (command.payload.containsKey(key)) key: command.payload[key],
          };
          if (private.isNotEmpty) {
            expanded.add(
              SyncQueueCommand(
                type: 'private.preferences',
                clientId: command.clientId,
                payload: {
                  'scopeId': scopeId,
                  'entityType': command.type.split('.').first,
                  'entityId': command.clientId,
                  'data': private,
                },
              ),
            );
            final public = Map<String, Object?>.from(command.payload)
              ..removeWhere((key, _) => private.containsKey(key));
            if (public.keys.any((key) => !{'id', 'scopeId'}.contains(key))) {
              expanded.add(
                SyncQueueCommand(
                  type: command.type,
                  clientId: command.clientId,
                  payload: public,
                  availableAt: command.availableAt,
                ),
              );
            }
            continue;
          }
        }
        if (scopeId != null &&
            command.type.endsWith('.create') &&
            command.clientId != null) {
          final type = syncEntityTypeForCommand(command.type);
          Map<String, Object?>? snapshot;
          switch (type) {
            case 'task':
              snapshot =
                  (await (_db.select(_db.tasks)
                            ..where((row) => row.id.equals(command.clientId!)))
                          .getSingleOrNull())
                      ?.toJson();
            case 'project':
              snapshot =
                  (await (_db.select(_db.projects)
                            ..where((row) => row.id.equals(command.clientId!)))
                          .getSingleOrNull())
                      ?.toJson();
            case 'label':
              snapshot =
                  (await (_db.select(_db.labels)
                            ..where((row) => row.id.equals(command.clientId!)))
                          .getSingleOrNull())
                      ?.toJson();
            case 'section':
              snapshot =
                  (await (_db.select(_db.sections)
                            ..where((row) => row.id.equals(command.clientId!)))
                          .getSingleOrNull())
                      ?.toJson();
          }
          if (snapshot != null) {
            expanded.add(
              SyncQueueCommand(
                type: command.type,
                clientId: command.clientId,
                availableAt: command.availableAt,
                payload: {
                  ...snapshot,
                  for (final key in ['recurrenceSourceId', 'occurrenceKey'])
                    if (command.payload.containsKey(key))
                      key: command.payload[key],
                },
              ),
            );
            continue;
          }
        }
        expanded.add(command);
      }
      retainedCommands
        ..clear()
        ..addAll(expanded);
      final latest =
          await (_db.select(_db.syncCommands)
                ..orderBy([(row) => OrderingTerm.desc(row.createdAt)])
                ..limit(1))
              .getSingleOrNull();
      final start = latest != null && !latest.createdAt.isBefore(requestedStart)
          ? latest.createdAt.add(const Duration(seconds: 1))
          : requestedStart;
      final scopeByCommand = <SyncQueueCommand, String?>{};
      final revisionByCommand = <SyncQueueCommand, int>{};
      final sharedAccess = SharedAccess(_db);
      for (final command in retainedCommands) {
        final scopeId = await sharedAccess.commandScope(
          command.type,
          command.clientId,
          command.payload,
        );
        scopeByCommand[command] = scopeId;
        if (scopeId == null) continue;
        if (command.type != 'private.preferences') {
          await sharedAccess.requireEdit(scopeId);
        } else if (await sharedAccess.scope(scopeId) == null) {
          throw StateError('Shared access revoked');
        }
        final entityType = syncEntityTypeForCommand(command.type);
        final entityId = syncEntityIdForCommand(
          (id: command.clientId ?? '', clientId: command.clientId, uuid: ''),
          command.payload,
          entityType,
        );
        final base =
            await (_db.select(_db.sharedEntities)..where(
                  (row) =>
                      row.scopeId.equals(scopeId) &
                      row.entityType.equals(entityType) &
                      row.entityId.equals(entityId),
                ))
                .getSingleOrNull();
        revisionByCommand[command] = base?.serverRevision ?? 0;
      }
      await _db.batch((batch) {
        batch.insertAll(_db.syncCommands, [
          for (var index = 0; index < retainedCommands.length; index++)
            SyncCommandsCompanion.insert(
              id: _uuid.v4(),
              uuid: _uuid.v4(),
              type: retainedCommands[index].type,
              scopeId: Value(scopeByCommand[retainedCommands[index]]),
              baseRevision: Value(
                revisionByCommand[retainedCommands[index]] ?? 0,
              ),
              clientId: Value(retainedCommands[index].clientId),
              payloadJson: jsonEncode(retainedCommands[index].payload),
              createdAt: start.add(Duration(seconds: index)),
              updatedAt: mutationTime,
              availableAt: Value(retainedCommands[index].availableAt?.toUtc()),
            ),
        ]);
      });
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
