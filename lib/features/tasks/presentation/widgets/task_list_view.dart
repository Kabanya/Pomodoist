import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/app_l10n.dart';
import '../../../../app/providers.dart';
import '../../domain/task_models.dart';
import 'quick_add_bar.dart';
import 'task_list_item.dart';

class TaskListView extends ConsumerWidget {
  const TaskListView({
    required this.title,
    required this.query,
    this.subtitle,
    this.headerAddon,
    this.emptyMessage,
    this.taskFilter,
    this.showQuickAdd = true,
    this.quickAddProjectId,
    super.key,
  });

  final String title;
  final String? subtitle;
  final TaskQuery query;
  final Widget? headerAddon;
  final String? emptyMessage;
  final bool Function(TaskItem task)? taskFilter;
  final bool showQuickAdd;
  final String? quickAddProjectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final tasks = ref.watch(tasksByQueryProvider(query));
    final allOpenTasks = ref.watch(tasksByQueryProvider(const TaskQuery.all()));
    final completedTasks = ref.watch(
      tasksByQueryProvider(const TaskQuery.completed()),
    );
    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (headerAddon != null) ...[
                    const SizedBox(height: 16),
                    headerAddon!,
                  ],
                  if (showQuickAdd) ...[
                    const SizedBox(height: 16),
                    QuickAddBar(projectId: quickAddProjectId),
                  ],
                ],
              ),
            ),
          ),
          tasks.when(
            data: (items) {
              final visibleItems = taskFilter == null
                  ? items
                  : items.where(taskFilter!).toList();
              if (visibleItems.isEmpty) {
                return SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text(
                      emptyMessage ?? l10n.noTasksHere,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                );
              }
              final allItems = [
                ...?allOpenTasks.value,
                ...?completedTasks.value,
                ...visibleItems,
              ];
              final progressById = taskSubtaskProgressById(allItems);
              final rows = _visibleTaskRows(allItems, visibleItems);
              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                sliver: SliverList.separated(
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    return TaskListItem(
                      task: row.task,
                      depth: row.depth,
                      subtaskProgress: progressById[row.task.id],
                    );
                  },
                  separatorBuilder: (context, index) => Divider(
                    height: 1,
                    indent: 38,
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              );
            },
            loading: () => const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, stackTrace) => SliverFillRemaining(
              child: Center(child: Text(l10n.failedToLoadTasks(error))),
            ),
          ),
        ],
      ),
    );
  }
}

List<_VisibleTaskRow> _visibleTaskRows(
  List<TaskItem> allItems,
  List<TaskItem> visibleItems,
) {
  final byId = <String, TaskItem>{for (final task in allItems) task.id: task};
  final visibleIds = {for (final task in visibleItems) task.id};
  final childrenByParent = <String?, List<TaskItem>>{};
  for (final task in byId.values) {
    final parentId = byId.containsKey(task.parentId) ? task.parentId : null;
    childrenByParent.putIfAbsent(parentId, () => []).add(task);
  }
  for (final children in childrenByParent.values) {
    children.sort(_compareTaskOrder);
  }

  final rows = <_VisibleTaskRow>[];
  void walk(TaskItem task, int depth) {
    final children = childrenByParent[task.id] ?? const <TaskItem>[];
    final isVisible = visibleIds.contains(task.id);
    if (isVisible) {
      rows.add(_VisibleTaskRow(task: task, depth: depth));
    }
    for (final child in children) {
      walk(child, depth + 1);
    }
  }

  for (final task in childrenByParent[null] ?? const <TaskItem>[]) {
    walk(task, 0);
  }
  return rows;
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

class _VisibleTaskRow {
  const _VisibleTaskRow({required this.task, required this.depth});

  final TaskItem task;
  final int depth;
}
