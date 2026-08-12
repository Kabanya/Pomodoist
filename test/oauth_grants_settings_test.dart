import 'dart:async';
import 'dart:collection';

import 'package:app_account/app_account.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/account_providers.dart';
import 'package:pomodoist/app/providers.dart';
import 'package:pomodoist/features/billing/billing.dart';
import 'package:pomodoist/features/integrations/google_calendar/data/auth/google_calendar_auth_contract.dart';
import 'package:pomodoist/features/settings/presentation/settings_screen.dart';
import 'package:pomodoist/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
  });

  testWidgets('connected agents are limited to configured signed-in accounts', (
    tester,
  ) async {
    final signedOut = _OAuthGrantsAccount(userId: null);
    await _pumpSettings(tester, account: signedOut);
    expect(find.byKey(const Key('connected-agents-section')), findsNothing);
    expect(signedOut.listCalls, 0);

    final unconfigured = _OAuthGrantsAccount();
    await _pumpSettings(tester, account: unconfigured, configured: false);
    expect(find.byKey(const Key('connected-agents-section')), findsNothing);
    expect(unconfigured.listCalls, 0);
  });

  testWidgets('shows localized loading, grant date, and no identifiers', (
    tester,
  ) async {
    final pending = Completer<List<AccountOAuthGrant>>();
    final account = _OAuthGrantsAccount(listResponses: [() => pending.future]);
    await _pumpSettings(
      tester,
      account: account,
      locale: const Locale('ru'),
      settle: false,
    );
    await tester.pump();

    expect(find.text('Подключённые агенты'), findsOneWidget);
    expect(find.byKey(const Key('connected-agents-loading')), findsOneWidget);

    pending.complete([_grant]);
    await tester.pumpAndSettle();

    expect(find.text('Task Pilot'), findsOneWidget);
    final context = tester.element(
      find.byKey(const Key('connected-agents-section')),
    );
    final date = MaterialLocalizations.of(
      context,
    ).formatMediumDate(_grant.connectedAt.toLocal());
    expect(find.textContaining(date), findsOneWidget);
    expect(find.textContaining(_grant.clientId), findsNothing);
    expect(find.textContaining('tasks:write'), findsNothing);
    expect(find.textContaining('account-user-secret-id'), findsNothing);
    expect(find.textContaining('account-access-token-secret'), findsNothing);
  });

  testWidgets('shows empty state', (tester) async {
    final account = _OAuthGrantsAccount(listResponses: [() async => []]);
    await _pumpSettings(tester, account: account);

    expect(find.byKey(const Key('connected-agents-empty')), findsOneWidget);
  });

  testWidgets('load error leaves settings usable and retry recovers', (
    tester,
  ) async {
    final account = _OAuthGrantsAccount(
      listResponses: [
        () => Future.error(StateError('offline')),
        () async => [_grant],
      ],
    );
    await _pumpSettings(tester, account: account);

    expect(find.byKey(const Key('connected-agents-error')), findsOneWidget);
    expect(find.byKey(const Key('settings-language-select')), findsOneWidget);

    await tester.tap(find.byKey(const Key('connected-agents-retry')));
    await tester.pumpAndSettle();

    expect(account.listCalls, 2);
    expect(find.text('Task Pilot'), findsOneWidget);
  });

  testWidgets('cancel names the client and does not revoke', (tester) async {
    final account = _OAuthGrantsAccount(
      listResponses: [
        () async => [_grant],
      ],
    );
    await _pumpSettings(tester, account: account);

    await tester.tap(find.byKey(const Key(_revokeKey)));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('connected-agent-revoke-dialog')),
      findsOneWidget,
    );
    expect(find.textContaining('Task Pilot'), findsWidgets);

    await tester.tap(find.byKey(const Key('connected-agent-revoke-cancel')));
    await tester.pumpAndSettle();

    expect(account.revokedClientIds, isEmpty);
  });

  testWidgets('confirmed revoke is single-flight and refreshes the list', (
    tester,
  ) async {
    final pending = Completer<void>();
    final account = _OAuthGrantsAccount(
      listResponses: [
        () async => [_grant],
        () async => [],
      ],
      revokeResponses: [(_) => pending.future],
    );
    await _pumpSettings(tester, account: account);

    await tester.tap(find.byKey(const Key(_revokeKey)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('connected-agent-revoke-confirm')));
    await tester.pump();

    expect(account.revokedClientIds, [_grant.clientId]);
    final revokeButton = tester.widget<IconButton>(
      find.byKey(const Key(_revokeKey)),
    );
    expect(revokeButton.onPressed, isNull);
    await tester.tap(find.byKey(const Key(_revokeKey)), warnIfMissed: false);
    await tester.pump();
    expect(account.revokedClientIds, [_grant.clientId]);

    pending.complete();
    await tester.pumpAndSettle();

    expect(account.listCalls, 2);
    expect(find.text('Task Pilot'), findsNothing);
    expect(find.byKey(const Key('connected-agents-empty')), findsOneWidget);
  });

  testWidgets('revoke failure retains the grant and permits retry', (
    tester,
  ) async {
    final account = _OAuthGrantsAccount(
      listResponses: [
        () async => [_grant],
      ],
      revokeResponses: [
        (_) => Future.error(StateError('offline')),
        (_) async {},
      ],
    );
    await _pumpSettings(tester, account: account);

    await _confirmRevoke(tester);
    await tester.pumpAndSettle();

    expect(find.text('Task Pilot'), findsOneWidget);
    expect(
      find.byKey(const Key('connected-agent-revoke-error')),
      findsOneWidget,
    );
    expect(
      tester.widget<IconButton>(find.byKey(const Key(_revokeKey))).onPressed,
      isNotNull,
    );

    await _confirmRevoke(tester);
    await tester.pumpAndSettle();

    expect(account.revokedClientIds, [_grant.clientId, _grant.clientId]);
  });

  testWidgets('same client user switch drops stale list and confirmation', (
    tester,
  ) async {
    final pending = Completer<List<AccountOAuthGrant>>();
    final account = _OAuthGrantsAccount(
      userId: 'user-a',
      listResponses: [
        () => pending.future,
        () async => [_grantB],
        () async => [_grantB],
      ],
    );
    await _pumpSettings(tester, account: account, settle: false);
    await tester.pump();

    account.userId = 'user-b';
    pending.complete([_grant]);
    await tester.pump();

    expect(find.text('Task Pilot'), findsNothing);

    await _updateSettingsAccount(tester, account);
    expect(find.text('Agent B'), findsOneWidget);

    await tester.tap(find.byKey(const Key(_revokeBKey)));
    await tester.pumpAndSettle();
    account.userId = 'user-c';
    await _updateSettingsAccount(tester, account);

    expect(
      find.byKey(const Key('connected-agent-revoke-dialog')),
      findsNothing,
    );
    expect(account.revokedClientIds, isEmpty);
  });

  testWidgets('replacement account resets a pending revoke', (tester) async {
    final pending = Completer<void>();
    final accountA = _OAuthGrantsAccount(
      userId: 'same-user',
      listResponses: [
        () async => [_grant],
      ],
      revokeResponses: [(_) => pending.future],
    );
    final accountB = _OAuthGrantsAccount(
      userId: 'same-user',
      listResponses: [
        () async => [_grant],
        () async => [],
      ],
    );
    await _pumpSettings(tester, account: accountA);
    await _confirmRevoke(tester);
    await tester.pump();
    expect(accountA.revokedClientIds, [_grant.clientId]);

    await _updateSettingsAccount(tester, accountB);
    expect(
      tester.widget<IconButton>(find.byKey(const Key(_revokeKey))).onPressed,
      isNotNull,
    );

    pending.complete();
    await tester.pump();
    expect(find.text('Task Pilot'), findsOneWidget);

    await _confirmRevoke(tester);
    await tester.pumpAndSettle();
    expect(accountB.revokedClientIds, [_grant.clientId]);
    expect(find.byKey(const Key('connected-agents-empty')), findsOneWidget);
  });
}

