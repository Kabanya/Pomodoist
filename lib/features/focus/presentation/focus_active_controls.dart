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
    required this.run,
    required this.interval,
    required this.remaining,
    required this.presets,
    required this.selectedPreset,
    required this.compact,
    required this.minimal,
    required this.viewMode,
    required this.repository,
    required this.onViewModeChanged,
    required this.onPresetChanged,
    required this.onCustomizePreset,
  });

  final FocusRunItem run;
  final FocusIntervalItem interval;
  final Duration remaining;
  final List<FocusPresetItem> presets;
  final FocusPresetItem? selectedPreset;
  final bool compact;
  final bool minimal;
  final FocusViewMode viewMode;
  final FocusRepository repository;
  final ValueChanged<FocusViewMode> onViewModeChanged;
  final ValueChanged<String> onPresetChanged;
  final ValueChanged<FocusPresetItem> onCustomizePreset;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final ready = interval.status == 'ready';
    final paused = interval.status == 'paused';
    final strict = selectedPreset?.strictMode ?? false;
    final allowPause = selectedPreset?.allowPause ?? true;
    final blocksEarlyCompletion = strict && remaining > Duration.zero;
    final primaryOnPressed = ready
        ? () => unawaited(_startReady(context))
        : paused || allowPause
        ? () => unawaited(_togglePause(context, paused))
        : null;
    final primaryButton = _ElasticFocusButton(
      enabled: primaryOnPressed != null,
      child: FilledButton(
        key: const Key('focus-primary-action'),
        style: FilledButton.styleFrom(minimumSize: const Size(176, 48)),
        onPressed: primaryOnPressed,
        child: AnimatedSwitcher(
          duration: _motionDuration(context, 180),
          child: Row(
            key: ValueKey('focus-primary-label-${interval.status}'),
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(ready || paused ? Icons.play_arrow : Icons.pause),
              const SizedBox(width: 8),
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
    final primary = _withPauseAvailabilitySemantics(
      context,
      unavailable: !ready && !paused && !allowPause,
      child: primaryButton,
    );
    final menu = PopupMenuButton<_FocusMoreAction>(
      key: const Key('focus-details-menu'),
      tooltip: l10n.moreFocusActions,
      icon: const Icon(Icons.more_horiz),
      constraints: const BoxConstraints(minWidth: 220),
      onSelected: (action) => _handleMore(context, action),
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
        if (!minimal && compact)
          PopupMenuItem(
            value: const _FocusMoreAction(_FocusMoreActionKind.logDistraction),
            child: Text(l10n.logDistraction),
          ),
        if (!minimal && selectedPreset != null) const PopupMenuDivider(),
        if (!minimal && selectedPreset != null)
          PopupMenuItem(
            value: const _FocusMoreAction(_FocusMoreActionKind.customize),
            child: Text(l10n.customizePreset),
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
        if (!minimal) const PopupMenuDivider(),
        PopupMenuItem(
          key: const Key('focus-switch-view-mode'),
          value: const _FocusMoreAction(_FocusMoreActionKind.toggleViewMode),
          child: Text(
            viewMode == FocusViewMode.full
                ? l10n.focusSwitchToMinimalView
                : l10n.focusSwitchToFullView,
          ),
        ),
      ],
    );

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
                    : () => unawaited(_complete(context)),
                icon: const Icon(Icons.check),
                label: Text(l10n.completeInterval),
              ),
            SizedBox.square(dimension: 48, child: menu),
          ],
        ),
        if (!minimal && !compact) ...[
          const SizedBox(height: 14),
          TextButton.icon(
            onPressed: () => unawaited(
              _perform(context, () => repository.logDistraction(runId: run.id)),
            ),
            icon: const Icon(Icons.info_outline),
            label: Text(l10n.logDistraction),
          ),
        ],
      ],
    );
  }

  void _handleMore(BuildContext context, _FocusMoreAction action) {
    switch (action.kind) {
      case _FocusMoreActionKind.complete:
        unawaited(_complete(context));
      case _FocusMoreActionKind.skip:
        unawaited(_perform(context, () => repository.skipActiveInterval()));
      case _FocusMoreActionKind.stop:
        unawaited(_stop(context));
      case _FocusMoreActionKind.logDistraction:
        unawaited(
          _perform(context, () => repository.logDistraction(runId: run.id)),
        );
      case _FocusMoreActionKind.customize:
        final preset = selectedPreset;
        if (preset != null) {
          onCustomizePreset(preset);
        }
      case _FocusMoreActionKind.changePreset:
        final presetId = action.presetId;
        if (presetId != null) {
          onPresetChanged(presetId);
        }
      case _FocusMoreActionKind.toggleViewMode:
        onViewModeChanged(
          viewMode == FocusViewMode.full
              ? FocusViewMode.minimal
              : FocusViewMode.full,
        );
    }
  }

  Future<void> _startReady(BuildContext context) async {
    await _perform(
      context,
      () => repository.startReadyInterval(),
      message: context.l10n.intervalStarted,
      icon: Icons.play_circle_outline,
      haptic: AppHapticCue.none,
    );
  }

  Future<void> _togglePause(BuildContext context, bool paused) async {
    await _perform(
      context,
      () => paused
          ? repository.resumeActiveInterval()
          : repository.pauseActiveInterval(),
      message: paused ? context.l10n.resume : context.l10n.pause,
      icon: paused ? Icons.play_circle_outline : Icons.pause_circle_outline,
      haptic: AppHapticCue.none,
    );
  }

  Future<void> _complete(BuildContext context) async {
    await _perform(
      context,
      () => repository.completeActiveInterval(),
      message: context.l10n.intervalCompleted,
      icon: Icons.check_circle_outline,
      haptic: AppHapticCue.none,
    );
  }

  Future<void> _stop(BuildContext context) async {
    await _perform(
      context,
      () => repository.stopActiveRun(reason: StopFocusReason.stopped),
      message: context.l10n.focusStopped,
      icon: Icons.stop_circle_outlined,
      haptic: AppHapticCue.light,
    );
  }

  Future<void> _perform(
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
}

enum _FocusMoreActionKind {
  complete,
  skip,
  stop,
  logDistraction,
  customize,
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
