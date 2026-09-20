import 'package:pomodoist/ui/tasks/widgets/project_localizations.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pomodoist/ui/core/themes/app_motion.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' as intl;

import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/tasks/view_models/task_selection_view_model.dart';
import 'package:pomodoist/ui/core/widgets/action_feedback.dart';
import 'package:pomodoist/domain/models/planning/quick_add_parser.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/ui/tasks/widgets/task_completion_feedback.dart';
import 'package:pomodoist/domain/use_cases/tasks/task_scheduling.dart';
import 'package:pomodoist/ui/tasks/widgets/task_motion.dart';

/// View-side adapter: owns dialogs and widget context, not selection state.
class TaskSelectionController {
  TaskSelectionController({
    required TaskSelectionViewModel viewModel,
    required Future<void> Function(BuildContext) showDue,
    required Future<void> Function(BuildContext) showProject,
    required Future<void> Function(BuildContext) showLabels,
    required Future<void> Function(BuildContext) showPriority,
    required Future<void> Function(BuildContext) showMore,
    required Future<void> Function(BuildContext) duplicate,
    required Future<void> Function(BuildContext) delete,
  }) : _viewModel = viewModel,
       _showDue = showDue,
       _showProject = showProject,
       _showLabels = showLabels,
       _showPriority = showPriority,
       _showMore = showMore,
       _duplicate = duplicate,
       _delete = delete;

  final TaskSelectionViewModel _viewModel;
  final Future<void> Function(BuildContext) _showDue;
  final Future<void> Function(BuildContext) _showProject;
  final Future<void> Function(BuildContext) _showLabels;
  final Future<void> Function(BuildContext) _showPriority;
  final Future<void> Function(BuildContext) _showMore;
  final Future<void> Function(BuildContext) _duplicate;
  final Future<void> Function(BuildContext) _delete;

  bool get active => _viewModel.active;
  bool get pending => _viewModel.pending;
  Set<String> get selectedIds => _viewModel.selectedIds;
  int get selectedCount => _viewModel.selectedIds.length;
  bool get hasSelection => _viewModel.hasSelection;
  Iterable<TaskItem> get visibleTasks => _viewModel.visibleTasks;
  bool get allVisibleSelected => _viewModel.allVisibleSelected;
  Iterable<TaskItem> get selectedTasks => _viewModel.selectedTasks;

  bool isSelected(String id) => _viewModel.isSelected(id);

  void updateVisible(Iterable<TaskItem> tasks) =>
      _viewModel.updateVisible(tasks);
  void begin(String id) => _viewModel.begin(id);
  void toggle(String id) => _viewModel.toggle(id);
  void toggleAll() => _viewModel.toggleAll();
  void retainVisible(Iterable<String> ids) => _viewModel.retainVisible(ids);
  void close() => _viewModel.clear();

  Future<void> showDue(BuildContext context) => _showDue(context);
  Future<void> showProject(BuildContext context) => _showProject(context);
  Future<void> showLabels(BuildContext context) => _showLabels(context);
  Future<void> showPriority(BuildContext context) => _showPriority(context);
  Future<void> showMore(BuildContext context) => _showMore(context);
  Future<void> duplicate(BuildContext context) => _duplicate(context);
  Future<void> delete(BuildContext context) => _delete(context);
}

class TaskSelectionScope extends InheritedWidget {
  const TaskSelectionScope({
    required this.controller,
    required this.active,
    required this.selectedIds,
    required super.child,
    super.key,
  });

  final TaskSelectionController controller;
  final bool active;
  final Set<String> selectedIds;

  static TaskSelectionController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<TaskSelectionScope>()
      ?.controller;

  @override
  bool updateShouldNotify(TaskSelectionScope oldWidget) =>
      oldWidget.active != active || oldWidget.selectedIds != selectedIds;
}

class TaskSelectionRegion extends ConsumerStatefulWidget {
  const TaskSelectionRegion({
    required this.visibleTasks,
    required this.child,
    this.scopeKey,
    this.shrinkWrap = false,
    super.key,
  });

