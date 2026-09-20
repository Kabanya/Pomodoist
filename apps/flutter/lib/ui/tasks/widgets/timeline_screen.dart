import 'package:pomodoist/ui/tasks/widgets/project_localizations.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart'
    show LucideIcons, ShadButton, ShadIconButton, ShadOption, ShadSelect;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/routing/task_detail_navigation.dart';
import 'package:pomodoist/ui/core/themes/app_motion.dart';
import 'package:pomodoist/ui/core/localization/formatters.dart';
import 'package:pomodoist/ui/tasks/view_models/timeline_view_model.dart';
import 'package:pomodoist/domain/models/settings/task_preferences.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/core/widgets/action_feedback.dart';
import 'package:pomodoist/ui/core/widgets/app_date_time_picker.dart';
import 'package:pomodoist/domain/models/tasks/project_colors.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/ui/tasks/widgets/task_completion_feedback.dart';
import 'package:pomodoist/ui/tasks/view_models/timeline_day_data.dart';
import 'package:pomodoist/ui/tasks/view_models/timeline_project_layout.dart';
import 'package:pomodoist/ui/tasks/widgets/project_color_picker.dart';
import 'package:pomodoist/ui/tasks/widgets/task_motion.dart';

part 'timeline_controls.dart';
part 'timeline_day.dart';
part 'timeline_grid.dart';
part 'timeline_project_header.dart';
part 'timeline_blocks.dart';
part 'timeline_helpers.dart';

class TimelineScreen extends StatelessWidget {
  const TimelineScreen({this.selectedDate, super.key});
  final DateTime? selectedDate;
  @override
  Widget build(BuildContext context) => ProviderScope(
    overrides: [timelineViewModelProvider.overrideWith(TimelineViewModel.new)],
    child: _TimelineScreen(selectedDate: selectedDate),
  );
}

class _TimelineScreen extends ConsumerWidget {
  const _TimelineScreen({this.selectedDate});

  final DateTime? selectedDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final viewState = ref.watch(timelineViewModelProvider);
    final today = timelineDateOnly(viewState.now);
    final day = timelineDateOnly(selectedDate ?? today);
    final tasks = viewState.tasks;
    final projects = viewState.projects;
    final visibleHours = viewState.visibleHours;

    return TaskMotionScope(
      key: ValueKey(day),
      builder: (context, motion) => SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.navTimeline,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.timelineSubtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _TimelineHeader(day: day, today: today),
                    const SizedBox(height: 12),
                    _VisibleHoursControls(visibleHours: visibleHours),
                  ],
                ),
              ),
            ),
            tasks.when(
              data: (items) {
                return projects.when(
                  data: (projectItems) => SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                    sliver: SliverToBoxAdapter(
                      child: _TimelineDay(
                        day: day,
                        presentation: ref.watch(
                          timelineDayPresentationProvider((
                            day: day,
                            retained: motion.retainedTasks,
                          )),
                        ),
                        visibleHours: visibleHours,
                      ),
                    ),
                  ),
                  loading: () => const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (error, stackTrace) => SliverFillRemaining(
                    child: Center(child: Text(l10n.projectsUnavailable(error))),
                  ),
                );
              },
              loading: () => const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, stackTrace) => SliverFillRemaining(
                child: Center(child: Text(l10n.failedToLoadTasks(error))),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
