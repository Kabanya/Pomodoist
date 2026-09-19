import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart'
    show LucideIcons, ShadButton, ShadDialog, ShadInput;

import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/domain/models/collaboration/collaboration_models.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/ui/collaboration/widgets/collaboration_copy.dart';
import 'package:pomodoist/ui/collaboration/view_models/task_collaboration_view_model.dart';

class TaskCollaborationSection extends ConsumerStatefulWidget {
  const TaskCollaborationSection({required this.task, super.key});

  final TaskItem task;

  @override
  ConsumerState<TaskCollaborationSection> createState() =>
      _TaskCollaborationSectionState();
}

class _TaskCollaborationSectionState
    extends ConsumerState<TaskCollaborationSection> {
  final _comment = TextEditingController();
  late TaskCollaborationState _state;
  TaskCollaborationQuery get _query =>
      (taskId: widget.task.id, scopeId: widget.task.scopeId);
  TaskCollaborationViewModel get _viewModel =>
      ref.read(taskCollaborationViewModelProvider(_query).notifier);

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _state = ref.watch(taskCollaborationViewModelProvider(_query));
    final scope = _state.scope;
    if (scope == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _assignees(context, scope),
        const SizedBox(height: 16),
        _comments(context, scope),
      ],
    );
  }

  Widget _assignees(BuildContext context, SharedScope scope) {
    final l10n = context.l10n;
    final names = [
      for (final id in widget.task.assigneeIds)
        collaborationMemberLabel(l10n, scope, id),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.collaborationAssignees,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (scope.canEdit)
              IconButton(
                key: const Key('task-assignees-edit'),
                tooltip: l10n.collaborationEditAssignees,
                onPressed: () => _editAssignees(scope),
                icon: const Icon(LucideIcons.userPlus, size: 18),
              ),
          ],
        ),
        if (names.isEmpty)
          Text(
            l10n.collaborationNoAssignees,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [for (final name in names) Chip(label: Text(name))],
          ),
      ],
    );
  }

  Widget _comments(BuildContext context, SharedScope scope) {
    final l10n = context.l10n;
    final comments = _state.comments;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.collaborationComments,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        for (final comment in comments) _commentTile(context, scope, comment),
        if (scope.canEdit) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: ShadInput(
                  key: const Key('task-comment-input'),
                  controller: _comment,
                  minLines: 1,
                  maxLines: 4,
                  placeholder: Text(l10n.collaborationCommentHint),
                ),
              ),
              const SizedBox(width: 8),
              ShadButton(
                key: const Key('task-comment-send'),
                onPressed: _sendComment,
                child: Text(l10n.collaborationCommentSend),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _commentTile(
    BuildContext context,
    SharedScope scope,
    Map<String, dynamic> comment,
  ) {
    final l10n = context.l10n;
    final body = comment['body'] as String? ?? '';
    final author = comment['createdBy'] as String? ?? '';
    final canDelete = _state.canDeleteComment(comment);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(body),
      subtitle: Text(collaborationMemberLabel(l10n, scope, author)),
      trailing: canDelete
          ? IconButton(
              key: Key('task-comment-delete-${comment['id']}'),
              tooltip: l10n.collaborationCommentDelete,
              onPressed: () =>
                  _deleteComment(scope.id, comment['id'] as String),
              icon: const Icon(LucideIcons.trash2, size: 18),
            )
          : null,
    );
  }

  Future<void> _sendComment() async {
    try {
      final sent = (await _viewModel.sendComment(_comment.text)).getOrThrow();
      if (mounted && sent) _comment.clear();
    } catch (error) {
      if (mounted) _snack(collaborationErrorMessage(context.l10n, error));
    }
  }

  Future<void> _deleteComment(String scopeId, String id) async {
    try {
      (await _viewModel.deleteComment(id)).getOrThrow();
    } catch (error) {
      if (mounted) _snack(collaborationErrorMessage(context.l10n, error));
    }
  }

  Future<void> _editAssignees(SharedScope scope) async {
    final l10n = context.l10n;
    final selected = <String>{...widget.task.assigneeIds};
    final editors = _state.editors;
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => ShadDialog(
          title: Text(l10n.collaborationEditAssignees),
          actions: [
            ShadButton.ghost(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.l10n.commonCancel),
            ),
            ShadButton(
              key: const Key('task-assignees-save'),
              onPressed: () => Navigator.of(context).pop(selected),
              child: Text(context.l10n.commonSave),
            ),
          ],
          child: SizedBox(
            width: 460,
            child: Material(
              type: MaterialType.transparency,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: editors.isEmpty
                    ? Padding(
                        key: const Key('task-assignees-empty'),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(l10n.collaborationNoAssignees),
                      )
                    : SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final member in editors)
                              CheckboxListTile(
                                key: Key(
                                  'task-assignee-option-${member['userId']}',
                                ),
                                value: selected.contains(member['userId']),
                                title: Text(
                                  collaborationMemberLabel(
                                    l10n,
                                    scope,
                                    member['userId'] as String? ?? '',
                                  ),
                                ),
                                onChanged: (checked) => setState(() {
                                  final userId =
                                      member['userId'] as String? ?? '';
                                  if (checked == true) {
                                    selected.add(userId);
                                  } else {
                                    selected.remove(userId);
                                  }
                                }),
                              ),
                          ],
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
    if (result == null || !mounted) return;
    try {
      (await _viewModel.setAssignees(result)).getOrThrow();
    } catch (error) {
      if (mounted) _snack(collaborationErrorMessage(context.l10n, error));
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
