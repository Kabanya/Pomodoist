import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_l10n.dart';
import '../../../app/providers.dart';
import '../../../app/widgets/action_feedback.dart';
import '../domain/task_models.dart';
import 'widgets/task_motion.dart';

const taskCompletionUndoFeedbackDuration = Duration(seconds: 7);

Future<bool> completeTaskWithUndoFeedback(
  BuildContext context,
  WidgetRef ref,
  String taskId,
) async {
  final taskRepository = ref.read(taskRepositoryProvider);
  final motion = TaskMotionScope.maybeOf(context);
  try {
    await taskRepository.completeTask(taskId);
  } catch (_) {
    if (context.mounted) {
      showActionFeedback(
        context,
        message: context.l10n.taskActionFailedCount(1),
        icon: Icons.error_outline,
        sound: ActionFeedbackSound.none,
        haptic: AppHapticCue.none,
      );
    }
    return false;
  }
  TaskItem? completed;
  try {
    completed = await taskRepository.watchTask(taskId).first;
  } catch (_) {
    // The repository write already succeeded; motion is best-effort.
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
    icon: Icons.check_circle_outline,
    duration: taskCompletionUndoFeedbackDuration,
    showCloseIcon: true,
    compact: true,
    action: SnackBarAction(
      label: l10n.commonUndo,
      onPressed: () => unawaited(() async {
        try {
          await taskRepository.uncompleteTask(taskId);
        } catch (_) {
          if (context.mounted) {
            showActionFeedback(
              context,
              message: context.l10n.taskActionFailedCount(1),
              icon: Icons.error_outline,
              sound: ActionFeedbackSound.none,
              haptic: AppHapticCue.none,
            );
          }
          return;
        }
        TaskItem? reopened;
        try {
          reopened = await taskRepository.watchTask(taskId).first;
        } catch (_) {
          // The repository write already succeeded; motion is best-effort.
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
