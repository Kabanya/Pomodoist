import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons;

import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';

class SharedProjectBadge extends StatelessWidget {
  const SharedProjectBadge({required this.project, this.size = 14, super.key});

  final ProjectItem project;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scopeId = project.scopeId;
    if (scopeId == null) return const SizedBox.shrink();
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
