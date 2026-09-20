import 'package:drift/drift.dart';

import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/domain/models/focus/focus_models.dart'
    show defaultPresetId;

class FocusLocalService {
  FocusLocalService(this._db);

  final AppDatabase _db;

  Stream<List<FocusPresetRow>> watchActivePresets() {
    final statement = _db.select(_db.focusPresets)
      ..where((preset) => preset.isDeleted.equals(false))
      ..orderBy([
        (preset) => OrderingTerm.desc(preset.isDefault),
        (preset) => OrderingTerm.asc(preset.name),
      ]);
    return statement.watch();
  }

  Future<List<FocusPresetRow>> nonDeletedPresets() {
    return (_db.select(
      _db.focusPresets,
    )..where((row) => row.isDeleted.equals(false))).get();
  }

  Future<FocusPresetRow?> findPreset(String id) {
    return (_db.select(_db.focusPresets)
          ..where((row) => row.id.equals(id) & row.isDeleted.equals(false))
          ..limit(1))
        .getSingleOrNull();
  }

  Future<FocusPresetRow> defaultPreset() async {
    final preset =
        await (_db.select(_db.focusPresets)
              ..where(
                (row) =>
                    row.isDefault.equals(true) & row.isDeleted.equals(false),
              )
              ..limit(1))
            .getSingleOrNull();
    if (preset != null) {
      return preset;
    }
    await _db.ensureSeedData();
    return (_db.select(_db.focusPresets)
          ..where((row) => row.id.equals(defaultPresetId))
          ..limit(1))
        .getSingle();
  }

  Future<void> insertPreset(FocusPresetsCompanion preset) {
    return _db.into(_db.focusPresets).insert(preset);
  }

  Future<void> updatePreset(String id, FocusPresetsCompanion preset) {
    return (_db.update(_db.focusPresets)
          ..where((row) => row.id.equals(id) & row.isDeleted.equals(false)))
        .write(preset);
  }

