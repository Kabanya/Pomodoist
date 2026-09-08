import 'dart:async';

import 'package:flutter/material.dart';
import '../theme/app_motion.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/focus/domain/focus_models.dart';
import '../../features/focus/presentation/focus_view_mode.dart';
import '../app_l10n.dart';
import '../formatters.dart';
import '../providers.dart';
import '../theme/app_theme.dart';
import 'action_feedback.dart';

class MiniFocusPlayer extends ConsumerWidget {
  const MiniFocusPlayer({this.floating = false, super.key});

  final bool floating;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final interval = ref.watch(activeFocusIntervalProvider).value;
    final run = ref.watch(activeFocusRunProvider).value;
    final remaining = ref.watch(activeFocusRemainingProvider);
    if (interval == null || run == null || remaining == null) {
      return const SizedBox.shrink();
    }

    final repository = ref.watch(focusRepositoryProvider);
    final presets = ref.watch(focusPresetsProvider).value ?? const [];
    final preset = _findPreset(presets, run.presetId);
    final viewMode = ref.watch(focusViewModeProvider);
    final ready = interval.status == 'ready';
    final paused = interval.status == 'paused';
    final l10n = context.l10n;
    final colors = context.appColors;
    if (viewMode == FocusViewMode.minimal) {
      return _MinimalMiniFocusPlayer(
        interval: interval,
        remaining: remaining,
        preset: preset,
        repository: repository,
        ready: ready,
        paused: paused,
        floating: floating,
      );
    }

    return _MiniFocusPlayerFrame(
      floating: floating,
      child: InkWell(
        onTap: () => context.go('/focus'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(
                interval.type == 'work'
                    ? LucideIcons.timer
                    : LucideIcons.coffee,
                color: colors.accent,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${ready ? '${l10n.readyShort} · ' : ''}'
                  '${_intervalLabel(context, interval)} · '
                  '${formatDurationCompact(remaining)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.merge(AppTheme.monoTextStyle)
                      .copyWith(
                        color: colors.primaryText,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              IconButton(
                tooltip: ready
                    ? l10n.startInterval
                    : (paused ? l10n.resume : l10n.pause),
                onPressed: ready
                    ? () => unawaited(_startReadyInterval(context, repository))
                    : (preset?.allowPause ?? true)
                    ? () => unawaited(
                        _toggleFocusPause(context, repository, paused),
                      )
                    : null,
                style: IconButton.styleFrom(
                  backgroundColor: colors.accentTint,
                  foregroundColor: colors.accent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: Icon(
                  ready || paused ? LucideIcons.play : LucideIcons.pause,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: l10n.commonStop,
                onPressed: () => unawaited(_stopFocus(context, repository)),
                icon: const Icon(LucideIcons.square),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _intervalLabel(BuildContext context, FocusIntervalItem interval) {
    final l10n = context.l10n;
    return switch (interval.type) {
      'work' => l10n.work,
      'longBreak' => l10n.longBreak,
      _ => l10n.breakLabel,
    };
  }

  FocusPresetItem? _findPreset(List<FocusPresetItem> presets, String id) {
    for (final preset in presets) {
      if (preset.id == id) {
        return preset;
      }
    }
    return null;
  }
}

class _MinimalMiniFocusPlayer extends StatelessWidget {
  const _MinimalMiniFocusPlayer({
    required this.interval,
    required this.remaining,
    required this.preset,
    required this.repository,
    required this.ready,
    required this.paused,
    required this.floating,
  });

  final FocusIntervalItem interval;
  final Duration remaining;
  final FocusPresetItem? preset;
  final FocusRepository repository;
  final bool ready;
  final bool paused;
  final bool floating;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    return _MiniFocusPlayerFrame(
      floating: floating,
      child: InkWell(
        onTap: () => context.go('/focus'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(
                interval.type == 'work'
                    ? LucideIcons.timer
                    : LucideIcons.coffee,
                color: colors.accent,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${ready ? '${l10n.readyShort} · ' : ''}'
                  '${formatDurationCompact(remaining)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.merge(AppTheme.monoTextStyle)
                      .copyWith(
                        color: colors.primaryText,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              IconButton(
                tooltip: ready
                    ? l10n.startInterval
                    : (paused ? l10n.resume : l10n.pause),
                onPressed: ready
                    ? () => unawaited(_startReadyInterval(context, repository))
                    : (preset?.allowPause ?? true)
                    ? () => unawaited(
                        _toggleFocusPause(context, repository, paused),
                      )
                    : null,
                style: IconButton.styleFrom(
                  backgroundColor: colors.accentTint,
                  foregroundColor: colors.accent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: Icon(
                  ready || paused ? LucideIcons.play : LucideIcons.pause,
                ),
              ),
              PopupMenuButton<_MiniFocusAction>(
                popUpAnimationStyle: AnimationStyle(
                  duration: AppMotion.duration(context, AppMotion.popup),
                  reverseDuration: AppMotion.duration(context, AppMotion.popup),
                  curve: AppMotion.curve,
                ),
                key: const Key('minimal-mini-focus-more-menu'),
                tooltip: l10n.moreFocusActions,
                icon: const Icon(LucideIcons.ellipsis),
                onSelected: (action) {
                  switch (action) {
                    case _MiniFocusAction.stop:
                      unawaited(_stopFocus(context, repository));
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: _MiniFocusAction.stop,
                    child: Text(l10n.commonStop),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniFocusPlayerFrame extends StatelessWidget {
  const _MiniFocusPlayerFrame({required this.floating, required this.child});

  final bool floating;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final radius = floating ? BorderRadius.circular(12) : BorderRadius.zero;
    final box = AnimatedContainer(
      duration: AppMotion.duration(context, AppMotion.state),
      curve: AppMotion.curve,
      key: const Key('mini-focus-player-surface'),
      decoration: BoxDecoration(
        color: colors.surface,
        border: floating
            ? Border.all(color: colors.border)
            : Border(top: BorderSide(color: colors.border)),
        borderRadius: floating ? radius : null,
        boxShadow: floating
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.10),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        clipBehavior: floating ? Clip.antiAlias : Clip.none,
        child: child,
      ),
    );

    return SafeArea(
      top: false,
      child: floating
          ? Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: box,
            )
          : box,
    );
  }
}

enum _MiniFocusAction { stop }

Future<void> _startReadyInterval(
  BuildContext context,
  FocusRepository repository,
) async {
  await repository.startReadyInterval();
  if (!context.mounted) {
    return;
  }
  showActionFeedback(
    context,
    message: context.l10n.intervalStarted,
    icon: LucideIcons.circlePlay,
    haptic: AppHapticCue.none,
  );
}

Future<void> _toggleFocusPause(
  BuildContext context,
  FocusRepository repository,
  bool paused,
) async {
  if (paused) {
    await repository.resumeActiveInterval();
  } else {
    await repository.pauseActiveInterval();
  }
  if (!context.mounted) {
    return;
  }
  showActionFeedback(
    context,
    message: paused ? context.l10n.resume : context.l10n.pause,
    icon: paused ? LucideIcons.circlePlay : LucideIcons.circlePause,
    haptic: AppHapticCue.none,
  );
}

Future<void> _stopFocus(
  BuildContext context,
  FocusRepository repository,
) async {
  await repository.stopActiveRun(reason: StopFocusReason.stopped);
  if (!context.mounted) {
    return;
  }
  showActionFeedback(
    context,
    message: context.l10n.focusStopped,
    icon: LucideIcons.circleStop,
  );
}
