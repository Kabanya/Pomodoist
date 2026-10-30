import 'package:pomodoist/ui/core/themes/app_motion.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/core/widgets/app_action_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart'
    show LucideIcons, ShadButton, ShadDialog, ShadInput, ShadContextMenuItem;

import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/domain/models/collaboration/collaboration_models.dart';
import 'package:pomodoist/domain/models/collaboration/collaboration_responses.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/ui/collaboration/widgets/collaboration_copy.dart';
import 'package:pomodoist/ui/collaboration/view_models/task_collaboration_view_model.dart';

class TaskCollaborationSection extends ConsumerStatefulWidget {
  const TaskCollaborationSection({
    required this.task,
    this.showAssignees = true,
    this.showComments = true,
    this.assigneeChips = false,
    super.key,
  });

  final TaskItem task;
  final bool showAssignees;
  final bool showComments;
  final bool assigneeChips;

  @override
  ConsumerState<TaskCollaborationSection> createState() =>
      _TaskCollaborationSectionState();
}

class _TaskCollaborationSectionState
    extends ConsumerState<TaskCollaborationSection> {
  final _comment = TextEditingController();
  bool _sending = false;
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
        if (widget.showAssignees) _assignees(context, scope),
        if (widget.showAssignees && widget.showComments)
          const SizedBox(height: 16),
        if (widget.showComments) _comments(context, scope),
      ],
    );
  }

  Widget _assignees(BuildContext context, SharedScope scope) {
    final l10n = context.l10n;
    final names = [
      for (final id in widget.task.assigneeIds)
        collaborationMemberLabel(l10n, scope, id),
    ];
    if (widget.assigneeChips) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final name in names)
            ActionChip(
              avatar: CircleAvatar(
                backgroundColor: context.appColors.surfaceTint,
                child: Text(
                  collaborationInitials(name),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
              label: Text(name),
              onPressed: scope.canEdit ? () => _editAssignees(scope) : null,
            ),
          TextButton.icon(
            onPressed: scope.canEdit ? () => _editAssignees(scope) : null,
            icon: const Icon(LucideIcons.userPlus, size: 18),
            label: Text(l10n.collaborationEditAssignees),
          ),
        ],
      );
    }
    return Row(
      children: [
        Icon(
          LucideIcons.users,
          size: 15,
          color: context.appColors.secondaryText,
        ),
        const SizedBox(width: 8),
        Flexible(
          flex: 2,
          child: SizedBox(
            width: 108,
            child: Text(
              l10n.collaborationAssignees,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.appColors.secondaryText,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: TextButton(
            key: const Key('task-assignees-edit'),
            style: TextButton.styleFrom(
              foregroundColor: context.appColors.primaryText,
              alignment: Alignment.centerLeft,
              minimumSize: const Size(44, 44),
              padding: const EdgeInsets.symmetric(horizontal: 4),
            ),
            onPressed: scope.canEdit ? () => _editAssignees(scope) : null,
            child: Text(
              names.isEmpty ? l10n.collaborationNoAssignees : names.join(', '),
            ),
          ),
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
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.taskDiscussionTab,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            Text(
              '${comments.length}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.appColors.secondaryText,
              ),
            ),
          ],
        ),
        for (final comment in comments) _commentTile(context, scope, comment),
        if (scope.canEdit) ...[
          const SizedBox(height: 16),
          ShadInput(
            key: const Key('task-comment-input'),
            controller: _comment,
            minLines: 1,
            maxLines: 4,
            placeholder: Text(l10n.collaborationCommentHint),
            trailing: IconButton(
              key: const Key('task-comment-send'),
              tooltip: l10n.collaborationCommentSend,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              onPressed: _sending ? null : _sendComment,
              icon: _sending
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(LucideIcons.arrowUp, size: 18),
            ),
          ),
        ],
      ],
    );
  }

  Widget _commentTile(
    BuildContext context,
    SharedScope scope,
    CollaborationComment comment,
  ) {
    final l10n = context.l10n;
    final author = collaborationMemberLabel(
      l10n,
      scope,
      comment.createdBy ?? '',
    );
    final time = collaborationCommentTime(
      comment.createdAt,
      Localizations.localeOf(context).toLanguageTag(),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: CircleAvatar(
              radius: 13,
              backgroundColor: context.appColors.surfaceTint,
              foregroundColor: context.appColors.secondaryText,
              child: Text(
                collaborationInitials(author),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      author,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    if (time.isNotEmpty)
                      Text(
                        time,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.appColors.secondaryText,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  comment.body,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(height: 1.6),
                ),
              ],
            ),
          ),
          if (_state.canDeleteComment(comment))
            AppActionMenu(
              width: 44,
              key: Key('task-comment-delete-${comment.id}'),
              tooltip: l10n.taskMore,
              items: [
                ShadContextMenuItem(
                  leading: const Icon(LucideIcons.trash2, size: 16),
                  onPressed: () => _deleteComment(scope.id, comment.id),
                  child: Text(l10n.collaborationCommentDelete),
                ),
              ],
              child: const Icon(LucideIcons.ellipsis, size: 16),
            ),
        ],
      ),
    );
  }

  Future<void> _sendComment() async {
    if (_sending || _comment.text.trim().isEmpty) return;
    final draft = _comment.text;
    setState(() => _sending = true);
    try {
      final sent = (await _viewModel.sendComment(draft)).getOrThrow();
      if (mounted && sent && _comment.text == draft) _comment.clear();
    } catch (error) {
      if (mounted) _snack(collaborationErrorMessage(context.l10n, error));
    } finally {
      if (mounted) setState(() => _sending = false);
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
    final result = await showTaskAssigneesDialog(
      context,
      scope: scope,
      assigneeIds: widget.task.assigneeIds.toSet(),
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

Future<Set<String>?> showTaskAssigneesDialog(
  BuildContext context, {
  required SharedScope scope,
  required Set<String> assigneeIds,
}) {
  final l10n = context.l10n;
  final selected = <String>{...assigneeIds};
  final editors = scope.members.where((member) => member.role.canEdit).toList();
  return showDialog<Set<String>>(
    context: context,
    animationStyle: AnimationStyle(
      duration: AppMotion.duration(context, AppMotion.popup),
      reverseDuration: AppMotion.duration(context, AppMotion.popup),
      curve: AppMotion.curve,
    ),
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
                              key: Key('task-assignee-option-${member.userId}'),
                              value: selected.contains(member.userId),
                              title: Text(
                                collaborationMemberLabel(
                                  l10n,
                                  scope,
                                  member.userId,
                                ),
                              ),
                              onChanged: (checked) => setState(() {
                                if (checked == true) {
                                  selected.add(member.userId);
                                } else {
                                  selected.remove(member.userId);
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
}
