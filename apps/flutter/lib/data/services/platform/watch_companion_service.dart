import 'dart:async';
import 'package:app_account/app_account.dart' show AccountSession;
import 'package:flutter/services.dart';
import 'package:pomodoist/domain/models/focus/focus_models.dart';
import 'package:pomodoist/domain/models/planning/task_decomposition.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/domain/models/platform/watch_companion.dart';

const watchCompanionChannelName = 'pomodoist/watch_companion';
const watchTaskCreateQuickAdd = 'task.createQuickAdd';
const watchTaskDecomposeTranscript = 'task.decomposeTranscript';
const watchTaskCommitDrafts = 'task.commitDrafts';
const watchTaskComplete = 'task.complete';
const watchTaskUncomplete = 'task.uncomplete';
const watchFocusStartDefault = 'focus.startDefault';
const watchFocusPause = 'focus.pause';
const watchFocusResume = 'focus.resume';
const watchFocusRestartInterval = 'focus.restartInterval';
const watchFocusComplete = 'focus.complete';
const watchFocusSkip = 'focus.skip';
const watchFocusStop = 'focus.stop';
const watchSnapshotRequest = 'snapshot.request';

Map<String, Object?> watchAccountSessionPayload(
  AccountSession? session, {
  required String environment,
  required String release,
  required String webAppUrl,
  required String? supabaseUrl,
  required String supabaseAnonKey,
  required String turnstileSiteKey,
  required String? sentryDsn,
}) {
  if (session == null ||
      session.accessToken == null ||
      session.refreshToken == null ||
      supabaseUrl == null ||
      supabaseAnonKey.isEmpty) {
    return {'signedIn': false};
  }
  return {
    'signedIn': true,
    'environment': environment,
    'release': release,
    'webAppUrl': webAppUrl,
    'supabaseUrl': supabaseUrl,
    'supabaseAnonKey': supabaseAnonKey,
    'anonKey': supabaseAnonKey,
    'turnstileSiteKey': turnstileSiteKey,
    'sentryDsn': sentryDsn ?? '',
    'userId': session.userId,
    'email': session.email,
    'accessToken': session.accessToken,
    'refreshToken': session.refreshToken,
    'expiresAt': session.expiresAt?.toUtc().toIso8601String(),
  };
}

/// Native protocol, serialization and subscription lifetime only.
class WatchCompanionService {
  WatchCompanionService({
    required Future<WatchCommandResult> Function(WatchCommand) execute,
    required Future<WatchSnapshot> Function() snapshot,
    required Iterable<Stream<Object?>> snapshotChanges,
    Map<String, Object?>? Function()? accountSessionProvider,
    MethodChannel channel = const MethodChannel(watchCompanionChannelName),
  }) : _execute = execute,
       _snapshot = snapshot,
       _snapshotChanges = snapshotChanges,
       _accountSessionProvider = accountSessionProvider,
       _channel = channel;

  final Future<WatchCommandResult> Function(WatchCommand) _execute;
  final Future<WatchSnapshot> Function() _snapshot;
  final Iterable<Stream<Object?>> _snapshotChanges;
  final Map<String, Object?>? Function()? _accountSessionProvider;
  final MethodChannel _channel;
  final _subscriptions = <StreamSubscription<Object?>>[];
  Timer? _pushTimer;
  bool _started = false;
  bool _disposed = false;

  void start() {
    if (_started || _disposed) return;
    _started = true;
    _channel.setMethodCallHandler(_handleMethodCall);
    for (final stream in _snapshotChanges) {
      _subscriptions.add(stream.listen((_) => _schedulePushSnapshot()));
    }
    unawaited(pushSnapshot());
  }

  void dispose() {
    _disposed = true;
    _started = false;
    _pushTimer?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    _channel.setMethodCallHandler(null);
  }

  Future<Map<String, Object?>> handleCommand(
    Map<String, Object?> command,
  ) async {
    try {
      final result = await _execute(_decodeCommand(command));
      if (result.ok && result.snapshot != null && _started && !_disposed) {
        unawaited(pushSnapshot());
      }
      return _encodeResult(result);
    } catch (error) {
      return {
        'ok': false,
        'error': error.toString(),
        'snapshot': await buildSnapshot(),
      };
    }
  }

  Future<Map<String, Object?>> buildSnapshot() async =>
      _encodeSnapshot(await _snapshot());

