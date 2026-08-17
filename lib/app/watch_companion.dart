import 'dart:async';
import 'dart:ui';

import 'package:app_account/app_account.dart' show AccountSession;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'account_providers.dart';
import '../core/db/app_database.dart';
import '../features/focus/domain/focus_models.dart';
import '../features/focus/presentation/focus_view_mode.dart';
import '../features/planning/data/quick_add_service.dart';
import '../features/planning/data/task_decomposer.dart';
import '../features/tasks/domain/task_models.dart';
import 'providers.dart';
import 'runtime_public_config.dart';

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

final watchCompanionControllerProvider = Provider<WatchCompanionController>((
  ref,
) {
  ref.watch(accountAuthStateProvider);
  final selectedPresetId = ref.watch(lastFocusPresetIdProvider);
  final account = ref.watch(accountClientProvider);
  final runtimeConfig = ref.watch(runtimePublicConfigProvider);
  final controller = WatchCompanionController(
    taskRepository: ref.watch(taskRepositoryProvider),
    projectRepository: ref.watch(projectRepositoryProvider),
    focusRepository: ref.watch(focusRepositoryProvider),
    quickAddService: ref.watch(quickAddServiceProvider),
    taskDecomposer: ref.watch(taskDecomposerProvider),
    localeProvider: () => PlatformDispatcher.instance.locale.toLanguageTag(),
    selectedFocusPresetIdProvider: () => selectedPresetId,
    accountSessionProvider: () {
      return watchAccountSessionPayload(account?.currentSession, runtimeConfig);
    },
  );
  controller.start();
  ref.onDispose(controller.dispose);
  return controller;
});

Map<String, Object?> watchAccountSessionPayload(
  AccountSession? session,
  RuntimePublicConfig runtimeConfig,
) {
  if (session == null ||
      session.accessToken == null ||
      session.refreshToken == null ||
      runtimeConfig.supabaseUrl == null ||
      runtimeConfig.supabaseAnonKey.isEmpty) {
    return {'signedIn': false};
  }
  return {
    'signedIn': true,
    'environment': runtimeConfig.environment.name,
    'release': runtimeConfig.release,
    'webAppUrl': runtimeConfig.webAppUrl.toString(),
    'supabaseUrl': runtimeConfig.supabaseUrl.toString(),
    'supabaseAnonKey': runtimeConfig.supabaseAnonKey,
    'anonKey': runtimeConfig.supabaseAnonKey,
    'googleWebClientId': runtimeConfig.googleWebClientId,
    'turnstileSiteKey': runtimeConfig.turnstileSiteKey,
    'sentryDsn': runtimeConfig.sentryDsn?.toString() ?? '',
    'userId': session.userId,
    'email': session.email,
    'accessToken': session.accessToken,
    'refreshToken': session.refreshToken,
    'expiresAt': session.expiresAt?.toUtc().toIso8601String(),
  };
}

class WatchCompanionController {
  WatchCompanionController({
    required TaskRepository taskRepository,
    required ProjectRepository projectRepository,
    required FocusRepository focusRepository,
    required QuickAddService quickAddService,
    required TaskDecomposer taskDecomposer,
    required String Function() localeProvider,
    Map<String, Object?>? Function()? accountSessionProvider,
    String? Function()? selectedFocusPresetIdProvider,
    MethodChannel channel = const MethodChannel(watchCompanionChannelName),
    DateTime Function()? now,
  }) : _taskRepository = taskRepository,
       _projectRepository = projectRepository,
       _focusRepository = focusRepository,
       _quickAddService = quickAddService,
       _taskDecomposer = taskDecomposer,
       _localeProvider = localeProvider,
       _accountSessionProvider = accountSessionProvider,
       _selectedFocusPresetIdProvider = selectedFocusPresetIdProvider,
       _channel = channel,
       _now = now ?? DateTime.now;

  final TaskRepository _taskRepository;
  final ProjectRepository _projectRepository;
  final FocusRepository _focusRepository;
  final QuickAddService _quickAddService;
  final TaskDecomposer _taskDecomposer;
  final String Function() _localeProvider;
  final Map<String, Object?>? Function()? _accountSessionProvider;
  final String? Function()? _selectedFocusPresetIdProvider;
  final MethodChannel _channel;
  final DateTime Function() _now;
  final _subscriptions = <StreamSubscription<Object?>>[];
  final _appliedCommandIds = <String>{};
  Timer? _pushTimer;
  bool _started = false;

  void start() {
    if (_started) {
      return;
    }
    _started = true;
    _channel.setMethodCallHandler(_handleMethodCall);
    _watchForSnapshotChanges();
    unawaited(pushSnapshot());
  }

  void dispose() {
    _started = false;
    _pushTimer?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _channel.setMethodCallHandler(null);
  }

