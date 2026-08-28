import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/task_models.dart';

enum TaskMotionKind { created, completed, reopened, deleted, landed }

class TaskMotionEvent {
  const TaskMotionEvent(this.kind, this.revision);

  final TaskMotionKind kind;
  final int revision;
}

class TaskMotionController extends ChangeNotifier {
  static const maxAnimatedBulkTasks = 6;

  final _events = <String, TaskMotionEvent>{};
  final _retained = <String, TaskItem>{};
  var _revision = 0;

  List<TaskItem> get retainedTasks => List.unmodifiable(_retained.values);

  TaskMotionEvent? eventFor(String taskId) => _events[taskId];

  void created(Set<String> taskIds) => _record(taskIds, TaskMotionKind.created);

  void completed(Iterable<TaskItem> tasks) =>
      _hold(tasks, TaskMotionKind.completed);

  void reopened(Iterable<TaskItem> tasks) =>
      _hold(tasks, TaskMotionKind.reopened);

  void deleted(Iterable<TaskItem> tasks) =>
      _hold(tasks, TaskMotionKind.deleted);

  void landed(Set<String> taskIds) => _record(taskIds, TaskMotionKind.landed);

  void finishDelete(String taskId, int revision) {
    if (_events[taskId]?.revision != revision) {
      return;
    }
    _events.remove(taskId);
    _retained.remove(taskId);
    notifyListeners();
  }

  @override
  void dispose() {
    _events.clear();
    _retained.clear();
    super.dispose();
  }

  void _hold(Iterable<TaskItem> tasks, TaskMotionKind kind) {
    final batch = tasks.toList();
    if (batch.length > maxAnimatedBulkTasks) {
      return;
    }
    for (final task in batch) {
      _retained[task.id] = task;
    }
    _record(batch.map((task) => task.id).toSet(), kind);
  }

  void _record(Set<String> taskIds, TaskMotionKind kind) {
    if (taskIds.isEmpty || taskIds.length > maxAnimatedBulkTasks) {
      return;
    }
    final revision = ++_revision;
    for (final taskId in taskIds) {
      _events[taskId] = TaskMotionEvent(kind, revision);
    }
    notifyListeners();
  }
}

class TaskMotionScope extends StatefulWidget {
  const TaskMotionScope({required this.builder, super.key});

  final Widget Function(BuildContext context, TaskMotionController controller)
  builder;

  static TaskMotionController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_TaskMotionInherited>()
      ?.notifier;

  @override
  State<TaskMotionScope> createState() => _TaskMotionScopeState();
}

class _TaskMotionScopeState extends State<TaskMotionScope> {
  final _controller = TaskMotionController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _TaskMotionInherited(
      controller: _controller,
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, child) => widget.builder(context, _controller),
      ),
    );
  }
}

class _TaskMotionInherited extends InheritedNotifier<TaskMotionController> {
  const _TaskMotionInherited({
    required TaskMotionController controller,
    required super.child,
  }) : super(notifier: controller);
}

class TaskMotionItem extends StatelessWidget {
  const TaskMotionItem({required this.taskId, required this.child, super.key});

  final String taskId;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final motion = TaskMotionScope.maybeOf(context);
    if (motion == null) {
      return child;
    }
    final event = motion.eventFor(taskId);
    final kind = event?.kind;
    final deleting = kind == TaskMotionKind.deleted;
    final creating = kind == TaskMotionKind.created;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : switch (kind) {
            TaskMotionKind.created ||
            TaskMotionKind.landed => const Duration(milliseconds: 160),
            TaskMotionKind.deleted => const Duration(milliseconds: 220),
            _ => Duration.zero,
          };
    final begin = creating || kind == TaskMotionKind.landed ? 0.0 : 1.0;

    return TweenAnimationBuilder<double>(
      key: ValueKey('${event?.revision ?? 0}-$kind'),
      tween: Tween(begin: begin, end: deleting ? 0 : 1),
      duration: duration,
      curve: Curves.easeOutCubic,
      onEnd: deleting && event != null
          ? () => motion.finishDelete(taskId, event.revision)
          : null,
      builder: (context, value, child) {
        final landed = kind == TaskMotionKind.landed;
        return DecoratedBox(
          key: Key('task-motion-highlight-$taskId'),
          decoration: BoxDecoration(
            color: landed
                ? Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.12 * (1 - value))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: ClipRect(
            child: Align(
              key: Key('task-motion-size-$taskId'),
              heightFactor: deleting ? value : 1,
              child: Transform.translate(
                key: Key('task-motion-offset-$taskId'),
                offset: Offset(0, creating ? 6 * (1 - value) : 0),
                child: Opacity(
                  key: Key('task-motion-opacity-$taskId'),
                  opacity: value,
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
      child: child,
    );
  }
}

class TaskCompletionControl extends StatelessWidget {
  const TaskCompletionControl({
    required this.taskId,
    required this.isCompleted,
    required this.color,
    required this.fillColor,
    required this.onPressed,
    this.tooltip,
    super.key,
  });

  final String taskId;
  final bool isCompleted;
  final Color color;
  final Color fillColor;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final event = TaskMotionScope.maybeOf(context)?.eventFor(taskId);
    final animated =
        event?.kind == TaskMotionKind.completed ||
        event?.kind == TaskMotionKind.reopened;
    final target = isCompleted ? 1.0 : 0.0;
    final duration = animated && !MediaQuery.disableAnimationsOf(context)
        ? const Duration(milliseconds: 180)
        : Duration.zero;
    final control = Semantics(
      button: true,
      checked: isCompleted,
      child: InkResponse(
        key: Key('task-completion-control-$taskId'),
        onTap: onPressed,
        radius: 18,
        child: SizedBox.square(
          dimension: 24,
          child: TweenAnimationBuilder<double>(
            key: ValueKey('task-completion-${event?.revision}-$target'),
            tween: Tween(begin: animated ? 1 - target : target, end: target),
            duration: duration,
            builder: (context, progress, child) => CustomPaint(
              key: Key('task-completion-paint-$taskId'),
              painter: TaskCompletionPainter(
                progress: progress,
                color: color,
                fillColor: fillColor,
              ),
            ),
          ),
        ),
      ),
    );
    return tooltip == null
        ? control
        : Tooltip(message: tooltip!, child: control);
  }
}

class TaskCompletionPainter extends CustomPainter {
  const TaskCompletionPainter({
    required this.progress,
    required this.color,
    required this.fillColor,
  });

  final double progress;
  final Color color;
  final Color fillColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - 1.5;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    final ringProgress = Curves.easeOutCubic.transform(
      (progress / (80 / 180)).clamp(0.0, 1.0),
    );
    if (ringProgress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        math.pi * 2 * ringProgress,
        false,
        Paint()
          ..color = fillColor
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 2.4,
      );
    }
    final fillProgress = Curves.easeOutCubic.transform(
      ((progress - (80 / 180)) / (100 / 180)).clamp(0.0, 1.0),
    );
    if (fillProgress <= 0) {
      return;
    }
    canvas.drawCircle(
      center,
      radius * fillProgress,
      Paint()..color = fillColor,
    );
    final check = Path()
      ..moveTo(size.width * 0.28, size.height * 0.52)
      ..lineTo(size.width * 0.44, size.height * 0.68)
      ..lineTo(size.width * 0.74, size.height * 0.35);
    canvas.drawPath(
      check,
      Paint()
        ..color = Colors.white.withValues(alpha: fillProgress)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(TaskCompletionPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.fillColor != fillColor;
}
