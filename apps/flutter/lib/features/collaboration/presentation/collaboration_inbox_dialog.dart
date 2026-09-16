import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart'
    show LucideIcons, ShadButton, ShadDialog;

import '../../../../app/app_l10n.dart';
import '../../../../l10n/app_localizations.dart';
import '../data/collaboration_repository.dart';
import '../domain/collaboration_models.dart';
import 'collaboration_copy.dart';
import 'collaboration_providers.dart';

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
  var _loading = true;
  var _busy = false;
  List<Map<String, dynamic>> _invitations = const [];
  List<Map<String, dynamic>> _notifications = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ShadDialog(
      title: Text(l10n.collaborationInboxTitle),
      actions: [
        ShadButton.ghost(
          key: const Key('collaboration-inbox-close'),
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.commonClose),
        ),
      ],
      child: SizedBox(
        width: 460,
        child: Material(
          type: MaterialType.transparency,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 520),
            child: _loading
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
                        if (_invitations.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(l10n.collaborationNoInvitations),
                          )
                        else
                          for (final invitation in _invitations)
                            ListTile(
                              key: Key(
                                'collaboration-invitation-${invitation['id']}',
                              ),
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(LucideIcons.users, size: 18),
                              title: Text(
                                collaborationRoleLabel(
                                  l10n,
                                  invitation['role'] as String? ?? 'member',
                                ),
                              ),
                              trailing: ShadButton(
                                key: Key(
                                  'collaboration-inbox-accept-${invitation['id']}',
                                ),
                                onPressed: _busy
                                    ? null
                                    : () => _accept(
                                        invitation['token'] as String? ?? '',
                                      ),
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
                            if (_notifications.any(
                              (item) => item['readAt'] == null,
                            ))
                              ShadButton.ghost(
                                key: const Key(
                                  'collaboration-notifications-read-all',
                                ),
                                onPressed: _busy ? null : _markAllRead,
                                child: Text(l10n.collaborationMarkAllRead),
                              ),
                          ],
                        ),
                        if (_notifications.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(l10n.collaborationNoNotifications),
                          )
                        else
                          for (final notification in _notifications)
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
    Map<String, dynamic> notification,
  ) {
    final unread = notification['readAt'] == null;
    final id = notification['id'] as String? ?? '';
    return ListTile(
      key: Key('collaboration-notification-$id'),
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(unread ? LucideIcons.bellDot : LucideIcons.bell, size: 18),
      title: Text(
        _notificationLabel(l10n, notification['kind'] as String? ?? ''),
        style: unread ? const TextStyle(fontWeight: FontWeight.w600) : null,
      ),
      onTap: unread && !_busy ? () => _markRead(id) : null,
    );
  }

  String _notificationLabel(AppLocalizations l10n, String kind) =>
      switch (kind) {
        'invitation' => l10n.collaborationNotificationInvitation,
        'discussion' => l10n.collaborationNotificationDiscussion,
        'assignment' => l10n.collaborationNotificationAssignment,
        _ => l10n.collaborationNotificationGeneric,
      };

  Future<void> _load() async {
    final repository = ref.read(collaborationRepositoryProvider);
    if (repository == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final result = await repository.state();
      if (!mounted) return;
      setState(() {
        _invitations = collaborationMaps(result['invitations']);
        _notifications = collaborationMaps(result['notifications']);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack(collaborationErrorMessage(context.l10n, error));
    }
  }

  Future<void> _accept(String token) async {
    if (token.isEmpty) return;
    await _run(
      (repository) => repository.acceptInvitation(token),
      success: context.l10n.collaborationInvitationAccepted,
    );
  }

  Future<void> _markRead(String id) => _run(
    (repository) =>
        repository.action('readNotification', {'notificationId': id}),
  );

  Future<void> _markAllRead() async {
    final unread = _notifications
        .where((item) => item['readAt'] == null)
        .map((item) => item['id'] as String)
        .take(50)
        .toList();
    await _run((repository) async {
      for (final id in unread) {
        await repository.action('readNotification', {'notificationId': id});
      }
    });
  }

  Future<void> _run(
    Future<void> Function(CollaborationRepository repository) action, {
    String? success,
  }) async {
    final repository = ref.read(collaborationRepositoryProvider);
    if (repository == null || _busy) return;
    setState(() => _busy = true);
    try {
      await action(repository);
      if (success != null && mounted) _snack(success);
      await _load();
    } catch (error) {
      if (mounted) _snack(collaborationErrorMessage(context.l10n, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
