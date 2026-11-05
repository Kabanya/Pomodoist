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
    required this.menu,
    required this.onMinimize,
  });
  final Widget preset;
  final Widget menu;
  final VoidCallback? onMinimize;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Row(
      children: [
        Expanded(
          child: CompactShellHeading.isShown(context)
              ? const SizedBox.shrink()
              : const FocusHeader(),
        ),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: math.min(220, constraints.maxWidth / 3),
          ),
          child: preset,
        ),
        if (onMinimize != null)
          ShortcutHintBadge(
            command: AppShortcutCommand.focus,
            outside: true,
            alignment: Alignment.topRight,
            child: IconButton(
              key: const Key('focus-header-minimize'),
              tooltip: context.l10n.focusSwitchToMinimalView,
              onPressed: onMinimize,
              icon: const Icon(LucideIcons.minimize, size: 18),
              color: context.appColors.secondaryText,
              constraints: const BoxConstraints.tightFor(width: 48, height: 48),
            ),
          ),
        menu,
      ],
    ),
  );
}

class _FocusControlDock extends StatelessWidget {
  const _FocusControlDock({
    required this.primary,
    this.secondary,
    this.duration,
  });

  final Widget primary;
  final Widget? secondary;
  final Widget? duration;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Column(
        key: const Key('focus-control-dock'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (secondary == null)
            primary
          else
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: primary),
                  const SizedBox(width: 16),
                  Expanded(child: secondary!),
                ],
              ),
            ),
          if (duration != null) ...[const SizedBox(height: 16), duration!],
        ],
      ),
    ),
  );
}

class _FocusDurationControls extends StatelessWidget {
  const _FocusDurationControls({
    required this.interval,
    required this.remaining,
    required this.strict,
    required this.onAdjust,
  });

  final FocusIntervalItem interval;
  final Duration remaining;
  final bool strict;
  final Future<void> Function(String, int) onAdjust;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final plan = Duration(seconds: interval.plannedSeconds);
    final planLabel = plan.inHours == 0
        ? l10n.pickerMinuteOffset(plan.inMinutes.toString())
        : l10n.durationHoursMinutes(plan.inHours, plan.inMinutes % 60);
    final title = Row(
      children: [
        Icon(
          LucideIcons.clock,
          color: context.appColors.secondaryText,
          size: 20,
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.focusDuration,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Text(
                l10n.focusPlannedDuration(planLabel),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.appColors.secondaryText,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    final step = focusDurationStepSeconds;
    final buttons = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final delta in [-step, step]) ...[
          if (delta > 0) const SizedBox(width: 8),
          OutlinedButton(
            key: ValueKey('focus-duration-$delta'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(56, 48),
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            onPressed:
                remaining <= Duration.zero ||
                    (delta < 0 && (strict || remaining.inSeconds <= step)) ||
                    !isFocusDurationAllowed(interval.plannedSeconds + delta)
                ? null
                : () => unawaited(
                    _performFocusAction(
                      context,
                      () => onAdjust(interval.id, delta),
                    ),
                  ),
            child: Text(
              delta < 0 ? l10n.focusShortenDuration : l10n.focusExtendDuration,
            ),
          ),
        ],
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) =>
          constraints.maxWidth < MediaQuery.textScalerOf(context).scale(305)
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [title, const SizedBox(height: 6), buttons],
            )
          : Row(
              children: [
                Expanded(child: title),
                const SizedBox(width: 8),
                buttons,
              ],
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
