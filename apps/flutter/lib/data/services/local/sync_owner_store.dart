import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';

class SyncOwnerStore {
  SyncOwnerStore(this.db, this.uuid);
  final AppDatabase db;
  final Uuid uuid;
  static final _queues = Expando<_SerialQueue>();
  static Future<T> serialized<T>(AppDatabase db, Future<T> Function() action) =>
      (_queues[db] ??= _SerialQueue()).run(action);
  Future<SyncStateRow?> owner() => state('pomodoist-account-owner-v1');
  Future<SyncStateRow?> state(String id) => (db.select(
    db.syncState,
  )..where((r) => r.id.equals(id))).getSingleOrNull();
  Future<void> reset() => db.resetAccountData();
  Future<void> backfill(String id) =>
      db.backfillTaskCreators(accountUserId: id);
  Future<void> writeOwner(String id) async {
    final now = DateTime.now().toUtc();
    await db
        .into(db.syncState)
        .insertOnConflictUpdate(
          SyncStateCompanion.insert(
            id: 'pomodoist-account-owner-v1',
            deviceId: uuid.v4(),
            cursor: Value(id),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }
}

class _SerialQueue {
  Future<void> _tail = Future.value();
  Future<T> run<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}
