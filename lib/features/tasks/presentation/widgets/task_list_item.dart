import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_l10n.dart';
import '../../../../app/formatters.dart';
import '../../../../app/providers.dart';
import '../../../../app/task_time.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../app/widgets/action_feedback.dart';
import '../../../focus/domain/focus_models.dart';
import '../../../focus/presentation/focus_view_mode.dart';
import '../../domain/project_colors.dart';
import '../../domain/task_focus_estimate.dart';
import '../../domain/task_models.dart';
import '../task_completion_feedback.dart';
import 'project_color_picker.dart';

enum TaskListItemPresentation { standard, agenda }

class TaskSubtaskProgress {
  const TaskSubtaskProgress({required this.completed, required this.total});

  final int completed;
  final int total;

  String get label => '$completed/$total';
}

Map<String, TaskSubtaskProgress> taskSubtaskProgressById(
  Iterable<TaskItem> tasks,
) {
  final byId = <String, TaskItem>{for (final task in tasks) task.id: task};
  final childrenByParent = <String, List<TaskItem>>{};
  for (final task in byId.values) {
    final parentId = task.parentId;
    if (parentId == null || !byId.containsKey(parentId)) {
      continue;
    }
    childrenByParent.putIfAbsent(parentId, () => []).add(task);
  }

  final cache = <String, TaskSubtaskProgress>{};
  TaskSubtaskProgress countFor(String id, Set<String> path) {
    final cached = cache[id];
    if (cached != null) {
      return cached;
    }

    var completed = 0;
    var total = 0;
    for (final child in childrenByParent[id] ?? const <TaskItem>[]) {
      if (!path.add(child.id)) {
        continue;
      }
      total += 1;
      if (child.isCompleted) {
        completed += 1;
      }
      final childProgress = countFor(child.id, path);
      completed += childProgress.completed;
      total += childProgress.total;
      path.remove(child.id);
    }

    final progress = TaskSubtaskProgress(completed: completed, total: total);
    cache[id] = progress;
    return progress;
  }

  final result = <String, TaskSubtaskProgress>{};
  for (final id in byId.keys) {
    final progress = countFor(id, {id});
    if (progress.total > 0) {
      result[id] = progress;
    }
  }
  return result;
}

Future<void> deleteTaskWithRecurringPrompt(
  BuildContext context,
  WidgetRef ref,
  TaskItem task, {
  VoidCallback? onDeleted,
}) async {
  final schedule = task.schedule;
  final includeFollowing = schedule?.isRecurringOccurrence ?? false
      ? await showDialog<bool>(
          context: context,
          builder: (context) {
            final l10n = context.l10n;
            return AlertDialog(
              title: Text(l10n.recurringDeleteTitle),
              content: Text(l10n.recurringDeleteMessage),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.commonCancel),
                ),
                TextButton(
                  key: const Key('delete-recurring-this-button'),
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(l10n.recurringDeleteThis),
                ),
                FilledButton(
                  key: const Key('delete-recurring-following-button'),
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(l10n.recurringDeleteThisAndFollowing),
                ),
              ],
            );
          },
        )
      : false;
  if (includeFollowing == null) {
    return;
  }

  final repository = ref.read(taskRepositoryProvider);
  if (schedule?.isRecurringOccurrence ?? false) {
    await repository.deleteRecurringOccurrence(
      task.id,
      includeFollowing: includeFollowing,
    );
  } else {
    await repository.deleteTask(task.id);
  }
  if (!context.mounted) {
    return;
  }
  showActionFeedback(
    context,
    message: context.l10n.taskDeleted,
    icon: Icons.delete_outline,
  );
  onDeleted?.call();
}

class TaskListItem extends ConsumerWidget {
  const TaskListItem({
    required this.task,
    this.depth = 0,
    this.subtaskProgress,
    this.enableSubtaskDrop = true,
    this.presentation = TaskListItemPresentation.standard,
    this.project,
    super.key,
  });

