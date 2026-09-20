import 'package:pomodoist/domain/models/planning/task_decomposition.dart';
import 'package:pomodoist/data/repositories/planning/task_decomposition_repository.dart';
import 'package:pomodoist/data/repositories/projects/project_repository.dart';
import 'package:pomodoist/data/repositories/tasks/task_repository.dart';
import 'package:pomodoist/data/repositories/focus/focus_repository.dart';
import 'package:pomodoist/domain/models/focus/focus_models.dart';
import 'package:pomodoist/domain/use_cases/quick_add/quick_add_use_case.dart';
import 'package:pomodoist/domain/use_cases/quick_add/voice_quick_add_use_case.dart';
import 'package:pomodoist/domain/models/planning/quick_add_parser.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/domain/models/platform/watch_companion.dart';

class WatchCompanionUseCase {
  WatchCompanionUseCase({
    required TaskRepository taskRepository,
    required ProjectRepository projectRepository,
    required FocusRepository focusRepository,
    required QuickAddUseCase quickAddService,
    required VoiceQuickAddUseCase voiceQuickAdd,
    required TaskDecomposer taskDecomposer,
    required String Function() localeProvider,
    String? Function()? selectedFocusPresetIdProvider,
    DateTime Function()? now,
  }) : _taskRepository = taskRepository,
       _projectRepository = projectRepository,
       _focusRepository = focusRepository,
       _quickAddService = quickAddService,
       _voiceQuickAdd = voiceQuickAdd,
       _taskDecomposer = taskDecomposer,
       _localeProvider = localeProvider,
       _selectedFocusPresetIdProvider = selectedFocusPresetIdProvider,
       _now = now ?? DateTime.now;

  final TaskRepository _taskRepository;
  final ProjectRepository _projectRepository;
  final FocusRepository _focusRepository;
  final QuickAddUseCase _quickAddService;
  final VoiceQuickAddUseCase _voiceQuickAdd;
  final TaskDecomposer _taskDecomposer;
  final String Function() _localeProvider;
  final String? Function()? _selectedFocusPresetIdProvider;
  final DateTime Function() _now;
  final _appliedCommandIds = <String>{};

  Iterable<Stream<Object?>> get snapshotChanges => [
    _focusRepository.watchActiveRun(),
    _focusRepository.watchActiveInterval(),
    _focusRepository.watchPresets(),
    _taskRepository.watchTasks(const TaskQuery.today()),
    _taskRepository.watchTasks(const TaskQuery.upcoming()),
    _taskRepository.watchTasks(const TaskQuery.inbox()),
    _taskRepository.watchTasks(const TaskQuery.all()),
    _projectRepository.watchProjects(),
  ];

