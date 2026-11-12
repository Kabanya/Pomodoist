import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons, ShadSwitch;
import 'package:pomodoist/ui/core/themes/app_motion.dart';
import 'package:pomodoist/ui/core/widgets/compact_shell_layout.dart';
import 'package:pomodoist/ui/tasks/widgets/task_blocking_controls.dart';
import 'package:pomodoist/ui/tasks/view_models/task_branch_rows.dart';
import 'package:pomodoist/ui/tasks/view_models/task_branch_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:pomodoist/ui/core/localization/formatters.dart';
import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/planning/view_models/today_view_model.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/ui/tasks/widgets/task_list_item.dart';
import 'package:pomodoist/ui/tasks/widgets/task_list_view.dart';
import 'package:pomodoist/ui/tasks/widgets/task_selection_region.dart';

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewState = ref.watch(todayViewModelProvider);
    final today = viewState.day;
    final l10n = context.l10n;
    final query = TaskQuery(kind: TaskQueryKind.today, now: today);
    final hasCompleted = viewState.hasCompleted;
    final compact = usesCompactMobileLayout(context);
    final showDetails = compact && ref.watch(todayTaskDetailsProvider);
    final shellHeading = compact && CompactShellHeading.isShown(context);
    final dates = MaterialLocalizations.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: TaskListView(
          title: l10n.navToday,
          subtitle: shellHeading
              ? null
              : compact
              ? dates.formatMediumDate(today)
              : dates.formatFullDate(today),
          subtitleSemanticsLabel: compact ? dates.formatFullDate(today) : null,
          query: query,
          emptyMessage: hasCompleted ? l10n.todayEmptyCompletedTitle : null,
          emptyDescription: hasCompleted
              ? l10n.todayEmptyCompletedDescription
              : null,
          showQuickAdd: !compact,
          quietToday: compact,
          showTodayDetails: showDetails,
          titleTrailing: compact && !CompactShellHeading.isShown(context)
              ? const TodayOptionsButton()
              : null,
          headerAddon: compact ? null : _TodayContext(query: query),
          footerAddon: _CompletedToday(
            day: today,
            compact: compact,
            showDetails: showDetails,
          ),
        ),
      ),
    );
  }
}

