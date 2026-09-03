part of 'focus_stage.dart';

class _FocusLinkedTaskContext extends ConsumerWidget {
  const _FocusLinkedTaskContext({
    required this.taskId,
    required this.projectId,
    required this.compact,
  });

  final String taskId;
  final String? projectId;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final task = ref.watch(taskProvider(taskId)).value;
    if (task == null || task.isDeleted) {
      return SizedBox(height: compact ? 28 : 36);
    }
    final projects = ref.watch(projectsProvider).value ?? const <ProjectItem>[];
    final resolvedProjectId = projectId ?? task.projectId;
    ProjectItem? project;
    for (final candidate in projects) {
      if (candidate.id == resolvedProjectId && !candidate.isDeleted) {
        project = candidate;
        break;
      }
    }

    return Padding(
      key: const Key('focus-task-context'),
      padding: EdgeInsets.only(
        top: compact ? 18 : 22,
        bottom: compact ? 26 : 32,
      ),
      child: Column(
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: TextButton(
              key: const Key('focus-linked-task'),
              style: TextButton.styleFrom(
                foregroundColor: context.appColors.primaryText,
                minimumSize: const Size(48, 48),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                textStyle: Theme.of(context).textTheme.titleLarge,
              ),
              onPressed: () =>
                  context.push('/task/${Uri.encodeComponent(task.id)}'),
              child: Text(
                task.content,
                maxLines: compact ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ),
          if (project != null) ...[
            const SizedBox(height: 4),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '#',
                    style: TextStyle(
                      color: projectColorValue(effectiveProjectColor(project)),
                    ),
                  ),
                  TextSpan(
                    text: ' ${project.name}',
                    style: TextStyle(color: context.appColors.secondaryText),
                  ),
                ],
              ),
              key: const Key('focus-project-context'),
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }
}

class _FocusActiveActions extends StatelessWidget {
  const _FocusActiveActions({
    required this.interval,
    required this.remaining,
    required this.selectedPreset,
    required this.compact,
    required this.minimal,
    required this.repository,
    required this.primary,
    required this.menu,
  });

  final FocusIntervalItem interval;
  final Duration remaining;
  final FocusPresetItem? selectedPreset;
  final bool compact;
  final bool minimal;
  final FocusRepository repository;
  final Widget primary;
  final Widget menu;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final ready = interval.status == 'ready';
    final strict = selectedPreset?.strictMode ?? false;
    final blocksEarlyCompletion = strict && remaining > Duration.zero;

    return Column(
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 10,
          children: [
            primary,
            if (!minimal && !compact)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(200, 48),
                ),
                onPressed: ready || blocksEarlyCompletion
                    ? null
                    : () => unawaited(
                        _performFocusAction(
                          context,
                          repository.completeActiveInterval,
                          message: l10n.intervalCompleted,
                          icon: Icons.check_circle_outline,
                        ),
                      ),
                icon: const Icon(Icons.check),
                label: Text(l10n.completeInterval),
              ),
            menu,
          ],
        ),
      ],
    );
  }
}

Widget _buildFocusPrimaryAction(
  BuildContext context, {
  required FocusIntervalItem interval,
  required FocusPresetItem? selectedPreset,
  required FocusRepository repository,
}) {
  final l10n = context.l10n;
  final ready = interval.status == 'ready';
  final paused = interval.status == 'paused';
  final allowPause = selectedPreset?.allowPause ?? true;
  final onPressed = ready
      ? () => unawaited(
          _performFocusAction(
            context,
            repository.startReadyInterval,
            message: l10n.intervalStarted,
            icon: Icons.play_circle_outline,
          ),
        )
      : paused || allowPause
      ? () => unawaited(
          _performFocusAction(
            context,
            paused
                ? repository.resumeActiveInterval
                : repository.pauseActiveInterval,
            message: paused ? l10n.resume : l10n.pause,
            icon: paused
                ? Icons.play_circle_outline
                : Icons.pause_circle_outline,
          ),
        )
      : null;
  final button = _ElasticFocusButton(
    enabled: onPressed != null,
    child: FilledButton(
      key: const Key('focus-primary-action'),
      style: FilledButton.styleFrom(minimumSize: const Size(176, 48)),
      onPressed: onPressed,
      child: AnimatedSwitcher(
        duration: _motionDuration(context, 180),
        child: Wrap(
          key: ValueKey('focus-primary-label-${interval.status}'),
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            Icon(ready || paused ? Icons.play_arrow : Icons.pause),
            Text(
              ready
                  ? l10n.startInterval
                  : paused
                  ? l10n.resume
                  : l10n.pause,
            ),
          ],
        ),
      ),
    ),
  );
  return _withPauseAvailabilitySemantics(
    context,
    unavailable: !ready && !paused && !allowPause,
    child: button,
  );
}