  Future<WatchCommandResult> execute(WatchCommand command) async {
    final type = command.action;
    final commandId = command.id;
    if (commandId != null && _appliedCommandIds.contains(commandId)) {
      return await _ok(appliedCommandId: commandId);
    }
    try {
      if (type == WatchAction.completeTask ||
          type == WatchAction.uncompleteTask) {
        await _requirePersonalTask(command.taskId!);
      }
      if (const {
        WatchAction.startFocus,
        WatchAction.pauseFocus,
        WatchAction.resumeFocus,
        WatchAction.restartInterval,
        WatchAction.completeInterval,
        WatchAction.skipInterval,
        WatchAction.stopFocus,
      }.contains(type)) {
        final taskId = type == WatchAction.startFocus
            ? command.taskId
            : (await _focusRepository.watchActiveRun().first)?.taskId;
        if (taskId != null) await _requirePersonalTask(taskId);
      }
      switch (type) {
        case WatchAction.createTask:
          final input = command.input;
          final id = await _createPersonalQuickAdd(input);
          return await _ok(createdId: id, appliedCommandId: commandId);
        case WatchAction.decomposeTranscript:
          return await _ok(
            drafts: await _decomposeTranscript(command),
            includeSnapshot: false,
            appliedCommandId: commandId,
          );
        case WatchAction.commitDrafts:
          final ids = await _commitDrafts(command.drafts);
          return await _ok(createdTaskIds: ids, appliedCommandId: commandId);
        case WatchAction.completeTask:
          await _taskRepository
              .completeTask(command.taskId!)
              .then((result) => result.getOrThrow());
          return await _ok(appliedCommandId: commandId);
        case WatchAction.uncompleteTask:
          await _taskRepository
              .uncompleteTask(command.taskId!)
              .then((result) => result.getOrThrow());
          return await _ok(appliedCommandId: commandId);
        case WatchAction.startFocus:
          final activeRun = await _focusRepository.watchActiveRun().first;
          if (activeRun != null && !command.replaceActive) {
            return await _focusConflict();
          }
          final id = await _focusRepository
              .startRun(
                StartFocusRunInput(
                  taskId: command.taskId,
                  presetId:
                      command.presetId ??
                      _selectedFocusPresetIdProvider?.call(),
                ),
                now: command.occurredAt,
              )
              .then((result) => result.getOrThrow());
          return await _ok(createdId: id, appliedCommandId: commandId);
        case WatchAction.pauseFocus:
          if ((await _focusRepository.watchActiveInterval().first)?.status !=
              'running') {
            return await _focusConflict();
          }
          await _focusRepository
              .pauseActiveInterval(now: command.occurredAt)
              .then((result) => result.getOrThrow());
          return await _ok(appliedCommandId: commandId);
        case WatchAction.resumeFocus:
          if ((await _focusRepository.watchActiveInterval().first)?.status !=
              'paused') {
            return await _focusConflict();
          }
          await _focusRepository
              .resumeActiveInterval(now: command.occurredAt)
              .then((result) => result.getOrThrow());
          return await _ok(appliedCommandId: commandId);
        case WatchAction.restartInterval:
          if (await _focusRepository.watchActiveInterval().first == null) {
            return await _focusConflict();
          }
          await _focusRepository
              .restartActiveInterval(now: command.occurredAt)
              .then((result) => result.getOrThrow());
          return await _ok(appliedCommandId: commandId);
        case WatchAction.completeInterval:
          if (await _focusRepository.watchActiveInterval().first == null) {
            return await _focusConflict();
          }
          await _focusRepository
              .completeActiveInterval(now: command.occurredAt)
              .then((result) => result.getOrThrow());
          return await _ok(appliedCommandId: commandId);
        case WatchAction.skipInterval:
          if (await _focusRepository.watchActiveInterval().first == null) {
            return await _focusConflict();
          }
          await _focusRepository
              .skipActiveInterval(now: command.occurredAt)
              .then((result) => result.getOrThrow());
          return await _ok(appliedCommandId: commandId);
        case WatchAction.stopFocus:
          if (await _focusRepository.watchActiveRun().first == null) {
            return await _focusConflict();
          }
          await _focusRepository
              .stopActiveRun(
                reason: StopFocusReason.stopped,
                now: command.occurredAt,
              )
              .then((result) => result.getOrThrow());
          return await _ok(appliedCommandId: commandId);
        case WatchAction.snapshot:
          return await _ok();
      }
    } catch (error) {
      return WatchCommandResult(
        ok: false,
        error: error,
        snapshot: await buildSnapshot(),
      );
    }
  }

