import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_l10n.dart';
import '../../../app/formatters.dart';
import '../../../app/providers.dart';
import '../../../app/task_time.dart';
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

class TaskDetailScreen extends ConsumerWidget {
  const TaskDetailScreen({required this.taskId, super.key});

  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final task = ref.watch(taskProvider(taskId));
    final taskRepository = ref.watch(taskRepositoryProvider);
    final focusRepository = ref.watch(focusRepositoryProvider);
    return TaskMotionScope(
      key: ValueKey(taskId),
      builder: (context, motion) => SafeArea(
        child: task.when(
          data: (item) {
            if (item == null) {
              return Center(child: Text(l10n.taskNotFound));
            }
            final calendarLink = ref.watch(googleCalendarLinkProvider(item.id));
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
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        tooltip: l10n.commonBack,
                        onPressed: () => _goBack(context),
                        icon: const Icon(Icons.arrow_back),
                      ),
                    ),
                    _EditableTaskTitle(task: item),
                    const SizedBox(height: 12),
                    _EditableTaskDescription(task: item),
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
                        FilledButton.icon(
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
                                    icon: Icons.play_circle_outline,
                                    haptic: AppHapticCue.none,
                                    action: SnackBarAction(
                                      label: l10n.commonOpen,
                                      onPressed: () => router.go('/focus'),
                                    ),
                                  );
                                },
                          icon: const Icon(Icons.play_arrow),
                          label: Text(l10n.startFocus),
                        ),
                        OutlinedButton.icon(
                          onPressed: () async {
                            if (item.isCompleted) {
                              try {
                                await taskRepository.uncompleteTask(item.id);
                              } catch (_) {
                                if (context.mounted) {
                                  showActionFeedback(
                                    context,
                                    message: l10n.taskActionFailedCount(1),
                                    icon: Icons.error_outline,
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
                                icon: Icons.undo,
                              );
                              return;
                            }

                            await completeTaskWithUndoFeedback(
                              context,
                              ref,
                              item.id,
                            );
                          },
                          icon: TaskCompletionControl(
                            taskId: item.id,
                            isCompleted: item.isCompleted,
                            color: context.appColors.accent,
                            fillColor: context.appColors.accentFill,
                            onPressed: null,
                          ),
                          label: Text(
                            item.isCompleted
                                ? l10n.markOpen
                                : l10n.markComplete,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            await deleteTaskWithRecurringPrompt(
                              context,
                              ref,
                              item,
                              onDeleted: () => Future<void>.delayed(
                                MediaQuery.disableAnimationsOf(context)
                                    ? Duration.zero
                                    : const Duration(milliseconds: 220),
                                () {
                                  if (context.mounted) {
                                    _goBack(context);
                                  }
                                },
                              ),
                            );
                          },
                          icon: const Icon(Icons.delete_outline),
                          label: Text(l10n.commonDelete),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _RecurrenceActions(task: item),
                    const SizedBox(height: 24),
                    _SubtasksSection(task: item),
                    const SizedBox(height: 24),
                    Text(
                      l10n.focusHistory,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    _FocusHistory(taskId: item.id),
                  ],
                ),
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) =>
              Center(child: Text(l10n.failedToLoadTask(error))),
        ),
      ),
    );
  }
}

