import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons;

import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/ui/collaboration/view_models/shared_project_badge_view_model.dart';

class SharedProjectBadge extends ConsumerWidget {
  const SharedProjectBadge({required this.project, this.size = 14, super.key});

  final ProjectItem project;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scopeId = project.scopeId;
    if (scopeId == null) return const SizedBox.shrink();
    final state = ref.watch(sharedProjectBadgeViewModelProvider(scopeId));
    if (state.hasConflicts) {
      return Tooltip(
        message: context.l10n.collaborationConflicts,
        child: Icon(
          LucideIcons.triangleAlert,
          size: size,
          color: Theme.of(context).colorScheme.error,
        ),
      );
    }
    return Tooltip(
      message: context.l10n.collaborationSharedBadge,
      child: Icon(
        LucideIcons.users,
        size: size,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
