import 'package:uuid/uuid.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/services/local/sync_owner_store.dart';
import 'package:pomodoist/data/services/local/account_recovery_store.dart';

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

    final reset = await _store.db.transaction(() async {
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
      final recovery = AccountRecoveryStore(_store.db);
      if (reset) {
        // Unknown legacy ownership is retained but never assigned to a new user.
        await recovery.archiveInTransaction(owner?.cursor ?? 'legacy-unowned');
        check();
        await _store.reset();
      }
      check();
      await recovery.restoreInTransaction(userId);
      await _store.writeOwner(userId);
      check();
      await _store.backfill(userId);
      return reset;
    });
    if (reset) await onReset?.call();
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
    var attemptedReset = false;
    bool reset;
    try {
      reset = await db.transaction(() async {
        final owner = await store.owner();
        if (!current() || owner?.cursor == 'guest') return false;
        final reset = owner != null;
        final recovery = AccountRecoveryStore(db);
        if (reset) {
          attemptedReset = true;
          await recovery.archiveInTransaction(owner.cursor!);
          if (!current()) throw const _ObsoleteGuestPreparation();
          await store.reset();
        }
        // Roll back instead of committing an unbound or wrong-owner dataset.
        if (!current()) throw const _ObsoleteGuestPreparation();
        await recovery.restoreInTransaction('guest');
        await store.writeOwner('guest');
        return reset;
      });
    } on _ObsoleteGuestPreparation {
      reset = false;
    }
    if (reset || attemptedReset) await onReset?.call();
    return reset;
  });
}

class _ObsoleteGuestPreparation implements Exception {
  const _ObsoleteGuestPreparation();
}
