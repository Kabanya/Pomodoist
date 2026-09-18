import 'dart:async';

import 'package:app_account/app_account.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons, ShadButton;

import '../../../app/config/account_providers.dart';
import '../../../app/config/app_l10n.dart';
import '../../../app/config/legal_urls.dart';
import '../../../app/config/providers.dart';
import '../../../app/theme/app_motion.dart';

class AccountDeleteDialog extends ConsumerStatefulWidget {
  const AccountDeleteDialog({required this.account, super.key});

  final AccountClient account;

  @override
  ConsumerState<AccountDeleteDialog> createState() =>
      _AccountDeleteDialogState();
}

class _AccountDeleteDialogState extends ConsumerState<AccountDeleteDialog> {
  var _submitting = false;
  Object? _error;

  Future<void> _deleteAccount() async {
    if (_submitting || !await _confirmAccountDeletion() || !mounted) return;
    final db = ref.read(appDatabaseProvider);
    final requestTimeout = ref.read(accountRequestTimeoutProvider);
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final response = await widget.account
          .invokeFunction('account-delete', body: const {'confirm': true})
          .timeout(requestTimeout);
      final data = response.data;
      if (data is! Map || data['deleted'] != true) {
        throw StateError('Account deletion was not confirmed by the server.');
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = error;
        });
      }
      return;
    }

    Object? cleanupError;
    try {
      await db.resetAccountData();
    } on Object catch (error) {
      cleanupError = error;
    }
    try {
      await widget.account.signOut();
    } on Object catch (error) {
      cleanupError ??= error;
    }

    if (!mounted) return;
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.maybeOf(context);
    Navigator.of(context).pop();
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          cleanupError == null
              ? l10n.accountDeleted
              : l10n.accountDeletedLocalCleanupError,
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
              enabled: !_submitting,
              onPressed: _submitting
                  ? null
                  : () =>
                        unawaited(launchPomodoistExternalUrl(appleAccountUrl)),
              leading: const Icon(LucideIcons.externalLink),
              child: Flexible(child: Text(l10n.manageSignInWithApple)),
            ),
            if (_error case final error?) ...[
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
            enabled: !_submitting,
            onPressed: _submitting ? null : () => Navigator.of(context).pop(),
            child: Text(l10n.commonCancel),
          ),
          ShadButton.destructive(
            height: 48,
            key: const Key('account-delete-confirm-button'),
            backgroundColor: colors.error,
            foregroundColor: colors.onError,
            enabled: !_submitting,
            onPressed: _submitting ? null : _deleteAccount,
            leading: _submitting
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
