import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_l10n.dart';
import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/action_feedback.dart';
import '../../tasks/presentation/task_completion_feedback.dart';
import '../domain/focus_models.dart';
import 'focus_completion_celebration_controller.dart';

const _celebrationDuration = Duration(milliseconds: 1600);

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
  late final Animation<Offset> _contentOffset;
  bool _started = false;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _celebrationDuration,
    );
    final contentCurve = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.48, 0.82, curve: Curves.easeOutCubic),
    );
    _contentOpacity = contentCurve;
    _contentOffset = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(contentCurve);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (!_started) {
      _started = true;
      if (_reduceMotion) {
        _controller.value = 1;
      } else {
        _controller.forward();
      }
    } else if (_reduceMotion && _controller.value != 1) {
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
    final taskTitle = completion.taskTitle?.trim();
    final subtitle = taskId == null
        ? l10n.focusCompletionStandaloneSubtitle
        : l10n.focusCompletionLinkedSubtitle;

    return PopScope(
      canPop: false,
      child: Material(
        key: const Key('focus-completion-overlay'),
        color: colors.canvas,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                colors.canvas,
                colors.accentTint.withValues(alpha: 0.62),
                colors.canvas,
              ],
              stops: const [0, 0.48, 1],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 32,
                ),
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
                          showParticles: !_reduceMotion,
                        ),
                        FadeTransition(
                          key: const Key('focus-completion-content-entrance'),
                          opacity: _contentOpacity,
                          child: SlideTransition(
                            position: _contentOffset,
                            child: _CompletionContent(
                              completion: completion,
                              taskTitle: taskTitle,
                              subtitle: subtitle,
                              resolvingTask: resolvingTask,
                              canCompleteTask: canCompleteTask,
                              onCompleteTask: taskId == null
                                  ? null
                                  : () => _completeTask(taskId),
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
      ),
    );
  }

  Future<void> _completeTask(String taskId) async {
    try {
      await completeTaskWithUndoFeedback(context, ref, taskId);
      if (mounted) {
        _dismiss();
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      showActionFeedback(
        context,
        message: context.l10n.focusCompletionTaskError(error),
        icon: Icons.error_outline,
        sound: ActionFeedbackSound.none,
      );
    }
  }

  void _dismiss() {
    ref.read(focusRunCompletionControllerProvider.notifier).dismiss();
  }
}

class _CelebrationArtwork extends StatelessWidget {
  const _CelebrationArtwork({
    required this.animation,
    required this.colors,
    required this.showParticles,
  });

