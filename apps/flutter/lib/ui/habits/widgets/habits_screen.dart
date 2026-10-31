import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pomodoist/domain/models/habits/habit_models.dart';
import 'package:pomodoist/routing/habit_detail_navigation.dart';
import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/habits/view_models/habits_view_model.dart';
import 'package:pomodoist/ui/habits/widgets/habit_icon.dart';
import 'package:pomodoist/ui/habits/widgets/habit_overview.dart';
import 'package:pomodoist/ui/habits/widgets/habit_presentation.dart';
import 'package:pomodoist/ui/habits/widgets/habits_progress_view.dart';
import 'package:pomodoist/ui/habits/view_models/habit_presentation_view_model.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class HabitsScreen extends ConsumerStatefulWidget {
  const HabitsScreen({super.key});

  @override
  ConsumerState<HabitsScreen> createState() => _HabitsScreenState();
}

class _HabitsScreenState extends ConsumerState<HabitsScreen> {
  // Keep invoking controls focusable after panel reflow or completion regrouping.
  final _progressFocus = <(String, bool), FocusNode>{};
  FocusNode _focusNode(String id, bool ring) =>
      _progressFocus.putIfAbsent((id, ring), FocusNode.new);

  @override
  void dispose() {
    for (final node in _progressFocus.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(habitsViewModelProvider);
    final l = context.l10n, colors = context.appColors;
    final layout = HabitPresentationScope.maybeOf(context);
    final progress = layout?.presentation == HabitPresentation.progress;
    return SafeArea(
      bottom: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final padding = constraints.maxWidth < 600 ? 16.0 : 32.0;
          final editorOpen = GoRouterState.of(
            context,
          ).uri.queryParameters.containsKey('habit');
          final wide = constraints.maxWidth >= 960 && !editorOpen;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(padding, 24, padding, 16),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 16,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.navHabits,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        if (!progress) ...[
                          const SizedBox(height: 4),
                          Text(
                            l.habitsSubtitle,
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(color: colors.mutedText),
                          ),
                        ],
                      ],
                    ),
                    Wrap(
                      spacing: 16,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (layout?.available == true)
                          const HabitPresentationControl(),
                        if (progress) _HabitStatusFilter(view: view),
                        ShadButton(
                          enabled: !view.saving,
                          onPressed: () => openHabitDetails(context, null),
                          leading: const Icon(LucideIcons.plus, size: 20),
                          child: Text(l.habitNew),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: progress
                    ? HabitsProgressView(
                        weekStrip: _WeekStrip(view: view),
                        focusNode: _focusNode,
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              key: const PageStorageKey('habits-list-scroll'),
                              padding: EdgeInsets.fromLTRB(
                                padding,
                                0,
                                wide ? 24 : padding,
                                32,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _WeekStrip(view: view),
                                  const SizedBox(height: 16),
                                  const Divider(height: 1),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                    child: Wrap(
                                      alignment: WrapAlignment.spaceBetween,
                                      spacing: 12,
                                      runSpacing: 8,
                                      children: [
                                        Text(
                                          DateFormat.yMMMEd(
                                            l.localeName,
                                          ).format(view.selectedDay),
                                          style: Theme.of(
                                            context,
                                          ).textTheme.titleMedium,
                                        ),
                                        Text(
                                          l.habitsSummary(
                                            view.completed,
                                            view.planned,
                                          ),
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                                color: colors.mutedText,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  _HabitStatusFilter(view: view),
                                  if (view.futureDay)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 16),
                                      child: Text(
                                        l.habitsFuture,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(color: colors.mutedText),
                                      ),
                                    ),
                                  const SizedBox(height: 20),
                                  if (view.loading)
                                    const Padding(
                                      padding: EdgeInsets.all(40),
                                      child: Center(
                                        child: CircularProgressIndicator(),
                                      ),
                                    )
                                  else if (view.loadError)
                                    Column(
                                      children: [
                                        Text(l.habitLoadError),
                                        ShadButton.ghost(
                                          onPressed: ref
                                              .read(
                                                habitsViewModelProvider
                                                    .notifier,
                                              )
                                              .retry,
                                          child: Text(l.commonRetry),
                                        ),
                                      ],
                                    )
                                  else if (view.rows.isEmpty)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 48,
                                      ),
                                      child: Column(
                                        children: [
                                          Icon(
                                            LucideIcons.repeat2,
                                            size: 32,
                                            color: colors.mutedText,
                                          ),
                                          const SizedBox(height: 16),
                                          Text(
                                            view.finished
                                                ? l.habitsFinishedEmpty
                                                : l.habitsEmpty,
                                            textAlign: TextAlign.center,
                                          ),
                                        ],
                                      ),
                                    )
                                  else if (view.finished)
                                    for (final row in view.rows)
                                      _HabitRow(row: row, view: view)
                                  else
                                    Stack(
                                      children: [
                                        PositionedDirectional(
                                          start: 23,
                                          top: 24,
                                          bottom: 40,
                                          child: Container(
                                            width: 1,
                                            color: colors.border,
                                          ),
                                        ),
                                        Column(
                                          children: [
                                            for (final group
                                                in view.rhythmGroups)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  bottom: 20,
                                                ),
                                                child: Column(
                                                  children: [
                                                    Row(
                                                      children: [
                                                        Container(
                                                          width: 48,
                                                          height: 48,
                                                          decoration:
                                                              BoxDecoration(
                                                                color: colors
                                                                    .canvas,
                                                                shape: BoxShape
                                                                    .circle,
                                                                border: Border.all(
                                                                  color: colors
                                                                      .border,
                                                                ),
                                                              ),
                                                          child: Icon(
                                                            switch (group
                                                                .period) {
                                                              HabitDayPeriod
                                                                  .anytime =>
                                                                LucideIcons
                                                                    .infinity,
                                                              HabitDayPeriod
                                                                  .morning =>
                                                                LucideIcons
                                                                    .sunrise,
                                                              HabitDayPeriod
                                                                  .afternoon =>
                                                                LucideIcons.sun,
                                                              HabitDayPeriod
                                                                  .evening =>
                                                                LucideIcons
                                                                    .moon,
                                                              HabitDayPeriod
                                                                  .night =>
                                                                LucideIcons
                                                                    .moonStar,
                                                              _ =>
                                                                LucideIcons
                                                                    .repeat2,
                                                            },
                                                            size: 24,
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          width: 16,
                                                        ),
                                                        Expanded(
                                                          child: Wrap(
                                                            crossAxisAlignment:
                                                                WrapCrossAlignment
                                                                    .center,
                                                            spacing: 12,
                                                            runSpacing: 4,
                                                            children: [
                                                              Text(
                                                                habitDayPeriodLabel(
                                                                  context,
                                                                  group.period,
                                                                ),
                                                                style: Theme.of(context)
                                                                    .textTheme
                                                                    .titleMedium
                                                                    ?.copyWith(
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w600,
                                                                    ),
                                                              ),
                                                              Text(
                                                                '${group.rows.where((r) => r.complete).length} / ${group.rows.length}',
                                                                style: AppTheme
                                                                    .monoTextStyle
                                                                    .copyWith(
                                                                      fontSize:
                                                                          13,
                                                                      color: colors
                                                                          .mutedText,
                                                                    ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Padding(
                                                      padding:
                                                          EdgeInsetsDirectional.only(
                                                            start:
                                                                constraints
                                                                        .maxWidth <
                                                                    600
                                                                ? 48
                                                                : 64,
                                                          ),
                                                      child: Column(
                                                        children: [
                                                          for (final row
                                                              in group.rows)
                                                            _HabitRow(
                                                              row: row,
                                                              view: view,
                                                            ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                          ],
                                        ),
                                      ],
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
                            ),
                          ),
                          if (wide &&
                              !view.loading &&
                              !view.loadError &&
                              view.selectedRow != null) ...[
                            VerticalDivider(
                              width: 1,
                              thickness: 1,
                              color: colors.border,
                            ),
                            const SizedBox(width: 439, child: HabitOverview()),
                          ],
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _HabitStatusFilter extends ConsumerWidget {
  const _HabitStatusFilter({required this.view});
  final HabitsViewState view;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ChoiceChip(
          label: Text(l.habitsActive),
          selected: !view.finished,
          onSelected: (_) =>
              ref.read(habitsViewModelProvider.notifier).showFinished(false),
        ),
        ChoiceChip(
          label: Text(l.habitsFinished),
          selected: view.finished,
          onSelected: (_) =>
              ref.read(habitsViewModelProvider.notifier).showFinished(true),
        ),
      ],
    );
  }
}

class _HabitRow extends ConsumerWidget {
  const _HabitRow({required this.row, required this.view});
  final HabitDayRow row;
  final HabitsViewState view;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final selected =
        row.habit.id == view.selectedHabitId &&
        (view.finished || row.actionPeriod == view.selectedPeriod);
    void select() => ref
        .read(habitsViewModelProvider.notifier)
        .selectHabit(row.habit.id, period: row.actionPeriod);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Semantics(
        button: true,
        explicitChildNodes: true,
        label: row.habit.title,
        selected: selected,
        onTap: select,
        child: Material(
          color: selected ? colors.accentTint : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            key: ValueKey(('habit-row', row.habit.id, row.actionPeriod)),
            borderRadius: BorderRadius.circular(8),
            excludeFromSemantics: true,
            onTap: select,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              child: Row(
                children: [
                  ExcludeSemantics(
                    child: HabitSign(
                      icon: row.habit.icon,
                      size: 44,
                      circular: true,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ExcludeSemantics(
                      child: Text(
                        row.habit.title,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${row.count} / ${row.target}',
                    style: AppTheme.monoTextStyle.copyWith(
                      fontSize: 13,
                      color: colors.mutedText,
                    ),
                  ),
                  const SizedBox(width: 12),
                  HabitCheckInButton(row: row),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WeekStrip extends ConsumerWidget {
  const _WeekStrip({required this.view});
  final HabitsViewState view;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vm = ref.read(habitsViewModelProvider.notifier);
    final l = context.l10n, colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: ShadButton.ghost(
            onPressed: vm.selectToday,
            child: Text(l.today),
          ),
        ),
        Row(
          children: [
            IconButton.outlined(
              tooltip: l.habitPreviousWeek,
              onPressed: () => vm.moveWeek(-1),
              icon: const Icon(LucideIcons.chevronLeft, size: 18),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final minimum =
                      7 *
                      MediaQuery.textScalerOf(
                        context,
                      ).scale(44).clamp(44.0, 100.0);
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: constraints.maxWidth < minimum
                          ? minimum
                          : constraints.maxWidth,
                      child: Row(
                        children: [
                          for (var i = 0; i < 7; i++)
                            Expanded(
                              child: Builder(
                                builder: (context) {
                                  final day = DateTime(
                                    view.weekStart.year,
                                    view.weekStart.month,
                                    view.weekStart.day + i,
                                  );
                                  final selected = day == view.selectedDay,
                                      today = day == view.today;
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 2,
                                    ),
                                    child: Semantics(
                                      label: DateFormat.yMMMMEEEEd(
                                        l.localeName,
                                      ).format(day),
                                      selected: selected,
                                      child: Material(
                                        color: selected
                                            ? colors.accentTint
                                            : today
                                            ? colors.surfaceTint
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(8),
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          onTap: () => vm.selectDay(day),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 8,
                                            ),
                                            child: Column(
                                              children: [
                                                Text(
                                                  DateFormat.E(
                                                    l.localeName,
                                                  ).format(day),
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .labelSmall
                                                      ?.copyWith(
                                                        color: selected
                                                            ? colors.accent
                                                            : colors.mutedText,
                                                      ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  '${day.day}',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .titleMedium
                                                      ?.copyWith(
                                                        color: selected
                                                            ? colors.accent
                                                            : colors
                                                                  .primaryText,
                                                      ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  today
                                                      ? l.today
                                                      : day.month !=
                                                            view.weekStart.month
                                                      ? DateFormat.MMM(
                                                          l.localeName,
                                                        ).format(day)
                                                      : '',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .labelSmall
                                                      ?.copyWith(
                                                        color: colors.mutedText,
                                                      ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
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
              ),
            ),
            const SizedBox(width: 8),
            IconButton.outlined(
              tooltip: l.habitNextWeek,
              onPressed: () => vm.moveWeek(1),
              icon: const Icon(LucideIcons.chevronRight, size: 18),
            ),
          ],
        ),
      ],
    );
  }
}
