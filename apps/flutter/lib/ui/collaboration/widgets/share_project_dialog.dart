import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart'
    show LucideIcons, ShadButton, ShadDialog, ShadInput, ShadOption, ShadSelect;

import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/domain/models/collaboration/collaboration_conflict.dart';
import 'package:pomodoist/domain/models/collaboration/collaboration_models.dart';
import 'package:pomodoist/domain/models/collaboration/collaboration_responses.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/utils/result.dart';
import 'package:pomodoist/ui/collaboration/widgets/collaboration_copy.dart';
import 'package:pomodoist/ui/collaboration/view_models/share_project_view_model.dart';

enum _MemberAction {
  transfer,
  remove,
  administrator(CollaborationRole.administrator),
  member(CollaborationRole.member),
  observer(CollaborationRole.observer);

  const _MemberAction([this.role]);

  final CollaborationRole? role;
}

Future<void> showShareProjectDialog(BuildContext context, ProjectItem project) {
  return showDialog<void>(
    context: context,
    builder: (_) => _ShareProjectDialog(project: project),
  );
}

class _ShareProjectDialog extends ConsumerStatefulWidget {
  const _ShareProjectDialog({required this.project});

  final ProjectItem project;

  @override
  ConsumerState<_ShareProjectDialog> createState() =>
      _ShareProjectDialogState();
}

