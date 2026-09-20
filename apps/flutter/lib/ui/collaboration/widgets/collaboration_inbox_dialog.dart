import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart'
    show LucideIcons, ShadButton, ShadDialog;

import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/localization/app_localizations.dart';
import 'package:pomodoist/domain/models/collaboration/collaboration_responses.dart';
import 'package:pomodoist/ui/collaboration/widgets/collaboration_copy.dart';
import 'package:pomodoist/ui/collaboration/view_models/collaboration_inbox_view_model.dart';

Future<void> showCollaborationInboxDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _CollaborationInboxDialog(),
  );
}

class _CollaborationInboxDialog extends ConsumerStatefulWidget {
  const _CollaborationInboxDialog();

  @override
  ConsumerState<_CollaborationInboxDialog> createState() =>
      _CollaborationInboxDialogState();
}

class _CollaborationInboxDialogState
    extends ConsumerState<_CollaborationInboxDialog> {
  late CollaborationInboxState _state;
  CollaborationInboxViewModel get _viewModel =>
      ref.read(collaborationInboxViewModelProvider.notifier);

  @override
  Widget build(BuildContext context) {
    _state = ref.watch(collaborationInboxViewModelProvider);
    ref.listen(collaborationInboxViewModelProvider, (previous, next) {
      if (next.error != null && previous?.error != next.error) {
        _snack(collaborationErrorMessage(context.l10n, next.error!));
      }
    });
    final l10n = context.l10n;
    return ShadDialog(
      title: Text(l10n.collaborationInboxTitle),
      actions: [
        ShadButton.ghost(
          key: const Key('collaboration-inbox-close'),
          onPressed: _state.busy ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.commonClose),
        ),
      ],
      child: SizedBox(
        width: 460,
        child: Material(
          type: MaterialType.transparency,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 520),
            child: _state.loading
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ),
                  )
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          l10n.collaborationInvitations,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (_state.invitations.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(l10n.collaborationNoInvitations),
                          )
                        else
                          for (final invitation in _state.invitations)
                            ListTile(
                              key: Key(
                                'collaboration-invitation-${invitation.id}',
                              ),
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(LucideIcons.users, size: 18),
                              title: Text(
                                collaborationRoleLabel(l10n, invitation.role),
                              ),
                              trailing: ShadButton(
                                key: Key(
                                  'collaboration-inbox-accept-${invitation.id}',
                                ),
                                onPressed: _state.busy
                                    ? null
                                    : () => _accept(invitation.token ?? ''),
                                child: Text(l10n.collaborationAccept),
                              ),
                            ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                l10n.collaborationNotifications,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            if (_state.notifications.any(
                              (notification) => notification.isUnread,
                            ))
                              ShadButton.ghost(
                                key: const Key(
                                  'collaboration-notifications-read-all',
                                ),
                                onPressed: _state.busy ? null : _markAllRead,
                                child: Text(l10n.collaborationMarkAllRead),
                              ),
                          ],
                        ),
                        if (_state.notifications.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(l10n.collaborationNoNotifications),
                          )
                        else
                          for (final notification in _state.notifications)
                            _notificationTile(l10n, notification),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _notificationTile(
    AppLocalizations l10n,
    CollaborationNotification notification,
  ) {
    final unread = notification.isUnread;
    final id = notification.id;
    return ListTile(
      key: Key('collaboration-notification-$id'),
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(unread ? LucideIcons.bellDot : LucideIcons.bell, size: 18),
      title: Text(
        _notificationLabel(l10n, notification.kind),
        style: unread ? const TextStyle(fontWeight: FontWeight.w600) : null,
      ),
      onTap: unread && !_state.busy ? () => _markRead(id) : null,
    );
  }

  String _notificationLabel(AppLocalizations l10n, String kind) =>
      switch (kind) {
        'invitation' => l10n.collaborationNotificationInvitation,
        'discussion' => l10n.collaborationNotificationDiscussion,
        'assignment' => l10n.collaborationNotificationAssignment,
        _ => l10n.collaborationNotificationGeneric,
      };

  Future<void> _accept(String token) async {
    final accepted = await _viewModel.accept(token);
    if (accepted && mounted) {
      _snack(context.l10n.collaborationInvitationAccepted);
    }
  }

  Future<bool> _markRead(String id) => _viewModel.markRead(id);
  Future<bool> _markAllRead() => _viewModel.markAllRead();

  void _snack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
