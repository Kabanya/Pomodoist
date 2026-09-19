import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:pomodoist/ui/core/localization/formatters.dart';
import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/planning/view_models/today_view_model.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/core/widgets/mini_focus_player.dart';
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
    return TaskListView(
      title: l10n.navToday,
      subtitle: MaterialLocalizations.of(context).formatFullDate(today),
      query: query,
      emptyMessage: hasCompleted ? l10n.todayEmptyCompletedTitle : null,
      emptyDescription: hasCompleted
          ? l10n.todayEmptyCompletedDescription
          : null,
      headerAddon: _TodayContext(query: query),
      footerAddon: _CompletedToday(day: today),
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
    final showFocus = viewState.showFocus;
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
        if (showFocus) ...[
          if (showSummary) const SizedBox(height: 12),
          const MiniFocusPlayer(dailyContext: true),
        ],
      ],
    );
  }
}

class _CompletedToday extends ConsumerWidget {
  const _CompletedToday({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(completedTodayViewModelProvider(day));
    if (tasks.isEmpty) {
      return const SizedBox.shrink();
    }
    return TaskSelectionRegion(
      scopeKey: ('completed-today', day),
      shrinkWrap: true,
      visibleTasks: tasks,
      child: ExpansionTile(
        key: ValueKey(day),
        title: Text(context.l10n.todayCompletedTasks(tasks.length)),
        initiallyExpanded: false,
        children: [
          for (var index = 0; index < tasks.length; index++) ...[
            if (index > 0) const TaskListDivider(),
            TaskListItem(task: tasks[index]),
          ],
        ],
      ),
    );
  }
}
