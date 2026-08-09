import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_l10n.dart';
import '../../../app/formatters.dart';
import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../domain/achievement_models.dart';
import '../domain/productivity_models.dart';
import 'achievement_widgets.dart';

const _wideReportsBreakpoint = 760.0;
const _reportsMaxWidth = 1160.0;

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final summary = ref.watch(productivitySummaryProvider);
    final achievements = ref.watch(achievementsProvider);
    final today = ref.watch(clockProvider).now().toLocal();

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Center(
            child: ConstrainedBox(
              key: const Key('reports-content'),
              constraints: const BoxConstraints(maxWidth: _reportsMaxWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.reportsTitle,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    MaterialLocalizations.of(context).formatFullDate(today),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 30),
                  summary.when(
                    data: (item) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _TodayStory(
                          key: const Key('reports-today-story'),
                          summary: item,
                        ),
                        const SizedBox(height: 30),
                        const Divider(),
                        const SizedBox(height: 28),
                        _WeeklyStory(
                          key: const Key('reports-weekly-story'),
                          days: item.lastSevenDays,
                        ),
                        const SizedBox(height: 30),
                        const Divider(),
                        const SizedBox(height: 24),
                        _NextAchievementSection(achievements: achievements),
                      ],
                    ),
                    loading: () => const _ReportsLoading(),
                    error: (error, stackTrace) => Text(
                      l10n.failedToLoadReports(error),
                      style: Theme.of(context).textTheme.bodyMedium,
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

class _TodayStory extends StatelessWidget {
  const _TodayStory({required this.summary, super.key});

  final ProductivitySummary summary;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _wideReportsBreakpoint;
        final introduction = _TodayIntroduction(summary: summary, wide: wide);
        final progress = _IntervalProgress(
          completed: summary.completedFocusIntervals,
          target: summary.plannedFocusIntervals,
          size: wide ? 154 : 126,
        );
        final metrics = _TodayMetrics(summary: summary, wide: wide);

        if (!wide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              introduction,
              const SizedBox(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  progress,
                  const SizedBox(width: 24),
                  Expanded(child: metrics),
                ],
              ),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(flex: 5, child: introduction),
            Container(
              width: 1,
              height: 132,
              margin: const EdgeInsets.symmetric(horizontal: 38),
              color: context.appColors.border,
            ),
            progress,
            const SizedBox(width: 48),
            Expanded(flex: 3, child: metrics),
          ],
        );
      },
    );
  }
}

class _TodayIntroduction extends StatelessWidget {
  const _TodayIntroduction({required this.summary, required this.wide});

  final ProductivitySummary summary;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.navToday.toUpperCase(),
          style: textTheme.labelMedium?.copyWith(
            color: colors.accent,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          context.l10n.reportsFocusedDay,
          style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 14),
        Text(
          formatFocusTime(context, summary.totalFocusSeconds),
          style: textTheme.displayMedium?.copyWith(
            color: colors.primaryText,
            fontSize: wide ? 56 : 40,
            fontWeight: FontWeight.w700,
            letterSpacing: -1.2,
            height: 1,
          ),
        ),
        const SizedBox(height: 2),
        Text(context.l10n.focusTime, style: textTheme.bodyMedium),
      ],
    );
  }
}

class _IntervalProgress extends StatelessWidget {
  const _IntervalProgress({
    required this.completed,
    required this.target,
    required this.size,
  });

  final int completed;
  final int target;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final hasTarget = target > 0;
    final ratio = hasTarget ? (completed / target).clamp(0, 1).toDouble() : 0.0;
    final value = hasTarget ? '$completed/$target' : '$completed';
    final semantics = hasTarget
        ? context.l10n.reportsIntervalProgressSemantics(completed, target)
        : context.l10n.reportsIntervalCountSemantics(completed);

