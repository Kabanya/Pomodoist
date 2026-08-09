import 'dart:async';

import 'package:app_account/app_account.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pomodoist/app/account_providers.dart';
import 'package:pomodoist/app/router.dart';

void main() {
  test('auth refresh keeps the active native route', () async {
    final authStates = StreamController<AccountAuthState>();
    final container = ProviderContainer(
      overrides: [
        accountClientProvider.overrideWithValue(null),
        accountAuthStateProvider.overrideWith((ref) => authStates.stream),
      ],
    );
    final subscription = container.listen(routerProvider, (_, _) {});
    addTearDown(() async {
      subscription.close();
      container.dispose();
      await authStates.close();
    });

    authStates.add(
      const AccountAuthState(
        signedIn: true,
        session: AccountSession(userId: 'user', accessToken: 'token-1'),
      ),
    );
    await pumpEventQueue();

    final router = container.read(routerProvider);
    router.go('/projects');

    authStates.add(
      const AccountAuthState(
        signedIn: true,
        session: AccountSession(userId: 'user', accessToken: 'token-2'),
      ),
    );
    await pumpEventQueue();

    expect(container.read(routerProvider), same(router));
    expect(_routerUri(router), '/projects');
  });

  testWidgets('login round trip preserves the exact local OAuth consent URI', (
    tester,
  ) async {
    final account = _MutableAccountClient()..userId = 'user';
    final container = ProviderContainer(
      overrides: [
        accountClientProvider.overrideWithValue(account),
        accountAuthStateProvider.overrideWithValue(const AsyncLoading()),
      ],
    );
    final subscription = container.listen(routerProvider, (_, _) {});
    addTearDown(() {
      subscription.close();
      container.dispose();
    });
    final router = container.read(routerProvider);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();

    router.go(
      '/login?returnTo=%2Foauth%2Fconsent%3Fauthorization_id%3D'
      'a%252Fb%252Bc%252520d',
    );
    await tester.pumpAndSettle();

    expect(
      _routerUri(router),
      '/oauth/consent?authorization_id=a%2Fb%2Bc%2520d',
    );
  });

  testWidgets(
    'same consent route reloads and submits the current authorization',
    (tester) async {
      final account = _MutableAccountClient()..userId = 'user';
      final container = ProviderContainer(
        overrides: [
          accountClientProvider.overrideWithValue(account),
          accountAuthStateProvider.overrideWithValue(const AsyncLoading()),
        ],
      );
      final subscription = container.listen(routerProvider, (_, _) {});
      addTearDown(() {
        subscription.close();
        container.dispose();
      });
      final router = container.read(routerProvider);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      router.go('/oauth/consent?authorization_id=A');
      await tester.pumpAndSettle();
      expect(account.getCalls, ['A']);
      expect(find.text('Agent A'), findsOneWidget);

      router.go('/oauth/consent?authorization_id=B');
      await tester.pumpAndSettle();
      expect(account.getCalls, ['A', 'B']);
      expect(find.text('Agent A'), findsNothing);
      expect(find.text('Agent B'), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(const Key('oauth-consent-approve')),
      );
      await tester.tap(find.byKey(const Key('oauth-consent-approve')));
      await tester.pump();

      expect(account.approveCalls, ['B']);
    },
  );

  testWidgets('same consent route reloads before another user can approve', (
    tester,
  ) async {
    final authStates = StreamController<AccountAuthState>();
    final account = _MutableAccountClient(scopeAuthorizationToUser: true)
      ..userId = 'A';
    final container = ProviderContainer(
      overrides: [
        accountClientProvider.overrideWithValue(account),
        accountAuthStateProvider.overrideWith((ref) => authStates.stream),
      ],
    );
    final subscription = container.listen(routerProvider, (_, _) {});
    addTearDown(() async {
      subscription.close();
      container.dispose();
      await authStates.close();
    });
    final router = container.read(routerProvider);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    router.go('/oauth/consent?authorization_id=pending');
    await tester.pumpAndSettle();
    expect(find.text('Agent A'), findsOneWidget);

    account.userId = 'B';
    await tester.ensureVisible(find.byKey(const Key('oauth-consent-approve')));
    await tester.tap(find.byKey(const Key('oauth-consent-approve')));
    await tester.pump();
    expect(account.approveCalls, isEmpty);

    authStates.add(
      const AccountAuthState(
        signedIn: true,
        session: AccountSession(userId: 'B'),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      container.read(accountAuthStateProvider).value?.session?.userId,
      'B',
    );
    expect(account.getCalls, ['pending', 'pending']);
    expect(find.text('Agent A'), findsNothing);
    expect(find.text('Agent B'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('oauth-consent-approve')));
    await tester.tap(find.byKey(const Key('oauth-consent-approve')));
    await tester.pump();

    expect(account.approveCalls, ['pending-B']);
    expect(account.approveUsers, ['B']);
  });

  testWidgets('replacement account reloads consent for the same user', (
    tester,
  ) async {
    final accountA = _MutableAccountClient(clientName: 'Agent A')
      ..userId = 'user';
    final accountB = _MutableAccountClient(clientName: 'Agent B')
      ..userId = 'user';
    final container = ProviderContainer(
      overrides: [
        accountClientProvider.overrideWithValue(accountA),
        accountAuthStateProvider.overrideWithValue(
          const AsyncData(
            AccountAuthState(
              signedIn: true,
              session: AccountSession(userId: 'user'),
            ),
          ),
        ),
      ],
    );
    final subscription = container.listen(routerProvider, (_, _) {});
    addTearDown(() {
      subscription.close();
      container.dispose();
    });
    final router = container.read(routerProvider);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    router.go('/oauth/consent?authorization_id=pending');
    await tester.pumpAndSettle();
    expect(find.text('Agent A'), findsOneWidget);

    container.updateOverrides([
      accountClientProvider.overrideWithValue(accountB),
      accountAuthStateProvider.overrideWithValue(
        const AsyncData(
          AccountAuthState(
            signedIn: true,
            session: AccountSession(userId: 'user'),
          ),
        ),
      ),
    ]);
    await tester.pumpAndSettle();

    expect(accountA.getCalls, ['pending']);
    expect(accountB.getCalls, ['pending']);
    expect(find.text('Agent A'), findsNothing);
    expect(find.text('Agent B'), findsOneWidget);
  });

  test('web startup preserves the requested local route and query', () {
    expect(
      initialAppLocationFor(
        isWeb: true,
        baseUri: Uri.parse('https://pomodoist.test/kanban?project=work'),
      ),
      '/kanban?project=work',
    );
  });

  test('non-web startup keeps the native today destination', () {
    expect(
      initialAppLocationFor(
        isWeb: false,
        baseUri: Uri.parse('https://pomodoist.test/kanban'),
      ),
      '/today',
    );
  });

  test('signed-out web app routes redirect to login with returnTo', () {
    expect(
      webAppRedirectFor(
        isWeb: true,
        signedIn: false,
        uri: Uri.parse('/projects'),
      ),
      '/login?returnTo=%2Fprojects',
    );
  });

  test('signed-out OAuth consent preserves its exact local returnTo', () {
    expect(
      webAppRedirectFor(
        isWeb: true,
        signedIn: false,
        uri: Uri.parse('/oauth/consent?authorization_id=a%2Fb%2Bc%2520d'),
      ),
      '/login?returnTo=%2Foauth%2Fconsent%3Fauthorization_id%3D'
      'a%252Fb%252Bc%252520d',
    );
  });

  test('signed-out web auth routes stay public', () {
    expect(
      webAppRedirectFor(isWeb: true, signedIn: false, uri: Uri.parse('/login')),
      isNull,
    );
  });
}

String _routerUri(GoRouter router) =>
    router.routeInformationProvider.value.uri.toString();

class _MutableAccountClient implements AccountClient {
  _MutableAccountClient({
    this.scopeAuthorizationToUser = false,
    this.clientName,
  });

  final bool scopeAuthorizationToUser;
  final String? clientName;
  String? userId;
  final getCalls = <String>[];
  final approveCalls = <String>[];
  final approveUsers = <String?>[];

  @override
  String? get currentUserId => userId;

  @override
  Future<AccountOAuthAuthorization> getOAuthAuthorization(
    String authorizationId,
  ) async {
    getCalls.add(authorizationId);
    final scopedAuthorizationId = scopeAuthorizationToUser
        ? '$authorizationId-$userId'
        : authorizationId;
    return AccountOAuthAuthorizationDetails(
      authorizationId: scopedAuthorizationId,
      clientId: 'client-$authorizationId',
      clientName:
          clientName ??
          (scopeAuthorizationToUser
              ? 'Agent $userId'
              : 'Agent $authorizationId'),
      redirectUri: 'https://agent-$authorizationId.test/callback',
      scopes: const ['pomodoist'],
    );
  }

  @override
  Future<AccountOAuthConsentResult> approveOAuthAuthorization(
    String authorizationId,
  ) async {
    approveCalls.add(authorizationId);
    approveUsers.add(userId);
    return const AccountOAuthConsentResult();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
