import 'package:pomodoist/ui/core/widgets/app_action_menu.dart';
import 'package:pomodoist/ui/focus/view_models/focus_view_model.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons, ShadContextMenuItem;

import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/routing/task_detail_navigation.dart';
import 'package:pomodoist/ui/core/localization/formatters.dart';
import 'package:pomodoist/ui/core/themes/app_motion.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/core/widgets/action_feedback.dart';
import 'package:pomodoist/domain/models/tasks/project_colors.dart';
import 'package:pomodoist/ui/tasks/widgets/project_localizations.dart';
import 'package:pomodoist/ui/tasks/widgets/project_color_picker.dart';
import 'package:pomodoist/domain/models/focus/focus_models.dart';
import 'package:pomodoist/ui/focus/widgets/focus_rhythm.dart';
import 'package:pomodoist/ui/focus/widgets/focus_preset_localizations.dart';
import 'package:pomodoist/ui/focus/widgets/focus_rhythm_rail.dart';
import 'package:pomodoist/domain/models/focus/focus_view_mode.dart';

part 'focus_active_controls.dart';
part 'focus_timer_stage.dart';
part 'focus_full_layout.dart';

final class FocusStageActions {
  const FocusStageActions({
    required this.startReadyInterval,
    required this.pauseActiveInterval,
    required this.resumeActiveInterval,
    required this.completeActiveInterval,
    required this.skipActiveInterval,
    required this.stopActiveRun,
  });

  final Future<void> Function() startReadyInterval;
  final Future<void> Function() pauseActiveInterval;
  final Future<void> Function() resumeActiveInterval;
  final Future<void> Function() completeActiveInterval;
  final Future<void> Function() skipActiveInterval;
  final Future<void> Function({required StopFocusReason reason}) stopActiveRun;
}

