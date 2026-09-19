import 'package:pomodoist/ui/tasks/view_models/task_subtask_progress.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons, ShadButton;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/tasks/view_models/task_list_view_model.dart';
import 'package:pomodoist/ui/core/widgets/action_feedback.dart';
import 'package:pomodoist/ui/core/widgets/adaptive_shell.dart'
    show showQuickAddDialog;
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/ui/tasks/widgets/quick_add_bar.dart';
import 'package:pomodoist/ui/tasks/widgets/task_list_item.dart';
import 'package:pomodoist/ui/tasks/widgets/task_motion.dart';
import 'package:pomodoist/ui/tasks/widgets/task_selection_region.dart';
import 'package:pomodoist/ui/tasks/widgets/task_view_state.dart';

class TaskListView extends ConsumerWidget {
  const TaskListView({
    required this.title,
    required this.query,
    this.subtitle,
    this.headerAddon,
    this.footerAddon,
    this.emptyMessage,
    this.emptyDescription,
    this.taskFilter,
    this.showQuickAdd = true,
    this.quickAddProjectId,
    this.titleLeading,
    super.key,
  });

  final String title;
  final String? subtitle;
  final TaskQuery query;
  final Widget? headerAddon;
  final Widget? footerAddon;
  final String? emptyMessage;
  final String? emptyDescription;
  final bool Function(TaskItem task)? taskFilter;
  final bool showQuickAdd;
  final String? quickAddProjectId;
  final Widget? titleLeading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final viewState = ref.watch(taskListViewModelProvider(query));
    final tasks = viewState.tasks;
    final emptyTitle =
        emptyMessage ??
        switch (query.kind) {
          TaskQueryKind.inbox => l10n.inboxEmptyTitle,
          TaskQueryKind.today => l10n.todayEmptyTitle,
          TaskQueryKind.project => l10n.projectEmptyTitle,
          _ => l10n.noTasksHere,
        };
    final emptyBody =
        emptyDescription ??
        switch (query.kind) {
          TaskQueryKind.inbox => l10n.inboxEmptyDescription,
          TaskQueryKind.today => l10n.todayEmptyDescription,
          TaskQueryKind.project => l10n.projectEmptyDescription,
          _ => null,
        };
    Widget loadError() => TaskViewState(
      icon: LucideIcons.circleAlert,
      title: l10n.taskListLoadError,
      actions: ShadButton.secondary(
        onPressed: () =>
            ref.read(taskListViewModelProvider(query).notifier).retry(),
        child: Text(l10n.commonRetry),
      ),
    );
    final supportsRootDrop =
        !kIsWeb &&
        switch (defaultTargetPlatform) {
          TargetPlatform.android || TargetPlatform.iOS => true,
          _ => false,
        };
    return TaskMotionScope(
      key: ValueKey(query),
      builder: (context, motion) {
        final visibleItems = viewState.visibleTasks(
          motion.retainedTasks,
          taskFilter,
        );
        final subtaskIds = {
          for (final task in visibleItems)
            if (task.parentId != null) task.id,
        };
        return SafeArea(
          bottom: false,
          child: TaskSelectionRegion(
            visibleTasks: visibleItems,
            scopeKey: query,
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (titleLeading != null) ...[
                              titleLeading!,
                              const SizedBox(width: 8),
                            ],
                            Expanded(
                              child: Text(
                                title,
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineMedium,
                              ),
                            ),
                          ],
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            subtitle!,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                        if (headerAddon != null) ...[
                          const SizedBox(height: 16),
                          headerAddon!,
                        ],
                        if (showQuickAdd) ...[
                          const SizedBox(height: 16),
                          QuickAddBar(
                            defaultDate: query.kind == TaskQueryKind.today
                                ? query.now
                                : null,
                            projectId: quickAddProjectId,
                            labelId: query.labelId,
                            onTaskCreated: (taskIds) {
                              motion.created(taskIds.toSet());
                              unawaited(playHaptic(AppHapticCue.light));
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (tasks.isLoading && tasks.hasValue)
                  const SliverToBoxAdapter(child: LinearProgressIndicator()),
                if (tasks.hasError && tasks.hasValue)
                  SliverToBoxAdapter(child: loadError()),
                tasks.when(
                  skipLoadingOnReload: true,
                  skipError: true,
                  data: (_) {
                    if (visibleItems.isEmpty &&
                        (tasks.isLoading || tasks.hasError)) {
                      return const SliverToBoxAdapter(child: SizedBox.shrink());
                    }
                    if (visibleItems.isEmpty) {
                      final empty = TaskViewState(
                        icon: switch (query.kind) {
                          TaskQueryKind.inbox => LucideIcons.inbox,
                          TaskQueryKind.today => LucideIcons.calendarCheck,
                          TaskQueryKind.project => LucideIcons.folder,
                          TaskQueryKind.label => LucideIcons.tag,
                          _ => LucideIcons.listChecks,
                        },
                        title: emptyTitle,
                        description: emptyBody,
                        actions: showQuickAdd
                            ? ShadButton.secondary(
                                onPressed: () => showQuickAddDialog(
                                  context,
                                  defaultDate: query.kind == TaskQueryKind.today
                                      ? query.now
                                      : null,
                                  projectId: quickAddProjectId,
                                  labelId: query.labelId,
                                ),
                                leading: const Icon(LucideIcons.plus, size: 16),
                                child: Text(l10n.addTask),
                              )
                            : null,
                      );
                      return footerAddon == null
                          ? SliverFillRemaining(
                              hasScrollBody: false,
                              child: empty,
                            )
                          : SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 32,
                                ),
                                child: empty,
                              ),
                            );
                    }
                    final allItems = [...viewState.allTasks, ...visibleItems];
                    final progressById = taskSubtaskProgressById(allItems);
                    final rows = viewState.rows(visibleItems);
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
                        separatorBuilder: (context, index) {
                          final colorScheme = Theme.of(context).colorScheme;
                          final divider = TaskListDivider(
                            previousDepth: rows[index].depth,
                            nextDepth: rows[index + 1].depth,
                          );
                          if (!supportsRootDrop) {
                            return divider;
                          }
                          return DragTarget<String>(
                            key: ValueKey('task-root-gap-$index'),
                            onWillAcceptWithDetails: (details) =>
                                subtaskIds.contains(details.data),
                            onAcceptWithDetails: (details) => unawaited(
                              _makeRootTask(context, ref, details.data),
                            ),
                            builder: (context, candidateData, rejectedData) {
                              final accepting = candidateData.isNotEmpty;
                              return AnimatedContainer(
                                duration:
                                    MediaQuery.disableAnimationsOf(context)
                                    ? Duration.zero
                                    : const Duration(milliseconds: 160),
                                height: accepting ? 32 : 12,
                                color: accepting
                                    ? colorScheme.primaryContainer
                                    : Colors.transparent,
                                child: Center(
                                  child: accepting
                                      ? Text(
                                          l10n.makeParentTask,
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelMedium
                                              ?.copyWith(
                                                color: colorScheme
                                                    .onPrimaryContainer,
                                              ),
                                        )
                                      : divider,
                                ),
                              );
                            },
                          );
                        },
                      ),
                    );
                  },
                  loading: () => const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (error, stackTrace) => SliverFillRemaining(
                    hasScrollBody: false,
                    child: loadError(),
                  ),
                ),
                if (footerAddon != null)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                    sliver: SliverToBoxAdapter(child: footerAddon),
                  ),
                if (supportsRootDrop && visibleItems.isNotEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: DragTarget<String>(
                      key: const Key('task-root-drop-zone'),
                      onWillAcceptWithDetails: (details) =>
                          subtaskIds.contains(details.data),
                      onAcceptWithDetails: (details) =>
                          unawaited(_makeRootTask(context, ref, details.data)),
                      builder: (context, candidateData, rejectedData) {
                        final accepting = candidateData.isNotEmpty;
                        final colorScheme = Theme.of(context).colorScheme;
                        return ColoredBox(
                          color: accepting
                              ? colorScheme.primaryContainer
                              : Colors.transparent,
                          child: Center(
                            child: accepting
                                ? Text(
                                    l10n.makeParentTask,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          color: colorScheme.onPrimaryContainer,
                                        ),
                                  )
                                : null,
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _makeRootTask(
    BuildContext context,
    WidgetRef ref,
    String taskId,
  ) async {
    try {
      await ref
          .read(taskListViewModelProvider(query).notifier)
          .makeRoot(taskId);
      if (context.mounted) {
        TaskMotionScope.maybeOf(context)?.landed({taskId});
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
