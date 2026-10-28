import 'package:pomodoist/ui/tasks/view_models/task_list_view_model.dart'
    show taskListViewModelProvider;
import 'package:pomodoist/ui/tasks/widgets/task_row_geometry.dart';
import 'package:pomodoist/ui/tasks/widgets/task_title_dialog.dart';
import 'package:pomodoist/ui/core/widgets/app_context_menu_region.dart';
import 'package:pomodoist/ui/core/widgets/app_action_menu.dart';
import 'package:pomodoist/ui/tasks/view_models/task_subtask_progress.dart';
import 'package:pomodoist/ui/tasks/widgets/project_localizations.dart';
import 'package:pomodoist/ui/tasks/view_models/task_branch_rows.dart';
import 'package:pomodoist/ui/tasks/view_models/task_branch_view_model.dart';
import 'package:pomodoist/ui/tasks/widgets/task_branch_widgets.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pomodoist/ui/core/themes/app_motion.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons, ShadContextMenuItem;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/routing/task_detail_navigation.dart';
import 'package:pomodoist/ui/core/localization/formatters.dart';
import 'package:pomodoist/ui/tasks/view_models/task_item_view_model.dart';
import 'package:pomodoist/domain/models/settings/task_preferences.dart';
import 'package:pomodoist/domain/models/tasks/task_time.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/core/widgets/action_feedback.dart';
import 'package:pomodoist/domain/models/tasks/project_colors.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/ui/tasks/widgets/task_completion_feedback.dart';
import 'package:pomodoist/ui/tasks/widgets/task_swipe_actions.dart';
import 'package:pomodoist/ui/tasks/widgets/project_color_picker.dart';
import 'package:pomodoist/ui/tasks/widgets/task_motion.dart';
import 'package:pomodoist/ui/tasks/widgets/task_selection_region.dart';

