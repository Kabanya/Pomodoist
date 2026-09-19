import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons, ShadButton;

import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/localization/formatters.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/domain/models/collaboration/public_project.dart';
import 'package:pomodoist/ui/collaboration/view_models/public_project_view_model.dart';

const _contentMaxWidth = 1120.0;
const _indentStep = 12.0;
const _maxIndentSteps = 4;

/// Anonymous read-only view of a project shared through a public link.
///
/// Visitors have no account, so the projection is requested through the
/// bootstrap client, which the collaboration function accepts without a
/// session for the `publicRead` action.
class PublicProjectScreen extends ConsumerStatefulWidget {
  const PublicProjectScreen({required this.token, super.key});

  final String token;

  @override
  ConsumerState<PublicProjectScreen> createState() =>
      PublicProjectScreenState();
}

class PublicProjectScreenState extends ConsumerState<PublicProjectScreen> {
  late PublicProjectState _state;

  void _load() =>
      ref.read(publicProjectViewModelProvider(widget.token).notifier).reload();

  @override
  Widget build(BuildContext context) {
    _state = ref.watch(publicProjectViewModelProvider(widget.token));
    return Scaffold(
      backgroundColor: context.appColors.canvas,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: _body(context)),
            _footer(context),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_state.loading) {
      return const Center(
        child: CircularProgressIndicator(key: Key('public-project-loading')),
      );
    }
    final failure = _state.failure;
    if (failure != null) return _failureState(context, failure);
    final project = _state.project;
    if (project == null || project.isEmpty) return _emptyState(context);
    return _content(context, project);
  }

  Widget _failureState(BuildContext context, PublicProjectFailure failure) {
    final l10n = context.l10n;
    final unavailable = failure == PublicProjectFailure.unavailable;
    return _CenteredMessage(
      key: const Key('public-project-failure'),
      icon: unavailable ? LucideIcons.lock : LucideIcons.triangleAlert,
      message: unavailable
          ? l10n.collaborationPublicUnavailable
          : l10n.collaborationError,
      action: unavailable
          ? null
          : ShadButton.ghost(
              key: const Key('public-project-retry'),
              onPressed: _load,
              leading: const Icon(LucideIcons.refreshCw, size: 16),
              child: Text(l10n.commonRetry),
            ),
    );
  }

  Widget _emptyState(BuildContext context) => _CenteredMessage(
    key: const Key('public-project-empty'),
    icon: LucideIcons.inbox,
    message: context.l10n.collaborationPublicEmpty,
  );

  Widget _content(BuildContext context, PublicProject project) {
    final single = project.singleProject;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(context, single),
                const SizedBox(height: 24),
                for (final section in project.sections)
                  _section(context, section, showName: section != single),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _header(BuildContext context, PublicProjectSection? single) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: context.appColors.accentTint,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  LucideIcons.lock,
                  size: 12,
                  color: context.appColors.accent,
                ),
                const SizedBox(width: 6),
                Text(
                  l10n.collaborationSharedBadge,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: context.appColors.accent,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          l10n.collaborationPublicNotice,
          key: const Key('public-project-notice'),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: context.appColors.secondaryText,
          ),
        ),
        if (single != null) ...[
          const SizedBox(height: 12),
          Text(
            single.title(l10n.collaborationSharedBadge),
            key: const Key('public-project-title'),
            style: theme.textTheme.headlineMedium,
          ),
        ],
      ],
    );
  }

  Widget _section(
    BuildContext context,
    PublicProjectSection section, {
    required bool showName,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showName) ...[
            Text(
              section.title(context.l10n.collaborationSharedBadge),
              key: Key('public-project-section-${section.id}'),
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
          ],
          if (section.tasks.isNotEmpty) ...[
            Text(
              context.l10n.collaborationPublicTasks,
              key: Key('public-project-tasks-${section.id}'),
              style: theme.textTheme.titleMedium?.copyWith(
                color: context.appColors.secondaryText,
              ),
            ),
            const SizedBox(height: 4),
            for (final node in section.tasks) _task(context, node),
          ],
        ],
      ),
    );
  }

  Widget _task(BuildContext context, PublicTaskNode node) {
    final theme = Theme.of(context);
    final task = node.task;
    final finished = task.isCompleted;
    final indent = _indentStep * node.depth.clamp(0, _maxIndentSteps);
    return Padding(
      key: Key('public-project-task-${task.id}'),
      padding: EdgeInsets.only(left: indent, top: 6, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  finished ? LucideIcons.circleCheck : LucideIcons.circle,
                  size: 16,
                  color: finished
                      ? context.appColors.success
                      : context.appColors.mutedText,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.content,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: finished
                            ? context.appColors.mutedText
                            : context.appColors.primaryText,
                        decoration: finished
                            ? TextDecoration.lineThrough
                            : null,
                        decorationColor: context.appColors.mutedText,
                      ),
                    ),
                    if (finished)
                      Text(
                        context.l10n.taskTimeStatusCompleted,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: context.appColors.mutedText,
                        ),
                      ),
                    ..._metadata(context, task),
                  ],
                ),
              ),
            ],
          ),
          if (node.comments.isNotEmpty) _comments(context, node.comments),
        ],
      ),
    );
  }

  List<Widget> _metadata(BuildContext context, PublicTask task) {
    final schedule = task.schedule;
    final labels = <(IconData, String)>[
      if (schedule != null)
        (LucideIcons.calendar, formatTaskSchedule(context, schedule)),
      if (task.deadline case final deadline?)
        (LucideIcons.calendarClock, formatLocalDate(context, deadline)),
      if (task.creatorName case final creator?)
        (LucideIcons.userRound, creator),
      if (task.assigneeNames.isNotEmpty)
        (LucideIcons.users, task.assigneeNames.join(', ')),
    ];
    if (labels.isEmpty) return const [];
    final theme = Theme.of(context);
    return [
      const SizedBox(height: 4),
      Wrap(
        spacing: 12,
        runSpacing: 4,
        children: [
          for (final (icon, label) in labels)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: context.appColors.mutedText),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: context.appColors.secondaryText,
                  ),
                ),
              ],
            ),
        ],
      ),
    ];
  }

  Widget _comments(BuildContext context, List<PublicComment> comments) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 26, top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.collaborationComments,
            style: theme.textTheme.labelLarge?.copyWith(
              color: context.appColors.secondaryText,
            ),
          ),
          const SizedBox(height: 4),
          for (final comment in comments)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Icon(
                      LucideIcons.messageSquare,
                      size: 14,
                      color: context.appColors.mutedText,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(comment.body, style: theme.textTheme.bodyMedium),
                        if (comment.author case final author?)
                          Text(
                            author,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: context.appColors.secondaryText,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _footer(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.appColors.surface,
        border: Border(top: BorderSide(color: context.appColors.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ShadButton(
                  key: const Key('public-project-open'),
                  onPressed: () => context.go('/today'),
                  trailing: const Icon(LucideIcons.arrowRight, size: 16),
                  child: Text(context.l10n.collaborationPublicOpen),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shared layout for the loading-free placeholder states.
class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.message,
    this.action,
    super.key,
  });

  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Semantics(
          liveRegion: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 28, color: context.appColors.mutedText),
              const SizedBox(height: 12),
              Text(
                message,
                key: const Key('public-project-message'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: context.appColors.secondaryText,
                ),
              ),
              if (action case final actionWidget?) ...[
                const SizedBox(height: 8),
                actionWidget,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
