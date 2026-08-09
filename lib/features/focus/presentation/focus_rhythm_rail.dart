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
    this.activeSequence,
    this.recenterToken,
    super.key,
  });

  final FocusRhythm rhythm;
  final String semanticsLabel;
  final bool compact;
  final int? activeSequence;
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
                    activeStepKey:
                        widget.rhythm.steps[index].sequence ==
                            widget.activeSequence
                        ? _activeStepKey
                        : null,
                    leadingConnectorSource:
                        index > 0 &&
                            widget.rhythm.steps[index - 1].sequence ==
                                widget.activeSequence
                        ? widget.rhythm.steps[index - 1]
                        : null,
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
          child: ExcludeSemantics(
            child: scrolls
                ? SingleChildScrollView(
                    controller: _scrollController,
                    scrollDirection: Axis.horizontal,
                    child: rail,
                  )
                : Align(child: rail),
          ),
        );
      },
    );
  }

  void _scheduleActiveCenter(String signature, {required bool scrolls}) {
    if (!scrolls ||
        widget.activeSequence == null ||
        _lastCenterSignature == signature) {
      return;
    }
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
        _scrollController.jumpTo(target);
      }
    });
  }
}

class _RhythmStepSlot extends StatelessWidget {
  const _RhythmStepSlot({
    required this.step,
    required this.compact,
    required this.active,
    required this.activeStepKey,
    required this.leadingConnectorSource,
    required this.showLeadingConnector,
    required this.showTrailingConnector,
  });

  final FocusRhythmStep step;
  final bool compact;
  final bool active;
  final GlobalKey? activeStepKey;
  final FocusRhythmStep? leadingConnectorSource;
  final bool showLeadingConnector;
  final bool showTrailingConnector;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final activeColor = _activeColor(colors, step);
    final leadingColor = leadingConnectorSource == null
        ? colors.border
        : _activeColor(colors, leadingConnectorSource!);
    final activeForeground = _highContrastForeground(activeColor);
    final foreground = active ? activeColor : colors.secondaryText;
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
            ExcludeSemantics(
              child: Align(
                alignment: const AlignmentDirectional(-1, -0.58),
                child: FractionallySizedBox(
                  key: ValueKey('focus-rhythm-connector-${step.sequence}'),
                  widthFactor: 0.5,
                  child: Divider(
                    color: leadingColor,
                    thickness: leadingConnectorSource == null ? 1 : 2,
                  ),
                ),
              ),
            ),
          if (showTrailingConnector)
            ExcludeSemantics(
              child: Align(
                alignment: const AlignmentDirectional(1, -0.58),
                child: FractionallySizedBox(
                  key: ValueKey(
                    'focus-rhythm-trailing-connector-${step.sequence}',
                  ),
                  widthFactor: 0.5,
                  child: Divider(
                    color: active ? activeColor : colors.border,
                    thickness: active ? 2 : 1,
                  ),
                ),
              ),
            ),
          KeyedSubtree(
            key: activeStepKey,
            child: Container(
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
              child: _RhythmStepMark(
                step: step,
                color: active ? activeForeground : foreground,
                compact: compact,
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