enum TaskListItemPresentation { standard, agenda }

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
          animationStyle: AnimationStyle(
            duration: AppMotion.duration(context, AppMotion.popup),
            reverseDuration: AppMotion.duration(context, AppMotion.popup),
            curve: AppMotion.curve,
          ),
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

  final viewModel = ref.read(taskItemViewModelProvider(task).notifier);
  late final DeletedTaskBatch batch;
  try {
    batch = await viewModel.delete(includeFollowing: includeFollowing);
  } catch (_) {
    if (context.mounted) {
      showActionFeedback(
        context,
        message: context.l10n.taskActionFailedCount(1),
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
  final motion = TaskMotionScope.maybeOf(context);
  final visibleTasks = TaskSelectionScope.maybeOf(context)?.visibleTasks;
  motion?.deleted(
    visibleTasks == null
        ? [task]
        : visibleTasks.where((item) => batch.taskIds.contains(item.id)),
  );
  showActionFeedback(
    context,
    message: context.l10n.taskDeleted,
    icon: LucideIcons.trash2,
    duration: const Duration(seconds: 7),
    showCloseIcon: true,
    compact: true,
    action: SnackBarAction(
      label: context.l10n.commonUndo,
      onPressed: () => unawaited(() async {
        final bool restored;
        try {
          restored = await viewModel.restore(batch);
        } catch (_) {
          if (context.mounted) {
            showActionFeedback(
              context,
              message: context.l10n.taskActionFailedCount(batch.taskIds.length),
              icon: LucideIcons.circleAlert,
              sound: ActionFeedbackSound.none,
              haptic: AppHapticCue.none,
            );
          }
          return;
        }
        if (restored) {
          await playHaptic(AppHapticCue.light);
          if (context.mounted) {
            motion?.created(batch.taskIds);
          }
          return;
        }
        if (!context.mounted) {
          return;
        }
        showActionFeedback(
          context,
          message: context.l10n.taskActionFailedCount(batch.taskIds.length),
          icon: LucideIcons.circleAlert,
          sound: ActionFeedbackSound.none,
          haptic: AppHapticCue.none,
        );
      }()),
    ),
  );
  onDeleted?.call();
}

/// Structure is supplied by the list; content is observed by task ID.
class TaskListRow extends ConsumerWidget {
  const TaskListRow({
    required this.row,
    required this.branchScope,
    this.progress,
    this.query,
    this.project,
    this.presentation = TaskListItemPresentation.standard,
    super.key,
  });
  final VisibleTaskRow row;
  final TaskQuery? query;
  final String branchScope;
  final TaskSubtaskProgress? progress;
  final ProjectItem? project;
  final TaskListItemPresentation presentation;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liveTask = query == null
        ? ref.watch(
            taskHierarchyViewModelProvider.select(
              (data) => data.byId[row.task.id],
            ),
          )
        : ref.watch(
            taskListViewModelProvider(
              query!,
            ).select((state) => state.byId[row.task.id]),
          );
    return TaskListItem(
      key: ValueKey(row.task.id),
      task: liveTask ?? row.task,
      depth: row.displayDepth,
      hierarchy: row,
      branchScope: branchScope,
      subtaskProgress: progress,
      project: project,
      presentation: presentation,
    );
  }
}

class TaskListItem extends ConsumerWidget {
  const TaskListItem({
    required this.task,
    this.depth = 0,
    this.hierarchy,
    this.branchScope,
    this.subtaskProgress,
    this.enableSubtaskDrop = true,
    this.compactDetails = false,
    this.presentation = TaskListItemPresentation.standard,
    this.project,
    this.diagram = false,
    this.onAddSubtask,
    this.onDiagramMove,
    super.key,
  });

  final TaskItem task;
  final int depth;
  final VisibleTaskRow? hierarchy;
  final String? branchScope;
  final TaskSubtaskProgress? subtaskProgress;
  final bool enableSubtaskDrop;
  final bool compactDetails;
  final TaskListItemPresentation presentation;
  final ProjectItem? project;
  final bool diagram;
  final VoidCallback? onAddSubtask;
  final VoidCallback? onDiagramMove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final progressSnapshot = ref.watch(taskProgressProvider(task.id));
    final progress = progressSnapshot.live
        ? progressSnapshot.progress
        : subtaskProgress;
    final rowDepth = hierarchy?.displayDepth ?? math.min(depth, 2);
    final grouped =
        !diagram &&
        hierarchy?.groupRootId != null &&
        ref.watch(taskBranchStyleViewModelProvider) == TaskBranchStyle.grouped;
    final rowIndent = grouped
        ? hierarchy!.groupDisplayDepth * 12.0
        : rowDepth * 28.0;
    final showParent =
        task.parentId != null &&
        (hierarchy == null ||
            hierarchy!.visibleParentId == null ||
            hierarchy!.depth > 2);
    final ancestors = ref.watch(taskAncestorsProvider(task)).items;
    final selection = TaskSelectionScope.maybeOf(context);
    final viewState = ref.watch(taskItemViewModelProvider(task));
    final viewModel = ref.read(taskItemViewModelProvider(task).notifier);
    final focusEstimate = viewState.focusEstimate;
    final colorScheme = Theme.of(context).colorScheme;
    final colors = context.appColors;
    final taskTimeState = viewState.timeState;
    final timeDisplayMode = viewState.timeDisplayMode;
    final defaultTimedBlockMinutes = viewState.timedMinutes;
    final description = task.description?.trim();
    final hasDescription = description != null && description.isNotEmpty;
    final hasMeta = _hasListMeta(task, focusEstimate);
    final isAgenda = presentation == TaskListItemPresentation.agenda;
    final isModern = viewState.listStyle == TaskListStyle.modern;
    final verticalPadding = compactDetails
        ? 0.0
        : TaskRowGeometry.verticalPadding(viewState.rowSpacing);
    final rowProject =
        project ??
        (isModern || usesTouchTaskInteraction ? viewState.project : null);

    Widget focusAction({Key? key}) => _taskFocusAction(
      context,
      enabled: !task.isCompleted && !(selection?.active ?? false),
      onPressed: () => _startFocus(context, ref),
      key: key,
    );

    Widget overflowAction() => AppActionMenu(
      key: ValueKey('agenda-overflow-action-${task.id}'),
      tooltip: l10n.moreFocusActions,
      items: _quickActionItems(context, ref, includeFocus: isModern),
    );

    Future<void> toggleCompletion() async {
      if (task.isCompleted) {
        try {
          await viewModel.reopen();
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
        final reopened = await viewModel.current();
        if (!context.mounted) {
          return;
        }
        if (reopened != null) {
          TaskMotionScope.maybeOf(context)?.reopened([reopened]);
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
        complete: viewModel.complete,
        undo: viewModel.reopen,
      );
    }

    if (diagram) {
      final menu = [
        ShadContextMenuItem(
          height: 44,
          onPressed: () => openTaskDetails(context, task.id),
          leading: const Icon(LucideIcons.externalLink, size: 16),
          child: Text(l10n.commonOpen),
        ),
        if (task.canEdit && onAddSubtask != null)
          ShadContextMenuItem(
            height: 44,
            onPressed: onAddSubtask,
            leading: const Icon(LucideIcons.plus, size: 16),
            child: Text(l10n.addSubtask),
          ),
        if (task.canEdit && onDiagramMove != null)
          ShadContextMenuItem(
            height: 44,
            onPressed: onDiagramMove,
            leading: const Icon(LucideIcons.move, size: 16),
            child: Text(l10n.taskMove),
          ),
        if (task.canEdit && onDiagramMove != null)
          ShadContextMenuItem(
            height: 44,
            onPressed: () =>
                unawaited(_runQuickAction(context, ref, _TaskQuickAction.move)),
            leading: const Icon(LucideIcons.folderInput, size: 16),
            child: Text(l10n.taskChangeProject),
          ),
        if (task.canEdit)
          ..._quickActionItems(
            context,
            ref,
            includeFocus: true,
            includeMove: false,
          )
        else
          ShadContextMenuItem(
            height: 44,
            enabled: !task.isCompleted,
            onPressed: () => unawaited(_startFocus(context, ref)),
            leading: const Icon(LucideIcons.play, size: 16),
            child: Text(l10n.startFocus),
          ),
      ];
      final schedule = task.schedule;
      final label = schedule == null
          ? null
          : formatTaskListSchedule(
              context,
              schedule,
              displayMode: timeDisplayMode,
              defaultTimedBlockMinutes: defaultTimedBlockMinutes,
            );
      return AppContextMenuRegion(
        items: menu,
        child: Material(
          color: selection?.isSelected(task.id) == true
              ? colors.accentTint
              : Colors.transparent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      hoverColor: Colors.transparent,
                      mouseCursor: task.canEdit
                          ? SystemMouseCursors.text
                          : SystemMouseCursors.click,
                      onTap: () => selection?.active == true
                          ? selection!.toggle(task.id)
                          : task.canEdit
                          ? unawaited(showTaskTitleDialog(context, task))
                          : openTaskDetails(context, task.id),
                      child: Tooltip(
                        message: task.content,
                        child: Text(
                          task.content,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: task.isCompleted
                                    ? colors.secondaryText
                                    : colors.primaryText,
                                decoration: task.isCompleted
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  [
                    ?label,
                    if (focusEstimate != null)
                      '${task.completedFocusIntervals}/$focusEstimate',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: colors.secondaryText),
                ),
              ),
              Row(
                children: [
                  SizedBox(
                    width: 44,
                    height: 48,
                    child: Center(
                      child: TaskCompletionControl(
                        taskId: task.id,
                        hitSize: 44,
                        isCompleted: task.isCompleted,
                        color: _priorityColor(
                          task.priority,
                          colorScheme,
                          colors,
                        ),
                        fillColor: colors.accentFill,
                        tooltip: task.isCompleted
                            ? l10n.markOpen
                            : l10n.markComplete,
                        onPressed: task.canEdit ? toggleCompletion : null,
                      ),
                    ),
                  ),
                  if (progress != null && progress.total > 0)
                    Expanded(
                      child: TaskBranchProgressButton(
                        taskId: task.id,
                        progress: progress,
                      ),
                    )
                  else
                    const Spacer(),
                  AppActionMenu(tooltip: l10n.taskMore, items: menu),
                ],
              ),
            ],
          ),
        ),
      );
    }

    Widget completionControl(bool mobile) => SizedBox(
      width: mobile ? 44 : 34,
      height: mobile ? 44 : null,
      child: selection?.active ?? false
          ? Checkbox(
              value: selection!.isSelected(task.id),
              visualDensity: mobile
                  ? VisualDensity.standard
                  : VisualDensity.compact,
              materialTapTargetSize: mobile
                  ? MaterialTapTargetSize.padded
                  : MaterialTapTargetSize.shrinkWrap,
              shape: const CircleBorder(),
              onChanged: (_) => selection.toggle(task.id),
            )
          : Center(
              child: TaskCompletionControl(
                taskId: task.id,
                hitSize: mobile ? 44 : 24,
                isCompleted: task.isCompleted,
                color: task.isCompleted
                    ? colors.accent
                    : _priorityColor(task.priority, colorScheme, colors),
                fillColor: colors.accentFill,
                tooltip: task.isCompleted ? l10n.markOpen : l10n.markComplete,
                onPressed: toggleCompletion,
              ),
            ),
    );

    Widget? branchDisclosure() =>
        hierarchy?.hasVisibleChildren == true &&
            branchScope != null &&
            progress != null &&
            progress.total > 0
        ? TaskBranchProgressButton(
            taskId: task.id,
            progress: progress,
            expanded: hierarchy!.expanded,
            showProgress: false,
            onToggle: () => unawaited(
              setTaskBranchExpanded(
                context,
                ref,
                branchScope!,
                task.id,
                !hierarchy!.expanded,
              ),
            ),
          )
        : null;

    Widget row(
      bool accepting, {
      required bool agendaDesktop,
      required bool showAgendaFocusAction,
    }) {
      final trailingAction = usesTouchTaskInteraction
          ? SizedBox(width: 44, height: 44, child: branchDisclosure())
          : isModern
          ? _desktopTaskActions(
              context,
              columns: agendaDesktop,
              active: showAgendaFocusAction,
              focusAction: focusAction(),
              overflowAction: overflowAction(),
            )
          : switch (presentation) {
              TaskListItemPresentation.standard => focusAction(),
              TaskListItemPresentation.agenda when agendaDesktop => SizedBox(
                key: ValueKey('agenda-focus-slot-${task.id}'),
                width: 48,
                height: 48,
                child: showAgendaFocusAction
                    ? focusAction(
                        key: ValueKey('agenda-focus-action-${task.id}'),
                      )
                    : null,
              ),
              TaskListItemPresentation.agenda => overflowAction(),
            };
      Widget buildContent() {
        final rowContent = Material(
          color: accepting || (selection?.isSelected(task.id) ?? false)
              ? colors.accentTint
              : Colors.transparent,
          child: Semantics(
            selected: selection?.active ?? false
                ? selection!.isSelected(task.id)
                : null,
            child: InkWell(
              key: ValueKey('task-list-item-row-${task.id}'),
              borderRadius: BorderRadius.circular(10),
              focusColor: colors.accentTint,
              hoverColor: colors.surfaceTint,
              onTap: () {
                if (selection?.active ?? false) {
                  selection!.toggle(task.id);
                } else {
                  openTaskDetails(context, task.id);
                }
              },
              onLongPress:
                  usesTouchTaskInteraction && (selection?.active ?? false)
                  ? () => selection!.toggle(task.id)
                  : null,
              child: Padding(
                padding: EdgeInsetsDirectional.fromSTEB(
                  0,
                  verticalPadding,
                  4,
                  verticalPadding,
                ),
                child: compactDetails
                    ? Row(
                        children: [
                          completionControl(true),
                          Expanded(
                            child: _TaskTextDragSource(
                              task: task,
                              enabled: !(selection?.active ?? false),
                              child: Text(
                                task.content,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: task.isCompleted
                                          ? colors.secondaryText
                                          : colors.primaryText,
                                      decoration: task.isCompleted
                                          ? TextDecoration.lineThrough
                                          : null,
                                    ),
                              ),
                            ),
                          ),
                          if (usesTouchTaskInteraction)
                            SizedBox(
                              width: 44,
                              height: 44,
                              child: branchDisclosure(),
                            ),
                          overflowAction(),
                        ],
                      )
                    : usesTouchTaskInteraction
                    ? _MobileTaskContent(
                        rowSpacing: viewState.rowSpacing,
                        task: task,
                        modern: isModern,
                        description: isAgenda ? null : description,
                        project: rowProject,
                        progress: progress,
                        focusEstimate: focusEstimate,
                        taskTimeState: taskTimeState,
                        timeDisplayMode: timeDisplayMode,
                        defaultTimedBlockMinutes: defaultTimedBlockMinutes,
                        withinDate: isAgenda,
                        parentContext: showParent
                            ? TaskParentContext(
                                task: task,
                                ancestors: ancestors,
                              )
                            : null,
                        completion: completionControl(true),
                        disclosure: trailingAction,
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          completionControl(false),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (showParent)
                                  TaskParentContext(
                                    task: task,
                                    ancestors: ancestors,
                                  ),
                                if (isAgenda || isModern)
                                  _AgendaTaskContent(
                                    rowSpacing: viewState.rowSpacing,
                                    task: task,
                                    project: rowProject,
                                    modern: isModern,
                                    withinDate: isAgenda,
                                    description: isAgenda ? null : description,
                                    focusEstimate: focusEstimate,
                                    subtaskProgress: progress,
                                    allowMetadataWrap: !agendaDesktop,
                                    taskTimeState: taskTimeState,
                                    timeDisplayMode: timeDisplayMode,
                                    defaultTimedBlockMinutes:
                                        defaultTimedBlockMinutes,
                                    dragEnabled: !(selection?.active ?? false),
                                  )
                                else
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _TaskTextDragSource(
                                          task: task,
                                          enabled:
                                              !(selection?.active ?? false),
                                          child: _TaskContent(
                                            rowSpacing: viewState.rowSpacing,
                                            task: task,
                                            description: description,
                                            hasDescription: hasDescription,
                                            hasMeta: hasMeta,
                                            focusEstimate: focusEstimate,
                                            taskTimeState: taskTimeState,
                                            timeDisplayMode: timeDisplayMode,
                                            defaultTimedBlockMinutes:
                                                defaultTimedBlockMinutes,
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: MediaQuery.textScalerOf(
                                          context,
                                        ).scale(72),
                                        child:
                                            progress != null &&
                                                progress.total > 0
                                            ? TaskBranchProgressButton(
                                                taskId: task.id,
                                                progress: progress,
                                              )
                                            : null,
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          trailingAction,
                        ],
                      ),
              ),
            ),
          ),
        );
        final rowWithDisclosure = Row(
          children: [
            if (hierarchy != null && !usesTouchTaskInteraction)
              SizedBox(width: taskBranchGutterWidth, child: branchDisclosure()),
            Expanded(
              child: Padding(
                padding: EdgeInsetsDirectional.only(start: rowIndent),
                child: rowContent,
              ),
            ),
          ],
        );
        final content = hierarchy == null
            ? rowWithDisclosure
            : grouped
            ? TaskBranchSurface(row: hierarchy!, child: rowWithDisclosure)
            : TaskBranchLines(
                row: hierarchy!,
                anchor: usesTouchTaskInteraction
                    ? verticalPadding + _mobileGeometry(context).anchor
                    : null,
                child: rowWithDisclosure,
              );
        final contextualContent = selection?.active ?? false
            ? content
            : AppContextMenuRegion(
                enableLongPress: usesTouchTaskInteraction,
                items: _quickActionItems(
                  context,
                  ref,
                  includeFocus: usesTouchTaskInteraction,
                ),
                child: content,
              );
        if (!enableSubtaskDrop) {
          return contextualContent;
        }
        return AnimatedPadding(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : AppMotion.state,
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.symmetric(vertical: accepting ? 4 : 0),
          child: contextualContent,
        );
      }

      if (!usesTouchTaskInteraction) return buildContent();
      return TaskSwipeActions(
        key: ValueKey('task-swipe-${task.id}'),
        enabled:
            !task.isCompleted && !(selection?.active ?? false) && !accepting,
        onFocus: () => _startFocus(context, ref),
        onDelete: () => deleteTaskWithRecurringPrompt(context, ref, task),
        builder: (_) => buildContent(),
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

    if (!isAgenda && !isModern) {
      return TaskMotionItem(
        taskId: task.id,
        child: rowWithDropTarget(
          agendaDesktop: false,
          showAgendaFocusAction: true,
        ),
      );
    }

    return TaskMotionItem(
      taskId: task.id,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = isModern
              ? constraints.maxWidth -
                        (hierarchy == null ? 0 : taskBranchGutterWidth) -
                        56 >=
                    840 * MediaQuery.textScalerOf(context).scale(14) / 14
              : constraints.maxWidth >= 760;
          return _AgendaInteractionRegion(
            taskId: task.id,
            builder: (context, isActive) => rowWithDropTarget(
              agendaDesktop: isDesktop,
              showAgendaFocusAction:
                  isDesktop &&
                  (isActive ||
                      (isModern &&
                          !_usesImmediateTaskDrag(defaultTargetPlatform))),
            ),
          );
        },
      ),
    );
  }

  bool _hasListMeta(TaskItem task, int? focusEstimate) {
    return task.schedule != null || focusEstimate != null;
  }

  List<Widget> _quickActionItems(
    BuildContext context,
    WidgetRef ref, {
    bool includeFocus = false,
    bool includeMove = true,
  }) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final selection = TaskSelectionScope.maybeOf(context);
    final parent = usesTouchTaskInteraction
        ? taskParentForNavigation(task, {
            for (final parent in ref.watch(taskAncestorsProvider(task)).items)
              parent.id: parent,
          }, selectionActive: selection?.active ?? false)
        : null;
    return [
      if (includeFocus)
        ShadContextMenuItem(
          height: 44,
          onPressed: () => unawaited(
            _runQuickAction(context, ref, _TaskQuickAction.startFocus),
          ),
          enabled: !task.isCompleted && !(selection?.active ?? false),
          child: _TaskMenuRow(icon: LucideIcons.play, label: l10n.startFocus),
        ),
      ShadContextMenuItem(
        height: 44,
        onPressed: () =>
            unawaited(_runQuickAction(context, ref, _TaskQuickAction.schedule)),
        child: _TaskMenuRow(
          icon: LucideIcons.calendar,
          label: l10n.taskSchedule,
        ),
      ),
      if (parent != null)
        ShadContextMenuItem(
          height: 44,
          onPressed: () {
            final data = ref.read(taskHierarchyViewModelProvider);
            final current = data.byId[task.id];
            final destination = current == null
                ? null
                : taskParentForNavigation(
                    current,
                    data.byId,
                    selectionActive: selection?.active ?? false,
                  );
            if (destination != null) openTaskDetails(context, destination.id);
          },
          child: _TaskMenuRow(
            icon: LucideIcons.cornerUpLeft,
            label: l10n.taskOpenParent,
          ),
        ),
      if (selection != null) ...[
        ShadContextMenuItem(
          height: 44,
          onPressed: () =>
              unawaited(_runQuickAction(context, ref, _TaskQuickAction.select)),
          child: _TaskMenuRow(
            icon: LucideIcons.listChecks,
            label: l10n.taskSelect,
          ),
        ),
        if (includeMove)
          ShadContextMenuItem(
            height: 44,
            onPressed: () =>
                unawaited(_runQuickAction(context, ref, _TaskQuickAction.move)),
            child: _TaskMenuRow(
              icon: LucideIcons.folderInput,
              label: l10n.taskMove,
            ),
          ),
        ShadContextMenuItem(
          height: 44,
          onPressed: () => unawaited(
            _runQuickAction(context, ref, _TaskQuickAction.choosePriority),
          ),
          child: _TaskMenuRow(icon: LucideIcons.flag, label: l10n.taskPriority),
        ),
        ShadContextMenuItem(
          height: 44,
          onPressed: () => unawaited(
            _runQuickAction(context, ref, _TaskQuickAction.duplicate),
          ),
          child: _TaskMenuRow(
            icon: LucideIcons.copy,
            label: l10n.taskDuplicate,
          ),
        ),
        ShadContextMenuItem(
          height: 44,
          onPressed: () => unawaited(
            _runQuickAction(context, ref, _TaskQuickAction.deleteSelection),
          ),
          child: _TaskMenuRow(
            icon: LucideIcons.trash2,
            label: l10n.commonDelete,
            color: colors.accent,
          ),
        ),
      ] else ...[
        ShadContextMenuItem(
          height: 44,
          onPressed: () => unawaited(
            _runQuickAction(context, ref, _TaskQuickAction.startFocus),
          ),
          enabled: !task.isCompleted,
          child: _TaskMenuRow(icon: LucideIcons.play, label: l10n.startFocus),
        ),
        ShadContextMenuItem(
          height: 44,
          onPressed: () => unawaited(
            _runQuickAction(context, ref, _TaskQuickAction.toggleComplete),
          ),
          child: _TaskMenuRow(
            icon: task.isCompleted ? LucideIcons.undo2 : LucideIcons.check,
            label: task.isCompleted ? l10n.markOpen : l10n.markComplete,
          ),
        ),
        if (includeMove && task.parentId != null)
          ShadContextMenuItem(
            height: 44,
            onPressed: () => unawaited(
              _runQuickAction(context, ref, _TaskQuickAction.makeParent),
            ),
            child: _TaskMenuRow(
              icon: LucideIcons.indentDecrease,
              label: l10n.makeParentTask,
            ),
          ),
        Divider(height: 8, color: context.appColors.border),
        ShadContextMenuItem(
          height: 44,
          onPressed: () =>
              unawaited(_runQuickAction(context, ref, _TaskQuickAction.today)),
          child: _TaskMenuRow(
            icon: LucideIcons.calendarCheck,
            label: l10n.today,
          ),
        ),
        ShadContextMenuItem(
          height: 44,
          onPressed: () => unawaited(
            _runQuickAction(context, ref, _TaskQuickAction.tomorrow),
          ),
          child: _TaskMenuRow(icon: LucideIcons.calendar, label: l10n.tomorrow),
        ),
        if (task.schedule != null)
          ShadContextMenuItem(
            height: 44,
            onPressed: () => unawaited(
              _runQuickAction(context, ref, _TaskQuickAction.clearDate),
            ),
            child: _TaskMenuRow(
              icon: LucideIcons.calendarX,
              label: l10n.clearDate,
            ),
          ),
        Divider(height: 8, color: context.appColors.border),
        for (final priority in [1, 2, 3, 4])
          ShadContextMenuItem(
            height: 44,
            onPressed: () => unawaited(
              _runQuickAction(context, ref, _priorityAction(priority)),
            ),
            child: _TaskMenuRow(
              icon: LucideIcons.flag,
              label: l10n.priority(priority),
              selected: task.priority == priority,
              color: _priorityColor(
                priority,
                Theme.of(context).colorScheme,
                colors,
              ),
            ),
          ),
        Divider(height: 8, color: context.appColors.border),
        ShadContextMenuItem(
          height: 44,
          onPressed: () =>
              unawaited(_runQuickAction(context, ref, _TaskQuickAction.delete)),
          child: _TaskMenuRow(
            icon: LucideIcons.trash2,
            label: l10n.commonDelete,
            color: colors.accent,
          ),
        ),
      ],
    ];
  }

  Future<void> _runQuickAction(
    BuildContext context,
    WidgetRef ref,
    _TaskQuickAction action,
  ) {
    final viewModel = ref.read(taskItemViewModelProvider(task).notifier);
    switch (action) {
      case _TaskQuickAction.select:
        TaskSelectionScope.maybeOf(context)?.begin(task.id);
        return Future.value();
      case _TaskQuickAction.schedule:
        return _scheduleTask(context, ref);
      case _TaskQuickAction.move:
        final selection = TaskSelectionScope.maybeOf(context);
        selection?.begin(task.id);
        return selection?.showProject(context) ?? Future.value();
      case _TaskQuickAction.choosePriority:
        final selection = TaskSelectionScope.maybeOf(context);
        selection?.begin(task.id);
        return selection?.showPriority(context) ?? Future.value();
      case _TaskQuickAction.duplicate:
        final selection = TaskSelectionScope.maybeOf(context);
        selection?.begin(task.id);
        return selection?.duplicate(context) ?? Future.value();
      case _TaskQuickAction.deleteSelection:
        final selection = TaskSelectionScope.maybeOf(context);
        selection?.begin(task.id);
        return selection?.delete(context) ?? Future.value();
      case _TaskQuickAction.startFocus:
        return _startFocus(context, ref);
      case _TaskQuickAction.toggleComplete:
        return task.isCompleted
            ? viewModel.reopen().then<void>((_) {})
            : completeTaskWithUndoFeedback(
                context,
                complete: viewModel.complete,
                undo: viewModel.reopen,
              ).then<void>((_) {});
      case _TaskQuickAction.today:
        return viewModel.moveToDay(0);
      case _TaskQuickAction.tomorrow:
        return viewModel.moveToDay(1);
      case _TaskQuickAction.clearDate:
        return viewModel.clearSchedule();
      case _TaskQuickAction.makeParent:
        return viewModel.makeParent();
      case _TaskQuickAction.priority1:
        return viewModel.setPriority(1);
      case _TaskQuickAction.priority2:
        return viewModel.setPriority(2);
      case _TaskQuickAction.priority3:
        return viewModel.setPriority(3);
      case _TaskQuickAction.priority4:
        return viewModel.setPriority(4);
      case _TaskQuickAction.delete:
        return deleteTaskWithRecurringPrompt(context, ref, task);
    }
  }

  Future<void> _scheduleTask(BuildContext context, WidgetRef ref) async {
    final viewModel = ref.read(taskItemViewModelProvider(task).notifier);
    try {
      final result = await showTaskDuePanel(context, ref);
      if (result == null || !context.mounted) return;
      await viewModel.schedule(result);
    } catch (_) {
      if (context.mounted) _showActionError(context);
    }
  }

  Future<void> _startFocus(BuildContext context, WidgetRef ref) async {
    final viewModel = ref.read(taskItemViewModelProvider(task).notifier);
    try {
      final opened = await viewModel.startFocus(() async {
        if (!context.mounted) return false;
        return await showDialog<bool>(
                  context: context,
                  animationStyle: AnimationStyle(
                    duration: AppMotion.duration(context, AppMotion.popup),
                    reverseDuration: AppMotion.duration(
                      context,
                      AppMotion.popup,
                    ),
                    curve: AppMotion.curve,
                  ),
                  builder: (dialogContext) => AlertDialog(
                    title: Text(context.l10n.taskFocusSwitchTitle),
                    content: Text(
                      context.l10n.taskFocusSwitchMessage(task.content),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: Text(context.l10n.commonCancel),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        child: Text(context.l10n.taskFocusSwitchConfirm),
                      ),
                    ],
                  ),
                ) ==
                true &&
            context.mounted;
      });
      if (opened && context.mounted) context.go('/focus');
    } catch (_) {
      if (context.mounted) _showActionError(context);
    }
  }

  void _showActionError(BuildContext context) {
    showActionFeedback(
      context,
      message: context.l10n.taskActionFailedCount(1),
      icon: LucideIcons.circleAlert,
      sound: ActionFeedbackSound.none,
      haptic: AppHapticCue.none,
    );
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
          .read(taskItemViewModelProvider(task).notifier)
          .nestTask(draggedTaskId);
      if (context.mounted) {
        TaskMotionScope.maybeOf(context)?.landed({draggedTaskId});
        if (branchScope != null) {
          await revealCreatedTaskBranches(context, ref, branchScope!, [
            draggedTaskId,
          ]);
        }
        await playHaptic(AppHapticCue.light);
      }
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      showActionFeedback(
        context,
        message: context.l10n.taskActionFailedCount(1),
        icon: LucideIcons.circleAlert,
        sound: ActionFeedbackSound.none,
        haptic: AppHapticCue.none,
      );
    }
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

