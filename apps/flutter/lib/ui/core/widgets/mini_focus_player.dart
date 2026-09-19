import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pomodoist/ui/core/themes/app_motion.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:pomodoist/domain/models/focus/focus_models.dart';
import 'package:pomodoist/domain/models/focus/focus_view_mode.dart';
import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/localization/formatters.dart';
import 'package:pomodoist/ui/focus/view_models/mini_focus_view_model.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/core/widgets/action_feedback.dart';

class MiniFocusPlayer extends ConsumerWidget {
  const MiniFocusPlayer({
    this.floating = false,
    this.dailyContext = false,
    super.key,
  });

  final bool floating;
  final bool dailyContext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(miniFocusViewModelProvider);
    if (!state.visible) {
      return const SizedBox.shrink();
    }
    final interval = state.interval!;
    final run = state.run!;
    final remaining = state.remaining!;
    final preset = state.preset;
    final viewModel = ref.read(miniFocusViewModelProvider.notifier);
    final viewMode = state.viewMode;
    final ready = interval.status == 'ready';
    final paused = interval.status == 'paused';
    final l10n = context.l10n;
    final colors = context.appColors;
    if (dailyContext) {
      final task = run.taskId == null ? null : state.task;
      final title = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${l10n.todayFocusingOn} · '
            '${ready ? '${l10n.readyShort} · ' : ''}${_intervalLabel(context, interval)}',
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: colors.secondaryText),
          ),
          const SizedBox(height: 4),
          Text(
            task?.content ?? l10n.navFocus,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ],
      );
      final controls = Wrap(
        spacing: 12,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            formatDurationCompact(remaining),
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.merge(AppTheme.monoTextStyle),
          ),
          IconButton(
            tooltip: ready
                ? l10n.startInterval
                : (paused ? l10n.resume : l10n.pause),
            onPressed: ready
                ? () => unawaited(_startReadyInterval(context, viewModel.start))
                : (preset?.allowPause ?? false)
                ? () => unawaited(
                    _toggleFocusPause(context, viewModel.togglePause, paused),
                  )
                : null,
            icon: Icon(ready || paused ? LucideIcons.play : LucideIcons.pause),
          ),
          TextButton(
            onPressed: () => context.go('/focus'),
            child: Text(l10n.openFocus),
          ),
        ],
      );
      return DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceTint,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: LayoutBuilder(
            builder: (context, constraints) => constraints.maxWidth >= 600
                ? Row(
                    children: [
                      Expanded(child: title),
                      const SizedBox(width: 16),
                      Flexible(child: controls),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [title, const SizedBox(height: 4), controls],
                  ),
          ),
        ),
      );
    }
    if (viewMode == FocusViewMode.minimal) {
      return _MinimalMiniFocusPlayer(
        interval: interval,
        remaining: remaining,
        preset: preset,
        onStart: viewModel.start,
        onTogglePause: viewModel.togglePause,
        onStop: viewModel.stop,
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
                    ? () => unawaited(
                        _startReadyInterval(context, viewModel.start),
                      )
                    : (preset?.allowPause ?? true)
                    ? () => unawaited(
                        _toggleFocusPause(
                          context,
                          viewModel.togglePause,
                          paused,
                        ),
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
                onPressed: () => unawaited(_stopFocus(context, viewModel.stop)),
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
}

class _MinimalMiniFocusPlayer extends StatelessWidget {
  const _MinimalMiniFocusPlayer({
    required this.interval,
    required this.remaining,
    required this.preset,
    required this.onStart,
    required this.onTogglePause,
    required this.onStop,
    required this.ready,
    required this.paused,
    required this.floating,
  });

  final FocusIntervalItem interval;
  final Duration remaining;
  final FocusPresetItem? preset;
  final Future<void> Function() onStart;
  final Future<void> Function() onTogglePause;
  final Future<void> Function() onStop;
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
                    ? () => unawaited(_startReadyInterval(context, onStart))
                    : (preset?.allowPause ?? true)
                    ? () => unawaited(
                        _toggleFocusPause(context, onTogglePause, paused),
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
                      unawaited(_stopFocus(context, onStop));
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
  Future<void> Function() start,
) async {
  try {
    await start();
  } catch (_) {
    if (context.mounted) _showFocusActionError(context);
    return;
  }
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
  Future<void> Function() toggle,
  bool paused,
) async {
  try {
    await toggle();
  } catch (_) {
    if (context.mounted) _showFocusActionError(context);
    return;
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
  Future<void> Function() stop,
) async {
  try {
    await stop();
  } catch (_) {
    if (context.mounted) _showFocusActionError(context);
    return;
  }
  if (!context.mounted) {
    return;
  }
  showActionFeedback(
    context,
    message: context.l10n.focusStopped,
    icon: LucideIcons.circleStop,
  );
}

void _showFocusActionError(BuildContext context) {
  showActionFeedback(
    context,
    message: context.l10n.focusActionFailed,
    icon: LucideIcons.circleAlert,
    haptic: AppHapticCue.none,
  );
}