    return Semantics(
      label: semantics,
      readOnly: true,
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: size,
          child: CustomPaint(
            painter: _ProgressRingPainter(
              progress: ratio,
              trackColor: colors.surfaceHover,
              progressColor: colors.accent,
            ),
            child: Center(
              child: Column(
                key: const Key('reports-interval-progress-value'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(value, style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 2),
                  Text(
                    context.l10n.focusIntervals,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
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

class _ProgressRingPainter extends CustomPainter {
  const _ProgressRingPainter({
    required this.progress,
    required this.trackColor,
    required this.progressColor,
  });

  final double progress;
  final Color trackColor;
  final Color progressColor;

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 9.0;
    final center = size.center(Offset.zero);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final value = Paint()
      ..color = progressColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2, false, track);
    if (progress > 0) {
      canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * progress, false, value);
    }
  }

  @override
  bool shouldRepaint(_ProgressRingPainter oldDelegate) =>
      progress != oldDelegate.progress ||
      trackColor != oldDelegate.trackColor ||
      progressColor != oldDelegate.progressColor;
}

class _TodayMetrics extends StatelessWidget {
  const _TodayMetrics({required this.summary, required this.wide});

  final ProductivitySummary summary;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final children = [
      _StoryMetric(
        icon: Icons.check_circle_outline,
        iconKey: const Key('reports-completed-tasks-icon'),
        iconColor: context.appColors.info,
        value: '${summary.completedTasks}',
        label: context.l10n.completedTasks,
      ),
      _StoryMetric(
        icon: Icons.circle_outlined,
        iconColor: context.appColors.accent,
        value: '${summary.openTasks}',
        label: context.l10n.openTasks,
      ),
    ];
    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [children[0], const SizedBox(height: 20), children[1]],
      );
    }
    return Row(
      children: [
        Expanded(child: children[0]),
        Container(
          width: 1,
          height: 64,
          margin: const EdgeInsets.symmetric(horizontal: 22),
          color: context.appColors.border,
        ),
        Expanded(child: children[1]),
      ],
    );
  }
}

class _StoryMetric extends StatelessWidget {
  const _StoryMetric({
    required this.icon,
    this.iconKey,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final Key? iconKey;
  final Color iconColor;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, key: iconKey, size: 22, color: iconColor),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WeeklyStory extends StatelessWidget {
  const _WeeklyStory({required this.days, super.key});

  final List<ProductivityDaySummary> days;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final textTheme = Theme.of(context).textTheme;
    final totalTasks = days.fold<int>(
      0,
      (sum, day) => sum + day.completedTasks,
    );
    final totalFocusIntervals = days.fold<int>(
      0,
      (sum, day) => sum + day.completedFocusIntervals,
    );
    final totalFocusSeconds = days.fold<int>(
      0,
      (sum, day) => sum + day.totalFocusSeconds,
    );
    final hasStats =
        totalTasks > 0 || totalFocusIntervals > 0 || totalFocusSeconds > 0;
    final pointLabels = [
      for (final day in days) formatFocusTime(context, day.totalFocusSeconds),
    ];
    final weekdayLabels = [
      for (final day in days) _weekdayLabel(context, day.localDate),
    ];
    final semanticsSummary = [
      for (var index = 0; index < days.length; index++)
        '${weekdayLabels[index]} ${pointLabels[index]}',
    ].join(', ');

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _wideReportsBreakpoint;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.lastSevenDaysLabel.toUpperCase(),
              style: textTheme.labelMedium?.copyWith(
                color: colors.accent,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 10),
            Text(context.l10n.reportsThisWeek, style: textTheme.titleLarge),
            const SizedBox(height: 22),
            SizedBox(
              key: const Key('reports-weekly-chart'),
              height: wide ? 260 : 210,
              width: double.infinity,
              child: hasStats && days.isNotEmpty
                  ? Semantics(
                      label: context.l10n.reportsWeeklyChartSemantics(
                        semanticsSummary,
                      ),
                      readOnly: true,
                      child: ExcludeSemantics(
                        child: CustomPaint(
                          painter: _WeeklyFocusChartPainter(
                            days: days,
                            pointLabels: pointLabels,
                            weekdayLabels: weekdayLabels,
                            lineColor: colors.accent,
                            gridColor: colors.border,
                            fillColor: colors.accentTint.withValues(alpha: 0.7),
                            primaryTextColor: colors.primaryText,
                            mutedTextColor: colors.mutedText,
                            textDirection: Directionality.of(context),
                          ),
                        ),
                      ),
                    )
                  : Center(
                      child: Text(
                        context.l10n.noWeeklyStatsLabel,
                        textAlign: TextAlign.center,
                        style: textTheme.bodySmall,
                      ),
                    ),
            ),
            const SizedBox(height: 18),
            _WeeklyTotals(
              key: const Key('reports-weekly-totals'),
              focusTime: formatFocusTime(context, totalFocusSeconds),
              focusIntervals: '$totalFocusIntervals',
              completedTasks: '$totalTasks',
              compact: !wide,
            ),
          ],
        );
      },
    );
  }
}

