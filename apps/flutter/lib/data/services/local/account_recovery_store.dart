import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';

/// Durable account snapshots. Call archive/restore inside the owner transaction.
class AccountRecoveryStore {
  AccountRecoveryStore(this.db);
  final AppDatabase db;

  // Explicit allowlist: never execute a table/column name read from a snapshot.
  static const tables = [
    'users',
    'workspaces',
    'projects',
    'sections',
    'tasks',
    'task_completions',
    'labels',
    'task_labels',
    'kanban_settings',
    'filters',
    'reminders',
    'focus_presets',
    'focus_runs',
    'focus_intervals',
    'focus_events',
    'focus_daily_stats',
    'sync_commands',
    'sync_state',
    'calendar_projections',
    'google_calendar_connections',
    'google_calendar_event_links',
    'id_mappings',
    'habits',
    'habit_check_ins',
    'shared_scopes',
    'shared_entities',
  ];

  Future<void> archiveInTransaction(String ownerId) async {
    if (await (db.select(
          db.accountRecoverySnapshots,
        )..where((r) => r.ownerId.equals(ownerId))).getSingleOrNull() !=
        null) {
      throw StateError('An unrestored account snapshot already exists.');
    }
    final data = <String, Object?>{};
    for (final table in tables) {
      data[table] = (await db.customSelect('SELECT * FROM "$table"').get())
          .map((r) => r.data)
          .toList();
    }
    await db
        .into(db.accountRecoverySnapshots)
        .insert(
          AccountRecoverySnapshotsCompanion.insert(
            ownerId: ownerId,
            schemaVersion: db.schemaVersion,
            payloadJson: jsonEncode({
              'version': 1,
              'owner': ownerId,
              'tables': data,
            }),
            createdAt: DateTime.now().toUtc(),
          ),
        );
  }

  Future<AccountRecoveryData?> legacyData() async {
    final snapshot = await (db.select(
      db.accountRecoverySnapshots,
    )..where((r) => r.ownerId.equals('legacy-unowned'))).getSingleOrNull();
    if (snapshot == null) return null;
    final payload = jsonDecode(snapshot.payloadJson) as Map<String, dynamic>;
    if (payload['version'] != 1 ||
        payload['owner'] != 'legacy-unowned' ||
        snapshot.schemaVersion < 11 ||
        snapshot.schemaVersion > db.schemaVersion) {
      throw const FormatException('Unsupported legacy recovery snapshot');
    }
    return AccountRecoveryData(snapshot, payload);
  }

  Future<bool> restoreInTransaction(String ownerId) async {
    final snapshot = await (db.select(
      db.accountRecoverySnapshots,
    )..where((r) => r.ownerId.equals(ownerId))).getSingleOrNull();
    if (snapshot == null) return false;
    final payload = jsonDecode(snapshot.payloadJson) as Map<String, dynamic>;
    if (payload['version'] != 1 ||
        payload['owner'] != ownerId ||
        snapshot.schemaVersion < 11 ||
        snapshot.schemaVersion > db.schemaVersion) {
      throw StateError('Unsupported account recovery snapshot.');
    }
    final data = (payload['tables'] as Map).cast<String, dynamic>();
    final sharedProjects = <Object?>{};
    final sharedTasks = <Object?>{};
    for (final row in data['projects'] as List) {
      if (row['scope_id'] != null) sharedProjects.add(row['id']);
    }
    for (final row in data['tasks'] as List) {
      if (row['scope_id'] != null ||
          sharedProjects.contains(row['project_id'])) {
        sharedTasks.add(row['id']);
      }
    }
    for (final name in tables) {
      final table = db.allTables.singleWhere((t) => t.actualTableName == name);
      final columns = table.$columns.map((c) => c.$name).toSet();
      // Snapshots from schema 11/12 predate generic calendar projections.
      final rows = name == 'calendar_projections' && data[name] == null
          ? const []
          : data[name] as List;
      for (final raw in rows) {
        final row = (raw as Map).cast<String, Object?>();
        // Shared cache is fetched again after membership validation. Keep the
        // original scoped commands, which the shared sync permission gate owns.
        if (name == 'shared_scopes') continue;
        if (name != 'sync_commands' &&
            (row['scope_id'] != null && row['scope_id'] != '_account' ||
                !name.startsWith('focus_') &&
                    (sharedProjects.contains(row['project_id']) ||
                        sharedTasks.contains(row['task_id'])))) {
          continue;
        }
        if (!columns.containsAll(row.keys)) {
          throw StateError('Unknown account recovery columns.');
        }
        final keys = row.keys.toList();
        await db.customStatement(
          'INSERT OR REPLACE INTO "$name" '
          '(${keys.map((k) => '"$k"').join(',')}) '
          'VALUES (${keys.map((_) => '?').join(',')})',
          keys.map((k) => row[k]).toList(),
        );
      }
    }
    // A signed-out interval must never count as uninterrupted focus time.
    await (db.update(db.focusIntervals)..where(
          (r) =>
              r.status.equals('running') &
              r.completedAt.isNull() &
              r.stoppedAt.isNull(),
        ))
        .write(
          FocusIntervalsCompanion(
            status: const Value('paused'),
            pausedAt: Value(snapshot.createdAt),
          ),
        );
    await (db.update(db.focusRuns)..where((r) => r.status.equals('active')))
        .write(const FocusRunsCompanion(status: Value('paused')));
    for (final table in db.allTables) {
      if (tables.contains(table.actualTableName)) {
        db.notifyUpdates({TableUpdate.onTable(table)});
      }
    }
    await discardOwner(ownerId);
    return true;
  }

  Future<void> discardOwner(
    String ownerId, {
    bool includeRecoveredLegacy = false,
  }) =>
      (db.delete(db.accountRecoverySnapshots)..where(
            (r) =>
                r.ownerId.equals(ownerId) |
                (includeRecoveredLegacy
                    ? r.ownerId.like('legacy-recovered:$ownerId:%')
                    : const Constant(false)),
          ))
          .go();
}

/// Read typed rows without inserting archived state into the active database.
class AccountRecoveryData {
  AccountRecoveryData(this.snapshot, this.payload);
  final AccountRecoverySnapshotRow snapshot;
  final Map<String, dynamic> payload;
  String get fingerprint => const Uuid().v5(
    Namespace.url.value,
    jsonEncode([
      snapshot.schemaVersion,
      snapshot.createdAt.toIso8601String(),
      payload['tables'],
    ]),
  );

  Future<List<D>> rows<T extends Table, D>(TableInfo<T, D> table) async {
    if (!AccountRecoveryStore.tables.contains(table.actualTableName)) {
      throw const FormatException('Unsupported recovery table');
    }
    final data = payload['tables'] as Map;
    final raw = data[table.actualTableName];
    if (raw is! List) throw const FormatException('Missing recovery table');
    final columns = table.$columns.map((c) => c.$name).toSet();
    return Future.wait(
      raw.map((value) async {
        final row = Map<String, dynamic>.from(value as Map);
        if (!columns.containsAll(row.keys)) {
          throw const FormatException('Unknown recovery columns');
        }
        if (table.actualTableName == 'tasks') {
          row.putIfAbsent('is_focus_estimate_manual', () => 0);
        }
        return table.map(row);
      }),
    );
  }
}
