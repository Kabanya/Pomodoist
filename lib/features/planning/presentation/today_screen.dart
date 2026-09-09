import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/formatters.dart';
import '../../../app/app_l10n.dart';
import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/mini_focus_player.dart';
import '../../tasks/domain/task_models.dart';
import '../../tasks/presentation/widgets/task_list_item.dart';
import '../../tasks/presentation/widgets/task_list_view.dart';
import '../../tasks/presentation/widgets/task_selection_region.dart';
import 'today_tasks.dart';

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clock = ref.watch(clockProvider);
    final today = ref.watch(
      focusTickerProvider.select((ticker) {
        final now = (ticker.value ?? clock.now()).toLocal();
        return DateTime(now.year, now.month, now.day);
      }),
    );
    final l10n = context.l10n;
    final query = TaskQuery(kind: TaskQueryKind.today, now: today);
    final completed = ref.watch(
      tasksByQueryProvider(const TaskQuery.completed()),
    );
    final hasCompleted = completedTasksForDay(
      completed.value ?? const [],
      today,
    ).isNotEmpty;
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
    final tasks = ref.watch(tasksByQueryProvider(query));
    final summary = ref.watch(productivitySummaryProvider);
    final showFocus = ref.watch(todayFocusStripVisibleProvider);
    final data = summary.value;
    final showSummary =
        !tasks.isLoading &&
        !tasks.hasError &&
        tasks.value != null &&
        !summary.isLoading &&
        !summary.hasError &&
        data != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showSummary)
          Text(
            context.l10n.todayTaskSummary(
              tasks.value!.length,
              data.plannedFocusIntervals,
              formatFocusTime(context, data.totalFocusSeconds),
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
    final completed = ref.watch(
      tasksByQueryProvider(const TaskQuery.completed()),
    );
    final tasks = completedTasksForDay(completed.value ?? const [], day);
    if (completed.isLoading || completed.hasError || tasks.isEmpty) {
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