class _WeeklyFocusChartPainter extends CustomPainter {
  const _WeeklyFocusChartPainter({
    required this.days,
    required this.pointLabels,
    required this.weekdayLabels,
    required this.lineColor,
    required this.gridColor,
    required this.fillColor,
    required this.primaryTextColor,
    required this.mutedTextColor,
    required this.textDirection,
  });

  final List<ProductivityDaySummary> days;
  final List<String> pointLabels;
  final List<String> weekdayLabels;
  final Color lineColor;
  final Color gridColor;
  final Color fillColor;
  final Color primaryTextColor;
  final Color mutedTextColor;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    if (days.isEmpty) return;
    final maxSeconds = days.fold<int>(
      1,
      (maxValue, day) => math.max(maxValue, day.totalFocusSeconds),
    );
    const horizontalPadding = 26.0;
    const topPadding = 34.0;
    const bottomPadding = 30.0;
    final chartHeight = size.height - topPadding - bottomPadding;
    final chartWidth = size.width - horizontalPadding * 2;
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var index = 0; index < 3; index++) {
      final y = topPadding + chartHeight * index / 2;
      canvas.drawLine(
        Offset(horizontalPadding, y),
        Offset(size.width - horizontalPadding, y),
        gridPaint,
      );
    }

    final points = <Offset>[
      for (var index = 0; index < days.length; index++)
        Offset(
          days.length == 1
              ? size.width / 2
              : horizontalPadding + chartWidth * index / (days.length - 1),
          topPadding +
              chartHeight * (1 - days[index].totalFocusSeconds / maxSeconds),
        ),
    ];
    final linePath = _smoothPath(points);
    final areaPath = Path.from(linePath)
      ..lineTo(points.last.dx, topPadding + chartHeight)
      ..lineTo(points.first.dx, topPadding + chartHeight)
      ..close();
    canvas.drawPath(areaPath, Paint()..color = fillColor);
    canvas.drawPath(
      linePath,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final pointPaint = Paint()..color = lineColor;
    for (var index = 0; index < points.length; index++) {
      final point = points[index];
      canvas.drawCircle(point, 4.5, pointPaint);
      _paintLabel(
        canvas,
        pointLabels[index],
        Offset(point.dx, math.max(0, point.dy - 18)),
        canvasSize: size,
        color: primaryTextColor,
        alignAbove: true,
      );
      _paintLabel(
        canvas,
        weekdayLabels[index],
        Offset(point.dx, size.height - 2),
        canvasSize: size,
        color: mutedTextColor,
        alignAbove: true,
      );
    }
  }

  Path _smoothPath(List<Offset> points) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var index = 1; index < points.length; index++) {
      final previous = points[index - 1];
      final current = points[index];
      final midpointX = (previous.dx + current.dx) / 2;
      path.cubicTo(
        midpointX,
        previous.dy,
        midpointX,
        current.dy,
        current.dx,
        current.dy,
      );
    }
    return path;
  }

  void _paintLabel(
    Canvas canvas,
    String value,
    Offset anchor, {
    required Size canvasSize,
    required Color color,
    required bool alignAbove,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: textDirection,
      maxLines: 1,
    )..layout(maxWidth: 58);
    final x = (anchor.dx - painter.width / 2)
        .clamp(0.0, math.max(0.0, canvasSize.width - painter.width))
        .toDouble();
    final y = alignAbove ? anchor.dy - painter.height : anchor.dy;
    painter.paint(canvas, Offset(x, y));
  }

  @override
  bool shouldRepaint(_WeeklyFocusChartPainter oldDelegate) =>
      !listEquals(days, oldDelegate.days) ||
      !listEquals(pointLabels, oldDelegate.pointLabels) ||
      !listEquals(weekdayLabels, oldDelegate.weekdayLabels) ||
      lineColor != oldDelegate.lineColor ||
      gridColor != oldDelegate.gridColor ||
      fillColor != oldDelegate.fillColor ||
      primaryTextColor != oldDelegate.primaryTextColor ||
      mutedTextColor != oldDelegate.mutedTextColor ||
      textDirection != oldDelegate.textDirection;
}

class _WeeklyTotals extends StatelessWidget {
  const _WeeklyTotals({
    required this.focusTime,
    required this.focusIntervals,
    required this.completedTasks,
    required this.compact,
    super.key,
  });