  final Iterable<TaskItem> visibleTasks;
  final Object? scopeKey;
  final bool shrinkWrap;
  final Widget child;

  @override
  ConsumerState<TaskSelectionRegion> createState() =>
      _TaskSelectionRegionState();
}

class _TaskSelectionRegionState extends ConsumerState<TaskSelectionRegion> {
  final _identity = Object();
  bool _visibleSyncScheduled = false;
  TaskSelectionViewModel get _viewModel =>
      ref.read(taskSelectionViewModelProvider(_identity).notifier);

  late final TaskSelectionController _controller = TaskSelectionController(
    viewModel: _viewModel,
    showDue: _showDue,
    showProject: _showProject,
    showLabels: _showLabels,
    showPriority: _showPriority,
    showMore: _showMore,
    duplicate: _duplicate,
    delete: _delete,
  );

  @override
  void initState() {
    super.initState();
    _scheduleVisibleSync();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  void _scheduleVisibleSync() {
    if (_visibleSyncScheduled) return;
    _visibleSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _visibleSyncScheduled = false;
      if (!mounted) return;
      _viewModel.updateVisible(widget.visibleTasks);
    });
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (!_controller.active ||
        event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape ||
        !(ModalRoute.of(context)?.isCurrent ?? false)) {
      return false;
    }
    _controller.close();
    return true;
  }

  @override
  void didUpdateWidget(covariant TaskSelectionRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scopeKey != widget.scopeKey) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _viewModel.clear();
      });
    }
    _scheduleVisibleSync();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selection = ref.watch(taskSelectionViewModelProvider(_identity));
    return PopScope(
      canPop: !_controller.active,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _controller.close();
      },
      child: Focus(
        autofocus: !widget.shrinkWrap,
        child: CallbackShortcuts(
          bindings: {
            if (_controller.active)
              const SingleActivator(LogicalKeyboardKey.escape):
                  _controller.close,
          },
          child: TaskSelectionScope(
            controller: _controller,
            active: selection.active,
            selectedIds: selection.selectedIds,
            child: Column(
              mainAxisSize: widget.shrinkWrap
                  ? MainAxisSize.min
                  : MainAxisSize.max,
              children: [
                if (_controller.active) _selectionHeader(context),
                if (widget.shrinkWrap)
                  widget.child
                else
                  Expanded(child: widget.child),
                if (_controller.active) _selectionBar(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _selectionHeader(BuildContext context) {
    final l10n = context.l10n;
    return Material(
      key: const Key('task-selection-header'),
      elevation: 1,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              IconButton(
                tooltip: l10n.commonClose,
                onPressed: _controller.close,
                icon: const Icon(LucideIcons.x),
              ),
              Expanded(
                child: Text(
                  l10n.taskSelectedCount(_controller.selectedCount),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton(
                key: const Key('task-selection-toggle-all'),
                onPressed: _controller.toggleAll,
                child: Text(
                  _controller.allVisibleSelected
                      ? l10n.taskDeselectAll
                      : l10n.taskSelectAll,
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _selectionBar(BuildContext context) {
    final l10n = context.l10n;
    return Material(
      key: const Key('task-selection-bottom-bar'),
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            _barAction(LucideIcons.calendar, l10n.taskDue, _showDue),
            _barAction(LucideIcons.folder, l10n.taskProject, _showProject),
            _barAction(LucideIcons.tag, l10n.taskLabels, _showLabels),
            _barAction(LucideIcons.flag, l10n.taskPriority, _showPriority),
            _barAction(LucideIcons.ellipsis, l10n.taskMore, _showMore),
          ],
        ),
      ),
    );
  }

  Widget _barAction(
    IconData icon,
    String label,
    Future<void> Function(BuildContext) action,
  ) {
    return Expanded(
      child: TextButton(
        onPressed: _controller.hasSelection && !_controller.pending
            ? () => action(context)
            : null,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 21),
            const SizedBox(height: 2),
            Text(label, maxLines: 1, style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Future<void> _showDue(BuildContext context) async {
    if (!_controller.hasSelection) return;
    final result = await showTaskDuePanel(context, ref);
    if (result == null || !mounted) return;
    final failed = await _viewModel.schedule(_controller.selectedTasks, result);
    if (mounted) _finishNonDestructive(failed);
  }

  Future<void> _showProject(BuildContext context) async {
    if (!_controller.hasSelection) return;
    final projects = ref
        .read(taskSelectionViewModelProvider(_identity))
        .projects;
    final projectId = await _showChoice<String>(
      context,
      title: context.l10n.taskProject,
      choices: [
        for (final project in projects)
          (project.id, project.displayName(context.l10n)),
      ],
    );
    if (projectId == null || !mounted) return;
    final failed = await _viewModel.setProject(
      _controller.selectedTasks,
      projectId,
    );
    if (mounted) _finishNonDestructive(failed);
  }

  Future<void> _showLabels(BuildContext context) async {
    if (!_controller.hasSelection) return;
    final labels = ref.read(taskSelectionViewModelProvider(_identity)).labels;
    final selected = await showTaskLabelPanel(context, labels);
    if (selected == null || selected.isEmpty || !mounted) return;
    final failed = await _viewModel.setLabels(
      _controller.selectedIds,
      selected,
    );
    if (mounted) _finishNonDestructive(failed);
  }

  Future<void> _showPriority(BuildContext context) async {
    if (!_controller.hasSelection) return;
    final priority = await _showChoice<int>(
      context,
      title: context.l10n.taskPriority,
      choices: [
        for (final value in [1, 2, 3, 4]) (value, context.l10n.priority(value)),
      ],
    );
    if (priority == null || !mounted) return;
    final failed = await _viewModel.setPriority(
      _controller.selectedIds,
      priority,
    );
    if (mounted) _finishNonDestructive(failed);
  }

  Future<void> _showMore(BuildContext context) async {
    if (!_controller.hasSelection) return;
    final reopen = _controller.selectedTasks.every((task) => task.isCompleted);
    final action = await _showChoice<_MoreAction>(
      context,
      title: context.l10n.taskMore,
      choices: [
        (
          _MoreAction.complete,
          reopen
              ? context.l10n.taskReopenSelected
              : context.l10n.taskCompleteSelected,
        ),
        (_MoreAction.duplicate, context.l10n.taskDuplicate),
        (_MoreAction.delete, context.l10n.commonDelete),
      ],
    );
    if (action == null || !mounted) return;
    switch (action) {
      case _MoreAction.complete:
        await _completeOrReopen(reopen: reopen);
      case _MoreAction.duplicate:
        await _duplicate(this.context);
      case _MoreAction.delete:
        await _delete(this.context);
    }
  }

  Future<void> _completeOrReopen({required bool reopen}) async {
    final l10n = context.l10n;
    final motion = TaskMotionScope.maybeOf(context);
    final viewModel = _viewModel;
    final result = await viewModel.setCompleted(
      _controller.selectedIds,
      completed: !reopen,
    );
    final succeeded = result.succeeded;
    final failed = result.failed;
    final changedTasks = result.tasks;
    if (!mounted) return;
    if (reopen) {
      motion?.reopened(changedTasks);
    } else {
      motion?.completed(changedTasks);
    }
    if (failed.isEmpty) {
      _controller.close();
    } else {
      _controller.retainVisible(failed);
      _showFailures(failed.length);
    }
    if (succeeded.isEmpty) return;
    showActionFeedback(
      context,
      message: reopen ? l10n.taskReopened : l10n.taskCompleted,
      icon: reopen ? LucideIcons.undo2 : LucideIcons.circleCheck,
      duration: taskCompletionUndoFeedbackDuration,
      showCloseIcon: true,
      compact: true,
      action: SnackBarAction(
        label: l10n.commonUndo,
        onPressed: () => unawaited(() async {
          final result = await viewModel.undoCompleted(
            succeeded,
            completed: reopen,
          );
          final undone = result.tasks;
          final undoFailures = result.failed.length;
          if (mounted) {
            if (reopen) {
              motion?.completed(undone);
            } else {
              motion?.reopened(undone);
            }
          }
          if (undone.isNotEmpty) {
            await playHaptic(AppHapticCue.light);
          }
          if (mounted && undoFailures > 0) {
            _showFailures(undoFailures);
          }
        }()),
      ),
    );
  }

  Future<void> _duplicate(BuildContext context) async {
    if (!_controller.hasSelection) return;
    final includeSubtasks = await _showChoice<bool>(
      context,
      title: context.l10n.taskDuplicateTitle,
      choices: [
        (false, context.l10n.taskDuplicateSelectedOnly),
        (true, context.l10n.taskDuplicateWithSubtasks),
      ],
    );
    if (includeSubtasks == null || !mounted) return;
    try {
      final createdIds = await _viewModel.duplicate(
        _controller.selectedIds,
        includeSubtasks: includeSubtasks,
      );
      if (!mounted) return;
      TaskMotionScope.maybeOf(this.context)?.created(createdIds.toSet());
      _controller.close();
      await playHaptic(AppHapticCue.light);
    } catch (_) {
      _showFailures(_controller.selectedCount);
    }
  }

  Future<void> _delete(BuildContext context) async {
    if (!_controller.hasSelection) return;
    final hasRecurring = _controller.selectedTasks.any(
      (task) => task.schedule?.isRecurringOccurrence ?? false,
    );
    final includeFollowing = await _confirmDelete(context, hasRecurring);
    if (includeFollowing == null || !mounted) return;
    final viewModel = _viewModel;
    final result = await viewModel.delete(
      _controller.selectedTasks,
      includeFollowing: includeFollowing,
    );
    final failed = result.failed;
    final batches = result.batches;
    if (!mounted) return;
    final motion = TaskMotionScope.maybeOf(this.context);
    final deletedIds = batches.expand((batch) => batch.taskIds).toSet();
    final deletedTasks = _controller.visibleTasks
        .where((task) => deletedIds.contains(task.id))
        .toList();
    motion?.deleted(deletedTasks);
    if (failed.isEmpty) {
      _controller.close();
    } else {
      _controller.retainVisible(failed);
      _showFailures(failed.length);
    }
    if (batches.isEmpty) {
      return;
    }
    showActionFeedback(
      this.context,
      message: this.context.l10n.taskDeleted,
      icon: LucideIcons.trash2,
      duration: const Duration(seconds: 7),
      showCloseIcon: true,
      compact: true,
      action: SnackBarAction(
        label: this.context.l10n.commonUndo,
        onPressed: () => unawaited(() async {
          final result = await viewModel.restore(batches);
          final restoredIds = result.ids;
          final restoreFailures = result.failures;
          if (restoredIds.isNotEmpty) {
            await playHaptic(AppHapticCue.light);
            if (mounted) {
              motion?.created(restoredIds);
            }
          }
          if (mounted && restoreFailures > 0) {
            _showFailures(restoreFailures);
          }
        }()),
      ),
    );
  }

  void _finishNonDestructive(List<String> failed) {
    if (failed.isEmpty) {
      _controller.close();
      return;
    }
    _controller.retainVisible(failed);
    _showFailures(failed.length);
  }

  void _showFailures(int count) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.taskActionFailedCount(count))),
    );
  }

  Future<T?> _showChoice<T>(
    BuildContext context, {
    required String title,
    required List<(T, String)> choices,
  }) {
    return showAdaptiveTaskPanel<T>(
      context,
      builder: (panelContext) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(title, style: Theme.of(context).textTheme.titleLarge),
          ),
          for (final choice in choices)
            ListTile(
              title: Text(choice.$2),
              onTap: () => Navigator.of(panelContext).pop(choice.$1),
            ),
        ],
      ),
    );
  }

  Future<bool?> _confirmDelete(BuildContext context, bool recurring) {
    return showDialog<bool>(
      context: context,
      animationStyle: AnimationStyle(
        duration: AppMotion.duration(context, AppMotion.popup),
        reverseDuration: AppMotion.duration(context, AppMotion.popup),
        curve: AppMotion.curve,
      ),
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.taskDeleteSelectedTitle),
        content: Text(context.l10n.taskDeleteSelectedMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(context.l10n.commonCancel),
          ),
          if (recurring)
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(context.l10n.recurringDeleteThis),
            ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(recurring),
            child: Text(
              recurring
                  ? context.l10n.recurringDeleteThisAndFollowing
                  : context.l10n.commonDelete,
            ),
          ),
        ],
      ),
    );
  }
}