  final TaskItem task;
  final int depth;
  final TaskSubtaskProgress? subtaskProgress;
  final bool enableSubtaskDrop;
  final TaskListItemPresentation presentation;
  final ProjectItem? project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final taskRepository = ref.watch(taskRepositoryProvider);
    final focusRepository = ref.watch(focusRepositoryProvider);
    final presets = ref.watch(focusPresetsProvider).value ?? const [];
    final selectedPreset = selectedFocusPresetOrDefault(
      presets,
      ref.watch(lastFocusPresetIdProvider),
    );
    final focusEstimate = targetFocusIntervalsForTask(task, selectedPreset);
    final colorScheme = Theme.of(context).colorScheme;
    final colors = context.appColors;
    final taskTimeState = ref.watch(taskTimeStateProvider(task));
    final timeDisplayMode = ref.watch(taskTimeDisplayModeProvider);
    final defaultTimedBlockMinutes = ref.watch(
      quickAddDefaultTimedBlockMinutesProvider,
    );
    final description = task.description?.trim();
    final hasDescription = description != null && description.isNotEmpty;
    final hasMeta = _hasListMeta(task, focusEstimate, subtaskProgress);
    final isAgenda = presentation == TaskListItemPresentation.agenda;

    Widget focusAction({Key? key}) {
      return IconButton(
        key: key,
        tooltip: l10n.startFocus,
        onPressed: task.isCompleted
            ? null
            : () async {
                final router = GoRouter.of(context);
                await focusRepository.startRun(
                  StartFocusRunInput(
                    taskId: task.id,
                    projectId: task.projectId,
                    presetId: selectedPreset?.id,
                    targetWorkIntervals: _targetForStart(focusEstimate),
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
        style: IconButton.styleFrom(
          backgroundColor: colors.accentTint,
          foregroundColor: colors.accent,
          disabledBackgroundColor: Colors.transparent,
          disabledForegroundColor: colors.mutedText,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        icon: const Icon(Icons.play_arrow),
      );
    }

    Widget overflowAction() {
      return Builder(
        builder: (buttonContext) => IconButton(
          key: ValueKey('agenda-overflow-action-${task.id}'),
          tooltip: l10n.moreFocusActions,
          visualDensity: VisualDensity.compact,
          onPressed: () {
            final renderObject = buttonContext.findRenderObject();
            if (renderObject is! RenderBox) {
              return;
            }
            final position = renderObject.localToGlobal(
              Offset(renderObject.size.width, renderObject.size.height),
            );
            unawaited(_showQuickActions(buttonContext, ref, position));
          },
          icon: const Icon(Icons.more_horiz),
        ),
      );
    }

    Widget row(
      bool accepting, {
      required bool agendaDesktop,
      required bool showAgendaFocusAction,
    }) {
      final trailingAction = switch (presentation) {
        TaskListItemPresentation.standard => focusAction(),
        TaskListItemPresentation.agenda when agendaDesktop => SizedBox(
          key: ValueKey('agenda-focus-slot-${task.id}'),
          width: 48,
          height: 48,
          child: showAgendaFocusAction
              ? focusAction(key: ValueKey('agenda-focus-action-${task.id}'))
              : null,
        ),
        TaskListItemPresentation.agenda => overflowAction(),
      };
      return Material(
        color: accepting ? colors.accentTint : Colors.transparent,
        child: InkWell(
          key: ValueKey('task-list-item-row-${task.id}'),
          hoverColor: colors.surfaceTint,
          onTap: () => context.push('/task/${task.id}'),
          onSecondaryTapDown: (details) => unawaited(
            _showQuickActions(context, ref, details.globalPosition),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              depth * 18,
              isAgenda ? 4 : 10,
              4,
              isAgenda ? 4 : 10,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 34,
                  child: Checkbox(
                    value: task.isCompleted,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: const CircleBorder(),
                    side: BorderSide(
                      color: task.isCompleted
                          ? colors.accent
                          : _priorityColor(task.priority, colorScheme, colors),
                      width: 1.4,
                    ),
                    fillColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return colors.accentFill;
                      }
                      return Colors.transparent;
                    }),
                    checkColor: Colors.white,
                    onChanged: (_) async {
                      if (task.isCompleted) {
                        await taskRepository.uncompleteTask(task.id);
                        if (!context.mounted) {
                          return;
                        }
                        showActionFeedback(
                          context,
                          message: l10n.taskReopened,
                          icon: Icons.undo,
                        );
                        return;
                      }

                      await completeTaskWithUndoFeedback(context, ref, task.id);
                    },
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _TaskTextDragSource(
                    task: task,
                    child: isAgenda
                        ? _AgendaTaskContent(
                            task: task,
                            project: project,
                            focusEstimate: focusEstimate,
                            subtaskProgress: subtaskProgress,
                            allowMetadataWrap: !agendaDesktop,
                            taskTimeState: taskTimeState,
                            timeDisplayMode: timeDisplayMode,
                            defaultTimedBlockMinutes: defaultTimedBlockMinutes,
                          )
                        : _TaskContent(
                            task: task,
                            description: description,
                            hasDescription: hasDescription,
                            hasMeta: hasMeta,
                            focusEstimate: focusEstimate,
                            subtaskProgress: subtaskProgress,
                            taskTimeState: taskTimeState,
                            timeDisplayMode: timeDisplayMode,
                            defaultTimedBlockMinutes: defaultTimedBlockMinutes,
                          ),
                  ),
                ),
                const SizedBox(width: 8),
                trailingAction,
              ],
            ),
          ),
        ),
      );
    }

    Widget rowWithDropTarget({
      required bool agendaDesktop,
      required bool showAgendaFocusAction,
    }) {
      if (!enableSubtaskDrop) {
        return row(
          false,
          agendaDesktop: agendaDesktop,
          showAgendaFocusAction: showAgendaFocusAction,
        );
      }

      return DragTarget<String>(
        onWillAcceptWithDetails: (details) => details.data != task.id,
        onAcceptWithDetails: (details) =>
            unawaited(_moveDroppedTask(context, ref, details.data)),
        builder: (context, candidateData, rejectedData) => row(
          candidateData.isNotEmpty,
          agendaDesktop: agendaDesktop,
          showAgendaFocusAction: showAgendaFocusAction,
        ),
      );
    }

    if (!isAgenda) {
      return rowWithDropTarget(
        agendaDesktop: false,
        showAgendaFocusAction: true,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 760;
        return _AgendaInteractionRegion(
          taskId: task.id,
          builder: (context, isActive) => rowWithDropTarget(
            agendaDesktop: isDesktop,
            showAgendaFocusAction: isDesktop && isActive,
          ),
        );
      },
    );
  }

  Color _priorityColor(
    int priority,
    ColorScheme scheme,
    AppThemePalette colors,
  ) {
    return switch (priority) {
      1 => colors.accent,
      2 => colors.warning,
      3 => colors.info,
      _ => scheme.outline,
    };
  }

  bool _hasListMeta(
    TaskItem task,
    int? focusEstimate,
    TaskSubtaskProgress? subtaskProgress,
  ) {
    return task.schedule != null ||
        focusEstimate != null ||
        (subtaskProgress?.total ?? 0) > 0;
  }

  Future<void> _showQuickActions(
    BuildContext context,
    WidgetRef ref,
    Offset position,
  ) async {
    final l10n = context.l10n;
    final colors = context.appColors;
    final action = await showMenu<_TaskQuickAction>(
      context: context,
      position: _menuPosition(context, position),
      items: [
        PopupMenuItem(
          value: _TaskQuickAction.startFocus,
          enabled: !task.isCompleted,
          child: _TaskMenuRow(icon: Icons.play_arrow, label: l10n.startFocus),
        ),
        PopupMenuItem(
          value: _TaskQuickAction.toggleComplete,
          child: _TaskMenuRow(
            icon: task.isCompleted ? Icons.undo : Icons.check,
            label: task.isCompleted ? l10n.markOpen : l10n.markComplete,
          ),
        ),
        if (task.parentId != null)
          PopupMenuItem(
            value: _TaskQuickAction.makeParent,
            child: _TaskMenuRow(
              icon: Icons.format_indent_decrease,
              label: l10n.makeParentTask,
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _TaskQuickAction.today,
          child: _TaskMenuRow(icon: Icons.today_outlined, label: l10n.today),
        ),
        PopupMenuItem(
          value: _TaskQuickAction.tomorrow,
          child: _TaskMenuRow(icon: Icons.event_outlined, label: l10n.tomorrow),
        ),
        if (task.schedule != null)
          PopupMenuItem(
            value: _TaskQuickAction.clearDate,
            child: _TaskMenuRow(
              icon: Icons.event_busy_outlined,
              label: l10n.clearDate,
            ),
          ),
        const PopupMenuDivider(),
        for (final priority in [1, 2, 3, 4])
          PopupMenuItem(
            value: _priorityAction(priority),
            child: _TaskMenuRow(
              icon: Icons.flag_outlined,
              label: l10n.priority(priority),
              selected: task.priority == priority,
              color: _priorityColor(
                priority,
                Theme.of(context).colorScheme,
                colors,
              ),
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _TaskQuickAction.delete,
          child: _TaskMenuRow(
            icon: Icons.delete_outline,
            label: l10n.commonDelete,
            color: colors.accent,
          ),
        ),
      ],
    );
    if (action == null || !context.mounted) {
      return;
    }
    await _runQuickAction(context, ref, action);
  }

  RelativeRect _menuPosition(BuildContext context, Offset globalPosition) {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final position = overlay.globalToLocal(globalPosition);
    return RelativeRect.fromRect(
      Rect.fromLTWH(position.dx, position.dy, 0, 0),
      Offset.zero & overlay.size,
    );
  }

  Future<void> _runQuickAction(
    BuildContext context,
    WidgetRef ref,
    _TaskQuickAction action,
  ) {
    final taskRepository = ref.read(taskRepositoryProvider);
    switch (action) {
      case _TaskQuickAction.startFocus:
        if (task.isCompleted) {
          return Future.value();
        }
        final selectedPreset = _selectedPreset(ref);
        final focusEstimate = targetFocusIntervalsForTask(task, selectedPreset);
        return ref
            .read(focusRepositoryProvider)
            .startRun(
              StartFocusRunInput(
                taskId: task.id,
                projectId: task.projectId,
                presetId: selectedPreset?.id,
                targetWorkIntervals: _targetForStart(focusEstimate),
              ),
            );
      case _TaskQuickAction.toggleComplete:
        return task.isCompleted
            ? taskRepository.uncompleteTask(task.id)
            : completeTaskWithUndoFeedback(context, ref, task.id);
      case _TaskQuickAction.today:
        return taskRepository.updateTask(
          task.id,
          UpdateTaskPatch(
            schedule: TaskSchedule.allDay(
              _today(),
              recurrence: task.schedule?.recurrence,
              recurrenceSeriesId: task.schedule?.recurrenceSeriesId,
            ),
          ),
        );
      case _TaskQuickAction.tomorrow:
        return taskRepository.updateTask(
          task.id,
          UpdateTaskPatch(
            schedule: TaskSchedule.allDay(
              _today().add(const Duration(days: 1)),
              recurrence: task.schedule?.recurrence,
              recurrenceSeriesId: task.schedule?.recurrenceSeriesId,
            ),
          ),
        );
      case _TaskQuickAction.clearDate:
        return taskRepository.updateTask(
          task.id,
          const UpdateTaskPatch(clearSchedule: true),
        );
      case _TaskQuickAction.makeParent:
        return taskRepository.moveTask(
          task.id,
          clearParentId: true,
          orderKey: _newOrderKey(),
        );
      case _TaskQuickAction.priority1:
        return taskRepository.updateTask(
          task.id,
          const UpdateTaskPatch(priority: 1),
        );
      case _TaskQuickAction.priority2:
        return taskRepository.updateTask(
          task.id,
          const UpdateTaskPatch(priority: 2),
        );
      case _TaskQuickAction.priority3:
        return taskRepository.updateTask(
          task.id,
          const UpdateTaskPatch(priority: 3),
        );
      case _TaskQuickAction.priority4:
        return taskRepository.updateTask(
          task.id,
          const UpdateTaskPatch(priority: 4),
        );
      case _TaskQuickAction.delete:
        return deleteTaskWithRecurringPrompt(context, ref, task);
    }
  }

  int? _targetForStart(int? estimate) {
    if (estimate == null) {
      return null;
    }
    return estimate < 1 ? 1 : estimate;
  }

  FocusPresetItem? _selectedPreset(WidgetRef ref) {
    return selectedFocusPresetOrDefault(
      ref.read(focusPresetsProvider).value ?? const [],
      ref.read(lastFocusPresetIdProvider),
    );
  }

  DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  _TaskQuickAction _priorityAction(int priority) {
    return switch (priority) {
      1 => _TaskQuickAction.priority1,
      2 => _TaskQuickAction.priority2,
      3 => _TaskQuickAction.priority3,
      _ => _TaskQuickAction.priority4,
    };
  }

  Future<void> _moveDroppedTask(
    BuildContext context,
    WidgetRef ref,
    String draggedTaskId,
  ) async {
    try {
      await ref
          .read(taskRepositoryProvider)
          .moveTask(
            draggedTaskId,
            projectId: task.projectId,
            sectionId: task.sectionId,
            clearSectionId: task.sectionId == null,
            parentId: task.id,
            orderKey: _newOrderKey(),
          );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      showActionFeedback(
        context,
        message: context.l10n.couldNotMoveTask(error),
        icon: Icons.error_outline,
      );
    }
  }

  String _newOrderKey() {
    return DateTime.now().toUtc().microsecondsSinceEpoch.toString().padLeft(
      20,
      '0',
    );
  }
}

class _AgendaInteractionRegion extends StatefulWidget {
  const _AgendaInteractionRegion({required this.taskId, required this.builder});

  final String taskId;
  final Widget Function(BuildContext context, bool isActive) builder;

  @override
  State<_AgendaInteractionRegion> createState() =>
      _AgendaInteractionRegionState();
}

class _AgendaInteractionRegionState extends State<_AgendaInteractionRegion> {
  late final FocusNode _focusNode = FocusNode(
    debugLabel: 'Agenda task ${widget.taskId}',
  );
  bool _isHovered = false;
  bool _hasFocus = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (_hasFocus != _focusNode.hasFocus) {
      setState(() => _hasFocus = _focusNode.hasFocus);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      key: ValueKey('agenda-row-focus-${widget.taskId}'),
      focusNode: _focusNode,
      child: MouseRegion(
        onEnter: (_) {
          if (!_isHovered) {
            setState(() => _isHovered = true);
          }
        },
        onExit: (_) {
          if (_isHovered) {
            setState(() => _isHovered = false);
          }
        },
        child: widget.builder(context, _isHovered || _hasFocus),
      ),
    );
  }
}

