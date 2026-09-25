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
    final state = ref.watch(
      focusLinkedTaskViewModelProvider((taskId, projectId)),
    );
    final task = state.task;
    if (task == null || task.isDeleted) {
      return SizedBox(height: compact ? 28 : 36);
    }
    final project = state.project;

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
              onPressed: () => openTaskDetails(context, task.id),
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
                    text: ' ${project.displayName(context.l10n)}',
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
    required this.minimal,
    required this.actions,
    required this.primary,
    required this.summary,
  });
  final FocusIntervalItem interval;
  final Duration remaining;
  final FocusPresetItem? selectedPreset;
  final bool minimal;
  final FocusStageActions actions;
  final Widget primary;
  final String summary;

  @override
  Widget build(BuildContext context) {
    if (minimal) return Center(child: primary);
    final blocked =
        interval.status == 'ready' ||
        ((selectedPreset?.strictMode ?? false) && remaining > Duration.zero);
    return _FocusControlDock(
      summary: summary,
      primary: primary,
      secondary: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(minimumSize: const Size(200, 48)),
        onPressed: blocked
            ? null
            : () => unawaited(
                _performFocusAction(
                  context,
                  actions.completeActiveInterval,
                  message: context.l10n.intervalCompleted,
                  icon: LucideIcons.circleCheck,
                ),
              ),
        icon: const Icon(LucideIcons.check, size: 18),
        label: Text(context.l10n.completeInterval),
      ),
    );
  }
}