enum _MoreAction { complete, duplicate, delete }

Future<TaskDueResult?> showTaskDuePanel(BuildContext context, WidgetRef ref) {
  return showAdaptiveTaskPanel<TaskDueResult>(
    context,
    builder: (panelContext) => _TaskDuePanel(
      now: ref.read(taskDuePanelViewModelProvider),
      onResult: (result) => Navigator.of(panelContext).pop(result),
    ),
  );
}

Future<List<String>?> showTaskLabelPanel(
  BuildContext context,
  List<LabelItem> labels,
) {
  return showAdaptiveTaskPanel<List<String>>(
    context,
    builder: (panelContext) => _TaskLabelPanel(
      labels: labels,
      onDone: (names) => Navigator.of(panelContext).pop(names),
    ),
  );
}

Future<T?> showAdaptiveTaskPanel<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  if (_usesTouchPanels) {
    return showModalBottomSheet<T>(
      context: context,
      useRootNavigator: true,
      sheetAnimationStyle: AnimationStyle(
        duration: AppMotion.duration(context, AppMotion.panel),
        reverseDuration: AppMotion.duration(context, AppMotion.panel),
      ),
      isScrollControlled: true,
      useSafeArea: true,
      builder: builder,
    );
  }
  return showDialog<T>(
    context: context,
    useRootNavigator: true,
    animationStyle: AnimationStyle(
      duration: AppMotion.duration(context, AppMotion.popup),
      reverseDuration: AppMotion.duration(context, AppMotion.popup),
      curve: AppMotion.curve,
    ),
    builder: (dialogContext) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 680),
        child: builder(dialogContext),
      ),
    ),
  );
}

