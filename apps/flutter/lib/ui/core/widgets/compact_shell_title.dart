import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/tasks/view_models/project_view_model.dart';
import 'package:pomodoist/ui/tasks/widgets/project_localizations.dart';

String? compactShellTitle(
  BuildContext context,
  WidgetRef ref,
  String location,
) {
  final l10n = context.l10n;
  return switch (Uri.parse(location).pathSegments) {
    ['today'] => l10n.navToday,
    ['upcoming'] => l10n.navUpcoming,
    ['inbox'] => l10n.navInbox,
    ['search'] => l10n.navSearch,
    ['habits'] => l10n.navHabits,
    ['priority-matrix'] => l10n.navPriorityMatrix,
    ['calendar'] => l10n.navCalendar,
    ['timeline'] => l10n.navTimeline,
    ['kanban'] => l10n.kanbanTitle,
    ['focus'] => l10n.focusTitle,
    ['blocking'] => l10n.blockingTitle,
    ['browse'] => l10n.browseTitle,
    ['browse', 'overdue'] => l10n.overdueTitle,
    ['browse', 'completed'] => l10n.completedTasks,
    ['projects'] => l10n.navProjects,
    ['project', final id] =>
      ref.watch(projectViewModelProvider(id))?.displayName(l10n) ??
          l10n.projectFallbackTitle,
    ['label', final id] => switch (ref
        .watch(labelViewModelProvider(id))
        .value) {
      final label? => '@${label.name}',
      null => l10n.labelsTitle,
    },
    ['reports'] => l10n.reportsTitle,
    ['reports', 'achievements'] => l10n.achievementsTitle,
    ['settings'] => l10n.settingsTitle,
    ['settings', 'shortcuts'] => l10n.settingsShortcutsTitle,
    ['integrations', 'google-calendar'] => l10n.googleCalendarTitle,
    _ => null,
  };
}
