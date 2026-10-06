import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:pomodoist/domain/models/habits/habit_models.dart';
import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/core/themes/app_motion.dart';
import 'package:pomodoist/ui/core/widgets/app_action_menu.dart';
import 'package:go_router/go_router.dart';
import 'package:pomodoist/routing/habit_detail_navigation.dart';
import 'package:pomodoist/ui/habits/view_models/habits_view_model.dart';
import 'package:pomodoist/ui/habits/widgets/habit_editor.dart';
import 'package:pomodoist/ui/habits/widgets/habit_icon.dart';

class HabitsScreen extends ConsumerStatefulWidget {
  const HabitsScreen({super.key});
  @override
  ConsumerState<HabitsScreen> createState() => _HabitsScreenState();
}

class _HabitsScreenState extends ConsumerState<HabitsScreen> {
  Future<void> _delete(Habit habit) async {
    final l = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      animationStyle: AnimationStyle(
        duration: AppMotion.duration(context, AppMotion.popup),
        reverseDuration: AppMotion.duration(context, AppMotion.popup),
        curve: AppMotion.curve,
      ),
      builder: (context) => AlertDialog(
        title: Text(l.habitDeleteConfirm),
        content: Text(habit.title),
        actions: [
          ShadButton.ghost(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.commonCancel),
          ),
          ShadButton.destructive(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      final success = await ref
          .read(habitsViewModelProvider.notifier)
          .deleteHabit(habit.id);
      if (success &&
          mounted &&
          GoRouter.of(context).state.uri.queryParameters['habit'] == habit.id) {
        closeHabitDetails(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(habitsViewModelProvider),
        vm = ref.read(habitsViewModelProvider.notifier),
        l = context.l10n;
    final colors = context.appColors;
    return SafeArea(
      bottom: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: EdgeInsets.all(constraints.maxWidth < 600 ? 16 : 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 16,
                  runSpacing: 12,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      l.navHabits,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    ShadButton(
                      enabled: !view.saving,
                      onPressed: () => openHabitDetails(context, null),
                      leading: const Icon(LucideIcons.plus, size: 18),
                      child: Text(l.habitNew),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                LayoutBuilder(
                  builder: (context, space) {
                    final calendar = _calendar(context, view, vm);
                    final summary = _summary(context, view);
                    return space.maxWidth >= 700
                        ? Row(
                            children: [
                              Expanded(child: calendar),
                              const SizedBox(width: 24),
                              SizedBox(width: 180, child: summary),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              calendar,
                              const SizedBox(height: 16),
                              summary,
                            ],
                          );
                  },
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: Text(l.habitsActive),
                          selected: !view.finished,
                          onSelected: (_) => vm.showFinished(false),
                        ),
                        ChoiceChip(
                          label: Text(l.habitsFinished),
                          selected: view.finished,
                          onSelected: (_) => vm.showFinished(true),
                        ),
                      ],
                    ),
                    if (!view.finished)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            label: Text(l.habitsListView),
                            selected: view.viewMode == HabitViewMode.list,
                            side: BorderSide(
                              color: view.viewMode == HabitViewMode.list
                                  ? colors.accent
                                  : colors.border,
                            ),
                            onSelected:
                                view.viewSaving || view.viewSettingsLoading
                                ? null
                                : (_) => vm.setViewMode(HabitViewMode.list),
                          ),
                          ChoiceChip(
                            label: Text(l.habitsRhythmView),
                            selected: view.viewMode == HabitViewMode.rhythm,
                            side: BorderSide(
                              color: view.viewMode == HabitViewMode.rhythm
                                  ? colors.accent
                                  : colors.border,
                            ),
                            onSelected:
                                view.viewSaving || view.viewSettingsLoading
                                ? null
                                : (_) => vm.setViewMode(HabitViewMode.rhythm),
                          ),
                        ],
                      ),
                  ],
                ),
                if (view.viewError)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      children: [
                        Text(
                          l.habitsViewPreferenceError,
                          style: TextStyle(color: colors.error),
                        ),
                        ShadButton.ghost(
                          onPressed: view.viewSaving ? null : vm.retryViewMode,
                          child: Text(l.commonRetry),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                if (view.futureDay)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      l.habitsFuture,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: colors.mutedText),
                    ),
                  ),
                if (view.loading)
                  const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (view.loadError)
                  Column(
                    children: [
                      Text(l.habitLoadError),
                      ShadButton.ghost(
                        onPressed: vm.retry,
                        child: Text(l.commonRetry),
                      ),
                    ],
                  )
                else if (view.rows.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Column(
                      children: [
                        Icon(
                          LucideIcons.repeat2,
                          size: 32,
                          color: colors.mutedText,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          view.finished ? l.habitsFinishedEmpty : l.habitsEmpty,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                else if (view.finished)
                  for (final row in view.rows) _row(context, row, view)
                else if (view.viewMode == HabitViewMode.list) ...[
                  if (view.remainingRows.isNotEmpty) ...[
                    _section(
                      context,
                      view.futureDay ? l.habitsPlanned : l.habitsRemaining,
                      '${view.remainingRows.length}',
                    ),
                    for (final row in view.remainingRows)
                      _row(context, row, view),
                  ],
                  if (view.completedRows.isNotEmpty) ...[
                    _section(
                      context,
                      l.habitsDone,
                      '${view.completedRows.length}',
                    ),
                    for (final row in view.completedRows)
                      _row(context, row, view),
                  ],
                ] else
                  for (final group in view.rhythmGroups)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: BorderDirectional(
                            start: BorderSide(color: colors.border),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsetsDirectional.only(start: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _section(
                                context,
                                habitDayPeriodLabel(context, group.period),
                                '${group.rows.where((r) => r.complete).length} / ${group.rows.length}',
                              ),
                              for (final row in group.rows)
                                _row(context, row, view),
                            ],
                          ),
                        ),
                      ),
                    ),
                if (view.actionError)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      l.habitSaveError,
                      style: TextStyle(color: colors.error),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _calendar(
    BuildContext context,
    HabitsViewState view,
    HabitsViewModel vm,
  ) {
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.spaceBetween,
          children: [
            Text(
              DateFormat.yMMMM(l.localeName).format(view.selectedDay),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ShadButton.ghost(
                  onPressed: vm.selectToday,
                  child: Text(l.today),
                ),
                IconButton(
                  tooltip: l.habitPreviousWeek,
                  onPressed: () => vm.moveWeek(-1),
                  icon: const Icon(LucideIcons.chevronLeft, size: 18),
                ),
                IconButton(
                  tooltip: l.habitNextWeek,
                  onPressed: () => vm.moveWeek(1),
                  icon: const Icon(LucideIcons.chevronRight, size: 18),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, space) {
            final minimumWidth =
                MediaQuery.textScalerOf(
                  context,
                ).scale(44).clamp(44, double.infinity).toDouble() *
                7;
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: space.maxWidth < minimumWidth
                    ? minimumWidth
                    : space.maxWidth,
                child: Row(
                  children: [
                    for (var i = 0; i < 7; i++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: _day(
                            context,
                            DateTime(
                              view.weekStart.year,
                              view.weekStart.month,
                              view.weekStart.day + i,
                            ),
                            view,
                            vm,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _summary(BuildContext context, HabitsViewState view) {
    final colors = context.appColors, l = context.l10n;
    return Semantics(
      label: l.habitsSummary(view.completed, view.planned),
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${view.completed} / ${view.planned}',
            style: AppTheme.monoTextStyle.copyWith(
              fontSize: 24,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            l.habitsCompletedLabel,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.mutedText),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: view.planned == 0 ? 0 : view.completed / view.planned,
            minHeight: 4,
            borderRadius: BorderRadius.circular(4),
            color: colors.accent,
            backgroundColor: colors.surfaceTint,
          ),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String title, String count) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleSmall),
        ),
        const SizedBox(width: 12),
        Text(
          count,
          style: AppTheme.monoTextStyle.copyWith(
            fontSize: 12,
            color: context.appColors.mutedText,
          ),
        ),
      ],
    ),
  );

  Widget _day(
    BuildContext context,
    DateTime day,
    HabitsViewState view,
    HabitsViewModel vm,
  ) {
    final selected = day == view.selectedDay;
    final colors = context.appColors;
    return Semantics(
      selected: selected,
      label: DateFormat.yMMMMEEEEd(context.l10n.localeName).format(day),
      child: Material(
        color: selected ? colors.accentTint : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => vm.selectDay(day),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                Text(
                  DateFormat.E(context.l10n.localeName).format(day),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: selected ? colors.accent : colors.mutedText,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${day.day}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: selected ? colors.accent : null,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: day == view.today
                        ? colors.accent
                        : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, HabitDayRow row, HabitsViewState view) {
    final vm = ref.read(habitsViewModelProvider.notifier), l = context.l10n;
    final colors = context.appColors;
    final complete = row.complete;
    final schedule = row.habit.scheduleFor(view.selectedDay);
    final metadata = <String>[
      if (row.project != null) row.project!.name,
      if (row.actionPeriod == null && row.targets.length > 1)
        for (final e in row.targets.entries)
          '${habitDayPeriodLabel(context, e.key)} ${row.periodCounts[e.key] ?? 0}/${e.value}',
      if (schedule != null)
        schedule.weekdays.length == 7
            ? l.habitDaily
            : schedule.weekdays
                  .map(
                    (weekday) => DateFormat.E(l.localeName).format(
                      DateTime(
                        view.weekStart.year,
                        view.weekStart.month,
                        view.weekStart.day + weekday - 1,
                      ),
                    ),
                  )
                  .join(', '),
      if (row.habit.reminderMinutes != null)
        '${l.habitReminderTime}: ${MaterialLocalizations.of(context).formatTimeOfDay(
          TimeOfDay(hour: row.habit.reminderMinutes! ~/ 60, minute: row.habit.reminderMinutes! % 60),
          alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
        )}',
    ];
    return Container(
      key: ValueKey((row.habit.id, row.actionPeriod)),
      padding: EdgeInsets.symmetric(vertical: complete ? 12 : 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          HabitIconButton(
            icon: row.habit.icon,
            onPressed: view.saving
                ? null
                : () => showHabitIconPicker(
                    context,
                    icon: row.habit.icon,
                    onSave: (icon) => vm.updateIcon(row.habit.id, icon),
                  ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.habit.title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: complete ? colors.mutedText : colors.primaryText,
                  ),
                ),
                if (metadata.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      metadata.join(' · '),
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: colors.mutedText),
                    ),
                  ),
                if (!complete) ...[
                  const SizedBox(height: 8),
                  Semantics(
                    label: l.habitHistory,
                    child: Row(
                      children: [
                        for (final day in row.history)
                          Flexible(
                            child: Padding(
                              padding: const EdgeInsetsDirectional.only(end: 4),
                              child: _historyDay(context, day, view.today),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 64,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${row.count} / ${row.target}',
                  style: AppTheme.monoTextStyle.copyWith(
                    fontSize: 12,
                    color: complete ? colors.accent : colors.mutedText,
                  ),
                ),
                if (row.target > 1 && !complete) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: row.count / row.target,
                    minHeight: 4,
                    borderRadius: BorderRadius.circular(4),
                    color: colors.accent,
                    backgroundColor: colors.surfaceTint,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 4),
          if (row.actionPeriod == null && row.targets.length > 1)
            PopupMenuButton<HabitDayPeriod>(
              tooltip: l.habitAddCheckIn,
              enabled: row.canAdd && !view.saving,
              icon: Icon(
                complete ? LucideIcons.circleCheck : LucideIcons.circlePlus,
                color: complete ? colors.accent : colors.mutedText,
                size: 24,
              ),
              onSelected: (period) =>
                  vm.addCheckIn(row.habit.id, period: period),
              itemBuilder: (context) => [
                for (final e in row.targets.entries)
                  PopupMenuItem(
                    value: e.key,
                    enabled: (row.periodCounts[e.key] ?? 0) < e.value,
                    child: Text(
                      '${habitDayPeriodLabel(context, e.key)} · ${row.periodCounts[e.key] ?? 0} / ${e.value}',
                    ),
                  ),
              ],
            )
          else
            IconButton(
              tooltip: l.habitAddCheckIn,
              onPressed: row.canAdd && !view.saving
                  ? () => vm.addCheckIn(row.habit.id, period: row.actionPeriod)
                  : null,
              icon: Icon(
                complete ? LucideIcons.circleCheck : LucideIcons.circlePlus,
                color: complete ? colors.accent : colors.mutedText,
                size: 24,
              ),
            ),
          AppActionMenu(
            tooltip: l.habitEdit,
            enabled: !view.saving,
            items: [
              ShadContextMenuItem(
                enabled: row.canUndo,
                onPressed: () =>
                    vm.undoCheckIn(row.habit.id, period: row.actionPeriod),
                child: Text(l.habitUndoCheckIn),
              ),
              ShadContextMenuItem(
                onPressed: () => openHabitDetails(context, row.habit.id),
                child: Text(l.habitEdit),
              ),
              ShadContextMenuItem(
                onPressed: () => _delete(row.habit),
                child: Text(l.commonDelete),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _historyDay(
    BuildContext context,
    ({DateTime day, int count, int? target}) day,
    DateTime today,
  ) {
    final colors = context.appColors, l = context.l10n;
    final future = day.day.isAfter(today);
    final complete = day.target != null && day.count >= day.target!;
    final partial = day.count > 0 && !complete;
    final date = DateFormat.yMMMMEEEEd(l.localeName).format(day.day);
    final label =
        '$date · ${future
            ? l.habitsFuture
            : day.target == null
            ? l.habitNotScheduled
            : '${day.count} / ${day.target}'}';
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Semantics(
        label: label,
        child: SizedBox(
          width: 32,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 16,
                height: 6,
                decoration: BoxDecoration(
                  color: future || day.target == null
                      ? Colors.transparent
                      : complete
                      ? colors.accent
                      : partial
                      ? colors.accentTint
                      : colors.border,
                  borderRadius: BorderRadius.circular(2),
                  border: future || day.target == null || partial
                      ? Border.all(
                          color: partial ? colors.accent : colors.border,
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 4),
              ExcludeSemantics(
                child: Text(
                  DateFormat.E(l.localeName).format(day.day),
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: colors.mutedText),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
