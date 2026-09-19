import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons, ShadButton;

import 'package:pomodoist/ui/settings/view_models/account_delete_view_model.dart';
import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/platform/legal_urls.dart';
import 'package:pomodoist/ui/core/themes/app_motion.dart';

class AccountDeleteDialog extends ConsumerStatefulWidget {
  const AccountDeleteDialog({super.key});

  @override
  ConsumerState<AccountDeleteDialog> createState() =>
      _AccountDeleteDialogState();
}

class _AccountDeleteDialogState extends ConsumerState<AccountDeleteDialog> {
  late AsyncValue<bool?> _state;

  Future<void> _deleteAccount() async {
    if (_state.isLoading || !await _confirmAccountDeletion() || !mounted) {
      return;
    }
    final cleanupFailed = await ref
        .read(accountDeleteViewModelProvider.notifier)
        .delete();
    if (!mounted || cleanupFailed == null) return;
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.maybeOf(context);
    Navigator.of(context).pop();
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          cleanupFailed
              ? l10n.accountDeletedLocalCleanupError
              : l10n.accountDeleted,
        ),
      ),
    );
  }

  Future<bool> _confirmAccountDeletion() async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          animationStyle: AnimationStyle(
            duration: AppMotion.duration(context, AppMotion.popup),
            reverseDuration: AppMotion.duration(context, AppMotion.popup),
            curve: AppMotion.curve,
          ),
          builder: (dialogContext) {
            final colors = Theme.of(dialogContext).colorScheme;
            final l10n = dialogContext.l10n;
            return PopScope(
              canPop: false,
              child: AlertDialog(
                scrollable: true,
                constraints: const BoxConstraints(maxWidth: 560),
                key: const Key('account-delete-final-dialog'),
                title: Text(l10n.deleteAccount),
                content: Text(l10n.deleteAccountFinalConfirmation),
                actions: [
                  ShadButton.ghost(
                    height: 48,
                    key: const Key('account-delete-final-cancel-button'),
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: Text(l10n.commonCancel),
                  ),
                  ShadButton.destructive(
                    height: 48,
                    key: const Key('account-delete-final-confirm-button'),
                    backgroundColor: colors.error,
                    foregroundColor: colors.onError,
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    leading: const Icon(LucideIcons.trash2),
                    child: Text(l10n.deleteAccount),
                  ),
                ],
              ),
            );
          },
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    _state = ref.watch(accountDeleteViewModelProvider);
    final l10n = context.l10n;
    final colors = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      child: AlertDialog(
        key: const Key('account-delete-dialog'),
        scrollable: true,
        constraints: const BoxConstraints(maxWidth: 560),
        title: Text(l10n.deleteAccount),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.deleteAccountConfirmation),
            const SizedBox(height: 8),
            ShadButton.ghost(
              key: const Key('account-delete-manage-apple-button'),
              height: 0,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              enabled: !_state.isLoading,
              onPressed: _state.isLoading
                  ? null
                  : () =>
                        unawaited(launchPomodoistExternalUrl(appleAccountUrl)),
              leading: const Icon(LucideIcons.externalLink),
              child: Flexible(child: Text(l10n.manageSignInWithApple)),
            ),
            if (_state.error case final error?) ...[
              const SizedBox(height: 12),
              Semantics(
                key: const Key('account-delete-error'),
                liveRegion: true,
                child: Text(
                  l10n.deleteAccountError(error),
                  style: TextStyle(color: colors.error),
                ),
              ),
            ],
          ],
        ),
        actions: [
          ShadButton.ghost(
            height: 48,
            key: const Key('account-delete-cancel-button'),
            enabled: !_state.isLoading,
            onPressed: _state.isLoading
                ? null
                : () => Navigator.of(context).pop(),
            child: Text(l10n.commonCancel),
          ),
          ShadButton.destructive(
            height: 48,
            key: const Key('account-delete-confirm-button'),
            backgroundColor: colors.error,
            foregroundColor: colors.onError,
            enabled: !_state.isLoading,
            onPressed: _state.isLoading ? null : _deleteAccount,
            leading: _state.isLoading
                ? SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.onError,
                    ),
                  )
                : const Icon(LucideIcons.trash2),
            child: Text(l10n.deleteAccount),
          ),
        ],
      ),
    );
  }
}