bool get _usesTouchPanels =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

class _TaskDuePanel extends StatefulWidget {
  const _TaskDuePanel({required this.now, required this.onResult});

  final DateTime now;
  final ValueChanged<TaskDueResult> onResult;

  @override
  State<_TaskDuePanel> createState() => _TaskDuePanelState();
}

class _TaskDuePanelState extends State<_TaskDuePanel> {
  final _controller = TextEditingController();
  DateTime? _selectedDate;
  String? _error;

  DateTime get _today =>
      DateTime(widget.now.year, widget.now.month, widget.now.day);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final presets = [
      (LucideIcons.calendarCheck, l10n.today, _today),
      (LucideIcons.sun, l10n.tomorrow, _today.add(const Duration(days: 1))),
      (LucideIcons.armchair, l10n.taskWeekend, taskWeekendPresetDate(_today)),
      (
        LucideIcons.calendarSync,
        l10n.taskNextWeek,
        taskNextWeekPresetDate(_today),
      ),
    ];
    final height = (MediaQuery.sizeOf(context).height * 0.82)
        .clamp(420.0, 680.0)
        .toDouble();
    return SizedBox(
      height: height,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              children: [
                Text(
                  l10n.taskDue,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('task-due-input'),
                  controller: _controller,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: l10n.taskEnterDue,
                    errorText: _error,
                    prefixIcon: const Icon(LucideIcons.clock),
                  ),
                  onSubmitted: (_) => _applyDone(),
                ),
                const SizedBox(height: 8),
                for (final preset in presets)
                  ListTile(
                    leading: Icon(preset.$1),
                    title: Text(preset.$2),
                    trailing: Text(
                      intl.DateFormat.EEEE(
                        Localizations.localeOf(context).toLanguageTag(),
                      ).format(preset.$3),
                    ),
                    onTap: () => _applyPreset(preset.$3),
                  ),
                const Divider(),
                CalendarDatePicker(
                  initialDate: _selectedDate ?? _today,
                  firstDate: DateTime(_today.year - 2),
                  lastDate: DateTime(_today.year + 10),
                  onDateChanged: (date) => setState(() => _selectedDate = date),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                TextButton(
                  onPressed: () => widget.onResult(const TaskDueResult.clear()),
                  child: Text(l10n.taskClearDue),
                ),
                const Spacer(),
                FilledButton(
                  key: const Key('task-due-done'),
                  onPressed: _applyDone,
                  child: Text(l10n.commonDone),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _applyPreset(DateTime date) {
    final parsed = _parse(defaultDate: date);
    if (parsed == null) return;
    widget.onResult(TaskDueResult.schedule(_onDate(parsed, date)));
  }

  void _applyDone() {
    final fallback = _selectedDate ?? _today;
    final parsed = _parse(defaultDate: fallback);
    if (parsed == null) return;
    widget.onResult(TaskDueResult.schedule(parsed));
  }

  TaskSchedule? _parse({required DateTime defaultDate}) {
    final input = _controller.text.trim();
    if (input.isEmpty) {
      setState(() => _error = null);
      return TaskSchedule.allDay(defaultDate);
    }
    final parsed = const QuickAddParser().parse(
      input,
      now: widget.now,
      defaultDate: defaultDate,
    );
    final valid =
        parsed.schedule != null &&
        parsed.content.isEmpty &&
        parsed.project == null &&
        parsed.section == null &&
        parsed.labels.isEmpty &&
        parsed.priority == null &&
        parsed.estimatedFocusIntervals == null;
    setState(() => _error = valid ? null : context.l10n.taskInvalidDue);
    return valid ? parsed.schedule : null;
  }

  TaskSchedule _onDate(TaskSchedule schedule, DateTime date) {
    if (schedule.isAllDay) return TaskSchedule.allDay(date);
    final localStart = schedule.start!.toLocal();
    final start = DateTime(
      date.year,
      date.month,
      date.day,
      localStart.hour,
      localStart.minute,
    );
    return TaskSchedule.timed(
      start: start,
      end: start.add(schedule.duration!),
      timeZone: schedule.timeZone,
    );
  }
}

class _TaskLabelPanel extends StatefulWidget {
  const _TaskLabelPanel({required this.labels, required this.onDone});

  final List<LabelItem> labels;
  final ValueChanged<List<String>> onDone;

  @override
  State<_TaskLabelPanel> createState() => _TaskLabelPanelState();
}

class _TaskLabelPanelState extends State<_TaskLabelPanel> {
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            context.l10n.taskLabels,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        for (final label in widget.labels)
          CheckboxListTile(
            value: _selected.contains(label.name),
            title: Text(label.name),
            onChanged: (_) => setState(() {
              if (!_selected.remove(label.name)) _selected.add(label.name);
            }),
          ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: FilledButton(
            onPressed: () => widget.onDone(_selected.toList()),
            child: Text(context.l10n.commonDone),
          ),
        ),
      ],
    );
  }
}

DateTime taskWeekendPresetDate(DateTime today) =>
    today.add(Duration(days: (DateTime.saturday - today.weekday) % 7));

DateTime taskNextWeekPresetDate(DateTime today) =>
    today.add(Duration(days: 8 - today.weekday));