  Future<void> pushSnapshot() async {
    if (_disposed) return;
    try {
      final snapshot = await buildSnapshot();
      if (_disposed) return;
      await _channel.invokeMethod<void>('updateSnapshot', {
        'snapshot': snapshot,
        'accountSession': _accountSessionProvider?.call(),
      });
    } on MissingPluginException {
      // No native host on non-iOS platforms.
    } on PlatformException {
      // Best-effort delivery; command replies still carry snapshots.
    }
  }

  Future<Object?> _handleMethodCall(MethodCall call) async {
    if (call.method != 'command') {
      throw PlatformException(
        code: 'unsupported_method',
        message: 'Unsupported watch method: ${call.method}',
      );
    }
    return handleCommand(_stringKeyMap(call.arguments));
  }

  void _schedulePushSnapshot() {
    if (_disposed) return;
    _pushTimer?.cancel();
    _pushTimer = Timer(
      const Duration(milliseconds: 250),
      () => unawaited(pushSnapshot()),
    );
  }
}

WatchCommand _decodeCommand(Map<String, Object?> command) {
  final action = switch (command['type']) {
    watchTaskCreateQuickAdd => WatchAction.createTask,
    watchTaskDecomposeTranscript => WatchAction.decomposeTranscript,
    watchTaskCommitDrafts => WatchAction.commitDrafts,
    watchTaskComplete => WatchAction.completeTask,
    watchTaskUncomplete => WatchAction.uncompleteTask,
    watchFocusStartDefault => WatchAction.startFocus,
    watchFocusPause => WatchAction.pauseFocus,
    watchFocusResume => WatchAction.resumeFocus,
    watchFocusRestartInterval => WatchAction.restartInterval,
    watchFocusComplete => WatchAction.completeInterval,
    watchFocusSkip => WatchAction.skipInterval,
    watchFocusStop => WatchAction.stopFocus,
    watchSnapshotRequest => WatchAction.snapshot,
    final type => throw ArgumentError.value(
      type,
      'type',
      'Unsupported watch command',
    ),
  };
  return WatchCommand(
    action: action,
    id: _commandId(command),
    occurredAt: _commandTime(command),
    input: switch (action) {
      WatchAction.createTask => _requiredString(command, 'input'),
      WatchAction.decomposeTranscript => _requiredString(command, 'transcript'),
      _ => '',
    },
    taskId: switch (action) {
      WatchAction.completeTask ||
      WatchAction.uncompleteTask => _requiredTaskId(command),
      _ => _optionalString(command, 'taskId'),
    },
    presetId: _optionalString(command, 'presetId'),
    replaceActive: command['replaceActive'] == true,
    locale: command['locale'] as String?,
    drafts: action == WatchAction.commitDrafts
        ? [
            for (final draft in _draftMaps(command['tasks']))
              if ((draft['quickAdd'] ?? draft['input'])?.toString().trim()
                  case final String input when input.isNotEmpty)
                DecomposedTaskDraft(
                  quickAdd: input,
                  description: draft['description']?.toString(),
                ),
          ]
        : const [],
  );
}

Map<String, Object?> _encodeSnapshot(WatchSnapshot snapshot) => {
  'version': 1,
  'generatedAt': snapshot.generatedAt.toUtc().toIso8601String(),
  'locale': snapshot.locale,
  'focus': _focusMap(snapshot.run, snapshot.interval, snapshot.preset),
  'tasks': {
    for (final entry in snapshot.taskLists.entries)
      entry.key: _taskList(entry.value),
    'byProject': {
      for (final entry in snapshot.tasksByProject.entries)
        entry.key: _taskList(entry.value),
    },
  },
  'projects': [
    for (final project in snapshot.projects)
      _projectMap(project, snapshot.projectCounts[project.id] ?? 0),
  ],
  'sync': {'appliedCommandIds': snapshot.appliedCommandIds},
};

Map<String, Object?> _encodeResult(WatchCommandResult result) => {
  'ok': result.ok,
  if (result.conflict) ...{
    'conflict': true,
    'keepPending': true,
    'error': 'Open Pomodoist on iPhone to resolve',
  },
  if (result.error != null) 'error': result.error.toString(),
  if (result.appliedCommandId != null)
    'appliedCommandId': result.appliedCommandId,
  if (result.createdId != null) 'id': result.createdId,
  if (result.createdTaskIds != null) 'ids': result.createdTaskIds,
  if (result.drafts != null) 'tasks': result.drafts!.map(_draftMap).toList(),
  if (result.snapshot != null) 'snapshot': _encodeSnapshot(result.snapshot!),
};

