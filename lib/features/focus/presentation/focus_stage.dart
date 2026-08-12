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
                Text(
                  preset?.name ?? l10n.noPreset,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
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
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: _MinimalPresetSelector(
                    presets: presets,
                    selectedPreset: preset,
                    onSelected: onPresetSelected,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox.square(
                  dimension: 48,
                  child: PopupMenuButton<_MinimalIdleAction>(
                    key: const Key('minimal-idle-more-menu'),
                    tooltip: l10n.moreFocusOptions,
                    icon: const Icon(Icons.more_horiz),
                    onSelected: (action) {
                      switch (action) {
                        case _MinimalIdleAction.customize:
                          onCustomize?.call();
                        case _MinimalIdleAction.create:
                          onCreate();
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: _MinimalIdleAction.customize,
                        enabled: onCustomize != null,
                        child: Text(l10n.customize),
                      ),
                      PopupMenuItem(
                        value: _MinimalIdleAction.create,
                        child: Text(l10n.newPreset),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MinimalPresetSelector extends StatelessWidget {
  const _MinimalPresetSelector({
    required this.presets,
    required this.selectedPreset,
    required this.onSelected,
  });

  final List<FocusPresetItem> presets;
  final FocusPresetItem? selectedPreset;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    if (presets.isEmpty) {
      return InputDecorator(
        key: const Key('minimal-preset-select'),
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: const Icon(Icons.tune),
          labelText: context.l10n.preset,
        ),
        child: Text(context.l10n.noPreset),
      );
    }
    return DropdownButtonFormField<String>(
      key: const Key('minimal-preset-select'),
      initialValue: selectedPreset?.id,
      decoration: InputDecoration(
        isDense: true,
        prefixIcon: const Icon(Icons.tune),
        labelText: context.l10n.preset,
      ),
      items: [
        for (final preset in presets)
          DropdownMenuItem(value: preset.id, child: Text(preset.name)),
      ],
      onChanged: (id) {
        if (id != null && id != selectedPreset?.id) {
          onSelected(id);
        }
      },
    );
  }
}

enum _MinimalIdleAction { customize, create }

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
