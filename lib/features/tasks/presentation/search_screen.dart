import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_l10n.dart';
import '../../../app/providers.dart';
import '../domain/task_models.dart';
import 'widgets/task_list_item.dart';
import 'widgets/task_motion.dart';
import 'widgets/task_selection_region.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final trimmedQuery = _query.trim();
    final tasks = ref.watch(
      tasksByQueryProvider(
        TaskQuery(kind: TaskQueryKind.search, search: trimmedQuery),
      ),
    );
    final allOpenTasks = ref.watch(tasksByQueryProvider(const TaskQuery.all()));
    final completedTasks = ref.watch(
      tasksByQueryProvider(const TaskQuery.completed()),
    );
    final visibleItems = trimmedQuery.isEmpty
        ? const <TaskItem>[]
        : tasks.value ?? const <TaskItem>[];

    return SafeArea(
      bottom: false,
      child: TaskSelectionRegion(
        visibleTasks: visibleItems,
        scopeKey: trimmedQuery,
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
                    TextField(
                      controller: _controller,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: l10n.searchTasks,
                        prefixIcon: const Icon(Icons.search),
                      ),
                      onChanged: (value) => setState(() => _query = value),
                    ),
                  ],
                ),
              ),
            ),
            if (trimmedQuery.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text(
                    l10n.searchStartTyping,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              )
            else
              TaskMotionScope(
                key: ValueKey(trimmedQuery),
                builder: (context, motion) => tasks.when(
                  data: (items) {
                    final visibleById = <String, TaskItem>{
                      for (final task in motion.retainedTasks) task.id: task,
                      for (final task in items) task.id: task,
                    };
                    final visibleItems = visibleById.values.toList();
                    if (visibleItems.isEmpty) {
                      return SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Text(
                            l10n.searchNoMatches,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      );
                    }
                    final progressById = taskSubtaskProgressById([
                      ...?allOpenTasks.value,
                      ...?completedTasks.value,
                      ...visibleItems,
                    ]);
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
                        separatorBuilder: (context, index) => Divider(
                          height: 1,
                          indent: 38,
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                    );
                  },
                  loading: () => const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (error, stackTrace) => SliverFillRemaining(
                    child: Center(child: Text(l10n.failedToSearchTasks(error))),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
