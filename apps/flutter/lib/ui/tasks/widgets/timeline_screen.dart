import 'package:pomodoist/ui/core/widgets/shortcut_hints.dart';
import 'package:pomodoist/ui/tasks/widgets/task_branch_widgets.dart';
import 'package:pomodoist/ui/tasks/widgets/project_localizations.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:shadcn_ui/shadcn_ui.dart'
    show
        LucideIcons,
        ShadAnchorAuto,
        ShadButton,
        ShadIconButton,
        ShadOption,
        ShadPopover,
        ShadPopoverController,
        ShadSelect;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/widgets/compact_shell_layout.dart';
import 'package:pomodoist/routing/task_detail_navigation.dart';
import 'package:pomodoist/ui/core/themes/app_motion.dart';
import 'package:pomodoist/ui/tasks/view_models/timeline_view_model.dart';
import 'package:pomodoist/domain/models/settings/task_preferences.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/core/widgets/action_feedback.dart';
import 'package:pomodoist/ui/core/widgets/app_date_time_picker.dart';
import 'package:pomodoist/ui/core/widgets/app_action_menu.dart'
    show actionMenuPlacement;
import 'package:pomodoist/ui/core/widgets/task_details_host.dart'
    show DetailsPanelViewport;
import 'package:pomodoist/ui/tasks/widgets/quick_add_dialog.dart'
    show showQuickAddDialog;
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
  Widget build(BuildContext context) =>
      _TimelineScreen(selectedDate: selectedDate);
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final layoutWidth =
            DetailsPanelViewport.maybeOf(
              context,
            )?.backgroundLayoutWidth(constraints.maxWidth) ??
            constraints.maxWidth;
        final compact =
            MediaQuery.sizeOf(context).width < 820 || layoutWidth < 560;
        final padding = compact ? 16.0 : 28.0;
        return TaskMotionScope(
          key: ValueKey(day),
          builder: (context, motion) {
            final presentation = tasks.hasValue && projects.hasValue
                ? ref.watch(
                    timelineDayPresentationProvider((
                      day: day,
                      retained: motion.retainedTasks,
                    )),
                  )
                : null;
            return SafeArea(
              bottom: false,
              child: CustomScrollView(
                key: const Key('timeline-page-scroll'),
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      padding,
                      compact ? 24 : 40,
                      padding,
                      24,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!CompactShellHeading.isShown(context)) ...[
                            Text(
                              l10n.navTimeline,
                              style: Theme.of(context).textTheme.headlineLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            SizedBox(height: compact ? 24 : 32),
                          ],
                          _TimelineHeader(
                            day: day,
                            today: today,
                            compact: compact,
                            presentation: presentation,
                          ),
                        ],
                      ),
                    ),
                  ),
                  tasks.when(
                    data: (_) => projects.when(
                      data: (_) => SliverPadding(
                        padding: EdgeInsets.fromLTRB(padding, 0, padding, 32),
                        sliver: SliverToBoxAdapter(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _TimelineDay(
                                day: day,
                                presentation: presentation!,
                                visibleHours: visibleHours,
                                compact: compact,
                              ),
                              if (!compact) ...[
                                const SizedBox(height: 40),
                                Align(
                                  alignment: AlignmentDirectional.centerEnd,
                                  child: ShadButton(
                                    key: const Key('timeline-add-task'),
                                    onPressed: () => unawaited(
                                      showQuickAddDialog(
                                        context,
                                        defaultDate: day,
                                      ),
                                    ),
                                    height: 48,
                                    leading: const Icon(LucideIcons.plus),
                                    child: Text(l10n.addTask),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      loading: () => const SliverFillRemaining(
                        child: Center(child: CircularProgressIndicator()),
                      ),
                      error: (error, _) => SliverFillRemaining(
                        child: Center(
                          child: Text(l10n.projectsUnavailable(error)),
                        ),
                      ),
                    ),
                    loading: () => const SliverFillRemaining(
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (error, _) => SliverFillRemaining(
                      child: Center(child: Text(l10n.failedToLoadTasks(error))),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
