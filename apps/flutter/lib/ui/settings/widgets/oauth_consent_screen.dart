import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons, ShadButton;

import 'package:pomodoist/ui/settings/view_models/oauth_consent_view_model.dart';
import 'package:pomodoist/domain/models/account/account_management.dart';
import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/auth/widgets/captcha_handoff.dart';

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
  late OAuthConsentState _state;
  OAuthConsentViewModel get _viewModel =>
      ref.read(oauthConsentViewModelProvider(widget.uri).notifier);
  void _retry() => _viewModel.reload();
  Future<void> _submit(bool approve) => _viewModel.submit(approve);

  @override
  Widget build(BuildContext context) {
    _state = ref.watch(oauthConsentViewModelProvider(widget.uri));
    ref.listen(oauthConsentViewModelProvider(widget.uri), (_, next) {
      if (next.redirectUrl case final url?) {
        try {
          (widget.replaceLocation ?? replaceWithOAuthRedirect)(url);
        } catch (_) {
          _viewModel.handoffFailed();
        }
      }
    });
    final l10n = context.l10n;
    if (!_state.valid) {
      return _ConsentFrame(
        child: Text(
          l10n.oauthConsentInvalidAuthorization,
          key: const Key('oauth-consent-invalid-authorization'),
        ),
      );
    }
    if (_state.loadError != null) {
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
            ShadButton.outline(
              key: const Key('oauth-consent-retry'),
              onPressed: _retry,
              child: Text(l10n.commonRetry),
            ),
          ],
        ),
      );
    }
    final authorization = _state.authorization;
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
    if (authorization case final OAuthAuthorizationDetails details) {
      final clientName = details.clientName?.trim();
      final unsupportedScopes = details.unsupportedScopes;
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
                  icon: LucideIcons.circleCheck,
                  items: [
                    l10n.oauthConsentManagePlanning,
                    l10n.oauthConsentReadInsights,
                  ],
                ),
                const SizedBox(height: 16),
                _CapabilitySection(
                  key: const Key('oauth-consent-unavailable'),
                  title: l10n.oauthConsentUnavailableTitle,
                  icon: LucideIcons.ban,
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
                if (_state.actionError != null || _state.redirectError) ...[
                  const SizedBox(height: 16),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _state.redirectError
                          ? l10n.oauthConsentRedirectError
                          : l10n.oauthConsentActionError,
                      key: Key(
                        _state.redirectError
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
                ShadButton(
                  key: const Key('oauth-consent-approve'),
                  enabled:
                      !(unsupportedScopes ||
                          _state.action != ConsentAction.idle),
                  onPressed:
                      unsupportedScopes || _state.action != ConsentAction.idle
                      ? null
                      : () => unawaited(_submit(true)),
                  child: Text(
                    _state.action == ConsentAction.approving
                        ? l10n.oauthConsentApproving
                        : _state.action == ConsentAction.redirecting
                        ? l10n.oauthConsentRedirecting
                        : l10n.oauthConsentApprove,
                    key: switch (_state.action) {
                      ConsentAction.approving => const Key(
                        'oauth-consent-approving',
                      ),
                      ConsentAction.redirecting => const Key(
                        'oauth-consent-redirecting',
                      ),
                      _ => null,
                    },
                  ),
                ),
                const SizedBox(height: 8),
                ShadButton.outline(
                  key: const Key('oauth-consent-deny'),
                  enabled: _state.action == ConsentAction.idle,
                  onPressed: _state.action == ConsentAction.idle
                      ? () => unawaited(_submit(false))
                      : null,
                  child: Text(
                    _state.action == ConsentAction.denying
                        ? l10n.oauthConsentDenying
                        : l10n.oauthConsentDeny,
                    key: _state.action == ConsentAction.denying
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
          _state.redirectError
              ? l10n.oauthConsentRedirectError
              : l10n.oauthConsentRedirecting,
          key: Key(
            _state.redirectError
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
