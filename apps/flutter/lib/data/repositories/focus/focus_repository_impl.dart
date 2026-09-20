import 'package:pomodoist/utils/result.dart';
import 'package:pomodoist/data/repositories/focus/focus_repository.dart';
import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:pomodoist/data/services/audio/focus_sound_player.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart'
    hide FocusDailyStats;
import 'package:pomodoist/data/services/local/focus_local_service.dart';
import 'package:pomodoist/data/services/notifications/notification_scheduler.dart';
import 'package:pomodoist/data/services/local/outbox_service.dart';
import 'package:pomodoist/utils/timer_engine.dart';
import 'package:pomodoist/domain/models/focus/focus_models.dart';
import 'package:pomodoist/data/repositories/local/kanban_transition_coordinator.dart';

class DriftFocusRepository implements FocusRepository {
  DriftFocusRepository(
    AppDatabase db,
    this._syncQueue,
    this._notifications, {
    FocusSoundPlayer? soundPlayer,
    Uuid? uuid,
    KanbanTransitionCoordinator? kanbanTransitions,
    void Function(FocusRunCompletionEvent event)? onRunCompleted,
  }) : _db = db,
       _soundPlayer = soundPlayer,
       _onRunCompleted = onRunCompleted,
       _kanbanTransitions =
           kanbanTransitions ??
           KanbanTransitionCoordinator(db, _syncQueue, uuid: uuid),
       _uuid = uuid ?? const Uuid(),
       _focus = FocusLocalService(db);

  final AppDatabase _db;
  final OutboxService _syncQueue;
  final NotificationScheduler _notifications;
  final FocusSoundPlayer? _soundPlayer;
  final void Function(FocusRunCompletionEvent event)? _onRunCompleted;
  final KanbanTransitionCoordinator _kanbanTransitions;
  final Uuid _uuid;
  final FocusLocalService _focus;
  final Set<String> _publishedCompletionRunIds = <String>{};

  @override
  Stream<List<FocusPresetItem>> watchPresets() {
    return _focus.watchActivePresets().map(
      (rows) => List<FocusPresetItem>.unmodifiable(rows.map(_mapPreset)),
    );
  }

  @override
  Stream<FocusRunItem?> watchActiveRun() {
    return _focus.watchActiveRun().map(
      (row) => row == null ? null : _mapRun(row),
    );
  }

  @override
  Stream<FocusIntervalItem?> watchActiveInterval() {
    return _focus.watchActiveInterval().map(
      (row) => row == null ? null : _mapInterval(row),
    );
  }

  @override
  Stream<List<FocusRunItem>> watchRunsForTask(String taskId) {
    return _focus
        .watchRunsForTask(taskId)
        .map((rows) => List<FocusRunItem>.unmodifiable(rows.map(_mapRun)));
  }

  @override
  Stream<List<FocusIntervalItem>> watchIntervalsForTask(String taskId) {
    return _focus
        .watchIntervalsForTask(taskId)
        .map(
          (rows) =>
              List<FocusIntervalItem>.unmodifiable(rows.map(_mapInterval)),
        );
  }

  @override
  Stream<List<FocusIntervalItem>> watchIntervalsForRun(String runId) {
    return _focus
        .watchIntervalsForRun(runId)
        .map(
          (rows) =>
              List<FocusIntervalItem>.unmodifiable(rows.map(_mapInterval)),
        );
  }