Map<String, Object?> _focusMap(
  FocusRunItem? run,
  FocusIntervalItem? interval,
  FocusPresetItem? preset,
) {
  return {
    'active': run != null && interval != null,
    'presetId': preset?.id,
    'presetName': preset?.name,
    'preset': preset == null
        ? null
        : {
            'id': preset.id,
            'name': preset.name,
            'workSeconds': preset.workSeconds,
            'shortBreakSeconds': preset.shortBreakSeconds,
            'longBreakSeconds': preset.longBreakSeconds,
            'intervalsBeforeLongBreak': preset.intervalsBeforeLongBreak,
            'allowPause': preset.allowPause,
            'strictMode': preset.strictMode,
          },
    'run': run == null
        ? null
        : {
            'id': run.id,
            'status': run.status,
            'taskId': run.taskId,
            'projectId': run.projectId,
            'startedAt': run.startedAt.toUtc().toIso8601String(),
            'completedWorkIntervals': run.completedWorkIntervals,
            'targetWorkIntervals': run.targetWorkIntervals,
          },
    'interval': interval == null
        ? null
        : {
            'id': interval.id,
            'type': interval.type,
            'status': interval.status,
            'plannedSeconds': interval.plannedSeconds,
            'startedAt': interval.startedAt.toUtc().toIso8601String(),
            'pausedAt': interval.pausedAt?.toUtc().toIso8601String(),
            'pausedTotalSeconds': interval.pausedTotalSeconds,
            'sequenceNumber': interval.sequenceNumber,
          },
  };
}

List<Map<String, Object?>> _taskList(List<TaskItem> tasks) {
  return tasks.map(_taskMap).toList();
}

Map<String, Object?> _taskMap(TaskItem task) {
  return {
    'id': task.id,
    'content': task.content,
    'description': task.description,
    'projectId': task.projectId,
    'priority': task.priority,
    'completed': task.isCompleted,
    'schedule': _scheduleMap(task.schedule),
    'estimatedFocusIntervals': task.estimatedFocusIntervals,
    'completedFocusIntervals': task.completedFocusIntervals,
    'createdAt': task.createdAt.toUtc().toIso8601String(),
  };
}

Map<String, Object?>? _scheduleMap(TaskSchedule? schedule) {
  if (schedule == null) {
    return null;
  }
  return switch (schedule.kind) {
    TaskScheduleKind.allDay => {
      'kind': 'allDay',
      'date': _dateString(schedule.date!),
    },
    TaskScheduleKind.timed => {
      'kind': 'timed',
      'start': schedule.start!.toUtc().toIso8601String(),
      'end': schedule.end!.toUtc().toIso8601String(),
      'durationSeconds': schedule.duration?.inSeconds,
    },
  };
}

Map<String, Object?> _projectMap(ProjectItem project, int count) {
  return {
    'id': project.id,
    'name': project.name,
    'color': project.color,
    'openTaskCount': count,
  };
}

Map<String, Object?> _draftMap(DecomposedTaskDraft draft) {
  return {'quickAdd': draft.quickAdd, 'description': draft.description};
}

List<Map<String, Object?>> _draftMaps(Object? value) {
  if (value is! Iterable) {
    return const [];
  }
  return value
      .whereType<Map<Object?, Object?>>()
      .map(
        (map) => {
          for (final entry in map.entries)
            if (entry.key is String) entry.key! as String: entry.value,
        },
      )
      .toList();
}

Map<String, Object?> _stringKeyMap(Object? value) {
  if (value is! Map) {
    return const {};
  }
  return {
    for (final entry in value.entries)
      if (entry.key is String) entry.key! as String: entry.value,
  };
}

String _requiredString(Map<String, Object?> command, String key) {
  final value = command[key];
  if (value is String && value.trim().isNotEmpty) {
    return value;
  }
  throw ArgumentError.value(value, key, 'Expected non-empty string');
}

String _requiredTaskId(Map<String, Object?> command) {
  return _optionalString(command, 'taskId') ?? _requiredString(command, 'id');
}

String? _optionalString(Map<String, Object?> command, String key) {
  final value = command[key];
  if (value is String && value.trim().isNotEmpty) {
    return value;
  }
  return null;
}

String? _commandId(Map<String, Object?> command) {
  final id = _optionalString(command, 'id');
  if (id == null) {
    return null;
  }
  if (_optionalString(command, 'createdAt') != null ||
      _optionalString(command, 'occurredAt') != null ||
      _optionalString(command, 'baseSnapshotGeneratedAt') != null) {
    return id;
  }
  return null;
}

DateTime? _commandTime(Map<String, Object?> command) {
  for (final key in const ['occurredAt', 'createdAt']) {
    final value = command[key];
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) {
        return parsed.toUtc();
      }
    }
  }
  return null;
}

String _dateString(DateTime value) {
  return '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
