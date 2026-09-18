import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons, ShadButton;

import '../../../app/config/app_l10n.dart';
import '../../../app/config/providers.dart';
import '../domain/task_models.dart';
import 'widgets/label_icon.dart';
import 'widgets/task_list_view.dart';
import 'widgets/task_view_state.dart';

class LabelScreen extends ConsumerWidget {
  const LabelScreen({required this.labelId, super.key});

  final String labelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final labels = ref.watch(labelsProvider);
    return labels.when(
      data: (items) {
        LabelItem? label;
        for (final item in items) {
          if (item.id == labelId) {
            label = item;
            break;
          }
        }
        if (label == null) {
          return Center(
            child: TaskViewState(
              icon: LucideIcons.tag,
              title: context.l10n.labelNotFound,
              actions: ShadButton.secondary(
                onPressed: () => context.go('/projects?tab=labels'),
                child: Text(context.l10n.labelsTitle),
              ),
            ),
          );
        }
        final current = label;
        return TaskListView(
          title: '@${current.name}',
          subtitle: context.l10n.labelTasksSubtitle,
          titleLeading: IconButton(
            tooltip: context.l10n.labelIcon,
            onPressed: () => editLabelIcon(context, ref, current),
            icon: Icon(labelIconData(current.icon)),
          ),
          query: TaskQuery(kind: TaskQueryKind.label, labelId: labelId),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: TaskViewState(
          icon: LucideIcons.circleAlert,
          title: context.l10n.failedToLoadLabels(error),
          actions: ShadButton.secondary(
            onPressed: () => ref.invalidate(labelsProvider),
            child: Text(context.l10n.commonRetry),
          ),
        ),
      ),
    );
  }
}