Widget _buildFocusMoreActionsMenu(
  BuildContext context, {
  required FocusIntervalItem interval,
  required Duration remaining,
  required List<FocusPresetItem> presets,
  required FocusPresetItem? selectedPreset,
  required bool compact,
  required bool minimal,
  required FocusViewMode viewMode,
  required bool showViewModeMenu,
  required FocusRepository repository,
  required ValueChanged<FocusViewMode> onViewModeChanged,
  required ValueChanged<String> onPresetChanged,
  required ValueChanged<FocusPresetItem> onCustomizePreset,
  required VoidCallback onCreatePreset,
}) {
  final l10n = context.l10n;
  final ready = interval.status == 'ready';
  final strict = selectedPreset?.strictMode ?? false;
  final blocksEarlyCompletion = strict && remaining > Duration.zero;

  return SizedBox.square(
    dimension: 48,
    child: Semantics(
      key: const Key('focus-details-menu'),
      label: l10n.moreFocusActions,
      container: true,
      button: true,
      child: PopupMenuButton<_FocusMoreAction>(
        tooltip: l10n.moreFocusActions,
        icon: const Icon(Icons.more_horiz),
        constraints: const BoxConstraints(minWidth: 220),
        onSelected: (action) {
          switch (action.kind) {
            case _FocusMoreActionKind.complete:
              unawaited(
                _performFocusAction(
                  context,
                  repository.completeActiveInterval,
                  message: l10n.intervalCompleted,
                  icon: Icons.check_circle_outline,
                ),
              );
            case _FocusMoreActionKind.skip:
              unawaited(
                _performFocusAction(context, repository.skipActiveInterval),
              );
            case _FocusMoreActionKind.stop:
              unawaited(
                _performFocusAction(
                  context,
                  () =>
                      repository.stopActiveRun(reason: StopFocusReason.stopped),
                  message: l10n.focusStopped,
                  icon: Icons.stop_circle_outlined,
                  haptic: AppHapticCue.light,
                ),
              );
            case _FocusMoreActionKind.customize:
              final preset = selectedPreset;
              if (preset != null) onCustomizePreset(preset);
            case _FocusMoreActionKind.createPreset:
              onCreatePreset();
            case _FocusMoreActionKind.changePreset:
              final presetId = action.presetId;
              if (presetId != null) onPresetChanged(presetId);
            case _FocusMoreActionKind.toggleViewMode:
              onViewModeChanged(
                viewMode == FocusViewMode.full
                    ? FocusViewMode.minimal
                    : FocusViewMode.full,
              );
          }
        },
        itemBuilder: (context) => [
          if (!minimal && compact)
            PopupMenuItem(
              value: const _FocusMoreAction(_FocusMoreActionKind.complete),
              enabled: !ready && !blocksEarlyCompletion,
              child: Text(l10n.completeInterval),
            ),
          if (!minimal)
            PopupMenuItem(
              value: const _FocusMoreAction(_FocusMoreActionKind.skip),
              enabled: !strict,
              child: Text(l10n.skip),
            ),
          if (!minimal)
            PopupMenuItem(
              value: const _FocusMoreAction(_FocusMoreActionKind.stop),
              child: Text(l10n.commonStop),
            ),
          if (!minimal && selectedPreset != null) const PopupMenuDivider(),
          if (!minimal && selectedPreset != null)
            PopupMenuItem(
              value: const _FocusMoreAction(_FocusMoreActionKind.customize),
              child: Text(l10n.customizePreset),
            ),
          if (!minimal)
            PopupMenuItem(
              value: const _FocusMoreAction(_FocusMoreActionKind.createPreset),
              child: Text(l10n.newPreset),
            ),
          for (final preset in minimal ? const <FocusPresetItem>[] : presets)
            PopupMenuItem(
              value: _FocusMoreAction(
                _FocusMoreActionKind.changePreset,
                preset.id,
              ),
              enabled: preset.id != selectedPreset?.id,
              child: Text(l10n.usePreset(preset.name)),
            ),
          if (showViewModeMenu && !minimal) const PopupMenuDivider(),
          if (showViewModeMenu)
            PopupMenuItem(
              key: const Key('focus-switch-view-mode'),
              value: const _FocusMoreAction(
                _FocusMoreActionKind.toggleViewMode,
              ),
              child: Text(
                viewMode == FocusViewMode.full
                    ? l10n.focusSwitchToMinimalView
                    : l10n.focusSwitchToFullView,
              ),
            ),
        ],
      ),
    ),
  );
}

Future<void> _performFocusAction(
  BuildContext context,
  Future<void> Function() action, {
  String? message,
  IconData icon = Icons.check_circle_outline,
  AppHapticCue haptic = AppHapticCue.none,
}) async {
  try {
    await action();
  } catch (_) {
    if (context.mounted) {
      showActionFeedback(
        context,
        message: context.l10n.focusActionFailed,
        icon: Icons.error_outline,
        sound: ActionFeedbackSound.none,
        haptic: AppHapticCue.none,
      );
    }
    return;
  }
  if (context.mounted && message != null) {
    showActionFeedback(context, message: message, icon: icon, haptic: haptic);
  }
}

enum _FocusMoreActionKind {
  complete,
  skip,
  stop,
  customize,
  createPreset,
  changePreset,
  toggleViewMode,
}

class _FocusMoreAction {
  const _FocusMoreAction(this.kind, [this.presetId]);

  final _FocusMoreActionKind kind;
  final String? presetId;
}

Widget _withPauseAvailabilitySemantics(
  BuildContext context, {
  required bool unavailable,
  required Widget child,
}) {
  if (!unavailable) {
    return child;
  }
  return Semantics(
    label: context.l10n.focusPauseUnavailable,
    button: true,
    enabled: false,
    excludeSemantics: true,
    child: child,
  );
}
