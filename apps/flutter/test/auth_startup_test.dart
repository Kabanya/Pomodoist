import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pomodoist/app/account_providers.dart';
import 'package:pomodoist/app/app.dart';
import 'package:pomodoist/app/app_startup_gate.dart';
import 'package:pomodoist/app/providers.dart';
import 'package:pomodoist/app/router.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
  });

  testWidgets('login renders while app startup is still pending', (
    tester,
  ) async {
    final harness = await _pumpWithPendingStartup(tester);

    harness.router.go('/login');
    await _pumpFrames(tester);

    expect(_routerUri(harness.router), '/login');
    expect(find.byKey(const Key('login-register-link')), findsOneWidget);
    expect(find.byKey(const Key('app-startup-loading')), findsNothing);
  });

  testWidgets('register renders while app startup is still pending', (
    tester,
  ) async {
    final harness = await _pumpWithPendingStartup(tester);

    harness.router.go('/register');
    await _pumpFrames(tester);

    expect(_routerUri(harness.router), '/register');
    expect(find.byKey(const Key('register-email-field')), findsOneWidget);
    expect(find.byKey(const Key('app-startup-loading')), findsNothing);
  });

  testWidgets('OAuth consent renders outside app startup and shell', (
    tester,
  ) async {
    final harness = await _pumpWithPendingStartup(tester);

    harness.router.go('/oauth/consent?authorization_id=pending-id');
    await _pumpFrames(tester);

    expect(
      _routerUri(harness.router),
      '/oauth/consent?authorization_id=pending-id',
    );
    expect(find.byKey(const Key('oauth-consent-screen')), findsOneWidget);
    expect(find.byKey(const Key('app-startup-loading')), findsNothing);
    expect(find.byKey(const Key('adaptive-shell')), findsNothing);
  });

  testWidgets('signed-in shell waits for the account boundary startup', (
    tester,
  ) async {
    final accountStartup = Completer<void>();
    var accountStartupCalls = 0;
    final container = ProviderContainer(
      overrides: [
        appStartupProvider.overrideWith((ref) async {}),
        accountSyncStartupProvider.overrideWith((ref) {
          accountStartupCalls += 1;
          return accountStartup.future;
        }),
        appStartupLifecycleProvider.overrideWith((ref) {}),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: AppStartupGate(
            child: SizedBox(key: Key('account-ready-child')),
          ),
        ),
      ),
    );
    await _pumpFrames(tester);

    expect(find.byKey(const Key('app-startup-loading')), findsOneWidget);
    expect(find.byKey(const Key('account-ready-child')), findsNothing);
    expect(accountStartupCalls, 1);

    await tester.pump(const Duration(seconds: 30));
    expect(find.byKey(const Key('app-startup-slow')), findsOneWidget);

    await tester.tap(find.byKey(const Key('app-startup-continue-waiting')));
    await tester.pump();
    expect(find.byKey(const Key('app-startup-loading')), findsOneWidget);
    expect(accountStartupCalls, 1);

    accountStartup.complete();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('account-ready-child')), findsOneWidget);
    expect(accountStartupCalls, 1);
  });

  testWidgets('startup warning never restarts the pending work', (
    tester,
  ) async {
    final startup = Completer<void>();
    var calls = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appStartupProvider.overrideWith((ref) {
            calls += 1;
            return startup.future;
          }),
          accountSyncStartupProvider.overrideWith((ref) async {}),
          appStartupLifecycleProvider.overrideWith((ref) {}),
        ],
        child: const MaterialApp(
          home: AppStartupGate(
            child: SizedBox(key: Key('startup-ready-child')),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 30));

    expect(find.byKey(const Key('app-startup-slow')), findsOneWidget);
    expect(calls, 1);

    await tester.tap(find.byKey(const Key('app-startup-continue-waiting')));
    await tester.pump();

    expect(find.byKey(const Key('app-startup-loading')), findsOneWidget);
    expect(calls, 1);

    await tester.pump(const Duration(seconds: 30));
    expect(find.byKey(const Key('app-startup-slow')), findsOneWidget);
    expect(calls, 1);

    startup.complete();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('startup-ready-child')), findsOneWidget);
    expect(calls, 1);
  });
}

Future<({ProviderContainer container, GoRouter router})>
_pumpWithPendingStartup(WidgetTester tester) async {
  final startup = Completer<void>();
  final container = ProviderContainer(
    overrides: [appStartupProvider.overrideWith((ref) => startup.future)],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const PomodoistApp(),
    ),
  );
  await _pumpFrames(tester);
  return (container: container, router: container.read(routerProvider));
}

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 8; i += 1) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

String _routerUri(GoRouter router) =>
    router.routeInformationProvider.value.uri.toString();
