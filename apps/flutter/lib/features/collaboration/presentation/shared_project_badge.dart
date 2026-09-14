import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons;

import '../../../app/app_l10n.dart';
import '../../tasks/domain/task_models.dart';
import 'collaboration_providers.dart';

class SharedProjectBadge extends ConsumerWidget {
  const SharedProjectBadge({required this.project, this.size = 14, super.key});

  final ProjectItem project;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scopeId = project.scopeId;
    if (scopeId == null) return const SizedBox.shrink();
    final conflicts =
        ref.watch(scopeConflictsProvider(scopeId)).value ?? const [];
    if (conflicts.isNotEmpty) {
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