  Future<WatchSnapshot> buildSnapshot() async {
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

    final activeRun = results[0] as FocusRunItem?;
    final run =
        activeRun?.taskId != null &&
            (await _taskRepository.watchTask(activeRun!.taskId!).first)
                    ?.scopeId !=
                null
        ? null
        : activeRun;
    final interval = run == null ? null : results[1] as FocusIntervalItem?;
    final presets = results[2] as List<FocusPresetItem>;
    final todayTasks = (results[3] as List<TaskItem>)
        .where((task) => task.scopeId == null)
        .toList();
    final upcomingTasks = (results[4] as List<TaskItem>)
        .where((task) => task.scopeId == null)
        .toList();
    final inboxTasks = (results[5] as List<TaskItem>)
        .where((task) => task.scopeId == null)
        .toList();
    final allTasks = (results[6] as List<TaskItem>)
        .where((task) => task.scopeId == null)
        .toList();
    final projects = results[7] as List<ProjectItem>;
    final preset = selectedFocusPresetOrDefault(
      presets,
      run?.presetId ?? _selectedFocusPresetIdProvider?.call(),
    );
    final counts = _projectCounts(allTasks);
    final recent = [...allTasks]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final visibleProjects = projects
        .where(
          (project) =>
              project.scopeId == null &&
              project.id != inboxProjectId &&
              !project.isArchived,
        )
        .toList();

    return WatchSnapshot(
      generatedAt: now,
      locale: _localeProvider(),
      run: run,
      interval: interval,
      preset: preset,
      taskLists: {
        'today': todayTasks.take(12).toList(),
        'upcoming': upcomingTasks.take(12).toList(),
        'inbox': inboxTasks.take(12).toList(),
        'recentAdded': recent.take(12).toList(),
      },
      tasksByProject: {
        for (final project in visibleProjects)
          project.id: allTasks
              .where((task) => task.projectId == project.id)
              .take(12)
              .toList(),
      },
      projects: visibleProjects,
      projectCounts: counts,
      appliedCommandIds: _appliedCommandIds,
    );
  }

  Future<WatchCommandResult> _ok({
    String? createdId,
    List<String>? createdTaskIds,
    List<DecomposedTaskDraft>? drafts,
    bool includeSnapshot = true,
    String? appliedCommandId,
  }) async {
    if (appliedCommandId != null) _markApplied(appliedCommandId);
    return WatchCommandResult(
      ok: true,
      createdId: createdId,
      createdTaskIds: createdTaskIds,
      drafts: drafts,
      appliedCommandId: appliedCommandId,
      snapshot: includeSnapshot ? await buildSnapshot() : null,
    );
  }

  Future<WatchCommandResult> _focusConflict() async => WatchCommandResult(
    ok: false,
    conflict: true,
    snapshot: await buildSnapshot(),
  );

  Future<List<DecomposedTaskDraft>> _decomposeTranscript(
    WatchCommand command,
  ) async {
    final transcript = command.input.trim();
    if (transcript.isEmpty) {
      return const [];
    }
    final locale = command.locale?.trim();
    final drafts = await _taskDecomposer.decompose(
      transcript,
      now: _now(),
      locale: locale == null || locale.isEmpty ? _localeProvider() : locale,
    );
    return drafts;
  }

  Future<void> _requirePersonalTask(String id) async {
    final task = await _taskRepository.watchTask(id).first;
    if (task?.scopeId != null) {
      throw StateError('Shared tasks are unavailable on Watch');
    }
  }

  Future<String> _createPersonalQuickAdd(
    String input, {
    String? description,
  }) async {
    final projectName = const QuickAddParser()
        .parse(input, now: _now())
        .project;
    if (projectName != null &&
        (await _projectRepository
                    .findByName(projectName)
                    .then((result) => result.getOrThrow()))
                ?.scopeId !=
            null) {
      throw StateError('Shared projects are unavailable on Watch');
    }
    return _quickAddService
        .createTask(input, description: description)
        .then((result) => result.getOrThrow());
  }

  Future<List<String>> _commitDrafts(List<DecomposedTaskDraft> drafts) async {
    await _requirePersonalDrafts(drafts);
    return _voiceQuickAdd.call(drafts);
  }

  Future<void> _requirePersonalDrafts(
    Iterable<DecomposedTaskDraft> drafts,
  ) async {
    for (final draft in drafts) {
      final quickAdd = draft.quickAdd.trim();
      if (quickAdd.isEmpty) {
        continue;
      }
      final projectName = const QuickAddParser()
          .parse(quickAdd, now: _now())
          .project;
      if (projectName != null &&
          (await _projectRepository
                      .findByName(projectName)
                      .then((result) => result.getOrThrow()))
                  ?.scopeId !=
              null) {
        throw StateError('Shared projects are unavailable on Watch');
      }
      await _requirePersonalDrafts(draft.subtasks);
    }
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
