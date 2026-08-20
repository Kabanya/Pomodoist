import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/audio/focus_sound_player.dart';
import '../../../core/db/app_database.dart' hide FocusDailyStats;
import '../../../core/notifications/notification_scheduler.dart';
import '../../../core/sync/sync_queue_repository.dart';
import '../../../core/time/timer_engine.dart';
import '../../focus/domain/focus_models.dart';
import '../../tasks/data/kanban_transition_coordinator.dart';

class DriftFocusRepository implements FocusRepository {
  DriftFocusRepository(
    this._db,
    this._syncQueue,
    this._notifications, {
    FocusSoundPlayer? soundPlayer,
    Uuid? uuid,
    KanbanTransitionCoordinator? kanbanTransitions,
    void Function(FocusRunCompletionEvent event)? onRunCompleted,
  }) : _soundPlayer = soundPlayer,
       _onRunCompleted = onRunCompleted,
       _kanbanTransitions =
           kanbanTransitions ??
           KanbanTransitionCoordinator(_db, _syncQueue, uuid: uuid),
       _uuid = uuid ?? const Uuid();

  final AppDatabase _db;
  final SyncQueueRepository _syncQueue;
  final NotificationScheduler _notifications;
  final FocusSoundPlayer? _soundPlayer;
  final void Function(FocusRunCompletionEvent event)? _onRunCompleted;
  final KanbanTransitionCoordinator _kanbanTransitions;
  final Uuid _uuid;
  final Set<String> _publishedCompletionRunIds = <String>{};

  @override
  Stream<List<FocusPresetItem>> watchPresets() {
    final statement = _db.select(_db.focusPresets)
      ..where((preset) => preset.isDeleted.equals(false))
      ..orderBy([
        (preset) => OrderingTerm.desc(preset.isDefault),
        (preset) => OrderingTerm.asc(preset.name),
      ]);
    return statement.watch().map((rows) => rows.map(_mapPreset).toList());
  }

  @override
  Stream<FocusRunItem?> watchActiveRun() {
    return _activeFocusRunQuery().watchSingleOrNull().map(
      (row) => row == null ? null : _mapRun(row.readTable(_db.focusRuns)),
    );
  }

  @override
  Stream<FocusIntervalItem?> watchActiveInterval() {
    return _activeFocusIntervalQuery().watchSingleOrNull().map(
      (row) =>
          row == null ? null : _mapInterval(row.readTable(_db.focusIntervals)),
    );
  }

  JoinedSelectStatement<HasResultSet, dynamic> _activeFocusRunQuery() {
    final query = _db.select(_db.focusRuns).join([
      innerJoin(
        _db.focusIntervals,
        _db.focusIntervals.runId.equalsExp(_db.focusRuns.id),
        useColumns: false,
      ),
    ]);
    _configureActiveFocusPairQuery(query);
    return query;
  }

  JoinedSelectStatement<HasResultSet, dynamic> _activeFocusIntervalQuery() {
    final query = _db.select(_db.focusIntervals).join([
      innerJoin(
        _db.focusRuns,
        _db.focusRuns.id.equalsExp(_db.focusIntervals.runId),
        useColumns: false,
      ),
    ]);
    _configureActiveFocusPairQuery(query);
    return query;
  }