class _ShareProjectDialogState extends ConsumerState<_ShareProjectDialog> {
  final _email = TextEditingController();
  late ShareProjectState _state;
  var _inviteRole = CollaborationRole.member;
  ShareProjectViewModel get _viewModel =>
      ref.read(shareProjectViewModelProvider(widget.project.id).notifier);

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    _state = ref.watch(shareProjectViewModelProvider(widget.project.id));
    final scope = _state.scope;
    return ShadDialog(
      title: Text(l10n.collaborationShareProject),
      actions: [
        ShadButton.ghost(
          key: const Key('collaboration-close'),
          onPressed: _state.busy ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.commonClose),
        ),
      ],
      child: SizedBox(
        width: 460,
        child: Material(
          type: MaterialType.transparency,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 560),
            child: SingleChildScrollView(
              child: scope == null
                  ? _shareIntro(context)
                  : _manageScope(context, scope),
            ),
          ),
        ),
      ),
    );
  }

  Widget _shareIntro(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l10n.collaborationShareIntro),
        const SizedBox(height: 16),
        ShadButton(
          key: const Key('collaboration-share-start'),
          onPressed: _state.busy ? null : _share,
          leading: _state.busy
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(LucideIcons.users, size: 16),
          child: Text(l10n.collaborationShareStart),
        ),
        if (_state.busy) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
          const SizedBox(height: 8),
          Text(
            l10n.collaborationShareInProgress,
            key: const Key('collaboration-share-progress'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  Widget _manageScope(BuildContext context, SharedScope scope) {
    final l10n = context.l10n;
    final actorId = _state.actorId;
    final conflicts = _state.conflicts;
    final members = scope.members;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_state.sharedJustNow) ...[
          Row(
            key: const Key('collaboration-share-confirmed'),
            children: [
              const Icon(LucideIcons.circleCheck, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(l10n.collaborationProjectShared)),
            ],
          ),
          const SizedBox(height: 12),
        ],
        Text(
          l10n.collaborationMembers,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final member in members) _memberRow(context, scope, member),
              if (_state.busy)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: LinearProgressIndicator(),
                ),
            ],
          ),
        ),
        if (scope.canManage) ...[
          const SizedBox(height: 8),
          _inviteForm(context),
          if (_state.invitations.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              l10n.collaborationPendingInvitations,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final invitation in _state.invitations)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(LucideIcons.mail, size: 18),
                title: Text(invitation.email ?? ''),
                subtitle: Text(collaborationRoleLabel(l10n, invitation.role)),
                trailing: ShadButton.ghost(
                  key: Key('collaboration-revoke-${invitation.id}'),
                  onPressed: _state.busy
                      ? null
                      : () => _revokeInvitation(invitation.id),
                  child: Text(l10n.collaborationRevoke),
                ),
              ),
          ],
        ],
        if (conflicts.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            l10n.collaborationConflicts,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          for (final conflict in conflicts)
            _conflictRow(context, scope, conflict),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            if (!scope.canDeleteRoot(actorId))
              ShadButton.ghost(
                key: const Key('collaboration-leave'),
                onPressed: _state.busy ? null : _leave,
                leading: const Icon(LucideIcons.logOut, size: 16),
                child: Text(l10n.collaborationLeaveProject),
              ),
            const Spacer(),
            if (scope.canDeleteRoot(actorId))
              ShadButton.ghost(
                key: const Key('collaboration-make-private'),
                onPressed: _state.busy ? null : _unshare,
                leading: const Icon(LucideIcons.lock, size: 16),
                child: Text(l10n.collaborationMakePrivate),
              ),
            if (scope.canDeleteRoot(actorId))
              ShadButton.destructive(
                key: const Key('collaboration-delete'),
                onPressed: _state.busy ? null : _delete,
                leading: const Icon(LucideIcons.trash2, size: 16),
                child: Text(l10n.collaborationDeleteSharedProject),
              ),
          ],
        ),
      ],
    );
  }

  Widget _memberRow(
    BuildContext context,
    SharedScope scope,
    CollaborationMember member,
  ) {
    final l10n = context.l10n;
    final actorId = _state.actorId;
    final userId = member.userId;
    final name = collaborationMemberLabel(l10n, scope, userId);
    final isOwner = userId == scope.ownerId;
    final canManageMembers = scope.canManage && !isOwner;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 16,
        child: Text(
          collaborationInitials(name),
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ),
      title: Text(name),
      subtitle: Text(
        isOwner
            ? '${collaborationRoleLabel(l10n, member.role)} · ${l10n.collaborationOwner}'
            : collaborationRoleLabel(l10n, member.role),
      ),
      trailing: scope.canManage && userId != actorId
          ? PopupMenuButton<_MemberAction>(
              key: Key('collaboration-member-menu-$userId'),
              enabled: !_state.busy,
              onSelected: (value) {
                switch (value) {
                  case _MemberAction.transfer:
                    _transfer(userId, name);
                  case _MemberAction.remove:
                    _remove(userId, name);
                  case _MemberAction.administrator ||
                      _MemberAction.member ||
                      _MemberAction.observer:
                    _setRole(userId, value.role!);
                }
              },
              itemBuilder: (context) => [
                if (canManageMembers) ...[
                  for (final action in const [
                    _MemberAction.administrator,
                    _MemberAction.member,
                    _MemberAction.observer,
                  ])
                    if (action.role != member.role)
                      PopupMenuItem(
                        key: Key(
                          'collaboration-role-$userId-${action.role!.name}',
                        ),
                        value: action,
                        child: Text(
                          collaborationRoleLabel(context.l10n, action.role!),
                        ),
                      ),
                ],
                if (scope.ownerId == actorId && userId != actorId)
                  PopupMenuItem(
                    key: Key('collaboration-transfer-$userId'),
                    value: _MemberAction.transfer,
                    child: Text(l10n.collaborationTransferOwnership),
                  ),
                if (canManageMembers)
                  PopupMenuItem(
                    key: Key('collaboration-remove-$userId'),
                    value: _MemberAction.remove,
                    child: Text(l10n.collaborationRemoveMember),
                  ),
              ],
            )
          : null,
    );
  }

  Widget _inviteForm(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ShadInput(
          key: const Key('collaboration-invite-email'),
          controller: _email,
          enabled: !_state.busy,
          placeholder: Text(l10n.collaborationEmail),
          leading: const Icon(LucideIcons.mail, size: 16),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ShadSelect<CollaborationRole>(
                key: const Key('collaboration-invite-role'),
                initialValue: _inviteRole,
                options: [
                  ShadOption(
                    value: CollaborationRole.member,
                    child: Text(l10n.collaborationRoleMember),
                  ),
                  ShadOption(
                    value: CollaborationRole.observer,
                    child: Text(l10n.collaborationRoleObserver),
                  ),
                ],
                selectedOptionBuilder: (context, value) =>
                    Text(collaborationRoleLabel(l10n, value)),
                onChanged: _state.busy
                    ? null
                    : (value) => setState(
                        () => _inviteRole = value ?? CollaborationRole.member,
                      ),
              ),
            ),
            const SizedBox(width: 8),
            ShadButton(
              key: const Key('collaboration-invite-submit'),
              onPressed: _state.busy ? null : _invite,
              leading: const Icon(LucideIcons.userPlus, size: 16),
              child: Text(l10n.collaborationInvite),
            ),
          ],
        ),
      ],
    );
  }

  Widget _conflictRow(
    BuildContext context,
    SharedScope scope,
    CollaborationConflict command,
  ) {
    final l10n = context.l10n;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: const Icon(LucideIcons.triangleAlert, size: 18),
      title: Text(command.label),
      subtitle: Text(l10n.collaborationConflictHint),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ShadButton.ghost(
            key: Key('collaboration-conflict-mine-${command.id}'),
            onPressed: _state.busy
                ? null
                : () => _resolveConflict(command, keepLocal: true),
            child: Text(l10n.collaborationConflictKeepLocal),
          ),
          ShadButton.ghost(
            key: Key('collaboration-conflict-server-${command.id}'),
            onPressed: _state.busy
                ? null
                : () => _resolveConflict(command, keepLocal: false),
            child: Text(l10n.collaborationConflictUseServer),
          ),
        ],
      ),
    );
  }

  Future<bool> _run<T>(
    Future<Result<T>> Function() action, {
    bool close = false,
    String? success,
  }) async {
    if (_state.busy) return false;
    try {
      (await action()).getOrThrow();
      if (!mounted) return false;
      if (success != null) _snack(success);
      if (close) Navigator.of(context).pop();
      return true;
    } catch (error) {
      if (mounted) _snack(collaborationErrorMessage(context.l10n, error));
      return false;
    }
  }

  void _snack(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));
  Future<bool> _share() => _run(_viewModel.share);

  Future<void> _invite() async {
    final email = _email.text.trim();
    if (_state.scope == null || email.isEmpty) return;
    await _run(() async {
      final result = await _viewModel.invite(email, _inviteRole);
      if (result case Success(:final value)) {
        if (mounted) {
          _snack(
            value.emailDelivery == CollaborationEmailDelivery.failed
                ? context.l10n.collaborationInviteEmailFailed
                : context.l10n.collaborationInviteSent(email),
          );
          _email.clear();
        }
      }
      return result;
    });
  }

  Future<bool> _revokeInvitation(String id) => _run(
    () => _viewModel.revokeInvitation(id),
    success: context.l10n.collaborationInvitationRevoked,
  );
  Future<bool> _setRole(String userId, CollaborationRole role) => _run(
    () => _viewModel.setRole(userId, role),
    success: context.l10n.collaborationRoleUpdated,
  );

  Future<void> _remove(String userId, String name) async {
    if (await _confirm(
              context.l10n.collaborationRemoveMember,
              context.l10n.collaborationRemoveConfirm(name),
              context.l10n.collaborationRemoveMember,
            ) !=
            true ||
        !mounted) {
      return;
    }
    await _run(
      () => _viewModel.remove(userId),
      success: context.l10n.collaborationMemberRemoved,
    );
  }

  Future<void> _transfer(String userId, String name) async {
    if (await _confirm(
              context.l10n.collaborationTransferOwnership,
              context.l10n.collaborationTransferConfirm(name),
              context.l10n.collaborationTransferOwnership,
            ) !=
            true ||
        !mounted) {
      return;
    }
    await _run(
      () => _viewModel.transfer(userId),
      success: context.l10n.collaborationOwnershipTransferred,
    );
  }

  Future<void> _leave() async {
    if (await _confirm(
              context.l10n.collaborationLeaveProject,
              context.l10n.collaborationLeaveConfirm,
              context.l10n.collaborationLeaveProject,
            ) !=
            true ||
        !mounted) {
      return;
    }
    await _run(
      _viewModel.leave,
      close: true,
      success: context.l10n.collaborationLeftProject,
    );
  }

  Future<void> _delete() async {
    if (await _confirm(
              context.l10n.collaborationDeleteSharedProject,
              context.l10n.collaborationDeleteSharedConfirm,
              context.l10n.commonDelete,
              destructive: true,
            ) !=
            true ||
        !mounted) {
      return;
    }
    await _run(
      _viewModel.delete,
      close: true,
      success: context.l10n.collaborationSharedProjectDeleted,
    );
  }

  Future<void> _unshare() async {
    if (await _confirm(
              context.l10n.collaborationMakePrivateConfirm,
              context.l10n.collaborationMakePrivateDescription,
              context.l10n.collaborationMakePrivate,
            ) !=
            true ||
        !mounted) {
      return;
    }
    await _run(
      _viewModel.unshare,
      close: true,
      success: context.l10n.collaborationProjectMadePrivate,
    );
  }

  Future<bool> _resolveConflict(
    CollaborationConflict command, {
    required bool keepLocal,
  }) => _run(
    () => _viewModel.resolveConflict(command, keepLocal: keepLocal),
    success: context.l10n.collaborationConflictResolved,
  );

  Future<bool?> _confirm(
    String title,
    String message,
    String confirmLabel, {
    bool destructive = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => ShadDialog(
        title: Text(title),
        actions: [
          ShadButton.ghost(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.commonCancel),
          ),
          if (destructive)
            ShadButton.destructive(
              key: const Key('collaboration-confirm'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(confirmLabel),
            )
          else
            ShadButton(
              key: const Key('collaboration-confirm'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(confirmLabel),
            ),
        ],
        child: Text(message),
      ),
    );
  }
}
