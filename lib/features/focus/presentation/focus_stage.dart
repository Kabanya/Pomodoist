import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_l10n.dart';
import '../../../app/formatters.dart';
import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/action_feedback.dart';
import '../../tasks/domain/project_colors.dart';
import '../../tasks/domain/task_models.dart';
import '../../tasks/presentation/widgets/project_color_picker.dart';
import '../domain/focus_models.dart';
import 'focus_rhythm.dart';
import 'focus_rhythm_rail.dart';
import 'focus_view_mode.dart';

part 'focus_active_controls.dart';
part 'focus_timer_stage.dart';

class FocusIdleStage extends StatelessWidget {
  const FocusIdleStage({
    required this.presets,
    required this.selectedPreset,
    required this.timerVisualStyle,
    required this.compact,
    required this.viewMode,
    this.showViewModeMenu = true,
    required this.onPresetSelected,
    required this.onViewModeChanged,
    required this.onStart,
    required this.onCustomize,
    required this.onCreate,
    super.key,
  });

  final List<FocusPresetItem> presets;
  final FocusPresetItem? selectedPreset;
  final FocusTimerVisualStyle timerVisualStyle;
  final bool compact;
  final FocusViewMode viewMode;
  final bool showViewModeMenu;
  final ValueChanged<String> onPresetSelected;
  final ValueChanged<FocusViewMode> onViewModeChanged;
  final Future<void> Function()? onStart;
  final VoidCallback? onCustomize;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final preset = selectedPreset;
    final full = viewMode == FocusViewMode.full;
    final inlineCircle =
        !full && timerVisualStyle == FocusTimerVisualStyle.circle;
    final cadence = preset == null
        ? 0
        : preset.intervalsBeforeLongBreak.clamp(1, 12);
    final rhythm = preset == null
        ? null
        : buildFocusRhythm(preset: preset, targetWorkIntervals: cadence);
    final primary = _ElasticFocusButton(
      enabled: onStart != null,
      child: FilledButton(
        key: const Key('focus-primary-action'),
        style: FilledButton.styleFrom(minimumSize: const Size(176, 48)),
        onPressed: onStart,
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [const Icon(Icons.play_arrow), Text(l10n.startFocus)],
        ),
      ),
    );

    return Column(
      key: const Key('focus-state-idle'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FocusModeDetails(
          visible: full && rhythm != null,
          child: rhythm == null
              ? const SizedBox.shrink()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.focusSessionProgress(1, cadence),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.secondaryText,
                      ),
                    ),
                    SizedBox(height: compact ? 12 : 16),
                    FocusRhythmRail(
                      rhythm: rhythm,
                      semanticsLabel: l10n.focusRhythmPreviewSummary(
                        rhythm.steps.length,
                      ),
                      compact: compact,
                      activeProgress: 0,
                    ),
                  ],
                ),
        ),
        SizedBox(height: full ? (compact ? 28 : 42) : 8),
        Column(
          key: const Key('focus-primary-stage'),
          children: [
            if (!inlineCircle) ...[
              Icon(
                Icons.timer_outlined,
                size: compact ? 30 : 34,
                color: colors.mutedText,
              ),
              const SizedBox(height: 10),
            ],
            AnimatedSwitcher(
              duration: _motionDuration(context, 200),
              child: full
                  ? Column(
                      key: const Key('focus-idle-full-copy'),
                      children: [
                        Text(
                          l10n.noActiveSession,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          preset?.name ?? l10n.noPreset,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    )
                  : _MinimalPresetMenu(
                      key: const Key('focus-idle-minimal-copy'),
                      presets: presets,
                      selectedPreset: preset,
                      onSelected: onPresetSelected,
                      onCustomize: onCustomize,
                      onCreate: onCreate,
                    ),
            ),
            if (inlineCircle) ...[
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  final circleSize = compact
                      ? math.min(
                          300.0,
                          math.max(200.0, constraints.maxWidth - 24),
                        )
                      : 320.0;
                  return Center(
                    child: SizedBox.square(
                      key: const Key('focus-idle-circular-timer'),
                      dimension: circleSize,
                      child: CustomPaint(
                        painter: _FocusTimerPainter(
                          progress: 0,
                          trackColor: colors.surfaceHover,
                          fillColor: colors.mutedText,
                        ),
                        child: Center(
                          child: Text(
                            preset == null
                                ? '--:--'
                                : formatDurationCompact(
                                    Duration(seconds: preset.workSeconds),
                                  ),
                            style: Theme.of(context).textTheme.displayLarge
                                ?.copyWith(
                                  color: colors.primaryText,
                                  fontWeight: FontWeight.w700,
                                  fontSize: compact ? 54 : 62,
                                ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ] else if (preset != null) ...[
              const SizedBox(height: 8),
              Text(
                l10n.minutesWork((preset.workSeconds / 60).round()),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: colors.primaryText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
        SizedBox(height: compact ? 28 : 34),
        _FocusModeDetails(
          visible: full,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 22),
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final candidate in presets)
                  ChoiceChip(
                    key: ValueKey('preset-choice-${candidate.id}'),
                    selected: candidate.id == preset?.id,
                    onSelected: (_) => onPresetSelected(candidate.id),
                    label: Text(candidate.name),
                    avatar: Icon(
                      candidate.id == preset?.id
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 16,
                    ),
                  ),
              ],
            ),
          ),
        ),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            primary,
            if (full)
              OutlinedButton.icon(
                onPressed: onCustomize,
                icon: const Icon(Icons.tune),
                label: Text(l10n.customize),
              ),
            if (full)
              TextButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add),
                label: Text(l10n.newPreset),
              ),
            if (showViewModeMenu)
              _FocusViewModeMenu(
                viewMode: viewMode,
                onChanged: onViewModeChanged,
              ),
          ],
        ),
      ],
    );
  }
}

