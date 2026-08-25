import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' as intl;

import '../../../../app/app_l10n.dart';
import '../../../../app/providers.dart';
import '../../../../app/widgets/action_feedback.dart';
import '../../../planning/domain/quick_add_parser.dart';
import '../../domain/task_models.dart';
import '../task_completion_feedback.dart';

class TaskSelectionController extends ChangeNotifier {
  TaskSelectionController({
    required Future<void> Function(BuildContext) showDue,
    required Future<void> Function(BuildContext) showProject,
    required Future<void> Function(BuildContext) showLabels,
    required Future<void> Function(BuildContext) showPriority,
    required Future<void> Function(BuildContext) showMore,
    required Future<void> Function(BuildContext) duplicate,
    required Future<void> Function(BuildContext) delete,
  }) : _showDue = showDue,
       _showProject = showProject,
       _showLabels = showLabels,
       _showPriority = showPriority,
       _showMore = showMore,
       _duplicate = duplicate,
       _delete = delete;

  final Future<void> Function(BuildContext) _showDue;
  final Future<void> Function(BuildContext) _showProject;
  final Future<void> Function(BuildContext) _showLabels;
  final Future<void> Function(BuildContext) _showPriority;
  final Future<void> Function(BuildContext) _showMore;
  final Future<void> Function(BuildContext) _duplicate;
  final Future<void> Function(BuildContext) _delete;
  Map<String, TaskItem> _visibleTasks = const {};
  final Set<String> _selectedIds = {};
  bool _active = false;

  bool get active => _active;
  Set<String> get selectedIds => Set.unmodifiable(_selectedIds);
  int get selectedCount => _selectedIds.length;
  bool get hasSelection => _selectedIds.isNotEmpty;
  bool get allVisibleSelected =>
      _visibleTasks.isNotEmpty &&
      _visibleTasks.keys.every(_selectedIds.contains);
  Iterable<TaskItem> get selectedTasks sync* {
    for (final id in _selectedIds) {
      final task = _visibleTasks[id];
      if (task != null) yield task;
    }
  }

  bool isSelected(String id) => _selectedIds.contains(id);

  void updateVisible(Iterable<TaskItem> tasks) {
    _visibleTasks = {for (final task in tasks) task.id: task};
    if (!_active || _selectedIds.isEmpty) return;
    final hadSelection = _selectedIds.isNotEmpty;
    _selectedIds.removeWhere((id) => !_visibleTasks.containsKey(id));
    if (hadSelection && _selectedIds.isEmpty) {
      _active = false;
    }
    notifyListeners();
  }

  void begin(String id) {
    _active = true;
    _selectedIds
      ..clear()
      ..add(id);
    notifyListeners();
  }

  void toggle(String id) {
    if (!_active) return;
    if (!_selectedIds.remove(id)) _selectedIds.add(id);
    notifyListeners();
  }

  void toggleAll() {
    if (allVisibleSelected) {
      _selectedIds.clear();
    } else {
      _selectedIds.addAll(_visibleTasks.keys);
    }
    notifyListeners();
  }

  void retainOnly(Iterable<String> ids) {
    _selectedIds
      ..clear()
      ..addAll(ids.where(_visibleTasks.containsKey));
    _active = _selectedIds.isNotEmpty;
    notifyListeners();
  }

  void close() {
    if (!_active && _selectedIds.isEmpty) return;
    _active = false;
    _selectedIds.clear();
    notifyListeners();
  }

  Future<void> showDue(BuildContext context) => _showDue(context);
  Future<void> showProject(BuildContext context) => _showProject(context);
  Future<void> showLabels(BuildContext context) => _showLabels(context);
  Future<void> showPriority(BuildContext context) => _showPriority(context);
  Future<void> showMore(BuildContext context) => _showMore(context);
  Future<void> duplicate(BuildContext context) => _duplicate(context);
  Future<void> delete(BuildContext context) => _delete(context);
}

