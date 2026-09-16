import 'dart:convert';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart'
    show
        LucideIcons,
        ShadButton,
        ShadDialog,
        ShadInput,
        ShadOption,
        ShadSelect,
        ShadSwitch;

import '../../../../app/account_providers.dart';
import '../../../../app/app_l10n.dart';
import '../../../../core/db/app_database.dart';
import '../../../../app/runtime_public_config.dart';
import '../domain/collaboration_models.dart';
import '../../tasks/domain/task_models.dart';
import '../data/collaboration_repository.dart';
import 'collaboration_copy.dart';
import 'collaboration_providers.dart';

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
  var _busy = false;
  var _sharedJustNow = false;
  var _inviteRole = 'member';
  List<Map<String, dynamic>> _invitations = const [];
  String? _invitationsScopeId;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scope = ref.watch(sharedScopeForProjectProvider(widget.project.id));
    if (scope != null && _invitationsScopeId != scope.id) {
      _invitationsScopeId = scope.id;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadInvitations());
    }
    return ShadDialog(
      title: Text(l10n.collaborationShareProject),
      actions: [
        ShadButton.ghost(
          key: const Key('collaboration-close'),
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
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
          onPressed: _busy ? null : _share,
          leading: _busy
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(LucideIcons.users, size: 16),
          child: Text(l10n.collaborationShareStart),
        ),
        if (_busy) ...[
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
    final actorId = ref.watch(collaborationActorIdProvider).value;
    final conflicts =
        ref.watch(scopeConflictsProvider(scope.id)).value ?? const [];
    final members = scope.members;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_sharedJustNow) ...[
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
              if (_busy)
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
          if (_invitations.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              l10n.collaborationPendingInvitations,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final invitation in _invitations)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(LucideIcons.mail, size: 18),
                title: Text(invitation['email'] as String? ?? ''),
                subtitle: Text(
                  collaborationRoleLabel(
                    l10n,
                    invitation['role'] as String? ?? 'member',
                  ),
                ),
                trailing: ShadButton.ghost(
                  key: Key('collaboration-revoke-${invitation['id']}'),
                  onPressed: _busy
                      ? null
                      : () => _revokeInvitation(invitation['id'] as String),
                  child: Text(l10n.collaborationRevoke),
                ),
              ),
          ],
          const SizedBox(height: 12),
          Text(
            l10n.collaborationPublicLink,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            l10n.collaborationPublicLinkHint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          Row(
            children: [
              ShadSwitch(
                key: const Key('collaboration-public-link-switch'),
                value: scope.publicToken != null,
                onChanged: _busy ? null : _togglePublicLink,
              ),
              const SizedBox(width: 8),
              if (scope.publicToken != null)
                ShadButton.ghost(
                  key: const Key('collaboration-copy-link'),
                  onPressed: _copyPublicLink,
                  leading: const Icon(LucideIcons.copy, size: 16),
                  child: Text(l10n.collaborationCopyLink),
                ),
            ],
          ),
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
                onPressed: _busy ? null : _leave,
                leading: const Icon(LucideIcons.logOut, size: 16),
                child: Text(l10n.collaborationLeaveProject),
              ),
            const Spacer(),
            if (scope.canDeleteRoot(actorId))
              ShadButton.destructive(
                key: const Key('collaboration-delete'),
                onPressed: _busy ? null : _delete,
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
    Map<String, dynamic> member,
  ) {
    final l10n = context.l10n;
    final actorId = ref.watch(collaborationActorIdProvider).value;
    final userId = member['userId'] as String? ?? '';
    final role = member['role'] as String? ?? 'observer';
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
            ? '${collaborationRoleLabel(l10n, role)} · ${l10n.collaborationOwner}'
            : collaborationRoleLabel(l10n, role),
      ),
      trailing: scope.canManage && userId != actorId
          ? PopupMenuButton<String>(
              key: Key('collaboration-member-menu-$userId'),
              enabled: !_busy,
              onSelected: (value) {
                if (value == 'transfer') {
                  _transfer(userId, name);
                } else if (value == 'remove') {
                  _remove(userId, name);
                } else {
                  _setRole(userId, value);
                }
              },
              itemBuilder: (context) => [
                if (canManageMembers) ...[
                  for (final role in const [
                    'administrator',
                    'member',
                    'observer',
                  ])
                    if (role != member['role'])
                      PopupMenuItem(
                        key: Key('collaboration-role-$userId-$role'),
                        value: role,
                        child: Text(collaborationRoleLabel(context.l10n, role)),
                      ),
                ],
                if (scope.ownerId == actorId && userId != actorId)
                  PopupMenuItem(
                    key: Key('collaboration-transfer-$userId'),
                    value: 'transfer',
                    child: Text(l10n.collaborationTransferOwnership),
                  ),
                if (canManageMembers)
                  PopupMenuItem(
                    key: Key('collaboration-remove-$userId'),
                    value: 'remove',
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
          enabled: !_busy,
          placeholder: Text(l10n.collaborationEmail),
          leading: const Icon(LucideIcons.mail, size: 16),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ShadSelect<String>(
                key: const Key('collaboration-invite-role'),
                initialValue: _inviteRole,
                options: [
                  ShadOption(
                    value: 'member',
                    child: Text(l10n.collaborationRoleMember),
                  ),
                  ShadOption(
                    value: 'observer',
                    child: Text(l10n.collaborationRoleObserver),
                  ),
                ],
                selectedOptionBuilder: (context, value) =>
                    Text(collaborationRoleLabel(l10n, value)),
                onChanged: _busy
                    ? null
                    : (value) =>
                          setState(() => _inviteRole = value ?? 'member'),
              ),
            ),
            const SizedBox(width: 8),
            ShadButton(
              key: const Key('collaboration-invite-submit'),
              onPressed: _busy ? null : _invite,
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
    SyncCommandRow command,
  ) {
    final l10n = context.l10n;
    final decoded = command.lastError == null
        ? null
        : jsonDecode(command.lastError!);
    final conflict = decoded is Map<String, dynamic> ? decoded : null;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: const Icon(LucideIcons.triangleAlert, size: 18),
      title: Text(
        '${conflict?['entityType'] ?? command.type} · '
        '${conflict?['entityId'] ?? command.clientId ?? ''}',
      ),
      subtitle: Text(l10n.collaborationConflictHint),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ShadButton.ghost(
            key: Key('collaboration-conflict-mine-${command.id}'),
            onPressed: _busy
                ? null
                : () => _resolveConflict(command, keepLocal: true),
            child: Text(l10n.collaborationConflictKeepLocal),
          ),
          ShadButton.ghost(
            key: Key('collaboration-conflict-server-${command.id}'),
            onPressed: _busy
                ? null
                : () => _resolveConflict(command, keepLocal: false),
            child: Text(l10n.collaborationConflictUseServer),
          ),
        ],
      ),
    );
  }

  Future<void> _run(
    Future<void> Function(CollaborationRepository repository) action, {
    bool close = false,
    String? success,
  }) async {
    if (_busy) return;
    final repository = ref.read(collaborationRepositoryProvider);
    if (repository == null) {
      final signedIn =
          (ref.read(accountAuthStateProvider).value?.signedIn ?? false) ||
          ref.read(accountClientProvider)?.currentUserId != null;
      if (mounted) {
        _snack(
          signedIn
              ? context.l10n.collaborationUnavailable
              : context.l10n.collaborationSignedOut,
        );
      }
      return;
    }
    setState(() => _busy = true);
    try {
      await action(repository);
      if (success != null && mounted) _snack(success);
      if (close && mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) _snack(collaborationErrorMessage(context.l10n, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _copyToClipboard(String value) {
    // Clipboard access is optional and must never block the share panel.
    unawaited(
      Clipboard.setData(ClipboardData(text: value)).catchError((Object _) {}),
    );
  }

  void _snack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _share() => _run((repository) async {
    await repository.share(widget.project.id);
    if (mounted) setState(() => _sharedJustNow = true);
  });

  Future<void> _loadInvitations() async {
    final repository = ref.read(collaborationRepositoryProvider);
    final scope = ref.read(sharedScopeForProjectProvider(widget.project.id));
    if (repository == null || scope == null || !scope.canManage) return;
    try {
      final result = await repository.action('members', {'scopeId': scope.id});
      final invitations = collaborationMaps(result['invitations']);
      if (mounted) setState(() => _invitations = invitations);
    } catch (_) {
      // Pending invitations are auxiliary; the member list stays usable.
    }
  }

  Future<void> _invite() async {
    final scope = ref.read(sharedScopeForProjectProvider(widget.project.id));
    final email = _email.text.trim();
    if (scope == null || email.isEmpty) return;
    await _run((repository) async {
      final result = await repository.action('invite', {
        'scopeId': scope.id,
        'email': email,
        'role': _inviteRole,
      });
      if (result['emailDelivery'] == 'failed') {
        if (mounted) _snack(context.l10n.collaborationInviteEmailFailed);
      } else if (mounted) {
        _snack(context.l10n.collaborationInviteSent(email));
      }
    });
    if (mounted) {
      _email.clear();
      await _loadInvitations();
    }
  }

  Future<void> _revokeInvitation(String id) async {
    final scope = ref.read(sharedScopeForProjectProvider(widget.project.id));
    if (scope == null) return;
    await _run((repository) async {
      await repository.action('invite', {
        'scopeId': scope.id,
        'invitationId': id,
        'revoke': 'true',
      });
      await _loadInvitations();
    }, success: context.l10n.collaborationInvitationRevoked);
  }

  Future<void> _setRole(String userId, String role) async {
    final scope = ref.read(sharedScopeForProjectProvider(widget.project.id));
    if (scope == null) return;
    await _run(
      (repository) => repository.action('role', {
        'scopeId': scope.id,
        'userId': userId,
        'role': role,
      }),
      success: context.l10n.collaborationRoleUpdated,
    );
  }

  Future<void> _remove(String userId, String name) async {
    final scope = ref.read(sharedScopeForProjectProvider(widget.project.id));
    if (scope == null) return;
    final confirmed = await _confirm(
      context.l10n.collaborationRemoveMember,
      context.l10n.collaborationRemoveConfirm(name),
      context.l10n.collaborationRemoveMember,
    );
    if (confirmed != true || !mounted) return;
    await _run(
      (repository) =>
          repository.action('remove', {'scopeId': scope.id, 'userId': userId}),
      success: context.l10n.collaborationMemberRemoved,
    );
  }

  Future<void> _transfer(String userId, String name) async {
    final scope = ref.read(sharedScopeForProjectProvider(widget.project.id));
    if (scope == null) return;
    final confirmed = await _confirm(
      context.l10n.collaborationTransferOwnership,
      context.l10n.collaborationTransferConfirm(name),
      context.l10n.collaborationTransferOwnership,
    );
    if (confirmed != true || !mounted) return;
    await _run(
      (repository) => repository.action('transfer', {
        'scopeId': scope.id,
        'userId': userId,
      }),
      success: context.l10n.collaborationOwnershipTransferred,
    );
  }

  Future<void> _leave() async {
    final scope = ref.read(sharedScopeForProjectProvider(widget.project.id));
    if (scope == null) return;
    final confirmed = await _confirm(
      context.l10n.collaborationLeaveProject,
      context.l10n.collaborationLeaveConfirm,
      context.l10n.collaborationLeaveProject,
    );
    if (confirmed != true || !mounted) return;
    await _run(
      (repository) => repository.action('leave', {'scopeId': scope.id}),
      close: true,
      success: context.l10n.collaborationLeftProject,
    );
  }

  Future<void> _delete() async {
    final scope = ref.read(sharedScopeForProjectProvider(widget.project.id));
    if (scope == null) return;
    final confirmed = await _confirm(
      context.l10n.collaborationDeleteSharedProject,
      context.l10n.collaborationDeleteSharedConfirm,
      context.l10n.commonDelete,
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    await _run(
      (repository) => repository.action('delete', {'scopeId': scope.id}),
      close: true,
      success: context.l10n.collaborationSharedProjectDeleted,
    );
  }

  Future<void> _togglePublicLink(bool enabled) async {
    final scope = ref.read(sharedScopeForProjectProvider(widget.project.id));
    if (scope == null) return;
    await _run((repository) async {
      final result = await repository.action('publicLink', {
        'scopeId': scope.id,
        'enabled': enabled,
      });
      if (enabled && result['url'] != null && mounted) {
        _copyToClipboard(result['url'].toString());
        _snack(context.l10n.collaborationLinkCopied);
      }
    });
  }

  Future<void> _copyPublicLink() async {
    final scope = ref.read(sharedScopeForProjectProvider(widget.project.id));
    final token = scope?.publicToken;
    if (token == null) return;
    final webUrl = ref.read(runtimePublicConfigProvider).webAppUrl;
    _copyToClipboard('$webUrl/shared/public/$token');
    if (mounted) _snack(context.l10n.collaborationLinkCopied);
  }

  Future<void> _resolveConflict(
    SyncCommandRow command, {
    required bool keepLocal,
  }) => _run(
    (repository) => repository.resolveConflict(command, keepLocal: keepLocal),
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
