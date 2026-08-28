import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_l10n.dart';
import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/action_feedback.dart';
import '../domain/task_models.dart';
import 'widgets/quick_add_bar.dart';
import 'widgets/task_list_item.dart';
import 'widgets/task_motion.dart';
import 'widgets/task_selection_region.dart';

class PriorityMatrixScreen extends ConsumerWidget {
  const PriorityMatrixScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final tasks = ref.watch(tasksByQueryProvider(const TaskQuery.all()));
    return TaskMotionScope(
      builder: (context, motion) {
        final visibleById = <String, TaskItem>{
          for (final task in tasks.value ?? const <TaskItem>[])
            if (!task.isCompleted) task.id: task,
          for (final task in motion.retainedTasks) task.id: task,
        };
        final visibleTasks = visibleById.values.toList();
        return SafeArea(
          bottom: false,
          child: TaskSelectionRegion(
            visibleTasks: visibleTasks,
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.navPriorityMatrix,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
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
                    ),
                  ),
                ),
                tasks.when(
                  data: (_) => SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                    sliver: SliverToBoxAdapter(
                      child: _PriorityMatrix(items: visibleTasks),
                    ),
                  ),
                  loading: () => const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (error, stackTrace) => SliverFillRemaining(
                    child: Center(child: Text(l10n.failedToLoadTasks(error))),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PriorityMatrix extends ConsumerWidget {
  const _PriorityMatrix({required this.items});

  final List<TaskItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final buckets = <int, List<TaskItem>>{
      for (final priority in _priorities) priority: <TaskItem>[],
    };
    for (final item in items) {
      buckets[_priorityBucket(item.priority)]!.add(item);
    }
    for (final bucket in buckets.values) {
      bucket.sort(_compareMatrixTaskOrder);
    }
    final byId = {for (final item in items) item.id: item};

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;
        final panels = [
          for (final priority in _priorities)
            _PriorityQuadrant(
              priority: priority,
              tasks: buckets[priority]!,
              tasksById: byId,
              showMeaning: !wide,
              onPriorityChanged: (taskId) =>
                  unawaited(_updatePriority(context, ref, taskId, priority)),
            ),
        ];

        if (!wide) {
          return Column(
            children: [
              for (final panel in panels) ...[
                panel,
                if (panel != panels.last) const SizedBox(height: 12),
              ],
            ],
          );
        }

        final axisStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
          color: context.appColors.secondaryText,
          fontWeight: FontWeight.w700,
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
                  padding: const EdgeInsetsDirectional.only(
                    start: 6,
                    bottom: 8,
                  ),
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
                  padding: const EdgeInsetsDirectional.only(
                    start: 6,
                    bottom: 6,
                  ),
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
      },
    );
  }

  Future<void> _updatePriority(
    BuildContext context,
    WidgetRef ref,
    String taskId,
    int priority,
  ) async {
    try {
      await ref
          .read(taskRepositoryProvider)
          .updateTask(taskId, UpdateTaskPatch(priority: priority));
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
}

class _PriorityQuadrant extends StatelessWidget {
  const _PriorityQuadrant({
    required this.priority,
    required this.tasks,
    required this.tasksById,
    required this.showMeaning,
    required this.onPriorityChanged,
  });

  final int priority;
  final List<TaskItem> tasks;
  final Map<String, TaskItem> tasksById;
  final bool showMeaning;
  final ValueChanged<String> onPriorityChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final priorityColor = _priorityColor(priority, colors);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) {
        final task = tasksById[details.data];
        return task != null && _priorityBucket(task.priority) != priority;
      },
      onAcceptWithDetails: (details) => onPriorityChanged(details.data),
      builder: (context, candidateData, rejectedData) {
        final accepting = candidateData.isNotEmpty;
        final duration = MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 140);
        final borderColor = accepting
            ? priorityColor.withValues(alpha: 0.72)
            : colors.border;
        return AnimatedPadding(
          key: Key('priority-matrix-quadrant-p$priority'),
          duration: duration,
          padding: accepting
              ? const EdgeInsets.symmetric(vertical: 6)
              : EdgeInsets.zero,
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
                    color: priorityColor.withValues(
                      alpha: isDark ? 0.10 : 0.06,
                    ),
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
                                  fontWeight: FontWeight.w800,
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
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              if (showMeaning) ...[
                                const SizedBox(height: 2),
                                Text(
                                  _meaning(context, priority),
                                  key: Key(
                                    'priority-matrix-meaning-p$priority',
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(color: colors.mutedText),
                                ),
                              ],
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
                                  fontWeight: FontWeight.w700,
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
                        Divider(height: 1, indent: 38, color: colors.border),
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

const _priorities = [1, 2, 3, 4];

int _priorityBucket(int priority) {
  return priority >= 1 && priority <= 4 ? priority : 4;
}

int _compareMatrixTaskOrder(TaskItem a, TaskItem b) {
  final aStart = a.schedule?.occurrenceStartLocal;
  final bStart = b.schedule?.occurrenceStartLocal;
  if (aStart != null && bStart != null) {
    final scheduleCompare = aStart.compareTo(bStart);
    if (scheduleCompare != 0) {
      return scheduleCompare;
    }
  } else if (aStart != null) {
    return -1;
  } else if (bStart != null) {
    return 1;
  }

  final dayOrderCompare = (a.dayOrder ?? 999999).compareTo(
    b.dayOrder ?? 999999,
  );
  if (dayOrderCompare != 0) {
    return dayOrderCompare;
  }
  return a.orderKey.compareTo(b.orderKey);
}

Color _priorityColor(int priority, AppThemePalette colors) {
  return switch (priority) {
    1 => colors.accent,
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
