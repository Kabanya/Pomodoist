import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart'
    show
        LucideIcons,
        ShadBadge,
        ShadBorder,
        ShadButton,
        ShadContextMenuItem,
        ShadIconButton,
        ShadInput,
        ShadMenubar,
        ShadMenubarItem,
        ShadTab,
        ShadTabs;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_l10n.dart';
import '../../../app/theme/app_motion.dart';
import '../../../app/formatters.dart';
import '../../../app/providers.dart';
import '../../../app/task_time.dart';
import '../../../app/task_detail_navigation.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/action_feedback.dart';
import '../../focus/domain/focus_models.dart';
import '../../focus/presentation/focus_view_mode.dart';
import '../../planning/domain/quick_add_parser.dart';
import '../domain/task_focus_estimate.dart';
import '../domain/task_models.dart';
import 'task_completion_feedback.dart';
import 'widgets/quick_add_bar.dart';
import 'widgets/quick_add_text_controller.dart';
import 'widgets/task_list_item.dart';
import 'widgets/task_motion.dart';

class TaskDetailScreen extends ConsumerStatefulWidget {
  const TaskDetailScreen({
    required this.taskId,
    this.onClose,
    this.isPanel = false,
    super.key,
  });

  final String taskId;
  final VoidCallback? onClose;
  final bool isPanel;

  @override
  ConsumerState<TaskDetailScreen> createState() => TaskDetailScreenState();
}

class TaskDetailScreenState extends ConsumerState<TaskDetailScreen> {
  final _titleKey = GlobalKey<_EditableTaskTitleState>();
  final _descriptionKey = GlobalKey<_EditableTaskDescriptionState>();
  late final TaskDetailSaveGuard _saveGuard;
  late final Future<bool> Function() _saveCallback;

  @override
  void initState() {
    super.initState();
    _saveGuard = ref.read(taskDetailSaveGuardProvider);
    _saveCallback = saveEdits;
    _saveGuard.save = _saveCallback;
  }

  @override
  void dispose() {
    if (_saveGuard.save == _saveCallback) _saveGuard.save = null;
    super.dispose();
  }

  Future<bool> saveEdits() async {
    final titleSaved =
        await (_titleKey.currentState?._finishEditing() ?? Future.value(true));
    final descriptionSaved =
        await (_descriptionKey.currentState?._save() ?? Future.value(true));
    return titleSaved && descriptionSaved;
  }

  Future<void> _goBack(BuildContext context) async {
    if (widget.onClose != null) {
      widget.onClose!();
      return;
    }
    if (!await saveEdits() || !context.mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/today');
    }
  }

