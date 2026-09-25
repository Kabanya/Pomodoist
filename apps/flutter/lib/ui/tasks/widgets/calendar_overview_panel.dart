import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons, ShadCalendar;

import 'package:pomodoist/domain/models/focus/focus_models.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/routing/task_detail_navigation.dart';
import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/localization/formatters.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/core/widgets/action_feedback.dart';
import 'package:pomodoist/ui/core/widgets/app_date_time_picker.dart';
import 'package:pomodoist/ui/focus/view_models/focus_view_model.dart';
import 'package:pomodoist/ui/focus/widgets/focus_preset_localizations.dart';
import 'package:pomodoist/ui/tasks/widgets/project_localizations.dart';

/// The compact calendar and the current Focus session share the live Focus VM.
class CalendarOverviewPanel extends ConsumerStatefulWidget {
  const CalendarOverviewPanel({
    required this.selectedDate,
    required this.onDateSelected,
    required this.onOpenMonth,
    required this.onClose,
    this.onOpenTask,
    super.key,
  });

  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateSelected;
  final VoidCallback onOpenMonth;
  final VoidCallback onClose;
  final ValueChanged<String>? onOpenTask;

  @override
  ConsumerState<CalendarOverviewPanel> createState() =>
      _CalendarOverviewPanelState();
}

class _CalendarOverviewPanelState extends ConsumerState<CalendarOverviewPanel> {
  bool _actionPending = false;

  Future<void> _runFocusAction(
    Future<void> Function() action, {
    required String successMessage,
    required IconData successIcon,
  }) async {
    if (_actionPending) return;
    setState(() => _actionPending = true);
    try {
      await action();
      if (!mounted) return;
      showActionFeedback(
        context,
        message: successMessage,
        icon: successIcon,
        haptic: AppHapticCue.none,
      );
    } catch (_) {
      if (!mounted) return;
      showActionFeedback(
        context,
        message: context.l10n.focusActionFailed,
        icon: LucideIcons.circleAlert,
        sound: ActionFeedbackSound.none,
        haptic: AppHapticCue.none,
      );
    } finally {
      if (mounted) setState(() => _actionPending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final focus = ref.watch(focusViewModelProvider);
    final selected = DateUtils.dateOnly(widget.selectedDate);
    final material = MaterialLocalizations.of(context);

    return Material(
      color: colors.surface,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.calendarOverview,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: l10n.commonClose,
                onPressed: widget.onClose,
                icon: const Icon(LucideIcons.x, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Center(
            child: ShadCalendar(
              key: ValueKey((selected.year, selected.month)),
              selected: selected,
              initialMonth: DateTime(selected.year, selected.month),
              fromMonth: DateTime(math.min(1900, selected.year)),
              toMonth: DateTime(math.max(2200, selected.year), 12, 31),
              weekStartsOn: pickerWeekStartsOn(material),
              allowDeselection: false,
              dayButtonSize: 32,
              navigationButtonSize: 32,
              gridMainAxisSpacing: 4,
              headerPadding: const EdgeInsets.only(bottom: 8),
              onChanged: (date) {
                if (date != null) {
                  widget.onDateSelected(DateUtils.dateOnly(date));
                }
              },
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: widget.onOpenMonth,
            icon: const Icon(LucideIcons.arrowRight, size: 16),
            label: Text(l10n.calendarOpenMonth),
          ),
          const SizedBox(height: 16),
          Divider(color: colors.border, height: 1),
          const SizedBox(height: 20),
          Text(l10n.focusTitle, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          if (focus.loadError != null)
            Text(
              l10n.focusLoadError(focus.loadError!),
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.error),
            )
          else if (focus.loading)
            const Center(child: CircularProgressIndicator())
          else if (focus.run == null && focus.interval == null)
            _idleFocus(context, focus)
          else if (focus.run == null ||
              focus.interval == null ||
              focus.interval!.runId != focus.run!.id ||
              focus.remaining == null)
            Text(l10n.preparingFocus)
          else
            _activeFocus(context, focus),
        ],
      ),
    );
  }

  Widget _idleFocus(BuildContext context, FocusState focus) {
    final l10n = context.l10n;
    final preset = focus.effectivePreset;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.calendarNoActiveFocus,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: context.appColors.secondaryText,
          ),
        ),
        if (preset != null) ...[
          const SizedBox(height: 8),
          Text(preset.displayName(l10n)),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _actionPending
                ? null
                : () => unawaited(
                    _runFocusAction(
                      () => ref
                          .read(focusViewModelProvider.notifier)
                          .startFocus(preset),
                      successMessage: l10n.focusStarted,
                      successIcon: LucideIcons.circlePlay,
                    ),
                  ),
            icon: const Icon(LucideIcons.play, size: 18),
            label: Text(l10n.startFocus),
          ),
        ],
      ],
    );
  }

  Widget _activeFocus(BuildContext context, FocusState focus) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final run = focus.run!;
    final interval = focus.interval!;
    final remaining = focus.remaining!;
    final ready = interval.status == 'ready';
    final paused = interval.status == 'paused';
    final canPause = focus.activePreset?.allowPause ?? true;
    final statusLabel = ready
        ? l10n.readyShort
        : paused
        ? l10n.focusStatusPaused
        : l10n.focusStatusRunning;
    final action = ready
        ? ref.read(focusViewModelProvider.notifier).startReadyInterval
        : paused
        ? ref.read(focusViewModelProvider.notifier).resumeActiveInterval
        : ref.read(focusViewModelProvider.notifier).pauseActiveInterval;
    final actionLabel = ready
        ? l10n.startInterval
        : paused
        ? l10n.resume
        : l10n.pause;
    final actionIcon = ready || paused ? LucideIcons.play : LucideIcons.pause;
    final currentSession = math.min(
      run.targetWorkIntervals,
      math.max(
        1,
        run.completedWorkIntervals + (interval.type == 'work' ? 1 : 0),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.focusSessionProgress(currentSession, run.targetWorkIntervals),
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.secondaryText),
        ),
        const SizedBox(height: 4),
        Text(
          '${focusIntervalTypeLabel(l10n, interval.type)} · $statusLabel',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.secondaryText),
        ),
        const SizedBox(height: 12),
        Semantics(
          label: l10n.focusTimerSummary(
            focusIntervalTypeLabel(l10n, interval.type),
            statusLabel,
            formatDurationCompact(remaining),
            formatDurationCompact(Duration(seconds: interval.plannedSeconds)),
          ),
          child: ExcludeSemantics(
            child: Text(
              formatDurationCompact(remaining),
              style: AppTheme.monoTextStyle.copyWith(
                fontSize: 44,
                fontWeight: FontWeight.w700,
                color: colors.primaryText,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: _actionPending || (!ready && !paused && !canPause)
                  ? null
                  : () => unawaited(
                      _runFocusAction(
                        action,
                        successMessage: ready
                            ? l10n.intervalStarted
                            : actionLabel,
                        successIcon: ready || paused
                            ? LucideIcons.circlePlay
                            : LucideIcons.circlePause,
                      ),
                    ),
              icon: Icon(actionIcon, size: 18),
              label: Text(actionLabel),
            ),
            OutlinedButton.icon(
              onPressed: _actionPending
                  ? null
                  : () => unawaited(
                      _runFocusAction(
                        () => ref
                            .read(focusViewModelProvider.notifier)
                            .stopActiveRun(reason: StopFocusReason.stopped),
                        successMessage: l10n.focusStopped,
                        successIcon: LucideIcons.circleStop,
                      ),
                    ),
              icon: const Icon(LucideIcons.square, size: 16),
              label: Text(l10n.commonStop),
            ),
          ],
        ),
        if (run.taskId != null) ...[
          const SizedBox(height: 20),
          Divider(color: colors.border, height: 1),
          const SizedBox(height: 16),
          Text(
            l10n.calendarCurrentTask,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: colors.secondaryText),
          ),
          const SizedBox(height: 8),
          _LinkedTask(
            taskId: run.taskId!,
            projectId: run.projectId,
            onOpen: widget.onOpenTask,
          ),
        ],
      ],
    );
  }
}