class _AgendaTaskContent extends StatelessWidget {
  const _AgendaTaskContent({
    required this.task,
    required this.project,
    required this.focusEstimate,
    required this.subtaskProgress,
    required this.allowMetadataWrap,
    required this.taskTimeState,
    required this.timeDisplayMode,
    required this.defaultTimedBlockMinutes,
  });

  final TaskItem task;
  final ProjectItem? project;
  final int? focusEstimate;
  final TaskSubtaskProgress? subtaskProgress;
  final bool allowMetadataWrap;
  final TaskTimeState? taskTimeState;
  final TaskTimeDisplayMode timeDisplayMode;
  final int defaultTimedBlockMinutes;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final progress = subtaskProgress;
    final schedule = task.schedule;
    final scheduleLabel = schedule == null
        ? null
        : formatTaskListScheduleWithinDate(
            context,
            schedule,
            displayMode: timeDisplayMode,
            defaultTimedBlockMinutes: defaultTimedBlockMinutes,
          );
    final metadata = <Widget>[
      if (progress != null && progress.total > 0)
        _FixedMetaText(
          icon: Icons.account_tree_outlined,
          label: progress.label,
          tooltip: '${context.l10n.subtasks} ${progress.label}',
        ),
      if (focusEstimate != null)
        _FixedMetaText(
          icon: Icons.timer_outlined,
          label: '${task.completedFocusIntervals}/$focusEstimate',
        ),
      if (project != null) _AgendaProjectLabel(project: project!),
      if (scheduleLabel != null)
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 180),
          child: _TaskTimeMetaText(
            taskId: task.id,
            label: scheduleLabel,
            state: taskTimeState,
            color: taskTimeState == null
                ? colors.mutedText
                : colors.taskTimeColor(taskTimeState!),
            textStyle: Theme.of(context).textTheme.labelMedium,
            key: const Key('agenda-schedule-label'),
          ),
        ),
    ];
    final title = Text(
      task.content,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        color: task.isCompleted ? colors.mutedText : colors.primaryText,
        decoration: task.isCompleted ? TextDecoration.lineThrough : null,
        decorationColor: colors.mutedText,
      ),
    );

    if (metadata.isEmpty) {
      return title;
    }
    if (allowMetadataWrap) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          title,
          const SizedBox(height: 4),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Wrap(
              spacing: 10,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: metadata,
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: title),
        const SizedBox(width: 12),
        for (var index = 0; index < metadata.length; index++) ...[
          if (index > 0) const SizedBox(width: 12),
          metadata[index],
        ],
      ],
    );
  }
}