class TaskListDivider extends ConsumerWidget {
  const TaskListDivider({
    this.previousDepth = 0,
    this.nextDepth = 0,
    this.nextRow,
    this.previousRow,
    super.key,
  }) : _previewBranchStyle = null,
       _previewHasTrailingContent = null;

  TaskListDivider.preview({
    required VisibleTaskRow previous,
    required VisibleTaskRow next,
    required TaskBranchStyle branchStyle,
    required bool hasTrailingContent,
    super.key,
  }) : previousRow = previous,
       nextRow = next,
       previousDepth = previous.depth,
       nextDepth = next.depth,
       _previewBranchStyle = branchStyle,
       _previewHasTrailingContent = hasTrailingContent;

  final int previousDepth;
  final int nextDepth;
  final VisibleTaskRow? nextRow;
  final VisibleTaskRow? previousRow;
  final TaskBranchStyle? _previewBranchStyle;
  final bool? _previewHasTrailingContent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grouped =
        (_previewBranchStyle ?? ref.watch(taskBranchStyleViewModelProvider)) ==
        TaskBranchStyle.grouped;
    var lineOffset = 0.0;
    if (usesTouchTaskInteraction && previousRow != null) {
      final hasTrailingContent =
          _previewHasTrailingContent ??
          (() {
            final task = previousRow!.task;
            final state = ref.watch(taskItemViewModelProvider(task));
            final progress = ref.watch(taskProgressProvider(task.id)).progress;
            return (task.description?.trim().isNotEmpty ?? false) ||
                task.schedule != null ||
                state.project != null ||
                state.focusEstimate != null ||
                (progress?.total ?? 0) > 0 ||
                previousRow!.hasVisibleChildren;
          })();
      if (hasTrailingContent) {
        lineOffset = math.min(5, _mobileGeometry(context).titleInset / 2);
      }
    }
    final joinsGroup =
        grouped &&
        previousRow?.groupRootId != null &&
        previousRow!.groupRootId == nextRow?.groupRootId;
    final indent =
        (nextRow == null ? 0 : taskBranchGutterWidth) +
        (usesTouchTaskInteraction ? TaskRowGeometry.textStart : 38) +
        (joinsGroup
            ? 12.0 *
                  math.min(
                    previousRow!.groupDisplayDepth,
                    nextRow!.groupDisplayDepth,
                  )
            : 28.0 * math.min(math.min(previousDepth, nextDepth), 2));
    final divider = Padding(
      padding: EdgeInsetsDirectional.only(start: indent),
      child: Transform.translate(
        offset: Offset(0, lineOffset),
        child: Divider(
          height: usesTouchTaskInteraction ? 12 : 1,
          thickness: 1,
          color:
              grouped &&
                  !joinsGroup &&
                  (previousRow?.groupRootId != null ||
                      nextRow?.groupRootId != null)
              ? Colors.transparent
              : context.appColors.border,
        ),
      ),
    );
    if (joinsGroup) {
      return TaskBranchSurface(row: nextRow!, separator: true, child: divider);
    }
    return nextRow == null || grouped
        ? divider
        : TaskBranchLines(row: nextRow!, divider: true, child: divider);
  }
}

