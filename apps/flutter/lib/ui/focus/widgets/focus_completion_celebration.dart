import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart'
    show LucideIcons, ShadButton, ShadButtonVariant;

import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/localization/formatters.dart';
import 'package:pomodoist/ui/focus/view_models/focus_completion_view_model.dart';
import 'package:pomodoist/ui/core/themes/app_motion.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/core/widgets/action_feedback.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/ui/tasks/widgets/task_completion_feedback.dart';
import 'package:pomodoist/domain/models/focus/focus_models.dart';

const _celebrationDuration = Duration(milliseconds: 900);

// The mark completes early; the decorative burst settles on the same timeline.
({double ring, double check, double halo, double particles})
focusCompletionProgress(double progress, {bool reduceMotion = false}) {
  final t = reduceMotion ? 1.0 : progress.clamp(0.0, 1.0);
  double phase(double start, double end) =>
      ((t - start) / (end - start)).clamp(0.0, 1.0);
  return (
    ring: AppMotion.curve.transform(phase(0, .4)),
    check: AppMotion.curve.transform(phase(.2, .4)),
    halo: AppMotion.curve.transform(phase(.12, .8)),
    particles: phase(.24, 1),
  );
}

class FocusRunCompletionCelebrationSlot extends ConsumerWidget {
  const FocusRunCompletionCelebrationSlot({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final completion = ref.watch(focusCompletionSlotViewModelProvider);
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
    _controller = AnimationController(
      vsync: this,
      duration: _celebrationDuration,
    );
    _contentOpacity = _controller.drive(
      CurveTween(
        curve: Interval(
          0,
          AppMotion.state.inMilliseconds / _celebrationDuration.inMilliseconds,
          curve: AppMotion.curve,
        ),
      ),
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
    final state = ref.watch(focusCompletionViewModelProvider(completion));
    final actions = ref.read(
      focusCompletionViewModelProvider(completion).notifier,
    );
    final taskId = completion.taskId;
    final resolvingTask = state.resolvingTask;
    final canCompleteTask = state.canCompleteTask;
    final loading = state.loading;
    final hasError = state.hasError;
    final nextTask = state.nextTask;
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
                        animation: _controller,
                        colors: colors,
                      ),
                      FadeTransition(
                        key: const Key('focus-completion-content-entrance'),
                        opacity: _contentOpacity,
                        child: AnimatedBuilder(
                          animation: _contentOpacity,
                          builder: (context, child) => Transform.translate(
                            offset: Offset(0, 4 * (1 - _contentOpacity.value)),
                            child: child,
                          ),
                          child: _CompletionContent(
                            completion: completion,
                            taskTitle: taskTitle,
                            subtitle: subtitle,
                            resolvingTask: loading,
                            hasError: hasError,
                            busy: state.busy,
                            onRetry: actions.retry,
                            canCompleteTask: canCompleteTask,
                            onCompleteTask:
                                taskId == null ||
                                    resolvingTask ||
                                    state.taskHasError
                                ? null
                                : () => _completeTask(),
                            nextTask: nextTask,
                            onStartNextTask: nextTask == null
                                ? null
                                : _startNextTask,
                            onDismiss: _dismiss,
                          ),
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

  Future<void> _completeTask() async {
    final actions = ref.read(
      focusCompletionViewModelProvider(widget.completion).notifier,
    );
    final completed = await completeTaskWithUndoFeedback(
      context,
      complete: actions.completeLinkedTask,
      undo: actions.undoLinkedTask,
    );
    if (completed && mounted) actions.dismiss();
  }

  Future<void> _startNextTask() async {
    try {
      await ref
          .read(focusCompletionViewModelProvider(widget.completion).notifier)
          .startNextTask();
    } catch (error) {
      if (!mounted) return;
      showActionFeedback(
        context,
        message: context.l10n.kanbanCouldNotStartFocus(error),
        icon: LucideIcons.circleAlert,
        sound: ActionFeedbackSound.none,
      );
    }
  }

  void _dismiss() => ref
      .read(focusCompletionViewModelProvider(widget.completion).notifier)
      .dismiss();
}

class _CelebrationArtwork extends StatelessWidget {
  const _CelebrationArtwork({required this.animation, required this.colors});

  final Animation<double> animation;
  final AppThemePalette colors;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final size = MediaQuery.sizeOf(context).width < 420 ? 200.0 : 232.0;
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: size,
        child: AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            final frame = focusCompletionProgress(
              animation.value,
              reduceMotion: reduceMotion,
            );
            return Stack(
              fit: StackFit.expand,
              children: [
                if (!reduceMotion)
                  CustomPaint(
                    key: const Key('focus-completion-particles'),
                    painter: _CelebrationParticlePainter(
                      progress: frame.particles,
                      colors: [
                        colors.accent,
                        colors.secondaryText,
                        colors.accent,
                        colors.border,
                      ],
                    ),
                  ),
                Center(
                  child: CustomPaint(
                    key: const Key('focus-completion-mark'),
                    size: const Size.square(120),
                    painter: _CompletionMarkPainter(
                      ring: frame.ring,
                      check: frame.check,
                      halo: frame.halo,
                      accent: colors.accent,
                      tint: colors.accentTint,
                      border: colors.border,
                    ),
                  ),
                ),
              ],
            );
          },
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
    required this.hasError,
    required this.busy,
    required this.onRetry,
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
  final bool hasError;
  final bool busy;
  final VoidCallback onRetry;
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
    final state = ref.watch(focusCompletionTimeViewModelProvider(nextTask));
    final taskTimeState = state.timeState;
    final taskTimeColor = taskTimeState == null
        ? colors.secondaryText
        : colors.taskTimeColor(taskTimeState);
    final timeDisplayMode = state.displayMode;
    final defaultTimedBlockMinutes = state.defaultTimedBlockMinutes;
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
        if (resolvingTask || busy) ...[
          const SizedBox.square(
            key: Key('focus-completion-task-loading'),
            dimension: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          const SizedBox(height: 16),
        ],
        if (hasError) ...[
          Text(
            l10n.taskActionFailedCount(1),
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(color: colors.error),
          ),
          ShadButton.secondary(
            onPressed: onRetry,
            enabled: !busy && !resolvingTask,
            child: Text(l10n.focusCompletionRetry),
          ),
        ],
        if (canCompleteTask) ...[
          Text(
            l10n.focusCompletionQuestion,
            textAlign: TextAlign.center,
            style: textTheme.bodyLarge?.copyWith(color: colors.primaryText),
          ),
          const SizedBox(height: 16),
        ],
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          runSpacing: 8,
          children: [
            if (nextTask != null)
              ShadButton(
                key: const Key('focus-completion-start-next-task'),
                onPressed: onStartNextTask,
                enabled:
                    !busy &&
                    !resolvingTask &&
                    !hasError &&
                    onStartNextTask != null,
                leading: const Icon(LucideIcons.play, size: 18),
                height: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Flexible(
                  child: Text(
                    canCompleteTask
                        ? l10n.focusCompletionCompleteAndNext
                        : l10n.focusCompletionStartNext,
                  ),
                ),
              ),
            if (canCompleteTask)
              ShadButton.raw(
                variant: nextTask == null
                    ? ShadButtonVariant.primary
                    : ShadButtonVariant.secondary,
                key: const Key('focus-completion-complete-task'),
                onPressed: onCompleteTask,
                enabled: !busy && onCompleteTask != null,
                leading: const Icon(LucideIcons.circleCheck, size: 18),
                height: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Flexible(child: Text(l10n.focusCompletionCompleteTask)),
              ),
            if (canCompleteTask)
              ShadButton.ghost(
                key: const Key('focus-completion-keep-open'),
                onPressed: onDismiss,
                enabled: !busy,
                height: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Flexible(child: Text(l10n.focusCompletionKeepOpen)),
              )
            else
              ShadButton.secondary(
                key: const Key('focus-completion-done'),
                onPressed: onDismiss,
                enabled: !busy,
                leading: const Icon(LucideIcons.check, size: 18),
                height: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Flexible(child: Text(l10n.focusCompletionDone)),
              ),
          ],
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
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _CompletionMarkPainter extends CustomPainter {
  const _CompletionMarkPainter({
    required this.ring,
    required this.check,
    required this.halo,
    required this.accent,
    required this.tint,
    required this.border,
  });

  final double ring;
  final double check;
  final double halo;
  final Color accent;
  final Color tint;
  final Color border;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 8;
    canvas.drawCircle(
      center,
      radius + 24 * halo,
      Paint()..color = accent.withValues(alpha: .08 * (1 - halo)),
    );
    canvas.drawCircle(center, radius, Paint()..color = tint);
    final ringPaint = Paint()
      ..color = border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, ringPaint);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      math.pi * 2 * ring,
      false,
      ringPaint..color = accent,
    );
    if (check > 0) {
      final path = Path()
        ..moveTo(size.width * .31, size.height * .51)
        ..lineTo(size.width * .45, size.height * .65)
        ..lineTo(size.width * .70, size.height * .36);
      final metric = path.computeMetrics().first;
      canvas.drawPath(
        metric.extractPath(0, metric.length * check),
        Paint()
          ..color = accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(_CompletionMarkPainter oldDelegate) =>
      oldDelegate.ring != ring ||
      oldDelegate.check != check ||
      oldDelegate.halo != halo ||
      oldDelegate.accent != accent ||
      oldDelegate.tint != tint ||
      oldDelegate.border != border;
}

class _CelebrationParticlePainter extends CustomPainter {
  const _CelebrationParticlePainter({
    required this.progress,
    required this.colors,
  });

  final double progress;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    final center = size.center(Offset.zero);
    final travel = AppMotion.curve.transform(progress);
    final opacity = math.sin(math.pi * progress).clamp(0.0, 1.0) * .8;
    for (var index = 0; index < 18; index++) {
      final angle = index * math.pi * (3 - math.sqrt(5));
      final spread = size.shortestSide * (.35 + (index % 5) * .025);
      final distance = 54 + (spread - 54) * travel;
      final drift = Offset(math.cos(angle), math.sin(angle)) * distance;
      final length = 2.0 + (index % 3);
      final paint = Paint()
        ..color = colors[index % colors.length].withValues(alpha: opacity);
      canvas.save();
      canvas.translate(center.dx + drift.dx, center.dy + drift.dy);
      canvas.rotate(angle + progress * .6);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset.zero,
            width: length,
            height: length * 1.6,
          ),
          const Radius.circular(1),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_CelebrationParticlePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.colors != colors;
}
