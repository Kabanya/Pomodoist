part of 'focus_stage.dart';

class FocusCompactHeader extends StatelessWidget {
  const FocusCompactHeader({
    required this.state,
    required this.actions,
    required this.onMenuPressed,
    required this.onViewModeChanged,
    required this.onSessionDisplayChanged,
    required this.onPresetSelected,
    required this.onCustomize,
    required this.onCreate,
    super.key,
  });

  final FocusState state;
  final FocusStageActions actions;
  final VoidCallback onMenuPressed;
  final ValueChanged<FocusViewMode> onViewModeChanged;
  final ValueChanged<FocusSessionDisplay> onSessionDisplayChanged;
  final ValueChanged<String> onPresetSelected;
  final ValueChanged<FocusPresetItem> onCustomize;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final full = state.viewMode == FocusViewMode.full;
    final run = state.run;
    final interval = state.interval;
    final remaining = state.remaining;
    final preset = run == null ? state.effectivePreset : state.activePreset;
    final ready = !state.loading && state.loadError == null;
    final active =
        ready &&
        run != null &&
        interval != null &&
        interval.runId == run.id &&
        remaining != null;
    final idle = ready && run == null && interval == null;
    final switchLabel = full
        ? l10n.focusSwitchToMinimalView
        : l10n.focusSwitchToFullView;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.appColors.border)),
      ),
      child: ConstrainedBox(
        key: const Key('focus-compact-header'),
        constraints: const BoxConstraints(minHeight: 52),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 48,
              child: IconButton(
                key: const Key('shell-menu-button'),
                tooltip: l10n.menuTooltip,
                onPressed: onMenuPressed,
                icon: const Icon(LucideIcons.panelLeft),
              ),
            ),
            SizedBox(
              width: 48,
              child: active || idle
                  ? _MinimalPresetMenu(
                      iconOnly: true,
                      presets: state.presets,
                      selectedPreset: preset,
                      onSelected: onPresetSelected,
                      onCustomize: preset == null
                          ? null
                          : () => onCustomize(preset),
                      onCreate: onCreate,
                    )
                  : null,
            ),
            // Equal 96 px wings keep the title at the viewport's center.
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Semantics(
                  header: true,
                  label: l10n.focusTitle,
                  excludeSemantics: true,
                  child: Text(
                    l10n.focusTitle,
                    key: const Key('shell-page-title'),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
            SizedBox.square(
              dimension: 48,
              child: active
                  ? _buildFocusMoreActionsMenu(
                      context,
                      interval: interval,
                      remaining: remaining,
                      presets: state.presets,
                      selectedPreset: preset,
                      minimal: !full,
                      viewMode: state.viewMode,
                      showViewModeMenu: false,
                      sessionDisplay: state.sessionDisplay,
                      onSessionDisplayChanged: onSessionDisplayChanged,
                      actions: actions,
                      onViewModeChanged: onViewModeChanged,
                      onPresetChanged: onPresetSelected,
                      onCustomizePreset: onCustomize,
                      onCreatePreset: onCreate,
                    )
                  : _FocusViewModeMenu(
                      viewMode: state.viewMode,
                      onChanged: onViewModeChanged,
                      sessionDisplay: state.sessionDisplay,
                      onSessionDisplayChanged: onSessionDisplayChanged,
                      showViewModeMenu: false,
                    ),
            ),
            SizedBox.square(
              dimension: 48,
              child: IconButton(
                key: const Key('focus-compact-switch-view'),
                tooltip: switchLabel,
                onPressed: () => onViewModeChanged(
                  full ? FocusViewMode.minimal : FocusViewMode.full,
                ),
                color: context.appColors.secondaryText,
                icon: Icon(
                  full ? LucideIcons.minimize : LucideIcons.maximize,
                  size: 20,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