class FocusIdleStage extends StatelessWidget {
  const FocusIdleStage({
    required this.presets,
    required this.selectedPreset,
    required this.timerVisualStyle,
    required this.compact,
    required this.viewMode,
    this.sessionDisplay = FocusSessionDisplay.compact,
    this.onSessionDisplayChanged,
    this.minHeight = 0,
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
  final FocusSessionDisplay sessionDisplay;
  final ValueChanged<FocusSessionDisplay>? onSessionDisplayChanged;
  final double minHeight;
  final bool showViewModeMenu;
  final ValueChanged<String> onPresetSelected;
  final ValueChanged<FocusViewMode> onViewModeChanged;
  final Future<void> Function()? onStart;
  final VoidCallback? onCustomize;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final preset = selectedPreset;
    final full = viewMode == FocusViewMode.full;
    final cadence = preset?.intervalsBeforeLongBreak.clamp(1, 12) ?? 0;
    final rhythm = preset == null
        ? null
        : buildFocusRhythm(preset: preset, targetWorkIntervals: cadence);
    final primary = _FocusPrimaryButton(
      minimal: !full,
      label: l10n.startFocus,
      icon: LucideIcons.play,
      onPressed: onStart,
    );
    final presetMenu = _MinimalPresetMenu(
      presets: presets,
      selectedPreset: preset,
      onSelected: onPresetSelected,
      onCustomize: onCustomize,
      onCreate: onCreate,
    );
    final sessionLabel = preset == null
        ? l10n.noPreset
        : l10n.focusSessionProgress(1, cadence);
    final nextLabel = _nextIntervalLabel(
      context,
      rhythm?.steps.skip(1).firstOrNull,
    );

    return ConstrainedBox(
      key: const Key('focus-state-idle'),
      constraints: BoxConstraints(minHeight: full ? minHeight : 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (full)
                Column(
                  children: [
                    _FocusFullHeader(
                      preset: presetMenu,
                      onMinimize: showViewModeMenu
                          ? () => onViewModeChanged(FocusViewMode.minimal)
                          : null,
                      menu: _FocusViewModeMenu(
                        viewMode: viewMode,
                        onChanged: onViewModeChanged,
                        showViewModeMenu: showViewModeMenu,
                        sessionDisplay: sessionDisplay,
                        onSessionDisplayChanged: onSessionDisplayChanged,
                      ),
                    ),
                    if (rhythm != null) ...[
                      const SizedBox(height: 24),
                      _FocusSessionOverview(
                        rhythm: rhythm,
                        label: sessionLabel,
                        presetName: preset!.displayName(l10n),
                        semanticsLabel: l10n.focusRhythmPreviewSummary(
                          rhythm.steps.length,
                        ),
                        compact: compact,
                        display: sessionDisplay,
                      ),
                    ],
                  ],
                ),
              Padding(
                padding: EdgeInsets.only(
                  top: full ? (compact ? 32 : 64) : 8,
                  bottom: 32,
                ),
                child: Column(
                  key: const Key('focus-primary-stage'),
                  children: [
                    if (full)
                      Text(
                        l10n.noActiveSession,
                        key: const Key('focus-idle-full-copy'),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium,
                      )
                    else
                      presetMenu,
                    const SizedBox(height: 28),
                    _FocusMinimalTimer(
                      style: timerVisualStyle,
                      remainingLabel: preset == null
                          ? '--:--'
                          : formatDurationCompact(
                              Duration(seconds: preset.workSeconds),
                            ),
                      progress: 0,
                      color: context.appColors.accent,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (full)
            _FocusControlDock(
              summary: nextLabel == null
                  ? sessionLabel
                  : '$sessionLabel\n$nextLabel',
              primary: primary,
            )
          else
            Center(child: primary),
        ],
      ),
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
    final title = selectedPreset?.displayName(l10n) ?? l10n.noPreset;

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
                  ? Icon(LucideIcons.check, size: 18, color: colors.accent)
                  : null,
            ),
            onPressed: () {
              if (preset.id != selectedPreset?.id) {
                onSelected(preset.id);
              }
            },
            child: Text(preset.displayName(l10n)),
          ),
        if (presets.isNotEmpty) const Divider(height: 1),
        MenuItemButton(
          key: const Key('minimal-preset-customize'),
          leadingIcon: const Icon(LucideIcons.slidersHorizontal, size: 20),
          onPressed: onCustomize,
          child: Text(l10n.customize),
        ),
        MenuItemButton(
          key: const Key('minimal-preset-create'),
          leadingIcon: const Icon(LucideIcons.plus, size: 20),
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
              foregroundColor: WidgetStatePropertyAll(colors.secondaryText),
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
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: colors.secondaryText,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  LucideIcons.chevronDown,
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
  const _FocusViewModeMenu({
    required this.viewMode,
    required this.onChanged,
    required this.sessionDisplay,
    required this.onSessionDisplayChanged,
    required this.showViewModeMenu,
  });

  final FocusViewMode viewMode;
  final ValueChanged<FocusViewMode> onChanged;
  final FocusSessionDisplay sessionDisplay;
  final ValueChanged<FocusSessionDisplay>? onSessionDisplayChanged;
  final bool showViewModeMenu;

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
        child: AppActionMenu(
          tooltip: context.l10n.moreFocusActions,
          items: [
            ..._sessionDisplayMenuItems(
              context,
              sessionDisplay,
              onSessionDisplayChanged,
            ),
            if (showViewModeMenu)
              ShadContextMenuItem(
                height: 44,
                key: const Key('focus-switch-view-mode'),
                onPressed: () => onChanged(target),
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
    this.sessionDisplay = FocusSessionDisplay.compact,
    this.onSessionDisplayChanged,
    this.minHeight = 0,
    required this.actions,
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
  final FocusSessionDisplay sessionDisplay;
  final ValueChanged<FocusSessionDisplay>? onSessionDisplayChanged;
  final double minHeight;
  final FocusStageActions actions;
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
      actions: actions,
      minimal: !full,
    );
    final menu = _buildFocusMoreActionsMenu(
      context,
      presets: presets,
      selectedPreset: preset,
      minimal: !full,
      viewMode: viewMode,
      showViewModeMenu: showViewModeMenu,
      sessionDisplay: sessionDisplay,
      onSessionDisplayChanged: onSessionDisplayChanged,
      actions: actions,
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

    final sessionLabel = l10n.focusSessionProgress(
      sessionNumber,
      run.targetWorkIntervals,
    );
    final nextStep = rhythm?.steps
        .where((step) => step.sequence > interval.sequenceNumber)
        .firstOrNull;
    final nextLabel = _nextIntervalLabel(context, nextStep);
    return ConstrainedBox(
      key: const Key('focus-state-active'),
      constraints: BoxConstraints(minHeight: full ? minHeight : 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _FocusModeDetails(
                visible: full,
                child: Column(
                  children: [
                    _FocusFullHeader(
                      preset: _MinimalPresetMenu(
                        presets: presets,
                        selectedPreset: preset,
                        onSelected: onPresetChanged,
                        onCustomize: preset == null
                            ? null
                            : () => onCustomizePreset(preset),
                        onCreate: onCreatePreset,
                      ),
                      menu: menu,
                      onMinimize: showViewModeMenu
                          ? () => onViewModeChanged(FocusViewMode.minimal)
                          : null,
                    ),
                    if (rhythm != null) ...[
                      const SizedBox(height: 24),
                      _FocusSessionOverview(
                        rhythm: rhythm,
                        label: sessionLabel,
                        presetName: preset!.displayName(l10n),
                        compact: compact,
                        display: sessionDisplay,
                        activeSequence: interval.sequenceNumber,
                        activeProgress: _progress(interval, remaining),
                        recenterToken:
                            '${run.id}:${interval.id}:${interval.status}:${interval.sequenceNumber}',
                        semanticsLabel: l10n.focusRhythmSummary(
                          activeStepNumber,
                          rhythm.steps.length,
                          phaseLabel,
                          _activeStatusLabel(context, interval.status),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.only(
                  top: full ? (compact ? 32 : 64) : 0,
                  bottom: 32,
                ),
                child: Column(
                  children: [
                    _FocusModeDetails(
                      visible: full && run.taskId != null,
                      child: run.taskId == null
                          ? const SizedBox.shrink()
                          : _FocusLinkedTaskContext(
                              taskId: run.taskId!,
                              projectId: run.projectId,
                              compact: compact,
                            ),
                    ),
                    _FocusTimerStage(
                      key: const Key('focus-primary-stage'),
                      interval: interval,
                      remaining: remaining,
                      style: timerVisualStyle,
                      compact: compact,
                      minimal: !full,
                    ),
                  ],
                ),
              ),
            ],
          ),
          _FocusActiveActions(
            interval: interval,
            remaining: remaining,
            selectedPreset: preset,
            minimal: !full,
            actions: actions,
            primary: primary,
            summary: nextLabel == null
                ? sessionLabel
                : '$sessionLabel\n$nextLabel',
          ),
        ],
      ),
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
      duration: AppMotion.duration(context, AppMotion.state),
      switchInCurve: AppMotion.curve,
      switchOutCurve: AppMotion.curve,
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
