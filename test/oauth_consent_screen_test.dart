import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:app_account/app_account.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/account_providers.dart';
import 'package:pomodoist/features/settings/presentation/oauth_consent_screen.dart';
import 'package:pomodoist/features/settings/presentation/settings_screen.dart';
import 'package:pomodoist/l10n/app_localizations.dart';

void main() {
  testWidgets('missing, blank, and duplicate authorization IDs are rejected', (
    tester,
  ) async {
    for (final uri in [
      Uri.parse('/oauth/consent'),
      Uri.parse('/oauth/consent?authorization_id='),
      Uri.parse('/oauth/consent?authorization_id=pending%20id'),
      Uri.parse(
        '/oauth/consent?authorization_id=first&authorization_id=second',
      ),
    ]) {
      final account = _OAuthAccount();
      await _pumpConsent(tester, account: account, uri: uri);

      expect(
        find.byKey(const Key('oauth-consent-invalid-authorization')),
        findsOneWidget,
        reason: uri.toString(),
      );
      expect(account.getCalls, isEmpty, reason: uri.toString());
    }
  });

  testWidgets('valid authorization ID loads once and exposes loading state', (
    tester,
  ) async {
    final pending = Completer<AccountOAuthAuthorization>();
    final account = _OAuthAccount(authorization: pending.future);

    await _pumpConsent(
      tester,
      account: account,
      uri: Uri.parse('/oauth/consent?authorization_id=pending-id'),
    );

    expect(account.getCalls, ['pending-id']);
    expect(find.byKey(const Key('oauth-consent-loading')), findsOneWidget);

    pending.complete(
      AccountOAuthAuthorizationDetails(
        authorizationId: 'pending-id',
        clientId: 'client-id',
        clientName: 'MCP Inspector',
        redirectUri: 'http://127.0.0.1:6274/oauth/callback',
        scopes: const ['pomodoist'],
      ),
    );
    await tester.pumpAndSettle();

    expect(account.getCalls, ['pending-id']);
  });

  testWidgets('pending consent presents the fixed V1 capability boundary', (
    tester,
  ) async {
    final account = _OAuthAccount(
      authorization: Future.value(
        AccountOAuthAuthorizationDetails(
          authorizationId: 'pending-id',
          clientId: 'client-id',
          clientName: 'MCP Inspector',
          redirectUri: 'http://127.0.0.1:6274/oauth/callback',
          scopes: const ['pomodoist'],
        ),
      ),
    );

    await _pumpConsent(
      tester,
      account: account,
      uri: Uri.parse('/oauth/consent?authorization_id=pending-id'),
    );
    await tester.pumpAndSettle();

    expect(find.text('MCP Inspector'), findsOneWidget);
    expect(find.text('http://127.0.0.1:6274'), findsOneWidget);
    expect(find.byKey(const Key('oauth-consent-capabilities')), findsOneWidget);
    expect(find.byKey(const Key('oauth-consent-unavailable')), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('oauth-consent-approve')))
          .onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('oauth-consent-deny')))
          .onPressed,
      isNotNull,
    );
    final heading = tester.getSemantics(
      find.byKey(const Key('oauth-consent-heading')),
    );
    expect(heading.flagsCollection.isHeader, isTrue);
    final approve = tester.getSemantics(
      find.byKey(const Key('oauth-consent-approve')),
    );
    expect(approve.flagsCollection.isButton, isTrue);
    expect(approve.flagsCollection.isEnabled, Tristate.isTrue);
  });

  testWidgets('account identity scopes cannot be approved', (tester) async {
    for (final forbiddenScope in ['openid', 'profile', 'phone']) {
      final account = _OAuthAccount(
        authorization: Future.value(
          AccountOAuthAuthorizationDetails(
            authorizationId: 'pending-id',
            clientId: 'client-id',
            clientName: 'MCP Inspector',
            redirectUri: 'https://agent.test/callback',
            scopes: [forbiddenScope],
          ),
        ),
      );

      await _pumpConsent(
        tester,
        account: account,
        uri: Uri.parse('/oauth/consent?authorization_id=pending-id'),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('oauth-consent-unsupported-scopes')),
        findsOneWidget,
        reason: forbiddenScope,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('oauth-consent-approve')),
            )
            .onPressed,
        isNull,
        reason: forbiddenScope,
      );
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('oauth-consent-deny')))
            .onPressed,
        isNotNull,
        reason: forbiddenScope,
      );
      expect(account.approveCalls, isEmpty, reason: forbiddenScope);
    }
  });

  testWidgets('failed authorization details can be retried', (tester) async {
    var attempt = 0;
    final account = _OAuthAccount(
      onGet: (_) {
        attempt += 1;
        if (attempt == 1) return Future.error(StateError('temporarily down'));
        return Future.value(
          AccountOAuthAuthorizationDetails(
            authorizationId: 'pending-id',
            clientId: 'client-id',
            clientName: 'Recovered agent',
            redirectUri: 'https://agent.test/callback',
            scopes: const ['pomodoist'],
          ),
        );
      },
    );

    await _pumpConsent(
      tester,
      account: account,
      uri: Uri.parse('/oauth/consent?authorization_id=pending-id'),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('oauth-consent-load-error')), findsOneWidget);
    expect(account.getCalls, ['pending-id']);

    await tester.tap(find.byKey(const Key('oauth-consent-retry')));
    await tester.pumpAndSettle();

    expect(account.getCalls, ['pending-id', 'pending-id']);
    expect(find.text('Recovered agent'), findsOneWidget);
  });

  testWidgets('already-consented response hands off the opaque redirect', (
    tester,
  ) async {
    const redirect = 'pomodoist-agent://callback?code=a%2Fb&state=x+y%2520z';
    final account = _OAuthAccount(
      authorization: Future.value(
        const AccountOAuthAuthorizationRedirect(redirectUrl: redirect),
      ),
    );
    String? handedOff;

    await _pumpConsent(
      tester,
      account: account,
      uri: Uri.parse('/oauth/consent?authorization_id=redirect-id'),
      replaceLocation: (value) => handedOff = value,
    );
    await tester.pumpAndSettle();

    expect(handedOff, redirect);
    expect(find.byKey(const Key('oauth-consent-redirecting')), findsOneWidget);
  });

  testWidgets('late redirect from another account is ignored', (tester) async {
    final authorization = Completer<AccountOAuthAuthorization>();
    final account = _OAuthAccount(authorization: authorization.future);
    final handedOff = <String>[];

    await _pumpConsent(
      tester,
      account: account,
      uri: Uri.parse('/oauth/consent?authorization_id=redirect-id'),
      replaceLocation: handedOff.add,
    );

    account.userId = 'user-2';
    authorization.complete(
      const AccountOAuthAuthorizationRedirect(
        redirectUrl: 'https://agent-a.test/callback',
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(handedOff, isEmpty);
    expect(find.byKey(const Key('oauth-consent-loading')), findsOneWidget);
  });

  testWidgets('approve is single-flight and hands off its exact redirect', (
    tester,
  ) async {
    final approval = Completer<AccountOAuthConsentResult>();
    final account = _OAuthAccount(
      authorization: Future.value(_pendingDetails()),
      onApprove: (_) => approval.future,
    );
    String? handedOff;
    await _pumpConsent(
      tester,
      account: account,
      uri: Uri.parse('/oauth/consent?authorization_id=pending-id'),
      replaceLocation: (value) => handedOff = value,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('oauth-consent-approve')));
    await tester.pump();

    expect(account.approveCalls, ['pending-id']);
    expect(account.denyCalls, isEmpty);
    expect(find.byKey(const Key('oauth-consent-approving')), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('oauth-consent-deny')))
          .onPressed,
      isNull,
    );

    await tester.tap(
      find.byKey(const Key('oauth-consent-approve')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(account.approveCalls, ['pending-id']);

    const redirect = 'https://agent.test/callback?code=a%2Fb&state=x+y';
    approval.complete(const AccountOAuthConsentResult(redirectUrl: redirect));
    await tester.pumpAndSettle();

    expect(handedOff, redirect);
    expect(find.byKey(const Key('oauth-consent-redirecting')), findsOneWidget);
  });

  testWidgets('deny failure is recoverable and retry hands off exactly', (
    tester,
  ) async {
    final firstDenial = Completer<AccountOAuthConsentResult>();
    var attempt = 0;
    const redirect = 'pomodoist-agent://callback?error=access_denied&state=x+y';
    final account = _OAuthAccount(
      authorization: Future.value(_pendingDetails()),
      onDeny: (_) {
        attempt += 1;
        return attempt == 1
            ? firstDenial.future
            : Future.value(
                const AccountOAuthConsentResult(redirectUrl: redirect),
              );
      },
    );
    String? handedOff;
    await _pumpConsent(
      tester,
      account: account,
      uri: Uri.parse('/oauth/consent?authorization_id=pending-id'),
      replaceLocation: (value) => handedOff = value,
    );
    await tester.pumpAndSettle();

    final denyButton = find.byKey(const Key('oauth-consent-deny'));
    await tester.ensureVisible(denyButton);
    await tester.tap(denyButton);
    await tester.pump();

    expect(account.denyCalls, ['pending-id']);
    expect(account.approveCalls, isEmpty);
    expect(find.byKey(const Key('oauth-consent-denying')), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('oauth-consent-approve')))
          .onPressed,
      isNull,
    );
    await tester.tap(denyButton, warnIfMissed: false);
    expect(account.denyCalls, ['pending-id']);

    firstDenial.completeError(StateError('temporarily down'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('oauth-consent-action-error')), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('oauth-consent-deny')))
          .onPressed,
      isNotNull,
    );

    await tester.ensureVisible(denyButton);
    await tester.tap(denyButton);
    await tester.pumpAndSettle();

    expect(account.denyCalls, ['pending-id', 'pending-id']);
    expect(handedOff, redirect);
    expect(find.byKey(const Key('oauth-consent-redirecting')), findsOneWidget);
  });

  testWidgets('unsafe or relative redirects stay on the consent page', (
    tester,
  ) async {
    for (final redirect in [
      '',
      ' JAVASCRIPT:alert(1)',
      '/relative/callback',
      'javascript:alert(1)',
      'data:text/html,blocked',
      'https:/missing-host',
    ]) {
      final account = _OAuthAccount(
        authorization: Future.value(
          AccountOAuthAuthorizationRedirect(redirectUrl: redirect),
        ),
      );
      final handedOff = <String>[];
      await _pumpConsent(
        tester,
        account: account,
        uri: Uri.parse('/oauth/consent?authorization_id=redirect-id'),
        replaceLocation: handedOff.add,
      );
      await tester.pumpAndSettle();

      expect(handedOff, isEmpty, reason: redirect);
      expect(
        find.byKey(const Key('oauth-consent-redirect-error')),
        findsOneWidget,
        reason: redirect,
      );
      expect(
        find.byKey(const Key('oauth-consent-screen')),
        findsOneWidget,
        reason: redirect,
      );
    }
  });

  testWidgets('web and registered agent redirects are handed off unchanged', (
    tester,
  ) async {
    for (final redirect in [
      'https://agent.test/callback?code=a%2Fb&state=x+y',
      'http://127.0.0.1:6274/oauth/callback?code=a%2Fb',
      'pomodoist-agent://callback?code=a%2Fb&state=x+y',
      'com.example.agent:/oauth/callback?code=a%2Fb',
    ]) {
      final account = _OAuthAccount(
        authorization: Future.value(
          AccountOAuthAuthorizationRedirect(redirectUrl: redirect),
        ),
      );
      final handedOff = <String>[];
      await _pumpConsent(
        tester,
        account: account,
        uri: Uri.parse('/oauth/consent?authorization_id=redirect-id'),
        replaceLocation: handedOff.add,
      );
      await tester.pumpAndSettle();

      expect(handedOff, [redirect], reason: redirect);
      expect(
        find.byKey(const Key('oauth-consent-redirecting')),
        findsOneWidget,
        reason: redirect,
      );
    }
  });

  testWidgets('deny with no redirect reports an error without navigating', (
    tester,
  ) async {
    final account = _OAuthAccount(
      authorization: Future.value(_pendingDetails()),
      onDeny: (_) async => const AccountOAuthConsentResult(),
    );
    final handedOff = <String>[];
    await _pumpConsent(
      tester,
      account: account,
      uri: Uri.parse('/oauth/consent?authorization_id=pending-id'),
      replaceLocation: handedOff.add,
    );
    await tester.pumpAndSettle();

    final denyButton = find.byKey(const Key('oauth-consent-deny'));
    await tester.ensureVisible(denyButton);
    await tester.tap(denyButton);
    await tester.pumpAndSettle();

    expect(account.denyCalls, ['pending-id']);
    expect(handedOff, isEmpty);
    expect(
      find.byKey(const Key('oauth-consent-redirect-error')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('oauth-consent-screen')), findsOneWidget);
  });

  testWidgets('browser handoff failure remains a visible page error', (
    tester,
  ) async {
    final account = _OAuthAccount(
      authorization: Future.value(
        const AccountOAuthAuthorizationRedirect(
          redirectUrl: 'https://agent.test/callback',
        ),
      ),
    );
    await _pumpConsent(
      tester,
      account: account,
      uri: Uri.parse('/oauth/consent?authorization_id=redirect-id'),
      replaceLocation: (_) => throw StateError('navigation blocked'),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('oauth-consent-redirect-error')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('oauth-consent-screen')), findsOneWidget);
  });

  testWidgets('social and magic-link auth preserve the consent returnTo', (
    tester,
  ) async {
    const returnTo = '/oauth/consent?authorization_id=a%2Fb%2Bc%2520d';
    const loginRedirect =
        'pomodoist://login-callback?returnTo=%2Foauth%2Fconsent%3F'
        'authorization_id%3Da%252Fb%252Bc%252520d';
    final account = _ReturnToAccount();
    await _pumpLogin(tester, account: account, returnTo: returnTo);

    await tester.tap(find.text('Apple'));
    await tester.pump();
    await tester.tap(find.text('Google'));
    await tester.pump();

    expect(account.appleRedirects, [loginRedirect]);
    expect(account.googleRedirects, [loginRedirect]);

    await tester.tap(find.text('Email'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('account-email-field')),
      'user@example.com',
    );
    await tester.pump();
    await tester.tap(find.text('Send link'));
    await tester.pumpAndSettle();

    expect(account.magicLinkRedirects, [loginRedirect]);

    await tester.tap(find.text('Email'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('account-auth-mode')),
        matching: find.text('Create account'),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('account-email-field')),
      'user@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('account-password-field')),
      'password',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pumpAndSettle();

    expect(account.signUpRedirects, [loginRedirect]);
  });
}

