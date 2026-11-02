import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/config/task_blocking_dependencies.dart';
import 'package:pomodoist/domain/models/tasks/task_blocking.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/routing/task_detail_navigation.dart';
import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';

class TaskPriorityCascadeControl extends ConsumerStatefulWidget {
  const TaskPriorityCascadeControl({super.key});
  @override
  ConsumerState<TaskPriorityCascadeControl> createState() =>
      _TaskPriorityCascadeControlState();
}

class _TaskPriorityCascadeControlState
    extends ConsumerState<TaskPriorityCascadeControl> {
  bool busy = false;
  bool failed = false;
  @override
  Widget build(BuildContext context) {
    final policy = ref.watch(taskBlockingPolicyProvider).asData?.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ShadSwitch(
          label: Text(context.l10n.blockingCascade),
          key: const ValueKey('task-priority-cascade'),
          value: policy?.priorityCascadeEnabled ?? false,
          onChanged: policy == null || busy
              ? null
              : (enabled) async {
                  setState(() {
                    busy = true;
                    failed = false;
                  });
                  try {
                    (await ref
                            .read(taskBlockingRepositoryProvider)
                            .setCascade(enabled))
                        .getOrThrow();
                  } catch (_) {
                    if (mounted) setState(() => failed = true);
                  } finally {
                    if (mounted) setState(() => busy = false);
                  }
                },
        ),
        if (failed) Text(context.l10n.blockingUnavailable),
      ],
    );
  }
}

class TaskBlockingControls extends ConsumerStatefulWidget {
  const TaskBlockingControls({
    required this.task,
    this.initiallyExpanded = false,
    this.child,
    super.key,
  });
  final TaskItem task;
  final Widget? child;
  final bool initiallyExpanded;
  @override
  ConsumerState<TaskBlockingControls> createState() =>
      _TaskBlockingControlsState();
}