  Future<Map<String, Object?>> handleCommand(
    Map<String, Object?> command,
  ) async {
    final type = command['type'];
    final commandId = _commandId(command);
    if (commandId != null && _appliedCommandIds.contains(commandId)) {
      return await _ok(appliedCommandId: commandId);
    }
    try {
      switch (type) {
        case watchTaskCreateQuickAdd:
          final input = _requiredString(command, 'input');
          final id = await _quickAddService.createTask(input);
          return await _ok(extra: {'id': id}, appliedCommandId: commandId);
        case watchTaskDecomposeTranscript:
          return await _ok(
            extra: {'tasks': await _decomposeTranscript(command)},
            includeSnapshot: false,
            appliedCommandId: commandId,
          );
        case watchTaskCommitDrafts:
          final ids = await _commitDrafts(command['tasks']);
          return await _ok(extra: {'ids': ids}, appliedCommandId: commandId);
        case watchTaskComplete:
          await _taskRepository.completeTask(_requiredTaskId(command));
          return await _ok(appliedCommandId: commandId);
        case watchTaskUncomplete:
          await _taskRepository.uncompleteTask(_requiredTaskId(command));
          return await _ok(appliedCommandId: commandId);
        case watchFocusStartDefault:
          final activeRun = await _focusRepository.watchActiveRun().first;
          if (activeRun != null && command['replaceActive'] != true) {
            return await _focusConflict();
          }
          final id = await _focusRepository.startRun(
            StartFocusRunInput(
              taskId: _optionalString(command, 'taskId'),
              presetId:
                  _optionalString(command, 'presetId') ??
                  _selectedFocusPresetIdProvider?.call(),
            ),
            now: _commandTime(command),
          );
          return await _ok(extra: {'id': id}, appliedCommandId: commandId);
        case watchFocusPause:
          if ((await _focusRepository.watchActiveInterval().first)?.status !=
              'running') {
            return await _focusConflict();
          }
          await _focusRepository.pauseActiveInterval(
            now: _commandTime(command),
          );
          return await _ok(appliedCommandId: commandId);
        case watchFocusResume:
          if ((await _focusRepository.watchActiveInterval().first)?.status !=
              'paused') {
            return await _focusConflict();
          }
          await _focusRepository.resumeActiveInterval(
            now: _commandTime(command),
          );
          return await _ok(appliedCommandId: commandId);
        case watchFocusRestartInterval:
          if (await _focusRepository.watchActiveInterval().first == null) {
            return await _focusConflict();
          }
          await _focusRepository.restartActiveInterval(
            now: _commandTime(command),
          );
          return await _ok(appliedCommandId: commandId);
        case watchFocusComplete:
          if (await _focusRepository.watchActiveInterval().first == null) {
            return await _focusConflict();
          }
          await _focusRepository.completeActiveInterval(
            now: _commandTime(command),
          );
          return await _ok(appliedCommandId: commandId);
        case watchFocusSkip:
          if (await _focusRepository.watchActiveInterval().first == null) {
            return await _focusConflict();
          }
          await _focusRepository.skipActiveInterval(now: _commandTime(command));
          return await _ok(appliedCommandId: commandId);
        case watchFocusStop:
          if (await _focusRepository.watchActiveRun().first == null) {
            return await _focusConflict();
          }
          await _focusRepository.stopActiveRun(
            reason: StopFocusReason.stopped,
            now: _commandTime(command),
          );
          return await _ok(appliedCommandId: commandId);
        case watchSnapshotRequest:
          return await _ok();
        default:
          throw ArgumentError.value(type, 'type', 'Unsupported watch command');
      }
    } catch (error) {
      return {
        'ok': false,
        'error': error.toString(),
        'snapshot': await buildSnapshot(),
      };
    }
  }

