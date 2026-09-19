import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons, ShadButton;

import 'package:pomodoist/ui/settings/view_models/connected_agents_view_model.dart';
import 'package:pomodoist/domain/models/account/account_management.dart';
import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/localization/formatters.dart';
import 'package:pomodoist/ui/core/themes/app_motion.dart';

class ConnectedAgentsSection extends ConsumerStatefulWidget {
  const ConnectedAgentsSection({super.key});

  @override
  ConsumerState<ConnectedAgentsSection> createState() =>
      _ConnectedAgentsSectionState();
}

class _ConnectedAgentsSectionState
    extends ConsumerState<ConnectedAgentsSection> {
  late ConnectedAgentsState _state;
  BuildContext? _confirmationContext;
  ConnectedAgentsViewModel get _viewModel =>
      ref.read(connectedAgentsViewModelProvider.notifier);

  @override
  void dispose() {
    _dismissConfirmation();
    super.dispose();
  }

  void _dismissConfirmation() {
    final dialogContext = _confirmationContext;
    _confirmationContext = null;
    if (dialogContext == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (dialogContext.mounted) Navigator.of(dialogContext).pop(false);
    });
  }

  Future<void> _load() => _viewModel.refresh();

  Future<void> _confirmRevoke(ConnectedAgent grant) async {
    if (_state.revokingClientId != null) return;
    final userId = _state.userId;
    if (userId == null) return;
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
    if (!confirmed || !mounted) return;
    await _viewModel.revoke(grant.clientId, userId);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final errorColor = Theme.of(context).colorScheme.error;
    final agents = _state = ref.watch(connectedAgentsViewModelProvider);
    ref.listen(connectedAgentsViewModelProvider, (previous, next) {
      if (previous?.userId != next.userId) _dismissConfirmation();
    });
    final grants = agents.grants;
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
                onPressed: _state.revokingClientId == null
                    ? () => _confirmRevoke(grant)
                    : null,
                icon: _state.revokingClientId == grant.clientId
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
        if (_state.revokeError != null) ...[
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