  Future<void> markPresetDeleted(String id, DateTime updatedAt) {
    return (_db.update(
      _db.focusPresets,
    )..where((row) => row.id.equals(id))).write(
      FocusPresetsCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(updatedAt),
      ),
    );
  }

  Future<void> reassignActiveRunsPreset(
    String presetId,
    String replacementPresetId,
    DateTime updatedAt,
  ) {
    return (_db.update(_db.focusRuns)..where(
          (row) =>
              row.presetId.equals(presetId) &
              (row.status.equals('active') | row.status.equals('paused')) &
              row.isDeleted.equals(false),
        ))
        .write(
          FocusRunsCompanion(
            presetId: Value(replacementPresetId),
            updatedAt: Value(updatedAt),
          ),
        );
  }

  Future<void> clearDefaultPresets(DateTime updatedAt) {
    return _db
        .update(_db.focusPresets)
        .write(
          FocusPresetsCompanion(
            isDefault: const Value(false),
            updatedAt: Value(updatedAt),
          ),
        );
  }

  Future<void> markPresetDefault(String id, DateTime updatedAt) {
    return (_db.update(
      _db.focusPresets,
    )..where((row) => row.id.equals(id))).write(
      FocusPresetsCompanion(
        isDefault: const Value(true),
        updatedAt: Value(updatedAt),
      ),
    );
  }

  Future<void> updateRunPreset(
    String runId,
    String presetId,
    DateTime updatedAt,
  ) {
    return (_db.update(
      _db.focusRuns,
    )..where((row) => row.id.equals(runId))).write(
      FocusRunsCompanion(
        presetId: Value(presetId),
        updatedAt: Value(updatedAt),
      ),
    );
  }

  Stream<FocusRunRow?> watchActiveRun() {
    return _activeRunQuery().watchSingleOrNull().map(
      (row) => row?.readTable(_db.focusRuns),
    );
  }

  Stream<FocusIntervalRow?> watchActiveInterval() {
    return _activeIntervalQuery().watchSingleOrNull().map(
      (row) => row?.readTable(_db.focusIntervals),
    );
  }

  Future<FocusRunRow?> activeRun() {
    return _activeRunQuery().getSingleOrNull().then(
      (row) => row?.readTable(_db.focusRuns),
    );
  }

  Future<FocusIntervalRow?> activeInterval() {
    return _activeIntervalQuery().getSingleOrNull().then(
      (row) => row?.readTable(_db.focusIntervals),
    );
  }

  JoinedSelectStatement<HasResultSet, dynamic> _activeRunQuery() {
    final query = _db.select(_db.focusRuns).join([
      innerJoin(
        _db.focusIntervals,
        _db.focusIntervals.runId.equalsExp(_db.focusRuns.id),
        useColumns: false,
      ),
    ]);
    _configureActivePairQuery(query);
    return query;
  }

  JoinedSelectStatement<HasResultSet, dynamic> _activeIntervalQuery() {
    final query = _db.select(_db.focusIntervals).join([
      innerJoin(
        _db.focusRuns,
        _db.focusRuns.id.equalsExp(_db.focusIntervals.runId),
        useColumns: false,
      ),
    ]);
    _configureActivePairQuery(query);
    return query;
  }

  void _configureActivePairQuery(
    JoinedSelectStatement<HasResultSet, dynamic> query,
  ) {
    query
      ..where(
        (_db.focusRuns.status.equals('active') |
                _db.focusRuns.status.equals('paused')) &
            _db.focusRuns.isDeleted.equals(false) &
            (_db.focusIntervals.status.equals('running') |
                _db.focusIntervals.status.equals('paused') |
                _db.focusIntervals.status.equals('ready')) &
            _db.focusIntervals.isDeleted.equals(false),
      )
      ..orderBy([
        OrderingTerm.desc(_db.focusRuns.startedAt),
        OrderingTerm.desc(_db.focusIntervals.sequenceNumber),
      ])
      ..limit(1);
  }

  Stream<List<FocusRunRow>> watchRunsForTask(String taskId) {
    final statement = _db.select(_db.focusRuns)
      ..where((run) => run.taskId.equals(taskId) & run.isDeleted.equals(false))
      ..orderBy([(run) => OrderingTerm.desc(run.startedAt)]);
    return statement.watch();
  }

  Stream<List<FocusIntervalRow>> watchIntervalsForTask(String taskId) {
    final statement = _db.select(_db.focusIntervals)
      ..where(
        (interval) =>
            interval.taskId.equals(taskId) & interval.isDeleted.equals(false),
      )
      ..orderBy([(interval) => OrderingTerm.desc(interval.startedAt)]);
    return statement.watch();
  }

  Stream<List<FocusIntervalRow>> watchIntervalsForRun(String runId) {
    final statement = _db.select(_db.focusIntervals)
      ..where(
        (interval) =>
            interval.runId.equals(runId) & interval.isDeleted.equals(false),
      )
      ..orderBy([(interval) => OrderingTerm.asc(interval.sequenceNumber)]);
    return statement.watch();
  }

  Stream<List<FocusIntervalRow>> watchNonDeletedIntervals() {
    final statement = _db.select(_db.focusIntervals)
      ..where((interval) => interval.isDeleted.equals(false));
    return statement.watch();
  }

  Future<FocusRunRow?> findRun(String id) {
    return (_db.select(
      _db.focusRuns,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
  }

  Future<TaskRow?> findTask(String id) {
    return (_db.select(
      _db.tasks,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
  }

  Future<TaskRow?> findActiveTask(String id) {
    return (_db.select(_db.tasks)
          ..where((task) => task.id.equals(id) & task.isDeleted.equals(false)))
        .getSingleOrNull();
  }

  Future<void> insertRun(FocusRunsCompanion run) {
    return _db.into(_db.focusRuns).insert(run);
  }

  Future<void> insertInterval(FocusIntervalsCompanion interval) {
    return _db.into(_db.focusIntervals).insert(interval);
  }

  Future<void> insertEvent(FocusEventsCompanion event) {
    return _db.into(_db.focusEvents).insert(event);
  }

  Future<void> startInterval(
    String intervalId,
    String runId,
    DateTime startedAt,
  ) async {
    await (_db.update(
      _db.focusIntervals,
    )..where((row) => row.id.equals(intervalId))).write(
      FocusIntervalsCompanion(
        status: const Value('running'),
        startedAt: Value(startedAt),
        pausedAt: const Value(null),
        pausedTotalSeconds: const Value(0),
        updatedAt: Value(startedAt),
      ),
    );
    await (_db.update(
      _db.focusRuns,
    )..where((row) => row.id.equals(runId))).write(
      FocusRunsCompanion(
        status: const Value('active'),
        updatedAt: Value(startedAt),
      ),
    );
  }

  Future<void> pauseInterval(
    String intervalId,
    String runId,
    DateTime pausedAt,
  ) async {
    await (_db.update(
      _db.focusIntervals,
    )..where((row) => row.id.equals(intervalId))).write(
      FocusIntervalsCompanion(
        status: const Value('paused'),
        pausedAt: Value(pausedAt),
        updatedAt: Value(pausedAt),
      ),
    );
    await (_db.update(
      _db.focusRuns,
    )..where((row) => row.id.equals(runId))).write(
      FocusRunsCompanion(
        status: const Value('paused'),
        updatedAt: Value(pausedAt),
      ),
    );
  }

  Future<void> resumeInterval(
    String intervalId,
    String runId,
    int pausedTotalSeconds,
    DateTime resumedAt,
  ) async {
    await (_db.update(
      _db.focusIntervals,
    )..where((row) => row.id.equals(intervalId))).write(
      FocusIntervalsCompanion(
        status: const Value('running'),
        pausedAt: const Value(null),
        pausedTotalSeconds: Value(pausedTotalSeconds),
        updatedAt: Value(resumedAt),
      ),
    );
    await (_db.update(
      _db.focusRuns,
    )..where((row) => row.id.equals(runId))).write(
      FocusRunsCompanion(
        status: const Value('active'),
        updatedAt: Value(resumedAt),
      ),
    );
  }

  Future<void> restartInterval(
    String intervalId,
    String runId,
    DateTime startedAt,
  ) async {
    await (_db.update(
      _db.focusIntervals,
    )..where((row) => row.id.equals(intervalId))).write(
      FocusIntervalsCompanion(
        status: const Value('running'),
        startedAt: Value(startedAt),
        pausedAt: const Value(null),
        pausedTotalSeconds: const Value(0),
        completedAt: const Value(null),
        stoppedAt: const Value(null),
        updatedAt: Value(startedAt),
      ),
    );
    await (_db.update(
      _db.focusRuns,
    )..where((row) => row.id.equals(runId))).write(
      FocusRunsCompanion(
        status: const Value('active'),
        updatedAt: Value(startedAt),
      ),
    );
  }

  Future<void> completeInterval(String intervalId, DateTime completedAt) {
    return (_db.update(
      _db.focusIntervals,
    )..where((row) => row.id.equals(intervalId))).write(
      FocusIntervalsCompanion(
        status: const Value('completed'),
        completedAt: Value(completedAt),
        pausedAt: const Value(null),
        updatedAt: Value(completedAt),
      ),
    );
  }

  Future<void> completeRun(
    String runId,
    int completedWorkIntervals,
    DateTime completedAt,
  ) {
    return (_db.update(
      _db.focusRuns,
    )..where((row) => row.id.equals(runId))).write(
      FocusRunsCompanion(
        status: const Value('completed'),
        endedAt: Value(completedAt),
        completedWorkIntervals: Value(completedWorkIntervals),
        updatedAt: Value(completedAt),
      ),
    );
  }

  Future<void> markRunInProgress(
    String runId,
    int completedWorkIntervals,
    DateTime updatedAt,
  ) {
    return (_db.update(
      _db.focusRuns,
    )..where((row) => row.id.equals(runId))).write(
      FocusRunsCompanion(
        status: const Value('active'),
        completedWorkIntervals: Value(completedWorkIntervals),
        updatedAt: Value(updatedAt),
      ),
    );
  }

  Future<void> markRunActive(String runId, DateTime updatedAt) {
    return (_db.update(
      _db.focusRuns,
    )..where((row) => row.id.equals(runId))).write(
      FocusRunsCompanion(
        status: const Value('active'),
        updatedAt: Value(updatedAt),
      ),
    );
  }

  Future<void> finishRun(String runId, DateTime endedAt) {
    return (_db.update(
      _db.focusRuns,
    )..where((row) => row.id.equals(runId))).write(
      FocusRunsCompanion(
        status: const Value('completed'),
        endedAt: Value(endedAt),
        updatedAt: Value(endedAt),
      ),
    );
  }

  Future<void> skipInterval(String intervalId, DateTime stoppedAt) {
    return (_db.update(
      _db.focusIntervals,
    )..where((row) => row.id.equals(intervalId))).write(
      FocusIntervalsCompanion(
        status: const Value('skipped'),
        pausedAt: const Value(null),
        stoppedAt: Value(stoppedAt),
        updatedAt: Value(stoppedAt),
      ),
    );
  }

  Future<void> stopInterval(String intervalId, DateTime stoppedAt) {
    return (_db.update(
      _db.focusIntervals,
    )..where((row) => row.id.equals(intervalId))).write(
      FocusIntervalsCompanion(
        status: const Value('stopped'),
        stoppedAt: Value(stoppedAt),
        updatedAt: Value(stoppedAt),
      ),
    );
  }

  Future<void> stopRun(String runId, String status, DateTime stoppedAt) {
    return (_db.update(
      _db.focusRuns,
    )..where((row) => row.id.equals(runId))).write(
      FocusRunsCompanion(
        status: Value(status),
        endedAt: Value(stoppedAt),
        updatedAt: Value(stoppedAt),
      ),
    );
  }

  Future<List<FocusIntervalRow>> completedWorkIntervalsForTask(String taskId) {
    return (_db.select(_db.focusIntervals)..where(
          (interval) =>
              interval.taskId.equals(taskId) &
              interval.type.equals('work') &
              interval.status.equals('completed') &
              interval.isDeleted.equals(false),
        ))
        .get();
  }

  Future<List<SharedEntityRow>> sharedFocusIntervals(String scopeId) {
    return (_db.select(_db.sharedEntities)..where(
          (row) =>
              row.scopeId.equals(scopeId) &
              row.entityType.equals('focus_interval') &
              row.isDeleted.equals(false),
        ))
        .get();
  }

  Future<void> updateTaskFocusTotals(
    String taskId,
    int completedFocusIntervals,
    int totalFocusSeconds,
    DateTime updatedAt,
  ) {
    return (_db.update(
      _db.tasks,
    )..where((task) => task.id.equals(taskId))).write(
      TasksCompanion(
        completedFocusIntervals: Value(completedFocusIntervals),
        totalFocusSeconds: Value(totalFocusSeconds),
        updatedAt: Value(updatedAt),
      ),
    );
  }
}