void _goBack(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go('/today');
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
        PopupMenuButton<int>(
          key: const Key('task-detail-priority-chip'),
          tooltip: l10n.priority(task.priority),
          onSelected: (priority) => unawaited(
            ref
                .read(taskRepositoryProvider)
                .updateTask(task.id, UpdateTaskPatch(priority: priority)),
          ),
          itemBuilder: (context) => [
            for (final priority in [1, 2, 3, 4])
              CheckedPopupMenuItem<int>(
                value: priority,
                checked: task.priority == priority,
                child: Text(l10n.priority(priority)),
              ),
          ],
          child: Chip(
            label: Text('p${task.priority}'),
            avatar: Icon(
              Icons.flag_outlined,
              color: _priorityColor(task.priority, colors),
            ),
          ),
        ),
        PopupMenuButton<_ScheduleQuickAction>(
          key: const Key('task-detail-schedule-chip'),
          tooltip: l10n.scheduleTitle,
          onSelected: (action) =>
              unawaited(_runScheduleQuickAction(context, ref, task, action)),
          itemBuilder: (context) => [
            PopupMenuItem(
              value: _ScheduleQuickAction.today,
              child: Text(l10n.today),
            ),
            PopupMenuItem(
              value: _ScheduleQuickAction.tomorrow,
              child: Text(l10n.tomorrow),
            ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: _ScheduleQuickAction.allDay,
              child: Text(l10n.allDay),
            ),
            PopupMenuItem(
              value: _ScheduleQuickAction.timed,
              child: Text(l10n.timedBlock),
            ),
            if (task.schedule != null) ...[
              const PopupMenuDivider(),
              PopupMenuItem(
                value: _ScheduleQuickAction.clear,
                child: Text(l10n.clearDate),
              ),
            ],
          ],
          child: Semantics(
            key: const Key('task-detail-time-meta'),
            label: scheduleSemanticLabel,
            child: Chip(
              label: Text(
                scheduleLabel,
                key: const Key('task-detail-time-label'),
                style: TextStyle(color: taskTimeColor),
              ),
              avatar: Icon(
                Icons.event,
                key: const Key('task-detail-time-icon'),
                color: taskTimeColor,
              ),
            ),
          ),
        ),
        Chip(
          label: Text(
            calendarLinked ? l10n.calendarLinked : l10n.calendarNotLinked,
          ),
          avatar: const Icon(Icons.sync),
        ),
        Chip(
          label: Text(
            l10n.focusProgress(
              task.completedFocusIntervals,
              focusEstimate ?? 0,
            ),
          ),
          avatar: const Icon(Icons.timer_outlined),
        ),
        Chip(
          label: Text(formatFocusTime(context, task.totalFocusSeconds)),
          avatar: const Icon(Icons.history),
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
      return _setTaskSchedule(ref, task, TaskSchedule.allDay(_today()));
    case _ScheduleQuickAction.tomorrow:
      return _setTaskSchedule(
        ref,
        task,
        TaskSchedule.allDay(_today().add(const Duration(days: 1))),
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
  const _EditableTaskTitle({required this.task});

  final TaskItem task;

  @override
  ConsumerState<_EditableTaskTitle> createState() => _EditableTaskTitleState();
}

class _EditableTaskTitleState extends ConsumerState<_EditableTaskTitle> {
  final _controller = QuickAddTextController();
  final _focusNode = FocusNode();
  bool _editing = false;
  bool _saving = false;

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
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
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

  Future<void> _finishEditing() async {
    if (_saving) {
      return;
    }
    final next = _controller.text.trim();
    if (next.isEmpty) {
      if (mounted) {
        setState(() => _editing = false);
      }
      return;
    }
    final parsed = ref
        .read(quickAddParserProvider)
        .parse(next, defaultDate: widget.task.schedule?.displayDate);
    final content = _parsedTitleContent(parsed);
    final schedule = parsed.dueDate != null || parsed.schedule?.isTimed == true
        ? parsed.schedule
        : null;
    final focusPreset = selectedFocusPresetOrDefault(
      ref.read(focusPresetsProvider).value ?? const [],
      ref.read(lastFocusPresetIdProvider),
    );
    final estimatedFocusIntervals = estimateFocusIntervalsForTaskDuration(
      schedule: schedule,
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
      return;
    }
    setState(() => _saving = true);
    try {
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
    } finally {
      if (mounted) {
        setState(() {
          _editing = false;
          _saving = false;
        });
      }
    }
  }

  String _parsedTitleContent(ParsedQuickAdd parsed) {
    return parsed.content.isEmpty ? widget.task.content : parsed.content;
  }
}

int? _targetForStart(int? estimate) {
  if (estimate == null) {
    return null;
  }
  return estimate < 1 ? 1 : estimate;
}

class _EditableTaskDescription extends ConsumerStatefulWidget {
  const _EditableTaskDescription({required this.task});

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

  @override
  void initState() {
    super.initState();
    _controller.text = widget.task.description ?? '';
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) {
        unawaited(_save());
      }
    });
  }

  @override
  void didUpdateWidget(covariant _EditableTaskDescription oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_focusNode.hasFocus || _saving) {
      return;
    }
    final nextText = widget.task.description ?? '';
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
    return TextField(
      key: const Key('task-comment-editor'),
      controller: _controller,
      focusNode: _focusNode,
      minLines: 1,
      maxLines: 5,
      textInputAction: TextInputAction.newline,
      decoration: InputDecoration(
        labelText: context.l10n.taskComment,
        hintText: context.l10n.taskCommentHint,
        prefixIcon: const Icon(Icons.notes_outlined),
      ),
    );
  }

  Future<void> _save() async {
    if (_saving) {
      return;
    }
    final current = widget.task.description?.trim() ?? '';
    final next = _controller.text.trim();
    if (next == current) {
      return;
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
        TextField(
          key: const Key('add-subtask-field'),
          controller: _controller,
          enabled: !_saving,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            hintText: l10n.addSubtaskHint,
            prefixIcon: const Icon(Icons.subdirectory_arrow_right),
            suffixIcon: IconButton(
              tooltip: l10n.addSubtask,
              onPressed: _saving ? null : _submit,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add),
            ),
          ),
          onSubmitted: (_) => _submit(),
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
            OutlinedButton.icon(
              onPressed: () => _pickAllDaySchedule(context, ref, task),
              icon: const Icon(Icons.event_available_outlined),
              label: Text(context.l10n.allDay),
            ),
            OutlinedButton.icon(
              onPressed: () => _pickTimedSchedule(context, ref, task),
              icon: const Icon(Icons.schedule),
              label: Text(context.l10n.timedBlock),
            ),
            if (task.schedule != null)
              TextButton.icon(
                onPressed: () => _clearTaskSchedule(ref, task),
                icon: const Icon(Icons.event_busy_outlined),
                label: Text(context.l10n.commonClear),
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
        Text(
          l10n.recurrenceTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('task-recurrence-interval-input'),
          controller: _controller,
          focusNode: _focusNode,
          enabled: schedule != null,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: l10n.recurrenceIntervalLabel,
            errorText: _errorText,
            prefixIcon: const Icon(Icons.repeat),
          ),
          onSubmitted: (_) => _save(unit),
        ),
        const SizedBox(height: 10),
        SegmentedButton<TaskRecurrenceUnit>(
          key: const Key('task-recurrence-unit-select'),
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
              value: TaskRecurrenceUnit.day,
              label: Text(l10n.recurrenceUnitDay),
            ),
            ButtonSegment(
              value: TaskRecurrenceUnit.week,
              label: Text(l10n.recurrenceUnitWeek),
            ),
            ButtonSegment(
              value: TaskRecurrenceUnit.month,
              label: Text(l10n.recurrenceUnitMonth),
            ),
          ],
          selected: {unit},
          onSelectionChanged: schedule == null
              ? null
              : (selection) => _save(selection.single),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              key: const Key('task-recurrence-save-button'),
              onPressed: schedule == null ? null : () => _save(unit),
              icon: const Icon(Icons.repeat),
              label: Text(l10n.commonSave),
            ),
            if (recurrence != null)
              TextButton.icon(
                key: const Key('task-recurrence-clear-button'),
                onPressed: _clear,
                icon: const Icon(Icons.repeat_one),
                label: Text(l10n.commonClear),
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
    1 => colors.accent,
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
                  interval.type == 'work' ? Icons.timer : Icons.coffee,
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
