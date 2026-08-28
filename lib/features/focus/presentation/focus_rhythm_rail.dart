import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../app/app_l10n.dart';
import '../../../app/theme/app_theme.dart';
import 'focus_rhythm.dart';

class FocusRhythmRail extends StatefulWidget {
  const FocusRhythmRail({
    required this.rhythm,
    required this.semanticsLabel,
    required this.compact,
    required this.activeProgress,
    this.activeSequence,
    this.recenterToken,
    super.key,
  });

  final FocusRhythm rhythm;
  final String semanticsLabel;
  final bool compact;
  final int? activeSequence;
  final double activeProgress;
  final Object? recenterToken;

  @override
  State<FocusRhythmRail> createState() => _FocusRhythmRailState();
}

class _FocusRhythmRailState extends State<FocusRhythmRail> {
  final _activeStepKey = GlobalKey();
  final _scrollController = ScrollController();
  String? _lastCenterSignature;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stepExtent = widget.compact ? 50.0 : 82.0;
        final contentWidth = widget.rhythm.steps.length * stepExtent;
        final scrolls = contentWidth > constraints.maxWidth;
        _scheduleActiveCenter(
          '${widget.activeSequence}:${constraints.maxWidth}:'
          '${widget.rhythm.steps.length}:${widget.compact}:'
          '${Directionality.of(context)}:${widget.recenterToken}',
          scrolls: scrolls,
          reduceMotion: MediaQuery.disableAnimationsOf(context),
        );

        final rail = SizedBox(
          width: contentWidth,
          child: Row(
            children: [
              for (var index = 0; index < widget.rhythm.steps.length; index++)
                Expanded(
                  child: _RhythmStepSlot(
                    step: widget.rhythm.steps[index],
                    compact: widget.compact,
                    active:
                        widget.rhythm.steps[index].sequence ==
                        widget.activeSequence,
                    activeProgress: widget.activeProgress.clamp(0.0, 1.0),
                    activeStepKey:
                        widget.rhythm.steps[index].sequence ==
                            widget.activeSequence
                        ? _activeStepKey
                        : null,
                    leadingConnectorSource: index > 0
                        ? widget.rhythm.steps[index - 1]
                        : null,
                    activeSequence: widget.activeSequence,
                    showLeadingConnector: index > 0,
                    showTrailingConnector:
                        index < widget.rhythm.steps.length - 1,
                  ),
                ),
            ],
          ),
        );

        return Semantics(
          key: const Key('focus-rhythm-rail'),
          label: widget.semanticsLabel,
          container: true,
          explicitChildNodes: false,
          child: RepaintBoundary(
            key: const Key('focus-rhythm-repaint-boundary'),
            child: ExcludeSemantics(
              child: scrolls
                  ? SingleChildScrollView(
                      controller: _scrollController,
                      scrollDirection: Axis.horizontal,
                      child: rail,
                    )
                  : Align(child: rail),
            ),
          ),
        );
      },
    );
  }

  void _scheduleActiveCenter(
    String signature, {
    required bool scrolls,
    required bool reduceMotion,
  }) {
    if (!scrolls ||
        widget.activeSequence == null ||
        _lastCenterSignature == signature) {
      return;
    }
    final animate = _lastCenterSignature != null && !reduceMotion;
    _lastCenterSignature = signature;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final activeContext = _activeStepKey.currentContext;
      if (!mounted || activeContext == null || !_scrollController.hasClients) {
        return;
      }
      final activeRenderObject = activeContext.findRenderObject();
      if (activeRenderObject == null) {
        return;
      }
      final viewport = RenderAbstractViewport.of(activeRenderObject);
      final target = viewport
          .getOffsetToReveal(activeRenderObject, 0.5)
          .offset
          .clamp(
            _scrollController.position.minScrollExtent,
            _scrollController.position.maxScrollExtent,
          )
          .toDouble();
      if ((_scrollController.offset - target).abs() > 0.5) {
        if (animate) {
          unawaited(
            _scrollController.animateTo(
              target,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
            ),
          );
        } else {
          _scrollController.jumpTo(target);
        }
      }
    });
  }
}

class _RhythmStepSlot extends StatelessWidget {
  const _RhythmStepSlot({
    required this.step,
    required this.compact,
    required this.active,
    required this.activeProgress,
    required this.activeStepKey,
    required this.leadingConnectorSource,
    required this.activeSequence,
    required this.showLeadingConnector,
    required this.showTrailingConnector,
  });

  final FocusRhythmStep step;
  final bool compact;
  final bool active;
  final double activeProgress;
  final GlobalKey? activeStepKey;
  final FocusRhythmStep? leadingConnectorSource;
  final int? activeSequence;
  final bool showLeadingConnector;
  final bool showTrailingConnector;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final activeColor = _activeColor(colors, step);
    final leadingSource = leadingConnectorSource;
    final leadingProgress = leadingSource == null
        ? 0.0
        : leadingSource.sequence == activeSequence
        ? (activeProgress * 2 - 1).clamp(0.0, 1.0)
        : _isFinished(leadingSource)
        ? 1.0
        : 0.0;
    final trailingProgress = active
        ? (activeProgress * 2).clamp(0.0, 1.0)
        : _isFinished(step)
        ? 1.0
        : 0.0;
    final activeForeground = _highContrastForeground(activeColor);
    final foreground = active ? activeColor : colors.secondaryText;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final nodeSize = compact
        ? (step.phase == FocusRhythmPhase.work ? 34.0 : 30.0)
        : (step.phase == FocusRhythmPhase.work ? 46.0 : 40.0);