class _FocusPrimaryButton extends StatelessWidget {
  const _FocusPrimaryButton({
    required this.minimal,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final bool minimal;
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final button = FilledButton(
      key: const Key('focus-primary-action'),
      style: minimal
          ? FilledButton.styleFrom(
              fixedSize: const Size.square(56),
              minimumSize: const Size.square(56),
              padding: EdgeInsets.zero,
              shape: const CircleBorder(),
            )
          : FilledButton.styleFrom(minimumSize: const Size(176, 48)),
      onPressed: onPressed,
      child: AnimatedSwitcher(
        duration: AppMotion.duration(context, AppMotion.state),
        switchInCurve: AppMotion.curve,
        switchOutCurve: AppMotion.curve,
        child: minimal
            ? Icon(icon, key: ValueKey(label), size: 20, semanticLabel: label)
            : Wrap(
                key: ValueKey(label),
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: [Icon(icon, size: 18), Text(label)],
              ),
      ),
    );
    return minimal
        ? Tooltip(message: label, excludeFromSemantics: true, child: button)
        : button;
  }
}

Widget _buildFocusPrimaryAction(
  BuildContext context, {
  required FocusIntervalItem interval,
  required FocusPresetItem? selectedPreset,
  required FocusStageActions actions,
  required bool minimal,
}) {
  final l10n = context.l10n;
  final ready = interval.status == 'ready';
  final paused = interval.status == 'paused';
  final allowPause = selectedPreset?.allowPause ?? true;
  final onPressed = ready
      ? () => unawaited(
          _performFocusAction(
            context,
            actions.startReadyInterval,
            message: l10n.intervalStarted,
            icon: LucideIcons.circlePlay,
          ),
        )
      : paused || allowPause
      ? () => unawaited(
          _performFocusAction(
            context,
            paused ? actions.resumeActiveInterval : actions.pauseActiveInterval,
            message: paused ? l10n.resume : l10n.pause,
            icon: paused ? LucideIcons.circlePlay : LucideIcons.circlePause,
          ),
        )
      : null;
  final button = _FocusPrimaryButton(
    minimal: minimal,
    onPressed: onPressed,
    icon: ready || paused ? LucideIcons.play : LucideIcons.pause,
    label: ready
        ? l10n.startInterval
        : paused
        ? l10n.resume
        : l10n.pause,
  );
  return _withPauseAvailabilitySemantics(
    context,
    unavailable: !ready && !paused && !allowPause,
    child: button,
  );
}

Widget _buildFocusMoreActionsMenu(
  BuildContext context, {
  required List<FocusPresetItem> presets,
  required FocusPresetItem? selectedPreset,
  required bool minimal,
  required FocusViewMode viewMode,
  required bool showViewModeMenu,
  required FocusSessionDisplay sessionDisplay,
  required ValueChanged<FocusSessionDisplay>? onSessionDisplayChanged,
  required FocusStageActions actions,
  required ValueChanged<FocusViewMode> onViewModeChanged,
  required ValueChanged<String> onPresetChanged,
  required ValueChanged<FocusPresetItem> onCustomizePreset,
  required VoidCallback onCreatePreset,
}) {
  final l10n = context.l10n;
  final strict = selectedPreset?.strictMode ?? false;

  void selectAction(_FocusMoreAction action) {
    switch (action.kind) {
      case _FocusMoreActionKind.skip:
        unawaited(_performFocusAction(context, actions.skipActiveInterval));
      case _FocusMoreActionKind.stop:
        unawaited(
          _performFocusAction(
            context,
            () => actions.stopActiveRun(reason: StopFocusReason.stopped),
            message: l10n.focusStopped,
            icon: LucideIcons.circleStop,
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
  }

  return SizedBox.square(
    dimension: 48,
    child: Semantics(
      key: const Key('focus-details-menu'),
      label: l10n.moreFocusActions,
      container: true,
      button: true,
      child: AppActionMenu(
        tooltip: l10n.moreFocusActions,
        constraints: const BoxConstraints(minWidth: 220),
        items: [
          ..._sessionDisplayMenuItems(
            context,
            sessionDisplay,
            onSessionDisplayChanged,
          ),
          if (!minimal)
            ShadContextMenuItem(
              height: 44,
              onPressed: () => selectAction(
                const _FocusMoreAction(_FocusMoreActionKind.skip),
              ),
              enabled: !strict,
              child: Text(l10n.skip),
            ),
          if (!minimal)
            ShadContextMenuItem(
              height: 44,
              onPressed: () => selectAction(
                const _FocusMoreAction(_FocusMoreActionKind.stop),
              ),
              child: Text(l10n.commonStop),
            ),
          if (!minimal && selectedPreset != null)
            Divider(height: 8, color: context.appColors.border),
          if (!minimal && selectedPreset != null)
            ShadContextMenuItem(
              height: 44,
              onPressed: () => selectAction(
                const _FocusMoreAction(_FocusMoreActionKind.customize),
              ),
              child: Text(l10n.customizePreset),
            ),
          if (!minimal)
            ShadContextMenuItem(
              height: 44,
              onPressed: () => selectAction(
                const _FocusMoreAction(_FocusMoreActionKind.createPreset),
              ),
              child: Text(l10n.newPreset),
            ),
          for (final preset in minimal ? const <FocusPresetItem>[] : presets)
            ShadContextMenuItem(
              height: 44,
              onPressed: () => selectAction(
                _FocusMoreAction(_FocusMoreActionKind.changePreset, preset.id),
              ),
              enabled: preset.id != selectedPreset?.id,
              child: Text(l10n.usePreset(preset.displayName(l10n))),
            ),
          if (showViewModeMenu && !minimal)
            Divider(height: 8, color: context.appColors.border),
          if (showViewModeMenu)
            ShadContextMenuItem(
              height: 44,
              key: const Key('focus-switch-view-mode'),
              onPressed: () => selectAction(
                const _FocusMoreAction(_FocusMoreActionKind.toggleViewMode),
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
  IconData icon = LucideIcons.circleCheck,
  AppHapticCue haptic = AppHapticCue.none,
}) async {
  try {
    await action();
  } catch (_) {
    if (context.mounted) {
      showActionFeedback(
        context,
        message: context.l10n.focusActionFailed,
        icon: LucideIcons.circleAlert,
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