class _TaskBlockingControlsState extends ConsumerState<TaskBlockingControls> {
  late bool expanded = widget.initiallyExpanded;
  String search = '';
  bool busy = false;
  String? error;
  Future<void> _change(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) setState(() => error = context.l10n.blockingUnavailable);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final policy = ref.watch(taskBlockingPolicyProvider).asData?.value;
    if (policy == null) return widget.child ?? const SizedBox.shrink();
    final task = policy.tasks[widget.task.id] ?? widget.task;
    final availability = policy.availability(task.id);
    final syncConflict =
        !task.isCompleted &&
        (ref
                .watch(taskBlockingConflictsProvider)
                .asData
                ?.value
                .contains(task.id) ??
            false);
    final selected = policy.selectionFor(task);
    final deleteAction = ref.watch(inlineTaskDeleteRequestsProvider)[task.id];
    final deletedIds = deleteAction == null
        ? const <String>{}
        : policy.subtree(task.id);
    final open = expanded || deleteAction != null;
    final canEdit = task.canEdit && !task.isCompleted && !task.isDeleted;
    final canUrgent =
        canEdit &&
        (task.scopeId == null || task.assigneeIds.contains(policy.actorId));
    final candidates = search.trim().isEmpty
        ? <TaskItem>[]
        : policy.tasks.values
              .where((candidate) {
                if (candidate.isDeleted ||
                    candidate.isCompleted ||
                    task.prerequisiteIds.contains(candidate.id) ||
                    !candidate.content.toLowerCase().contains(
                      search.toLowerCase(),
                    )) {
                  return false;
                }
                try {
                  policy.validateDependencies(task.id, [
                    ...task.prerequisiteIds,
                    candidate.id,
                  ]);
                  return true;
                } on ArgumentError {
                  return false;
                }
              })
              .take(8)
              .toList();
    final reason = availability.reasons.firstOrNull;
    final label = switch (reason) {
      TaskBlockReason.dependency => context.l10n.blockingDependency,
      TaskBlockReason.urgent => context.l10n.blockingUrgentReason,
      TaskBlockReason.priority => context.l10n.blockingPriority,
      null =>
        syncConflict
            ? context.l10n.blockingSyncConflict
            : context.l10n.blockingControls,
    };
    return Padding(
      padding: EdgeInsetsDirectional.only(start: widget.child == null ? 28 : 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.child != null)
            Row(
              children: [
                Expanded(child: widget.child!),
                IconButton(
                  key: ValueKey('task-blocking-expand-${task.id}'),
                  tooltip: label,
                  icon: Icon(
                    reason != null || syncConflict
                        ? LucideIcons.lockKeyhole
                        : selected != null
                        ? LucideIcons.flame
                        : LucideIcons.link,
                    size: 16,
                  ),
                  onPressed: () => setState(() => expanded = !expanded),
                ),
              ],
            )
          else
            ShadButton.ghost(
              key: ValueKey('task-blocking-expand-${task.id}'),
              expands: true,
              onPressed: () => setState(() => expanded = !expanded),
              leading: Icon(
                reason != null || syncConflict
                    ? LucideIcons.lockKeyhole
                    : selected != null
                    ? LucideIcons.flame
                    : LucideIcons.link,
                size: 14,
              ),
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          if (open) ...[
            if (syncConflict) Text(context.l10n.blockingSyncConflictDetails),
            if (deleteAction != null) ...[
              Text(context.l10n.blockingDeleteWarning),
              for (final affected in policy.tasks.values.where(
                (candidate) =>
                    !candidate.isDeleted &&
                    !deletedIds.contains(candidate.id) &&
                    candidate.prerequisiteIds.any(deletedIds.contains),
              ))
                ShadButton.ghost(
                  expands: true,
                  onPressed: () => openTaskDetails(context, affected.id),
                  child: Text(
                    affected.content,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              Wrap(
                children: [
                  ShadButton.ghost(
                    onPressed: busy
                        ? null
                        : () => _change(() async {
                            ref
                                .read(inlineTaskDeleteRequestsProvider.notifier)
                                .clear(task.id);
                            await deleteAction();
                          }),
                    child: Text(context.l10n.commonDelete),
                  ),
                  ShadButton.ghost(
                    onPressed: () => ref
                        .read(inlineTaskDeleteRequestsProvider.notifier)
                        .clear(task.id),
                    child: Text(context.l10n.commonCancel),
                  ),
                ],
              ),
            ],
            for (final id in availability.blockingTaskIds)
              ShadButton.ghost(
                expands: true,
                onPressed: policy.tasks[id] == null
                    ? null
                    : () => openTaskDetails(context, id),
                child: Text(
                  policy.tasks[id]?.content ?? id,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (canUrgent)
              ShadCheckbox(
                label: Text(context.l10n.blockingUrgent),
                value: selected != null,
                onChanged: busy
                    ? null
                    : (value) => _change(
                        () async =>
                            (await ref
                                    .read(taskBlockingRepositoryProvider)
                                    .setUrgent(task, urgent: value))
                                .getOrThrow(),
                      ),
              ),
            if (canUrgent &&
                selected != null &&
                task.schedule?.isRecurringOccurrence == true)
              ShadCheckbox(
                label: Text(context.l10n.blockingRepeat),
                value: selected.repeatWithSeries,
                onChanged: busy
                    ? null
                    : (value) => _change(
                        () async =>
                            (await ref
                                    .read(taskBlockingRepositoryProvider)
                                    .setUrgent(
                                      task,
                                      urgent: true,
                                      repeatWithSeries: value,
                                    ))
                                .getOrThrow(),
                      ),
              ),
            for (final id in task.prerequisiteIds)
              if (policy.tasks[id]?.isDeleted != true)
                Row(
                  children: [
                    Expanded(
                      child: ShadButton.ghost(
                        expands: true,
                        onPressed: () => openTaskDetails(context, id),
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            policy.tasks[id]?.content ?? id,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                    if (canEdit)
                      IconButton(
                        tooltip: context.l10n.commonDelete,
                        icon: const Icon(LucideIcons.x, size: 16),
                        onPressed: busy
                            ? null
                            : () => _change(
                                () async =>
                                    (await ref
                                            .read(taskRepositoryProvider)
                                            .updateTask(
                                              task.id,
                                              UpdateTaskPatch(
                                                prerequisiteIds: task
                                                    .prerequisiteIds
                                                    .where((p) => p != id)
                                                    .toList(),
                                              ),
                                            ))
                                        .getOrThrow(),
                              ),
                      ),
                  ],
                ),
            if (canEdit)
              ShadInput(
                key: ValueKey('task-dependency-search-${task.id}'),
                placeholder: Text(context.l10n.blockingSearch),
                onChanged: (value) => setState(() => search = value),
              ),
            for (final candidate in candidates)
              ShadButton.ghost(
                expands: true,
                onPressed: busy
                    ? null
                    : () => _change(
                        () async =>
                            (await ref
                                    .read(taskRepositoryProvider)
                                    .updateTask(
                                      task.id,
                                      UpdateTaskPatch(
                                        prerequisiteIds: [
                                          ...task.prerequisiteIds,
                                          candidate.id,
                                        ],
                                      ),
                                    ))
                                .getOrThrow(),
                      ),
                leading: const Icon(LucideIcons.plus, size: 16),
                child: Text(
                  candidate.content,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (search.isNotEmpty && candidates.isEmpty)
              Text(context.l10n.blockingNoMatches),
            if (error != null)
              Text(error!, style: TextStyle(color: context.appColors.error)),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}