  final String focusTime;
  final String focusIntervals;
  final String completedTasks;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _WeeklyTotal(
            icon: Icons.timelapse,
            iconColor: context.appColors.accent,
            value: focusTime,
            label: context.l10n.focusTime,
            compact: compact,
          ),
        ),
        Expanded(
          child: _WeeklyTotal(
            icon: Icons.timer_outlined,
            iconColor: context.appColors.accent,
            value: focusIntervals,
            label: context.l10n.focusIntervals,
            compact: compact,
          ),
        ),
        Expanded(
          child: _WeeklyTotal(
            icon: Icons.check_circle_outline,
            iconColor: context.appColors.info,
            value: completedTasks,
            label: context.l10n.completedTasks,
            compact: compact,
          ),
        ),
      ],
    );
  }
}

class _WeeklyTotal extends StatelessWidget {
  const _WeeklyTotal({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
    required this.compact,
  });

  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: compact ? 16 : 20, color: iconColor),
          SizedBox(width: compact ? 4 : 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    value,
                    style: compact
                        ? Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          )
                        : Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NextAchievementSection extends StatelessWidget {
  const _NextAchievementSection({required this.achievements});

  final AsyncValue<List<AchievementItem>> achievements;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('reports-next-achievement'),
      width: double.infinity,
      child: achievements.when(
        data: (items) => _NextAchievementContent(items: items),
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 26),
          child: LinearProgressIndicator(),
        ),
        error: (error, stackTrace) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Text(context.l10n.failedToLoadReports(error)),
        ),
      ),
    );
  }
}

class _NextAchievementContent extends StatelessWidget {
  const _NextAchievementContent({required this.items});

  final List<AchievementItem> items;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final textTheme = Theme.of(context).textTheme;

    if (items.isEmpty) {
      return Row(
        children: [
          Icon(Icons.emoji_events_outlined, color: colors.mutedText),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              context.l10n.noAchievementsYet,
              style: textTheme.titleMedium,
            ),
          ),
        ],
      );
    }

    final next = _closestLockedAchievement(items);
    final action = TextButton(
      onPressed: () => context.push('/reports/achievements'),
      child: Text(context.l10n.viewAllAchievementsCount(items.length)),
    );

    if (next == null) {
      return Row(
        children: [
          Icon(Icons.emoji_events_outlined, color: colors.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              context.l10n.allAchievementsUnlocked,
              style: textTheme.titleMedium,
            ),
          ),
          action,
        ],
      );
    }

    final progressLabel = '${next.progress}/${next.target}';
    final progress = Semantics(
      label: '${context.l10n.progressLabel}: $progressLabel',
      value: progressLabel,
      readOnly: true,
      child: ExcludeSemantics(
        child: Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  minHeight: 6,
                  value: next.progressRatio,
                  backgroundColor: colors.surfaceHover,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(progressLabel, style: textTheme.labelLarge),
          ],
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _wideReportsBreakpoint;
        final identity = Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: colors.accentTint,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                achievementGroupIcon(next.group),
                color: colors.accent,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.reportsNextAchievement.toUpperCase(),
                    style: textTheme.labelSmall?.copyWith(
                      color: colors.accent,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    next.titleFor(context.l10n.localeName),
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    next.subtitleFor(context.l10n.localeName),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        );

        if (!wide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              identity,
              const SizedBox(height: 18),
              progress,
              Align(alignment: AlignmentDirectional.centerStart, child: action),
            ],
          );
        }

        return Row(
          children: [
            Expanded(flex: 5, child: identity),
            const SizedBox(width: 30),
            Expanded(flex: 4, child: progress),
            const SizedBox(width: 18),
            action,
          ],
        );
      },
    );
  }
}

class _ReportsLoading extends StatelessWidget {
  const _ReportsLoading();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        SizedBox(height: 160, child: Center(child: LinearProgressIndicator())),
        SizedBox(height: 28),
        SizedBox(height: 240, child: Center(child: LinearProgressIndicator())),
      ],
    );
  }
}

AchievementItem? _closestLockedAchievement(List<AchievementItem> items) {
  AchievementItem? closest;
  for (final item in items) {
    if (item.unlocked) continue;
    if (closest == null || item.progressRatio > closest.progressRatio) {
      closest = item;
    }
  }
  return closest;
}

String _weekdayLabel(BuildContext context, DateTime date) {
  final l10n = context.l10n;
  return switch (date.weekday) {
    DateTime.monday => l10n.weekMon,
    DateTime.tuesday => l10n.weekTue,
    DateTime.wednesday => l10n.weekWed,
    DateTime.thursday => l10n.weekThu,
    DateTime.friday => l10n.weekFri,
    DateTime.saturday => l10n.weekSat,
    _ => l10n.weekSun,
  };
}
