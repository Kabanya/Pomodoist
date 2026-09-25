part of 'focus_stage.dart';

/// Grow with the available area while keeping a readable, bounded dial.
double focusTimerDiameter(Size viewport) =>
    math.min(viewport.width, (viewport.shortestSide * 0.5).clamp(280.0, 520.0));

class _FocusTimerStage extends StatelessWidget {
  const _FocusTimerStage({
    required this.interval,
    required this.remaining,
    required this.style,
    required this.compact,
    required this.minimal,
    super.key,
  });

  final FocusIntervalItem interval;
  final Duration remaining;
  final FocusTimerVisualStyle style;
  final bool compact;
  final bool minimal;

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
        ? LucideIcons.timer
        : interval.type == 'longBreak'
        ? LucideIcons.clock
        : LucideIcons.coffee;

    return TweenAnimationBuilder<Color?>(
      duration: AppMotion.duration(context, AppMotion.state),
      curve: AppMotion.curve,
      tween: ColorTween(begin: stateColor, end: stateColor),
      builder: (context, animatedColor, child) {
        final color = animatedColor ?? stateColor;
        return RepaintBoundary(
          key: const Key('focus-timer-repaint-boundary'),
          child: Semantics(
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
                  final circleSize = focusTimerDiameter(
                    Size(
                      constraints.maxWidth,
                      MediaQuery.sizeOf(context).height,
                    ),
                  );
                  final fontSize = circleSize * 2 / 9;
                  if (minimal) {
                    return Column(
                      children: [
                        const SizedBox(height: 8),
                        ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 48),
                          child: Center(
                            child: Wrap(
                              alignment: WrapAlignment.center,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 6,
                              children: [
                                Icon(phaseIcon, size: 16, color: color),
                                Text(
                                  phaseLabel,
                                  key: const Key('focus-phase-label'),
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(color: color),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        _FocusMinimalTimer(
                          style: style,
                          remainingLabel: remainingLabel,
                          progress: progress,
                          color: color,
                        ),
                      ],
                    );
                  }
                  if (style == FocusTimerVisualStyle.bar) {
                    return Column(
                      children: [
                        _PhaseLabel(
                          motionKey: '${interval.type}:${interval.status}',
                          icon: phaseIcon,
                          label: phaseLabel,
                          color: color,
                        ),
                        const SizedBox(height: 10),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            remainingLabel,
                            style: AppTheme.monoTextStyle.copyWith(
                              fontSize: fontSize,
                              color: colors.primaryText,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          totalLabel,
                          style: AppTheme.monoTextStyle.copyWith(
                            fontSize: Theme.of(
                              context,
                            ).textTheme.bodySmall?.fontSize,
                            color: colors.secondaryText,
                          ),
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
                              color: color,
                              backgroundColor: colors.surfaceHover,
                            ),
                          ),
                        ),
                      ],
                    );
                  }

                  return Center(
                    child: SizedBox.square(
                      key: const Key('focus-circular-timer'),
                      dimension: circleSize,
                      child: CustomPaint(
                        painter: _FocusTimerPainter(
                          progress: progress,
                          trackColor: colors.surfaceHover,
                          fillColor: color,
                        ),
                        child: RepaintBoundary(
                          child: Padding(
                            padding: EdgeInsets.all(compact ? 28 : 36),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _PhaseLabel(
                                    motionKey:
                                        '${interval.type}:${interval.status}',
                                    icon: phaseIcon,
                                    label: phaseLabel,
                                    color: color,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    remainingLabel,
                                    style: AppTheme.monoTextStyle.copyWith(
                                      color: colors.primaryText,
                                      fontWeight: FontWeight.w400,
                                      fontSize: fontSize,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    totalLabel,
                                    style: AppTheme.monoTextStyle.copyWith(
                                      fontSize: Theme.of(
                                        context,
                                      ).textTheme.bodyMedium?.fontSize,
                                      color: colors.secondaryText,
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
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FocusMinimalTimer extends StatelessWidget {
  const _FocusMinimalTimer({
    required this.style,
    required this.remainingLabel,
    required this.progress,
    required this.color,
  });

  final FocusTimerVisualStyle style;
  final String remainingLabel;
  final double progress;
  final Color color;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final diameter = focusTimerDiameter(
        Size(constraints.maxWidth, MediaQuery.sizeOf(context).height),
      );
      final time = FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          remainingLabel,
          textDirection: TextDirection.ltr,
          style: AppTheme.monoTextStyle.copyWith(
            fontSize: diameter * 2 / 9,
            fontWeight: FontWeight.w400,
            letterSpacing: -3,
            color: context.appColors.primaryText,
          ),
        ),
      );
      if (style == FocusTimerVisualStyle.bar) {
        return Column(
          key: const Key('focus-minimal-timer'),
          children: [
            time,
            const SizedBox(height: 24),
            SizedBox(
              width: 80,
              child: LinearProgressIndicator(
                key: const Key('focus-linear-timer'),
                value: progress,
                minHeight: 2,
                borderRadius: BorderRadius.circular(2),
                color: color,
                backgroundColor: context.appColors.surfaceHover,
                stopIndicatorColor: Colors.transparent,
                trackGap: 0,
              ),
            ),
          ],
        );
      }
      return ConstrainedBox(
        key: const Key('focus-minimal-timer'),
        constraints: BoxConstraints(maxWidth: diameter),
        child: AspectRatio(
          aspectRatio: 1,
          child: CustomPaint(
            key: const Key('focus-circular-timer'),
            painter: _FocusTimerPainter(
              progress: progress,
              trackColor: context.appColors.surfaceHover,
              fillColor: color,
            ),
            child: Center(
              child: Padding(padding: const EdgeInsets.all(28), child: time),
            ),
          ),
        ),
      );
    },
  );
}

class _PhaseLabel extends StatelessWidget {
  const _PhaseLabel({
    required this.motionKey,
    required this.icon,
    required this.label,
    required this.color,
  });

  final String motionKey;
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppMotion.duration(context, AppMotion.state),
      switchInCurve: AppMotion.curve,
      switchOutCurve: AppMotion.curve,
      child: Column(
        key: ValueKey(motionKey),
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
      ),
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
