import '../../../../l10n/app_localizations.dart';
import '../domain/collaboration_models.dart';

String collaborationRoleLabel(AppLocalizations l10n, String role) =>
    switch (role) {
      'administrator' => l10n.collaborationRoleAdministrator,
      'member' => l10n.collaborationRoleMember,
      _ => l10n.collaborationRoleObserver,
    };

String collaborationErrorMessage(AppLocalizations l10n, Object error) {
  final code = error is CollaborationException ? error.code : '';
  return switch (code) {
    'personal_sync_pending' => l10n.collaborationSyncPending,
    'forbidden' ||
    'invalid_assignee' ||
    'invalid_section' ||
    'cross_scope_move' ||
    'cross_scope_comment' ||
    'invalid_comment' ||
    'shared_task_required' ||
    'shared_root_requires_server_delete' => l10n.collaborationForbidden,
    'unauthenticated' => l10n.collaborationSignedOut,
    'function_not_found' => l10n.collaborationUnavailable,
    _ => l10n.collaborationError,
  };
}

String? collaborationMemberName(SharedScope scope, String userId) {
  for (final member in scope.members) {
    if (member['userId'] == userId) {
      final name = member['displayName'] as String?;
      if (name != null && name.trim().isNotEmpty) return name.trim();
    }
  }
  return null;
}

String collaborationMemberLabel(
  AppLocalizations l10n,
  SharedScope scope,
  String userId,
) => collaborationMemberName(scope, userId) ?? l10n.collaborationMemberFallback;

String collaborationInitials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .take(2)
      .toList();
  if (parts.isEmpty) return '?';
  return parts.map((part) => part[0]).join().toUpperCase();
}
