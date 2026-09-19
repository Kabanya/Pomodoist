import 'package:pomodoist/ui/tasks/widgets/project_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/tasks/view_models/project_view_model.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/ui/tasks/widgets/task_list_view.dart';

class ProjectScreen extends ConsumerWidget {
  const ProjectScreen({required this.projectId, super.key});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final project = ref.watch(projectViewModelProvider(projectId));
    return TaskListView(
      title: project?.displayName(context.l10n) ?? l10n.projectFallbackTitle,
      subtitle: l10n.projectSubtitle,
      query: TaskQuery(kind: TaskQueryKind.project, projectId: projectId),
      quickAddProjectId: projectId,
    );
  }
}
