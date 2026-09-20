import 'package:uuid/uuid.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/services/local/sync_owner_store.dart';

/// Repository policy shared by foreground, background and guest startup.
class SyncOwnershipCoordinator {
  SyncOwnershipCoordinator(AppDatabase db, Uuid uuid, this._currentUserId)
    : _store = SyncOwnerStore(db, uuid);
  final SyncOwnerStore _store;
  final String? Function() _currentUserId;
  Future<bool> prepareAccount({Future<void> Function()? onReset}) async {
    final userId = _currentUserId();
    if (userId == null || userId.isEmpty) {
      throw StateError('Account sync requires an authenticated user.');
    }
    void check() {
      if (_currentUserId() != userId) {
        throw StateError('Account changed during local preparation.');
      }
    }

    final owner = await _store.owner();
    check();
    if (owner?.cursor == userId) {
      await _store.backfill(userId);
      return false;
    }
    final imported = await _store.state('pomodoist-import');
    final synced = await _store.state('pomodoist');
    check();
    final reset = owner != null || imported != null || synced != null;
    if (reset) {
      await onReset?.call();
      check();
      await _store.reset();
    }
    check();
    await _store.writeOwner(userId);
    check();
    await _store.backfill(userId);
    return reset;
  }

  static Future<bool> prepareGuestLocalData({
    required AppDatabase db,
    required Uuid uuid,
    bool Function()? shouldPrepare,
    Future<void> Function()? onReset,
  }) => SyncOwnerStore.serialized(db, () async {
    final store = SyncOwnerStore(db, uuid);
    bool current() => shouldPrepare?.call() ?? true;
    if (!current()) return false;
    final owner = await store.owner();
    if (!current() || owner?.cursor == 'guest') return false;
    final reset = owner != null;
    if (reset) {
      await onReset?.call();
      if (!current()) return false;
      await store.reset();
    }
    if (!current()) return false;
    await store.writeOwner('guest');
    return reset;
  });
}
