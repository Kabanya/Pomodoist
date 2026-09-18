import 'project_localizations.dart';
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

import '../../../app/config/app_l10n.dart';
import '../../../app/routing/task_detail_navigation.dart';
import '../../../app/theme/app_motion.dart';
import '../../../app/config/formatters.dart';
import '../../../app/config/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/action_feedback.dart';
import '../../../app/widgets/app_date_time_picker.dart';
import '../domain/project_colors.dart';
import '../domain/task_models.dart';
import 'task_completion_feedback.dart';
import 'timeline_project_layout.dart';
import 'widgets/project_color_picker.dart';
import 'widgets/task_motion.dart';

part 'timeline_controls.dart';
part 'timeline_day.dart';
part 'timeline_grid.dart';
part 'timeline_project_header.dart';
part 'timeline_blocks.dart';
part 'timeline_helpers.dart';

class TimelineScreen extends ConsumerWidget {
  const TimelineScreen({this.selectedDate, super.key});

  final DateTime? selectedDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final today = _dateOnly(ref.watch(clockProvider).now().toLocal());
    final day = _dateOnly(selectedDate ?? today);
    final tasks = ref.watch(tasksByQueryProvider(const TaskQuery.all()));
    final projects = ref.watch(projectsProvider);
    final visibleHours = ref.watch(timelineVisibleHoursProvider);

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
                final visibleById = {
                  for (final item in motion.retainedTasks) item.id: item,
                  for (final item in items) item.id: item,
                };
                return projects.when(
                  data: (projectItems) => SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                    sliver: SliverToBoxAdapter(
                      child: _TimelineDay(
                        day: day,
                        tasks: visibleById.values.toList(),
                        projects: projectItems,
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