  @override
  Stream<FocusDailyStats> watchDailyStats(DateTime localDate) {
    final day = DateTime(localDate.year, localDate.month, localDate.day);
    return _focus.watchNonDeletedIntervals().map((rows) {
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
  Future<Result<String>> createPreset(CreateFocusPresetInput input) =>
      Result.capture<String>(() async {
        final now = DateTime.now().toUtc();
        final id = _uuid.v4();
        await _validatePresetInput(
          name: input.name,
          workSeconds: input.workSeconds,
          shortBreakSeconds: input.shortBreakSeconds,
          longBreakSeconds: input.longBreakSeconds,
          intervalsBeforeLongBreak: input.intervalsBeforeLongBreak,
        );
        await _focus.insertPreset(
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
      });

  @override
  Future<Result<void>> updatePreset(String id, UpdateFocusPresetInput input) =>
      Result.capture<void>(() async {
        await _validatePresetInput(
          name: input.name,
          workSeconds: input.workSeconds,
          shortBreakSeconds: input.shortBreakSeconds,
          longBreakSeconds: input.longBreakSeconds,
          intervalsBeforeLongBreak: input.intervalsBeforeLongBreak,
          existingId: id,
        );
        final now = DateTime.now().toUtc();
        await _focus.updatePreset(
          id,
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
      });

  @override
  Future<Result<void>> deletePreset(String id) =>
      Result.capture<void>(() async {
        final preset = await _presetById(id);
        if (preset == null || preset.isDefault) {
          return;
        }
        final defaultPreset = await _defaultPreset();
        final now = DateTime.now().toUtc();
        await _db.transaction(() async {
          await _focus.markPresetDeleted(id, now);
          await _focus.reassignActiveRunsPreset(id, defaultPreset.id, now);
        });
      });

  @override
  Future<Result<void>> setDefaultPreset(String id) =>
      Result.capture<void>(() async {
        final preset = await _presetById(id);
        if (preset == null) {
          return;
        }
        final now = DateTime.now().toUtc();
        await _db.transaction(() async {
          await _focus.clearDefaultPresets(now);
          await _focus.markPresetDefault(id, now);
        });
      });

  @override
  Future<Result<void>> changeActiveRunPreset(String presetId) =>
      Result.capture<void>(() async {
        final preset = await _presetById(presetId);
        final run = await _activeRunRow();
        if (preset == null || run == null) {
          return;
        }
        final now = DateTime.now().toUtc();
        await _focus.updateRunPreset(run.id, preset.id, now);
      });

  @override
  Future<Result<String>> startRun(
    StartFocusRunInput input, {
    DateTime? now,
  }) => Result.capture<String>(() async {
    final timestamp = (now ?? DateTime.now()).toUtc();
    final task = input.taskId == null
        ? null
        : await _focus.findActiveTask(input.taskId!);
    if (input.taskId != null && task == null) {
      throw ArgumentError.value(input.taskId, 'taskId', 'Unknown task');
    }
    if (task?.status == 'completed') {
      throw StateError('Completed tasks must be restored before Focus starts');
    }
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
      final activeRun = await _activeRunRow();
      if (activeRun != null) {
        await _stopRunInTransaction(
          activeRun,
          await _activeIntervalRow(),
          status: 'interrupted',
          timestamp: timestamp,
        );
      }
      if (input.taskId != null) {
        await _kanbanTransitions.prepareTaskForFocusInTransaction(
          input.taskId!,
          timestamp: timestamp,
        );
      }
      await _focus.insertRun(
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
      await _focus.insertInterval(
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
  });

  @override
  Future<Result<void>> startReadyInterval() => Result.capture<void>(() async {
    final interval = await _activeIntervalRow();
    if (interval == null || interval.status != 'ready') {
      return;
    }
    final now = DateTime.now().toUtc();
    await _db.transaction(() async {
      await _focus.startInterval(interval.id, interval.runId, now);
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
  });

  @override
  Future<Result<void>> pauseActiveInterval({DateTime? now}) =>
      Result.capture<void>(() async {
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
          await _focus.pauseInterval(interval.id, interval.runId, timestamp);
          await _insertEvent(
            interval.runId,
            interval.id,
            'intervalPaused',
            timestamp,
            null,
          );
        });
        await _cancelFocusNotificationBestEffort();
        _playSound(FocusSoundCue.pause);
      });

  @override
  Future<Result<void>> resumeActiveInterval({DateTime? now}) =>
      Result.capture<void>(() async {
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
          await _focus.resumeInterval(
            interval.id,
            interval.runId,
            pausedTotal,
            timestamp,
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
      });

  @override
  Future<Result<void>> restartActiveInterval({DateTime? now}) =>
      Result.capture<void>(() async {
        final interval = await _activeIntervalRow();
        if (interval == null) {
          return;
        }
        final timestamp = (now ?? DateTime.now()).toUtc();
        await _db.transaction(() async {
          await _focus.restartInterval(interval.id, interval.runId, timestamp);
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
      });

  @override
  Future<Result<void>> completeActiveInterval({DateTime? now}) =>
      Result.capture<void>(() async {
        final interval = await _activeIntervalRow();
        if (interval == null || interval.status == 'ready') {
          return;
        }
        final run = await _focus.findRun(interval.runId);
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
          await _focus.completeInterval(interval.id, timestamp);
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
            await _focus.completeRun(run.id, completedWorkIntervals, timestamp);
            await _insertEvent(
              run.id,
              interval.id,
              'runCompleted',
              timestamp,
              null,
            );
          } else {
            await _focus.markRunInProgress(
              run.id,
              completedWorkIntervals,
              timestamp,
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
              payload: {
                'id': run.id,
                'completedAt': timestamp.toIso8601String(),
              },
            );
          }
        });
        await _cancelFocusNotificationBestEffort();
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
      });

  @override
  Future<Result<void>> skipActiveInterval({DateTime? now}) =>
      Result.capture<void>(() async {
        final interval = await _activeIntervalRow();
        if (interval == null) {
          return;
        }
        final run = await _focus.findRun(interval.runId);
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
          await _focus.skipInterval(interval.id, timestamp);
          await _insertEvent(
            interval.runId,
            interval.id,
            'intervalSkipped',
            timestamp,
            null,
          );
          if (interval.type == 'work') {
            await _focus.markRunActive(run.id, timestamp);
            await _createNextInterval(
              run: run,
              type: 'shortBreak',
              status: _nextIntervalStatus('shortBreak', preset),
              plannedSeconds: preset.shortBreakSeconds,
              startedAt: timestamp,
              sequenceNumber: interval.sequenceNumber + 1,
            );
          } else if (completesRun) {
            await _focus.finishRun(run.id, timestamp);
            await _insertEvent(
              run.id,
              interval.id,
              'runCompleted',
              timestamp,
              null,
            );
          } else {
            await _focus.markRunActive(run.id, timestamp);
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
              payload: {
                'id': run.id,
                'completedAt': timestamp.toIso8601String(),
              },
            );
          }
        });
        await _cancelFocusNotificationBestEffort();
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
      });

  @override
  Future<Result<void>> stopActiveRun({
    required StopFocusReason reason,
    DateTime? now,
  }) => Result.capture<void>(() async {
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
        await _focus.stopInterval(interval.id, timestamp);
      }
      await _focus.stopRun(run.id, status, timestamp);
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
    await _cancelFocusNotificationBestEffort();
  });

  @override
  Future<Result<void>> logDistraction({required String runId, String? note}) =>
      Result.capture<void>(() async {
        final now = DateTime.now().toUtc();
        await _insertEvent(runId, null, 'distractionLogged', now, {
          'note': note,
        });
      });

  Future<void> _publishRunCompletion({
    required FocusRunRow run,
    required int completedWorkIntervals,
    required DateTime completedAt,
  }) async {
    final callback = _onRunCompleted;
    if (callback == null || !_publishedCompletionRunIds.add(run.id)) {
      return;
    }
    try {
      final task = run.taskId == null
          ? null
          : await _focus.findTask(run.taskId!);
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

  Future<void> _stopRunInTransaction(
    FocusRunRow run,
    FocusIntervalRow? interval, {
    required String status,
    required DateTime timestamp,
  }) async {
    if (interval != null) {
      await _focus.stopInterval(interval.id, timestamp);
    }
    await _focus.stopRun(run.id, status, timestamp);
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
  }

  Future<FocusRunRow?> _activeRunRow() {
    return _focus.activeRun();
  }

  Future<FocusIntervalRow?> _activeIntervalRow() {
    return _focus.activeInterval();
  }

  Future<FocusPresetRow> _defaultPreset() {
    return _focus.defaultPreset();
  }

  Future<FocusPresetRow?> _presetById(String id) {
    return _focus.findPreset(id);
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
    final run = await _focus.findRun(interval.runId);
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
    await _focus.insertInterval(
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

    final presets = await _focus.nonDeletedPresets();
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
    return _focus.insertEvent(
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
    final intervals = await _focus.completedWorkIntervalsForTask(taskId);
    var seconds = intervals.fold<int>(
      0,
      (sum, interval) => sum + _actualSeconds(interval),
    );
    var count = intervals.length;
    final task = await _focus.findTask(taskId);
    if (task?.scopeId != null) {
      final localIds = intervals.map((row) => row.id).toSet();
      final shared = await _focus.sharedFocusIntervals(task!.scopeId!);
      for (final contribution in shared) {
        final data = jsonDecode(contribution.dataJson) as Map<String, dynamic>;
        if (data['taskId'] == taskId &&
            !localIds.contains(contribution.entityId)) {
          seconds += (data['durationSeconds'] as num?)?.toInt() ?? 0;
          count++;
        }
      }
    }
    await _focus.updateTaskFocusTotals(
      taskId,
      count,
      seconds,
      DateTime.now().toUtc(),
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
    return _notifications
        .scheduleFocusIntervalEnd(
          expectedEndAt: endAt,
          title: 'pomodoist',
          body: _notifications.focusCompletedBody(type),
        )
        .catchError((Object _) {
          // The focus state is already committed; notifications are advisory.
        });
  }

  Future<void> _cancelFocusNotificationBestEffort() =>
      _notifications.cancelFocusNotification().catchError((Object _) {
        // The focus state is already committed; notifications are advisory.
      });

  void _playSound(FocusSoundCue cue) {
    final soundPlayer = _soundPlayer;
    if (soundPlayer != null) {
      unawaited(soundPlayer.play(cue).catchError((Object _) {}));
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