  Widget _header(BuildContext context, [TaskItem? item]) {
    final l10n = context.l10n;
    return Row(
      children: [
        Tooltip(
          message: widget.isPanel ? l10n.commonClose : l10n.commonBack,
          child: ShadIconButton.ghost(
            onPressed: () => _goBack(context),
            icon: Icon(widget.isPanel ? LucideIcons.x : LucideIcons.arrowLeft),
            width: 40,
            height: 40,
          ),
        ),
        const Spacer(),
        if (item != null)
          Tooltip(
            message: l10n.taskMore,
            child: ShadMenubar(
              padding: EdgeInsets.zero,
              border: ShadBorder.none,
              backgroundColor: Colors.transparent,
              items: [
                ShadMenubarItem(
                  height: 40,
                  items: [
                    ShadContextMenuItem(
                      onPressed: () async {
                        if (!await saveEdits() || !context.mounted) return;
                        await deleteTaskWithRecurringPrompt(
                          context,
                          ref,
                          item,
                          onDeleted: () => Future<void>.delayed(
                            AppMotion.duration(context, AppMotion.task),
                            () {
                              if (context.mounted) _goBack(context);
                            },
                          ),
                        );
                      },
                      leading: const Icon(LucideIcons.trash2),
                      child: Text(l10n.commonDelete),
                    ),
                  ],
                  child: Semantics(
                    label: l10n.taskMore,
                    child: const Icon(LucideIcons.ellipsis),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _status(Widget child) => Column(
    children: [
      Padding(padding: const EdgeInsets.all(20), child: _header(context)),
      Expanded(child: Center(child: child)),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final taskId = widget.taskId;
    final l10n = context.l10n;
    final task = ref.watch(taskProvider(taskId));
    final taskRepository = ref.watch(taskRepositoryProvider);
    final focusRepository = ref.watch(focusRepositoryProvider);
    return BackButtonListener(
      onBackButtonPressed: () async {
        await _goBack(context);
        return true;
      },
      child: TaskMotionScope(
        key: ValueKey(taskId),
        builder: (context, motion) => SafeArea(
          child: task.when(
            data: (item) {
              if (item == null || item.isDeleted) {
                return _status(Text(l10n.taskNotFound));
              }
              final calendarLink = ref.watch(
                googleCalendarLinkProvider(item.id),
              );
              final presets = ref.watch(focusPresetsProvider).value ?? const [];
              final selectedPreset = selectedFocusPresetOrDefault(
                presets,
                ref.watch(lastFocusPresetIdProvider),
              );
              final focusEstimate = targetFocusIntervalsForTask(
                item,
                selectedPreset,
              );
              return TaskMotionItem(
                taskId: item.id,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _header(context, item),
                      _EditableTaskTitle(key: _titleKey, task: item),
                      const SizedBox(height: 12),
                      _EditableTaskDescription(
                        key: _descriptionKey,
                        task: item,
                      ),
                      const SizedBox(height: 16),
                      _TaskMetadataChips(
                        task: item,
                        calendarLinked: calendarLink.value != null,
                        focusEstimate: focusEstimate,
                      ),
                      const SizedBox(height: 20),
                      _ScheduleActions(task: item),
                      const SizedBox(height: 20),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ShadButton(
                            onPressed: item.isCompleted
                                ? null
                                : () async {
                                    final router = GoRouter.of(context);
                                    await focusRepository.startRun(
                                      StartFocusRunInput(
                                        taskId: item.id,
                                        projectId: item.projectId,
                                        presetId: selectedPreset?.id,
                                        targetWorkIntervals: _targetForStart(
                                          focusEstimate,
                                        ),
                                      ),
                                    );
                                    if (!context.mounted) {
                                      return;
                                    }
                                    showActionFeedback(
                                      context,
                                      message: l10n.focusStarted,
                                      icon: LucideIcons.circlePlay,
                                      haptic: AppHapticCue.none,
                                      action: SnackBarAction(
                                        label: l10n.commonOpen,
                                        onPressed: () => router.go('/focus'),
                                      ),
                                    );
                                  },
                            enabled: !(item.isCompleted),
                            leading: const Icon(LucideIcons.play),
                            child: Text(l10n.startFocus),
                          ),
                          ShadButton.outline(
                            onPressed: () async {
                              if (item.isCompleted) {
                                try {
                                  await taskRepository.uncompleteTask(item.id);
                                } catch (_) {
                                  if (context.mounted) {
                                    showActionFeedback(
                                      context,
                                      message: l10n.taskActionFailedCount(1),
                                      icon: LucideIcons.circleAlert,
                                      sound: ActionFeedbackSound.none,
                                      haptic: AppHapticCue.none,
                                    );
                                  }
                                  return;
                                }
                                if (!context.mounted) {
                                  return;
                                }
                                final reopened = await taskRepository
                                    .watchTask(item.id)
                                    .first;
                                if (!context.mounted) {
                                  return;
                                }
                                if (reopened != null) {
                                  motion.reopened([reopened]);
                                }
                                showActionFeedback(
                                  context,
                                  message: l10n.taskReopened,
                                  icon: LucideIcons.undo2,
                                );
                                return;
                              }

                              await completeTaskWithUndoFeedback(
                                context,
                                ref,
                                item.id,
                              );
                            },
                            leading: TaskCompletionControl(
                              taskId: item.id,
                              isCompleted: item.isCompleted,
                              color: context.appColors.accent,
                              fillColor: context.appColors.accentFill,
                              onPressed: null,
                            ),
                            child: Text(
                              item.isCompleted
                                  ? l10n.markOpen
                                  : l10n.markComplete,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _SubtasksSection(task: item),
                      const SizedBox(height: 16),
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: Text(l10n.recurrenceTitle),
                        children: [_RecurrenceActions(task: item)],
                      ),
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: Text(l10n.focusHistory),
                        children: [_FocusHistory(taskId: item.id)],
                      ),
                    ],
                  ),
                ),
              );
            },
            loading: () => _status(const CircularProgressIndicator()),
            error: (error, stackTrace) =>
                _status(Text(l10n.failedToLoadTask(error))),
          ),
        ),
      ),
    );
  }
}

class _TaskMetadataChips extends ConsumerWidget {
  const _TaskMetadataChips({
    required this.task,
    required this.calendarLinked,
    required this.focusEstimate,
  });

  final TaskItem task;
  final bool calendarLinked;
  final int? focusEstimate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final taskTimeState = ref.watch(taskTimeStateProvider(task));
    final taskTimeColor = taskTimeState == null
        ? null
        : colors.taskTimeColor(taskTimeState);
    final timeDisplayMode = ref.watch(taskTimeDisplayModeProvider);
    final defaultTimedBlockMinutes = ref.watch(
      quickAddDefaultTimedBlockMinutesProvider,
    );
    final scheduleLabel = formatTaskSchedule(
      context,
      task.schedule,
      displayMode: timeDisplayMode,
      defaultTimedBlockMinutes: defaultTimedBlockMinutes,
    );
    final scheduleSemanticLabel = taskTimeState == null
        ? scheduleLabel
        : '$scheduleLabel, ${taskTimeStatusLabel(l10n, taskTimeState)}';
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        Tooltip(
          message: l10n.priority(task.priority),
          child: ShadMenubar(
            key: const Key('task-detail-priority-chip'),
            padding: EdgeInsets.zero,
            border: ShadBorder.none,
            backgroundColor: Colors.transparent,
            items: [
              ShadMenubarItem(
                items: [
                  for (final priority in [1, 2, 3, 4])
                    ShadContextMenuItem(
                      trailing: Icon(
                        task.priority == priority ? LucideIcons.check : null,
                        size: 16,
                      ),
                      onPressed: () => unawaited(
                        ref
                            .read(taskRepositoryProvider)
                            .updateTask(
                              task.id,
                              UpdateTaskPatch(priority: priority),
                            ),
                      ),
                      child: Text(l10n.priority(priority)),
                    ),
                ],
                height: 36,
                buttonPadding: const EdgeInsets.symmetric(horizontal: 10),
                child: ShadBadge.secondary(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        LucideIcons.flag,
                        size: 16,
                        color: _priorityColor(task.priority, colors),
                      ),
                      const SizedBox(width: 6),
                      Text('p${task.priority}'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Tooltip(
          message: l10n.scheduleTitle,
          child: ShadMenubar(
            key: const Key('task-detail-schedule-chip'),
            padding: EdgeInsets.zero,
            border: ShadBorder.none,
            backgroundColor: Colors.transparent,
            items: [
              ShadMenubarItem(
                items: [
                  ShadContextMenuItem(
                    onPressed: () => unawaited(
                      _runScheduleQuickAction(
                        context,
                        ref,
                        task,
                        _ScheduleQuickAction.today,
                      ),
                    ),
                    child: Text(l10n.today),
                  ),
                  ShadContextMenuItem(
                    onPressed: () => unawaited(
                      _runScheduleQuickAction(
                        context,
                        ref,
                        task,
                        _ScheduleQuickAction.tomorrow,
                      ),
                    ),
                    child: Text(l10n.tomorrow),
                  ),
                  const Divider(height: 8),
                  ShadContextMenuItem(
                    onPressed: () => unawaited(
                      _runScheduleQuickAction(
                        context,
                        ref,
                        task,
                        _ScheduleQuickAction.allDay,
                      ),
                    ),
                    child: Text(l10n.allDay),
                  ),
                  ShadContextMenuItem(
                    onPressed: () => unawaited(
                      _runScheduleQuickAction(
                        context,
                        ref,
                        task,
                        _ScheduleQuickAction.timed,
                      ),
                    ),
                    child: Text(l10n.timedBlock),
                  ),
                  if (task.schedule != null) ...[
                    const Divider(height: 8),
                    ShadContextMenuItem(
                      onPressed: () => unawaited(
                        _runScheduleQuickAction(
                          context,
                          ref,
                          task,
                          _ScheduleQuickAction.clear,
                        ),
                      ),
                      child: Text(l10n.clearDate),
                    ),
                  ],
                ],
                height: 36,
                buttonPadding: const EdgeInsets.symmetric(horizontal: 10),
                child: Semantics(
                  key: const Key('task-detail-time-meta'),
                  label: scheduleSemanticLabel,
                  child: ShadBadge.secondary(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          LucideIcons.calendar,
                          size: 16,
                          key: const Key('task-detail-time-icon'),
                          color: taskTimeColor,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          scheduleLabel,
                          key: const Key('task-detail-time-label'),
                          style: TextStyle(color: taskTimeColor),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        ShadBadge.secondary(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.refreshCw, size: 16),
              const SizedBox(width: 6),
              Text(
                calendarLinked ? l10n.calendarLinked : l10n.calendarNotLinked,
              ),
            ],
          ),
        ),
        ShadBadge.secondary(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.timer, size: 16),
              const SizedBox(width: 6),
              Text(
                l10n.focusProgress(
                  task.completedFocusIntervals,
                  focusEstimate ?? 0,
                ),
              ),
            ],
          ),
        ),
        ShadBadge.secondary(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.history, size: 16),
              const SizedBox(width: 6),
              Text(formatFocusTime(context, task.totalFocusSeconds)),
            ],
          ),
        ),
      ],
    );
  }
}

enum _ScheduleQuickAction { today, tomorrow, allDay, timed, clear }

Future<void> _runScheduleQuickAction(
  BuildContext context,
  WidgetRef ref,
  TaskItem task,
  _ScheduleQuickAction action,
) {
  switch (action) {
    case _ScheduleQuickAction.today:
      final today = _today();
      return _setTaskSchedule(
        ref,
        task,
        task.schedule?.moveToDate(today) ?? TaskSchedule.allDay(today),
      );
    case _ScheduleQuickAction.tomorrow:
      final tomorrow = _today().add(const Duration(days: 1));
      return _setTaskSchedule(
        ref,
        task,
        task.schedule?.moveToDate(tomorrow) ?? TaskSchedule.allDay(tomorrow),
      );
    case _ScheduleQuickAction.allDay:
      return _pickAllDaySchedule(context, ref, task);
    case _ScheduleQuickAction.timed:
      return _pickTimedSchedule(context, ref, task);
    case _ScheduleQuickAction.clear:
      return _clearTaskSchedule(ref, task);
  }
}

class _EditableTaskTitle extends ConsumerStatefulWidget {
  const _EditableTaskTitle({required this.task, super.key});

  final TaskItem task;

  @override
  ConsumerState<_EditableTaskTitle> createState() => _EditableTaskTitleState();
}

class _EditableTaskTitleState extends ConsumerState<_EditableTaskTitle> {
  final _controller = QuickAddTextController();
  final _focusNode = FocusNode();
  bool _editing = false;
  bool _saving = false;
  Future<bool>? _pendingSave;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (_editing && !_focusNode.hasFocus) {
        unawaited(_finishEditing());
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.headlineMedium;
    if (_editing) {
      return QuickAddInput(
        controller: _controller,
        enabled: !_saving,
        focusNode: _focusNode,
        textFieldKey: const Key('task-title-editor'),
        autofocus: true,
        maxLines: 1,
        style: style,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(hintText: context.l10n.taskTitleHint),
        onSubmitted: (_) => unawaited(_finishEditing()),
      );
    }
    return MouseRegion(
      cursor: SystemMouseCursors.text,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: _startEditing,
        child: SizedBox(
          width: double.infinity,
          child: Text(
            widget.task.content,
            key: const Key('task-title-display'),
            style: style,
          ),
        ),
      ),
    );
  }

  void _startEditing() {
    _controller.text = widget.task.content;
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
    setState(() => _editing = true);
  }

  Future<bool> _finishEditing() {
    return _pendingSave ??= _persistTitle().whenComplete(
      () => _pendingSave = null,
    );
  }

  Future<bool> _persistTitle() async {
    if (!_editing) return true;
    try {
      final next = _controller.text.trim();
      if (next.isEmpty) {
        if (mounted) {
          setState(() => _editing = false);
        }
        return true;
      }
      final parsed = ref
          .read(quickAddParserProvider)
          .parse(next, defaultDate: widget.task.schedule?.displayDate);
      final content = _parsedTitleContent(parsed);
      var schedule = parsed.dueDate != null || parsed.schedule?.isTimed == true
          ? parsed.schedule
          : null;
      if (parsed.dueDate != null && schedule?.isAllDay == true) {
        schedule =
            widget.task.schedule?.moveToDate(parsed.dueDate!) ?? schedule;
      }
      final focusPreset = selectedFocusPresetOrDefault(
        ref.read(focusPresetsProvider).value ?? const [],
        ref.read(lastFocusPresetIdProvider),
      );
      final estimatedFocusIntervals = estimateFocusIntervalsForTaskDuration(
        schedule: parsed.schedule,
        durationSeconds: null,
        explicitEstimate: parsed.estimatedFocusIntervals,
        preset: focusPreset,
      );
      final patch = UpdateTaskPatch(
        content: content == widget.task.content ? null : content,
        priority: parsed.priority,
        schedule: schedule,
        dueDate: schedule == null ? parsed.dueDate : null,
        estimatedFocusIntervals: estimatedFocusIntervals,
        labelNames: parsed.labels.isEmpty ? null : parsed.labels,
      );
      final shouldUpdateTask =
          patch.content != null ||
          patch.priority != null ||
          patch.schedule != null ||
          patch.dueDate != null ||
          patch.estimatedFocusIntervals != null ||
          patch.labelNames != null;
      final shouldMoveTask = parsed.project != null;
      if (!shouldUpdateTask && !shouldMoveTask) {
        if (mounted) {
          setState(() => _editing = false);
        }
        return true;
      }
      setState(() => _saving = true);
      final taskRepository = ref.read(taskRepositoryProvider);
      if (shouldUpdateTask) {
        await taskRepository.updateTask(widget.task.id, patch);
      }
      final project = parsed.project;
      if (project != null) {
        final projectId = await ref
            .read(projectRepositoryProvider)
            .createProject(project);
        await taskRepository.moveTask(widget.task.id, projectId: projectId);
      }
      if (mounted) setState(() => _editing = false);
      return true;
    } catch (_) {
      if (mounted) _showEditFailure(context);
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  String _parsedTitleContent(ParsedQuickAdd parsed) {
    return parsed.content.isEmpty ? widget.task.content : parsed.content;
  }
}

void _showEditFailure(BuildContext context) {
  showActionFeedback(
    context,
    message: context.l10n.taskActionFailedCount(1),
    icon: LucideIcons.circleAlert,
    sound: ActionFeedbackSound.none,
    haptic: AppHapticCue.none,
  );
}

int? _targetForStart(int? estimate) {
  if (estimate == null) {
    return null;
  }
  return estimate < 1 ? 1 : estimate;
}

class _EditableTaskDescription extends ConsumerStatefulWidget {
  const _EditableTaskDescription({required this.task, super.key});

  final TaskItem task;

  @override
  ConsumerState<_EditableTaskDescription> createState() =>
      _EditableTaskDescriptionState();
}

class _EditableTaskDescriptionState
    extends ConsumerState<_EditableTaskDescription> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _saving = false;
  Future<bool>? _pendingSave;
  late String _savedText;

  @override
  void initState() {
    super.initState();
    _savedText = widget.task.description ?? '';
    _controller.text = _savedText;
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) {
        unawaited(_save());
      }
    });
  }

  @override
  void didUpdateWidget(covariant _EditableTaskDescription oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_focusNode.hasFocus || _saving || _controller.text != _savedText) {
      return;
    }
    final nextText = widget.task.description ?? '';
    _savedText = nextText;
    if (_controller.text != nextText) {
      _controller.text = nextText;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ShadInput(
      key: const Key('task-comment-editor'),
      controller: _controller,
      enabled: !_saving,
      focusNode: _focusNode,
      minLines: 1,
      maxLines: 5,
      textInputAction: TextInputAction.newline,
      placeholder: Text(context.l10n.taskCommentHint),
      top: Text(context.l10n.taskComment),
      leading: const Icon(LucideIcons.notebookPen),
    );
  }

  Future<bool> _save() {
    return _pendingSave ??= _persistDescription().whenComplete(
      () => _pendingSave = null,
    );
  }

  Future<bool> _persistDescription() async {
    final current = _savedText.trim();
    final draft = _controller.text;
    final next = draft.trim();
    if (next == current) {
      return true;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(taskRepositoryProvider)
          .updateTask(
            widget.task.id,
            UpdateTaskPatch(
              description: next.isEmpty ? null : next,
              updateDescription: true,
            ),
          );
      _savedText = draft;
      return true;
    } catch (_) {
      if (mounted) _showEditFailure(context);
      return false;
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
}

class _SubtasksSection extends ConsumerStatefulWidget {
  const _SubtasksSection({required this.task});

  final TaskItem task;

  @override
  ConsumerState<_SubtasksSection> createState() => _SubtasksSectionState();
}

class _SubtasksSectionState extends ConsumerState<_SubtasksSection> {
  final _controller = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tasks = ref.watch(tasksByQueryProvider(const TaskQuery.all()));
    final completedTasks = ref.watch(
      tasksByQueryProvider(const TaskQuery.completed()),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.subtasks, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        ShadInput(
          key: const Key('add-subtask-field'),
          controller: _controller,
          enabled: !_saving,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          placeholder: Text(l10n.addSubtaskHint),
          leading: const Icon(LucideIcons.cornerDownRight),
          trailing: Tooltip(
            message: l10n.addSubtask,
            child: ShadIconButton.ghost(
              onPressed: _saving ? null : _submit,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(LucideIcons.plus),
              enabled: !(_saving),
              width: 40,
              height: 40,
            ),
          ),
        ),
        const SizedBox(height: 12),
        tasks.when(
          data: (items) {
            final progressById = taskSubtaskProgressById([
              ...items,
              ...?completedTasks.value,
            ]);
            final children =
                items.where((task) => task.parentId == widget.task.id).toList()
                  ..sort(_compareTaskOrder);
            if (children.isEmpty) {
              return Text(
                l10n.noSubtasks,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              );
            }
            return Column(
              children: [
                for (final child in children)
                  TaskListItem(
                    task: child,
                    depth: 1,
                    subtaskProgress: progressById[child.id],
                  ),
              ],
            );
          },
          loading: () => const LinearProgressIndicator(),
          error: (error, stackTrace) => Text(l10n.failedToLoadTasks(error)),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    final input = _controller.text.trim();
    if (input.isEmpty || _saving) {
      return;
    }
    setState(() => _saving = true);
    try {
      final parsed = ref.read(quickAddParserProvider).parse(input);
      if (parsed.content.isEmpty) {
        return;
      }
      final focusPreset = selectedFocusPresetOrDefault(
        ref.read(focusPresetsProvider).value ?? const [],
        ref.read(lastFocusPresetIdProvider),
      );
      final estimatedFocusIntervals = estimateFocusIntervalsForTaskDuration(
        schedule: parsed.schedule,
        durationSeconds: null,
        explicitEstimate: parsed.estimatedFocusIntervals,
        preset: focusPreset,
      );
      await ref
          .read(taskRepositoryProvider)
          .createTask(
            CreateTaskInput(
              content: parsed.content,
              projectId: widget.task.projectId,
              sectionId: widget.task.sectionId,
              parentId: widget.task.id,
              priority: parsed.priority,
              labelNames: parsed.labels,
              schedule: parsed.schedule,
              dueDate: parsed.schedule == null ? parsed.dueDate : null,
              durationSeconds: parsed.schedule?.duration?.inSeconds,
              estimatedFocusIntervals: estimatedFocusIntervals,
            ),
          );
      _controller.clear();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.taskCreateFailed)));
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
}

int _compareTaskOrder(TaskItem a, TaskItem b) {
  final dayOrderCompare = (a.dayOrder ?? 999999).compareTo(
    b.dayOrder ?? 999999,
  );
  if (dayOrderCompare != 0) {
    return dayOrderCompare;
  }
  return a.orderKey.compareTo(b.orderKey);
}

class _ScheduleActions extends ConsumerWidget {
  const _ScheduleActions({required this.task});

  final TaskItem task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.scheduleTitle,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ShadButton.outline(
              onPressed: () => _pickAllDaySchedule(context, ref, task),
              leading: const Icon(LucideIcons.calendarCheck),
              child: Text(context.l10n.allDay),
            ),
            ShadButton.outline(
              onPressed: () => _pickTimedSchedule(context, ref, task),
              leading: const Icon(LucideIcons.clock),
              child: Text(context.l10n.timedBlock),
            ),
            if (task.schedule != null)
              ShadButton.ghost(
                onPressed: () => _clearTaskSchedule(ref, task),
                leading: const Icon(LucideIcons.calendarX),
                child: Text(context.l10n.commonClear),
              ),
          ],
        ),
      ],
    );
  }
}

