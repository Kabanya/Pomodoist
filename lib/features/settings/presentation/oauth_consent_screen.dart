import 'dart:async';

import 'package:app_account/app_account.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/account_providers.dart';
import '../../../app/app_l10n.dart';
import '../../../app/captcha_handoff.dart';

enum _ConsentAction { idle, approving, denying, redirecting }

class OAuthConsentScreen extends ConsumerStatefulWidget {
  const OAuthConsentScreen({
    required this.uri,
    this.replaceLocation,
    super.key,
  });

  final Uri uri;
  final void Function(String value)? replaceLocation;

  @override
  ConsumerState<OAuthConsentScreen> createState() => _OAuthConsentScreenState();
}

class _OAuthConsentScreenState extends ConsumerState<OAuthConsentScreen> {
  AccountOAuthAuthorization? _authorization;
  AccountClient? _authorizationAccount;
  String? _authorizationUserId;
  Object? _loadError;
  Object? _actionError;
  bool _redirectError = false;
  _ConsentAction _action = _ConsentAction.idle;

  List<String> get _authorizationIds =>
      widget.uri.queryParametersAll['authorization_id'] ?? const [];

  bool get _validAuthorizationId =>
      _authorizationIds.length == 1 &&
      _authorizationIds.single.isNotEmpty &&
      !RegExp(r'\s').hasMatch(_authorizationIds.single);

  @override
  void initState() {
    super.initState();
    if (_validAuthorizationId) _load();
  }

  Future<void> _load() async {
    final account = ref.read(accountClientProvider);
    final userId = account?.currentUserId;
    if (account == null || userId == null || !_sameIdentity(account, userId)) {
      setState(() => _loadError = StateError('Account unavailable'));
      return;
    }
    _authorizationAccount = account;
    _authorizationUserId = userId;
    try {
      final authorization = await account.getOAuthAuthorization(
        _authorizationIds.single,
      );
      if (!mounted || !_sameIdentity(account, userId)) return;
      setState(() => _authorization = authorization);
      if (authorization case final AccountOAuthAuthorizationRedirect redirect) {
        setState(() => _action = _ConsentAction.redirecting);
        _handoff(redirect.redirectUrl);
      }
    } on Object catch (error) {
      if (mounted) setState(() => _loadError = error);
    }
  }

  void _retry() {
    setState(() => _loadError = null);
    unawaited(_load());
  }

  void _handoff(String? value) {
    if (!_safeRedirect(value)) {
      setState(() => _redirectError = true);
      return;
    }
    try {
      (widget.replaceLocation ?? replaceWithOAuthRedirect)(value!);
    } on Object {
      if (mounted) setState(() => _redirectError = true);
    }
  }