AccountOAuthAuthorizationDetails _pendingDetails({
  List<String> scopes = const ['pomodoist'],
}) {
  return AccountOAuthAuthorizationDetails(
    authorizationId: 'pending-id',
    clientId: 'client-id',
    clientName: 'MCP Inspector',
    redirectUri: 'https://agent.test/callback',
    scopes: scopes,
  );
}

Future<void> _pumpConsent(
  WidgetTester tester, {
  required _OAuthAccount account,
  required Uri uri,
  void Function(String value)? replaceLocation,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        accountClientProvider.overrideWithValue(account),
        accountAuthStateProvider.overrideWithValue(
          const AsyncData(
            AccountAuthState(
              signedIn: true,
              session: AccountSession(userId: 'user-1'),
            ),
          ),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: OAuthConsentScreen(uri: uri, replaceLocation: replaceLocation),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _pumpLogin(
  WidgetTester tester, {
  required _ReturnToAccount account,
  required String returnTo,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        accountClientProvider.overrideWithValue(account),
        accountAuthStateProvider.overrideWithValue(
          const AsyncData(AccountAuthState(signedIn: false)),
        ),
        accountOverviewProvider.overrideWith((ref) async => null),
      ],
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: LoginScreen(returnTo: returnTo),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _OAuthAccount implements AccountClient {
  _OAuthAccount({
    Future<AccountOAuthAuthorization>? authorization,
    this.onGet,
    this.onApprove,
    this.onDeny,
  }) : authorization =
           authorization ??
           Future.value(
             const AccountOAuthAuthorizationRedirect(
               redirectUrl: 'https://agent.test/callback',
             ),
           );

  final Future<AccountOAuthAuthorization> authorization;
  final Future<AccountOAuthAuthorization> Function(String authorizationId)?
  onGet;
  final Future<AccountOAuthConsentResult> Function(String authorizationId)?
  onApprove;
  final Future<AccountOAuthConsentResult> Function(String authorizationId)?
  onDeny;
  final List<String> getCalls = [];
  final List<String> approveCalls = [];
  final List<String> denyCalls = [];
  String? userId = 'user-1';

  @override
  String? get currentUserId => userId;

  @override
  Future<AccountOAuthAuthorization> getOAuthAuthorization(
    String authorizationId,
  ) async {
    getCalls.add(authorizationId);
    return onGet?.call(authorizationId) ?? authorization;
  }

  @override
  Future<AccountOAuthConsentResult> approveOAuthAuthorization(
    String authorizationId,
  ) {
    approveCalls.add(authorizationId);
    return onApprove?.call(authorizationId) ??
        Future.value(
          const AccountOAuthConsentResult(
            redirectUrl: 'https://agent.test/approved',
          ),
        );
  }

  @override
  Future<AccountOAuthConsentResult> denyOAuthAuthorization(
    String authorizationId,
  ) {
    denyCalls.add(authorizationId);
    return onDeny?.call(authorizationId) ??
        Future.value(
          const AccountOAuthConsentResult(
            redirectUrl: 'https://agent.test/denied',
          ),
        );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ReturnToAccount implements AccountClient {
  final appleRedirects = <String?>[];
  final googleRedirects = <String?>[];
  final magicLinkRedirects = <String?>[];
  final signUpRedirects = <String?>[];

  @override
  String? get currentUserId => null;

  @override
  Future<void> signInWithApple({String? redirectTo}) async {
    appleRedirects.add(redirectTo);
  }

  @override
  Future<void> signInWithGoogle({String? redirectTo}) async {
    googleRedirects.add(redirectTo);
  }

  @override
  Future<void> signInWithEmail(
    String email, {
    String? redirectTo,
    String? captchaToken,
  }) async {
    magicLinkRedirects.add(redirectTo);
  }

  @override
  Future<void> signUpWithPassword({
    required String email,
    required String password,
    String? redirectTo,
    String? captchaToken,
  }) async {
    signUpRedirects.add(redirectTo);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
