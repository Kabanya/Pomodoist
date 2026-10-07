import 'package:pomodoist/domain/models/settings/task_preferences.dart';
import 'package:pomodoist/ui/files/widgets/files_panel.dart';
import 'package:pomodoist/ui/tasks/view_models/task_subtask_progress.dart';
import 'dart:async';
import 'package:pomodoist/ui/tasks/view_models/task_branch_view_model.dart';
import 'package:pomodoist/ui/tasks/view_models/task_branch_rows.dart';
import 'package:pomodoist/ui/tasks/widgets/task_branch_widgets.dart';

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart'
    show
        LucideIcons,
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

import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/themes/app_motion.dart';
import 'package:pomodoist/ui/core/localization/formatters.dart';
import 'package:pomodoist/ui/tasks/view_models/task_detail_view_model.dart';
import 'package:pomodoist/ui/tasks/view_models/task_item_view_model.dart';
import 'package:pomodoist/routing/task_detail_navigation.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/core/widgets/action_feedback.dart';
import 'package:pomodoist/ui/core/widgets/app_action_menu.dart';
import 'package:pomodoist/ui/core/widgets/app_date_time_picker.dart';
import 'package:pomodoist/ui/collaboration/widgets/collaboration_copy.dart';
import 'package:pomodoist/ui/tasks/view_models/task_history_view_model.dart';
import 'package:pomodoist/ui/collaboration/widgets/task_collaboration_section.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/ui/tasks/widgets/task_completion_feedback.dart';
import 'package:pomodoist/ui/tasks/widgets/quick_add_bar.dart';
import 'package:pomodoist/ui/tasks/view_models/quick_add_text_controller.dart';
import 'package:pomodoist/ui/tasks/widgets/task_list_item.dart';
import 'package:pomodoist/ui/tasks/widgets/task_selection_region.dart';
import 'package:pomodoist/ui/tasks/widgets/task_motion.dart';
import 'package:pomodoist/ui/tasks/widgets/project_localizations.dart';