  Future<void> _submit(bool approve) async {
    if (_action != _ConsentAction.idle) return;
    final authorization = _authorization;
    if (authorization is! AccountOAuthAuthorizationDetails) return;
    final account = ref.read(accountClientProvider);
    final userId = _authorizationUserId;
    if (account == null ||
        userId == null ||
        !identical(account, _authorizationAccount) ||
        !_sameIdentity(account, userId)) {
      setState(() => _actionError = StateError('Account unavailable'));
      return;
    }
    setState(() {
      _action = approve ? _ConsentAction.approving : _ConsentAction.denying;
      _actionError = null;
      _redirectError = false;
    });
    try {
      final result = approve
          ? await account.approveOAuthAuthorization(
              authorization.authorizationId,
            )
          : await account.denyOAuthAuthorization(authorization.authorizationId);
      if (!mounted || !_sameIdentity(account, userId)) return;
      setState(() => _action = _ConsentAction.redirecting);
      _handoff(result.redirectUrl);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _action = _ConsentAction.idle;
        _actionError = error;
      });
    }
  }

  bool _sameIdentity(AccountClient account, String userId) {
    final sessionUserId = ref
        .read(accountAuthStateProvider)
        .value
        ?.session
        ?.userId;
    return identical(ref.read(accountClientProvider), account) &&
        account.currentUserId == userId &&
        (sessionUserId == null || sessionUserId == userId);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (!_validAuthorizationId) {
      return _ConsentFrame(
        child: Text(
          l10n.oauthConsentInvalidAuthorization,
          key: const Key('oauth-consent-invalid-authorization'),
        ),
      );
    }
    if (_loadError != null) {
      return _ConsentFrame(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              liveRegion: true,
              child: Text(
                l10n.oauthConsentLoadError,
                key: const Key('oauth-consent-load-error'),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              key: const Key('oauth-consent-retry'),
              onPressed: _retry,
              child: Text(l10n.commonRetry),
            ),
          ],
        ),
      );
    }
    final authorization = _authorization;
    if (authorization == null) {
      return _ConsentFrame(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(key: Key('oauth-consent-loading')),
            const SizedBox(height: 12),
            Text(l10n.oauthConsentLoading),
          ],
        ),
      );
    }
    if (authorization case final AccountOAuthAuthorizationDetails details) {
      final clientName = details.clientName?.trim();
      final unsupportedScopes = details.scopes.any(
        const {'openid', 'profile', 'phone'}.contains,
      );
      return _ConsentFrame(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    l10n.oauthConsentTitle,
                    key: const Key('oauth-consent-heading'),
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.oauthConsentClientRequest(
                    clientName == null || clientName.isEmpty
                        ? l10n.oauthConsentClientFallback
                        : clientName,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  clientName == null || clientName.isEmpty
                      ? l10n.oauthConsentClientFallback
                      : clientName,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.oauthConsentRedirectOrigin,
                  style: Theme.of(context).textTheme.labelMedium,
                  textAlign: TextAlign.center,
                ),
                Text(
                  _displayOrigin(details.redirectUri),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                _CapabilitySection(
                  key: const Key('oauth-consent-capabilities'),
                  title: l10n.oauthConsentCapabilitiesTitle,
                  icon: Icons.check_circle_outline,
                  items: [
                    l10n.oauthConsentManagePlanning,
                    l10n.oauthConsentReadInsights,
                  ],
                ),
                const SizedBox(height: 16),
                _CapabilitySection(
                  key: const Key('oauth-consent-unavailable'),
                  title: l10n.oauthConsentUnavailableTitle,
                  icon: Icons.block_outlined,
                  items: [l10n.oauthConsentUnavailable],
                ),
                if (unsupportedScopes) ...[
                  const SizedBox(height: 16),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      l10n.oauthConsentUnsupportedScopes,
                      key: const Key('oauth-consent-unsupported-scopes'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
                if (_actionError != null || _redirectError) ...[
                  const SizedBox(height: 16),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _redirectError
                          ? l10n.oauthConsentRedirectError
                          : l10n.oauthConsentActionError,
                      key: Key(
                        _redirectError
                            ? 'oauth-consent-redirect-error'
                            : 'oauth-consent-action-error',
                      ),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  key: const Key('oauth-consent-approve'),
                  onPressed: unsupportedScopes || _action != _ConsentAction.idle
                      ? null
                      : () => unawaited(_submit(true)),
                  child: Text(
                    _action == _ConsentAction.approving
                        ? l10n.oauthConsentApproving
                        : _action == _ConsentAction.redirecting
                        ? l10n.oauthConsentRedirecting
                        : l10n.oauthConsentApprove,
                    key: switch (_action) {
                      _ConsentAction.approving => const Key(
                        'oauth-consent-approving',
                      ),
                      _ConsentAction.redirecting => const Key(
                        'oauth-consent-redirecting',
                      ),
                      _ => null,
                    },
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  key: const Key('oauth-consent-deny'),
                  onPressed: _action == _ConsentAction.idle
                      ? () => unawaited(_submit(false))
                      : null,
                  child: Text(
                    _action == _ConsentAction.denying
                        ? l10n.oauthConsentDenying
                        : l10n.oauthConsentDeny,
                    key: _action == _ConsentAction.denying
                        ? const Key('oauth-consent-denying')
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return _ConsentFrame(
      child: Semantics(
        liveRegion: true,
        child: Text(
          _redirectError
              ? l10n.oauthConsentRedirectError
              : l10n.oauthConsentRedirecting,
          key: Key(
            _redirectError
                ? 'oauth-consent-redirect-error'
                : 'oauth-consent-redirecting',
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _ConsentFrame extends StatelessWidget {
  const _ConsentFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('oauth-consent-screen'),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _CapabilitySection extends StatelessWidget {
  const _CapabilitySection({
    required this.title,
    required this.icon,
    required this.items,
    super.key,
  });

  final String title;
  final IconData icon;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(item)),
              ],
            ),
          ),
      ],
    );
  }
}

String _displayOrigin(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null || !uri.hasScheme) return '—';
  if (uri.scheme == 'http' || uri.scheme == 'https') {
    return uri.host.isEmpty ? '—' : uri.origin;
  }
  return uri.authority.isEmpty
      ? '${uri.scheme}:'
      : '${uri.scheme}://${uri.authority}';
}

bool _safeRedirect(String? value) {
  if (value == null || value.trim().isEmpty) return false;
  final uri = Uri.tryParse(value);
  if (uri == null || !uri.isAbsolute) return false;
  final scheme = uri.scheme.toLowerCase();
  if (scheme == 'javascript' || scheme == 'data') return false;
  return (scheme != 'http' && scheme != 'https') || uri.host.isNotEmpty;
}