Future<void> _updateSettingsAccount(
  WidgetTester tester,
  _OAuthGrantsAccount account,
) async {
  ProviderScope.containerOf(
    tester.element(find.byType(SettingsScreen)),
  ).updateOverrides([
    accountClientProvider.overrideWithValue(account),
    accountConfiguredProvider.overrideWithValue(true),
    accountAuthStateProvider.overrideWithValue(
      AsyncData(
        AccountAuthState(signedIn: true, session: account.currentSession),
      ),
    ),
    accountOverviewProvider.overrideWith(
      (ref) async => AccountOverview.empty(account.currentUserId!),
    ),
    applePurchasesSupportedProvider.overrideWithValue(false),
    pomodoistDeviceIdProvider.overrideWith((ref) async => 'device-1'),
    googleCalendarAuthServiceProvider.overrideWithValue(
      const _NoopGoogleCalendarAuthService(),
    ),
    googleCalendarConnectionProvider.overrideWith((ref) => Stream.value(null)),
  ]);
  await tester.pumpAndSettle();
}

const _clientId = '11111111-1111-4111-8111-111111111111';
const _revokeKey = 'connected-agent-revoke-$_clientId';
const _clientBId = '22222222-2222-4222-8222-222222222222';
const _revokeBKey = 'connected-agent-revoke-$_clientBId';

