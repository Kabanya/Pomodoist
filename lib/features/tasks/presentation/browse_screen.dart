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

import '../../../app/account_providers.dart';
import '../../../app/app_l10n.dart';
import '../../../app/formatters.dart';
import '../../../app/providers.dart';
import '../../../app/theme/app_motion.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/db/app_database.dart' show inboxProjectId;
import '../../../core/sync/pomodoist_retention.dart';
import '../../billing/billing.dart';
import '../domain/task_models.dart';
import 'browse_summary.dart';
import 'project_list_data.dart';
import 'widgets/create_project_dialog.dart';
import 'widgets/project_context_menu.dart';
import 'widgets/project_icon.dart';
import 'widgets/task_list_view.dart';

class BrowseScreen extends ConsumerStatefulWidget {
  const BrowseScreen({super.key});

  @override
  ConsumerState<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends ConsumerState<BrowseScreen> {
  BrowsePeriod _period = BrowsePeriod.today;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final summary = ref.watch(productivitySummaryProvider);
    final item = summary.hasValue
        ? browseSummary(summary.value!, _period)
        : null;
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
                            onPressed: () => context.go('/settings'),
                            child: Text(l10n.account),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  _SectionHeading(
                    title: l10n.productivityTitle,
                    action: Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        IntrinsicWidth(
                          child: ShadTabs<BrowsePeriod>(
                            value: _period,
                            onChanged: (value) =>
                                setState(() => _period = value),
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
                        ShadButton.ghost(
                          onPressed: () => context.go('/reports'),
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
                    onRetry: () => ref.invalidate(productivitySummaryProvider),
                  ),
                  const SizedBox(height: 20),
                  AnimatedSwitcher(
                    duration: AppMotion.duration(context, AppMotion.state),
                    switchInCurve: AppMotion.curve,
                    switchOutCurve: AppMotion.curve,
                    child: LayoutBuilder(
                      key: ValueKey(_period),
                      builder: (context, constraints) {
                        final columns = constraints.maxWidth >= 640 ? 4 : 2;
                        final width =
                            (constraints.maxWidth - (columns - 1) * 16) /
                            columns;
                        return Wrap(
                          spacing: 16,
                          runSpacing: 20,
                          children: [
                            _Metric(
                              width: width,
                              label: l10n.completedTasks,
                              value: item?.completedTasks.toString() ?? '—',
                            ),
                            _Metric(
                              width: width,
                              label: l10n.focusIntervals,
                              value: item?.focusIntervals.toString() ?? '—',
                            ),
                            _Metric(
                              width: width,
                              label: l10n.focusTime,
                              value: item == null
                                  ? '—'
                                  : formatFocusTime(context, item.focusSeconds),
                            ),
                            _Metric(
                              width: width,
                              label: l10n.browseOpenNow,
                              value: item?.openTasks.toString() ?? '—',
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 28),
                  const Divider(height: 1),
                  const SizedBox(height: 24),
                  LayoutBuilder(
                    builder: (context, constraints) =>
                        constraints.maxWidth >= 960
                        ? const Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: _BrowseProjects()),
                              SizedBox(width: 32),
                              SizedBox(width: 280, child: _BrowseSecondary()),
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
    final projects = ref.watch(projectsProvider);
    const query = TaskQuery.all();
    final tasks = ref.watch(tasksByQueryProvider(query));
    final counts = tasks.hasValue
        ? countOpenTasksByProject(tasks.value!)
        : null;
    final rows = projectRows([
      for (final project in projects.value ?? const <ProjectItem>[])
        if (project.id != inboxProjectId &&
            !project.isArchived &&
            !project.isDeleted)
          project,
    ]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeading(
          title: l10n.navProjects,
          action: ShadButton.ghost(
            leading: const Icon(LucideIcons.plus, size: 16),
            onPressed: () => showCreateProjectDialog(context),
            child: Text(l10n.newProject),
          ),
        ),
        _LoadStatus(
          value: projects,
          errorText: l10n.failedToLoadProjects,
          onRetry: () => ref.invalidate(projectsProvider),
        ),
        _LoadStatus(
          value: tasks,
          errorText: l10n.failedToLoadTasks,
          onRetry: () => ref.invalidate(tasksByQueryProvider(query)),
        ),
        const SizedBox(height: 8),
        if (projects.hasValue && rows.isEmpty)
          Text(l10n.noProjects, style: Theme.of(context).textTheme.bodyMedium),
        for (final row in rows)
          Padding(
            padding: EdgeInsetsDirectional.only(start: row.depth * 20.0),
            child: ProjectContextMenu(
              key: ValueKey('browse-project-${row.project.id}'),
              project: row.project,
              showMenuButton: true,
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  hoverColor: context.appColors.surfaceHover,
                  focusColor: context.appColors.accentTint,
                  hoverDuration: AppMotion.duration(context, AppMotion.hover),
                  onTap: () => context.go('/project/${row.project.id}'),
                  child: SizedBox(
                    height: 48,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: [
                          ProjectIconView(project: row.project, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              row.project.name,
                              maxLines: 1,
                              textAlign: TextAlign.start,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w500),
                            ),
                          ),
                          const SizedBox(width: 12),
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
    final labels = ref.watch(labelsProvider);
    final items = labels.value ?? const <LabelItem>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeading(
          title: l10n.labelsTitle,
          action: Tooltip(
            message: l10n.newLabel,
            child: ShadIconButton.ghost(
              width: 36,
              height: 36,
              icon: const Icon(LucideIcons.plus, size: 18),
              onPressed: () => showCreateLabelDialog(context),
            ),
          ),
        ),
        _LoadStatus(
          value: labels,
          errorText: l10n.failedToLoadLabels,
          onRetry: () => ref.invalidate(labelsProvider),
        ),
        const SizedBox(height: 8),
        if (labels.hasValue && items.isEmpty)
          Text(l10n.noLabels, style: Theme.of(context).textTheme.bodyMedium),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final label in items)
              Material(
                type: MaterialType.transparency,
                child: Chip(
                  avatar: const Icon(LucideIcons.tag, size: 14),
                  label: Text(
                    '@${label.name}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 24),
        const Divider(height: 1),
        const SizedBox(height: 16),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: ShadButton.ghost(
            key: const Key('browse-completed-tasks'),
            onPressed: () => context.go('/browse/completed'),
            leading: const Icon(LucideIcons.circleCheck, size: 18),
            trailing: const Icon(LucideIcons.arrowRight, size: 16),
            child: Text(l10n.completedTasks),
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
    final pending = ref.watch(pendingSyncCommandsProvider);
    final count = pending.hasValue ? pending.value!.length : null;
    final description = pending.hasError
        ? l10n.browseQueueUnavailable
        : pending.isLoading
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
              _LoadStatus(
                value: pending,
                errorText: (_) => l10n.browseQueueUnavailable,
                onRetry: () => ref.invalidate(pendingSyncCommandsProvider),
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
            pending.hasError ? LucideIcons.cloudAlert : LucideIcons.cloudUpload,
            size: 16,
            color: pending.hasError
                ? context.appColors.error
                : context.appColors.secondaryText,
          ),
          child: Text(pending.isLoading ? '…' : count?.toString() ?? '—'),
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
    required this.label,
    required this.value,
  });

  final double width;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.merge(AppTheme.monoTextStyle),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.appColors.secondaryText,
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
    final accountOverview = ref.watch(accountOverviewProvider);
    final billing = ref.watch(billingControllerProvider);
    final completedTaskCutoff = accountOverview.hasValue && !billing.loading
        ? pomodoistTaskHistoryCutoff(
            accountOverview.value,
            hasLocalPaidEntitlement: billing.hasActiveEntitlement,
          )
        : null;
    return TaskListView(
      title: context.l10n.completedTasks,
      query: const TaskQuery.completed(),
      showQuickAdd: false,
      taskFilter: completedTaskCutoff == null
          ? null
          : (task) => !(task.completedAt ?? task.updatedAt).toUtc().isBefore(
              completedTaskCutoff,
            ),
    );
  }
}
