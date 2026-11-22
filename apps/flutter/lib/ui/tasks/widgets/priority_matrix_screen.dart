import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons;

import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/widgets/compact_shell_layout.dart';
import 'package:pomodoist/ui/core/themes/app_motion.dart';
import 'package:pomodoist/ui/tasks/view_models/priority_matrix_view_model.dart';
import 'package:pomodoist/ui/tasks/view_models/task_branch_rows.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/core/widgets/action_feedback.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/ui/tasks/widgets/quick_add_bar.dart';
import 'package:pomodoist/ui/tasks/widgets/quick_add_dialog.dart';
import 'package:pomodoist/ui/tasks/widgets/task_list_item.dart';
import 'package:pomodoist/ui/tasks/widgets/task_motion.dart';
import 'package:pomodoist/ui/tasks/widgets/task_selection_region.dart';

class PriorityMatrixScreen extends ConsumerStatefulWidget {
  const PriorityMatrixScreen({super.key});

  @override
  ConsumerState<PriorityMatrixScreen> createState() =>
      _PriorityMatrixScreenState();
}

class _PriorityMatrixScreenState extends ConsumerState<PriorityMatrixScreen> {
  int? _selectedPriority;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final matrix = ref.watch(priorityMatrixViewModelProvider);
    return TaskMotionScope(
      builder: (context, motion) {
        final buckets = ref
            .read(priorityMatrixViewModelProvider.notifier)
            .bucketsWithRetained(motion.retainedTasks);
        return SafeArea(
          bottom: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact =
                  constraints.maxWidth - 24 < 760 ||
                  usesCompactMobileLayout(context);
              final selected =
                  _selectedPriority ??
                  matrixPriorities.firstWhere(
                    (priority) => matrix.buckets[priority]?.isNotEmpty ?? false,
                    orElse: () => 1,
                  );
              final tasks = buckets[selected] ?? const <TaskItem>[];
              return TaskSelectionRegion(
                scopeKey: compact ? selected : null,
                visibleTasks: compact
                    ? matrix.buckets[selected] ?? const <TaskItem>[]
                    : matrix.tasks.value ?? const <TaskItem>[],
                child: CustomScrollView(
                  slivers: [
                    if (!CompactShellHeading.isShown(context))
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                        sliver: SliverToBoxAdapter(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.navPriorityMatrix,
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineMedium,
                              ),
                              if (!compact) ...[
                                const SizedBox(height: 4),
                                Text(
                                  l10n.priorityMatrixSubtitle,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    matrix.tasks.when(
                      data: (_) => compact
                          ? _compactList(context, matrix, selected, tasks)
                          : SliverPadding(
                              padding: const EdgeInsets.fromLTRB(
                                12,
                                12,
                                12,
                                24,
                              ),
                              sliver: SliverToBoxAdapter(
                                child: _PriorityMatrix(
                                  buckets: buckets,
                                  tasksById: matrix.tasksById,
                                ),
                              ),
                            ),
                      loading: () => const SliverFillRemaining(
                        child: Center(child: CircularProgressIndicator()),
                      ),
                      error: (error, stackTrace) => SliverFillRemaining(
                        child: Center(
                          child: Text(l10n.failedToLoadTasks(error)),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _compactList(
    BuildContext context,
    PriorityMatrixState matrix,
    int selected,
    List<TaskItem> tasks,
  ) {
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: _CompactPriorityOverview(
            buckets: matrix.buckets,
            selected: selected,
            onSelect: (priority) =>
                setState(() => _selectedPriority = priority),
            tasksById: matrix.tasksById,
            onDrop: (taskId, priority) =>
                unawaited(_updatePriority(context, ref, taskId, priority)),
          ),
        ),
        if (tasks.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Text(
                  context.l10n.noTasksHere,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.appColors.secondaryText,
                  ),
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
            sliver: SliverList.separated(
              itemCount: tasks.length,
              itemBuilder: (context, index) => TaskListItem(
                key: ValueKey(tasks[index].id),
                task: tasks[index],
                enableSubtaskDrop: false,
              ),
              separatorBuilder: (context, index) => TaskListDivider(
                previousRow: VisibleTaskRow(task: tasks[index], depth: 0),
              ),
            ),
          ),
      ],
    );
  }
}

class _PriorityMatrix extends ConsumerWidget {
  const _PriorityMatrix({required this.buckets, required this.tasksById});

  final Map<int, List<TaskItem>> buckets;
  final Map<String, TaskItem> tasksById;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final panels = [
      for (final priority in matrixPriorities)
        _PriorityQuadrant(
          priority: priority,
          tasks: buckets[priority]!,
          tasksById: tasksById,
          onPriorityChanged: (taskId) =>
              unawaited(_updatePriority(context, ref, taskId, priority)),
        ),
    ];

    final axisStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: context.appColors.secondaryText,
      fontWeight: FontWeight.w600,
    );
    final l10n = context.l10n;
    return Table(
      columnWidths: const {
        0: FixedColumnWidth(36),
        1: FlexColumnWidth(),
        2: FlexColumnWidth(),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.top,
      children: [
        TableRow(
          children: [
            const SizedBox.shrink(),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 6, bottom: 8),
              child: Center(
                child: Text(
                  l10n.priorityMatrixAxisUrgent,
                  key: const Key('priority-matrix-axis-urgent'),
                  style: axisStyle,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 6, bottom: 8),
              child: Center(
                child: Text(
                  l10n.priorityMatrixAxisNotUrgent,
                  key: const Key('priority-matrix-axis-not-urgent'),
                  style: axisStyle,
                ),
              ),
            ),
          ],
        ),
        TableRow(
          children: [
            TableCell(
              verticalAlignment: TableCellVerticalAlignment.middle,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(bottom: 6),
                child: Center(
                  child: RotatedBox(
                    quarterTurns: 3,
                    child: Text(
                      l10n.priorityMatrixAxisImportant,
                      key: const Key('priority-matrix-axis-important'),
                      style: axisStyle,
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 6, bottom: 6),
              child: panels[0],
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 6, bottom: 6),
              child: panels[1],
            ),
          ],
        ),
        TableRow(
          children: [
            TableCell(
              verticalAlignment: TableCellVerticalAlignment.middle,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(top: 6),
                child: Center(
                  child: RotatedBox(
                    quarterTurns: 3,
                    child: Text(
                      l10n.priorityMatrixAxisNotImportant,
                      key: const Key('priority-matrix-axis-not-important'),
                      style: axisStyle,
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 6, top: 6),
              child: panels[2],
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 6, top: 6),
              child: panels[3],
            ),
          ],
        ),
      ],
    );
  }
}

Future<void> _updatePriority(
  BuildContext context,
  WidgetRef ref,
  String taskId,
  int priority,
) async {
  try {
    await ref
        .read(priorityMatrixViewModelProvider.notifier)
        .setPriority(taskId, priority);
    if (context.mounted) {
      TaskMotionScope.maybeOf(context)?.landed({taskId});
      unawaited(playHaptic(AppHapticCue.light));
    }
  } catch (_) {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.taskActionFailedCount(1))),
    );
  }
}

class _CompactPriorityOverview extends StatelessWidget {
  const _CompactPriorityOverview({
    required this.buckets,
    required this.selected,
    required this.onSelect,
    required this.tasksById,
    required this.onDrop,
  });

  final Map<int, List<TaskItem>> buckets;
  final int selected;
  final ValueChanged<int> onSelect;
  final Map<String, TaskItem> tasksById;
  final void Function(String taskId, int priority) onDrop;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final color = _priorityColor(selected, colors);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 20),
          child: LayoutBuilder(
            builder: (context, constraints) => Column(
              children: [
                for (final pair in const [(1, 2), (3, 4)]) ...[
                  if (pair.$1 == 3) const SizedBox(height: 6),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final priority in [pair.$1, pair.$2]) ...[
                          if (priority == pair.$2) const SizedBox(width: 6),
                          Expanded(
                            child: DragTarget<String>(
                              onWillAcceptWithDetails: (details) {
                                final task = tasksById[details.data];
                                return task != null &&
                                    priorityBucket(task.priority) != priority;
                              },
                              onAcceptWithDetails: (details) =>
                                  onDrop(details.data, priority),
                              builder: (context, candidates, _) =>
                                  _PriorityTile(
                                    priority: priority,
                                    count: buckets[priority]!.length,
                                    stacked:
                                        constraints.maxWidth < 334 ||
                                        MediaQuery.textScalerOf(
                                              context,
                                            ).scale(14) >
                                            17 ||
                                        buckets[priority]!.length >= 100,
                                    selected: selected == priority,
                                    accepting: candidates.isNotEmpty,
                                    onTap: () => onSelect(priority),
                                  ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        Divider(height: 1, color: colors.border),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(
            children: [
              _PriorityBadge(priority: selected),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _title(context, selected),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                key: const Key('priority-matrix-add'),
                tooltip: context.l10n.addTask,
                style: IconButton.styleFrom(
                  minimumSize: const Size.square(44),
                  foregroundColor: color,
                  backgroundColor: color.withValues(alpha: 0.12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () =>
                    showQuickAddDialog(context, defaultPriority: selected),
                icon: const Icon(LucideIcons.plus, size: 20),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PriorityTile extends StatelessWidget {
  const _PriorityTile({
    required this.priority,
    required this.count,
    required this.selected,
    required this.accepting,
    required this.stacked,
    required this.onTap,
  });
  final int priority;
  final int count;
  final bool selected;
  final bool accepting;
  final bool stacked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final color = _priorityColor(priority, colors);
    final theme = Theme.of(context).textTheme;
    final border = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: BorderSide(
        color: accepting || selected ? color : Colors.transparent,
        width: 1.5,
      ),
    );
    final badge = _PriorityBadge(priority: priority);
    final counter = Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: colors.primaryText.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text('$count', style: theme.labelMedium),
    );
    final caption = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _title(context, priority),
          style: theme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(
          _meaning(context, priority),
          key: Key('priority-matrix-meaning-p$priority'),
          style: theme.labelSmall?.copyWith(color: colors.secondaryText),
        ),
      ],
    );
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        key: Key('priority-matrix-quadrant-p$priority'),
        color: Color.alphaBlend(
          color.withValues(alpha: accepting ? 0.18 : 0.08),
          colors.surface,
        ),
        shape: border,
        child: InkWell(
          customBorder: border,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: stacked
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [badge, counter],
                      ),
                      const SizedBox(height: 4),
                      caption,
                    ],
                  )
                : Row(
                    children: [
                      badge,
                      const SizedBox(width: 6),
                      Expanded(child: caption),
                      const SizedBox(width: 4),
                      counter,
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _PriorityBadge extends StatelessWidget {
  const _PriorityBadge({required this.priority});
  final int priority;

  @override
  Widget build(BuildContext context) {
    final color = _priorityColor(priority, context.appColors);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'P$priority',
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PriorityQuadrant extends StatelessWidget {
  const _PriorityQuadrant({
    required this.priority,
    required this.tasks,
    required this.tasksById,
    required this.onPriorityChanged,
  });

  final int priority;
  final List<TaskItem> tasks;
  final Map<String, TaskItem> tasksById;
  final ValueChanged<String> onPriorityChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final priorityColor = _priorityColor(priority, colors);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) {
        final task = tasksById[details.data];
        return task != null && priorityBucket(task.priority) != priority;
      },
      onAcceptWithDetails: (details) => onPriorityChanged(details.data),
      builder: (context, candidateData, rejectedData) {
        final accepting = candidateData.isNotEmpty;
        final duration = AppMotion.duration(context, AppMotion.hover);
        final borderColor = accepting
            ? priorityColor.withValues(alpha: 0.72)
            : colors.border;
        return AnimatedPadding(
          key: Key('priority-matrix-quadrant-p$priority'),
          duration: duration,
          padding: accepting
              ? const EdgeInsets.symmetric(vertical: 6)
              : EdgeInsets.zero,
          curve: AppMotion.curve,
          child: AnimatedContainer(
            duration: duration,
            constraints: const BoxConstraints(minHeight: 180),
            decoration: BoxDecoration(
              color: accepting
                  ? Color.alphaBlend(
                      priorityColor.withValues(alpha: isDark ? 0.14 : 0.08),
                      colors.surface,
                    )
                  : colors.surface,
              border: Border.all(color: borderColor),
              borderRadius: BorderRadius.circular(8),
            ),
            curve: AppMotion.curve,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 3,
                    width: double.infinity,
                    child: ColoredBox(color: priorityColor),
                  ),
                  Container(
                    color: colors.surface,
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: priorityColor.withValues(alpha: 0.10),
                            border: Border.all(
                              color: priorityColor.withValues(alpha: 0.32),
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'P$priority',
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: priorityColor,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _title(context, priority),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: colors.surfaceTint,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${tasks.length}',
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  color: colors.mutedText,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: colors.border),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
                    child: QuickAddBar(
                      defaultPriority: priority,
                      onTaskCreated: (taskIds) {
                        TaskMotionScope.maybeOf(
                          context,
                        )?.created(taskIds.toSet());
                        unawaited(playHaptic(AppHapticCue.light));
                      },
                    ),
                  ),
                  if (tasks.isEmpty)
                    SizedBox(
                      height: 96,
                      child: Center(
                        child: Text(
                          context.l10n.noTasksHere,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: colors.mutedText),
                        ),
                      ),
                    )
                  else
                    for (var index = 0; index < tasks.length; index++) ...[
                      TaskListItem(
                        task: tasks[index],
                        enableSubtaskDrop: false,
                      ),
                      if (index != tasks.length - 1)
                        TaskListDivider(
                          previousRow: VisibleTaskRow(
                            task: tasks[index],
                            depth: 0,
                          ),
                        ),
                    ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

Color _priorityColor(int priority, AppThemePalette colors) {
  return switch (priority) {
    1 => colors.overdue,
    2 => colors.warning,
    3 => colors.info,
    _ => colors.mutedText,
  };
}

String _title(BuildContext context, int priority) {
  final l10n = context.l10n;
  return switch (priority) {
    1 => l10n.priorityMatrixP1Title,
    2 => l10n.priorityMatrixP2Title,
    3 => l10n.priorityMatrixP3Title,
    _ => l10n.priorityMatrixP4Title,
  };
}

String _meaning(BuildContext context, int priority) {
  final l10n = context.l10n;
  final importance = priority <= 2
      ? l10n.priorityMatrixAxisImportant
      : l10n.priorityMatrixAxisNotImportant;
  final urgency = priority == 1 || priority == 3
      ? l10n.priorityMatrixAxisUrgent
      : l10n.priorityMatrixAxisNotUrgent;
  return '$importance / $urgency';
}