  Future<Map<String, Object?>> buildSnapshot() async {
    final now = _now();
    final today = DateTime(now.year, now.month, now.day);
    final results = await Future.wait<Object?>([
      _focusRepository.watchActiveRun().first,
      _focusRepository.watchActiveInterval().first,
      _focusRepository.watchPresets().first,
      _taskRepository
          .watchTasks(TaskQuery(kind: TaskQueryKind.today, now: today))
          .first,
      _taskRepository
          .watchTasks(TaskQuery(kind: TaskQueryKind.upcoming, now: today))
          .first,
      _taskRepository.watchTasks(const TaskQuery.inbox()).first,
      _taskRepository.watchTasks(const TaskQuery.all()).first,
      _projectRepository.watchProjects().first,
    ]);

    final run = results[0] as FocusRunItem?;
    final interval = results[1] as FocusIntervalItem?;
    final presets = results[2] as List<FocusPresetItem>;
    final todayTasks = results[3] as List<TaskItem>;
    final upcomingTasks = results[4] as List<TaskItem>;
    final inboxTasks = results[5] as List<TaskItem>;
    final allTasks = results[6] as List<TaskItem>;
    final projects = results[7] as List<ProjectItem>;
    final preset = selectedFocusPresetOrDefault(
      presets,
      run?.presetId ?? _selectedFocusPresetIdProvider?.call(),
    );
    final counts = _projectCounts(allTasks);
    final recent = [...allTasks]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final visibleProjects = projects
        .where((project) => project.id != inboxProjectId && !project.isArchived)
        .toList();

    return {
      'version': 1,
      'generatedAt': now.toUtc().toIso8601String(),
      'focus': _focusMap(run, interval, preset),
      'tasks': {
        'today': _taskList(todayTasks),
        'upcoming': _taskList(upcomingTasks),
        'inbox': _taskList(inboxTasks),
        'recentAdded': _taskList(recent),
        'byProject': {
          for (final project in visibleProjects)
            project.id: _taskList(
              allTasks.where((task) => task.projectId == project.id).toList(),
            ),
        },
      },
      'projects': visibleProjects
          .map((project) => _projectMap(project, counts[project.id] ?? 0))
          .toList(),
      'sync': {'appliedCommandIds': _appliedCommandIds.toList()},
    };
  }

  Future<void> pushSnapshot() async {
    try {
      await _channel.invokeMethod<void>('updateSnapshot', {
        'snapshot': await buildSnapshot(),
        'accountSession': _accountSessionProvider?.call(),
      });
    } on MissingPluginException {
      // No native host on non-iOS platforms.
    } on PlatformException {
      // The watch host is best-effort; command replies still carry snapshots.
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

  void _watchForSnapshotChanges() {
    void watch(Stream<Object?> stream) {
      _subscriptions.add(stream.listen((_) => _schedulePushSnapshot()));
    }

    watch(_focusRepository.watchActiveRun());
    watch(_focusRepository.watchActiveInterval());
    watch(_focusRepository.watchPresets());
    watch(_taskRepository.watchTasks(const TaskQuery.today()));
    watch(_taskRepository.watchTasks(const TaskQuery.upcoming()));
    watch(_taskRepository.watchTasks(const TaskQuery.inbox()));
    watch(_taskRepository.watchTasks(const TaskQuery.all()));
    watch(_projectRepository.watchProjects());
  }

  void _schedulePushSnapshot() {
    _pushTimer?.cancel();
    _pushTimer = Timer(
      const Duration(milliseconds: 250),
      () => unawaited(pushSnapshot()),
    );
  }

  Future<Map<String, Object?>> _ok({
    Map<String, Object?> extra = const {},
    bool includeSnapshot = true,
    String? appliedCommandId,
  }) async {
    if (appliedCommandId != null) {
      _markApplied(appliedCommandId);
    }
    final result = <String, Object?>{'ok': true, ...extra};
    if (appliedCommandId != null) {
      result['appliedCommandId'] = appliedCommandId;
    }
    if (includeSnapshot) {
      result['snapshot'] = await buildSnapshot();
      if (_started) {
        unawaited(pushSnapshot());
      }
    }
    return result;
  }

  Future<Map<String, Object?>> _focusConflict() async {
    return {
      'ok': false,
      'conflict': true,
      'keepPending': true,
      'error': 'Open Pomodoist on iPhone to resolve',
      'snapshot': await buildSnapshot(),
    };
  }

  Future<List<Map<String, Object?>>> _decomposeTranscript(
    Map<String, Object?> command,
  ) async {
    final transcript = _requiredString(command, 'transcript').trim();
    if (transcript.isEmpty) {
      return const [];
    }
    final locale = (command['locale'] as String?)?.trim();
    final drafts = await _taskDecomposer.decompose(
      transcript,
      now: _now(),
      locale: locale == null || locale.isEmpty ? _localeProvider() : locale,
    );
    return drafts.map(_draftMap).toList();
  }

  Future<List<String>> _commitDrafts(Object? rawTasks) async {
    final ids = <String>[];
    for (final draft in _draftMaps(rawTasks)) {
      final quickAdd = (draft['quickAdd'] ?? draft['input'])?.toString().trim();
      if (quickAdd == null || quickAdd.isEmpty) {
        continue;
      }
      final description = draft['description']?.toString();
      ids.add(
        await _quickAddService.createTask(quickAdd, description: description),
      );
    }
    return ids;
  }

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
    return tasks.take(12).map(_taskMap).toList();
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

  Map<String, int> _projectCounts(List<TaskItem> tasks) {
    final counts = <String, int>{};
    for (final task in tasks) {
      counts.update(task.projectId, (count) => count + 1, ifAbsent: () => 1);
    }
    return counts;
  }

  void _markApplied(String commandId) {
    _appliedCommandIds.add(commandId);
    while (_appliedCommandIds.length > 200) {
      _appliedCommandIds.remove(_appliedCommandIds.first);
    }
  }
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
