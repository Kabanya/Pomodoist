import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/services/local/outbox_service.dart';
import 'package:pomodoist/data/services/local/shared_access.dart';
import 'package:pomodoist/data/services/local/task_repository_support.dart';
import 'package:pomodoist/domain/models/tasks/task_blocking.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/utils/result.dart';

class TaskBlockingStore {
  TaskBlockingStore(this.db, this.queue) {
    if (!_zonesReady) {
      tz_data.initializeTimeZones();
      _zonesReady = true;
    }
  }
  static bool _zonesReady = false;
  final AppDatabase db;
  final OutboxService queue;

  Future<TaskBlockingPolicy> policy({DateTime? now}) async {
    final records = await db.select(db.taskBlockingRecords).get();
    final data = {
      for (final row in records)
        row.id: Map<String, dynamic>.from(jsonDecode(row.dataJson) as Map),
    };
    final settings = data['settings'] ?? const <String, dynamic>{};
    final scopes = {
      for (final row in await db.select(db.sharedScopes).get())
        row.id: sharedScopeFromRow(row),
    };
    return TaskBlockingPolicy(
      tasks: (await db.select(db.tasks).get()).map(
        (r) => taskItemFromRow(r, scope: scopes[r.scopeId]),
      ),
      actorId: await SharedAccess(db).actorId(),
      now: now,
      priorityCascadeEnabled: settings['priorityCascadeEnabled'] == true,
      timeZone: settings['timeZone'] as String? ?? 'UTC',
      urgentSelections: {
        for (final entry in data.entries)
          if (entry.key != 'settings' && entry.value['taskId'] is String)
            entry.key: UrgentTaskSelection(
              taskId: entry.value['taskId'] as String,
              seriesId: entry.value['seriesId'] as String?,
              repeatWithSeries: entry.value['repeatWithSeries'] != false,
            ),
      },
    );
  }

  Stream<TaskBlockingPolicy> watchPolicy() {
    late StreamController<TaskBlockingPolicy> controller;
    StreamSubscription<Object?>? subscription;
    Timer? timer;
    Future<void> pending = Future.value();
    void refresh() {
      pending = pending.then((_) async {
        if (controller.isClosed) return;
        try {
          final next = await policy();
          if (!controller.isClosed) controller.add(next);
        } catch (error, stack) {
          if (!controller.isClosed) controller.addError(error, stack);
        }
      });
    }

    controller = StreamController<TaskBlockingPolicy>(
      onListen: () {
        subscription = db
            .customSelect(
              'SELECT 1',
              readsFrom: {
                db.tasks,
                db.taskBlockingRecords,
                db.sharedScopes,
                db.syncState,
              },
            )
            .watch()
            .listen((_) => refresh(), onError: controller.addError);
        timer = Timer.periodic(const Duration(seconds: 30), (_) => refresh());
      },
      onCancel: () async {
        timer?.cancel();
        await subscription?.cancel();
      },
    );
    return controller.stream;
  }

  Future<void> initializeSettings() async {
    if (await (db.select(
          db.taskBlockingRecords,
        )..where((r) => r.id.equals('settings'))).getSingleOrNull() ==
        null) {
      await _write('settings', await _settings());
    }
  }

  Future<Map<String, Object?>> _settings() async {
    final existing = await (db.select(
      db.taskBlockingRecords,
    )..where((r) => r.id.equals('settings'))).getSingleOrNull();
    if (existing != null) {
      return Map<String, Object?>.from(jsonDecode(existing.dataJson) as Map);
    }
    String zone = 'UTC';
    try {
      zone = (await FlutterTimezone.getLocalTimezone()).identifier;
    } on MissingPluginException {
      /* Unit tests have no native timezone plugin. */
    } on UnsupportedError {
      /* The fallback also supports headless clients. */
    }
    return {'priorityCascadeEnabled': false, 'timeZone': zone};
  }

  Future<void> _write(String id, Map<String, Object?> data) async {
    final now = DateTime.now().toUtc();
    final payload = {
      ...data,
      'id': id,
      'userId': localUserId,
      'updatedAt': now.toIso8601String(),
    };
    await db
        .into(db.taskBlockingRecords)
        .insertOnConflictUpdate(
          TaskBlockingRecordsCompanion.insert(
            id: id,
            dataJson: jsonEncode(payload),
            updatedAt: now,
          ),
        );
    await queue.enqueue(
      type: 'task_blocking.upsert',
      clientId: id,
      payload: payload,
    );
  }

  Future<Result<void>> setCascade(bool enabled) => Result.capture(() async {
    final settings = await _settings();
    await ownerBoundTransaction(
      db,
      queue,
      () =>
          _write('settings', {...settings, 'priorityCascadeEnabled': enabled}),
    );
  });
  Future<Result<void>> setUrgent(
    TaskItem task, {
    required bool urgent,
    bool repeatWithSeries = true,
  }) => Result.capture(() async {
    final settings = await _settings();
    await ownerBoundTransaction(db, queue, () async {
      final currentPolicy = await policy();
      final current = currentPolicy.tasks[task.id];
      if (current == null ||
          current.isDeleted ||
          current.isCompleted ||
          !current.canEdit ||
          current.scopeId != null &&
              !current.assigneeIds.contains(currentPolicy.actorId)) {
        throw ArgumentError('Only your own active tasks can be urgent');
      }
      await _write('settings', settings);
      await _write(currentPolicy.queueFor(current), {
        'taskId': urgent ? current.id : null,
        'seriesId': urgent ? current.schedule?.recurrenceSeriesKey : null,
        'repeatWithSeries': repeatWithSeries,
      });
    });
  });
}