class _MinimalPresetMenu extends StatelessWidget {
  const _MinimalPresetMenu({
    required this.presets,
    required this.selectedPreset,
    required this.onSelected,
    required this.onCustomize,
    required this.onCreate,
    super.key,
  });

  final List<FocusPresetItem> presets;
  final FocusPresetItem? selectedPreset;
  final ValueChanged<String> onSelected;
  final VoidCallback? onCustomize;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final title = selectedPreset?.name ?? l10n.noPreset;

    return MenuAnchor(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(colors.surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      menuChildren: [
        for (final preset in presets)
          MenuItemButton(
            key: ValueKey('minimal-preset-choice-${preset.id}'),
            leadingIcon: SizedBox.square(
              dimension: 20,
              child: preset.id == selectedPreset?.id
                  ? Icon(Icons.check_rounded, size: 18, color: colors.accent)
                  : null,
            ),
            onPressed: () {
              if (preset.id != selectedPreset?.id) {
                onSelected(preset.id);
              }
            },
            child: Text(preset.name),
          ),
        if (presets.isNotEmpty) const Divider(height: 1),
        MenuItemButton(
          key: const Key('minimal-preset-customize'),
          leadingIcon: const Icon(Icons.tune, size: 20),
          onPressed: onCustomize,
          child: Text(l10n.customize),
        ),
        MenuItemButton(
          key: const Key('minimal-preset-create'),
          leadingIcon: const Icon(Icons.add, size: 20),
          onPressed: onCreate,
          child: Text(l10n.newPreset),
        ),
      ],
      builder: (context, controller, child) {
        return Tooltip(
          message: l10n.preset,
          child: TextButton(
            key: const Key('minimal-preset-menu'),
            onPressed: controller.isOpen ? controller.close : controller.open,
            style: ButtonStyle(
              minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              ),
              foregroundColor: WidgetStatePropertyAll(colors.primaryText),
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.hovered) ||
                    states.contains(WidgetState.focused) ||
                    states.contains(WidgetState.pressed)) {
                  return colors.surfaceHover;
                }
                return Colors.transparent;
              }),
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: colors.mutedText,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FocusViewModeMenu extends StatelessWidget {
  const _FocusViewModeMenu({required this.viewMode, required this.onChanged});

  final FocusViewMode viewMode;
  final ValueChanged<FocusViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final target = viewMode == FocusViewMode.full
        ? FocusViewMode.minimal
        : FocusViewMode.full;
    return SizedBox.square(
      dimension: 48,
      child: Semantics(
        key: const Key('focus-details-menu'),
        label: context.l10n.moreFocusActions,
        container: true,
        button: true,
        child: PopupMenuButton<FocusViewMode>(
          tooltip: context.l10n.moreFocusActions,
          icon: const Icon(Icons.more_horiz),
          onSelected: onChanged,
          itemBuilder: (context) => [
            PopupMenuItem(
              key: const Key('focus-switch-view-mode'),
              value: target,
              child: Text(
                target == FocusViewMode.full
                    ? context.l10n.focusSwitchToFullView
                    : context.l10n.focusSwitchToMinimalView,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FocusActiveStage extends StatelessWidget {
  const FocusActiveStage({
    required this.run,
    required this.interval,
    required this.intervals,
    required this.remaining,
    required this.presets,
    required this.selectedPreset,
    required this.timerVisualStyle,
    required this.compact,
    required this.viewMode,
    this.showViewModeMenu = true,
    required this.repository,
    required this.onViewModeChanged,
    required this.onPresetChanged,
    required this.onCustomizePreset,
    required this.onCreatePreset,
    super.key,
  });

  final FocusRunItem run;
  final FocusIntervalItem interval;
  final List<FocusIntervalItem> intervals;
  final Duration remaining;
  final List<FocusPresetItem> presets;
  final FocusPresetItem? selectedPreset;
  final FocusTimerVisualStyle timerVisualStyle;
  final bool compact;
  final FocusViewMode viewMode;
  final bool showViewModeMenu;
  final FocusRepository repository;
  final ValueChanged<FocusViewMode> onViewModeChanged;
  final ValueChanged<String> onPresetChanged;
  final ValueChanged<FocusPresetItem> onCustomizePreset;
  final VoidCallback onCreatePreset;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final preset = selectedPreset;
    final full = viewMode == FocusViewMode.full;
    final primary = _buildFocusPrimaryAction(
      context,
      interval: interval,
      selectedPreset: preset,
      repository: repository,
    );
    final menu = _buildFocusMoreActionsMenu(
      context,
      run: run,
      interval: interval,
      remaining: remaining,
      presets: presets,
      selectedPreset: preset,
      compact: compact,
      minimal: !full,
      viewMode: viewMode,
      showViewModeMenu: showViewModeMenu,
      repository: repository,
      onViewModeChanged: onViewModeChanged,
      onPresetChanged: onPresetChanged,
      onCustomizePreset: onCustomizePreset,
      onCreatePreset: onCreatePreset,
    );
    final rhythm = preset == null
        ? null
        : buildFocusRhythm(
            preset: preset,
            targetWorkIntervals: run.targetWorkIntervals,
            intervals: intervals,
          );
    final phaseLabel = _phaseLabel(context, interval);
    final activeStepIndex = rhythm?.steps.indexWhere(
      (step) => step.sequence == interval.sequenceNumber,
    );
    final activeStepNumber = activeStepIndex == null || activeStepIndex < 0
        ? 1
        : activeStepIndex + 1;
    final sessionNumber = math.min(
      run.targetWorkIntervals,
      math.max(
        1,
        run.completedWorkIntervals + (interval.type == 'work' ? 1 : 0),
      ),
    );

    return Column(
      key: const Key('focus-state-active'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FocusModeDetails(
          visible: full && rhythm != null,
          child: rhythm == null
              ? const SizedBox.shrink()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.focusSessionProgress(
                        sessionNumber,
                        run.targetWorkIntervals,
                      ),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    SizedBox(height: compact ? 12 : 16),
                    FocusRhythmRail(
                      rhythm: rhythm,
                      activeSequence: interval.sequenceNumber,
                      activeProgress: _progress(interval, remaining),
                      recenterToken:
                          '${run.id}:${interval.id}:${interval.status}:'
                          '${interval.sequenceNumber}',
                      semanticsLabel: l10n.focusRhythmSummary(
                        activeStepNumber,
                        rhythm.steps.length,
                        phaseLabel,
                        _activeStatusLabel(context, interval.status),
                      ),
                      compact: compact,
                    ),
                    SizedBox(height: compact ? 32 : 44),
                  ],
                ),
        ),
        _FocusTimerStage(
          key: const Key('focus-primary-stage'),
          interval: interval,
          remaining: remaining,
          style: timerVisualStyle,
          compact: compact,
        ),
        _FocusModeDetails(
          visible: full,
          child: run.taskId == null
              ? SizedBox(height: compact ? 28 : 36)
              : _FocusLinkedTaskContext(
                  taskId: run.taskId!,
                  projectId: run.projectId,
                  compact: compact,
                ),
        ),
        if (!full) const SizedBox(height: 32),
        _FocusActiveActions(
          run: run,
          interval: interval,
          remaining: remaining,
          selectedPreset: preset,
          compact: compact,
          minimal: !full,
          repository: repository,
          primary: primary,
          menu: menu,
        ),
      ],
    );
  }
}

class _FocusModeDetails extends StatelessWidget {
  const _FocusModeDetails({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: _motionDuration(context, 200),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SizeTransition(
          sizeFactor: animation,
          alignment: Alignment.topCenter,
          child: child,
        ),
      ),
      child: visible
          ? KeyedSubtree(key: const Key('focus-full-details'), child: child)
          : const SizedBox.shrink(key: Key('focus-minimal-details')),
    );
  }
}

Duration _motionDuration(BuildContext context, int milliseconds) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : Duration(milliseconds: milliseconds);

class _ElasticFocusButton extends StatefulWidget {
  const _ElasticFocusButton({required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  @override
  State<_ElasticFocusButton> createState() => _ElasticFocusButtonState();
}

class _ElasticFocusButtonState extends State<_ElasticFocusButton> {
  bool _pressed = false;

  void _setPressed(bool pressed) {
    if (!widget.enabled || _pressed == pressed) {
      return;
    }
    setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: _motionDuration(context, _pressed ? 80 : 180),
      curve: Curves.easeOutCubic,
      tween: Tween(begin: 1, end: _pressed ? 0.96 : 1),
      builder: (context, scale, child) => Transform.scale(
        key: const Key('focus-primary-action-elastic'),
        scale: scale,
        child: child,
      ),
      child: Listener(
        onPointerDown: (_) => _setPressed(true),
        onPointerUp: (_) => _setPressed(false),
        onPointerCancel: (_) => _setPressed(false),
        child: widget.child,
      ),
    );
  }
}
