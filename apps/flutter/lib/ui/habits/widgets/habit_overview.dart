import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:pomodoist/domain/models/habits/habit_models.dart';
import 'package:pomodoist/domain/models/notifications/habit_reminder_status.dart';
import 'package:pomodoist/routing/habit_detail_navigation.dart';
import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/themes/app_motion.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/core/widgets/app_action_menu.dart';
import 'package:pomodoist/ui/habits/view_models/habits_view_model.dart';
import 'package:pomodoist/ui/habits/widgets/habit_icon.dart';

String habitDayPeriodLabel(BuildContext context, HabitDayPeriod period) {
  final l = context.l10n;
  return switch (period) {
    HabitDayPeriod.automatic => l.habitPeriodAutomatic,
    HabitDayPeriod.anytime => l.habitPeriodAnytime,
    HabitDayPeriod.morning => l.calendarMorning,
    HabitDayPeriod.afternoon => l.calendarAfternoon,
    HabitDayPeriod.evening => l.calendarEvening,
    HabitDayPeriod.night => l.habitPeriodNight,
  };
}

String habitScheduleLabel(BuildContext context, HabitDayRow row, DateTime day) {
  final schedule = row.habit.scheduleFor(day) ?? row.habit.scheduleHistory.last;
  final weekdays = schedule.weekdays.length == 7
      ? context.l10n.habitDaily
      : schedule.weekdays
            .map(
              (d) => DateFormat.E(context.l10n.localeName).format(
                DateTime(day.year, day.month, day.day - day.weekday + d),
              ),
            )
            .join(', ');
  return [if (row.project != null) row.project!.name, weekdays].join(' · ');
}

