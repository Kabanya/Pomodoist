part of 'quick_add_bar.dart';

class _VoicePulse extends StatelessWidget {
  const _VoicePulse({
    required this.animation,
    required this.active,
    required this.listeningLevel,
    required this.icon,
  });

  final Animation<double> animation;
  final bool active;
  final double? listeningLevel;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final value = active ? animation.value : 0.0;
        return SizedBox.square(
          dimension: 72,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Transform.scale(
                scale: 1 + value * .04,
                child: Opacity(
                  opacity: active ? .18 * (1 - value) : 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colorScheme.primary,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
              AnimatedContainer(
                duration: AppMotion.duration(context, AppMotion.state),
                curve: Curves.easeOutCubic,
                width: active ? 58 : 52,
                height: active ? 58 : 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active
                      ? colorScheme.primaryContainer
                      : colorScheme.surfaceContainerHighest,
                  border: Border.all(
                    color: active
                        ? colorScheme.primary.withValues(alpha: .28)
                        : colorScheme.outlineVariant,
                  ),
                ),
                child: listeningLevel == null
                    ? Icon(
                        icon,
                        color: active
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onSurfaceVariant,
                      )
                    : _VoiceAmplitudeBars(level: listeningLevel!),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _VoiceAmplitudeBars extends StatelessWidget {
  const _VoiceAmplitudeBars({required this.level});

  final double level;

  @override
  Widget build(BuildContext context) {
    const factors = [.45, .75, 1.0, .75, .45];
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final effectiveLevel = reduceMotion ? .45 : level;
    final color = Theme.of(context).colorScheme.onPrimaryContainer;
    return ExcludeSemantics(
      child: Row(
        key: const Key('voice-amplitude-bars'),
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var index = 0; index < factors.length; index += 1) ...[
            AnimatedContainer(
              key: Key('voice-amplitude-bar-$index'),
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 100),
              curve: Curves.easeOutCubic,
              width: 3,
              height: 4 + 28 * effectiveLevel * factors[index],
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            if (index < factors.length - 1) const SizedBox(width: 2),
          ],
        ],
      ),
    );
  }
}

class _VoiceProcessingSteps extends StatelessWidget {
  const _VoiceProcessingSteps({required this.activeIndex});

  final int activeIndex;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final labels = [
      l10n.voiceStepRecord,
      l10n.voiceStepAnalyze,
      l10n.voiceStepReview,
    ];
    const icons = [
      LucideIcons.mic,
      LucideIcons.sparkles,
      LucideIcons.listChecks,
    ];

    return Row(
      children: [
        for (var index = 0; index < labels.length; index++)
          Expanded(
            child: _VoiceProcessingStep(
              icon: icons[index],
              label: labels[index],
              active: index == activeIndex,
              complete: index < activeIndex,
            ),
          ),
      ],
    );
  }
}

class _VoiceProcessingStep extends StatelessWidget {
  const _VoiceProcessingStep({
    required this.icon,
    required this.label,
    required this.active,
    required this.complete,
  });

  final IconData icon;
  final String label;
  final bool active;
  final bool complete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final highlighted = active || complete;
    final foreground = highlighted
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant;
    return AnimatedDefaultTextStyle(
      duration: AppMotion.duration(context, AppMotion.state),
      curve: Curves.easeOutCubic,
      style: Theme.of(context).textTheme.labelSmall!.copyWith(
        color: foreground,
        fontWeight: highlighted ? FontWeight.w700 : FontWeight.w500,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: AppMotion.duration(context, AppMotion.state),
            curve: Curves.easeOutCubic,
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active
                  ? colorScheme.primaryContainer
                  : complete
                  ? colorScheme.primary.withValues(alpha: .10)
                  : colorScheme.surfaceContainerHighest.withValues(alpha: .55),
              border: Border.all(
                color: highlighted
                    ? colorScheme.primary.withValues(alpha: .42)
                    : colorScheme.outlineVariant,
              ),
            ),
            child: Icon(icon, size: 18, color: foreground),
          ),
          const SizedBox(height: 5),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _TranscriptPanel extends StatelessWidget {
  const _TranscriptPanel({
    super.key,
    required this.text,
    required this.muted,
    required this.colorScheme,
  });

  final String text;
  final bool muted;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: .45),
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: SingleChildScrollView(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: muted
                    ? colorScheme.onSurfaceVariant
                    : colorScheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AnalysisPanel extends StatelessWidget {
  const _AnalysisPanel({
    super.key,
    required this.transcript,
    required this.progress,
    required this.activity,
  });

  final String transcript;
  final Animation<double> progress;
  final Animation<double> activity;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: .35),
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              key: const Key('voice-analysis-status'),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: .62),
                border: Border.all(
                  color: colorScheme.primary.withValues(alpha: .24),
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.sparkles,
                    size: 18,
                    color: colorScheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      context.l10n.voiceAnalyzing,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _TranscriptPreview(text: transcript),
            const SizedBox(height: 16),
            AnimatedBuilder(
              animation: progress,
              builder: (context, _) {
                return LinearProgressIndicator(
                  minHeight: 3,
                  value: progress.value,
                );
              },
            ),
            const SizedBox(height: 14),
            const _SkeletonLine(widthFactor: .92),
            const SizedBox(height: 8),
            const _SkeletonLine(widthFactor: .74),
            const SizedBox(height: 8),
            const _SkeletonLine(widthFactor: .82),
          ],
        ),
      ),
    );
  }
}

class _TranscriptPreview extends StatelessWidget {
  const _TranscriptPreview({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final content = Text(
      text,
      key: const Key('voice-transcript-visualization'),
      style: Theme.of(context).textTheme.bodyLarge,
    );
    if (MediaQuery.disableAnimationsOf(context)) return content;
    return TweenAnimationBuilder<double>(
      key: ValueKey(text),
      tween: Tween(begin: 0, end: 1),
      duration: AppMotion.state,
      curve: AppMotion.curve,
      builder: (context, value, child) => Opacity(opacity: value, child: child),
      child: content,
    );
  }
}

class _SkeletonLine extends StatelessWidget {
  const _SkeletonLine({required this.widthFactor});

  final double widthFactor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return FractionallySizedBox(
      widthFactor: widthFactor,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(99),
        ),
        child: const SizedBox(height: 12),
      ),
    );
  }
}
