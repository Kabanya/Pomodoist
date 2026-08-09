part of 'focus_stage.dart';

class _FocusTimerStage extends StatelessWidget {
  const _FocusTimerStage({
    required this.interval,
    required this.remaining,
    required this.style,
    required this.compact,
    super.key,
  });

  final FocusIntervalItem interval;
  final Duration remaining;
  final FocusTimerVisualStyle style;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final phaseLabel = _phaseLabel(context, interval);
    final remainingLabel = formatDurationCompact(remaining);
    final plannedLabel = formatDurationCompact(
      Duration(seconds: interval.plannedSeconds),
    );
    final totalLabel = context.l10n.focusTimerTotal(plannedLabel);
    final progress = _progress(interval, remaining);
    final stateColor = interval.status == 'paused'
        ? colors.warning
        : interval.type == 'work'
        ? colors.accent
        : colors.info;
    final phaseIcon = interval.type == 'work'
        ? Icons.timer_outlined
        : interval.type == 'longBreak'
        ? Icons.schedule
        : Icons.coffee_outlined;

    return Semantics(
      key: const Key('focus-timer-semantics'),
      label: context.l10n.focusTimerSummary(
        phaseLabel,
        _activeStatusLabel(context, interval.status),
        remainingLabel,
        plannedLabel,
      ),
      container: true,
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (style == FocusTimerVisualStyle.bar) {
              return Column(
                children: [
                  _PhaseLabel(
                    icon: phaseIcon,
                    label: phaseLabel,
                    color: stateColor,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    remainingLabel,
                    style: Theme.of(context).textTheme.displayLarge?.copyWith(
                      color: colors.primaryText,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    totalLabel,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 20),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        key: const Key('focus-linear-timer'),
                        minHeight: compact ? 8 : 10,
                        value: progress,
                        color: stateColor,
                        backgroundColor: colors.surfaceHover,
                      ),
                    ),
                  ),
                ],
              );
            }

            final circleSize = compact
                ? math.min(300.0, math.max(200.0, constraints.maxWidth - 24))
                : 320.0;
            return Center(
              child: SizedBox.square(
                key: const Key('focus-circular-timer'),
                dimension: circleSize,
                child: CustomPaint(
                  painter: _FocusTimerPainter(
                    progress: progress,
                    trackColor: colors.surfaceHover,
                    fillColor: stateColor,
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(compact ? 28 : 36),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _PhaseLabel(
                            icon: phaseIcon,
                            label: phaseLabel,
                            color: stateColor,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            remainingLabel,
                            style: Theme.of(context).textTheme.displayLarge
                                ?.copyWith(
                                  color: colors.primaryText,
                                  fontWeight: FontWeight.w700,
                                  fontSize: compact ? 62 : 70,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            totalLabel,
                            style: Theme.of(context).textTheme.bodyMedium,
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
    );
  }
}

class _PhaseLabel extends StatelessWidget {
  const _PhaseLabel({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 22, color: color),
        const SizedBox(height: 5),
        Text(
          key: const Key('focus-phase-label'),
          label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _FocusTimerPainter extends CustomPainter {
  const _FocusTimerPainter({
    required this.progress,
    required this.trackColor,
    required this.fillColor,
  });

  final double progress;
  final Color trackColor;
  final Color fillColor;

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 11.0;
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth;
    final fill = Paint()
      ..color = fillColor
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, track);
    if (progress > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * progress.clamp(0.0, 1.0),
        false,
        fill,
      );
    }
  }

  @override
  bool shouldRepaint(_FocusTimerPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.fillColor != fillColor;
}

String _phaseLabel(BuildContext context, FocusIntervalItem interval) {
  final l10n = context.l10n;
  final label = switch (interval.type) {
    'work' => l10n.workInterval,
    'longBreak' => l10n.longBreak,
    _ => l10n.shortBreak,
  };
  return interval.status == 'ready' ? l10n.readyLabel(label) : label;
}

double _progress(FocusIntervalItem interval, Duration remaining) {
  if (interval.status == 'ready' || interval.plannedSeconds <= 0) {
    return 0;
  }
  return 1 - (remaining.inSeconds / interval.plannedSeconds).clamp(0.0, 1.0);
}

String _activeStatusLabel(BuildContext context, String status) {
  final l10n = context.l10n;
  return switch (status) {
    'ready' => l10n.readyShort,
    'paused' => l10n.focusStatusPaused,
    _ => l10n.focusStatusRunning,
  };
}
