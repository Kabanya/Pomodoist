import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/ui/tasks/widgets/task_branch_widgets.dart';
import 'package:pomodoist/ui/core/widgets/app_action_menu.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pomodoist/ui/core/widgets/bottom_panel_surface.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons, ShadContextMenuItem;
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
  const MiniFocusPlayer({this.floating = false, super.key});

  final bool floating;

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
    final task = run.taskId == null ? null : state.task;
    if (viewMode == FocusViewMode.minimal) {
      return _MinimalMiniFocusPlayer(
        interval: interval,
        task: task,
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
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
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
                      if (task != null)
                        TaskHierarchySummary(task: task, compact: true),
                    ],
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
                        _toggleFocusPause(context, viewModel.togglePause),
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
    required this.task,
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
  final TaskItem? task;
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
    final task = this.task;
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
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
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
                      if (task != null)
                        TaskHierarchySummary(task: task, compact: true),
                    ],
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
                    ? () => unawaited(_toggleFocusPause(context, onTogglePause))
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
              AppActionMenu(
                key: const Key('minimal-mini-focus-more-menu'),
                tooltip: l10n.moreFocusActions,
                items: [
                  ShadContextMenuItem(
                    height: 44,
                    onPressed: () => unawaited(_stopFocus(context, onStop)),
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
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: BottomPanelSurface(
      floating: floating,
      surfaceKey: const Key('mini-focus-player-surface'),
      child: child,
    ),
  );
}

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
}

Future<void> _toggleFocusPause(
  BuildContext context,
  Future<void> Function() toggle,
) async {
  try {
    await toggle();
  } catch (_) {
    if (context.mounted) _showFocusActionError(context);
    return;
  }
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
}

void _showFocusActionError(BuildContext context) {
  showActionFeedback(
    context,
    message: context.l10n.focusActionFailed,
    icon: LucideIcons.circleAlert,
    haptic: AppHapticCue.none,
  );
}
