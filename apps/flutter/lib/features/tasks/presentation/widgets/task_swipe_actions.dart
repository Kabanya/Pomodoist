import 'dart:math' as math;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons;

import '../../../../app/app_l10n.dart';
import '../../../../app/theme/app_motion.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../app/widgets/action_feedback.dart';

enum TaskSwipeAction { focus, schedule }

/// Gesture state only: revealing an action can never execute it.
class TaskSwipeState {
  double offset = 0;
  double _origin = 0;
  double _travel = 0;
  bool dragging = false;

  static double actionExtent(double rowWidth) => math.min(144, rowWidth / 2);

  TaskSwipeAction? get revealed => dragging || offset == 0
      ? null
      : offset > 0
      ? TaskSwipeAction.focus
      : TaskSwipeAction.schedule;

  void begin(double currentOffset) {
    _origin = offset = currentOffset;
    _travel = 0;
    dragging = true;
  }

  void update(double delta, double extent) {
    if (!dragging) return;
    _travel += delta;
    offset = (_origin + _travel).clamp(-extent, extent);
  }

  void end(double extent) {
    if (!dragging) return;
    dragging = false;
    if (_origin != 0) {
      offset = _travel * _origin < 0 ? 0 : _origin.sign * extent;
    } else {
      offset = _travel.abs() >= 48 ? _travel.sign * extent : 0;
    }
  }

  void close() {
    offset = _origin = _travel = 0;
    dragging = false;
  }
}

class TaskSwipeActions extends StatefulWidget {
  const TaskSwipeActions({
    required this.enabled,
    required this.onFocus,
    required this.onSchedule,
    required this.builder,
    super.key,
  });

  final bool enabled;
  final Future<void> Function() onFocus;
  final Future<void> Function() onSchedule;
  final Widget Function(ValueChanged<bool> onTaskDraggingChanged) builder;

  @override
  State<TaskSwipeActions> createState() => _TaskSwipeActionsState();
}

class _TaskSwipeActionsState extends State<TaskSwipeActions>
    with SingleTickerProviderStateMixin {
  final _swipe = TaskSwipeState();
  late final _slide = AnimationController.unbounded(vsync: this);
  bool _taskDragging = false;
  bool _executing = false;

  bool get _enabled => widget.enabled && !_taskDragging && !_executing;

  @override
  void didUpdateWidget(covariant TaskSwipeActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) {
      _swipe.close();
      _slide.value = 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) _slide.value = _swipe.offset;
  }

  @override
  void dispose() {
    _slide.dispose();
    super.dispose();
  }

  void _settle() {
    final duration = AppMotion.duration(context, AppMotion.state);
    if (duration == Duration.zero) {
      _slide.value = _swipe.offset;
    } else {
      _slide.animateTo(
        _swipe.offset,
        duration: duration,
        curve: AppMotion.curve,
      );
    }
  }

  void _close() {
    if (!mounted) return;
    _swipe.close();
    _settle();
    setState(() {});
  }

  void _onTaskDraggingChanged(bool value) {
    if (!mounted) return;
    setState(() {
      _taskDragging = value;
      _swipe.close();
      _slide.value = 0;
    });
  }

  Future<void> _activate(TaskSwipeAction action) async {
    if (!_enabled || _swipe.revealed != action) return;
    setState(() => _executing = true);
    _close();
    try {
      await (action == TaskSwipeAction.focus
          ? widget.onFocus
          : widget.onSchedule)();
    } catch (_) {
      if (mounted) {
        showActionFeedback(
          context,
          message: context.l10n.taskActionFailedCount(1),
          icon: LucideIcons.circleAlert,
          sound: ActionFeedbackSound.none,
          haptic: AppHapticCue.none,
        );
      }
    } finally {
      if (mounted) setState(() => _executing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.builder(_onTaskDraggingChanged);
    return LayoutBuilder(
      builder: (context, constraints) {
        final extent = TaskSwipeState.actionExtent(constraints.maxWidth);
        return AnimatedBuilder(
          animation: _slide,
          child: AbsorbPointer(absorbing: _executing, child: row),
          builder: (context, child) {
            final offset = _slide.value.clamp(-extent, extent);
            final action = offset > 0
                ? TaskSwipeAction.focus
                : TaskSwipeAction.schedule;
            final label = action == TaskSwipeAction.focus
                ? context.l10n.navFocus
                : context.l10n.taskSchedule;
            return PopScope(
              canPop: offset == 0,
              onPopInvokedWithResult: (didPop, _) {
                if (!didPop && offset != 0) _close();
              },
              child: TapRegion(
                onTapOutside: (_) {
                  if (offset != 0) _close();
                },
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  dragStartBehavior: DragStartBehavior.down,
                  onHorizontalDragStart: !_enabled
                      ? null
                      : (_) {
                          _slide.stop();
                          setState(() => _swipe.begin(_slide.value));
                        },
                  onHorizontalDragUpdate: !_enabled
                      ? null
                      : (details) {
                          _swipe.update(details.delta.dx, extent);
                          _slide.value = _swipe.offset;
                        },
                  onHorizontalDragEnd: !_enabled
                      ? null
                      : (_) {
                          setState(() => _swipe.end(extent));
                          _settle();
                        },
                  onHorizontalDragCancel: !_enabled ? null : _close,
                  child: ClipRect(
                    child: Stack(
                      children: [
                        if (offset != 0)
                          Positioned(
                            top: 0,
                            bottom: 0,
                            left: offset > 0 ? 0 : null,
                            right: offset < 0 ? 0 : null,
                            width: offset.abs(),
                            child: ClipRect(
                              child: OverflowBox(
                                alignment: offset > 0
                                    ? Alignment.centerLeft
                                    : Alignment.centerRight,
                                minWidth: extent,
                                maxWidth: extent,
                                child: Material(
                                  color: context.appColors.accentTint,
                                  child: TextButton(
                                    onPressed:
                                        _enabled && _swipe.revealed == action
                                        ? () => _activate(action)
                                        : null,
                                    child: Text(
                                      label,
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        Transform.translate(
                          offset: Offset(offset, 0),
                          child: child,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
