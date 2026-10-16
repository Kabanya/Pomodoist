import 'package:pomodoist/ui/tasks/widgets/task_row_geometry.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons;
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/routing/task_detail_navigation.dart';
import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/core/widgets/action_feedback.dart';
import 'package:pomodoist/ui/tasks/view_models/task_branch_rows.dart';
import 'package:pomodoist/ui/tasks/view_models/task_branch_view_model.dart';
import 'package:pomodoist/ui/tasks/view_models/task_subtask_progress.dart';

bool get usesTouchTaskInteraction =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// Mobile disclosure uses the trailing action slot, not a leading margin.
double get taskBranchGutterWidth => usesTouchTaskInteraction ? 0 : 24;

Future<void> setTaskBranchExpanded(
  BuildContext context,
  WidgetRef ref,
  String scopeKey,
  String taskId,
  bool expanded,
) async {
  try {
    await ref
        .read(taskBranchViewModelProvider(scopeKey).notifier)
        .setExpanded(taskId, expanded);
  } catch (_) {
    if (context.mounted) _saveError(context);
  }
}

Future<void> revealCreatedTaskBranches(
  BuildContext context,
  WidgetRef ref,
  String scopeKey,
  Iterable<String> taskIds,
) async {
  try {
    await ref
        .read(taskBranchViewModelProvider(scopeKey).notifier)
        .revealCreatedTasks(taskIds);
  } catch (_) {
    if (context.mounted) _saveError(context);
  }
}

void _saveError(BuildContext context) => showActionFeedback(
  context,
  message: context.l10n.settingsSaveError,
  icon: LucideIcons.circleAlert,
  sound: ActionFeedbackSound.none,
  haptic: AppHapticCue.none,
);

class TaskParentContext extends StatelessWidget {
  const TaskParentContext({
    required this.task,
    required this.ancestors,
    super.key,
  });
  final TaskItem task;
  final List<TaskItem> ancestors;

  @override
  Widget build(BuildContext context) {
    final parent = ancestors
        .where((item) => item.id == task.parentId)
        .firstOrNull;
    final label = parent == null
        ? context.l10n.taskParentUnavailable
        : context.l10n.taskParentPath(
            ancestors.map((item) => item.content).join(' / '),
          );
    if (usesTouchTaskInteraction) {
      return Tooltip(
        message: label,
        triggerMode: TooltipTriggerMode.manual,
        excludeFromSemantics: true,
        child: Semantics(
          label: label,
          child: Transform.flip(
            flipX: Directionality.of(context) == TextDirection.rtl,
            child: Icon(
              LucideIcons.cornerDownRight,
              size: 12,
              color: context.appColors.secondaryText,
            ),
          ),
        ),
      );
    }
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Transform.flip(
          flipX: Directionality.of(context) == TextDirection.rtl,
          child: const Icon(LucideIcons.cornerDownRight, size: 12),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: context.appColors.secondaryText,
            ),
          ),
        ),
      ],
    );
    if (parent == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: content,
      );
    }
    return Tooltip(
      message: label,
      child: TextButton(
        onPressed: () => openTaskDetails(context, parent.id),
        style: TextButton.styleFrom(
          alignment: AlignmentDirectional.centerStart,
          minimumSize: const Size(44, 44),
          padding: EdgeInsets.zero,
          foregroundColor: context.appColors.secondaryText,
        ),
        child: content,
      ),
    );
  }
}

class TaskBranchProgressButton extends StatefulWidget {
  const TaskBranchProgressButton({
    required this.taskId,
    required this.progress,
    this.expanded,
    this.onToggle,
    this.showProgress = true,
    super.key,
  });
  final String taskId;
  final TaskSubtaskProgress progress;
  final bool? expanded;
  final VoidCallback? onToggle;
  final bool showProgress;

  @override
  State<TaskBranchProgressButton> createState() =>
      _TaskBranchProgressButtonState();
}

