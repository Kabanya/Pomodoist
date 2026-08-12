import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_l10n.dart';
import '../../../app/providers.dart';
import '../../../app/widgets/action_feedback.dart';

const taskCompletionUndoFeedbackDuration = Duration(seconds: 7);

Future<void> completeTaskWithUndoFeedback(
  BuildContext context,
  WidgetRef ref,
  String taskId,
) async {
  final taskRepository = ref.read(taskRepositoryProvider);
  await taskRepository.completeTask(taskId);
  if (!context.mounted) {
    return;
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
      onPressed: () => unawaited(taskRepository.uncompleteTask(taskId)),
    ),
  );
}
