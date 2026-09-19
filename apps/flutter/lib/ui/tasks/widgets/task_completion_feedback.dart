import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons;

import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/widgets/action_feedback.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/ui/tasks/widgets/task_motion.dart';

const taskCompletionUndoFeedbackDuration = Duration(seconds: 7);

Future<bool> completeTaskWithUndoFeedback(
  BuildContext context, {
  required Future<TaskItem?> Function() complete,
  required Future<TaskItem?> Function() undo,
}) async {
  final motion = TaskMotionScope.maybeOf(context);
  TaskItem? completed;
  try {
    completed = await complete();
  } catch (_) {
    if (context.mounted) {
      showActionFeedback(
        context,
        message: context.l10n.taskActionFailedCount(1),
        icon: LucideIcons.circleAlert,
        sound: ActionFeedbackSound.none,
        haptic: AppHapticCue.none,
      );
    }
    return false;
  }
  if (!context.mounted) {
    return true;
  }
  if (completed != null) {
    motion?.completed([completed]);
  }
  final l10n = context.l10n;
  showActionFeedback(
    context,
    message: l10n.taskCompleted,
    icon: LucideIcons.circleCheck,
    duration: taskCompletionUndoFeedbackDuration,
    showCloseIcon: true,
    compact: true,
    action: SnackBarAction(
      label: l10n.commonUndo,
      onPressed: () => unawaited(() async {
        TaskItem? reopened;
        try {
          reopened = await undo();
        } catch (_) {
          if (context.mounted) {
            showActionFeedback(
              context,
              message: context.l10n.taskActionFailedCount(1),
              icon: LucideIcons.circleAlert,
              sound: ActionFeedbackSound.none,
              haptic: AppHapticCue.none,
            );
          }
          return;
        }
        if (reopened != null && context.mounted) {
          motion?.reopened([reopened]);
        }
        await playHaptic(AppHapticCue.light);
      }()),
    ),
  );
  return true;
}
