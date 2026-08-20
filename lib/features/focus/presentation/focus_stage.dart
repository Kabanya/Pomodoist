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
    required this.compact,
    required this.onPresetSelected,
    required this.onStart,
    required this.onCustomize,
    required this.onCreate,
    super.key,
  });

  final List<FocusPresetItem> presets;
  final FocusPresetItem? selectedPreset;
  final bool compact;
  final ValueChanged<String> onPresetSelected;
  final Future<void> Function()? onStart;
  final VoidCallback? onCustomize;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final preset = selectedPreset;
    final cadence = preset == null
        ? 0
        : preset.intervalsBeforeLongBreak.clamp(1, 12);
    final rhythm = preset == null
        ? null
        : buildFocusRhythm(preset: preset, targetWorkIntervals: cadence);

    return Column(
      key: const Key('focus-state-idle'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (rhythm != null) ...[
          Text(
            l10n.focusSessionProgress(1, cadence),
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.secondaryText),
          ),
          SizedBox(height: compact ? 12 : 16),
          FocusRhythmRail(
            rhythm: rhythm,
            semanticsLabel: l10n.focusRhythmPreviewSummary(rhythm.steps.length),
            compact: compact,
          ),
        ],
        SizedBox(height: compact ? 28 : 42),
        Column(
          key: const Key('focus-primary-stage'),
          children: [
            Icon(
              Icons.timer_outlined,
              size: compact ? 30 : 34,
              color: colors.mutedText,
            ),
            const SizedBox(height: 10),
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
            if (preset != null) ...[
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
        Wrap(
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
        const SizedBox(height: 22),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              key: const Key('focus-primary-action'),
              onPressed: onStart,
              icon: const Icon(Icons.play_arrow),
              label: Text(l10n.startFocus),
            ),
            OutlinedButton.icon(
              onPressed: onCustomize,
              icon: const Icon(Icons.tune),
              label: Text(l10n.customize),
            ),
            TextButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: Text(l10n.newPreset),
            ),
          ],
        ),
      ],
    );
  }
}

class FocusMinimalIdleStage extends StatelessWidget {
  const FocusMinimalIdleStage({
    required this.presets,
    required this.selectedPreset,
    required this.onPresetSelected,
    required this.onStart,
    required this.onCustomize,
    required this.onCreate,
    super.key,
  });

  final List<FocusPresetItem> presets;
  final FocusPresetItem? selectedPreset;
  final ValueChanged<String> onPresetSelected;
  final Future<void> Function()? onStart;
  final VoidCallback? onCustomize;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final preset = selectedPreset;

    return Align(
      key: const Key('focus-state-idle'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Column(
              key: const Key('focus-primary-stage'),
              children: [
                Icon(Icons.timer_outlined, size: 32, color: colors.mutedText),
                const SizedBox(height: 14),
                _MinimalPresetMenu(
                  presets: presets,
                  selectedPreset: preset,
                  onSelected: onPresetSelected,
                  onCustomize: onCustomize,
                  onCreate: onCreate,
                ),
                const SizedBox(height: 6),
                Text(
                  preset == null
                      ? l10n.preparingFocus
                      : l10n.minutesWork((preset.workSeconds / 60).round()),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: colors.primaryText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            Align(
              child: FilledButton.icon(
                key: const Key('focus-primary-action'),
                style: FilledButton.styleFrom(minimumSize: const Size(176, 48)),
                onPressed: onStart,
                icon: const Icon(Icons.play_arrow),
                label: Text(l10n.startFocus),
              ),
            ),
          ],
        ),
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
    required this.repository,
    required this.onPresetChanged,
    required this.onCustomizePreset,
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
  final FocusRepository repository;
  final ValueChanged<String> onPresetChanged;
  final ValueChanged<FocusPresetItem> onCustomizePreset;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final preset = selectedPreset;
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
        if (rhythm != null) ...[
          Text(
            l10n.focusSessionProgress(sessionNumber, run.targetWorkIntervals),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          SizedBox(height: compact ? 12 : 16),
          FocusRhythmRail(
            rhythm: rhythm,
            activeSequence: interval.sequenceNumber,
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
        _FocusTimerStage(
          key: const Key('focus-primary-stage'),
          interval: interval,
          remaining: remaining,
          style: timerVisualStyle,
          compact: compact,
        ),
        if (run.taskId case final taskId?)
          _FocusLinkedTaskContext(
            taskId: taskId,
            projectId: run.projectId,
            compact: compact,
          )
        else
          SizedBox(height: compact ? 28 : 36),
        _FocusActiveActions(
          run: run,
          interval: interval,
          remaining: remaining,
          presets: presets,
          selectedPreset: preset,
          compact: compact,
          repository: repository,
          onPresetChanged: onPresetChanged,
          onCustomizePreset: onCustomizePreset,
        ),
      ],
    );
  }
}

class FocusMinimalActiveStage extends StatelessWidget {
  const FocusMinimalActiveStage({
    required this.interval,
    required this.remaining,
    required this.selectedPreset,
    required this.timerVisualStyle,
    required this.repository,
    super.key,
  });

  final FocusIntervalItem interval;
  final Duration remaining;
  final FocusPresetItem? selectedPreset;
  final FocusTimerVisualStyle timerVisualStyle;
  final FocusRepository repository;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final ready = interval.status == 'ready';
    final paused = interval.status == 'paused';
    final allowPause = selectedPreset?.allowPause ?? true;

    return Column(
      key: const Key('focus-state-active'),
      mainAxisSize: MainAxisSize.min,
      children: [
        _FocusTimerStage(
          key: const Key('focus-primary-stage'),
          interval: interval,
          remaining: remaining,
          style: timerVisualStyle,
          compact: true,
        ),
        const SizedBox(height: 32),
        _withPauseAvailabilitySemantics(
          context,
          unavailable: !ready && !paused && !allowPause,
          child: FilledButton.icon(
            key: const Key('focus-primary-action'),
            style: FilledButton.styleFrom(minimumSize: const Size(176, 48)),
            onPressed: ready
                ? () => unawaited(_startReady(context))
                : paused || allowPause
                ? () => unawaited(_togglePause(context, paused))
                : null,
            icon: Icon(ready || paused ? Icons.play_arrow : Icons.pause),
            label: Text(
              ready
                  ? l10n.startInterval
                  : paused
                  ? l10n.resume
                  : l10n.pause,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _startReady(BuildContext context) async {
    await repository.startReadyInterval();
    if (!context.mounted) return;
    showActionFeedback(
      context,
      message: context.l10n.intervalStarted,
      icon: Icons.play_circle_outline,
      haptic: AppHapticCue.none,
    );
  }

  Future<void> _togglePause(BuildContext context, bool paused) async {
    if (paused) {
      await repository.resumeActiveInterval();
    } else {
      await repository.pauseActiveInterval();
    }
    if (!context.mounted) return;
    showActionFeedback(
      context,
      message: paused ? context.l10n.resume : context.l10n.pause,
      icon: paused ? Icons.play_circle_outline : Icons.pause_circle_outline,
      haptic: AppHapticCue.none,
    );
  }
}