TaskRowGeometry _mobileGeometry(BuildContext context) {
  final style = Theme.of(context).textTheme.titleMedium!;
  final scaler = MediaQuery.textScalerOf(context);
  return TaskRowGeometry(
    titleLineHeight: scaler.scale(style.fontSize ?? 16) * (style.height ?? 1.5),
  );
}

Color _priorityColor(
  int priority,
  ColorScheme scheme,
  AppThemePalette colors,
) => switch (priority) {
  1 => colors.overdue,
  2 => colors.warning,
  3 => colors.info,
  _ => scheme.outline,
};

Widget _taskFocusAction(
  BuildContext context, {
  required bool enabled,
  required VoidCallback onPressed,
  Key? key,
}) => IconButton(
  key: key,
  tooltip: context.l10n.startFocus,
  onPressed: enabled ? onPressed : null,
  style: IconButton.styleFrom(
    backgroundColor: context.appColors.accentTint,
    foregroundColor: context.appColors.accent,
    disabledBackgroundColor: Colors.transparent,
    disabledForegroundColor: context.appColors.mutedText,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  ),
  icon: const Icon(LucideIcons.play),
);

Widget _desktopTaskActions(
  BuildContext context, {
  required bool columns,
  required bool active,
  required Widget focusAction,
  required Widget overflowAction,
}) => SizedBox(
  width: columns ? 96 : 48,
  child: AnimatedOpacity(
    opacity: !columns || active ? 1 : 0,
    duration: AppMotion.duration(context, AppMotion.hover),
    curve: AppMotion.curve,
    alwaysIncludeSemantics: true,
    child: Row(
      children: [
        if (columns) Expanded(child: focusAction),
        Expanded(child: overflowAction),
      ],
    ),
  ),
);

