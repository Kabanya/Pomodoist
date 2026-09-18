import 'dart:async';

import 'package:app_account/app_account.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons, ShadButton;

import '../../../app/config/account_providers.dart';
import '../../../app/config/app_l10n.dart';
import '../../../app/config/formatters.dart';
import '../../../app/theme/app_motion.dart';

class ConnectedAgentsSection extends ConsumerStatefulWidget {
  const ConnectedAgentsSection({required this.account, super.key});

  final AccountClient account;

  @override
  ConsumerState<ConnectedAgentsSection> createState() =>
      _ConnectedAgentsSectionState();
}

class _ConnectedAgentsSectionState
    extends ConsumerState<ConnectedAgentsSection> {
  Object? _revokeError;
  String? _revokingClientId;
  BuildContext? _confirmationContext;
  late AccountClient _account;
  String? _userId;

  @override
  void initState() {
    super.initState();
    _account = widget.account;
    _userId = widget.account.currentUserId;
  }

  @override
  void didUpdateWidget(ConnectedAgentsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final userId = widget.account.currentUserId;
    if (!identical(_account, widget.account) || _userId != userId) {
      _dismissConfirmation();
      _account = widget.account;
      _userId = userId;
      _revokeError = null;
      _revokingClientId = null;
    }
  }

  @override
  void dispose() {
    _dismissConfirmation();
    super.dispose();
  }

  bool _isCurrent(AccountClient account, String? userId) {
    return mounted &&
        userId != null &&
        identical(_account, account) &&
        identical(widget.account, account) &&
        _userId == userId &&
        account.currentUserId == userId;
  }

  void _dismissConfirmation() {
    final dialogContext = _confirmationContext;
    _confirmationContext = null;
    if (dialogContext == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (dialogContext.mounted) Navigator.of(dialogContext).pop(false);
    });
  }

  Future<void> _load() => ref.read(connectedAgentsProvider.notifier).refresh();

  Future<void> _confirmRevoke(AccountOAuthGrant grant) async {
    if (_revokingClientId != null) return;
    final account = widget.account;
    final userId = account.currentUserId;
    if (!_isCurrent(account, userId)) return;
    final l10n = context.l10n;
    final clientName = grant.clientName?.trim().isNotEmpty == true
        ? grant.clientName!.trim()
        : l10n.settingsConnectedAgentsUnknownClient;
    final confirmed =
        await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          animationStyle: AnimationStyle(
            duration: AppMotion.duration(context, AppMotion.popup),
            reverseDuration: AppMotion.duration(context, AppMotion.popup),
            curve: AppMotion.curve,
          ),
          builder: (dialogContext) {
            _confirmationContext = dialogContext;
            return AlertDialog(
              key: const Key('connected-agent-revoke-dialog'),
              title: Text(l10n.settingsConnectedAgentsRevokeConfirmTitle),
              content: Text(
                l10n.settingsConnectedAgentsRevokeConfirmMessage(clientName),
              ),
              actions: [
                ShadButton.ghost(
                  height: 48,
                  key: const Key('connected-agent-revoke-cancel'),
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: Text(l10n.commonCancel),
                ),
                ShadButton(
                  height: 48,
                  key: const Key('connected-agent-revoke-confirm'),
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: Text(l10n.settingsConnectedAgentsRevoke),
                ),
              ],
            );
          },
        ) ??
        false;
    _confirmationContext = null;
    if (!confirmed || !_isCurrent(account, userId)) return;
    await _revoke(grant.clientId, account, userId);
  }

  Future<void> _revoke(
    String clientId,
    AccountClient account,
    String? userId,
  ) async {
    if (_revokingClientId != null || !_isCurrent(account, userId)) return;
    setState(() {
      _revokingClientId = clientId;
      _revokeError = null;
    });
    try {
      await ref.read(connectedAgentsProvider.notifier).revoke(clientId);
    } on Object catch (error) {
      if (_isCurrent(account, userId)) {
        setState(() => _revokeError = error);
      }
    } finally {
      if (_isCurrent(account, userId)) {
        setState(() => _revokingClientId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final errorColor = Theme.of(context).colorScheme.error;
    final agents = ref.watch(connectedAgentsProvider);
    final grants = ref.read(connectedAgentsProvider.notifier).grants;
    return Column(
      key: const Key('connected-agents-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.settingsConnectedAgentsTitle,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        if (agents.isLoading && grants == null)
          Semantics(
            key: const Key('connected-agents-loading'),
            liveRegion: true,
            child: Row(
              children: [
                const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(l10n.settingsConnectedAgentsLoading)),
              ],
            ),
          )
        else if (agents.hasError && grants == null)
          _ConnectedAgentsError(
            retryKey: const Key('connected-agents-retry'),
            onRetry: _load,
          )
        else if (grants?.isEmpty ?? true)
          Text(
            key: const Key('connected-agents-empty'),
            l10n.settingsConnectedAgentsEmpty,
          )
        else ...[
          for (final grant in grants!)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(LucideIcons.bot),
              title: Text(
                grant.clientName?.trim().isNotEmpty == true
                    ? grant.clientName!.trim()
                    : l10n.settingsConnectedAgentsUnknownClient,
              ),
              subtitle: Text(
                l10n.settingsConnectedAgentsConnectedOn(
                  formatLocalDate(context, grant.connectedAt.toLocal()),
                ),
              ),
              trailing: IconButton(
                key: Key('connected-agent-revoke-${grant.clientId}'),
                tooltip: l10n.settingsConnectedAgentsRevoke,
                onPressed: _revokingClientId == null
                    ? () => _confirmRevoke(grant)
                    : null,
                icon: _revokingClientId == grant.clientId
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(LucideIcons.unlink),
              ),
            ),
        ],
        if (agents.hasError && grants != null) ...[
          const SizedBox(height: 8),
          _ConnectedAgentsError(
            retryKey: const Key('connected-agents-retry'),
            onRetry: _load,
          ),
        ],
        if (_revokeError != null) ...[
          const SizedBox(height: 8),
          Semantics(
            key: const Key('connected-agent-revoke-error'),
            liveRegion: true,
            child: Text(
              l10n.settingsConnectedAgentsRevokeError,
              style: TextStyle(color: errorColor),
            ),
          ),
        ],
      ],
    );
  }
}

class _ConnectedAgentsError extends StatelessWidget {
  const _ConnectedAgentsError({required this.retryKey, required this.onRetry});

  final Key retryKey;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Semantics(
      key: const Key('connected-agents-error'),
      liveRegion: true,
      child: Row(
        children: [
          Expanded(child: Text(l10n.settingsConnectedAgentsLoadError)),
          ShadButton.ghost(
            height: 48,
            key: retryKey,
            onPressed: onRetry,
            leading: const Icon(LucideIcons.refreshCw),
            child: Text(l10n.commonRetry),
          ),
        ],
      ),
    );
  }
}