  final Animation<double> animation;
  final AppThemePalette colors;
  final bool showParticles;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context).width < 420 ? 210.0 : 250.0;
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: size,
        child: AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            return Stack(
              fit: StackFit.expand,
              children: [
                if (showParticles)
                  CustomPaint(
                    key: const Key('focus-completion-particles'),
                    painter: _CelebrationParticlePainter(
                      progress: _interval(animation.value, 0.28, 0.9),
                      colors: [colors.accent, colors.warning, colors.info],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(34),
                  child: CustomPaint(
                    key: const Key('focus-completion-mark'),
                    painter: _CompletionMarkPainter(
                      progress: animation.value,
                      accent: colors.accent,
                      accentFill: colors.accentFill,
                      tint: colors.accentTint,
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

class _CompletionContent extends StatelessWidget {
  const _CompletionContent({
    required this.completion,
    required this.taskTitle,
    required this.subtitle,
    required this.resolvingTask,
    required this.canCompleteTask,
    required this.onCompleteTask,
    required this.onDismiss,
  });

  final FocusRunCompletionEvent completion;
  final String? taskTitle;
  final String subtitle;
  final bool resolvingTask;
  final bool canCompleteTask;
  final Future<void> Function()? onCompleteTask;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.focusCompletionTitle,
          textAlign: TextAlign.center,
          style: textTheme.headlineMedium?.copyWith(
            color: colors.primaryText,
            fontWeight: FontWeight.w800,
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
              color: colors.surface.withValues(alpha: 0.86),
              border: Border.all(color: colors.border),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              taskTitle!,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: textTheme.titleLarge?.copyWith(
                color: colors.primaryText,
                fontWeight: FontWeight.w700,
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
            style: textTheme.labelLarge?.copyWith(
              color: colors.accent,
              fontWeight: FontWeight.w700,
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
              FilledButton.icon(
                key: const Key('focus-completion-complete-task'),
                onPressed: onCompleteTask,
                icon: const Icon(Icons.task_alt),
                label: Text(l10n.focusCompletionCompleteTask),
              ),
              TextButton(
                key: const Key('focus-completion-keep-open'),
                onPressed: onDismiss,
                child: Text(l10n.focusCompletionKeepOpen),
              ),
            ],
          ),
        ] else
          FilledButton.icon(
            key: const Key('focus-completion-done'),
            onPressed: onDismiss,
            icon: const Icon(Icons.check),
            label: Text(l10n.focusCompletionDone),
          ),
      ],
    );
  }
}

class _CompletionMarkPainter extends CustomPainter {
  const _CompletionMarkPainter({
    required this.progress,
    required this.accent,
    required this.accentFill,
    required this.tint,
  });

  final double progress;
  final Color accent;
  final Color accentFill;
  final Color tint;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 8;
    final haloProgress = _interval(progress, 0.16, 0.68);
    final ringProgress = _interval(progress, 0.02, 0.48);
    final fillProgress = _interval(progress, 0.34, 0.66);
    final checkProgress = _interval(progress, 0.44, 0.72);

    canvas.drawCircle(
      center,
      radius + 18 * haloProgress,
      Paint()..color = accent.withValues(alpha: 0.1 * (1 - haloProgress)),
    );
    canvas.drawCircle(center, radius, Paint()..color = tint);
    if (fillProgress > 0) {
      canvas.drawCircle(
        center,
        radius * Curves.easeOutCubic.transform(fillProgress),
        Paint()..color = Color.lerp(tint, accentFill, fillProgress)!,
      );
    }

    final ringPaint = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      math.pi * 2 * ringProgress,
      false,
      ringPaint,
    );

    if (checkProgress > 0) {
      final check = Path()
        ..moveTo(size.width * 0.29, size.height * 0.53)
        ..lineTo(size.width * 0.45, size.height * 0.68)
        ..lineTo(size.width * 0.73, size.height * 0.36);
      final metric = check.computeMetrics().first;
      final visible = metric.extractPath(0, metric.length * checkProgress);
      canvas.drawPath(
        visible,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 11
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(_CompletionMarkPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.accent != accent ||
      oldDelegate.accentFill != accentFill ||
      oldDelegate.tint != tint;
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
    if (progress <= 0 || progress >= 1) {
      return;
    }
    final center = size.center(Offset.zero);
    final travel = Curves.easeOutCubic.transform(progress);
    final opacity = math.sin(math.pi * progress).clamp(0.0, 1.0);
    for (var index = 0; index < 30; index++) {
      final angle = index * math.pi * (3 - math.sqrt(5));
      final spread = 46.0 + (index % 7) * 9;
      final drift = Offset(math.cos(angle), math.sin(angle)) * spread * travel;
      final particleCenter = center + drift;
      final length = 4.0 + (index % 4) * 1.6;
      final paint = Paint()
        ..color = colors[index % colors.length].withValues(alpha: opacity);
      canvas.save();
      canvas.translate(particleCenter.dx, particleCenter.dy);
      canvas.rotate(angle + progress * 1.5);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset.zero,
            width: length,
            height: length * 1.8,
          ),
          const Radius.circular(2),
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

double _interval(double value, double start, double end) {
  return ((value - start) / (end - start)).clamp(0.0, 1.0);
}