/// Appearance sample shares row contents and hover feedback; actions stay inert.
class TaskListRowPreview extends StatelessWidget {
  const TaskListRowPreview({
    required this.task,
    required this.row,
    required this.style,
    required this.spacing,
    required this.branchStyle,
    this.project,
    this.progress,
    this.timeDisplayMode = TaskTimeDisplayMode.smart,
    this.timedMinutes = 30,
    super.key,
  });

  final TaskItem task;
  final VisibleTaskRow row;
  final TaskListStyle style;
  final TaskRowSpacing spacing;
  final TaskBranchStyle branchStyle;
  final ProjectItem? project;
  final TaskSubtaskProgress? progress;
  final TaskTimeDisplayMode timeDisplayMode;
  final int timedMinutes;

  @override
  Widget build(BuildContext context) => _AgendaInteractionRegion(
    taskId: task.id,
    builder: (context, active) => LayoutBuilder(
      builder: (context, constraints) {
        final mobile = usesTouchTaskInteraction;
        final desktopColumns =
            constraints.maxWidth - taskBranchGutterWidth - 56 >=
            840 * MediaQuery.textScalerOf(context).scale(14) / 14;
        final grouped = branchStyle == TaskBranchStyle.grouped;
        final padding = TaskRowGeometry.verticalPadding(spacing);
        final completion = SizedBox(
          width: mobile ? 44 : 34,
          height: mobile ? 44 : null,
          child: Center(
            child: TaskCompletionControl(
              taskId: task.id,
              isCompleted: task.isCompleted,
              color: task.isCompleted
                  ? context.appColors.accent
                  : _priorityColor(
                      task.priority,
                      Theme.of(context).colorScheme,
                      context.appColors,
                    ),
              fillColor: context.appColors.accentFill,
              hitSize: mobile ? 44 : 24,
              onPressed: null,
            ),
          ),
        );
        final focusAction = _taskFocusAction(
          context,
          enabled: !task.isCompleted,
          onPressed: () {},
        );
        final disclosure = mobile
            ? SizedBox.square(
                dimension: 44,
                child: row.hasVisibleChildren
                    ? Icon(
                        LucideIcons.chevronDown,
                        size: 16,
                        color: context.appColors.secondaryText,
                      )
                    : null,
              )
            : style == TaskListStyle.modern
            ? _desktopTaskActions(
                context,
                columns: desktopColumns,
                active:
                    active || !_usesImmediateTaskDrag(defaultTargetPlatform),
                focusAction: focusAction,
                overflowAction: AppActionMenu(
                  tooltip: context.l10n.moreFocusActions,
                  items: const [],
                ),
              )
            : focusAction;
        final state = task.isCompleted
            ? TaskTimeState.completed
            : TaskTimeState.future;
        final focusEstimate = task.estimatedFocusIntervals;
        final content = Padding(
          padding: EdgeInsetsDirectional.fromSTEB(
            grouped ? row.groupDisplayDepth * 12.0 : row.displayDepth * 28.0,
            padding,
            4,
            padding,
          ),
          child: mobile
              ? _MobileTaskContent(
                  rowSpacing: spacing,
                  task: task,
                  modern: style == TaskListStyle.modern,
                  description: task.description,
                  project: project,
                  progress: progress,
                  focusEstimate: focusEstimate,
                  taskTimeState: state,
                  timeDisplayMode: timeDisplayMode,
                  defaultTimedBlockMinutes: timedMinutes,
                  withinDate: false,
                  parentContext: row.depth > 2
                      ? TaskParentContext(task: task, ancestors: row.ancestors)
                      : null,
                  completion: completion,
                  disclosure: disclosure,
                )
              : Row(
                  children: [
                    SizedBox(
                      width: taskBranchGutterWidth,
                      child: row.hasVisibleChildren && progress != null
                          ? TaskBranchProgressButton(
                              taskId: task.id,
                              progress: progress!,
                              expanded: row.expanded,
                              onToggle: () {},
                              showProgress: false,
                            )
                          : null,
                    ),
                    completion,
                    const SizedBox(width: 4),
                    Expanded(
                      child: style == TaskListStyle.modern
                          ? _AgendaTaskContent(
                              rowSpacing: spacing,
                              task: task,
                              project: project,
                              focusEstimate: focusEstimate,
                              allowMetadataWrap: !desktopColumns,
                              subtaskProgress: progress,
                              dragEnabled: false,
                              taskTimeState: state,
                              timeDisplayMode: timeDisplayMode,
                              defaultTimedBlockMinutes: timedMinutes,
                              modern: true,
                              withinDate: false,
                              description: task.description,
                            )
                          : Row(
                              children: [
                                Expanded(
                                  child: _TaskContent(
                                    rowSpacing: spacing,
                                    task: task,
                                    description: task.description,
                                    hasDescription:
                                        task.description?.isNotEmpty ?? false,
                                    hasMeta:
                                        task.schedule != null ||
                                        focusEstimate != null,
                                    focusEstimate: focusEstimate,
                                    taskTimeState: state,
                                    timeDisplayMode: timeDisplayMode,
                                    defaultTimedBlockMinutes: timedMinutes,
                                  ),
                                ),
                                SizedBox(
                                  width: MediaQuery.textScalerOf(
                                    context,
                                  ).scale(72),
                                  child: progress == null
                                      ? null
                                      : TaskBranchProgressButton(
                                          taskId: task.id,
                                          progress: progress!,
                                        ),
                                ),
                              ],
                            ),
                    ),
                    const SizedBox(width: 8),
                    disclosure,
                  ],
                ),
        );
        return AbsorbPointer(
          child: grouped
              ? TaskBranchSurface(row: row, child: content)
              : TaskBranchLines(
                  row: row,
                  anchor: mobile
                      ? padding + _mobileGeometry(context).anchor
                      : null,
                  child: content,
                ),
        );
      },
    ),
  );
}