class TaskSelectionScope extends InheritedNotifier<TaskSelectionController> {
  const TaskSelectionScope({
    required TaskSelectionController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static TaskSelectionController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<TaskSelectionScope>()
      ?.notifier;
}

class TaskSelectionRegion extends ConsumerStatefulWidget {
  const TaskSelectionRegion({
    required this.visibleTasks,
    required this.child,
    this.scopeKey,
    super.key,
  });

  final Iterable<TaskItem> visibleTasks;
  final Object? scopeKey;
  final Widget child;

  @override
  ConsumerState<TaskSelectionRegion> createState() =>
      _TaskSelectionRegionState();
}

class _TaskSelectionRegionState extends ConsumerState<TaskSelectionRegion> {
  late final TaskSelectionController _controller = TaskSelectionController(
    showDue: _showDue,
    showProject: _showProject,
    showLabels: _showLabels,
    showPriority: _showPriority,
    showMore: _showMore,
    duplicate: _duplicate,
    delete: _delete,
  )..updateVisible(widget.visibleTasks);

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
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
    if (oldWidget.scopeKey != widget.scopeKey) _controller.close();
    _controller.updateVisible(widget.visibleTasks);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => PopScope(
        canPop: !_controller.active,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _controller.close();
        },
        child: Focus(
          autofocus: true,
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.escape):
                  _controller.close,
            },
            child: TaskSelectionScope(
              controller: _controller,
              child: Column(
                children: [
                  if (_controller.active) _selectionHeader(context),
                  Expanded(child: widget.child),
                  if (_controller.active) _selectionBar(context),
                ],
              ),
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
                icon: const Icon(Icons.close),
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
            _barAction(Icons.event_outlined, l10n.taskDue, _showDue),
            _barAction(Icons.folder_outlined, l10n.taskProject, _showProject),
            _barAction(Icons.label_outline, l10n.taskLabels, _showLabels),
            _barAction(Icons.flag_outlined, l10n.taskPriority, _showPriority),
            _barAction(Icons.more_horiz, l10n.taskMore, _showMore),
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
        onPressed: _controller.hasSelection ? () => action(context) : null,
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
    final tasks = _controller.selectedTasks.toList();
    final failed = <String>[];
    var successCount = 0;
    for (final task in tasks) {
      try {
        await ref
            .read(taskRepositoryProvider)
            .updateTask(
              task.id,
              result.clear
                  ? const UpdateTaskPatch(clearSchedule: true)
                  : UpdateTaskPatch(
                      schedule: _preserveRecurrence(
                        result.schedule!,
                        task.schedule,
                      ),
                    ),
            );
        successCount++;
      } catch (_) {
        failed.add(task.id);
      }
    }
    if (successCount > 0) {
      unawaited(
        ref
            .read(googleCalendarSyncControllerProvider)
            .syncNow()
            .catchError((_) {}),
      );
    }
    _finishNonDestructive(failed);
  }

  Future<void> _showProject(BuildContext context) async {
    if (!_controller.hasSelection) return;
    final projects = ref.read(projectsProvider).value ?? const <ProjectItem>[];
    final projectId = await _showChoice<String>(
      context,
      title: context.l10n.taskProject,
      choices: [for (final project in projects) (project.id, project.name)],
    );
    if (projectId == null || !mounted) return;
    final tasksById = {
      for (final task in _controller.selectedTasks) task.id: task,
    };
    final selectedIds = _controller.selectedIds;
    await _runUpdates((id) {
      final task = tasksById[id]!;
      final projectChanged = task.projectId != projectId;
      return ref
          .read(taskRepositoryProvider)
          .moveTask(
            id,
            projectId: projectId,
            clearSectionId: projectChanged,
            clearParentId:
                projectChanged &&
                task.parentId != null &&
                !selectedIds.contains(task.parentId),
          );
    });
  }

  Future<void> _showLabels(BuildContext context) async {
    if (!_controller.hasSelection) return;
    final labels = ref.read(labelsProvider).value ?? const <LabelItem>[];
    final selected = await showTaskLabelPanel(context, labels);
    if (selected == null || selected.isEmpty || !mounted) return;
    await _runUpdates(
      (id) => ref
          .read(taskRepositoryProvider)
          .updateTask(id, UpdateTaskPatch(labelNames: selected)),
    );
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
    await _runUpdates(
      (id) => ref
          .read(taskRepositoryProvider)
          .updateTask(id, UpdateTaskPatch(priority: priority)),
    );
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
    final ids = _controller.selectedIds.toList();
    final succeeded = <String>[];
    final failed = <String>[];
    for (final id in ids) {
      try {
        if (reopen) {
          await ref.read(taskRepositoryProvider).uncompleteTask(id);
        } else {
          await ref.read(taskRepositoryProvider).completeTask(id);
        }
        succeeded.add(id);
      } catch (_) {
        failed.add(id);
      }
    }
    if (!mounted) return;
    if (failed.isEmpty) {
      _controller.close();
    } else {
      _controller.retainOnly(failed);
      _showFailures(failed.length);
    }
    if (succeeded.isEmpty) return;
    showActionFeedback(
      context,
      message: reopen ? context.l10n.taskReopened : context.l10n.taskCompleted,
      icon: reopen ? Icons.undo : Icons.check_circle_outline,
      duration: taskCompletionUndoFeedbackDuration,
      showCloseIcon: true,
      compact: true,
      action: SnackBarAction(
        label: context.l10n.commonUndo,
        onPressed: () {
          for (final id in succeeded) {
            unawaited(
              reopen
                  ? ref.read(taskRepositoryProvider).completeTask(id)
                  : ref.read(taskRepositoryProvider).uncompleteTask(id),
            );
          }
        },
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
      await ref
          .read(taskRepositoryProvider)
          .duplicateTasks(
            _controller.selectedIds,
            includeSubtasks: includeSubtasks,
          );
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
    final failed = <String>[];
    for (final task in _controller.selectedTasks.toList()) {
      try {
        if (task.schedule?.isRecurringOccurrence ?? false) {
          await ref
              .read(taskRepositoryProvider)
              .deleteRecurringOccurrence(
                task.id,
                includeFollowing: includeFollowing,
              );
        } else {
          await ref.read(taskRepositoryProvider).deleteTask(task.id);
        }
      } catch (_) {
        failed.add(task.id);
      }
    }
    if (!mounted) return;
    if (failed.isEmpty) {
      _controller.close();
    } else {
      _controller.retainOnly(failed);
      _showFailures(failed.length);
    }
  }

  Future<void> _runUpdates(Future<void> Function(String id) update) async {
    final failed = <String>[];
    for (final id in _controller.selectedIds.toList()) {
      try {
        await update(id);
      } catch (_) {
        failed.add(id);
      }
    }
    if (mounted) _finishNonDestructive(failed);
  }

  void _finishNonDestructive(List<String> failed) {
    if (failed.isEmpty) return;
    _controller.retainOnly(failed);
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

class TaskDueResult {
  const TaskDueResult.schedule(this.schedule) : clear = false;
  const TaskDueResult.clear() : schedule = null, clear = true;

  final TaskSchedule? schedule;
  final bool clear;
}

Future<TaskDueResult?> showTaskDuePanel(BuildContext context, WidgetRef ref) {
  return showAdaptiveTaskPanel<TaskDueResult>(
    context,
    builder: (panelContext) => _TaskDuePanel(
      now: ref.read(clockProvider).now().toLocal(),
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
      isScrollControlled: true,
      useSafeArea: true,
      builder: builder,
    );
  }
  return showDialog<T>(
    context: context,
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
      (Icons.today_outlined, l10n.today, _today),
      (
        Icons.wb_sunny_outlined,
        l10n.tomorrow,
        _today.add(const Duration(days: 1)),
      ),
      (Icons.weekend_outlined, l10n.taskWeekend, taskWeekendPresetDate(_today)),
      (
        Icons.event_repeat_outlined,
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
                    prefixIcon: const Icon(Icons.schedule_outlined),
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

TaskSchedule _preserveRecurrence(
  TaskSchedule schedule,
  TaskSchedule? existing,
) {
  final recurrence = existing?.recurrence;
  if (recurrence != null) return schedule.withRecurrence(recurrence);
  return schedule.withRecurrenceSeriesId(existing?.recurrenceSeriesId);
}

DateTime taskWeekendPresetDate(DateTime today) =>
    today.add(Duration(days: (DateTime.saturday - today.weekday) % 7));

DateTime taskNextWeekPresetDate(DateTime today) =>
    today.add(Duration(days: 8 - today.weekday));
