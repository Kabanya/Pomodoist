import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons, ShadButton;

import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/localization/formatters.dart';
import 'package:pomodoist/ui/productivity/view_models/productivity_view_models.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/domain/models/productivity/achievement_models.dart';
import 'package:pomodoist/ui/productivity/widgets/achievement_localizations.dart';
import 'package:pomodoist/domain/models/productivity/productivity_models.dart';
import 'package:pomodoist/ui/productivity/widgets/achievement_widgets.dart';
import 'package:pomodoist/domain/models/tasks/project_colors.dart';
import 'package:pomodoist/routing/task_detail_navigation.dart';

const _wideReportsBreakpoint = 760.0;
const _reportsMaxWidth = 1160.0;

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(reportsViewModelProvider);
    final summary = state.summary;
    final achievements = state.achievements;
    final today = state.today;

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
                          today: today,
                        ),
                        const SizedBox(height: 30),
                        const Divider(),
                        const SizedBox(height: 24),
                        _ProjectFocusSection(
                          key: const Key('reports-project-focus'),
                          summary: item,
                          state: state,
                          viewModel: ref.read(
                            reportsViewModelProvider.notifier,
                          ),
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
        final wide =
            constraints.maxWidth >= _wideReportsBreakpoint &&
            MediaQuery.textScalerOf(context).scale(1) <= 1.3;
        final introduction = _TodayIntroduction(summary: summary, wide: wide);
        final progress = SizedBox(
          width: wide ? 200 : constraints.maxWidth,
          child: Column(
            children: [
              _IntervalProgress(
                completed: summary.completedFocusIntervals,
                target: summary.plannedFocusIntervals,
                size: MediaQuery.textScalerOf(context)
                    .scale(wide ? 154 : 126)
                    .clamp(0, wide ? 200 : constraints.maxWidth)
                    .toDouble(),
              ),
              const SizedBox(height: 12),
              Text(
                context.l10n.reportsPlanEstimates,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        );
        final metrics = _TodayMetrics(summary: summary);

        if (!wide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              introduction,
              const SizedBox(height: 24),
              metrics,
              const SizedBox(height: 24),
              progress,
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
              margin: const EdgeInsets.symmetric(horizontal: 24),
              color: context.appColors.border,
            ),
            progress,
            const SizedBox(width: 24),
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
          style: textTheme.displayMedium
              ?.merge(AppTheme.monoTextStyle)
              .copyWith(
                color: colors.primaryText,
                fontSize: wide ? 56 : 40,
                fontWeight: FontWeight.w700,
                letterSpacing: -1.2,
                height: 1,
              ),
        ),
        const SizedBox(height: 2),
        Text(context.l10n.focusTime, style: textTheme.bodyMedium),
        const SizedBox(height: 12),
        Text(context.l10n.reportsDayInProgress, style: textTheme.bodySmall),
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
                  Text(
                    value,
                    style: Theme.of(
                      context,
                    ).textTheme.headlineSmall?.merge(AppTheme.monoTextStyle),
                  ),
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
  const _TodayMetrics({required this.summary});

  final ProductivitySummary summary;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _StoryMetric(
        icon: LucideIcons.circleCheck,
        iconKey: const Key('reports-completed-tasks-icon'),
        iconColor: context.appColors.info,
        value: '${summary.completedTasks}',
        label: context.l10n.completedTasks,
      ),
      const SizedBox(height: 16),
      Text(
        '${context.l10n.openTasks}: ${summary.openTasks}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );
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
              Text(
                value,
                style: Theme.of(
                  context,
                ).textTheme.headlineSmall?.merge(AppTheme.monoTextStyle),
              ),
              const SizedBox(height: 2),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

class _WeeklyStory extends StatelessWidget {
  const _WeeklyStory({required this.days, required this.today, super.key});

  final List<ProductivityDaySummary> days;
  final DateTime today;

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
        '${weekdayLabels[index]} ${pointLabels[index]}${days[index].localDate == today ? ', ${context.l10n.navToday}' : ''}',
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
            const SizedBox(height: 6),
            Text(context.l10n.reportsDayInProgress, style: textTheme.bodySmall),
            const SizedBox(height: 22),
            SizedBox(
              key: const Key('reports-weekly-chart'),
              width: double.infinity,
              child: hasStats && days.isNotEmpty
                  ? Semantics(
                      label: context.l10n.reportsWeeklyChartSemantics(
                        semanticsSummary,
                      ),
                      readOnly: true,
                      child: ExcludeSemantics(
                        child: _WeeklyFocusBars(
                          days: days,
                          today: today,
                          pointLabels: pointLabels,
                          weekdayLabels: weekdayLabels,
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

class _WeeklyFocusBars extends StatelessWidget {
  const _WeeklyFocusBars({
    required this.days,
    required this.today,
    required this.pointLabels,
    required this.weekdayLabels,
  });

  final List<ProductivityDaySummary> days;
  final DateTime today;
  final List<String> pointLabels;
  final List<String> weekdayLabels;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final maxSeconds = days.fold<int>(
      1,
      (value, day) => math.max(value, day.totalFocusSeconds),
    );
    final textStyle = Theme.of(context).textTheme.labelSmall;
    final textScaler = MediaQuery.textScalerOf(context);
    // Labels keep their text scale; narrow charts scroll rather than shrink.
    final labelWidths = [...pointLabels, ...weekdayLabels].map((label) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: textStyle),
        textDirection: Directionality.of(context),
        textScaler: textScaler,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    });
    final dayWidth = math.max(64.0, labelWidths.fold<double>(0, math.max) + 16);
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: math.max(constraints.maxWidth, days.length * dayWidth),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var index = 0; index < days.length; index++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          pointLabels[index],
                          style: textStyle,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 140,
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: Container(
                              width: 44,
                              height: days[index].totalFocusSeconds == 0
                                  ? 2
                                  : math.max(
                                      2,
                                      140 *
                                          days[index].totalFocusSeconds /
                                          maxSeconds,
                                    ),
                              decoration: BoxDecoration(
                                color: days[index].localDate == today
                                    ? colors.accent
                                    : colors.accentTint,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(4),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          weekdayLabels[index],
                          style: textStyle,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          height: 8,
                          child: days[index].localDate == today
                              ? Icon(
                                  LucideIcons.circle,
                                  size: 6,
                                  color: colors.accent,
                                )
                              : null,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProjectFocusSection extends StatelessWidget {
  const _ProjectFocusSection({
    required this.summary,
    required this.state,
    required this.viewModel,
    super.key,
  });

  final ProductivitySummary summary;
  final ReportsState state;
  final ReportsViewModel viewModel;

  Color _color(BuildContext context, ProjectFocusSummary project) =>
      project.project == null
      ? context.appColors.mutedText
      : parseThemeColor(effectiveProjectColor(project.project!))!;

  String _title(BuildContext context, ProjectFocusSummary project) {
    final l10n = context.l10n;
    if (project.projectId == null) return l10n.reportsNoProject;
    if (project.name == null) return l10n.reportsUnknownProject;
    return project.isUnavailable
        ? l10n.reportsUnavailableName(project.name!)
        : project.name!;
  }

  String _taskTitle(BuildContext context, TaskFocusSummary task) {
    final l10n = context.l10n;
    if (task.taskId == null) return l10n.reportsNoTask;
    if (task.name == null) return l10n.reportsUnknownTask;
    return task.canOpen ? task.name! : l10n.reportsUnavailableName(task.name!);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final textTheme = Theme.of(context).textTheme;
    final projects = state.projectPeriod == ReportsProjectPeriod.today
        ? summary.todayProjects
        : summary.lastSevenDaysProjects;
    final total = projects.fold<int>(
      0,
      (sum, project) => sum + project.totalFocusSeconds,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.reportsTimeByProject, style: textTheme.titleLarge),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final period in ReportsProjectPeriod.values)
              Semantics(
                selected: state.projectPeriod == period,
                child: ShadButton.ghost(
                  key: ValueKey('reports-project-period-${period.name}'),
                  height: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  backgroundColor: state.projectPeriod == period
                      ? context.appColors.surfaceTint
                      : null,
                  onPressed: () => viewModel.setProjectPeriod(period),
                  child: Text(
                    period == ReportsProjectPeriod.today
                        ? l10n.navToday
                        : l10n.lastSevenDaysLabel,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          formatFocusTime(context, total),
          style: AppTheme.monoTextStyle.copyWith(
            fontSize: 36,
            fontWeight: FontWeight.w600,
            color: context.appColors.primaryText,
          ),
        ),
        if (total > 0) ...[
          const SizedBox(height: 20),
          ExcludeSemantics(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 12,
                child: Row(
                  children: [
                    for (final project in projects)
                      if (project.totalFocusSeconds > 0)
                        Expanded(
                          flex: project.totalFocusSeconds,
                          child: ColoredBox(
                            color: _color(context, project),
                            child: const SizedBox.expand(),
                          ),
                        ),
                  ],
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        if (projects.isEmpty)
          Text(l10n.reportsNoProjectFocus, style: textTheme.bodySmall),
        for (final project in projects) _projectRow(context, project, total),
      ],
    );
  }

  Widget _projectRow(
    BuildContext context,
    ProjectFocusSummary project,
    int total,
  ) {
    final expanded = state.expandedProjectIds.contains(project.projectId);
    final duration = formatFocusTime(context, project.totalFocusSeconds);
    final share = total == 0
        ? null
        : context.l10n.reportsProjectShare(
            MaterialLocalizations.of(
              context,
            ).formatDecimal((100 * project.totalFocusSeconds / total).round()),
          );
    final textTheme = Theme.of(context).textTheme;
    return Column(
      key: ValueKey(project.projectId),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          expanded: expanded,
          child: ShadButton.ghost(
            width: double.infinity,
            expands: true,
            height: 0,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            onPressed: () => viewModel.toggleProject(project.projectId),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final title = Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _color(context, project),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _title(context, project),
                        textAlign: TextAlign.start,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      expanded
                          ? LucideIcons.chevronDown
                          : LucideIcons.chevronRight,
                      size: 16,
                    ),
                  ],
                );
                final value = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      duration,
                      style: AppTheme.monoTextStyle.copyWith(
                        color: context.appColors.primaryText,
                      ),
                    ),
                    if (share != null) Text(share, style: textTheme.bodySmall),
                  ],
                );
                if (constraints.maxWidth < 480 ||
                    MediaQuery.textScalerOf(context).scale(1) > 1.3) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      title,
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsetsDirectional.only(start: 20),
                        child: value,
                      ),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: title),
                    const SizedBox(width: 24),
                    value,
                  ],
                );
              },
            ),
          ),
        ),
        if (expanded)
          for (final task in project.tasks)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 20),
              child: task.canOpen
                  ? ShadButton.ghost(
                      width: double.infinity,
                      expands: true,
                      height: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 12,
                      ),
                      onPressed: () => openTaskDetails(context, task.taskId!),
                      child: _taskRow(context, task),
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 12,
                      ),
                      child: _taskRow(context, task),
                    ),
            ),
        const Divider(height: 1),
      ],
    );
  }

  Widget _taskRow(BuildContext context, TaskFocusSummary task) => LayoutBuilder(
    builder: (context, constraints) {
      final title = Text(
        _taskTitle(context, task),
        textAlign: TextAlign.start,
        style: task.canOpen ? null : Theme.of(context).textTheme.bodySmall,
      );
      final time = Text(
        formatFocusTime(context, task.totalFocusSeconds),
        style: AppTheme.monoTextStyle.copyWith(
          color: context.appColors.secondaryText,
        ),
      );
      if (constraints.maxWidth < 480 ||
          MediaQuery.textScalerOf(context).scale(1) > 1.3) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [title, const SizedBox(height: 4), time],
        );
      }
      return Row(
        children: [
          Expanded(child: title),
          const SizedBox(width: 16),
          time,
        ],
      );
    },
  );
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
    final metrics = [
      _WeeklyTotal(
        icon: LucideIcons.clock,
        iconColor: context.appColors.accent,
        value: focusTime,
        label: context.l10n.focusTime,
        compact: compact,
      ),
      _WeeklyTotal(
        icon: LucideIcons.timer,
        iconColor: context.appColors.accent,
        value: focusIntervals,
        label: context.l10n.focusIntervals,
        compact: compact,
      ),
      _WeeklyTotal(
        icon: LucideIcons.circleCheck,
        iconColor: context.appColors.info,
        value: completedTasks,
        label: context.l10n.completedTasks,
        compact: compact,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 520 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.3) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < metrics.length; index++) ...[
                if (index > 0) const SizedBox(height: 16),
                metrics[index],
              ],
            ],
          );
        }
        return Row(
          children: [for (final metric in metrics) Expanded(child: metric)],
        );
      },
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
                Text(
                  value,
                  style:
                      (compact
                              ? Theme.of(context).textTheme.titleMedium
                              : Theme.of(context).textTheme.titleLarge)
                          ?.merge(AppTheme.monoTextStyle),
                ),
                const SizedBox(height: 2),
                Text(label, style: Theme.of(context).textTheme.bodySmall),
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
          Icon(LucideIcons.trophy, color: colors.mutedText),
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
    final action = ShadButton.ghost(
      height: 0,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      onPressed: () => context.push('/reports/achievements'),
      child: Flexible(
        child: Text(context.l10n.viewAllAchievementsCount(items.length)),
      ),
    );

    if (next == null) {
      return Row(
        children: [
          Icon(LucideIcons.trophy, color: colors.accent),
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
                    next.titleFor(context.l10n),
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    next.subtitleFor(context.l10n),
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