class _MobileTaskContent extends StatelessWidget {
  const _MobileTaskContent({
    required this.rowSpacing,
    required this.task,
    required this.modern,
    required this.description,
    required this.project,
    required this.progress,
    required this.focusEstimate,
    required this.taskTimeState,
    required this.timeDisplayMode,
    required this.defaultTimedBlockMinutes,
    required this.withinDate,
    required this.parentContext,
    required this.completion,
    required this.disclosure,
  });
  final TaskRowSpacing rowSpacing;
  final TaskItem task;
  final bool modern;
  final String? description;
  final ProjectItem? project;
  final TaskSubtaskProgress? progress;
  final int? focusEstimate;
  final TaskTimeState? taskTimeState;
  final TaskTimeDisplayMode timeDisplayMode;
  final int defaultTimedBlockMinutes;
  final bool withinDate;
  final TaskParentContext? parentContext;
  final Widget completion;
  final Widget disclosure;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final geometry = _mobileGeometry(context);
    final blockGap = TaskRowGeometry.mobileBlockGap(rowSpacing);
    final titleStyle = Theme.of(context).textTheme.titleMedium!.copyWith(
      height: Theme.of(context).textTheme.titleMedium!.height ?? 1.5,
      fontWeight: modern ? FontWeight.w600 : null,
      color: task.isCompleted ? colors.mutedText : colors.primaryText,
      decoration: task.isCompleted ? TextDecoration.lineThrough : null,
    );
    final scheduleRows = formatTaskListScheduleRows(
      context,
      task.schedule,
      withinDate: withinDate,
      displayMode: timeDisplayMode,
      defaultTimedBlockMinutes: defaultTimedBlockMinutes,
    );
    final scheduleColor = taskTimeState == null
        ? colors.mutedText
        : colors.taskTimeColor(taskTimeState!);
    final scheduleLabel = scheduleRows.map((row) => row.join(' ')).join(', ');
    final status = taskTimeState == null
        ? null
        : taskTimeStatusLabel(context.l10n, taskTimeState!);
    final blocks = <Widget>[
      if (description?.isNotEmpty ?? false)
        Text(
          description!,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.mutedText),
        ),
      if (scheduleRows.isNotEmpty)
        Semantics(
          label: status == null ? scheduleLabel : '$scheduleLabel, $status',
          excludeSemantics: true,
          child: Row(
            key: ValueKey('task-time-meta-${task.id}'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(LucideIcons.calendar, size: 14, color: scheduleColor),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  key: ValueKey('task-time-label-${task.id}'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final row in scheduleRows)
                      Wrap(
                        spacing: 4,
                        children: [
                          for (final part in row)
                            Text(
                              part,
                              softWrap: true,
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(color: scheduleColor),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      if (project != null ||
          focusEstimate != null ||
          (progress?.total ?? 0) > 0)
        Wrap(
          spacing: 8,
          runSpacing: blockGap,
          children: [
            if (project != null) _AgendaProjectLabel(project: project!),
            if (focusEstimate != null)
              _FixedMetaText(
                flexible: true,
                icon: LucideIcons.timer,
                label: '${task.completedFocusIntervals}/$focusEstimate',
              ),
            if ((progress?.total ?? 0) > 0)
              Semantics(
                label: context.l10n.taskAllSubtasksProgress(
                  progress!.completed,
                  progress!.total,
                ),
                excludeSemantics: true,
                child: _FixedMetaText(
                  flexible: true,
                  icon: LucideIcons.gitBranch,
                  label: progress!.label,
                ),
              ),
          ],
        ),
    ];
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: TaskRowGeometry.controlSize),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: TaskRowGeometry.textStart,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: EdgeInsetsDirectional.only(
                    top: geometry.titleInset,
                    end: TaskRowGeometry.controlSize,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Flexible(
                        child: Text(
                          task.content,
                          softWrap: true,
                          style: titleStyle,
                        ),
                      ),
                      if (parentContext != null) ...[
                        const SizedBox(width: 4),
                        Padding(
                          padding: EdgeInsets.only(
                            top: math.max(
                              0,
                              (geometry.titleLineHeight - 12) / 2,
                            ),
                          ),
                          child: parentContext!,
                        ),
                      ],
                    ],
                  ),
                ),
                for (final block in blocks) ...[
                  SizedBox(height: blockGap),
                  block,
                ],
              ],
            ),
          ),
          PositionedDirectional(
            start: 0,
            top: geometry.controlInset,
            child: completion,
          ),
          PositionedDirectional(
            end: 0,
            top: geometry.controlInset,
            child: disclosure,
          ),
        ],
      ),
    );
  }
}