class _LinkedTask extends ConsumerWidget {
  const _LinkedTask({
    required this.taskId,
    required this.projectId,
    this.onOpen,
  });

  final String taskId;
  final String? projectId;
  final ValueChanged<String>? onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(
      focusLinkedTaskViewModelProvider((taskId, projectId)),
    );
    final task = state.task;
    if (task == null || task.isDeleted) return Text(context.l10n.taskNotFound);
    final project = state.project;
    final colors = context.appColors;
    final estimate = task.estimatedFocusIntervals;
    final completed = task.completedFocusIntervals;
    final progress = estimate == null || estimate <= 0
        ? null
        : (completed / estimate).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton(
          style: TextButton.styleFrom(
            alignment: Alignment.centerLeft,
            padding: EdgeInsets.zero,
            foregroundColor: colors.primaryText,
          ),
          onPressed: () => onOpen == null
              ? openTaskDetails(context, task.id)
              : onOpen!(task.id),
          child: Text(
            task.content,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        if (task.description?.trim().isNotEmpty ?? false) ...[
          const SizedBox(height: 4),
          Text(
            task.description!.trim(),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.secondaryText),
          ),
        ],
        const SizedBox(height: 12),
        if (project != null)
          _fact(context, LucideIcons.folder, project.displayName(context.l10n)),
        if (task.schedule case final TaskSchedule schedule)
          _fact(
            context,
            LucideIcons.calendarDays,
            formatTaskSchedule(context, schedule),
          ),
        _fact(context, LucideIcons.flag, context.l10n.priority(task.priority)),
        if (progress != null) ...[
          const SizedBox(height: 8),
          LinearProgressIndicator(value: progress),
          const SizedBox(height: 4),
          Text(
            context.l10n.focusProgress(completed, estimate!),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.secondaryText),
          ),
        ],
      ],
    );
  }

  Widget _fact(BuildContext context, IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: context.appColors.secondaryText),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    ),
  );
}