class _RecurrenceActions extends ConsumerStatefulWidget {
  const _RecurrenceActions({required this.task});

  final TaskItem task;

  @override
  ConsumerState<_RecurrenceActions> createState() => _RecurrenceActionsState();
}

class _RecurrenceActionsState extends ConsumerState<_RecurrenceActions> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _showInterval(widget.task.schedule?.recurrence?.interval ?? 1);
  }

  @override
  void didUpdateWidget(covariant _RecurrenceActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_focusNode.hasFocus) {
      return;
    }
    _showInterval(widget.task.schedule?.recurrence?.interval ?? 1);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final schedule = widget.task.schedule;
    final recurrence = schedule?.recurrence;
    final unit = recurrence?.unit ?? TaskRecurrenceUnit.day;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ShadInput(
          key: const Key('task-recurrence-interval-input'),
          controller: _controller,
          focusNode: _focusNode,
          enabled: schedule != null,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onSubmitted: (_) => _save(unit),
          top: Text(l10n.recurrenceIntervalLabel),
          leading: const Icon(LucideIcons.repeat),
          bottom: _errorText == null
              ? null
              : Text(
                  _errorText!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
        ),
        const SizedBox(height: 10),
        IntrinsicWidth(
          child: ShadTabs<TaskRecurrenceUnit>(
            key: const Key('task-recurrence-unit-select'),
            value: unit,
            gap: 0,
            tabs: [
              ShadTab(
                value: TaskRecurrenceUnit.day,
                enabled: schedule != null,
                child: Text(l10n.recurrenceUnitDay),
              ),
              ShadTab(
                value: TaskRecurrenceUnit.week,
                enabled: schedule != null,
                child: Text(l10n.recurrenceUnitWeek),
              ),
              ShadTab(
                value: TaskRecurrenceUnit.month,
                enabled: schedule != null,
                child: Text(l10n.recurrenceUnitMonth),
              ),
            ],
            onChanged: _save,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ShadButton(
              key: const Key('task-recurrence-save-button'),
              onPressed: schedule == null ? null : () => _save(unit),
              enabled: !(schedule == null),
              leading: const Icon(LucideIcons.repeat),
              child: Text(l10n.commonSave),
            ),
            if (recurrence != null)
              ShadButton.ghost(
                key: const Key('task-recurrence-clear-button'),
                onPressed: _clear,
                leading: const Icon(LucideIcons.repeat1),
                child: Text(l10n.commonClear),
              ),
          ],
        ),
        if (schedule == null) ...[
          const SizedBox(height: 8),
          Text(
            l10n.recurrenceNeedsSchedule,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  void _showInterval(int interval) {
    _controller.value = TextEditingValue(
      text: '$interval',
      selection: TextSelection.collapsed(offset: '$interval'.length),
    );
  }

  Future<void> _save(TaskRecurrenceUnit unit) async {
    final schedule = widget.task.schedule;
    if (schedule == null) {
      return;
    }
    final interval = int.tryParse(_controller.text);
    if (interval == null || interval < 1 || interval > 999) {
      setState(() => _errorText = context.l10n.recurrenceInvalidInterval);
      return;
    }
    setState(() => _errorText = null);
    final existing = schedule.recurrence;
    final recurrence = TaskRecurrence(
      interval: interval,
      unit: unit,
      seriesId: existing?.seriesId ?? _newRecurrenceSeriesId(),
    );
    await _setTaskSchedule(
      ref,
      widget.task,
      schedule.withRecurrence(recurrence),
    );
  }

  Future<void> _clear() async {
    final schedule = widget.task.schedule;
    if (schedule == null) {
      return;
    }
    await _setTaskSchedule(
      ref,
      widget.task,
      schedule.withoutRecurrence(),
      preserveRecurrence: false,
    );
  }
}

Future<void> _pickAllDaySchedule(
  BuildContext context,
  WidgetRef ref,
  TaskItem task,
) async {
  final now = DateTime.now();
  final picked = await showDatePicker(
    context: context,
    initialDate: task.schedule?.displayDate ?? now,
    firstDate: DateTime(now.year - 5),
    lastDate: DateTime(now.year + 10),
  );
  if (picked == null) {
    return;
  }
  await _setTaskSchedule(ref, task, TaskSchedule.allDay(picked));
}

Future<void> _pickTimedSchedule(
  BuildContext context,
  WidgetRef ref,
  TaskItem task,
) async {
  final now = DateTime.now();
  final initialDate = task.schedule?.displayDate ?? now;
  final pickedDate = await showDatePicker(
    context: context,
    initialDate: initialDate,
    firstDate: DateTime(now.year - 5),
    lastDate: DateTime(now.year + 10),
  );
  if (pickedDate == null || !context.mounted) {
    return;
  }
  final currentStart = task.schedule?.isTimed ?? false
      ? task.schedule!.start!.toLocal()
      : DateTime(pickedDate.year, pickedDate.month, pickedDate.day, 9);
  final pickedStart = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(currentStart),
  );
  if (pickedStart == null || !context.mounted) {
    return;
  }
  final start = DateTime(
    pickedDate.year,
    pickedDate.month,
    pickedDate.day,
    pickedStart.hour,
    pickedStart.minute,
  );
  final currentDuration = task.schedule?.duration ?? const Duration(hours: 1);
  final pickedEnd = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(start.add(currentDuration)),
  );
  if (pickedEnd == null) {
    return;
  }
  var end = DateTime(
    pickedDate.year,
    pickedDate.month,
    pickedDate.day,
    pickedEnd.hour,
    pickedEnd.minute,
  );
  if (!end.isAfter(start)) {
    end = end.add(const Duration(days: 1));
  }
  await _setTaskSchedule(ref, task, TaskSchedule.timed(start: start, end: end));
}

