import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons, ShadButton;

import '../../../app/config/account_providers.dart';
import '../../../app/config/app_l10n.dart';
import '../../../app/config/formatters.dart';
import '../../../app/theme/app_theme.dart';
import '../../tasks/domain/task_models.dart';
import '../data/collaboration_api.dart';
import '../domain/collaboration_models.dart';

/// Public share tokens are 64 hexadecimal characters.
final _publicToken = RegExp(r'^[0-9a-fA-F]{64}$');

/// The server reports a revoked or unknown public link with this code.
const _revokedLinkCode = '42501';

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
      _PublicProjectScreenState();
}

class _PublicProjectScreenState extends ConsumerState<PublicProjectScreen> {
  _PublicProject? _project;
  _PublicFailure? _failure;
  var _loading = true;
  var _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(PublicProjectScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.token != widget.token) {
      _load();
    }
  }

  Future<void> _load() async {
    final token = widget.token.trim();
    if (!_publicToken.hasMatch(token)) {
      _showFailure(_PublicFailure.unavailable);
      return;
    }
    final generation = ++_generation;
    _showLoading();
    try {
      final account = ref.read(accountClientProvider);
      if (account == null) {
        throw const CollaborationException('unavailable');
      }
      final response = await CollaborationApi.account(
        account,
      ).call('publicRead', {'token': token});
      if (!mounted || generation != _generation) return;
      _showProject(_PublicProject.fromResponse(response));
    } catch (error) {
      if (!mounted || generation != _generation) return;
      _showFailure(
        error is CollaborationException && error.code == _revokedLinkCode
            ? _PublicFailure.unavailable
            : _PublicFailure.retryable,
      );
    }
  }

  void _showLoading() {
    setState(() {
      _loading = true;
      _project = null;
      _failure = null;
    });
  }

  void _showProject(_PublicProject project) {
    setState(() {
      _loading = false;
      _project = project;
      _failure = null;
    });
  }

  void _showFailure(_PublicFailure failure) {
    setState(() {
      _loading = false;
      _project = null;
      _failure = failure;
    });
  }

  @override
  Widget build(BuildContext context) {
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
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(key: Key('public-project-loading')),
      );
    }
    final failure = _failure;
    if (failure != null) return _failureState(context, failure);
    final project = _project;
    if (project == null || project.isEmpty) return _emptyState(context);
    return _content(context, project);
  }

  Widget _failureState(BuildContext context, _PublicFailure failure) {
    final l10n = context.l10n;
    final unavailable = failure == _PublicFailure.unavailable;
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

  Widget _content(BuildContext context, _PublicProject project) {
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

  Widget _header(BuildContext context, _ProjectSection? single) {
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
    _ProjectSection section, {
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

  Widget _task(BuildContext context, _TaskNode node) {
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

  List<Widget> _metadata(BuildContext context, _PublicTask task) {
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

  Widget _comments(BuildContext context, List<_Comment> comments) {
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

enum _PublicFailure { unavailable, retryable }

class _PublicProject {
  _PublicProject(this.sections);

  final List<_ProjectSection> sections;

  bool get isEmpty => sections.isEmpty;

  /// The only section, when the link covers a single named project.
  _ProjectSection? get singleProject {
    final only = sections.length == 1 ? sections.single : null;
    return only == null || only.name == null ? null : only;
  }

  static _PublicProject fromResponse(Map<String, dynamic> response) {
    final commentsByTask = <String, List<_Comment>>{};
    for (final comment in collaborationMaps(response['comments'])) {
      final taskId = _text(comment['taskId']);
      final body = _text(comment['body']);
      if (taskId == null || body == null) continue;
      (commentsByTask[taskId] ??= []).add(
        _Comment(
          id: _text(comment['id']) ?? taskId,
          body: body,
          author: _text(comment['creatorName']),
          createdAt: _text(comment['createdAt']),
        ),
      );
    }
    for (final comments in commentsByTask.values) {
      comments.sort((a, b) => _compareText(a.createdAt, b.createdAt));
    }

    final tasksByProject = <String, List<Map<String, dynamic>>>{};
    for (final task in collaborationMaps(response['tasks'])) {
      if (_text(task['id']) == null || _text(task['content']) == null) continue;
      (tasksByProject[_text(task['projectId']) ?? ''] ??= []).add(task);
    }

    final sections = <_ProjectSection>[];
    final named = <String>{};
    for (final project in collaborationMaps(response['projects'])) {
      final id = _text(project['id']);
      if (id == null) continue;
      named.add(id);
      sections.add(
        _ProjectSection(
          id: id,
          name: _text(project['name']),
          tasks: _taskTree(tasksByProject[id] ?? const [], commentsByTask),
        ),
      );
    }
    // Tasks of a project the projection did not name stay visible.
    final ungrouped = <_TaskNode>[
      for (final entry in tasksByProject.entries)
        if (!named.contains(entry.key))
          ..._taskTree(entry.value, commentsByTask),
    ];
    if (ungrouped.isNotEmpty) {
      sections.add(_ProjectSection(id: 'shared', tasks: ungrouped));
    }
    return _PublicProject(sections);
  }

  static List<_TaskNode> _taskTree(
    List<Map<String, dynamic>> rows,
    Map<String, List<_Comment>> commentsByTask,
  ) {
    final ordered = [...rows]
      ..sort((a, b) {
        final byOrder = _compareText(a['orderKey'], b['orderKey']);
        return byOrder != 0
            ? byOrder
            : _compareText(a['createdAt'], b['createdAt']);
      });
    final tasks = [
      for (final row in ordered)
        _PublicTask(
          id: _text(row['id'])!,
          content: _text(row['content'])!,
          parentId: _text(row['parentId']),
          status: _text(row['status']),
          creatorName: _text(row['creatorName']),
          assigneeNames: _names(row['assigneeNames']),
          schedule: TaskSchedule.fromJsonString(_text(row['dueJson'])),
          deadline: _deadline(row['deadlineJson']),
        ),
    ];
    final byId = {for (final task in tasks) task.id: task};
    final childTasks = <String, List<_PublicTask>>{};
    final roots = <_PublicTask>[];
    for (final task in tasks) {
      final parentId = task.parentId;
      if (parentId == null ||
          parentId == task.id ||
          !byId.containsKey(parentId)) {
        roots.add(task);
      } else {
        (childTasks[parentId] ??= []).add(task);
      }
    }

    final nodes = <_TaskNode>[];
    final visited = <String>{};
    void walk(_PublicTask task, int depth) {
      // A cycle or a repeated parent must never repeat or drop a task.
      if (!visited.add(task.id)) return;
      nodes.add(
        _TaskNode(
          task: task,
          depth: depth,
          comments: commentsByTask[task.id] ?? const [],
        ),
      );
      for (final child in childTasks[task.id] ?? const <_PublicTask>[]) {
        walk(child, depth + 1);
      }
    }

    for (final root in roots) {
      walk(root, 0);
    }
    for (final task in tasks) {
      walk(task, 0);
    }
    return nodes;
  }
}

class _ProjectSection {
  _ProjectSection({required this.id, this.name, required this.tasks});

  final String id;
  final String? name;
  final List<_TaskNode> tasks;

  String title(String fallback) => name ?? fallback;
}

class _TaskNode {
  _TaskNode({required this.task, required this.depth, required this.comments});

  final _PublicTask task;
  final int depth;
  final List<_Comment> comments;
}

class _PublicTask {
  _PublicTask({
    required this.id,
    required this.content,
    this.parentId,
    this.status,
    this.creatorName,
    this.assigneeNames = const [],
    this.schedule,
    this.deadline,
  });

  final String id;
  final String content;
  final String? parentId;
  final String? status;
  final String? creatorName;
  final List<String> assigneeNames;
  final TaskSchedule? schedule;
  final DateTime? deadline;

  bool get isCompleted => status == 'completed';
}

class _Comment {
  _Comment({required this.id, required this.body, this.author, this.createdAt});

  final String id;
  final String body;
  final String? author;
  final String? createdAt;
}

String? _text(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

List<String> _names(Object? value) {
  if (value is! List) return const [];
  return [
    for (final item in value)
      if (item is String && item.trim().isNotEmpty) item.trim(),
  ];
}

int _compareText(Object? a, Object? b) {
  if (a is! String) return b is String ? 1 : 0;
  if (b is! String) return -1;
  return a.compareTo(b);
}

DateTime? _deadline(Object? json) {
  if (json is! String) return null;
  final Object? decoded;
  try {
    decoded = jsonDecode(json);
  } on FormatException {
    return null;
  }
  if (decoded is! Map) return null;
  final raw = decoded['date'];
  final parsed = raw is String ? DateTime.tryParse(raw) : null;
  return parsed == null
      ? null
      : DateTime(parsed.year, parsed.month, parsed.day);
}
