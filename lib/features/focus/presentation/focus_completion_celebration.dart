import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons, ShadButton;

import '../../../app/app_l10n.dart';
import '../../../app/formatters.dart';
import '../../../app/providers.dart';
import '../../../app/task_time.dart';
import '../../../app/theme/app_motion.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/action_feedback.dart';
import '../../tasks/domain/task_focus_estimate.dart';
import '../../tasks/domain/task_models.dart';
import '../../tasks/presentation/task_completion_feedback.dart';
import '../domain/focus_models.dart';
import 'focus_completion_celebration_controller.dart';
import 'focus_view_mode.dart';

class FocusRunCompletionCelebrationSlot extends ConsumerWidget {
  const FocusRunCompletionCelebrationSlot({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final completion = ref.watch(focusRunCompletionControllerProvider);
    if (completion == null) {
      return const SizedBox.shrink();
    }
    return Positioned.fill(
      child: _FocusRunCompletionCelebration(
        key: ValueKey('focus-completion-${completion.runId}'),
        completion: completion,
      ),
    );
  }
}

class _FocusRunCompletionCelebration extends ConsumerStatefulWidget {
  const _FocusRunCompletionCelebration({required this.completion, super.key});

  final FocusRunCompletionEvent completion;

  @override
  ConsumerState<_FocusRunCompletionCelebration> createState() =>
      _FocusRunCompletionCelebrationState();
}

class _FocusRunCompletionCelebrationState
    extends ConsumerState<_FocusRunCompletionCelebration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _contentOpacity;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: AppMotion.state);
    _contentOpacity = CurvedAnimation(
      parent: _controller,
      curve: AppMotion.curve,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (!_started) {
      _started = true;
      if (reduceMotion) {
        _controller.value = 1;
      } else {
        _controller.forward();
      }
    } else if (reduceMotion && _controller.value != 1) {
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final completion = widget.completion;
    final colors = context.appColors;
    final l10n = context.l10n;
    final taskId = completion.taskId;
    final taskValue = taskId == null ? null : ref.watch(taskProvider(taskId));
    final task = taskValue?.value;
    final resolvingTask = taskValue?.isLoading ?? false;
    final canCompleteTask =
        task != null && !task.isDeleted && !task.isCompleted;
    final nextTask = _nextScheduledTask(
      ref.watch(tasksByQueryProvider(const TaskQuery.all())).value ?? const [],
      completion,
      task,
    );
    final nextTaskPreset = selectedFocusPresetOrDefault(
      ref.watch(focusPresetsProvider).value ?? const [],
      ref.watch(lastFocusPresetIdProvider),
    );
    final taskTitle = completion.taskTitle?.trim();
    final subtitle = taskId == null
        ? l10n.focusCompletionStandaloneSubtitle
        : l10n.focusCompletionLinkedSubtitle;

    return PopScope(
      canPop: false,
      child: Material(
        key: const Key('focus-completion-overlay'),
        color: colors.canvas,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Semantics(
                key: const Key('focus-completion-announcement'),
                container: true,
                explicitChildNodes: true,
                liveRegion: true,
                label:
                    '${l10n.focusCompletionTitle} '
                    '$subtitle${taskTitle == null ? '' : ' $taskTitle'}',
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _CelebrationArtwork(
                        animation: _contentOpacity,
                        colors: colors,
                      ),
                      FadeTransition(
                        key: const Key('focus-completion-content-entrance'),
                        opacity: _contentOpacity,
                        child: _CompletionContent(
                          completion: completion,
                          taskTitle: taskTitle,
                          subtitle: subtitle,
                          resolvingTask: resolvingTask,
                          canCompleteTask: canCompleteTask,
                          onCompleteTask: taskId == null
                              ? null
                              : () => _completeTask(taskId),
                          nextTask: nextTask,
                          onStartNextTask: nextTask == null
                              ? null
                              : () => _startNextTask(
                                  nextTask,
                                  nextTaskPreset,
                                  canCompleteTask ? taskId : null,
                                ),
                          onDismiss: _dismiss,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _completeTask(String taskId) async {
    try {
      final completed = await completeTaskWithUndoFeedback(
        context,
        ref,
        taskId,
      );
      if (completed && mounted) {
        _dismiss();
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      showActionFeedback(
        context,
        message: context.l10n.taskActionFailedCount(1),
        icon: LucideIcons.circleAlert,
        sound: ActionFeedbackSound.none,
      );
    }
  }

  Future<void> _startNextTask(
    TaskItem task,
    FocusPresetItem? preset,
    String? currentTaskId,
  ) async {
    final taskRepository = ref.read(taskRepositoryProvider);
    var completedCurrentTask = false;
    try {
      if (currentTaskId != null) {
        await taskRepository.completeTask(currentTaskId);
        completedCurrentTask = true;
      }
      final estimate = targetFocusIntervalsForTask(task, preset);
      await ref
          .read(focusRepositoryProvider)
          .startRun(
            StartFocusRunInput(
              taskId: task.id,
              projectId: task.projectId,
              presetId: preset?.id,
              targetWorkIntervals: estimate == null
                  ? null
                  : estimate < 1
                  ? 1
                  : estimate,
            ),
          );
      if (mounted) {
        _dismiss();
      }
    } catch (error) {
      if (completedCurrentTask) {
        try {
          await taskRepository.uncompleteTask(currentTaskId!);
        } catch (_) {}
      }
      if (!mounted) {
        return;
      }
      showActionFeedback(
        context,
        message: context.l10n.kanbanCouldNotStartFocus(error),
        icon: LucideIcons.circleAlert,
        sound: ActionFeedbackSound.none,
      );
    }
  }

  void _dismiss() {
    ref.read(focusRunCompletionControllerProvider.notifier).dismiss();
  }
}

class _CelebrationArtwork extends StatelessWidget {
  const _CelebrationArtwork({required this.animation, required this.colors});

  final Animation<double> animation;
  final AppThemePalette colors;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: FadeTransition(
        opacity: animation,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Container(
            key: const Key('focus-completion-mark'),
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border.all(color: colors.border),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              LucideIcons.circleCheck,
              size: 36,
              color: colors.accent,
            ),
          ),
        ),
      ),
    );
  }
}

class _CompletionContent extends ConsumerWidget {
  const _CompletionContent({
    required this.completion,
    required this.taskTitle,
    required this.subtitle,
    required this.resolvingTask,
    required this.canCompleteTask,
    required this.onCompleteTask,
    required this.nextTask,
    required this.onStartNextTask,
    required this.onDismiss,
  });

  final FocusRunCompletionEvent completion;
  final String? taskTitle;
  final String subtitle;
  final bool resolvingTask;
  final bool canCompleteTask;
  final Future<void> Function()? onCompleteTask;
  final TaskItem? nextTask;
  final Future<void> Function()? onStartNextTask;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final textTheme = Theme.of(context).textTheme;
    final taskTimeState = nextTask == null
        ? null
        : ref.watch(taskTimeStateProvider(nextTask!));
    final taskTimeColor = taskTimeState == null
        ? colors.secondaryText
        : colors.taskTimeColor(taskTimeState);
    final timeDisplayMode = ref.watch(taskTimeDisplayModeProvider);
    final defaultTimedBlockMinutes = ref.watch(
      quickAddDefaultTimedBlockMinutesProvider,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.focusCompletionTitle,
          textAlign: TextAlign.center,
          style: textTheme.headlineMedium?.copyWith(
            color: colors.primaryText,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: textTheme.bodyLarge?.copyWith(color: colors.secondaryText),
        ),
        if (taskTitle != null && taskTitle!.isNotEmpty) ...[
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border.all(color: colors.border),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              taskTitle!,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: textTheme.titleLarge?.copyWith(
                color: colors.primaryText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: colors.border),
          ),
          child: Text(
            l10n.focusProgress(
              completion.completedWorkIntervals,
              completion.targetWorkIntervals,
            ),
            style: AppTheme.monoTextStyle.copyWith(
              fontSize: textTheme.labelLarge?.fontSize,
              color: colors.accent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 26),
        if (resolvingTask)
          const SizedBox.square(
            key: Key('focus-completion-task-loading'),
            dimension: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          )
        else if (canCompleteTask) ...[
          Text(
            l10n.focusCompletionQuestion,
            textAlign: TextAlign.center,
            style: textTheme.bodyLarge?.copyWith(color: colors.primaryText),
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 8,
            children: [
              ShadButton(
                key: const Key('focus-completion-complete-task'),
                onPressed: onCompleteTask,
                enabled: onCompleteTask != null,
                leading: const Icon(LucideIcons.circleCheck, size: 18),
                height: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Flexible(child: Text(l10n.focusCompletionCompleteTask)),
              ),
              ShadButton.ghost(
                key: const Key('focus-completion-keep-open'),
                onPressed: onDismiss,
                height: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Flexible(child: Text(l10n.focusCompletionKeepOpen)),
              ),
            ],
          ),
        ] else
          ShadButton(
            key: const Key('focus-completion-done'),
            onPressed: onDismiss,
            leading: const Icon(LucideIcons.check, size: 18),
            height: 0,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Flexible(child: Text(l10n.focusCompletionDone)),
          ),
        if (nextTask case final task?) ...[
          const SizedBox(height: 24),
          Container(
            key: const Key('focus-completion-next-task'),
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border.all(color: colors.border),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.focusCompletionNextTask,
                  textAlign: TextAlign.center,
                  style: textTheme.labelLarge?.copyWith(
                    color: colors.secondaryText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  task.content,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleMedium?.copyWith(
                    color: colors.primaryText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Semantics(
                  key: const Key('focus-completion-next-task-time-meta'),
                  label: taskTimeState == null
                      ? null
                      : taskTimeStatusLabel(context.l10n, taskTimeState),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        LucideIcons.calendar,
                        key: const Key('focus-completion-next-task-time-icon'),
                        size: 16,
                        color: taskTimeColor,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        formatTaskListSchedule(
                          context,
                          task.schedule!,
                          now: completion.completedAt,
                          displayMode: timeDisplayMode,
                          defaultTimedBlockMinutes: defaultTimedBlockMinutes,
                        ),
                        key: const Key('focus-completion-next-task-time'),
                        textAlign: TextAlign.center,
                        style: textTheme.bodyMedium?.copyWith(
                          color: taskTimeColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                ShadButton.secondary(
                  key: const Key('focus-completion-start-next-task'),
                  onPressed: onStartNextTask,
                  enabled: onStartNextTask != null,
                  leading: const Icon(LucideIcons.play, size: 18),
                  height: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Flexible(child: Text(l10n.startFocus)),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

TaskItem? _nextScheduledTask(
  Iterable<TaskItem> tasks,
  FocusRunCompletionEvent completion,
  TaskItem? currentTask,
) {
  final currentSchedule = currentTask?.schedule;
  final hasTimedCurrentTask = currentSchedule?.isTimed ?? false;
  TaskItem? next;
  for (final task in tasks) {
    final schedule = task.schedule;
    if (task.id == completion.taskId ||
        task.isCompleted ||
        task.isDeleted ||
        schedule == null ||
        !schedule.isTimed) {
      continue;
    }
    if (hasTimedCurrentTask) {
      if (_compareScheduledTasks(task, currentTask!) <= 0) {
        continue;
      }
    } else if (!schedule.start!.isAfter(completion.completedAt)) {
      continue;
    }
    if (next == null || _compareScheduledTasks(task, next) < 0) {
      next = task;
    }
  }
  return next;
}

int _compareScheduledTasks(TaskItem left, TaskItem right) {
  final start = left.schedule!.start!.compareTo(right.schedule!.start!);
  if (start != 0) {
    return start;
  }
  final dayOrder = (left.dayOrder ?? 999999).compareTo(
    right.dayOrder ?? 999999,
  );
  if (dayOrder != 0) {
    return dayOrder;
  }
  final orderKey = left.orderKey.compareTo(right.orderKey);
  return orderKey != 0 ? orderKey : left.id.compareTo(right.id);
}
