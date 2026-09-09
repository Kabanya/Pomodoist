import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart'
    show LucideIcons, ShadButton, ShadInput;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/account_providers.dart';
import '../../../app/app_l10n.dart';
import '../../../app/providers.dart';
import '../../../app/widgets/adaptive_shell.dart' show showQuickAddDialog;
import '../../../core/sync/pomodoist_retention.dart';
import '../../billing/billing.dart';
import '../domain/task_models.dart';
import 'task_search.dart';
import 'widgets/task_list_item.dart';
import 'widgets/task_motion.dart';
import 'widgets/task_selection_region.dart';
import 'widgets/task_view_state.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.initialQuery = ''});

  final String initialQuery;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final _controller = TextEditingController(text: widget.initialQuery);
  String? _projectId;
  TaskSearchStatus _status = TaskSearchStatus.open;

  @override
  void didUpdateWidget(covariant SearchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialQuery != widget.initialQuery) {
      _controller.text = widget.initialQuery;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _clearFilters() => setState(() {
    _projectId = null;
    _status = TaskSearchStatus.all;
  });

  void _retry() {
    ref.invalidate(tasksByQueryProvider(const TaskQuery.all()));
    ref.invalidate(tasksByQueryProvider(const TaskQuery.completed()));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final query = _controller.text.trim();
    final open = ref.watch(tasksByQueryProvider(const TaskQuery.all()));
    final completed = ref.watch(
      tasksByQueryProvider(const TaskQuery.completed()),
    );
    final projects =
        (ref.watch(projectsProvider).value ?? const <ProjectItem>[])
            .where((project) => !project.isDeleted)
            .toList();
    final projectId = projects.any((project) => project.id == _projectId)
        ? _projectId
        : null;
    final overview = ref.watch(accountOverviewProvider);
    final billing = ref.watch(billingControllerProvider);
    final cutoff = overview.hasValue && !billing.loading
        ? pomodoistTaskHistoryCutoff(
            overview.value,
            hasLocalPaidEntitlement: billing.hasActiveEntitlement,
          )
        : null;
    final allTasks = <String, TaskItem>{
      for (final task in open.value ?? const <TaskItem>[]) task.id: task,
      for (final task in completed.value ?? const <TaskItem>[]) task.id: task,
    }.values.toList();
    final items = filterTaskSearch(
      allTasks,
      query: query,
      projectId: projectId,
      status: _status,
      completedTaskCutoff: cutoff,
    );
    final sources = [
      if (_status != TaskSearchStatus.completed) open,
      if (_status != TaskSearchStatus.open) completed,
    ];
    final loading = sources.any((source) => source.isLoading);
    final hasError = sources.any((source) => source.hasError);
    final progressById = taskSubtaskProgressById(allTasks);
    final scope = (query, projectId, _status);
    final retry = ShadButton.outline(
      onPressed: _retry,
      child: Text(l10n.commonRetry),
    );
    final statusLabels = {
      TaskSearchStatus.open: l10n.searchStatusOpen,
      TaskSearchStatus.completed: l10n.searchStatusCompleted,
      TaskSearchStatus.all: l10n.searchStatusAll,
    };

    return SafeArea(
      bottom: false,
      child: TaskSelectionRegion(
        visibleTasks: items,
        scopeKey: scope,
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.navSearch,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 16),
                    ShadInput(
                      controller: _controller,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      onChanged: (_) => setState(() {}),
                      placeholder: Text(l10n.searchTasks),
                      leading: const Icon(LucideIcons.search),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 240),
                          child: DropdownButton<String>(
                            isExpanded: true,
                            value: projectId,
                            hint: Text(l10n.searchAllProjects),
                            items: [
                              DropdownMenuItem(
                                value: null,
                                child: Text(l10n.searchAllProjects),
                              ),
                              for (final project in projects)
                                DropdownMenuItem(
                                  value: project.id,
                                  child: Text(
                                    project.name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (value) =>
                                setState(() => _projectId = value),
                          ),
                        ),
                        DropdownButton<TaskSearchStatus>(
                          value: _status,
                          items: [
                            for (final entry in statusLabels.entries)
                              DropdownMenuItem(
                                value: entry.key,
                                child: Text(entry.value),
                              ),
                          ],
                          onChanged: (value) {
                            if (value != null) setState(() => _status = value);
                          },
                        ),
                        ShadButton.ghost(
                          onPressed: _clearFilters,
                          child: Text(l10n.searchClearFilters),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (query.isNotEmpty && loading && items.isNotEmpty)
              const SliverToBoxAdapter(child: LinearProgressIndicator()),
            if (query.isNotEmpty && hasError && items.isNotEmpty)
              SliverToBoxAdapter(
                child: TaskViewState(
                  icon: LucideIcons.circleAlert,
                  title: l10n.taskListLoadError,
                  actions: retry,
                ),
              ),
            if (query.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: TaskViewState(
                  icon: LucideIcons.search,
                  title: l10n.searchStartTyping,
                  description: l10n.searchEmptyDescription,
                ),
              )
            else
              TaskMotionScope(
                key: ValueKey(scope),
                builder: (context, motion) {
                  final visibleItems = <String, TaskItem>{
                    for (final task in motion.retainedTasks) task.id: task,
                    for (final task in items) task.id: task,
                  }.values.toList();
                  if (visibleItems.isEmpty) {
                    if (hasError) {
                      return SliverFillRemaining(
                        hasScrollBody: false,
                        child: TaskViewState(
                          icon: LucideIcons.circleAlert,
                          title: l10n.taskListLoadError,
                          actions: retry,
                        ),
                      );
                    }
                    if (loading) {
                      return const SliverFillRemaining(
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    return SliverFillRemaining(
                      hasScrollBody: false,
                      child: TaskViewState(
                        icon: LucideIcons.search,
                        title: l10n.searchNoMatches,
                        description: l10n.searchNoMatchesDescription,
                        actions: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            ShadButton.outline(
                              onPressed: _clearFilters,
                              child: Text(l10n.searchClearFilters),
                            ),
                            ShadButton(
                              onPressed: () => showQuickAddDialog(
                                context,
                                initialText: _controller.text,
                                projectId: projectId,
                              ),
                              child: Text(l10n.searchCreateTask),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  return SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    sliver: SliverList.separated(
                      itemCount: visibleItems.length,
                      itemBuilder: (context, index) {
                        final task = visibleItems[index];
                        return TaskListItem(
                          task: task,
                          subtaskProgress: progressById[task.id],
                        );
                      },
                      separatorBuilder: (context, index) =>
                          const TaskListDivider(),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