enum _TaskDetailTab { details, files, discussion }

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
  _TaskDetailTab _selectedTab = _TaskDetailTab.details;
  final _titleKey = GlobalKey<_EditableTaskTitleState>();
  final _descriptionKey = GlobalKey<_EditableTaskDescriptionState>();
  final _saveIdentity = Object();
  final _titleEditorIdentity = Object();
  final _descriptionEditorIdentity = Object();
  final _subtaskEditorIdentity = Object();
  late final TaskDetailSaveGuard _saveGuard;
  late final Future<bool> Function() _saveCallback;

  @override
  void initState() {
    super.initState();
    _saveGuard = ref.read(taskDetailSaveGuardProvider);
    _saveCallback = saveEdits;
    _saveGuard.register(_saveIdentity, _saveCallback);
  }

  @override
  void dispose() {
    _saveGuard.unregister(_saveIdentity);
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

  Future<bool> _confirmFocusSwitch(String title) async {
    if (!mounted) return false;
    return await showDialog<bool>(
              context: context,
              animationStyle: AnimationStyle(
                duration: AppMotion.duration(context, AppMotion.popup),
                reverseDuration: AppMotion.duration(context, AppMotion.popup),
                curve: AppMotion.curve,
              ),
              builder: (dialogContext) => AlertDialog(
                title: Text(context.l10n.taskFocusSwitchTitle),
                content: Text(context.l10n.taskFocusSwitchMessage(title)),
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
        mounted;
  }

  Future<void> _runFocusAction(
    TaskDetailFocusAction action,
    String? runId,
    String taskTitle,
  ) async {
    final viewModel = ref.read(
      taskDetailViewModelProvider(widget.taskId).notifier,
    );
    try {
      if (action == TaskDetailFocusAction.startFocus) {
        await viewModel.startFocus(() => _confirmFocusSwitch(taskTitle));
      } else {
        if (runId == null) return;
        await viewModel.performFocusAction(action, runId);
      }
    } catch (_) {
      if (!mounted) return;
      showActionFeedback(
        context,
        message: context.l10n.focusActionFailed,
        icon: LucideIcons.circleAlert,
        sound: ActionFeedbackSound.none,
        haptic: AppHapticCue.none,
      );
    }
  }

  Widget _header(BuildContext context, [TaskItem? item, String? projectName]) {
    final l10n = context.l10n;
    return Row(
      children: [
        Expanded(
          child: Text(
            projectName ?? l10n.navInbox,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.appColors.secondaryText,
            ),
          ),
        ),
        if (item != null)
          AppActionMenu(
            tooltip: l10n.taskMore,
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
          ),
        Tooltip(
          message: widget.isPanel ? l10n.commonClose : l10n.commonBack,
          child: ShadIconButton.ghost(
            onPressed: () => _goBack(context),
            icon: Icon(widget.isPanel ? LucideIcons.x : LucideIcons.arrowLeft),
            width: 44,
            height: 44,
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

  Widget _tab(
    _TaskDetailTab tab,
    String label,
    _TaskDetailTab active, [
    int? count,
  ]) {
    final selected = tab == active;
    return Semantics(
      selected: selected,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? context.appColors.accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: TextButton(
          style: TextButton.styleFrom(
            minimumSize: const Size(44, 44),
            foregroundColor: selected
                ? context.appColors.primaryText
                : context.appColors.secondaryText,
            shape: const RoundedRectangleBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 12),
          ),
          onPressed: () => setState(() => _selectedTab = tab),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label),
              if (count != null && count > 0) ...[
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.appColors.secondaryText,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final taskId = widget.taskId;
    final l10n = context.l10n;
    final viewState = ref.watch(taskDetailViewModelProvider(taskId));
    final descriptionFirst =
        viewState.layout == TaskDetailLayout.descriptionFirst;
    final task = viewState.task;
    final viewModel = ref.read(taskDetailViewModelProvider(taskId).notifier);
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
              final focusEstimate = viewState.focusEstimate;
              final focusAction = viewState.focusAction;
              final focusLabel = switch (focusAction) {
                TaskDetailFocusAction.pause ||
                TaskDetailFocusAction.pauseUnavailable => l10n.pause,
                TaskDetailFocusAction.resume => l10n.resume,
                TaskDetailFocusAction.startInterval => l10n.startInterval,
                _ => l10n.startFocus,
              };
              final focusDisabled =
                  focusAction == null ||
                  focusAction == TaskDetailFocusAction.pauseUnavailable ||
                  (item.isCompleted &&
                      focusAction == TaskDetailFocusAction.startFocus);
              final shared = item.scopeId != null;
              final activeTab =
                  !shared && _selectedTab == _TaskDetailTab.discussion
                  ? _TaskDetailTab.details
                  : _selectedTab;
              final showDetails =
                  descriptionFirst || activeTab == _TaskDetailTab.details;
              final inset = widget.isPanel ? 24.0 : 20.0;
              Widget retained(String key, bool visible, Widget child) =>
                  Visibility(
                    key: ValueKey(key),
                    visible: visible,
                    maintainState: true,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: child,
                    ),
                  );
              final properties = retained(
                'properties',
                showDetails,
                _DetailDisclosure(
                  label: l10n.taskProperties,
                  alwaysOpen: !descriptionFirst,
                  child: _TaskProperties(
                    task: item,
                    projectName: viewState.projectName,
                    projects: viewState.projects,
                    calendarLinked: viewState.calendarLinked,
                  ),
                ),
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(inset, 8, inset, 8),
                    child: _header(context, item, viewState.projectName),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: inset),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Tooltip(
                          message: item.isCompleted
                              ? l10n.markOpen
                              : l10n.markComplete,
                          child: SizedBox(
                            width: 44,
                            height: 44,
                            child: Center(
                              child: TaskCompletionControl(
                                taskId: item.id,
                                isCompleted: item.isCompleted,
                                hitSize: 44,
                                color: context.appColors.accent,
                                fillColor: context.appColors.accentFill,
                                onPressed: !item.canEdit
                                    ? null
                                    : () async {
                                        if (item.isCompleted) {
                                          try {
                                            await viewModel.reopen();
                                          } catch (_) {
                                            if (context.mounted) {
                                              showActionFeedback(
                                                context,
                                                message: l10n
                                                    .taskActionFailedCount(1),
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
                                          final reopened = await viewModel
                                              .current();
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
                                          complete: viewModel.complete,
                                          undo: viewModel.reopen,
                                        );
                                      },
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: _EditableTaskTitle(
                              key: _titleKey,
                              identity: _titleEditorIdentity,
                              task: item,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(inset, 8, inset, 8),
                    child: Wrap(
                      spacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Tooltip(
                          message:
                              focusAction ==
                                  TaskDetailFocusAction.pauseUnavailable
                              ? l10n.focusPauseUnavailable
                              : focusLabel,
                          child: TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: context.appColors.primaryText,
                              minimumSize: const Size(44, 44),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                            ),
                            onPressed: focusDisabled
                                ? null
                                : () => _runFocusAction(
                                    focusAction,
                                    viewState.focusRunId,
                                    item.content,
                                  ),
                            icon: Icon(
                              focusAction == TaskDetailFocusAction.pause ||
                                      focusAction ==
                                          TaskDetailFocusAction.pauseUnavailable
                                  ? LucideIcons.pause
                                  : LucideIcons.play,
                              size: 16,
                            ),
                            label: Text(focusLabel),
                          ),
                        ),
                        Text(
                          l10n.focusProgress(
                            item.completedFocusIntervals,
                            focusEstimate ?? 0,
                          ),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: context.appColors.secondaryText,
                              ),
                        ),
                        if (item.totalFocusSeconds > 0)
                          Text(
                            formatFocusTime(context, item.totalFocusSeconds),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: context.appColors.secondaryText,
                                ),
                          ),
                      ],
                    ),
                  ),
                  Visibility(
                    visible: !descriptionFirst,
                    maintainState: true,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: inset),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: context.appColors.border),
                          ),
                        ),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _tab(
                                _TaskDetailTab.details,
                                l10n.taskDetailsTab,
                                activeTab,
                              ),
                              _tab(
                                _TaskDetailTab.files,
                                l10n.filesTitle,
                                activeTab,
                                viewState.fileCount,
                              ),
                              if (shared)
                                _tab(
                                  _TaskDetailTab.discussion,
                                  l10n.taskDiscussionTab,
                                  activeTab,
                                  viewState.commentCount,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(inset, 20, inset, 24),
                      child: TaskMotionItem(
                        taskId: item.id,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (!descriptionFirst) properties,
                            retained(
                              'description',
                              showDetails,
                              _EditableTaskDescription(
                                key: _descriptionKey,
                                identity: _descriptionEditorIdentity,
                                task: item,
                              ),
                            ),
                            retained(
                              'files',
                              descriptionFirst ||
                                  activeTab == _TaskDetailTab.files,
                              FilesPanel(taskId: item.id, compact: true),
                            ),
                            retained(
                              'subtasks',
                              showDetails,
                              _SubtasksSection(
                                identity: _subtaskEditorIdentity,
                                task: item,
                              ),
                            ),
                            if (descriptionFirst) properties,
                            retained(
                              'history',
                              showDetails,
                              _DetailDisclosure(
                                label: l10n.focusHistory,
                                child: _FocusHistory(task: item),
                              ),
                            ),
                            retained(
                              'discussion',
                              shared &&
                                  (descriptionFirst ||
                                      activeTab == _TaskDetailTab.discussion),
                              TaskCollaborationSection(
                                task: item,
                                showAssignees: false,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
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

class _PropertyRow extends StatelessWidget {
  const _PropertyRow({
    required this.icon,
    required this.label,
    required this.child,
  });
  final IconData icon;
  final String label;
  final Widget child;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 15, color: context.appColors.secondaryText),
        const SizedBox(width: 8),
        Flexible(
          flex: 2,
          child: SizedBox(
            width: 108,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.appColors.secondaryText,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(flex: 3, child: child),
      ],
    ),
  );
}

class _DetailDisclosure extends StatefulWidget {
  const _DetailDisclosure({
    required this.label,
    required this.child,
    this.alwaysOpen = false,
    this.icon,
    this.value,
  });
  final String label;
  final Widget child;
  final bool alwaysOpen;
  final IconData? icon;
  final String? value;
  @override
  State<_DetailDisclosure> createState() => _DetailDisclosureState();
}

class _DetailDisclosureState extends State<_DetailDisclosure> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (!widget.alwaysOpen)
        TextButton(
          style: TextButton.styleFrom(
            alignment: Alignment.centerLeft,
            foregroundColor: context.appColors.secondaryText,
            minimumSize: const Size(44, 44),
            padding: EdgeInsets.zero,
          ),
          onPressed: () => setState(() => _expanded = !_expanded),
          child: widget.icon == null
              ? Row(
                  children: [
                    Expanded(child: Text(widget.label)),
                    Icon(
                      _expanded
                          ? LucideIcons.chevronUp
                          : LucideIcons.chevronDown,
                      size: 16,
                    ),
                  ],
                )
              : _PropertyRow(
                  icon: widget.icon!,
                  label: widget.label,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.value ?? '',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      Icon(
                        _expanded
                            ? LucideIcons.chevronUp
                            : LucideIcons.chevronDown,
                        size: 14,
                      ),
                    ],
                  ),
                ),
        ),
      Visibility(
        visible: widget.alwaysOpen || _expanded,
        maintainState: true,
        child: widget.child,
      ),
    ],
  );
}

class _TaskProperties extends ConsumerWidget {
  const _TaskProperties({
    required this.task,
    required this.projectName,
    required this.projects,
    required this.calendarLinked,
  });
  final TaskItem task;
  final String? projectName;
  final List<ProjectItem> projects;
  final bool calendarLinked;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final scheduleState = ref.watch(taskScheduleViewModelProvider(task));
    final timeState = scheduleState.timeState;
    final color = timeState == null
        ? colors.primaryText
        : colors.taskTimeColor(timeState);
    final scheduleLabel = formatTaskSchedule(
      context,
      task.schedule,
      displayMode: scheduleState.displayMode,
      defaultTimedBlockMinutes: scheduleState.timedMinutes,
    );
    Widget menu(
      Widget child,
      List<Widget> items, {
      Key? key,
      FocusNode? focusNode,
      bool enabled = true,
    }) => LayoutBuilder(
      builder: (context, constraints) => ShadMenubar(
        key: key,
        padding: EdgeInsets.zero,
        border: ShadBorder.none,
        backgroundColor: Colors.transparent,
        items: [
          ShadMenubarItem(
            enabled: task.canEdit && enabled,
            height: 44,
            width: constraints.maxWidth,
            focusNode: focusNode,
            buttonPadding: const EdgeInsets.symmetric(horizontal: 4),
            items: items,
            child: SizedBox(
              width: (constraints.maxWidth - 8).clamp(0, double.infinity),
              child: DefaultTextStyle.merge(
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                child: child,
              ),
            ),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PropertyRow(
          icon: LucideIcons.calendar,
          label: l10n.scheduleTitle,
          child: AppDateTimePicker(
            builder: (context, picker) => menu(
              Semantics(
                label: timeState == null
                    ? scheduleLabel
                    : '$scheduleLabel, ${taskTimeStatusLabel(l10n, timeState)}',
                child: Text(scheduleLabel, style: TextStyle(color: color)),
              ),
              [
                ShadContextMenuItem(
                  onPressed: () async {
                    try {
                      final result = await showTaskDuePanel(context, ref);
                      if (result == null || !context.mounted) return;
                      await ref
                          .read(taskItemViewModelProvider(task).notifier)
                          .schedule(result);
                    } catch (_) {
                      if (context.mounted) _showEditFailure(context);
                    }
                  },
                  child: Text(l10n.scheduleTitle),
                ),
                const Divider(height: 8),
                ShadContextMenuItem(
                  onPressed: () => unawaited(
                    _runScheduleQuickAction(
                      context,
                      ref,
                      task,
                      picker,
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
                      picker,
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
                      picker,
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
                      picker,
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
                        picker,
                        _ScheduleQuickAction.clear,
                      ),
                    ),
                    child: Text(l10n.clearDate),
                  ),
                ],
              ],
              key: const Key('task-detail-schedule-chip'),
              focusNode: picker.focusNode,
            ),
          ),
        ),
        if (calendarLinked)
          Padding(
            padding: const EdgeInsets.only(left: 24, bottom: 4),
            child: Text(
              l10n.calendarLinked,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.secondaryText),
            ),
          ),
        _PropertyRow(
          icon: LucideIcons.flag,
          label: l10n.taskPriority,
          child: menu(
            Text(
              l10n.priority(task.priority),
              style: TextStyle(color: _priorityColor(task.priority, colors)),
            ),
            [
              for (final priority in [1, 2, 3, 4])
                ShadContextMenuItem(
                  trailing: Icon(
                    task.priority == priority ? LucideIcons.check : null,
                    size: 16,
                  ),
                  onPressed: () => unawaited(
                    ref
                        .read(taskScheduleViewModelProvider(task).notifier)
                        .setPriority(priority),
                  ),
                  child: Text(l10n.priority(priority)),
                ),
            ],
            key: const Key('task-detail-priority-chip'),
          ),
        ),
        _PropertyRow(
          icon: LucideIcons.folder,
          label: l10n.taskProject,
          child: menu(
            Row(
              children: [
                Expanded(
                  child: Text(
                    task.projectId == inboxProjectId
                        ? l10n.navInbox
                        : projectName ?? l10n.navInbox,
                  ),
                ),
                const Icon(LucideIcons.chevronDown, size: 14),
              ],
            ),
            [
              for (final project in projects)
                ShadContextMenuItem(
                  height: 44,
                  trailing: Icon(
                    task.projectId == project.id ? LucideIcons.check : null,
                    size: 16,
                  ),
                  onPressed: () => unawaited(() async {
                    try {
                      await ref
                          .read(taskDetailViewModelProvider(task.id).notifier)
                          .setProject(project.id);
                    } catch (_) {
                      if (context.mounted) _showEditFailure(context);
                    }
                  }()),
                  child: Text(project.displayName(l10n)),
                ),
            ],
            key: const Key('task-detail-project-chip'),
            enabled: projects.isNotEmpty,
          ),
        ),
        if (task.scopeId != null)
          TaskCollaborationSection(task: task, showComments: false),
        _DetailDisclosure(
          label: l10n.recurrenceTitle,
          icon: LucideIcons.repeat,
          value: switch (task.schedule?.recurrence) {
            final recurrence? => switch (recurrence.unit) {
              TaskRecurrenceUnit.day => l10n.recurrenceEveryDays(
                recurrence.interval,
              ),
              TaskRecurrenceUnit.week => l10n.recurrenceEveryWeeks(
                recurrence.interval,
              ),
              TaskRecurrenceUnit.month => l10n.recurrenceEveryMonths(
                recurrence.interval,
              ),
            },
            null => l10n.never,
          },
          child: _RecurrenceActions(task: task),
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
  AppDateTimePickerState picker,
  _ScheduleQuickAction action,
) {
  switch (action) {
    case _ScheduleQuickAction.today:
      final today = _today(ref, task);
      return _setTaskSchedule(
        ref,
        task,
        task.schedule?.moveToDate(today) ?? TaskSchedule.allDay(today),
      );
    case _ScheduleQuickAction.tomorrow:
      final tomorrow = _today(ref, task).add(const Duration(days: 1));
      return _setTaskSchedule(
        ref,
        task,
        task.schedule?.moveToDate(tomorrow) ?? TaskSchedule.allDay(tomorrow),
      );
    case _ScheduleQuickAction.allDay:
      return _pickAllDaySchedule(context, ref, task, picker);
    case _ScheduleQuickAction.timed:
      return _pickTimedSchedule(context, ref, task, picker);
    case _ScheduleQuickAction.clear:
      return _clearTaskSchedule(ref, task);
  }
}

class _EditableTaskTitle extends ConsumerStatefulWidget {
  const _EditableTaskTitle({
    required this.identity,
    required this.task,
    super.key,
  });

  final Object identity;
  final TaskItem task;

  @override
  ConsumerState<_EditableTaskTitle> createState() => _EditableTaskTitleState();
}

class _EditableTaskTitleState extends ConsumerState<_EditableTaskTitle> {
  final _controller = QuickAddTextController();
  final _focusNode = FocusNode();
  bool _editing = false;
  bool get _saving =>
      ref.read(taskEditorViewModelProvider(widget.identity)).saving;
  Future<bool>? _pendingSave;

  @override
  void initState() {
    super.initState();
    final state = ref.read(taskEditorViewModelProvider(widget.identity));
    if (state.dirty || state.failed) {
      _editing = true;
      _controller.text = state.draft;
    }
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
    ref.watch(
      taskEditorViewModelProvider(
        widget.identity,
      ).select((state) => state.saving),
    );
    final style = Theme.of(context).textTheme.headlineSmall?.copyWith(
      fontWeight: FontWeight.w600,
      height: 1.35,
    );
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
        onChanged: (value) => ref
            .read(taskEditorViewModelProvider(widget.identity).notifier)
            .updateDraft(value),
        onSubmitted: (_) => unawaited(_finishEditing()),
      );
    }
    return MouseRegion(
      cursor: SystemMouseCursors.text,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: widget.task.canEdit ? _startEditing : null,
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
    final provider = taskEditorViewModelProvider(widget.identity);
    final state = ref.read(provider);
    final draft = state.dirty || state.failed
        ? state.draft
        : widget.task.content;
    ref.read(provider.notifier).updateDraft(draft);
    _controller.text = draft;
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
      final saved = await ref
          .read(taskEditorViewModelProvider(widget.identity).notifier)
          .saveTitle(widget.task, _controller.text);
      if (!saved) {
        if (mounted) _showEditFailure(context);
        return false;
      }
      if (mounted) setState(() => _editing = false);
      return true;
    } catch (_) {
      if (mounted) _showEditFailure(context);
      return false;
    } finally {}
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

class _EditableTaskDescription extends ConsumerStatefulWidget {
  const _EditableTaskDescription({
    required this.identity,
    required this.task,
    super.key,
  });

  final Object identity;
  final TaskItem task;

  @override
  ConsumerState<_EditableTaskDescription> createState() =>
      _EditableTaskDescriptionState();
}

class _EditableTaskDescriptionState
    extends ConsumerState<_EditableTaskDescription> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool get _saving =>
      ref.read(taskEditorViewModelProvider(widget.identity)).saving;
  Future<bool>? _pendingSave;

  @override
  void initState() {
    super.initState();
    final state = ref.read(taskEditorViewModelProvider(widget.identity));
    _controller.text = state.dirty || state.failed
        ? state.draft
        : (widget.task.description ?? '');
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) {
        unawaited(_save());
      }
    });
  }

  @override
  void didUpdateWidget(covariant _EditableTaskDescription oldWidget) {
    super.didUpdateWidget(oldWidget);
    final state = ref.read(taskEditorViewModelProvider(widget.identity));
    if (_focusNode.hasFocus || state.saving || state.failed || state.dirty) {
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
    ref.watch(
      taskEditorViewModelProvider(
        widget.identity,
      ).select((state) => state.saving),
    );
    return TextField(
      key: const Key('task-comment-editor'),
      controller: _controller,
      enabled: !_saving,
      readOnly: !widget.task.canEdit,
      focusNode: _focusNode,
      minLines: 1,
      maxLines: null,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.7),
      textInputAction: TextInputAction.newline,
      decoration: InputDecoration(
        hintText: context.l10n.taskDescriptionHint,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: context.appColors.accent),
        ),
        filled: false,
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
      ),
      onChanged: (value) => ref
          .read(taskEditorViewModelProvider(widget.identity).notifier)
          .updateDraft(value),
    );
  }

  Future<bool> _save() {
    return _pendingSave ??= _persistDescription().whenComplete(
      () => _pendingSave = null,
    );
  }

  Future<bool> _persistDescription() async {
    try {
      final saved = await ref
          .read(taskEditorViewModelProvider(widget.identity).notifier)
          .saveDescription(widget.task, _controller.text);
      if (!saved) {
        if (mounted) _showEditFailure(context);
        return false;
      }
      return true;
    } catch (_) {
      if (mounted) _showEditFailure(context);
      return false;
    } finally {}
  }
}

class _SubtasksSection extends ConsumerStatefulWidget {
  const _SubtasksSection({required this.identity, required this.task});

  final Object identity;
  final TaskItem task;

  @override
  ConsumerState<_SubtasksSection> createState() => _SubtasksSectionState();
}

class _SubtasksSectionState extends ConsumerState<_SubtasksSection> {
  bool _adding = false;
  final _controller = TextEditingController();
  bool get _saving =>
      ref.read(taskEditorViewModelProvider(widget.identity)).saving;

  @override
  void initState() {
    super.initState();
    final state = ref.read(taskEditorViewModelProvider(widget.identity));
    _adding = state.dirty || state.failed;
    if (state.dirty || state.failed) {
      _controller.text = state.draft;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(
      taskEditorViewModelProvider(
        widget.identity,
      ).select((state) => state.saving),
    );
    final l10n = context.l10n;
    final subtasks = ref.watch(subtasksViewModelProvider(widget.task.id));
    final tasks = subtasks.tasks;
    final scope = 'details:${widget.task.id}';
    final expansion = ref.watch(taskBranchViewModelProvider(scope));
    final progressById = taskSubtaskProgressById(subtasks.allTasks);
    final rootProgress = progressById[widget.task.id];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.subtasks,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            if (rootProgress != null)
              TaskBranchProgressButton(
                taskId: widget.task.id,
                progress: rootProgress,
                expanded: expansion[widget.task.id] ?? true,
                onToggle: () => unawaited(
                  setTaskBranchExpanded(
                    context,
                    ref,
                    scope,
                    widget.task.id,
                    !(expansion[widget.task.id] ?? true),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: widget.task.canEdit
              ? () => setState(() => _adding = !_adding)
              : null,
          style: TextButton.styleFrom(
            foregroundColor: context.appColors.secondaryText,
            minimumSize: const Size(44, 44),
          ),
          icon: const Icon(LucideIcons.plus, size: 16),
          label: Text(l10n.addSubtask),
        ),
        Visibility(
          visible: _adding,
          maintainState: true,
          child: ShadInput(
            key: const Key('add-subtask-field'),
            controller: _controller,
            enabled: !_saving && widget.task.canEdit,
            textInputAction: TextInputAction.done,
            onChanged: (value) => ref
                .read(taskEditorViewModelProvider(widget.identity).notifier)
                .updateDraft(value),
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
                width: 44,
                height: 44,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        tasks.when(
          data: (items) {
            final children = withTaskBranchGroups(
              visibleTaskRows(
                subtasks.allTasks,
                [widget.task, ...items],
                expansion: expansion,
              ).where((row) => row.task.id != widget.task.id).toList(),
            );
            if (items.isEmpty) {
              return Text(
                l10n.noSubtasks,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              );
            }
            return Column(
              children: [
                for (var index = 0; index < children.length; index++) ...[
                  if (index > 0)
                    TaskListDivider(
                      previousDepth: children[index - 1].depth,
                      previousRow: children[index - 1],
                      nextDepth: children[index].depth,
                      nextRow: children[index],
                    ),
                  TaskListItem(
                    key: ValueKey(children[index].task.id),
                    task: children[index].task,
                    compactDetails: true,
                    depth: children[index].displayDepth,
                    hierarchy: children[index],
                    branchScope: scope,
                    subtaskProgress: progressById[children[index].task.id],
                  ),
                ],
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
    try {
      final saved = await ref
          .read(taskEditorViewModelProvider(widget.identity).notifier)
          .createSubtask(widget.task, input);
      if (!saved) throw StateError('Could not create subtask');
      _controller.clear();
      if (mounted) {
        await setTaskBranchExpanded(
          context,
          ref,
          'details:${widget.task.id}',
          widget.task.id,
          true,
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.taskCreateFailed)));
      }
    } finally {}
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
          enabled: schedule != null && widget.task.canEdit,
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
        SizedBox(
          width: double.infinity,
          child: ShadTabs<TaskRecurrenceUnit>(
            scrollable: true,
            key: const Key('task-recurrence-unit-select'),
            value: unit,
            gap: 0,
            tabs: [
              ShadTab(
                height: 44,
                value: TaskRecurrenceUnit.day,
                enabled: schedule != null && widget.task.canEdit,
                child: Text(l10n.recurrenceUnitDay),
              ),
              ShadTab(
                height: 44,
                value: TaskRecurrenceUnit.week,
                enabled: schedule != null && widget.task.canEdit,
                child: Text(l10n.recurrenceUnitWeek),
              ),
              ShadTab(
                height: 44,
                value: TaskRecurrenceUnit.month,
                enabled: schedule != null && widget.task.canEdit,
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
              height: 44,
              key: const Key('task-recurrence-save-button'),
              onPressed: schedule == null || !widget.task.canEdit
                  ? null
                  : () => _save(unit),
              enabled: !(schedule == null),
              leading: const Icon(LucideIcons.repeat),
              child: Text(l10n.commonSave),
            ),
            if (recurrence != null)
              ShadButton.ghost(
                height: 44,
                key: const Key('task-recurrence-clear-button'),
                onPressed: widget.task.canEdit ? _clear : null,
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
  AppDateTimePickerState picker,
) async {
  final now = ref.read(taskScheduleViewModelProvider(task)).now;
  final picked = await picker.pickDate(
    initialDate: task.schedule?.displayDate ?? now,
    firstDate: DateTime(now.year - 5),
    lastDate: DateTime(now.year + 10),
  );
  if (picked == null || !context.mounted) {
    return;
  }
  await _setTaskSchedule(ref, task, TaskSchedule.allDay(picked));
}

Future<void> _pickTimedSchedule(
  BuildContext context,
  WidgetRef ref,
  TaskItem task,
  AppDateTimePickerState picker,
) async {
  final now = ref.read(taskScheduleViewModelProvider(task)).now;
  final date = task.schedule?.displayDate ?? now;
  final currentStart = task.schedule?.isTimed ?? false
      ? task.schedule!.start!.toLocal()
      : DateTime(date.year, date.month, date.day, 9);
  final pickedStart = await picker.pickTime(
    initialTime: TimeOfDay.fromDateTime(currentStart),
    helpText: context.l10n.timelineStartHour,
  );
  if (pickedStart == null || !context.mounted) {
    return;
  }
  final start = DateTime(
    date.year,
    date.month,
    date.day,
    pickedStart.hour,
    pickedStart.minute,
  );
  final currentDuration = task.schedule?.duration ?? const Duration(hours: 1);
  final pickedEnd = await picker.pickTime(
    initialTime: TimeOfDay.fromDateTime(start.add(currentDuration)),
    helpText: context.l10n.timelineEndHour,
  );
  if (pickedEnd == null || !context.mounted) {
    return;
  }
  var end = DateTime(
    date.year,
    date.month,
    date.day,
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
  await ref
      .read(taskScheduleViewModelProvider(task).notifier)
      .setSchedule(schedule, preserveRecurrence: preserveRecurrence);
}

Future<void> _clearTaskSchedule(WidgetRef ref, TaskItem task) async {
  await ref.read(taskScheduleViewModelProvider(task).notifier).clear();
}

DateTime _today(WidgetRef ref, TaskItem task) {
  final now = ref.read(taskScheduleViewModelProvider(task)).now;
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
  const _FocusHistory({required this.task});

  final TaskItem task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final viewState = ref.watch(taskHistoryViewModelProvider(task));
    final entries = viewState.entries;
    final scope = viewState.scope;
    if (entries.isEmpty) {
      return Text(l10n.noFocusIntervals);
    }
    return Column(
      children: [
        for (final entry in entries.take(20))
          Padding(
            key: Key(entry.key),
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  entry.type == 'work' ? LucideIcons.timer : LucideIcons.coffee,
                  size: 16,
                  color: context.appColors.secondaryText,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${focusIntervalTypeLabel(l10n, entry.type)} · ${focusIntervalStatusLabel(l10n, entry.status)}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        entry.authorId != null && scope != null
                            ? '${collaborationMemberLabel(l10n, scope, entry.authorId!)} · ${formatLocalDate(context, entry.startedAt.toLocal())}'
                            : formatLocalDate(
                                context,
                                entry.startedAt.toLocal(),
                              ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    formatFocusTime(context, entry.seconds),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