class _AgendaTaskContent extends StatelessWidget {
  const _AgendaTaskContent({
    required this.rowSpacing,
    required this.task,
    required this.project,
    required this.focusEstimate,
    required this.allowMetadataWrap,
    required this.subtaskProgress,
    required this.dragEnabled,
    required this.taskTimeState,
    required this.timeDisplayMode,
    required this.defaultTimedBlockMinutes,
    this.modern = false,
    this.withinDate = true,
    this.description,
  });

  final TaskRowSpacing rowSpacing;
  final TaskItem task;
  final ProjectItem? project;
  final int? focusEstimate;
  final bool allowMetadataWrap;
  final TaskSubtaskProgress? subtaskProgress;
  final bool dragEnabled;
  final TaskTimeState? taskTimeState;
  final TaskTimeDisplayMode timeDisplayMode;
  final int defaultTimedBlockMinutes;
  final bool modern;
  final bool withinDate;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final schedule = task.schedule;
    final scheduleLabel = schedule == null
        ? null
        : (withinDate
              ? formatTaskListScheduleWithinDate
              : formatTaskListSchedule)(
            context,
            schedule,
            displayMode: timeDisplayMode,
            defaultTimedBlockMinutes: defaultTimedBlockMinutes,
          );
    Widget dragSource(Widget child) =>
        _TaskTextDragSource(task: task, enabled: dragEnabled, child: child);
    final textScaler = MediaQuery.textScalerOf(context);
    final metadata = <Widget>[
      SizedBox(
        width: textScaler.scale(120),
        child: project == null
            ? null
            : dragSource(_AgendaProjectLabel(project: project!)),
      ),
      SizedBox(
        width: textScaler.scale(56),
        child: focusEstimate == null
            ? null
            : dragSource(
                _FixedMetaText(
                  flexible: true,
                  icon: LucideIcons.timer,
                  label: '${task.completedFocusIntervals}/$focusEstimate',
                ),
              ),
      ),
      SizedBox(
        width: textScaler.scale(72),
        child: subtaskProgress != null && subtaskProgress!.total > 0
            ? TaskBranchProgressButton(
                taskId: task.id,
                progress: subtaskProgress!,
              )
            : null,
      ),
    ];
    final title = AnimatedDefaultTextStyle(
      duration: modern
          ? AppMotion.duration(context, AppMotion.state)
          : MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 340),
      curve: modern ? AppMotion.curve : Curves.linear,
      style: Theme.of(context).textTheme.titleMedium!.copyWith(
        fontWeight: modern ? FontWeight.w600 : null,
        color: task.isCompleted ? colors.mutedText : colors.primaryText,
        decoration: task.isCompleted ? TextDecoration.lineThrough : null,
        decorationColor: colors.mutedText,
      ),
      child: Text(
        task.content,
        maxLines: modern && !withinDate ? 2 : 1,
        overflow: TextOverflow.ellipsis,
      ),
    );

    final hasDescription = modern && (description?.isNotEmpty ?? false);
    final heading = dragSource(
      hasDescription || scheduleLabel != null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                title,
                if (hasDescription) ...[
                  SizedBox(height: TaskRowGeometry.blockGap(rowSpacing, 2)),
                  Text(
                    description!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: colors.mutedText),
                  ),
                ],
                if (scheduleLabel != null) ...[
                  SizedBox(height: TaskRowGeometry.blockGap(rowSpacing, 4)),
                  _TaskTimeMetaText(
                    taskId: task.id,
                    label: scheduleLabel,
                    state: taskTimeState,
                    color: taskTimeState == null
                        ? colors.mutedText
                        : colors.taskTimeColor(taskTimeState!),
                    textStyle: Theme.of(context).textTheme.labelMedium,
                    key: const Key('agenda-schedule-label'),
                  ),
                ],
              ],
            )
          : title,
    );
    if (allowMetadataWrap) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          heading,
          SizedBox(height: TaskRowGeometry.blockGap(rowSpacing, 4)),
          LayoutBuilder(
            builder: (context, constraints) => Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 12,
                runSpacing: TaskRowGeometry.blockGap(rowSpacing, 4),
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final item in metadata)
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: constraints.maxWidth,
                      ),
                      child: item,
                    ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: heading),
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
              project.displayName(context.l10n),
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
    required this.rowSpacing,
    required this.task,
    required this.description,
    required this.hasDescription,
    required this.hasMeta,
    required this.focusEstimate,
    required this.taskTimeState,
    required this.timeDisplayMode,
    required this.defaultTimedBlockMinutes,
  });

  final TaskRowSpacing rowSpacing;
  final TaskItem task;
  final String? description;
  final bool hasDescription;
  final bool hasMeta;
  final int? focusEstimate;
  final TaskTimeState? taskTimeState;
  final TaskTimeDisplayMode timeDisplayMode;
  final int defaultTimedBlockMinutes;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final metaItems = <Widget>[
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
          icon: LucideIcons.timer,
          label: '${task.completedFocusIntervals}/$focusEstimate',
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedDefaultTextStyle(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 340),
          style: Theme.of(context).textTheme.titleMedium!.copyWith(
            color: task.isCompleted ? colors.mutedText : colors.primaryText,
            decoration: task.isCompleted ? TextDecoration.lineThrough : null,
            decorationColor: colors.mutedText,
          ),
          child: Text(
            task.content,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (hasDescription) ...[
          SizedBox(height: TaskRowGeometry.blockGap(rowSpacing, 2)),
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
          SizedBox(height: TaskRowGeometry.blockGap(rowSpacing, 6)),
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
    return Transform.scale(
      scale: 1.025,
      child: Material(
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
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
      children: [
        Icon(LucideIcons.calendar, size: 14, color: color),
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
      softWrap: false,
      style: textStyle?.copyWith(color: color),
    );
  }
}

class _FixedMetaText extends StatelessWidget {
  const _FixedMetaText({
    required this.icon,
    required this.label,
    this.flexible = false,
  });

  final IconData icon;
  final String label;
  final bool flexible;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    final text = Text(
      label,
      maxLines: 1,
      overflow: flexible ? TextOverflow.ellipsis : TextOverflow.clip,
      softWrap: false,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
    );
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        if (flexible) Flexible(child: text) else text,
      ],
    );
    return content;
  }
}

enum _TaskQuickAction {
  select,
  schedule,
  move,
  choosePriority,
  duplicate,
  deleteSelection,
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
  const _TaskTextDragSource({
    required this.task,
    required this.child,
    this.enabled = true,
  });

  final TaskItem task;
  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
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
    return child;
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
        if (selected) const Icon(LucideIcons.check, size: 18),
      ],
    );
  }
}
