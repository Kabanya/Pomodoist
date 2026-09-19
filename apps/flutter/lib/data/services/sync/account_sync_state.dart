part of 'account_sync_engine.dart';

extension AccountSyncState on AccountSyncEngine {
  Future<String> deviceId() => _ensureDeviceId();

  DateTime _snapshotClockForLabel(LabelRow row) {
    const seeds = <String, ({String name, String systemKey, String orderKey})>{
      kanbanStatusBacklogId: (
        name: 'Backlog',
        systemKey: kanbanSystemKeyBacklog,
        orderKey: '00000000000000000000',
      ),
      kanbanStatusTodoId: (
        name: 'To do',
        systemKey: kanbanSystemKeyTodo,
        orderKey: '00000000000000001000',
      ),
      kanbanStatusInProgressId: (
        name: 'In progress',
        systemKey: kanbanSystemKeyInProgress,
        orderKey: '00000000000000002000',
      ),
      kanbanStatusDoneId: (
        name: 'Done',
        systemKey: kanbanSystemKeyDone,
        orderKey: '00004503599627370496',
      ),
    };
    final seed = seeds[row.id];
    final untouched =
        seed != null &&
        row.updatedAt == row.createdAt &&
        row.userId == localUserId &&
        row.name == seed.name &&
        row.color == null &&
        row.kind == labelKindKanbanStatus &&
        row.systemKey == seed.systemKey &&
        row.orderKey == seed.orderKey &&
        !row.isFavorite &&
        !row.isDeleted;
    if (untouched) {
      return AccountSyncEngine._seedSnapshotClock;
    }
    return row.updatedAt;
  }

  DateTime _snapshotClockForSettings(KanbanSettingsRow row) {
    final untouched =
        row.updatedAt == row.createdAt &&
        row.userId == localUserId &&
        row.selectedProjectIdsJson == jsonEncode([inboxProjectId]) &&
        row.focusStatusLabelId == kanbanStatusInProgressId;
    return untouched ? AccountSyncEngine._seedSnapshotClock : row.updatedAt;
  }

  Future<SyncStateRow?> _syncState() {
    return (_db.select(_db.syncState)
          ..where((row) => row.id.equals(AccountSyncEngine._syncStateId)))
        .getSingleOrNull();
  }

  Future<String> _ensureDeviceId() async {
    final state = await _syncState();
    if (state != null) {
      return state.deviceId;
    }
    final now = DateTime.now().toUtc();
    final deviceId = _uuid.v4();
    await _db
        .into(_db.syncState)
        .insert(
          SyncStateCompanion.insert(
            id: AccountSyncEngine._syncStateId,
            deviceId: deviceId,
            createdAt: now,
            updatedAt: now,
          ),
        );
    return deviceId;
  }

  Future<void> _saveCursor(int cursor) async {
    final now = DateTime.now().toUtc();
    final state = await _syncState();
    if (state == null) {
      await _db
          .into(_db.syncState)
          .insert(
            SyncStateCompanion.insert(
              id: AccountSyncEngine._syncStateId,
              deviceId: _uuid.v4(),
              cursor: Value('$cursor'),
              lastPulledAt: Value(now),
              createdAt: now,
              updatedAt: now,
            ),
          );
      return;
    }
    await (_db.update(
      _db.syncState,
    )..where((row) => row.id.equals(AccountSyncEngine._syncStateId))).write(
      SyncStateCompanion(
        cursor: Value('$cursor'),
        lastPulledAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }

  Future<void> _broadcastSyncHint() async {
    try {
      await _account
          .broadcastSyncHint(
            appId: AccountAppId.pomodoist,
            deviceId: await _ensureDeviceId(),
          )
          .timeout(_requestTimeout);
    } on Object {
      // Realtime hints only accelerate the next pull; persisted sync succeeded.
    }
  }
}