class TodayShellTitle extends ConsumerWidget {
  const TodayShellTitle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final day = ref.watch(todayViewModelProvider.select((state) => state.day));
    final dates = MaterialLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final locale = context.l10n.localeName;
    final dateStyle = textTheme.bodySmall?.copyWith(
      color: context.appColors.secondaryText,
      height: 1,
    );
    return LayoutBuilder(
      builder: (context, constraints) => Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsetsDirectional.only(end: 4),
              child: ExcludeSemantics(
                child: Text(
                  intl.DateFormat.E(locale).format(day),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: dateStyle,
                ),
              ),
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth * .6),
            child: Semantics(
              header: true,
              label: context.l10n.navToday,
              excludeSemantics: true,
              child: Text(
                context.l10n.navToday,
                key: const Key('shell-page-title'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: textTheme.titleLarge?.copyWith(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsetsDirectional.only(start: 4),
              child: Tooltip(
                message: dates.formatFullDate(day),
                excludeFromSemantics: true,
                child: Semantics(
                  label: dates.formatFullDate(day),
                  excludeSemantics: true,
                  child: Column(
                    key: const Key('today-shell-date'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        dates.formatDecimal(day.day),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        intl.DateFormat.MMM(locale).format(day),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: dateStyle,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TodayOptionsButton extends StatelessWidget {
  const TodayOptionsButton({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final textTheme = Theme.of(context).textTheme;
    return IconButton(
      key: const Key('today-options'),
      tooltip: l10n.taskMore,
      icon: const Icon(LucideIcons.ellipsis),
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        useSafeArea: true,
        isScrollControlled: true,
        showDragHandle: true,
        constraints: const BoxConstraints(minWidth: double.infinity),
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          side: BorderSide(color: context.appColors.border),
        ),
        backgroundColor: context.appColors.surface,
        sheetAnimationStyle: AnimationStyle(
          duration: AppMotion.duration(context, AppMotion.panel),
          reverseDuration: AppMotion.duration(context, AppMotion.panel),
        ),
        builder: (context) => SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Consumer(
              builder: (context, ref, child) {
                final day = ref.watch(
                  todayViewModelProvider.select((state) => state.day),
                );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(l10n.navToday, style: textTheme.titleLarge),
                    const SizedBox(height: 12),
                    _TodayContext(
                      query: TaskQuery(kind: TaskQueryKind.today, now: day),
                    ),
                    const SizedBox(height: 8),
                    const TaskPriorityCascadeControl(),
                    ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48),
                      child: ShadSwitch(
                        key: const Key('today-task-details'),
                        label: Text(l10n.todayShowTaskDetails),
                        value: ref.watch(todayTaskDetailsProvider),
                        onChanged: ref
                            .read(todayTaskDetailsProvider.notifier)
                            .setVisible,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _TodayContext extends ConsumerWidget {
  const _TodayContext({required this.query});

  final TaskQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewState = ref.watch(todayContextViewModelProvider(query));
    final showSummary = viewState.showSummary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showSummary)
          Text(
            context.l10n.todayTaskSummary(
              viewState.tasks,
              viewState.plannedIntervals,
              formatFocusTime(context, viewState.focusSeconds),
            ),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: context.appColors.secondaryText,
            ),
          ),
      ],
    );
  }
}

class _CompletedToday extends ConsumerStatefulWidget {
  const _CompletedToday({
    required this.day,
    required this.compact,
    required this.showDetails,
  });
  final DateTime day;
  final bool compact;
  final bool showDetails;
  @override
  ConsumerState<_CompletedToday> createState() => _CompletedTodayState();
}

class _CompletedTodayState extends ConsumerState<_CompletedToday> {
  bool _expanded = false;
  @override
  void didUpdateWidget(covariant _CompletedToday oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.day != widget.day) _expanded = false;
  }

  @override
  Widget build(BuildContext context) {
    final day = widget.day;
    final tasks = ref.watch(completedTodayViewModelProvider(day));
    const scope = 'today:completed';
    final expansion = ref.watch(taskBranchViewModelProvider(scope));
    final data = ref.watch(taskHierarchyViewModelProvider);
    final rows = visibleTaskRows(
      data.byId.values.toList(),
      tasks,
      expansion: expansion,
    );
    if (tasks.isEmpty) {
      return const SizedBox.shrink();
    }
    return TaskSelectionRegion(
      scopeKey: ('completed-today', day),
      shrinkWrap: true,
      visibleTasks: _expanded
          ? rows.map((row) => row.task)
          : const <TaskItem>[],
      child: ExpansionTile(
        key: ValueKey(day),
        title: Text(context.l10n.todayCompletedTasks(tasks.length)),
        initiallyExpanded: false,
        onExpansionChanged: (value) => setState(() => _expanded = value),
        children: [
          for (var index = 0; index < rows.length; index++) ...[
            if (index > 0)
              TaskListDivider(
                previousDepth: rows[index - 1].depth,
                previousRow: rows[index - 1],
                nextDepth: rows[index].depth,
                nextRow: rows[index],
                quietDay: widget.compact && !widget.showDetails ? day : null,
              ),
            TaskListItem(
              key: ValueKey(rows[index].task.id),
              task: rows[index].task,
              hierarchy: rows[index],
              branchScope: scope,
              depth: rows[index].displayDepth,
              quietDay: widget.compact ? day : null,
              presentation: widget.showDetails
                  ? TaskListItemPresentation.agenda
                  : TaskListItemPresentation.standard,
            ),
          ],
        ],
      ),
    );
  }
}
