import 'dart:async';

import 'package:app_account/app_account.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/account_providers.dart';
import 'package:pomodoist/features/billing/billing.dart';
import 'package:pomodoist/features/settings/presentation/settings_screen.dart';
import 'package:pomodoist/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('late account bootstrap success replaces timeout error', () async {
    final completer = Completer<AccountClient?>();
    final account = _FakeAccountClient();
    var attempts = 0;
    final container = ProviderContainer(
      overrides: [
        accountBootstrapInitializerProvider.overrideWithValue(() {
          attempts += 1;
          return completer.future;
        }),
        accountBootstrapTimeoutProvider.overrideWithValue(
          const Duration(milliseconds: 10),
        ),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      accountBootstrapProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(container.read(accountBootstrapProvider).hasError, isTrue);
    expect(container.read(accountClientProvider), isNull);

    completer.complete(account);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(accountBootstrapProvider).value, same(account));
    expect(container.read(accountClientProvider), same(account));
    expect(attempts, 1);
  });

  test('account bootstrap retry reuses an unfinished initialization', () async {
    final completer = Completer<AccountClient?>();
    final account = _FakeAccountClient();
    var attempts = 0;
    final container = ProviderContainer(
      overrides: [
        accountBootstrapInitializerProvider.overrideWithValue(() {
          attempts += 1;
          return completer.future;
        }),
        accountBootstrapTimeoutProvider.overrideWithValue(
          const Duration(milliseconds: 10),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.listen(
      accountBootstrapProvider,
      (_, _) {},
      fireImmediately: true,
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final retry = container.read(accountBootstrapProvider.notifier).retry();
    await Future<void>.delayed(Duration.zero);
    expect(attempts, 1);

    completer.complete(account);
    await retry;

    expect(container.read(accountBootstrapProvider).value, same(account));
  });

  test('account bootstrap retry starts over after a real failure', () async {
    final account = _FakeAccountClient();
    var attempts = 0;
    final container = ProviderContainer(
      overrides: [
        accountBootstrapInitializerProvider.overrideWithValue(() {
          attempts += 1;
          return attempts == 1
              ? Future<AccountClient?>.error(StateError('failed'))
              : Future<AccountClient?>.value(account);
        }),
      ],
    );
    addTearDown(container.dispose);
    container.listen(
      accountBootstrapProvider,
      (_, _) {},
      fireImmediately: true,
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(accountBootstrapProvider).hasError, isTrue);

    await container.read(accountBootstrapProvider.notifier).retry();

    expect(attempts, 2);
    expect(container.read(accountClientProvider), same(account));
  });

  testWidgets('settings contains account bootstrap timeout and retry', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(const {});
    final pending = Completer<AccountClient?>();
    var attempts = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountBootstrapInitializerProvider.overrideWithValue(() {
            attempts += 1;
            return pending.future;
          }),
          accountBootstrapTimeoutProvider.overrideWithValue(
            const Duration(milliseconds: 10),
          ),
          accountOverviewProvider.overrideWith((ref) async => null),
          applePurchasesSupportedProvider.overrideWithValue(false),
        ],
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: SettingsScreen()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.byKey(const Key('account-bootstrap-error')), findsOneWidget);
    expect(find.byKey(const Key('account-bootstrap-retry')), findsOneWidget);
    expect(find.byKey(const Key('billing-paywall')), findsOneWidget);

    await tester.tap(find.byKey(const Key('account-bootstrap-retry')));
    await tester.pump(const Duration(milliseconds: 20));
    expect(attempts, 1);
  });

  test('registerInstall failure does not block account overview', () async {
    final overview = AccountOverview(
      profile: const AccountProfile(id: 'user'),
      apps: const [],
      generatedAt: DateTime.utc(2026, 7, 11),
    );
    final account = _OverviewAccountClient(
      overview: () async => overview,
      registerInstallCallback: () async => throw StateError('offline'),
    );
    final container = ProviderContainer(
      overrides: [
        accountClientProvider.overrideWithValue(account),
        accountAuthStateProvider.overrideWithValue(
          const AsyncData(AccountAuthState(signedIn: true)),
        ),
        pomodoistDeviceIdProvider.overrideWith((ref) async => 'device'),
        accountRequestTimeoutProvider.overrideWithValue(
          const Duration(milliseconds: 10),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(
      await container.read(accountOverviewProvider.future),
      same(overview),
    );
  });

  testWidgets('account overview failure remains until login retry', (
    tester,
  ) async {
    final pending = Completer<AccountOverview>();
    final overview = AccountOverview(
      profile: const AccountProfile(
        id: 'user',
        displayName: 'Test User',
        email: 'user@example.com',
      ),
      apps: const [],
      generatedAt: DateTime.utc(2026, 7, 11),
    );
    var overviewCalls = 0;
    final account = _OverviewAccountClient(
      overview: () {
        overviewCalls += 1;
        return overviewCalls == 1 ? pending.future : Future.value(overview);
      },
      registerInstallCallback: () async {},
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountClientProvider.overrideWithValue(account),
          accountAuthStateProvider.overrideWithValue(
            const AsyncData(AccountAuthState(signedIn: true)),
          ),
          pomodoistDeviceIdProvider.overrideWith((ref) async => 'device'),
          accountRequestTimeoutProvider.overrideWithValue(
            const Duration(milliseconds: 10),
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
          home: const LoginScreen(),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('login-account-loading')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump(const Duration(milliseconds: 250));

    expect(overviewCalls, 1);
    expect(find.byKey(const Key('login-account-loading')), findsNothing);
    expect(find.byKey(const Key('login-account-retry')), findsOneWidget);

    await tester.tap(find.byKey(const Key('login-account-retry')));
    await tester.pumpAndSettle();

    expect(overviewCalls, 2);
    expect(find.text('user@example.com'), findsOneWidget);
  });
}

class _FakeAccountClient implements AccountClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _OverviewAccountClient implements AccountClient {
  _OverviewAccountClient({
    required this.overview,
    required this.registerInstallCallback,
  });

  final Future<AccountOverview> Function() overview;
  final Future<void> Function() registerInstallCallback;

  @override
  String? get currentUserId => 'user';

  @override
  Future<AccountOverview> getOverview() => overview();

  @override
  Future<void> registerInstall({
    required String appId,
    required String deviceId,
    String? platform,
    String? appVersion,
  }) => registerInstallCallback();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