class _AgendaProjectLabel extends StatelessWidget {
  const _AgendaProjectLabel({required this.project});

  final ProjectItem project;

  @override
  Widget build(BuildContext context) {
    final color = projectColorValue(effectiveProjectColor(project));
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 160),
      child: Row(
        key: const Key('agenda-project-label'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '#',
            key: const Key('agenda-project-color'),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              project.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskContent extends StatelessWidget {
  const _TaskContent({
    required this.task,
    required this.description,
    required this.hasDescription,
    required this.hasMeta,
    required this.focusEstimate,
    required this.subtaskProgress,
    required this.taskTimeState,
    required this.timeDisplayMode,
    required this.defaultTimedBlockMinutes,
  });

  final TaskItem task;
  final String? description;
  final bool hasDescription;
  final bool hasMeta;
  final int? focusEstimate;
  final TaskSubtaskProgress? subtaskProgress;
  final TaskTimeState? taskTimeState;
  final TaskTimeDisplayMode timeDisplayMode;
  final int defaultTimedBlockMinutes;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final progress = subtaskProgress;
    final progressLabel = progress?.label;
    final metaItems = <Widget>[
      if (progress != null && progress.total > 0)
        _FixedMetaText(
          icon: Icons.account_tree_outlined,
          label: progress.label,
          tooltip: '${context.l10n.subtasks} $progressLabel',
        ),
      if (task.schedule != null)
        Flexible(
          child: _TaskTimeMetaText(
            taskId: task.id,
            label: formatTaskListSchedule(
              context,
              task.schedule!,
              displayMode: timeDisplayMode,
              defaultTimedBlockMinutes: defaultTimedBlockMinutes,
            ),
            state: taskTimeState,
            color: taskTimeState == null
                ? Theme.of(context).colorScheme.onSurfaceVariant
                : colors.taskTimeColor(taskTimeState!),
            textStyle: Theme.of(context).textTheme.labelSmall,
            expanded: true,
          ),
        ),
      if (focusEstimate != null)
        _FixedMetaText(
          icon: Icons.timer_outlined,
          label: '${task.completedFocusIntervals}/$focusEstimate',
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          task.content,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: task.isCompleted ? colors.mutedText : colors.primaryText,
            decoration: task.isCompleted ? TextDecoration.lineThrough : null,
            decorationColor: colors.mutedText,
          ),
        ),
        if (hasDescription) ...[
          const SizedBox(height: 2),
          Text(
            description!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.mutedText),
          ),
        ],
        if (hasMeta) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              for (var index = 0; index < metaItems.length; index++) ...[
                if (index > 0) const SizedBox(width: 10),
                metaItems[index],
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class _TaskDragFeedback extends StatelessWidget {
  const _TaskDragFeedback({required this.task});

  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: colors.primaryText.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              task.content,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.primaryText),
            ),
          ),
        ),
      ),
    );
  }
}

