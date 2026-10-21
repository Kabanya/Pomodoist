import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/domain/models/focus/focus_models.dart';
import 'pomo_activity_repository.dart';

class LocalPomoActivityRepository implements PomoActivityRepository {
  LocalPomoActivityRepository(this._db);
  final AppDatabase _db;
  @override
  Stream<List<FocusIntervalItem>> watchSinceBreak() => _db
      .customSelect(
        '''
    SELECT * FROM focus_intervals
    WHERE is_deleted = 0 AND type = 'work'
      AND started_at >= COALESCE((
        SELECT MAX(completed_at) FROM focus_intervals
        WHERE is_deleted = 0 AND type != 'work' AND status = 'completed'
      ), 0)
    ORDER BY started_at
    ''',
        readsFrom: {_db.focusIntervals},
      )
      .watch()
      .map(
        (rows) => [
          for (final result in rows) _map(_db.focusIntervals.map(result.data)),
        ],
      );
  FocusIntervalItem _map(FocusIntervalRow row) => FocusIntervalItem(
    id: row.id,
    runId: row.runId,
    taskId: row.taskId,
    projectId: row.projectId,
    type: row.type,
    status: row.status,
    plannedSeconds: row.plannedSeconds,
    startedAt: row.startedAt,
    pausedAt: row.pausedAt,
    pausedTotalSeconds: row.pausedTotalSeconds,
    completedAt: row.completedAt,
    stoppedAt: row.stoppedAt,
    sequenceNumber: row.sequenceNumber,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );
}
