import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/data/services/local/task_blocking_store.dart';
import 'package:pomodoist/domain/models/tasks/task_blocking.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';

final taskBlockingRepositoryProvider = Provider(
  (ref) => TaskBlockingStore(
    ref.watch(appDatabaseProvider),
    ref.watch(syncQueueRepositoryProvider),
  ),
);
final taskBlockingPolicyProvider =
    StreamProvider.autoDispose<TaskBlockingPolicy>(
      (ref) => ref.watch(taskBlockingRepositoryProvider).watchPolicy(),
    );

final taskBlockingConflictsProvider = StreamProvider.autoDispose<Set<String>>((
  ref,
) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.syncCommands)..where(
        (r) => r.status.equals('rejected') & r.lastError.like('task_blocked%'),
      ))
      .watch()
      .map(
        (rows) => {
          for (final row in rows) ...[
            if (row.clientId != null) row.clientId!,
            for (final op
                in (jsonDecode(row.payloadJson) as Map)['_syncOperationsV1']
                        as List? ??
                    const [])
              if (op['entityType'] == 'task' && op['entityId'] is String)
                op['entityId'] as String,
          ],
        },
      );
});

final taskBlockingActionsProvider = Provider((ref) {
  final store = ref.watch(taskBlockingRepositoryProvider);
  return (
    setCascade: store.setCascade,
    setUrgent:
        (TaskItem task, {required bool urgent, bool repeatWithSeries = true}) =>
            store.setUrgent(
              task,
              urgent: urgent,
              repeatWithSeries: repeatWithSeries,
            ),
  );
});