class _TaskTimeMetaText extends StatelessWidget {
  const _TaskTimeMetaText({
    required this.taskId,
    required this.label,
    required this.state,
    required this.color,
    required this.textStyle,
    this.expanded = false,
    super.key,
  });

  final String taskId;
  final String label;
  final TaskTimeState? state;
  final Color color;
  final TextStyle? textStyle;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final status = state == null
        ? null
        : taskTimeStatusLabel(context.l10n, state!);
    final content = Row(
      key: ValueKey('task-time-meta-$taskId'),
      mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
      children: [
        Icon(Icons.event_outlined, size: 14, color: color),
        const SizedBox(width: 4),
        if (expanded) Expanded(child: _label()) else Flexible(child: _label()),
      ],
    );
    return Semantics(
      label: status == null ? label : '$label, $status',
      child: content,
    );
  }

  Widget _label() {
    return Text(
      label,
      key: ValueKey('task-time-label-$taskId'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: textStyle?.copyWith(color: color),
    );
  }
}

class _FixedMetaText extends StatelessWidget {
  const _FixedMetaText({required this.icon, required this.label, this.tooltip});

  final IconData icon;
  final String label;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.clip,
          softWrap: false,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
        ),
      ],
    );
    final message = tooltip;
    if (message == null) {
      return content;
    }
    return Tooltip(
      message: message,
      child: Semantics(label: message, child: content),
    );
  }
}