class _TaskBranchProgressButtonState extends State<TaskBranchProgressButton> {
  final _focus = FocusNode();
  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final action = widget.onToggle == null
        ? l10n.taskOpenFullBranch
        : widget.expanded!
        ? l10n.taskCollapseSubtasks
        : l10n.taskExpandSubtasks;
    final label =
        '$action. ${l10n.taskAllSubtasksProgress(widget.progress.completed, widget.progress.total)}';
    return Semantics(
      expanded: widget.onToggle == null ? null : widget.expanded,
      child: Tooltip(
        message: label,
        child: TextButton(
          key: ValueKey('task-branch-toggle-${widget.taskId}'),
          focusNode: _focus,
          onPressed: () {
            if (widget.onToggle == null) {
              openTaskDetails(context, widget.taskId);
            } else {
              _focus.requestFocus();
              widget.onToggle!();
            }
          },
          style: TextButton.styleFrom(
            minimumSize: const Size(44, 44),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            foregroundColor: context.appColors.secondaryText,
            alignment: widget.onToggle == null
                ? AlignmentDirectional.centerStart
                : Alignment.center,
          ),
          child: Semantics(
            label: label,
            excludeSemantics: true,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.flip(
                  flipX:
                      widget.onToggle != null &&
                      !widget.expanded! &&
                      Directionality.of(context) == TextDirection.rtl,
                  child: Icon(
                    widget.onToggle == null
                        ? LucideIcons.gitBranch
                        : widget.expanded!
                        ? LucideIcons.chevronDown
                        : LucideIcons.chevronRight,
                    size: 12,
                  ),
                ),
                if (widget.showProgress) ...[
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      widget.progress.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.monoTextStyle.copyWith(fontSize: 11),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact cards retain their own activation target and fixed geometry.
class TaskHierarchySummary extends ConsumerWidget {
  const TaskHierarchySummary({
    required this.task,
    this.compact = false,
    super.key,
  });
  final TaskItem task;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(taskHierarchyViewModelProvider);
    final ancestors = hierarchyAncestors(task, data);
    final progress = data.progress[task.id];
    if (task.parentId == null && progress == null) {
      return const SizedBox.shrink();
    }
    if (!compact) {
      return Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (task.parentId != null)
            TaskParentContext(task: task, ancestors: ancestors),
          if (progress != null)
            TaskBranchProgressButton(taskId: task.id, progress: progress),
        ],
      );
    }
    final parentLabel = task.parentId == null
        ? null
        : ancestors.isEmpty
        ? context.l10n.taskParentUnavailable
        : context.l10n.taskParentPath(
            ancestors.map((item) => item.content).join(' / '),
          );
    final label = [
      ?parentLabel,
      if (progress != null)
        context.l10n.taskAllSubtasksProgress(
          progress.completed,
          progress.total,
        ),
    ].join(' · ');
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        excludeSemantics: true,
        child: Text.rich(
          TextSpan(
            children: [
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(end: 4),
                  child: Transform.flip(
                    flipX:
                        parentLabel != null &&
                        Directionality.of(context) == TextDirection.rtl,
                    child: Icon(
                      parentLabel == null
                          ? LucideIcons.gitBranch
                          : LucideIcons.cornerDownRight,
                      size: 12,
                      color: context.appColors.secondaryText,
                    ),
                  ),
                ),
              ),
              TextSpan(
                text: [
                  ?parentLabel,
                  if (progress != null) progress.label,
                ].join(' · '),
              ),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: context.appColors.secondaryText,
          ),
        ),
      ),
    );
  }
}

class TaskBranchLines extends StatelessWidget {
  const TaskBranchLines({
    required this.row,
    required this.child,
    this.divider = false,
    this.anchor,
    super.key,
  });
  final VisibleTaskRow row;
  final Widget child;
  final bool divider;
  final double? anchor;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _BranchPainter(
      row,
      context.appColors.border,
      Directionality.of(context),
      divider,
      anchor,
    ),
    child: child,
  );
}

class _BranchPainter extends CustomPainter {
  _BranchPainter(
    this.row,
    this.color,
    this.direction,
    this.divider,
    this.anchor,
  );
  final VisibleTaskRow row;
  final Color color;
  final TextDirection direction;
  final bool divider;
  final double? anchor;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    double x(int level) {
      final offset =
          taskBranchGutterWidth +
          (usesTouchTaskInteraction ? 22.0 : 17.0) +
          28 * level;
      return direction == TextDirection.ltr ? offset : size.width - offset;
    }

