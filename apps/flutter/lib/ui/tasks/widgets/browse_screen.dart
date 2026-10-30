import 'package:pomodoist/ui/tasks/view_models/browse_view_model.dart';
import 'package:pomodoist/ui/tasks/widgets/project_localizations.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart'
    show
        LucideIcons,
        ShadButton,
        ShadIconButton,
        ShadPopover,
        ShadPopoverController,
        ShadTab,
        ShadTabs;

import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/localization/formatters.dart';
import 'package:pomodoist/ui/core/themes/app_motion.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/ui/tasks/view_models/browse_summary.dart';
import 'package:pomodoist/ui/tasks/widgets/create_project_dialog.dart';
import 'package:pomodoist/ui/tasks/widgets/project_context_menu.dart';
import 'package:pomodoist/ui/tasks/widgets/project_icon.dart';
import 'package:pomodoist/ui/tasks/widgets/task_list_view.dart';
import 'package:pomodoist/ui/tasks/widgets/task_selection_region.dart';
import 'package:pomodoist/ui/tasks/widgets/label_icon.dart';

class BrowseScreen extends ConsumerStatefulWidget {
  const BrowseScreen({super.key});

  @override
  ConsumerState<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends ConsumerState<BrowseScreen> {
  final _identity = Object();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final viewState = ref.watch(browseViewModelProvider(_identity));
    final summary = viewState.summary;
    final period = viewState.period;
    final item = viewState.numbers;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      Text(
                        l10n.browseTitle,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const _QueueIndicator(),
                          const SizedBox(width: 4),
                          ShadButton.ghost(
                            leading: const Icon(
                              LucideIcons.userRound,
                              size: 16,
                            ),
                            onPressed: () =>
                                context.go('/settings?section=account'),
                            child: Text(l10n.account),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: context.appColors.surface,
                      border: Border.all(color: context.appColors.border),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        LayoutBuilder(
                          builder: (context, constraints) => Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 16,
                            runSpacing: 8,
                            children: [
                              Wrap(
                                spacing: 16,
                                runSpacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth: constraints.maxWidth,
                                    ),
                                    child: SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: IntrinsicWidth(
                                        child: ShadTabs<BrowsePeriod>(
                                          value: period,
                                          onChanged: (value) => ref
                                              .read(
                                                browseViewModelProvider(
                                                  _identity,
                                                ).notifier,
                                              )
                                              .setPeriod(value),
                                          tabs: [
                                            ShadTab(
                                              value: BrowsePeriod.today,
                                              child: Text(l10n.today),
                                            ),
                                            ShadTab(
                                              value: BrowsePeriod.sevenDays,
                                              child: Text(l10n.browseSevenDays),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  Text(
                                    MaterialLocalizations.of(
                                      context,
                                    ).formatFullDate(viewState.today),
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color:
                                              context.appColors.secondaryText,
                                        ),
                                  ),
                                ],
                              ),
                              ShadButton.ghost(
                                onPressed: () => context.go('/reports'),
                                leading: const Icon(
                                  LucideIcons.chartNoAxesColumn,
                                  size: 16,
                                ),
                                trailing: const Icon(
                                  LucideIcons.arrowRight,
                                  size: 16,
                                ),
                                child: Text(l10n.reportsTitle),
                              ),
                            ],
                          ),
                        ),
                        _LoadStatus(
                          value: summary,
                          keyPrefix: 'browse-productivity',
                          errorText: l10n.failedToLoadReports,
                          onRetry: () => ref
                              .read(browseViewModelProvider(_identity).notifier)
                              .retry(),
                        ),
                        const SizedBox(height: 20),
                        AnimatedSwitcher(
                          duration: AppMotion.duration(
                            context,
                            AppMotion.state,
                          ),
                          switchInCurve: AppMotion.curve,
                          switchOutCurve: AppMotion.curve,
                          child: LayoutBuilder(
                            key: ValueKey(period),
                            builder: (context, constraints) {
                              final scale =
                                  MediaQuery.textScalerOf(context).scale(14) /
                                  14;
                              final columns = math.min(
                                constraints.maxWidth >= 640 ? 4 : 2,
                                math.max(
                                  1,
                                  (constraints.maxWidth / (140 * scale))
                                      .floor(),
                                ),
                              );
                              final width =
                                  (constraints.maxWidth - (columns - 1) * 16) /
                                  columns;
                              return Wrap(
                                spacing: 16,
                                runSpacing: 24,
                                children: [
                                  _Metric(
                                    width: width,
                                    icon: LucideIcons.circleCheck,
                                    color: context.appColors.success,
                                    label: l10n.completedTasks,
                                    value:
                                        item?.completedTasks.toString() ?? '—',
                                  ),
                                  _Metric(
                                    width: width,
                                    icon: LucideIcons.timer,
                                    color: context.appColors.accent,
                                    label: l10n.focusIntervals,
                                    value:
                                        item?.focusIntervals.toString() ?? '—',
                                  ),
                                  _Metric(
                                    width: width,
                                    icon: LucideIcons.target,
                                    color: context.appColors.accent,
                                    label: l10n.focusTime,
                                    value: item == null
                                        ? '—'
                                        : formatFocusTime(
                                            context,
                                            item.focusSeconds,
                                          ),
                                  ),
                                  _Metric(
                                    width: width,
                                    icon: LucideIcons.listTodo,
                                    color: context.appColors.secondaryText,
                                    label: l10n.browseOpenNow,
                                    value: item?.openTasks.toString() ?? '—',
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  LayoutBuilder(
                    builder: (context, constraints) =>
                        constraints.maxWidth >= 960
                        ? const Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: _BrowseProjects()),
                              SizedBox(width: 32),
                              SizedBox(width: 320, child: _BrowseSecondary()),
                            ],
                          )
                        : const Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _BrowseProjects(),
                              SizedBox(height: 24),
                              Divider(height: 1),
                              SizedBox(height: 24),
                              _BrowseSecondary(),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BrowseProjects extends ConsumerWidget {
  const _BrowseProjects();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final viewState = ref.watch(browseProjectsViewModelProvider);
    final projects = viewState.projects;
    final tasks = viewState.tasks;
    final counts = viewState.counts;
    final rows = viewState.rows;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeading(
          title: l10n.navProjects,
          action: ShadButton(
            leading: const Icon(LucideIcons.plus, size: 16),
            onPressed: () => showCreateProjectDialog(context),
            child: Text(l10n.newProject),
          ),
        ),
        _LoadStatus(
          value: projects,
          errorText: l10n.failedToLoadProjects,
          onRetry: () => ref
              .read(browseProjectsViewModelProvider.notifier)
              .retryProjects(),
        ),
        _LoadStatus(
          value: tasks,
          errorText: l10n.failedToLoadTasks,
          onRetry: () =>
              ref.read(browseProjectsViewModelProvider.notifier).retryTasks(),
        ),
        const SizedBox(height: 8),
        if (projects.hasValue && rows.isEmpty)
          Text(l10n.noProjects, style: Theme.of(context).textTheme.bodyMedium),
        for (final row in rows)
          Padding(
            padding: EdgeInsetsDirectional.only(
              start: math.min(row.depth, 4) * 20.0,
              top: row.depth == 0 ? 8 : 0,
            ),
            child: ProjectContextMenu(
              key: ValueKey('browse-project-${row.project.id}'),
              project: row.project,
              showMenuButton: true,
              child: Material(
                color: row.depth == 0
                    ? context.appColors.surface
                    : Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: context.appColors.border),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  hoverColor: context.appColors.surfaceHover,
                  focusColor: context.appColors.accentTint,
                  hoverDuration: AppMotion.duration(context, AppMotion.hover),
                  onTap: () => context.go('/project/${row.project.id}'),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 52),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          ProjectIconView(project: row.project, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              row.project.displayName(context.l10n),
                              textAlign: TextAlign.start,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    fontWeight: row.depth == 0
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Semantics(
                            label: l10n.browseOpenNow,
                            child: Text(
                              counts == null
                                  ? '—'
                                  : '${counts[row.project.id] ?? 0}',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.merge(AppTheme.monoTextStyle)
                                  .copyWith(
                                    color: context.appColors.secondaryText,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _BrowseSecondary extends ConsumerWidget {
  const _BrowseSecondary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final labels = ref.watch(browseLabelsViewModelProvider);
    final labelTaskCounts = ref.watch(labelTaskCountsViewModelProvider);
    final items = labels.value ?? const <LabelItem>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeading(
          title: l10n.labelsTitle,
          action: Tooltip(
            message: l10n.newLabel,
            child: ShadIconButton.ghost(
              width: 44,
              height: 44,
              icon: const Icon(LucideIcons.plus, size: 18),
              onPressed: () => showCreateLabelDialog(context),
            ),
          ),
        ),
        _LoadStatus(
          value: labels,
          errorText: l10n.failedToLoadLabels,
          onRetry: () =>
              ref.read(browseLabelsViewModelProvider.notifier).retry(),
        ),
        const SizedBox(height: 8),
        if (labels.hasValue && items.isEmpty)
          Text(l10n.noLabels, style: Theme.of(context).textTheme.bodyMedium),
        if (items.isNotEmpty)
          Material(
            color: context.appColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: context.appColors.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var index = 0; index < items.length; index++) ...[
                  if (index > 0) const Divider(height: 1),
                  Semantics(
                    button: true,
                    child: InkWell(
                      onTap: () => context.go('/label/${items[index].id}'),
                      hoverColor: context.appColors.surfaceHover,
                      focusColor: context.appColors.accentTint,
                      hoverDuration: AppMotion.duration(
                        context,
                        AppMotion.hover,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            LabelIconView(label: items[index], size: 18),
                            const SizedBox(width: 12),
                            Expanded(child: Text(items[index].name)),
                            const SizedBox(width: 12),
                            Text(
                              '${labelTaskCounts[items[index].id] ?? 0}',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.merge(AppTheme.monoTextStyle)
                                  .copyWith(
                                    color: context.appColors.secondaryText,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        const _OverdueSummary(),
        const SizedBox(height: 24),
        const Divider(height: 1),
        const SizedBox(height: 16),
        Material(
          color: context.appColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: context.appColors.border),
          ),
          child: Semantics(
            button: true,
            child: InkWell(
              key: const Key('browse-completed-tasks'),
              borderRadius: BorderRadius.circular(8),
              onTap: () => context.go('/browse/completed'),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(LucideIcons.circleCheck, size: 18),
                    const SizedBox(width: 12),
                    Expanded(child: Text(l10n.completedTasks)),
                    const SizedBox(width: 8),
                    const Icon(LucideIcons.arrowRight, size: 16),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _QueueIndicator extends ConsumerStatefulWidget {
  const _QueueIndicator();

  @override
  ConsumerState<_QueueIndicator> createState() => _QueueIndicatorState();
}

class _QueueIndicatorState extends ConsumerState<_QueueIndicator> {
  final _popover = ShadPopoverController();

  @override
  void dispose() {
    _popover.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final pending = ref.watch(syncQueueViewModelProvider);
    final healthState = ref.watch(syncQueueStatusViewModelProvider);
    final health = healthState.value;
    final unavailable = pending.hasError || healthState.hasError;
    final loading = pending.isLoading || healthState.isLoading;
    final unresolved = (health?.rejected ?? 0) + (health?.repair ?? 0);
    final count = pending.hasValue ? pending.value! : null;
    final description = unavailable
        ? l10n.browseQueueUnavailable
        : loading
        ? l10n.browseQueueLoading
        : l10n.pendingLocalCommands(count!);
    final media = MediaQuery.of(context);
    return ShadPopover(
      controller: _popover,
      popover: (context) => ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: math.max(1, math.min(280, media.size.width - 64)),
          maxHeight: math.max(
            1,
            media.size.height - media.viewInsets.bottom - 96,
          ),
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.syncReadyQueue,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              if (count != null) Text(l10n.pendingLocalCommands(count)),
              if (unresolved > 0)
                Text(
                  l10n.syncUnresolvedChanges(
                    health?.rejected ?? 0,
                    health?.repair ?? 0,
                  ),
                  style: TextStyle(color: context.appColors.error),
                ),
              _LoadStatus(
                value: healthState.hasError ? healthState : pending,
                errorText: (_) => l10n.browseQueueUnavailable,
                onRetry: () =>
                    ref.read(syncQueueViewModelProvider.notifier).retry(),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.browseQueueExplanation,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      child: Tooltip(
        message: description,
        child: ShadButton.ghost(
          onPressed: _popover.toggle,
          leading: Icon(
            unavailable || unresolved > 0
                ? LucideIcons.cloudAlert
                : LucideIcons.cloudUpload,
            size: 16,
            color: unavailable || unresolved > 0
                ? context.appColors.error
                : context.appColors.secondaryText,
          ),
          child: Text(
            loading
                ? '…'
                : count == null
                ? '—'
                : '${count + unresolved}',
          ),
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.action});

  final String title;
  final Widget action;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.spaceBetween,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 12,
    runSpacing: 8,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleLarge),
      action,
    ],
  );
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.width,
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  final double width;
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.appColors.secondaryText,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  value,
                  style: Theme.of(
                    context,
                  ).textTheme.headlineSmall?.merge(AppTheme.monoTextStyle),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _LoadStatus extends StatelessWidget {
  const _LoadStatus({
    required this.value,
    required this.errorText,
    required this.onRetry,
    this.keyPrefix,
  });

  final AsyncValue<Object?> value;
  final String Function(Object) errorText;
  final VoidCallback onRetry;
  final String? keyPrefix;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (value.isLoading)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: LinearProgressIndicator(
            key: keyPrefix == null ? null : Key('$keyPrefix-loading'),
          ),
        ),
      if (value.hasError)
        Semantics(
          liveRegion: true,
          child: Padding(
            key: keyPrefix == null ? null : Key('$keyPrefix-error'),
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  errorText(value.error!),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.appColors.error,
                  ),
                ),
                ShadButton.ghost(
                  key: keyPrefix == null ? null : Key('$keyPrefix-retry'),
                  onPressed: onRetry,
                  leading: const Icon(LucideIcons.refreshCw, size: 16),
                  child: Text(context.l10n.commonRetry),
                ),
              ],
            ),
          ),
        ),
    ],
  );
}

class CompletedTasksScreen extends ConsumerWidget {
  const CompletedTasksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(completedTasksViewModelProvider);
    return TaskListView(
      title: context.l10n.completedTasks,
      query: const TaskQuery.completed(),
      showQuickAdd: false,
      taskFilter: ref.read(completedTasksViewModelProvider.notifier).includes,
    );
  }
}

class _OverdueSummary extends ConsumerWidget {
  const _OverdueSummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(overdueViewModelProvider);
    final count = tasks.value?.length ?? 0;
    if (count == 0 && !tasks.isLoading && !tasks.hasError) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(height: 1),
          const SizedBox(height: 20),
          _LoadStatus(
            value: tasks,
            errorText: context.l10n.failedToLoadTasks,
            onRetry: () => ref.read(overdueViewModelProvider.notifier).retry(),
          ),
          if (count > 0)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      LucideIcons.timer,
                      size: 18,
                      color: context.appColors.overdue,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        context.l10n.overdueTaskCount(count),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Material(
                  color: context.appColors.overdue.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  child: Semantics(
                    button: true,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => context.push('/browse/overdue'),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(
                              LucideIcons.listChecks,
                              size: 18,
                              color: context.appColors.overdue,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                context.l10n.overdueReview,
                                style: Theme.of(context).textTheme.labelLarge
                                    ?.copyWith(
                                      color: context.appColors.overdue,
                                    ),
                              ),
                            ),
                            Icon(
                              LucideIcons.arrowRight,
                              size: 16,
                              color: context.appColors.overdue,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class OverdueTasksScreen extends ConsumerWidget {
  const OverdueTasksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overdue = ref.watch(overdueViewModelProvider);
    final ids = {
      for (final task in overdue.value ?? const <TaskItem>[]) task.id,
    };
    return TaskListView(
      title: context.l10n.overdueTitle,
      query: const TaskQuery.all(),
      taskFilter: (task) => ids.contains(task.id),
      showQuickAdd: false,
      emptyMessage: context.l10n.overdueEmpty,
      headerAddon: Builder(
        builder: (context) {
          final selection = TaskSelectionScope.maybeOf(context)!;
          return Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              ShadButton.ghost(
                leading: const Icon(LucideIcons.arrowLeft, size: 16),
                onPressed: () =>
                    context.canPop() ? context.pop() : context.go('/browse'),
                child: Text(context.l10n.browseTitle),
              ),
              ShadButton.ghost(
                onPressed: ids.isEmpty
                    ? null
                    : () => selection.retainVisible(ids),
                child: Text(context.l10n.taskSelectAll),
              ),
            ],
          );
        },
      ),
    );
  }
}