    return SizedBox(
      key: ValueKey('focus-rhythm-step-${step.sequence}'),
      height: compact ? 48 : 78,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          if (showLeadingConnector)
            _RhythmConnectorHalf(
              key: ValueKey('focus-rhythm-connector-${step.sequence}'),
              progressKey: ValueKey(
                'focus-rhythm-leading-progress-${step.sequence}',
              ),
              alignment: const AlignmentDirectional(-1, -0.58),
              progress: leadingProgress,
              color: leadingSource == null
                  ? colors.border
                  : _activeColor(colors, leadingSource),
              trackColor: colors.border,
            ),
          if (showTrailingConnector)
            _RhythmConnectorHalf(
              key: ValueKey('focus-rhythm-trailing-connector-${step.sequence}'),
              progressKey: ValueKey(
                'focus-rhythm-trailing-progress-${step.sequence}',
              ),
              alignment: const AlignmentDirectional(1, -0.58),
              progress: trailingProgress,
              color: activeColor,
              trackColor: colors.border,
            ),
          if (activeStepKey != null)
            SizedBox.square(key: activeStepKey, dimension: nodeSize),
          TweenAnimationBuilder<double>(
            key: ValueKey('focus-rhythm-node-motion-${step.sequence}'),
            duration: reduceMotion || !active
                ? Duration.zero
                : const Duration(milliseconds: 260),
            tween: Tween(begin: 0, end: active ? 1 : 0),
            builder: (context, value, child) => Transform.scale(
              key: ValueKey('focus-rhythm-node-landing-${step.sequence}'),
              scale: active ? _landingScale(value) : 1,
              child: child,
            ),
            child: SizedBox.square(
              dimension: nodeSize,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    key: ValueKey('focus-rhythm-node-${step.sequence}'),
                    width: nodeSize,
                    height: nodeSize,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: active ? activeColor : colors.surfaceHover,
                      border: Border.all(
                        color: active ? activeColor : colors.border,
                        width: active ? 2 : 1,
                      ),
                    ),
                    child: AnimatedSwitcher(
                      duration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 180),
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(
                          scale: Tween(begin: 0.9, end: 1.0).animate(animation),
                          child: child,
                        ),
                      ),
                      child: _RhythmStepMark(
                        key: ValueKey(
                          'focus-rhythm-mark-${step.sequence}-${step.state}',
                        ),
                        step: step,
                        color: active ? activeForeground : foreground,
                        compact: compact,
                      ),
                    ),
                  ),
                  if (active && !showTrailingConnector)
                    RepaintBoundary(
                      child: SizedBox.square(
                        dimension: nodeSize,
                        child: CircularProgressIndicator(
                          key: ValueKey(
                            'focus-rhythm-node-progress-${step.sequence}',
                          ),
                          value: activeProgress,
                          strokeWidth: 3,
                          color: activeForeground,
                          backgroundColor: Colors.transparent,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (!compact)
            Positioned(
              top: 52,
              child: Text(
                context.l10n.durationMinutes(
                  (step.plannedSeconds / 60).round(),
                ),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.secondaryText),
              ),
            ),
          if (compact && active)
            Positioned(
              top: 42,
              child: Container(
                width: 28,
                height: 3,
                decoration: BoxDecoration(
                  color: activeColor,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RhythmConnectorHalf extends StatelessWidget {
  const _RhythmConnectorHalf({
    required this.progressKey,
    required this.alignment,
    required this.progress,
    required this.color,
    required this.trackColor,
    super.key,
  });

  final Key progressKey;
  final AlignmentDirectional alignment;
  final double progress;
  final Color color;
  final Color trackColor;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Align(
        alignment: alignment,
        child: FractionallySizedBox(
          widthFactor: 0.5,
          child: Stack(
            alignment: AlignmentDirectional.centerStart,
            children: [
              Divider(color: trackColor, thickness: 1),
              FractionallySizedBox(
                key: progressKey,
                widthFactor: progress,
                child: Divider(color: color, thickness: 2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

bool _isFinished(FocusRhythmStep step) =>
    step.state == FocusRhythmState.completed ||
    step.state == FocusRhythmState.skipped;

double _landingScale(double value) {
  if (value <= 0.65) {
    return 0.92 + (1.06 - 0.92) * value / 0.65;
  }
  return 1.06 + (1 - 1.06) * (value - 0.65) / 0.35;
}

Color _activeColor(AppThemePalette colors, FocusRhythmStep step) {
  if (step.state == FocusRhythmState.paused) {
    return colors.warning;
  }
  return step.phase == FocusRhythmPhase.work ? colors.accent : colors.info;
}

Color _highContrastForeground(Color background) {
  final luminance = background.computeLuminance();
  final whiteContrast = 1.05 / (luminance + 0.05);
  final blackContrast = (luminance + 0.05) / 0.05;
  return blackContrast >= whiteContrast ? Colors.black : Colors.white;
}

class _RhythmStepMark extends StatelessWidget {
  const _RhythmStepMark({
    required this.step,
    required this.color,
    required this.compact,
    super.key,
  });

  final FocusRhythmStep step;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (step.state == FocusRhythmState.completed) {
      return Icon(Icons.check, size: compact ? 17 : 20, color: color);
    }
    if (step.state == FocusRhythmState.skipped) {
      return Icon(Icons.skip_next, size: compact ? 17 : 20, color: color);
    }
    if (step.phase == FocusRhythmPhase.shortBreak) {
      return Icon(Icons.coffee_outlined, size: compact ? 15 : 18, color: color);
    }
    if (step.phase == FocusRhythmPhase.longBreak) {
      return Icon(Icons.schedule, size: compact ? 15 : 18, color: color);
    }
    return Text(
      '${step.workOrdinal}',
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        color: color,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}