enum _TaskQuickAction {
  startFocus,
  toggleComplete,
  makeParent,
  today,
  tomorrow,
  clearDate,
  priority1,
  priority2,
  priority3,
  priority4,
  delete,
}

class _TaskTextDragSource extends StatelessWidget {
  const _TaskTextDragSource({required this.task, required this.child});

  final TaskItem task;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final childWhenDragging = Opacity(opacity: 0.35, child: child);
    final feedback = _TaskDragFeedback(task: task);
    if (_usesImmediateTaskDrag(defaultTargetPlatform)) {
      return Draggable<String>(
        data: task.id,
        feedback: feedback,
        childWhenDragging: childWhenDragging,
        child: child,
      );
    }
    return LongPressDraggable<String>(
      data: task.id,
      feedback: feedback,
      childWhenDragging: childWhenDragging,
      child: child,
    );
  }
}

bool _usesImmediateTaskDrag(TargetPlatform platform) {
  return switch (platform) {
    TargetPlatform.macOS ||
    TargetPlatform.windows ||
    TargetPlatform.linux => true,
    TargetPlatform.android ||
    TargetPlatform.iOS ||
    TargetPlatform.fuchsia => false,
  };
}

class _TaskMenuRow extends StatelessWidget {
  const _TaskMenuRow({
    required this.icon,
    required this.label,
    this.selected = false,
    this.color,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(label, style: TextStyle(color: color)),
        ),
        if (selected) const Icon(Icons.check, size: 18),
      ],
    );
  }
}
