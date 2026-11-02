import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/data/repositories/tasks/task_blocking_repository.dart';
import 'package:pomodoist/domain/models/tasks/task_blocking.dart';

final taskBlockingRepositoryProvider = Provider(
  (ref) => DriftTaskBlockingRepository(
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

class InlineTaskDeleteRequests
    extends Notifier<Map<String, Future<void> Function()>> {
  @override
  Map<String, Future<void> Function()> build() => {};
  void request(String id, Future<void> Function() action) =>
      state = {...state, id: action};
  void clear(String id) => state = {...state}..remove(id);
}

final inlineTaskDeleteRequestsProvider =
    NotifierProvider<
      InlineTaskDeleteRequests,
      Map<String, Future<void> Function()>
    >(InlineTaskDeleteRequests.new);
