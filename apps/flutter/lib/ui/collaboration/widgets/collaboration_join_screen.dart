import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons, ShadButton;

import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/core/localization/app_localizations.dart';
import 'package:pomodoist/domain/models/collaboration/collaboration_models.dart';
import 'package:pomodoist/ui/collaboration/widgets/collaboration_copy.dart';
import 'package:pomodoist/ui/collaboration/view_models/collaboration_join_view_model.dart';

/// Standalone route for the invitation link sent by email.
class CollaborationJoinScreen extends ConsumerStatefulWidget {
  const CollaborationJoinScreen({required this.token, super.key});

  final String token;

  @override
  ConsumerState<CollaborationJoinScreen> createState() =>
      _CollaborationJoinScreenState();
}

class _CollaborationJoinScreenState
    extends ConsumerState<CollaborationJoinScreen> {
  late CollaborationJoinState _state;

  void _accept() => ref
      .read(collaborationJoinViewModelProvider(widget.token).notifier)
      .accept();

  @override
  Widget build(BuildContext context) {
    _state = ref.watch(collaborationJoinViewModelProvider(widget.token));
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _content(context),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _content(BuildContext context) {
    final l10n = context.l10n;
    if (!_state.valid) {
      return _notice(
        context,
        icon: LucideIcons.link,
        message: l10n.collaborationJoinInvalid,
        messageKey: const Key('collaboration-join-invalid'),
      );
    }
    if (!_state.signedIn) {
      return _notice(
        context,
        icon: LucideIcons.userX,
        message: l10n.collaborationSignedOut,
        messageKey: const Key('collaboration-join-signed-out'),
      );
    }
    return switch (_state.phase) {
      JoinPhase.loading => const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: CircularProgressIndicator(
            key: Key('collaboration-join-loading'),
          ),
        ),
      ],
      JoinPhase.ready || JoinPhase.working => _invitation(context),
      JoinPhase.accepted => _accepted(context),
      JoinPhase.failed => _failure(context),
    };
  }

  List<Widget> _notice(
    BuildContext context, {
    required IconData icon,
    required String message,
    required Key messageKey,
  }) {
    final colors = context.appColors;
    return [
      _badge(
        icon: icon,
        background: colors.surfaceTint,
        foreground: colors.secondaryText,
      ),
      const SizedBox(height: 20),
      Text(
        message,
        key: messageKey,
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        textAlign: TextAlign.center,
      ),
    ];
  }

  List<Widget> _invitation(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final textTheme = Theme.of(context).textTheme;
    final busy = _state.phase == JoinPhase.working;
    return [
      _badge(
        icon: LucideIcons.users,
        background: colors.accentTint,
        foreground: colors.accent,
      ),
      const SizedBox(height: 20),
      Text(
        l10n.collaborationJoinTitle,
        key: const Key('collaboration-join-title'),
        style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 8),
      Text(
        l10n.collaborationJoinDescription,
        style: textTheme.bodyLarge?.copyWith(color: colors.secondaryText),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 20),
      if (_state.role != null)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.collaborationJoinRole,
              style: textTheme.bodyMedium?.copyWith(
                color: colors.secondaryText,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              collaborationRoleLabel(l10n, _state.role!),
              key: const Key('collaboration-join-role'),
              style: textTheme.bodyMedium?.copyWith(
                color: colors.primaryText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      const SizedBox(height: 24),
      ShadButton(
        key: const Key('collaboration-join-accept'),
        onPressed: busy ? null : _accept,
        leading: busy
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(
                  key: Key('collaboration-join-progress'),
                  strokeWidth: 2,
                ),
              )
            : const Icon(LucideIcons.check, size: 16),
        child: Text(l10n.collaborationJoinAccept),
      ),
    ];
  }

  List<Widget> _accepted(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final projectId = _state.projectId;
    return [
      _badge(
        icon: LucideIcons.circleCheck,
        background: colors.accentTint,
        foreground: colors.accent,
      ),
      const SizedBox(height: 20),
      Text(
        l10n.collaborationInvitationAccepted,
        key: const Key('collaboration-join-accepted'),
        style: Theme.of(
          context,
        ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        textAlign: TextAlign.center,
      ),
      if (projectId != null) ...[
        const SizedBox(height: 24),
        ShadButton(
          key: const Key('collaboration-join-open'),
          onPressed: () => context.go('/project/$projectId'),
          leading: const Icon(LucideIcons.folderInput, size: 16),
          child: Text(l10n.collaborationJoinOpenProject),
        ),
      ],
    ];
  }

  List<Widget> _failure(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    return [
      _badge(
        icon: LucideIcons.circleAlert,
        background: colors.surfaceTint,
        foreground: colors.error,
      ),
      const SizedBox(height: 20),
      Text(
        _state.error == null
            ? l10n.collaborationError
            : _joinErrorMessage(l10n, _state.error!),
        key: const Key('collaboration-join-error'),
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 24),
      ShadButton(
        key: const Key('collaboration-join-accept'),
        onPressed: _accept,
        leading: Icon(
          _state.canRetry ? LucideIcons.refreshCw : LucideIcons.check,
          size: 16,
        ),
        child: Text(
          _state.canRetry ? l10n.commonRetry : l10n.collaborationJoinAccept,
        ),
      ),
    ];
  }

  Widget _badge({
    required IconData icon,
    required Color background,
    required Color foreground,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Icon(icon, color: foreground, size: 46),
      ),
    );
  }
}

String _joinErrorMessage(AppLocalizations l10n, Object error) {
  final code = error is CollaborationException ? error.code : '';
  return switch (code) {
    '42501' => l10n.collaborationJoinUnavailable,
    'unauthenticated' => l10n.collaborationSignedOut,
    'function_not_found' || 'unavailable' => l10n.collaborationUnavailable,
    _ => collaborationErrorMessage(l10n, error),
  };
}
