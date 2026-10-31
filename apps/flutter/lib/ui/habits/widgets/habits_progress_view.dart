import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/domain/models/habits/habit_models.dart';
import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/habits/view_models/habits_view_model.dart';
import 'package:pomodoist/ui/habits/widgets/habit_icon.dart';
import 'package:pomodoist/ui/habits/widgets/habit_overview.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class HabitsProgressView extends ConsumerWidget {
  const HabitsProgressView({
    required this.weekStrip,
    required this.focusNode,
    super.key,
  });
  final Widget weekStrip;
  final FocusNode Function(String id, bool ring) focusNode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(habitsViewModelProvider);
    final l = context.l10n, colors = context.appColors;
    final date = DateFormat.MMMd(l.localeName).format(view.selectedDay);
    final today = view.selectedDay == view.today;
    final remaining = view.remainingRows, completed = view.completedRows;
    Widget cards(List<HabitDayRow> rows) => LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 300).floor().clamp(1, 3);
        final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final row in rows)
              SizedBox(
                width: width,
                child: _ProgressHabit(
                  row: row,
                  card: true,
                  focusNode: focusNode(row.habit.id, false),
                ),
              ),
          ],
        );
      },
    );
    return SingleChildScrollView(
      key: const PageStorageKey('habits-progress-scroll'),
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          weekStrip,
          const SizedBox(height: 24),
          if (view.futureDay)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(l.habitsFuture),
            ),
          if (view.actionError)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                l.habitSaveError,
                style: TextStyle(color: colors.error),
              ),
            ),
          if (view.loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: CircularProgressIndicator(),
              ),
            )
          else if (view.loadError)
            Column(
              children: [
                Text(l.habitLoadError),
                ShadButton.ghost(
                  onPressed: ref.read(habitsViewModelProvider.notifier).retry,
                  child: Text(l.commonRetry),
                ),
              ],
            )
          else if (view.rows.isEmpty)
            Padding(
              padding: const EdgeInsets.all(48),
              child: Text(
                view.finished ? l.habitsFinishedEmpty : l.habitsEmpty,
                textAlign: TextAlign.center,
              ),
            )
          else if (view.finished)
            cards(view.rows)
          else ...[
            LayoutBuilder(
              builder: (context, constraints) {
                final ring = HabitsProgressCircle(
                  rows: view.rows,
                  focusNode: (id) => focusNode(id, true),
                );
                final list = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SectionTitle(
                      today
                          ? l.habitsRemainingToday
                          : l.habitsRemainingOn(date),
                    ),
                    const SizedBox(height: 16),
                    if (remaining.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(l.habitsDone),
                      ),
                    for (final row in remaining) ...[
                      _ProgressHabit(
                        row: row,
                        focusNode: focusNode(row.habit.id, false),
                      ),
                      const Divider(height: 1),
                    ],
                  ],
                );
                // The outer capability stays wide while an open panel narrows its background.
                if (constraints.maxWidth < 880) {
                  return Column(
                    children: [ring, const SizedBox(height: 24), list],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: ring),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsetsDirectional.only(start: 24),
                        decoration: BoxDecoration(
                          border: BorderDirectional(
                            start: BorderSide(color: colors.border),
                          ),
                        ),
                        child: list,
                      ),
                    ),
                  ],
                );
              },
            ),
            if (completed.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Divider(height: 1),
              ),
              _SectionTitle(
                today ? l.habitsCompletedToday : l.habitsCompletedOn(date),
              ),
              const SizedBox(height: 16),
              cards(completed),
            ],
          ],
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);
  final String title;
  @override
  Widget build(BuildContext context) =>
      Text(title, style: Theme.of(context).textTheme.titleLarge);
}

