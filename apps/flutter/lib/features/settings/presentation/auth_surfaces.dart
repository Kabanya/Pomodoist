import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons, ShadButton;

import '../../../app/auth/account_auth_feedback.dart';
import '../../../app/config/account_providers.dart';
import '../../../app/config/app_l10n.dart';

String loginRedirectFor(String returnTo) =>
    accountAuthRedirect(pomodoistLoginRedirect, returnTo);

String authRoute(String path, String returnTo) {
  if (returnTo == '/today') {
    return path;
  }
  return Uri(path: path, queryParameters: {'returnTo': returnTo}).toString();
}

class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    required this.footer,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  child,
                  const SizedBox(height: 12),
                  footer,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AuthRouteLink extends StatelessWidget {
  const AuthRouteLink({
    super.key,
    required this.prompt,
    required this.action,
    required this.route,
    required this.buttonKey,
  });

  final String prompt;
  final String action;
  final String route;
  final Key buttonKey;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      children: [
        Text(prompt),
        ShadButton.outline(
          key: buttonKey,
          onPressed: () => context.go(route),
          child: Text(action),
        ),
      ],
    );
  }
}

class AccountErrorCard extends StatelessWidget {
  const AccountErrorCard({
    required this.error,
    required this.retryKey,
    required this.onRetry,
    super.key,
  });

  final Object error;
  final Key retryKey;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final feedback = presentAccountAuthFailure(
      l10n,
      classifyAccountAuthFailure(
        error,
        operation: AccountAuthOperation.bootstrap,
      ),
      operation: AccountAuthOperation.bootstrap,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(liveRegion: true, child: Text(feedback.message)),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: ShadButton.ghost(
                key: retryKey,
                onPressed: onRetry,
                leading: const Icon(LucideIcons.refreshCw),
                child: Text(l10n.commonRetry),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AuthUnavailableCard extends StatelessWidget {
  const AuthUnavailableCard({
    super.key,
    required this.retryKey,
    required this.onRetry,
  });

  final Key retryKey;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              liveRegion: true,
              child: Text(
                context.l10n.authServiceUnavailable,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: ShadButton.ghost(
                key: retryKey,
                onPressed: onRetry,
                leading: const Icon(LucideIcons.refreshCw),
                child: Text(context.l10n.commonRetry),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AuthFailureNoticeCard extends StatelessWidget {
  const AuthFailureNoticeCard({
    super.key,
    required this.failure,
    required this.onSendNewLink,
  });

  final AccountAuthFailure failure;
  final VoidCallback? onSendNewLink;

  @override
  Widget build(BuildContext context) {
    final feedback = presentAccountAuthFailure(
      context.l10n,
      failure,
      operation: AccountAuthOperation.callback,
    );
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              key: const Key('login-auth-callback-error'),
              liveRegion: true,
              child: Text(
                feedback.message,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
            if (feedback.recovery == AccountAuthRecovery.sendNewLink &&
                onSendNewLink != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: ShadButton.ghost(
                  key: const Key('login-auth-send-new-link'),
                  enabled: onSendNewLink != null,
                  onPressed: onSendNewLink,
                  child: Text(context.l10n.authSendLink),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