    for (var level = 0; level < row.displayDepth; level++) {
      final direct = level == row.displayDepth - 1;
      // The direct rail follows displayed rows at capped indentation; outer
      // rails still describe the siblings of the child at each actual level.
      final continues = direct
          ? row.continuesDisplayRail
          : row.ancestorContinuations.length > level + 1 &&
                row.ancestorContinuations[level + 1];
      if (!direct && !continues) continue;
      canvas.drawLine(
        Offset(x(level), 0),
        Offset(
          x(level),
          divider || !direct || continues
              ? size.height
              : anchor ?? size.height / 2,
        ),
        paint,
      );
      if (direct && !divider) {
        canvas.drawLine(
          Offset(x(level), anchor ?? size.height / 2),
          Offset(
            x(level) +
                (direction == TextDirection.ltr
                    ? TaskRowGeometry.branchArm
                    : -TaskRowGeometry.branchArm),
            anchor ?? size.height / 2,
          ),
          paint,
        );
      }
    }
    if (!divider && row.hasVisibleChildren && row.expanded && row.depth < 2) {
      canvas.drawLine(
        Offset(x(row.displayDepth), (anchor ?? size.height / 2) + 12),
        Offset(x(row.displayDepth), size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BranchPainter old) =>
      old.row != row ||
      old.color != color ||
      old.direction != direction ||
      old.anchor != anchor ||
      old.divider != divider;
}

/// Paint contiguous row segments instead of replacing a lazy list with columns.
class TaskBranchSurface extends StatelessWidget {
  const TaskBranchSurface({
    required this.row,
    required this.child,
    this.separator = false,
    super.key,
  });
  final VisibleTaskRow row;
  final Widget child;
  final bool separator;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _BranchSurfacePainter(
      start: !separator && row.startsGroup,
      end: !separator && row.endsGroup,
      rtl: Directionality.of(context) == TextDirection.rtl,
      fill: context.appColors.surface,
      border: context.appColors.border,
    ),
    child: child,
  );
}

class _BranchSurfacePainter extends CustomPainter {
  const _BranchSurfacePainter({
    required this.start,
    required this.end,
    required this.rtl,
    required this.fill,
    required this.border,
  });
  final bool start, end, rtl;
  final Color fill, border;

  @override
  void paint(Canvas canvas, Size size) {
    final left = (rtl ? 0 : taskBranchGutterWidth) + .5;
    final right = size.width - (rtl ? taskBranchGutterWidth : 0) - .5;
    final top = start ? .5 : 0.0;
    final bottom = size.height - (end ? .5 : 0.0);
    final rect = RRect.fromRectAndCorners(
      Rect.fromLTRB(left, top, right, bottom),
      topLeft: Radius.circular(start ? 14 : 0),
      topRight: Radius.circular(start ? 14 : 0),
      bottomLeft: Radius.circular(end ? 14 : 0),
      bottomRight: Radius.circular(end ? 14 : 0),
    );
    canvas.drawRRect(rect, Paint()..color = fill);
    final path = Path()..moveTo(left, start ? 14 : 0);
    if (start) {
      path.quadraticBezierTo(left, top, left + 14, top);
      path.lineTo(right - 14, top);
      path.quadraticBezierTo(right, top, right, 14);
    } else {
      path.moveTo(right, 0);
    }
    path.lineTo(right, end ? bottom - 14 : bottom);
    if (end) {
      path.quadraticBezierTo(right, bottom, right - 14, bottom);
      path.lineTo(left + 14, bottom);
      path.quadraticBezierTo(left, bottom, left, bottom - 14);
    } else {
      path.moveTo(left, bottom);
    }
    path.lineTo(left, start ? 14 : 0);
    canvas.drawPath(
      path,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _BranchSurfacePainter old) =>
      start != old.start ||
      end != old.end ||
      rtl != old.rtl ||
      fill != old.fill ||
      border != old.border;
}
