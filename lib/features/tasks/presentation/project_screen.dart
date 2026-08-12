import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_l10n.dart';
import '../../../app/providers.dart';
import '../domain/task_models.dart';
import 'widgets/task_list_view.dart';

class ProjectScreen extends ConsumerWidget {
  const ProjectScreen({required this.projectId, super.key});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final projects = ref.watch(projectsProvider).value ?? const [];
    ProjectItem? project;
    for (final item in projects) {
      if (item.id == projectId) {
        project = item;
        break;
      }
    }
    return TaskListView(
      title: project?.name ?? l10n.projectFallbackTitle,
      subtitle: l10n.projectSubtitle,
      query: TaskQuery(kind: TaskQueryKind.project, projectId: projectId),
      quickAddProjectId: projectId,
    );
  }
}