  void _configureActiveFocusPairQuery(
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

  @override
  Stream<List<FocusRunItem>> watchRunsForTask(String taskId) {
    final statement = _db.select(_db.focusRuns)
      ..where((run) => run.taskId.equals(taskId) & run.isDeleted.equals(false))
      ..orderBy([(run) => OrderingTerm.desc(run.startedAt)]);
    return statement.watch().map((rows) => rows.map(_mapRun).toList());
  }

  @override
  Stream<List<FocusIntervalItem>> watchIntervalsForTask(String taskId) {
    final statement = _db.select(_db.focusIntervals)
      ..where(
        (interval) =>
            interval.taskId.equals(taskId) & interval.isDeleted.equals(false),
      )
      ..orderBy([(interval) => OrderingTerm.desc(interval.startedAt)]);
    return statement.watch().map((rows) => rows.map(_mapInterval).toList());
  }

  @override
  Stream<List<FocusIntervalItem>> watchIntervalsForRun(String runId) {
    final statement = _db.select(_db.focusIntervals)
      ..where(
        (interval) =>
            interval.runId.equals(runId) & interval.isDeleted.equals(false),
      )
      ..orderBy([(interval) => OrderingTerm.asc(interval.sequenceNumber)]);
    return statement.watch().map((rows) => rows.map(_mapInterval).toList());
  }

  @override
  Stream<FocusDailyStats> watchDailyStats(DateTime localDate) {
    final day = DateTime(localDate.year, localDate.month, localDate.day);
    final statement = _db.select(_db.focusIntervals)
      ..where((interval) => interval.isDeleted.equals(false));
    return statement.watch().map((rows) {
      final dayRows = rows.where((row) {
        final started = row.startedAt.toLocal();
        return started.year == day.year &&
            started.month == day.month &&
            started.day == day.day;
      }).toList();
      final completedWork = dayRows.where(
        (row) => row.type == 'work' && row.status == 'completed',
      );
      return FocusDailyStats(
        completedTasks: 0,
        completedFocusIntervals: completedWork.length,
        totalFocusSeconds: completedWork.fold<int>(
          0,
          (sum, row) => sum + _actualSeconds(row),
        ),
        interruptedIntervals: dayRows
            .where((row) => row.status == 'stopped')
            .length,
        plannedFocusIntervals: 0,
      );
    });
  }

  @override
  Future<String> createPreset(CreateFocusPresetInput input) async {
    final now = DateTime.now().toUtc();
    final id = _uuid.v4();
    await _validatePresetInput(
      name: input.name,
      workSeconds: input.workSeconds,
      shortBreakSeconds: input.shortBreakSeconds,
      longBreakSeconds: input.longBreakSeconds,
      intervalsBeforeLongBreak: input.intervalsBeforeLongBreak,
    );
    await _db
        .into(_db.focusPresets)
        .insert(
          FocusPresetsCompanion.insert(
            id: id,
            userId: localUserId,
            name: input.name.trim(),
            workSeconds: input.workSeconds,
            shortBreakSeconds: input.shortBreakSeconds,
            longBreakSeconds: input.longBreakSeconds,
            intervalsBeforeLongBreak: input.intervalsBeforeLongBreak,
            autoStartBreaks: Value(input.autoStartBreaks),
            autoStartWork: Value(input.autoStartWork),
            allowPause: Value(input.allowPause),
            strictMode: Value(input.strictMode),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return id;
  }

  @override
  Future<void> updatePreset(String id, UpdateFocusPresetInput input) async {
    await _validatePresetInput(
      name: input.name,
      workSeconds: input.workSeconds,
      shortBreakSeconds: input.shortBreakSeconds,
      longBreakSeconds: input.longBreakSeconds,
      intervalsBeforeLongBreak: input.intervalsBeforeLongBreak,
      existingId: id,
    );
    final now = DateTime.now().toUtc();
    await (_db.update(
      _db.focusPresets,
    )..where((row) => row.id.equals(id) & row.isDeleted.equals(false))).write(
      FocusPresetsCompanion(
        name: Value(input.name.trim()),
        workSeconds: Value(input.workSeconds),
        shortBreakSeconds: Value(input.shortBreakSeconds),
        longBreakSeconds: Value(input.longBreakSeconds),
        intervalsBeforeLongBreak: Value(input.intervalsBeforeLongBreak),
        autoStartBreaks: Value(input.autoStartBreaks),
        autoStartWork: Value(input.autoStartWork),
        allowPause: Value(input.allowPause),
        strictMode: Value(input.strictMode),
        updatedAt: Value(now),
      ),
    );
  }

  @override
  Future<void> deletePreset(String id) async {
    final preset = await _presetById(id);
    if (preset == null || preset.isDefault) {
      return;
    }
    final defaultPreset = await _defaultPreset();
    final now = DateTime.now().toUtc();
    await _db.transaction(() async {
      await (_db.update(
        _db.focusPresets,
      )..where((row) => row.id.equals(id))).write(
        FocusPresetsCompanion(
          isDeleted: const Value(true),
          updatedAt: Value(now),
        ),
      );
      await (_db.update(_db.focusRuns)..where(
            (row) =>
                row.presetId.equals(id) &
                (row.status.equals('active') | row.status.equals('paused')) &
                row.isDeleted.equals(false),
          ))
          .write(
            FocusRunsCompanion(
              presetId: Value(defaultPreset.id),
              updatedAt: Value(now),
            ),
          );
    });
  }

  @override
  Future<void> setDefaultPreset(String id) async {
    final preset = await _presetById(id);
    if (preset == null) {
      return;
    }
    final now = DateTime.now().toUtc();
    await _db.transaction(() async {
      await _db
          .update(_db.focusPresets)
          .write(
            FocusPresetsCompanion(
              isDefault: const Value(false),
              updatedAt: Value(now),
            ),
          );
      await (_db.update(
        _db.focusPresets,
      )..where((row) => row.id.equals(id))).write(
        FocusPresetsCompanion(
          isDefault: const Value(true),
          updatedAt: Value(now),
        ),
      );
    });
  }

  @override
  Future<void> changeActiveRunPreset(String presetId) async {
    final preset = await _presetById(presetId);
    final run = await _activeRunRow();
    if (preset == null || run == null) {
      return;
    }
    final now = DateTime.now().toUtc();
    await (_db.update(
      _db.focusRuns,
    )..where((row) => row.id.equals(run.id))).write(
      FocusRunsCompanion(presetId: Value(preset.id), updatedAt: Value(now)),
    );
  }

  @override
  Future<String> startRun(StartFocusRunInput input, {DateTime? now}) async {
    final timestamp = (now ?? DateTime.now()).toUtc();
    final task = input.taskId == null
        ? null
        : await (_db.select(_db.tasks)..where(
                (task) =>
                    task.id.equals(input.taskId!) &
                    task.isDeleted.equals(false),
              ))
              .getSingleOrNull();
    if (input.taskId != null && task == null) {
      throw ArgumentError.value(input.taskId, 'taskId', 'Unknown task');
    }
    if (task?.status == 'completed') {
      throw StateError('Completed tasks must be restored before Focus starts');
    }
    await _stopExistingActiveRunIfAny(now: now);
    final runId = _uuid.v4();
    final intervalId = _uuid.v4();
    final preset = await _presetByIdOrDefault(input.presetId);
    final cadence = preset.intervalsBeforeLongBreak < 1
        ? 1
        : preset.intervalsBeforeLongBreak;
    final targetWorkIntervals =
        input.targetWorkIntervals ??
        (input.taskId == null ? cadence : task?.estimatedFocusIntervals ?? 1);
    final projectId = input.projectId ?? task?.projectId;

    await _db.transaction(() async {
      if (input.taskId != null) {
        await _kanbanTransitions.prepareTaskForFocusInTransaction(
          input.taskId!,
          timestamp: timestamp,
        );
      }
      await _db
          .into(_db.focusRuns)
          .insert(
            FocusRunsCompanion.insert(
              id: runId,
              userId: localUserId,
              taskId: Value(input.taskId),
              projectId: Value(projectId),
              presetId: preset.id,
              status: 'active',
              startedAt: timestamp,
              targetWorkIntervals: targetWorkIntervals,
              note: Value(input.note),
              createdAt: timestamp,
              updatedAt: timestamp,
            ),
          );
      await _db
          .into(_db.focusIntervals)
          .insert(
            FocusIntervalsCompanion.insert(
              id: intervalId,
              runId: runId,
              taskId: Value(input.taskId),
              projectId: Value(projectId),
              type: 'work',
              status: 'running',
              plannedSeconds: preset.workSeconds,
              startedAt: timestamp,
              sequenceNumber: 1,
              createdAt: timestamp,
              updatedAt: timestamp,
            ),
          );
      await _insertEvent(runId, intervalId, 'runStarted', timestamp, {
        'taskId': input.taskId,
        'projectId': projectId,
      });
      await _insertEvent(runId, intervalId, 'intervalStarted', timestamp, {
        'type': 'work',
      });
    });
    await _scheduleIntervalNotification(
      type: 'work',
      startedAt: timestamp,
      plannedSeconds: preset.workSeconds,
      pausedTotalSeconds: 0,
    );
    _playSound(FocusSoundCue.start);
    return runId;
  }

  @override
  Future<void> startReadyInterval() async {
    final interval = await _activeIntervalRow();
    if (interval == null || interval.status != 'ready') {
      return;
    }
    final now = DateTime.now().toUtc();
    await _db.transaction(() async {
      await (_db.update(
        _db.focusIntervals,
      )..where((row) => row.id.equals(interval.id))).write(
        FocusIntervalsCompanion(
          status: const Value('running'),
          startedAt: Value(now),
          pausedAt: const Value(null),
          pausedTotalSeconds: const Value(0),
          updatedAt: Value(now),
        ),
      );
      await (_db.update(
        _db.focusRuns,
      )..where((row) => row.id.equals(interval.runId))).write(
        FocusRunsCompanion(
          status: const Value('active'),
          updatedAt: Value(now),
        ),
      );
      await _insertEvent(interval.runId, interval.id, 'intervalStarted', now, {
        'type': interval.type,
      });
    });
    await _scheduleIntervalNotification(
      type: interval.type,
      startedAt: now,
      plannedSeconds: interval.plannedSeconds,
      pausedTotalSeconds: 0,
    );
    _playSound(FocusSoundCue.start);
  }

  @override
  Future<void> pauseActiveInterval({DateTime? now}) async {
    final interval = await _activeIntervalRow();
    if (interval == null || interval.status != 'running') {
      return;
    }
    final preset = await _presetForInterval(interval);
    if (preset == null || !preset.allowPause) {
      return;
    }
    final timestamp = (now ?? DateTime.now()).toUtc();
    await _db.transaction(() async {
      await (_db.update(
        _db.focusIntervals,
      )..where((row) => row.id.equals(interval.id))).write(
        FocusIntervalsCompanion(
          status: const Value('paused'),
          pausedAt: Value(timestamp),
          updatedAt: Value(timestamp),
        ),
      );
      await (_db.update(
        _db.focusRuns,
      )..where((row) => row.id.equals(interval.runId))).write(
        FocusRunsCompanion(
          status: const Value('paused'),
          updatedAt: Value(timestamp),
        ),
      );
      await _insertEvent(
        interval.runId,
        interval.id,
        'intervalPaused',
        timestamp,
        null,
      );
    });
    await _notifications.cancelFocusNotification();
    _playSound(FocusSoundCue.pause);
  }

  @override
  Future<void> resumeActiveInterval({DateTime? now}) async {
    final interval = await _activeIntervalRow();
    if (interval == null ||
        interval.status != 'paused' ||
        interval.pausedAt == null) {
      return;
    }
    final timestamp = (now ?? DateTime.now()).toUtc();
    final pausedDelta = timestamp.difference(interval.pausedAt!).inSeconds;
    final pausedTotal =
        interval.pausedTotalSeconds + (pausedDelta < 0 ? 0 : pausedDelta);
    await _db.transaction(() async {
      await (_db.update(
        _db.focusIntervals,
      )..where((row) => row.id.equals(interval.id))).write(
        FocusIntervalsCompanion(
          status: const Value('running'),
          pausedAt: const Value(null),
          pausedTotalSeconds: Value(pausedTotal),
          updatedAt: Value(timestamp),
        ),
      );
      await (_db.update(
        _db.focusRuns,
      )..where((row) => row.id.equals(interval.runId))).write(
        FocusRunsCompanion(
          status: const Value('active'),
          updatedAt: Value(timestamp),
        ),
      );
      await _insertEvent(
        interval.runId,
        interval.id,
        'intervalResumed',
        timestamp,
        null,
      );
    });
    await _scheduleIntervalNotification(
      type: interval.type,
      startedAt: interval.startedAt,
      plannedSeconds: interval.plannedSeconds,
      pausedTotalSeconds: pausedTotal,
    );
    _playSound(FocusSoundCue.resume);
  }

  @override
  Future<void> restartActiveInterval({DateTime? now}) async {
    final interval = await _activeIntervalRow();
    if (interval == null) {
      return;
    }
    final timestamp = (now ?? DateTime.now()).toUtc();
    await _db.transaction(() async {
      await (_db.update(
        _db.focusIntervals,
      )..where((row) => row.id.equals(interval.id))).write(
        FocusIntervalsCompanion(
          status: const Value('running'),
          startedAt: Value(timestamp),
          pausedAt: const Value(null),
          pausedTotalSeconds: const Value(0),
          completedAt: const Value(null),
          stoppedAt: const Value(null),
          updatedAt: Value(timestamp),
        ),
      );
      await (_db.update(
        _db.focusRuns,
      )..where((row) => row.id.equals(interval.runId))).write(
        FocusRunsCompanion(
          status: const Value('active'),
          updatedAt: Value(timestamp),
        ),
      );
      await _insertEvent(
        interval.runId,
        interval.id,
        'intervalRestarted',
        timestamp,
        {'type': interval.type},
      );
    });
    await _scheduleIntervalNotification(
      type: interval.type,
      startedAt: timestamp,
      plannedSeconds: interval.plannedSeconds,
      pausedTotalSeconds: 0,
    );
  }

  @override
  Future<void> completeActiveInterval({DateTime? now}) async {
    final interval = await _activeIntervalRow();
    if (interval == null || interval.status == 'ready') {
      return;
    }
    final run = await (_db.select(
      _db.focusRuns,
    )..where((row) => row.id.equals(interval.runId))).getSingleOrNull();
    if (run == null) {
      return;
    }
    final timestamp = (now ?? DateTime.now()).toUtc();
    final preset = await _presetForRun(run);
    if (preset.strictMode &&
        !isIntervalExpired(
          now: timestamp,
          startedAt: interval.startedAt,
          plannedSeconds: interval.plannedSeconds,
          pausedTotalSeconds: interval.pausedTotalSeconds,
          pausedAt: interval.pausedAt,
        )) {
      return;
    }
    final completedWorkIntervals =
        run.completedWorkIntervals + (interval.type == 'work' ? 1 : 0);
    final completesRun =
        interval.type != 'work' &&
        completedWorkIntervals >= run.targetWorkIntervals;

    await _db.transaction(() async {
      await (_db.update(
        _db.focusIntervals,
      )..where((row) => row.id.equals(interval.id))).write(
        FocusIntervalsCompanion(
          status: const Value('completed'),
          completedAt: Value(timestamp),
          pausedAt: const Value(null),
          updatedAt: Value(timestamp),
        ),
      );
      await _insertEvent(
        interval.runId,
        interval.id,
        'intervalCompleted',
        timestamp,
        {'type': interval.type},
      );
      if (interval.type == 'work' && interval.taskId != null) {
        await _recalculateTaskFocusAggregates(interval.taskId!);
      }

      if (completesRun) {
        await (_db.update(
          _db.focusRuns,
        )..where((row) => row.id.equals(run.id))).write(
          FocusRunsCompanion(
            status: const Value('completed'),
            endedAt: Value(timestamp),
            completedWorkIntervals: Value(completedWorkIntervals),
            updatedAt: Value(timestamp),
          ),
        );
        await _insertEvent(
          run.id,
          interval.id,
          'runCompleted',
          timestamp,
          null,
        );
      } else {
        await (_db.update(
          _db.focusRuns,
        )..where((row) => row.id.equals(run.id))).write(
          FocusRunsCompanion(
            status: const Value('active'),
            completedWorkIntervals: Value(completedWorkIntervals),
            updatedAt: Value(timestamp),
          ),
        );
        final next = _nextIntervalSpec(
          completed: interval.type,
          completedWorkIntervals: completedWorkIntervals,
          preset: preset,
        );
        await _createNextInterval(
          run: run,
          type: next.type,
          status: _nextIntervalStatus(next.type, preset),
          plannedSeconds: next.plannedSeconds,
          startedAt: timestamp,
          sequenceNumber: interval.sequenceNumber + 1,
        );
      }
      if (completesRun) {
        await _syncQueue.enqueue(
          type: 'focus.run.complete',
          clientId: run.id,
          payload: {'id': run.id, 'completedAt': timestamp.toIso8601String()},
        );
      }
    });
    await _notifications.cancelFocusNotification();
    final nextInterval = await _activeIntervalRow();
    if (nextInterval != null && nextInterval.status == 'running') {
      await _scheduleIntervalNotification(
        type: nextInterval.type,
        startedAt: nextInterval.startedAt,
        plannedSeconds: nextInterval.plannedSeconds,
        pausedTotalSeconds: nextInterval.pausedTotalSeconds,
      );
    }
    _playSound(FocusSoundCue.complete);
    if (completesRun) {
      await _publishRunCompletion(
        run: run,
        completedWorkIntervals: completedWorkIntervals,
        completedAt: timestamp,
      );
    }
  }

  @override
  Future<void> skipActiveInterval({DateTime? now}) async {
    final interval = await _activeIntervalRow();
    if (interval == null) {
      return;
    }
    final run = await (_db.select(
      _db.focusRuns,
    )..where((row) => row.id.equals(interval.runId))).getSingleOrNull();
    if (run == null) {
      return;
    }
    final preset = await _presetForRun(run);
    if (preset.strictMode) {
      return;
    }
    final timestamp = (now ?? DateTime.now()).toUtc();
    final completesRun =
        interval.type != 'work' &&
        run.completedWorkIntervals >= run.targetWorkIntervals;
    await _db.transaction(() async {
      await (_db.update(
        _db.focusIntervals,
      )..where((row) => row.id.equals(interval.id))).write(
        FocusIntervalsCompanion(
          status: const Value('skipped'),
          pausedAt: const Value(null),
          stoppedAt: Value(timestamp),
          updatedAt: Value(timestamp),
        ),
      );
      await _insertEvent(
        interval.runId,
        interval.id,
        'intervalSkipped',
        timestamp,
        null,
      );
      if (interval.type == 'work') {
        await (_db.update(
          _db.focusRuns,
        )..where((row) => row.id.equals(run.id))).write(
          FocusRunsCompanion(
            status: const Value('active'),
            updatedAt: Value(timestamp),
          ),
        );
        await _createNextInterval(
          run: run,
          type: 'shortBreak',
          status: _nextIntervalStatus('shortBreak', preset),
          plannedSeconds: preset.shortBreakSeconds,
          startedAt: timestamp,
          sequenceNumber: interval.sequenceNumber + 1,
        );
      } else if (completesRun) {
        await (_db.update(
          _db.focusRuns,
        )..where((row) => row.id.equals(run.id))).write(
          FocusRunsCompanion(
            status: const Value('completed'),
            endedAt: Value(timestamp),
            updatedAt: Value(timestamp),
          ),
        );
        await _insertEvent(
          run.id,
          interval.id,
          'runCompleted',
          timestamp,
          null,
        );
      } else {
        await (_db.update(
          _db.focusRuns,
        )..where((row) => row.id.equals(run.id))).write(
          FocusRunsCompanion(
            status: const Value('active'),
            updatedAt: Value(timestamp),
          ),
        );
        await _createNextInterval(
          run: run,
          type: 'work',
          status: _nextIntervalStatus('work', preset),
          plannedSeconds: preset.workSeconds,
          startedAt: timestamp,
          sequenceNumber: interval.sequenceNumber + 1,
        );
      }
      if (completesRun) {
        await _syncQueue.enqueue(
          type: 'focus.run.complete',
          clientId: run.id,
          payload: {'id': run.id, 'completedAt': timestamp.toIso8601String()},
        );
      }
    });
    await _notifications.cancelFocusNotification();
    final nextInterval = await _activeIntervalRow();
    if (nextInterval != null && nextInterval.status == 'running') {
      await _scheduleIntervalNotification(
        type: nextInterval.type,
        startedAt: nextInterval.startedAt,
        plannedSeconds: nextInterval.plannedSeconds,
        pausedTotalSeconds: nextInterval.pausedTotalSeconds,
      );
    }
    if (completesRun) {
      _playSound(FocusSoundCue.complete);
      await _publishRunCompletion(
        run: run,
        completedWorkIntervals: run.completedWorkIntervals,
        completedAt: timestamp,
      );
    }
  }

  @override
  Future<void> stopActiveRun({
    required StopFocusReason reason,
    DateTime? now,
  }) async {
    final run = await _activeRunRow();
    if (run == null) {
      return;
    }
    final interval = await _activeIntervalRow();
    final timestamp = (now ?? DateTime.now()).toUtc();
    final status = reason == StopFocusReason.interrupted
        ? 'interrupted'
        : 'stopped';
    await _db.transaction(() async {
      if (interval != null) {
        await (_db.update(
          _db.focusIntervals,
        )..where((row) => row.id.equals(interval.id))).write(
          FocusIntervalsCompanion(
            status: const Value('stopped'),
            stoppedAt: Value(timestamp),
            updatedAt: Value(timestamp),
          ),
        );
      }
      await (_db.update(
        _db.focusRuns,
      )..where((row) => row.id.equals(run.id))).write(
        FocusRunsCompanion(
          status: Value(status),
          endedAt: Value(timestamp),
          updatedAt: Value(timestamp),
        ),
      );
      await _insertEvent(run.id, interval?.id, 'runStopped', timestamp, {
        'reason': status,
      });
      await _syncQueue.enqueue(
        type: 'focus.run.stop',
        clientId: run.id,
        payload: {
          'id': run.id,
          'reason': status,
          'stoppedAt': timestamp.toIso8601String(),
        },
      );
    });
    await _notifications.cancelFocusNotification();
  }

  @override
  Future<void> logDistraction({required String runId, String? note}) async {
    final now = DateTime.now().toUtc();
    await _insertEvent(runId, null, 'distractionLogged', now, {'note': note});
  }

  Future<void> _publishRunCompletion({
    required FocusRunRow run,
    required int completedWorkIntervals,
    required DateTime completedAt,
  }) async {
    final callback = _onRunCompleted;
    if (callback == null || !_publishedCompletionRunIds.add(run.id)) {
      return;
    }
    final task = run.taskId == null
        ? null
        : await (_db.select(
            _db.tasks,
          )..where((row) => row.id.equals(run.taskId!))).getSingleOrNull();
    try {
      callback(
        FocusRunCompletionEvent(
          runId: run.id,
          taskId: run.taskId,
          taskTitle: task?.content,
          completedWorkIntervals: completedWorkIntervals,
          targetWorkIntervals: run.targetWorkIntervals,
          completedAt: completedAt,
        ),
      );
    } catch (_) {
      // Completion is committed; presentation callbacks are best-effort.
    }
  }

  Future<void> _stopExistingActiveRunIfAny({DateTime? now}) async {
    final active = await _activeRunRow();
    if (active != null) {
      await stopActiveRun(reason: StopFocusReason.interrupted, now: now);
    }
  }

  Future<FocusRunRow?> _activeRunRow() {
    return _activeFocusRunQuery().getSingleOrNull().then(
      (row) => row?.readTable(_db.focusRuns),
    );
  }

  Future<FocusIntervalRow?> _activeIntervalRow() {
    return _activeFocusIntervalQuery().getSingleOrNull().then(
      (row) => row?.readTable(_db.focusIntervals),
    );
  }

  Future<FocusPresetRow> _defaultPreset() async {
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

  Future<FocusPresetRow?> _presetById(String id) {
    return (_db.select(_db.focusPresets)
          ..where((row) => row.id.equals(id) & row.isDeleted.equals(false))
          ..limit(1))
        .getSingleOrNull();
  }

  Future<FocusPresetRow> _presetByIdOrDefault(String? id) async {
    if (id != null) {
      final preset = await _presetById(id);
      if (preset != null) {
        return preset;
      }
    }
    return _defaultPreset();
  }

  Future<FocusPresetRow> _presetForRun(FocusRunRow run) {
    return _presetByIdOrDefault(run.presetId);
  }

  Future<FocusPresetRow?> _presetForInterval(FocusIntervalRow interval) async {
    final run = await (_db.select(
      _db.focusRuns,
    )..where((row) => row.id.equals(interval.runId))).getSingleOrNull();
    if (run == null) {
      return null;
    }
    return _presetForRun(run);
  }

  Future<void> _createNextInterval({
    required FocusRunRow run,
    required String type,
    required String status,
    required int plannedSeconds,
    required DateTime startedAt,
    required int sequenceNumber,
  }) async {
    final intervalId = _uuid.v4();
    await _db
        .into(_db.focusIntervals)
        .insert(
          FocusIntervalsCompanion.insert(
            id: intervalId,
            runId: run.id,
            taskId: Value(run.taskId),
            projectId: Value(run.projectId),
            type: type,
            status: status,
            plannedSeconds: plannedSeconds,
            startedAt: startedAt,
            sequenceNumber: sequenceNumber,
            createdAt: startedAt,
            updatedAt: startedAt,
          ),
        );
    await _insertEvent(
      run.id,
      intervalId,
      status == 'ready' ? 'intervalReady' : 'intervalStarted',
      startedAt,
      {'type': type},
    );
  }

  _NextIntervalSpec _nextIntervalSpec({
    required String completed,
    required int completedWorkIntervals,
    required FocusPresetRow preset,
  }) {
    if (completed == 'work') {
      final isLongBreak =
          completedWorkIntervals % preset.intervalsBeforeLongBreak == 0;
      return _NextIntervalSpec(
        type: isLongBreak ? 'longBreak' : 'shortBreak',
        plannedSeconds: isLongBreak
            ? preset.longBreakSeconds
            : preset.shortBreakSeconds,
      );
    }
    return _NextIntervalSpec(type: 'work', plannedSeconds: preset.workSeconds);
  }

  String _nextIntervalStatus(String type, FocusPresetRow preset) {
    if (type == 'work') {
      return preset.autoStartWork ? 'running' : 'ready';
    }
    return preset.autoStartBreaks ? 'running' : 'ready';
  }

  Future<void> _validatePresetInput({
    required String name,
    required int workSeconds,
    required int shortBreakSeconds,
    required int longBreakSeconds,
    required int intervalsBeforeLongBreak,
    String? existingId,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Preset name is required');
    }
    for (final entry in {
      'workSeconds': workSeconds,
      'shortBreakSeconds': shortBreakSeconds,
      'longBreakSeconds': longBreakSeconds,
    }.entries) {
      if (entry.value < 60 || entry.value > 180 * 60) {
        throw ArgumentError.value(
          entry.value,
          entry.key,
          'Duration must be between 1 and 180 minutes',
        );
      }
    }
    if (intervalsBeforeLongBreak < 1 || intervalsBeforeLongBreak > 12) {
      throw ArgumentError.value(
        intervalsBeforeLongBreak,
        'intervalsBeforeLongBreak',
        'Long-break cadence must be between 1 and 12 intervals',
      );
    }

    final presets = await (_db.select(
      _db.focusPresets,
    )..where((row) => row.isDeleted.equals(false))).get();
    final normalized = trimmed.toLowerCase();
    final duplicate = presets.any(
      (preset) =>
          preset.id != existingId &&
          preset.name.trim().toLowerCase() == normalized,
    );
    if (duplicate) {
      throw ArgumentError.value(name, 'name', 'Preset name must be unique');
    }
  }

  Future<void> _insertEvent(
    String runId,
    String? intervalId,
    String type,
    DateTime occurredAt,
    Map<String, Object?>? payload,
  ) {
    return _db
        .into(_db.focusEvents)
        .insert(
          FocusEventsCompanion.insert(
            id: _uuid.v4(),
            runId: runId,
            intervalId: Value(intervalId),
            type: type,
            occurredAt: occurredAt,
            payloadJson: Value(payload == null ? null : jsonEncode(payload)),
            createdAt: occurredAt,
          ),
        );
  }

  Future<void> _recalculateTaskFocusAggregates(String taskId) async {
    final intervals =
        await (_db.select(_db.focusIntervals)..where(
              (interval) =>
                  interval.taskId.equals(taskId) &
                  interval.type.equals('work') &
                  interval.status.equals('completed') &
                  interval.isDeleted.equals(false),
            ))
            .get();
    final seconds = intervals.fold<int>(
      0,
      (sum, interval) => sum + _actualSeconds(interval),
    );
    await (_db.update(
      _db.tasks,
    )..where((task) => task.id.equals(taskId))).write(
      TasksCompanion(
        completedFocusIntervals: Value(intervals.length),
        totalFocusSeconds: Value(seconds),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  Future<void> _scheduleIntervalNotification({
    required String type,
    required DateTime startedAt,
    required int plannedSeconds,
    required int pausedTotalSeconds,
  }) {
    final endAt = calculateExpectedEndAt(
      startedAt: startedAt,
      plannedSeconds: plannedSeconds,
      pausedTotalSeconds: pausedTotalSeconds,
    );
    final label = switch (type) {
      'work' => 'Focus interval completed',
      'longBreak' => 'Long break completed',
      _ => 'Break completed',
    };
    return _notifications.scheduleFocusIntervalEnd(
      expectedEndAt: endAt,
      title: 'pomodoist',
      body: label,
    );
  }

  void _playSound(FocusSoundCue cue) {
    final soundPlayer = _soundPlayer;
    if (soundPlayer != null) {
      unawaited(soundPlayer.play(cue));
    }
  }

  int _actualSeconds(FocusIntervalRow row) {
    final end = row.completedAt ?? row.stoppedAt ?? DateTime.now().toUtc();
    final seconds =
        end.difference(row.startedAt).inSeconds - row.pausedTotalSeconds;
    return seconds < 0 ? 0 : seconds;
  }

  FocusRunItem _mapRun(FocusRunRow row) => FocusRunItem(
    id: row.id,
    userId: row.userId,
    taskId: row.taskId,
    projectId: row.projectId,
    presetId: row.presetId,
    status: row.status,
    startedAt: row.startedAt,
    endedAt: row.endedAt,
    targetWorkIntervals: row.targetWorkIntervals,
    completedWorkIntervals: row.completedWorkIntervals,
    note: row.note,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );

  FocusIntervalItem _mapInterval(FocusIntervalRow row) => FocusIntervalItem(
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

  FocusPresetItem _mapPreset(FocusPresetRow row) => FocusPresetItem(
    id: row.id,
    userId: row.userId,
    name: row.name,
    workSeconds: row.workSeconds,
    shortBreakSeconds: row.shortBreakSeconds,
    longBreakSeconds: row.longBreakSeconds,
    intervalsBeforeLongBreak: row.intervalsBeforeLongBreak,
    autoStartBreaks: row.autoStartBreaks,
    autoStartWork: row.autoStartWork,
    allowPause: row.allowPause,
    strictMode: row.strictMode,
    isDefault: row.isDefault,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );
}

class _NextIntervalSpec {
  const _NextIntervalSpec({required this.type, required this.plannedSeconds});
  final String type;
  final int plannedSeconds;
}
