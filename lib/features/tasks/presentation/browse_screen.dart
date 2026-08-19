import 'dart:async';

import 'package:app_account/app_account.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/account_providers.dart';
import '../../../app/app_l10n.dart';
import '../../../app/formatters.dart';
import '../../../app/providers.dart';
import '../../../app/runtime_public_config.dart';
import '../../../core/sync/pomodoist_retention.dart';
import '../../billing/billing.dart';
import '../../settings/presentation/pomodoist_account_actions.dart';
import '../domain/task_models.dart';
import 'widgets/task_list_view.dart';

class BrowseScreen extends ConsumerStatefulWidget {
  const BrowseScreen({super.key});

  @override
  ConsumerState<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends ConsumerState<BrowseScreen> {
  final _projectController = TextEditingController();
  final _labelController = TextEditingController();

  @override
  void dispose() {
    _projectController.dispose();
    _labelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final projects = ref.watch(projectsProvider);
    final labels = ref.watch(labelsProvider);
    final summary = ref.watch(productivitySummaryProvider);
    final pending = ref.watch(pendingSyncCommandsProvider).value ?? const [];
    final accountOverview = ref.watch(accountOverviewProvider);
    final accountConfigured = ref.watch(accountConfiguredProvider);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            l10n.browseTitle,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 16),
          accountOverview.when(
            data: (overview) => accountConfigured
                ? AccountOverviewPanel(
                    overview: overview,
                    configured: true,
                    onRefresh: () => ref.invalidate(accountOverviewProvider),
                    actions: pomodoistAccountSignInActions(
                      context: context,
                      account: ref.read(accountClientProvider),
                      redirectTo: pomodoistLoginRedirect,
                      config: ref.read(runtimePublicConfigProvider),
                      nativeCaptchaCallbacks: ref
                          .read(nativeLinkCoordinatorProvider)
                          ?.captchaCallbacks,
                    ),
                  )
                : _Panel(
                    title: l10n.unifiedAccount,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Semantics(
                          liveRegion: true,
                          child: Text(l10n.authServiceUnavailable),
                        ),
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: TextButton.icon(
                            onPressed: () => unawaited(
                              ref
                                  .read(accountBootstrapProvider.notifier)
                                  .retry(),
                            ),
                            icon: const Icon(Icons.refresh),
                            label: Text(l10n.commonRetry),
                          ),
                        ),
                      ],
                    ),
                  ),
            loading: () => const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: LinearProgressIndicator(),
              ),
            ),
            error: (error, _) => _Panel(
              title: l10n.unifiedAccount,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    liveRegion: true,
                    child: Text(pomodoistAccountFailureMessage(context, error)),
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton.icon(
                      onPressed: () => ref.invalidate(accountOverviewProvider),
                      icon: const Icon(Icons.refresh),
                      label: Text(l10n.commonRetry),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _Panel(
            title: l10n.productivityTitle,
            child: summary.when(
              data: (item) => Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _Metric(
                    label: l10n.completedTasks,
                    value: '${item.completedTasks}',
                  ),
                  _Metric(
                    label: l10n.focusIntervals,
                    value: '${item.completedFocusIntervals}',
                  ),
                  _Metric(
                    label: l10n.focusTime,
                    value: formatFocusTime(context, item.totalFocusSeconds),
                  ),
                  _Metric(label: l10n.openTasks, value: '${item.openTasks}'),
                ],
              ),
              loading: () => const LinearProgressIndicator(
                key: Key('browse-productivity-loading'),
              ),
              error: (error, _) => Column(
                key: const Key('browse-productivity-error'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l10n.failedToLoadReports(error)),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      key: const Key('browse-productivity-retry'),
                      onPressed: () =>
                          ref.invalidate(productivitySummaryProvider),
                      icon: const Icon(Icons.refresh),
                      label: Text(l10n.commonRetry),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              key: const Key('browse-completed-tasks'),
              leading: const Icon(Icons.task_alt_outlined),
              title: Text(l10n.completedTasks),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go('/browse/completed'),
            ),
          ),
          const SizedBox(height: 16),
          _Panel(
            title: l10n.navProjects,
            trailing: _InlineCreate(
              controller: _projectController,
              hint: l10n.newProject,
              onSubmit: () async {
                final name = _projectController.text.trim();
                if (name.isEmpty) {
                  return;
                }
                await ref.read(projectRepositoryProvider).createProject(name);
                _projectController.clear();
              },
            ),
            child: projects.when(
              data: (items) => Column(
                children: [
                  for (final project in items)
                    ListTile(
                      leading: const Icon(Icons.folder_outlined),
                      title: Text(project.name),
                      subtitle: Text(project.viewStyle),
                      onTap: () => context.go('/project/${project.id}'),
                    ),
                ],
              ),
              loading: () => const LinearProgressIndicator(),
              error: (error, stackTrace) =>
                  Text(l10n.failedToLoadProjects(error)),
            ),
          ),
          const SizedBox(height: 16),
          _Panel(
            title: l10n.labelsTitle,
            trailing: _InlineCreate(
              controller: _labelController,
              hint: l10n.newLabel,
              onSubmit: () async {
                final name = _labelController.text.trim();
                if (name.isEmpty) {
                  return;
                }
                await ref.read(labelRepositoryProvider).createLabel(name);
                _labelController.clear();
              },
            ),
            child: labels.when(
              data: (items) => Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final label in items)
                    Chip(
                      avatar: const Icon(Icons.label_outline, size: 18),
                      label: Text('@${label.name}'),
                    ),
                ],
              ),
              loading: () => const LinearProgressIndicator(),
              error: (error, stackTrace) =>
                  Text(l10n.failedToLoadLabels(error)),
            ),
          ),
          const SizedBox(height: 16),
          _Panel(
            title: l10n.syncReadyQueue,
            child: Text(l10n.pendingLocalCommands(pending.length)),
          ),
        ],
      ),
    );
  }
}

class CompletedTasksScreen extends ConsumerWidget {
  const CompletedTasksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountOverview = ref.watch(accountOverviewProvider);
    final billing = ref.watch(billingControllerProvider);
    final completedTaskCutoff = accountOverview.hasValue && !billing.loading
        ? pomodoistTaskHistoryCutoff(
            accountOverview.value,
            hasLocalPaidEntitlement: billing.hasActiveEntitlement,
          )
        : null;
    return TaskListView(
      title: context.l10n.completedTasks,
      query: const TaskQuery.completed(),
      showQuickAdd: false,
      taskFilter: completedTaskCutoff == null
          ? null
          : (task) => !(task.completedAt ?? task.updatedAt).toUtc().isBefore(
              completedTaskCutoff,
            ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: Theme.of(context).textTheme.headlineSmall),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _InlineCreate extends StatelessWidget {
  const _InlineCreate({
    required this.controller,
    required this.hint,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final String hint;
  final Future<void> Function() onSubmit;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              decoration: InputDecoration(hintText: hint),
              onSubmitted: (_) => onSubmit(),
            ),
          ),
          IconButton(
            tooltip: context.l10n.commonCreate,
            onPressed: onSubmit,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}