final _grant = AccountOAuthGrant(
  clientId: _clientId,
  clientName: 'Task Pilot',
  scopes: const ['tasks:write', 'secret-scope'],
  connectedAt: DateTime.parse('2026-07-10T12:30:00Z'),
);

final _grantB = AccountOAuthGrant(
  clientId: _clientBId,
  clientName: 'Agent B',
  scopes: const [],
  connectedAt: DateTime.parse('2026-07-11T12:30:00Z'),
);

Future<void> _confirmRevoke(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key(_revokeKey)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('connected-agent-revoke-confirm')));
}

Future<void> _pumpSettings(
  WidgetTester tester, {
  required _OAuthGrantsAccount account,
  bool configured = true,
  bool settle = true,
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = const Size(1200, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        accountClientProvider.overrideWithValue(account),
        accountConfiguredProvider.overrideWithValue(configured),
        accountAuthStateProvider.overrideWithValue(
          AsyncData(
            AccountAuthState(
              signedIn: account.currentUserId != null,
              session: account.currentSession,
            ),
          ),
        ),
        accountOverviewProvider.overrideWith(
          (ref) async => account.currentUserId == null
              ? null
              : AccountOverview.empty(account.currentUserId!),
        ),
        applePurchasesSupportedProvider.overrideWithValue(false),
        pomodoistDeviceIdProvider.overrideWith((ref) async => 'device-1'),
        googleCalendarAuthServiceProvider.overrideWithValue(
          const _NoopGoogleCalendarAuthService(),
        ),
        googleCalendarConnectionProvider.overrideWith(
          (ref) => Stream.value(null),
        ),
      ],
      child: MaterialApp(
        locale: locale,
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
  if (settle) {
    await tester.pumpAndSettle();
  }
}

class _OAuthGrantsAccount implements AccountClient {
  _OAuthGrantsAccount({
    this.userId = 'account-user-secret-id',
    List<Future<List<AccountOAuthGrant>> Function()> listResponses = const [],
    List<Future<void> Function(String)> revokeResponses = const [],
  }) : _listResponses = Queue.of(listResponses),
       _revokeResponses = Queue.of(revokeResponses);

  String? userId;
  final Queue<Future<List<AccountOAuthGrant>> Function()> _listResponses;
  final Queue<Future<void> Function(String)> _revokeResponses;
  final List<String> revokedClientIds = [];
  var listCalls = 0;

  @override
  String? get currentUserId => userId;

  @override
  AccountSession? get currentSession => userId == null
      ? null
      : AccountSession(
          userId: userId!,
          accessToken: 'account-access-token-secret',
        );

  @override
  Future<List<AccountOAuthGrant>> listOAuthGrants() {
    listCalls += 1;
    return _listResponses.removeFirst()();
  }

  @override
  Future<void> revokeOAuthGrant(String clientId) {
    revokedClientIds.add(clientId);
    return _revokeResponses.isEmpty
        ? Future.value()
        : _revokeResponses.removeFirst()(clientId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoopGoogleCalendarAuthService implements GoogleCalendarAuthService {
  const _NoopGoogleCalendarAuthService();

  @override
  Future<String?> accessToken({bool interactive = false}) async => null;

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> initialize() async {}

  @override
  Future<GoogleCalendarAuthAccount> signIn() async {
    return const GoogleCalendarAuthAccount();
  }
}