class HabitsProgressCircle extends ConsumerWidget {
  const HabitsProgressCircle({
    required this.rows,
    required this.focusNode,
    super.key = const ValueKey('habits-progress-circle'),
  });
  final List<HabitDayRow> rows;
  final FocusNode Function(String id) focusNode;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors, l = context.l10n;
    final completed = rows.where((r) => r.complete).length;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = math.min(520.0, constraints.maxWidth);
        final radius = math.max(0.0, size / 2 - 40);
        final iconsFit =
            rows.length <= 1 ||
            2 * radius * math.sin(math.pi / rows.length) >= 72;
        return Center(
          child: SizedBox.square(
            dimension: size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: ExcludeSemantics(
                    child: CustomPaint(
                      painter: _HabitRingPainter(
                        completed: rows.map((r) => r.complete).toList(),
                        accent: colors.accentFill,
                        neutral: colors.border,
                      ),
                    ),
                  ),
                ),
                Semantics(
                  label: l.habitsSummary(completed, rows.length),
                  excludeSemantics: true,
                  child: SizedBox(
                    width: size * .54,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '$completed',
                                style: AppTheme.monoTextStyle.copyWith(
                                  fontSize: 56,
                                  fontWeight: FontWeight.w700,
                                  color: colors.accent,
                                ),
                              ),
                              Text(
                                ' / ${rows.length}',
                                style: AppTheme.monoTextStyle.copyWith(
                                  fontSize: 56,
                                  fontWeight: FontWeight.w700,
                                  color: colors.primaryText,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l.habitsProgressCaption,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(color: colors.mutedText),
                        ),
                      ],
                    ),
                  ),
                ),
                if (iconsFit)
                  for (var i = 0; i < rows.length; i++)
                    Positioned(
                      left:
                          size / 2 +
                          radius *
                              math.cos(
                                -math.pi / 2 +
                                    (i + .5) * 2 * math.pi / rows.length,
                              ) -
                          28,
                      top:
                          size / 2 +
                          radius *
                              math.sin(
                                -math.pi / 2 +
                                    (i + .5) * 2 * math.pi / rows.length,
                              ) -
                          28,
                      child: _RingHabit(
                        row: rows[i],
                        focusNode: focusNode(rows[i].habit.id),
                      ),
                    ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HabitRingPainter extends CustomPainter {
  const _HabitRingPainter({
    required this.completed,
    required this.accent,
    required this.neutral,
  });
  final List<bool> completed;
  final Color accent, neutral;
  @override
  void paint(Canvas canvas, Size size) {
    if (completed.isEmpty) return;
    final radius = math.max(0.0, size.shortestSide / 2 - 40);
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: radius,
    );
    final slot = math.pi * 2 / completed.length;
    final gap = math.min(.07, slot * .18);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 28
      ..strokeCap = StrokeCap.round;
    // Round caps must not close the gap between neighboring segments.
    final capAngle = radius == 0 ? 0.0 : math.min(slot * .4, 28 / radius);
    for (var i = 0; i < completed.length; i++) {
      paint.color = completed[i] ? accent : neutral;
      paint.strokeCap = slot * radius > 56 ? StrokeCap.round : StrokeCap.butt;
      final inset = paint.strokeCap == StrokeCap.round ? capAngle : 0.0;
      canvas.drawArc(
        rect,
        -math.pi / 2 + i * slot + (gap + inset) / 2,
        slot - gap - inset,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_HabitRingPainter oldDelegate) =>
      oldDelegate.completed != completed ||
      oldDelegate.accent != accent ||
      oldDelegate.neutral != neutral;
}

class _RingHabit extends ConsumerWidget {
  const _RingHabit({required this.row, required this.focusNode});
  final HabitDayRow row;
  final FocusNode focusNode;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    return Tooltip(
      message: '${row.habit.title} · ${row.count} / ${row.target}',
      child: Material(
        color: colors.canvas,
        shape: CircleBorder(
          side: BorderSide(
            color: row.complete ? colors.accent : colors.border,
            width: 2,
          ),
        ),
        child: InkWell(
          focusNode: focusNode,
          customBorder: const CircleBorder(),
          onTap: () => ref
              .read(habitsViewModelProvider.notifier)
              .selectHabit(row.habit.id),
          child: Semantics(
            label: '${row.habit.title}, ${row.count} / ${row.target}',
            child: SizedBox.square(
              dimension: 56,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  ExcludeSemantics(
                    child: HabitSign(
                      icon: row.habit.icon,
                      size: 44,
                      circular: true,
                    ),
                  ),
                  if (row.complete)
                    PositionedDirectional(
                      end: -4,
                      top: -4,
                      child: _DoneBadge(),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DoneBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: context.appColors.accentFill,
      shape: BoxShape.circle,
      border: Border.all(color: context.appColors.canvas, width: 2),
    ),
    child: Icon(LucideIcons.check, size: 16, color: context.appColors.onAccent),
  );
}

class _ProgressHabit extends ConsumerWidget {
  const _ProgressHabit({
    required this.row,
    required this.focusNode,
    this.card = false,
  });
  final HabitDayRow row;
  final FocusNode focusNode;
  final bool card;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final minutes = row.habit.reminderMinutes;
    final metadata = minutes != null
        ? MaterialLocalizations.of(context).formatTimeOfDay(
            TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
            alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
          )
        : row.targets.keys
              .map((p) => habitDayPeriodLabel(context, p))
              .join(' · ');
    void select() =>
        ref.read(habitsViewModelProvider.notifier).selectHabit(row.habit.id);
    return Material(
      key: ValueKey(('progress-habit', row.habit.id)),
      color: card ? colors.surface : Colors.transparent,
      shape: card
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: colors.border),
            )
          : null,
      child: Semantics(
        button: true,
        label: row.habit.title,
        explicitChildNodes: true,
        onTap: select,
        child: InkWell(
          focusNode: focusNode,
          excludeFromSemantics: true,
          borderRadius: BorderRadius.circular(card ? 10 : 0),
          onTap: select,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: card ? 16 : 0,
              vertical: 24,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: HabitSign(
                    icon: row.habit.icon,
                    size: card ? 48 : 56,
                    circular: true,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ExcludeSemantics(
                        child: Text(
                          row.habit.title,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${row.count} / ${row.target}',
                        style: AppTheme.monoTextStyle.copyWith(
                          color: colors.primaryText,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (minutes != null ||
                              !row.targets.containsKey(
                                HabitDayPeriod.anytime,
                              )) ...[
                            Icon(
                              LucideIcons.clock,
                              size: 16,
                              color: colors.mutedText,
                            ),
                            const SizedBox(width: 6),
                          ],
                          Expanded(
                            child: Text(
                              metadata,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: colors.mutedText),
                            ),
                          ),
                        ],
                      ),
                      if (!card) ...[
                        const SizedBox(height: 12),
                        ExcludeSemantics(
                          child: row.target <= 12
                              ? Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    for (var i = 0; i < row.target; i++)
                                      Container(
                                        width: 16,
                                        height: 16,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: i < row.count
                                              ? colors.accentFill
                                              : Colors.transparent,
                                          border: Border.all(
                                            color: i < row.count
                                                ? colors.accent
                                                : colors.mutedText,
                                          ),
                                        ),
                                      ),
                                  ],
                                )
                              : LinearProgressIndicator(
                                  value: (row.count / row.target).clamp(
                                    0.0,
                                    1.0,
                                  ),
                                  color: colors.accent,
                                  backgroundColor: colors.border,
                                  borderRadius: BorderRadius.circular(8),
                                  minHeight: 6,
                                ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (card && row.complete)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _DoneBadge(),
                  )
                else if (!card)
                  Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: HabitCheckInButton(row: row, round: true),
                  ),
                Padding(
                  padding: EdgeInsets.only(top: card ? 0 : 24),
                  child: HabitActionsMenu(row: row, vertical: true),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
