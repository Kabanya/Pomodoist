part of 'focus_stage.dart';

class FocusHeader extends StatelessWidget {
  const FocusHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const Key('focus-heading'),
      header: true,
      child: Text(
        context.l10n.focusTitle,
        style: Theme.of(context).textTheme.headlineMedium,
      ),
    );
  }
}

class _FocusFullHeader extends StatelessWidget {
  const _FocusFullHeader({
    required this.preset,
    required this.onMinimize,
    this.menu,
  });
  final Widget preset;
  final Widget? menu;
  final VoidCallback? onMinimize;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Row(
      children: [
        const Expanded(child: FocusHeader()),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: math.min(220, constraints.maxWidth / 3),
          ),
          child: preset,
        ),
        if (onMinimize != null)
          IconButton(
            key: const Key('focus-header-minimize'),
            tooltip: context.l10n.focusSwitchToMinimalView,
            onPressed: onMinimize,
            icon: const Icon(LucideIcons.minimize, size: 18),
            color: context.appColors.secondaryText,
            constraints: const BoxConstraints.tightFor(width: 48, height: 48),
          ),
        ?menu,
      ],
    ),
  );
}

class _FocusSessionOverview extends StatelessWidget {
  const _FocusSessionOverview({
    required this.rhythm,
    required this.label,
    required this.presetName,
    required this.semanticsLabel,
    required this.compact,
    required this.display,
    this.activeSequence,
    this.activeProgress = 0,
    this.recenterToken,
  });
  final FocusRhythm rhythm;
  final String label;
  final String presetName;
  final String semanticsLabel;
  final bool compact;
  final FocusSessionDisplay display;
  final int? activeSequence;
  final double activeProgress;
  final Object? recenterToken;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        spacing: 16,
        runSpacing: 8,
        children: [
          Text(
            label,
            style: AppTheme.monoTextStyle.copyWith(
              fontSize: Theme.of(context).textTheme.bodySmall?.fontSize,
              color: context.appColors.secondaryText,
            ),
          ),
          Text(
            presetName,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.appColors.secondaryText,
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      FocusRhythmRail(
        rhythm: rhythm,
        semanticsLabel: semanticsLabel,
        compact: compact,
        display: display,
        activeSequence: activeSequence,
        activeProgress: activeProgress,
        recenterToken: recenterToken,
      ),
    ],
  );
}

class _FocusControlDock extends StatelessWidget {
  const _FocusControlDock({
    required this.summary,
    required this.primary,
    this.secondary,
    this.menu,
  });
  final String summary;
  final Widget primary;
  final Widget? secondary;
  final Widget? menu;

  @override
  Widget build(BuildContext context) {
    final copy = Text(
      summary,
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: context.appColors.secondaryText),
    );
    return Container(
      key: const Key('focus-control-dock'),
      padding: const EdgeInsets.only(top: 20),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.appColors.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 680) {
            return Column(
              children: [
                copy,
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: [primary, ?secondary, ?menu],
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(end: 16),
                  child: copy,
                ),
              ),
              primary,
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    ?secondary,
                    if (menu != null) ...[
                      const SizedBox(width: 8),
                      menu!,
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

List<Widget> _sessionDisplayMenuItems(
  BuildContext context,
  FocusSessionDisplay display,
  ValueChanged<FocusSessionDisplay>? onChanged,
) {
  if (onChanged == null) return const [];
  return [
    ShadContextMenuItem(
      enabled: false,
      child: Text(context.l10n.focusSessionDisplay),
    ),
    for (final option in FocusSessionDisplay.values)
      ShadContextMenuItem(
        key: ValueKey('focus-session-display-${option.storageValue}'),
        height: 44,
        leading: Icon(
          option == FocusSessionDisplay.compact
              ? LucideIcons.minus
              : LucideIcons.coffee,
          size: 18,
        ),
        trailing: SizedBox.square(
          dimension: 18,
          child: option == display
              ? const Icon(LucideIcons.check, size: 18)
              : null,
        ),
        onPressed: () => onChanged(option),
        child: Text(
          option == FocusSessionDisplay.compact
              ? context.l10n.focusSessionCompact
              : context.l10n.focusSessionIcons,
        ),
      ),
    Divider(height: 8, color: context.appColors.border),
  ];
}

String? _nextIntervalLabel(BuildContext context, FocusRhythmStep? step) {
  if (step == null) return null;
  final phase = switch (step.phase) {
    FocusRhythmPhase.work => context.l10n.workInterval,
    FocusRhythmPhase.shortBreak => context.l10n.shortBreak,
    FocusRhythmPhase.longBreak => context.l10n.longBreak,
  };
  return context.l10n.focusNextInterval(
    phase,
    formatDurationCompact(Duration(seconds: step.plannedSeconds)),
  );
}