Future<void> _setTaskSchedule(
  WidgetRef ref,
  TaskItem task,
  TaskSchedule schedule, {
  bool preserveRecurrence = true,
}) async {
  final recurrence = preserveRecurrence
      ? schedule.recurrence ?? task.schedule?.recurrence
      : schedule.recurrence;
  final seriesId = preserveRecurrence
      ? task.schedule?.recurrenceSeriesKey
      : schedule.recurrenceSeriesId;
  final nextSchedule = recurrence == null
      ? schedule.withRecurrenceSeriesId(seriesId)
      : schedule.withRecurrence(recurrence);
  await ref
      .read(taskRepositoryProvider)
      .updateTask(task.id, UpdateTaskPatch(schedule: nextSchedule));
}

Future<void> _clearTaskSchedule(WidgetRef ref, TaskItem task) async {
  await ref
      .read(taskRepositoryProvider)
      .updateTask(task.id, const UpdateTaskPatch(clearSchedule: true));
}

DateTime _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

String _newRecurrenceSeriesId() {
  return 'rec-${DateTime.now().toUtc().microsecondsSinceEpoch}';
}

Color _priorityColor(int priority, AppThemePalette colors) {
  return switch (priority) {
    1 => colors.overdue,
    2 => colors.warning,
    3 => colors.info,
    _ => colors.secondaryText,
  };
}

class _FocusHistory extends ConsumerWidget {
  const _FocusHistory({required this.taskId});

  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StreamBuilder<List<FocusIntervalItem>>(
      stream: ref.watch(focusRepositoryProvider).watchIntervalsForTask(taskId),
      builder: (context, snapshot) {
        final intervals = snapshot.data ?? const [];
        if (intervals.isEmpty) {
          return Text(context.l10n.noFocusIntervals);
        }
        return Column(
          children: [
            for (final interval in intervals.take(20))
              ListTile(
                leading: Icon(
                  interval.type == 'work'
                      ? LucideIcons.timer
                      : LucideIcons.coffee,
                ),
                title: Text(
                  '${focusIntervalTypeLabel(context.l10n, interval.type)} · '
                  '${focusIntervalStatusLabel(context.l10n, interval.status)}',
                ),
                subtitle: Text(
                  formatLocalDate(context, interval.startedAt.toLocal()),
                ),
                trailing: Text(
                  formatFocusTime(context, interval.plannedSeconds),
                ),
              ),
          ],
        );
      },
    );
  }
}