class HabitOverview extends ConsumerWidget {
  const HabitOverview({
    this.onClose,
    super.key = const ValueKey('habit-overview'),
  });
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(habitsViewModelProvider);
    final row = view.selectedRow;
    final vm = ref.read(habitsViewModelProvider.notifier);
    final l = context.l10n, colors = context.appColors;
    if (row == null) return const SizedBox.shrink();
    final ratio = (row.count / row.target).clamp(0.0, 1.0);
    final date = DateFormat.MMMd(l.localeName).format(view.selectedDay);
    void edit() => openHabitDetails(context, row.habit.id);
    final time = row.habit.reminderMinutes;
    return Material(
      color: colors.canvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (onClose != null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: IconButton(
                tooltip: l.commonBack,
                onPressed: onClose,
                icon: const Icon(LucideIcons.arrowLeft),
              ),
            ),
          Expanded(
            child: SingleChildScrollView(
              key: const PageStorageKey('habit-overview-scroll'),
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ShadButton.ghost(
                        width: 64,
                        height: 64,
                        padding: EdgeInsets.zero,
                        enabled: !view.saving,
                        onPressed: () => showHabitIconPicker(
                          context,
                          icon: row.habit.icon,
                          onSave: (icon) => vm.updateIcon(row.habit.id, icon),
                        ),
                        child: Semantics(
                          label: l.habitIcon,
                          child: HabitSign(
                            icon: row.habit.icon,
                            size: 64,
                            circular: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              row.habit.title,
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              habitScheduleLabel(
                                context,
                                row,
                                view.selectedDay,
                              ),
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: colors.mutedText),
                            ),
                          ],
                        ),
                      ),
                      HabitActionsMenu(row: row),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Divider(height: 1),
                  ),
                  Text(
                    l.habitProgressOn(date),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Semantics(
                    label: '${row.count} / ${row.target}',
                    excludeSemantics: true,
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      children: [
                        Text(
                          '${row.count}',
                          style: AppTheme.monoTextStyle.copyWith(
                            fontSize: 56,
                            fontWeight: FontWeight.w600,
                            color: colors.accent,
                          ),
                        ),
                        Text(
                          '/ ${row.target}',
                          style: AppTheme.monoTextStyle.copyWith(
                            fontSize: 48,
                            color: colors.primaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: LinearProgressIndicator(
                          value: ratio,
                          minHeight: 12,
                          borderRadius: BorderRadius.circular(8),
                          color: colors.accent,
                          backgroundColor: colors.surfaceTint,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        NumberFormat.decimalPercentPattern(
                          locale: l.localeName,
                          decimalDigits:
                              ratio * 100 == (ratio * 100).roundToDouble()
                              ? 0
                              : 1,
                        ).format(ratio),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colors.mutedText,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  HabitCheckInButton(row: row, expanded: true),
                  if (view.futureDay)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(l.habitsFuture),
                    ),
                  if (view.actionError)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        l.habitSaveError,
                        style: TextStyle(color: colors.error),
                      ),
                    ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Divider(height: 1),
                  ),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Text(
                        l.habitWeekHistory,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '${DateFormat.MMMd(l.localeName).format(view.weekStart)} – ${DateFormat.yMMMd(l.localeName).format(DateTime(view.weekStart.year, view.weekStart.month, view.weekStart.day + 6))}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.mutedText,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final minWidth =
                          7 *
                          MediaQuery.textScalerOf(
                            context,
                          ).scale(44).clamp(44.0, 100.0);
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: constraints.maxWidth < minWidth
                              ? minWidth
                              : constraints.maxWidth,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final day in row.history)
                                Expanded(
                                  child: _HistoryDay(day: day, view: view),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Divider(height: 1),
                  ),
                  _OverviewAction(
                    icon: LucideIcons.bell,
                    title: l.habitReminder,
                    subtitle: time == null
                        ? l.habitPeriodNoTimeReason
                        : '${habitScheduleLabel(context, row, view.selectedDay)} · ${MaterialLocalizations.of(context).formatTimeOfDay(
                            TimeOfDay(hour: time ~/ 60, minute: time % 60),
                            alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
                          )}',
                    onPressed: view.saving ? null : edit,
                  ),
                  if (view.reminderStatus != HabitReminderStatus.available)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        switch (view.reminderStatus) {
                          HabitReminderStatus.unsupported =>
                            l.habitReminderUnavailable,
                          HabitReminderStatus.denied => l.habitReminderDenied,
                          _ => l.habitReminderFailed,
                        },
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.mutedText,
                        ),
                      ),
                    ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Divider(height: 1),
                  ),
                  _OverviewAction(
                    icon: LucideIcons.pencil,
                    title: l.habitEdit,
                    onPressed: view.saving ? null : edit,
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

class _OverviewAction extends StatelessWidget {
  const _OverviewAction({
    required this.icon,
    required this.title,
    required this.onPressed,
    this.subtitle,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    minVerticalPadding: 12,
    leading: Icon(icon, size: 28),
    title: Text(title),
    subtitle: subtitle == null ? null : Text(subtitle!),
    trailing: const Icon(LucideIcons.chevronRight, size: 18),
    onTap: onPressed,
  );
}

class _HistoryDay extends ConsumerWidget {
  const _HistoryDay({required this.day, required this.view});
  final ({DateTime day, int count, int? target}) day;
  final HabitsViewState view;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors, l = context.l10n;
    final future = day.day.isAfter(view.today), scheduled = day.target != null;
    final selected = day.day == view.selectedDay;
    final ratio = !scheduled || future
        ? 0.0
        : (day.count / day.target!).clamp(0.0, 1.0);
    final label =
        '${DateFormat.yMMMMEEEEd(l.localeName).format(day.day)} · ${future
            ? l.habitsFuture
            : !scheduled
            ? l.habitNotScheduled
            : '${day.count} / ${day.target}'}';
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        selected: selected,
        child: Material(
          color: selected ? colors.accentTint : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            key: ValueKey('habit-week-${habitDayKey(day.day)}'),
            borderRadius: BorderRadius.circular(8),
            onTap: () =>
                ref.read(habitsViewModelProvider.notifier).selectDay(day.day),
            child: ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 2,
                ),
                child: Column(
                  children: [
                    Text(
                      DateFormat.E(l.localeName).format(day.day),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: selected ? colors.accent : colors.mutedText,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('${day.day.day}'),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CircularProgressIndicator(
                            value: ratio,
                            strokeWidth: 2,
                            color: colors.accent,
                            backgroundColor: colors.border,
                          ),
                          if (!future && scheduled && ratio == 1)
                            Icon(
                              LucideIcons.check,
                              size: 14,
                              color: colors.accent,
                            ),
                          if (!scheduled && !future)
                            Icon(
                              LucideIcons.minus,
                              size: 12,
                              color: colors.mutedText,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      future || !scheduled ? '–' : '${day.count}/${day.target}',
                      style: AppTheme.monoTextStyle.copyWith(
                        fontSize: 11,
                        color: colors.mutedText,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class HabitCheckInButton extends ConsumerWidget {
  const HabitCheckInButton({
    required this.row,
    this.expanded = false,
    this.round = false,
    super.key,
  });
  final HabitDayRow row;
  final bool expanded;
  final bool round;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(habitsViewModelProvider);
    final vm = ref.read(habitsViewModelProvider.notifier);
    final colors = context.appColors, l = context.l10n;
    final enabled = row.canAdd && !view.saving;
    final icon = row.complete ? LucideIcons.check : LucideIcons.plus;
    final label = row.complete ? l.habitsDone : l.habitCheckIn;
    if (row.actionPeriod == null && row.targets.length > 1) {
      return LayoutBuilder(
        builder: (context, constraints) => DecoratedBox(
          decoration: BoxDecoration(
            color: (expanded || round) && enabled
                ? colors.accentFill
                : Colors.transparent,
            shape: round ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: round ? null : BorderRadius.circular(8),
          ),
          child: SizedBox(
            height: round ? 56 : null,
            child: Center(
              child: AppActionMenu(
                tooltip: l.habitAddCheckIn,
                enabled: enabled,
                width: expanded
                    ? constraints.maxWidth
                    : round
                    ? 56
                    : 44,
                items: [
                  for (final e in row.targets.entries)
                    ShadContextMenuItem(
                      enabled: (row.periodCounts[e.key] ?? 0) < e.value,
                      onPressed: () =>
                          vm.addCheckIn(row.habit.id, period: e.key),
                      child: Text(
                        '${habitDayPeriodLabel(context, e.key)} · ${l.habitsRemaining}: ${e.value - (row.periodCounts[e.key] ?? 0)}',
                      ),
                    ),
                ],
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      color: (expanded || round) && enabled
                          ? colors.onAccent
                          : colors.accent,
                      size: 22,
                    ),
                    if (expanded) ...[
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          label,
                          style: TextStyle(
                            color: enabled ? colors.onAccent : colors.mutedText,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    void add() => vm.addCheckIn(
      row.habit.id,
      period: row.actionPeriod ?? row.targets.keys.single,
    );
    if (expanded) {
      return ShadButton(
        enabled: enabled,
        onPressed: add,
        leading: Icon(icon, size: 22),
        child: Text(label),
      );
    }
    if (round) {
      return IconButton.filled(
        tooltip:
            '${row.habit.title}, ${row.complete ? l.habitsDone : l.habitAddCheckIn}',
        onPressed: enabled ? add : null,
        style: IconButton.styleFrom(
          minimumSize: const Size.square(56),
          shape: const CircleBorder(),
          backgroundColor: colors.accentFill,
          foregroundColor: colors.onAccent,
          disabledBackgroundColor: colors.surfaceTint,
          disabledForegroundColor: colors.mutedText,
        ),
        icon: Icon(icon, size: 28),
      );
    }
    return Tooltip(
      message: row.complete ? l.habitsDone : l.habitAddCheckIn,
      child: ShadButton.outline(
        width: 44,
        height: 44,
        padding: EdgeInsets.zero,
        enabled: enabled,
        onPressed: add,
        backgroundColor: row.complete ? colors.accentFill : null,
        child: Icon(
          icon,
          size: 22,
          color: row.complete ? colors.onAccent : colors.primaryText,
        ),
      ),
    );
  }
}

class HabitActionsMenu extends ConsumerWidget {
  const HabitActionsMenu({required this.row, this.vertical = false, super.key});
  final HabitDayRow row;
  final bool vertical;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(habitsViewModelProvider);
    final vm = ref.read(habitsViewModelProvider.notifier);
    final l = context.l10n;
    return AppActionMenu(
      tooltip: l.habitEdit,
      enabled: !view.saving,
      width: 44,
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
          onPressed: () => showHabitIconPicker(
            context,
            icon: row.habit.icon,
            onSave: (icon) => vm.updateIcon(row.habit.id, icon),
          ),
          child: Text(l.habitIcon),
        ),
        ShadContextMenuItem(
          onPressed: () async {
            final confirmed = await showDialog<bool>(
              context: context,
              animationStyle: AnimationStyle(
                duration: AppMotion.duration(context, AppMotion.popup),
                reverseDuration: AppMotion.duration(context, AppMotion.popup),
                curve: AppMotion.curve,
              ),
              builder: (context) => AlertDialog(
                title: Text(l.habitDeleteConfirm),
                content: Text(row.habit.title),
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
            if (confirmed != true || !context.mounted) return;
            final success = await vm.deleteHabit(row.habit.id);
            if (success &&
                context.mounted &&
                GoRouter.of(context).state.uri.queryParameters['habit'] ==
                    row.habit.id) {
              closeHabitDetails(context);
            }
          },
          child: Text(l.commonDelete),
        ),
      ],
      child: Icon(
        vertical ? LucideIcons.ellipsisVertical : LucideIcons.ellipsis,
      ),
    );
  }
}
