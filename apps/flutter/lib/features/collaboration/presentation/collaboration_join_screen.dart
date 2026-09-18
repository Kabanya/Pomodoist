import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons, ShadButton;

import '../../../app/config/app_l10n.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../l10n/app_localizations.dart';
import '../data/collaboration_repository.dart';
import '../domain/collaboration_models.dart';
import 'collaboration_copy.dart';
import 'collaboration_providers.dart';

final _invitationTokenPattern = RegExp(r'^[0-9a-fA-F]{64}$');

enum _JoinPhase { loading, ready, working, accepted, failed }

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
  _JoinPhase _phase = _JoinPhase.loading;
  String? _role;
  String? _projectId;
  String? _errorMessage;
  var _canRetry = false;
  String? _listedToken;

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(collaborationRepositoryProvider);
    if (repository != null &&
        _invitationTokenPattern.hasMatch(widget.token) &&
        _listedToken != widget.token) {
      _listedToken = widget.token;
      WidgetsBinding.instance.addPostFrameCallback((_) => _listInvitation());
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _content(context, repository),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _content(
    BuildContext context,
    CollaborationRepository? repository,
  ) {
    final l10n = context.l10n;
    if (!_invitationTokenPattern.hasMatch(widget.token)) {
      return _notice(
        context,
        icon: LucideIcons.link,
        message: l10n.collaborationJoinInvalid,
        messageKey: const Key('collaboration-join-invalid'),
      );
    }
    if (repository == null) {
      return _notice(
        context,
        icon: LucideIcons.userX,
        message: l10n.collaborationSignedOut,
        messageKey: const Key('collaboration-join-signed-out'),
      );
    }
    return switch (_phase) {
      _JoinPhase.loading => const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: CircularProgressIndicator(
            key: Key('collaboration-join-loading'),
          ),
        ),
      ],
      _JoinPhase.ready || _JoinPhase.working => _invitation(context),
      _JoinPhase.accepted => _accepted(context),
      _JoinPhase.failed => _failure(context),
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
    final busy = _phase == _JoinPhase.working;
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
      if (_role != null)
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
              collaborationRoleLabel(l10n, _role!),
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
    final projectId = _projectId;
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
        _errorMessage ?? l10n.collaborationError,
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
          _canRetry ? LucideIcons.refreshCw : LucideIcons.check,
          size: 16,
        ),
        child: Text(
          _canRetry ? l10n.commonRetry : l10n.collaborationJoinAccept,
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

  Future<void> _listInvitation() async {
    final repository = ref.read(collaborationRepositoryProvider);
    if (repository == null || !mounted) return;
    try {
      final state = await repository.state();
      for (final invitation in collaborationMaps(state['invitations'])) {
        if (invitation['token'] != widget.token) continue;
        final role = invitation['role'];
        if (role is String) _role = role;
        break;
      }
    } catch (_) {
      // The server validates the invitation when it is accepted, so a missing
      // or unreadable listing must not block the invitation screen. The role
      // stays unknown rather than being guessed.
    }
    if (mounted) setState(() => _phase = _JoinPhase.ready);
  }

  Future<void> _accept() async {
    if (_phase == _JoinPhase.working) return;
    final repository = ref.read(collaborationRepositoryProvider);
    if (repository == null) {
      setState(() {
        _phase = _JoinPhase.failed;
        _errorMessage = context.l10n.collaborationSignedOut;
        _canRetry = false;
      });
      return;
    }
    setState(() {
      _phase = _JoinPhase.working;
      _errorMessage = null;
    });
    try {
      final result = await repository.acceptInvitation(widget.token);
      final scope = result['scope'];
      final projectId = scope is Map
          ? scope['rootProjectId']?.toString()
          : null;
      if (!mounted) return;
      setState(() {
        _projectId = projectId;
        _phase = _JoinPhase.accepted;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = _joinErrorMessage(context.l10n, error);
        _canRetry = error is! CollaborationException || error.code != '42501';
        _phase = _JoinPhase.failed;
      });
    }
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
