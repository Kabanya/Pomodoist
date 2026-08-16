import 'dart:async';

import 'package:app_account/app_account.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/account_providers.dart';
import 'package:pomodoist/app/providers.dart';
import 'package:pomodoist/core/db/app_database.dart';
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

  testWidgets('delete account is last and requires two confirmations', (
    tester,
  ) async {
    final pending = Completer<AccountFunctionResponse>();
    final account = _RecordingAccountClient(onInvoke: () => pending.future);
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.ensureSeedData();
    await _pumpSettings(tester, account: account, db: db);

    final settingsList = tester.widget<ListView>(
      find.byKey(const Key('settings-list')),
    );
    final settingsChildren =
        (settingsList.childrenDelegate as SliverChildListDelegate).children;
    final keyedChildren = settingsChildren
        .where((child) => child.key != null)
        .toList();
    expect(keyedChildren.last.key, const Key('account-delete-section'));
    expect(
      keyedChildren[keyedChildren.length - 2].key,
      const Key('settings-shortcuts-button'),
    );

    final firstConfirmation = find.byKey(const Key('account-delete-button'));
    await _scrollToDeleteButton(tester);
    await tester.tap(firstConfirmation);
    await tester.pumpAndSettle();

    expect(account.invocations, isEmpty);
    expect(find.byKey(const Key('account-delete-dialog')), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('account-delete-dialog')), findsOneWidget);

    await tester.tap(find.byKey(const Key('account-delete-confirm-button')));
    await tester.pumpAndSettle();

    expect(account.invocations, isEmpty);
    expect(
      find.byKey(const Key('account-delete-final-dialog')),
      findsOneWidget,
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('account-delete-final-dialog')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('account-delete-final-cancel-button')),
    );
    await tester.pumpAndSettle();
    expect(account.invocations, isEmpty);
    expect(find.byKey(const Key('account-delete-dialog')), findsOneWidget);

    await _confirmDelete(tester);

    expect(account.invocations, [
      const _Invocation('account-delete', {'confirm': true}),
    ]);

    pending.complete(
      const AccountFunctionResponse(status: 200, data: {'deleted': true}),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('delete account is hidden when signed out', (tester) async {
    final account = _RecordingAccountClient(
      userId: null,
      onInvoke: () async =>
          const AccountFunctionResponse(status: 200, data: {'deleted': true}),
    );
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.ensureSeedData();

    await _pumpSettings(tester, account: account, db: db);

    expect(find.byKey(const Key('account-delete-button')), findsNothing);
  });

  testWidgets('delete account remains available when account overview fails', (
    tester,
  ) async {
    final account = _RecordingAccountClient(
      onInvoke: () async =>
          const AccountFunctionResponse(status: 200, data: {'deleted': true}),
    );
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.ensureSeedData();

    await _pumpSettings(
      tester,
      account: account,
      db: db,
      overviewError: StateError('overview unavailable'),
    );

    expect(find.byKey(const Key('account-overview-error')), findsOneWidget);
    await _scrollToDeleteButton(tester);
    expect(find.byKey(const Key('account-delete-button')), findsOneWidget);
  });

  testWidgets('cancel closes confirmation without deleting the account', (
    tester,
  ) async {
    final account = _RecordingAccountClient(
      onInvoke: () async =>
          const AccountFunctionResponse(status: 200, data: {'deleted': true}),
    );
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.ensureSeedData();
    await _pumpSettings(tester, account: account, db: db);
    await _openDeleteDialog(tester);

    await tester.tap(find.byKey(const Key('account-delete-cancel-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('account-delete-dialog')), findsNothing);
    expect(account.invocations, isEmpty);
    expect(account.signOutCalls, 0);
  });

  testWidgets('delete dialog offers manual Sign in with Apple revocation', (
    tester,
  ) async {
    final account = _RecordingAccountClient(
      onInvoke: () async =>
          const AccountFunctionResponse(status: 200, data: {'deleted': true}),
    );
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.ensureSeedData();
    await _pumpSettings(tester, account: account, db: db);
    await _openDeleteDialog(tester);

    final manageApple = find.byKey(
      const Key('account-delete-manage-apple-button'),
    );
    expect(manageApple, findsOneWidget);
    expect(find.text('Manage Sign in with Apple'), findsOneWidget);
    expect(tester.widget<TextButton>(manageApple).onPressed, isNotNull);
  });

  testWidgets('confirmed deletion is single-flight and clears local data', (
    tester,
  ) async {
    final pending = Completer<AccountFunctionResponse>();
    final account = _RecordingAccountClient(onInvoke: () => pending.future);
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.ensureSeedData();
    await _insertTask(db, 'delete-me');
    await _pumpSettings(tester, account: account, db: db);
    await _openDeleteDialog(tester);

    await _confirmDelete(tester);

    expect(account.invocations, hasLength(1));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('account-delete-confirm-button')),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const Key('account-delete-confirm-button')));
    await tester.pump();
    expect(account.invocations, hasLength(1));

    pending.complete(
      const AccountFunctionResponse(status: 200, data: {'deleted': true}),
    );
    await tester.pumpAndSettle();

    expect(account.signOutCalls, 1);
    expect(
      await (db.select(
        db.tasks,
      )..where((row) => row.id.equals('delete-me'))).get(),
      isEmpty,
    );
    expect(find.text('Account deleted.'), findsOneWidget);
  });

  testWidgets('backend error preserves local data and allows retry', (
    tester,
  ) async {
    var attempts = 0;
    final account = _RecordingAccountClient(
      onInvoke: () async {
        attempts += 1;
        if (attempts == 1) throw StateError('offline');
        return const AccountFunctionResponse(
          status: 200,
          data: {'deleted': true},
        );
      },
    );
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.ensureSeedData();
    await _insertTask(db, 'keep-on-error');
    await _pumpSettings(tester, account: account, db: db);
    await _openDeleteDialog(tester);

    await _confirmDelete(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('account-delete-error')), findsOneWidget);
    expect(account.signOutCalls, 0);
    expect(
      await (db.select(
        db.tasks,
      )..where((row) => row.id.equals('keep-on-error'))).get(),
      hasLength(1),
    );

    await _confirmDelete(tester);
    await tester.pumpAndSettle();

    expect(account.invocations, hasLength(2));
    expect(account.signOutCalls, 1);
    expect(
      await (db.select(
        db.tasks,
      )..where((row) => row.id.equals('keep-on-error'))).get(),
      isEmpty,
    );
  });

  testWidgets('unconfirmed backend response preserves local data and session', (
    tester,
  ) async {
    final account = _RecordingAccountClient(
      onInvoke: () async =>
          const AccountFunctionResponse(status: 200, data: {'deleted': false}),
    );
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.ensureSeedData();
    await _insertTask(db, 'keep-unconfirmed');
    await _pumpSettings(tester, account: account, db: db);
    await _openDeleteDialog(tester);

    await _confirmDelete(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('account-delete-error')), findsOneWidget);
    expect(account.signOutCalls, 0);
    expect(
      await (db.select(
        db.tasks,
      )..where((row) => row.id.equals('keep-unconfirmed'))).get(),
      hasLength(1),
    );
  });

  testWidgets('backend timeout shows a retryable error', (tester) async {
    final account = _RecordingAccountClient(
      onInvoke: () => Completer<AccountFunctionResponse>().future,
    );
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.ensureSeedData();
    await _pumpSettings(
      tester,
      account: account,
      db: db,
      requestTimeout: const Duration(milliseconds: 10),
    );
    await _openDeleteDialog(tester);

    await _confirmDelete(tester);
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump();

    expect(find.byKey(const Key('account-delete-error')), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('account-delete-confirm-button')),
          )
          .onPressed,
      isNotNull,
    );
    expect(account.signOutCalls, 0);
  });

  testWidgets('local cleanup failure signs out without retrying backend', (
    tester,
  ) async {
    final account = _RecordingAccountClient(
      onInvoke: () async =>
          const AccountFunctionResponse(status: 200, data: {'deleted': true}),
    );
    final db = _FailingResetDatabase();
    addTearDown(db.close);
    await db.ensureSeedData();
    await _pumpSettings(tester, account: account, db: db);
    await _openDeleteDialog(tester);

    await _confirmDelete(tester);
    await tester.pumpAndSettle();

    expect(account.invocations, hasLength(1));
    expect(account.signOutCalls, 1);
    expect(find.byKey(const Key('account-delete-dialog')), findsNothing);
    expect(
      find.text(
        'Your account was deleted, but local data could not be cleared. '
        "Clear the app's data before using this device again.",
      ),
      findsOneWidget,
    );
  });

  testWidgets('pending deletion completes after Settings is disposed', (
    tester,
  ) async {
    final pending = Completer<AccountFunctionResponse>();
    final account = _RecordingAccountClient(onInvoke: () => pending.future);
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.ensureSeedData();
    await _insertTask(db, 'delete-after-dispose');
    await _pumpSettings(tester, account: account, db: db);
    await _openDeleteDialog(tester);
    await _confirmDelete(tester);

    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(
      const AccountFunctionResponse(status: 200, data: {'deleted': true}),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(account.signOutCalls, 1);
    expect(
      await (db.select(
        db.tasks,
      )..where((row) => row.id.equals('delete-after-dispose'))).get(),
      isEmpty,
    );
  });
}

Future<void> _openDeleteDialog(WidgetTester tester) async {
  final button = find.byKey(const Key('account-delete-button'));
  await _scrollToDeleteButton(tester);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> _scrollToDeleteButton(WidgetTester tester) {
  return tester.scrollUntilVisible(
    find.byKey(const Key('account-delete-button')),
    500,
    scrollable: find.byType(Scrollable).first,
  );
}

Future<void> _confirmDelete(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('account-delete-confirm-button')));
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(const Key('account-delete-final-confirm-button')),
  );
  await tester.pump();
}

Future<void> _insertTask(AppDatabase db, String id) {
  final now = DateTime.utc(2026, 7, 19);
  return db
      .into(db.tasks)
      .insert(
        TasksCompanion.insert(
          id: id,
          userId: localUserId,
          content: 'Private task',
          projectId: inboxProjectId,
          orderKey: id,
          createdAt: now,
          updatedAt: now,
        ),
      );
}

Future<void> _pumpSettings(
  WidgetTester tester, {
  required _RecordingAccountClient account,
  required AppDatabase db,
  AccountOverview? overview,
  Object? overviewError,
  Duration requestTimeout = const Duration(seconds: 15),
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        accountClientProvider.overrideWithValue(account),
        accountConfiguredProvider.overrideWithValue(true),
        accountAuthStateProvider.overrideWithValue(
          AsyncData(
            AccountAuthState(
              signedIn: account.currentUserId != null,
              session: account.currentSession,
            ),
          ),
        ),
        accountOverviewProvider.overrideWith((ref) async {
          if (overviewError != null) throw overviewError;
          return account.currentUserId == null
              ? null
              : overview ?? AccountOverview.empty(account.currentUserId!);
        }),
        accountRequestTimeoutProvider.overrideWithValue(requestTimeout),
        applePurchasesSupportedProvider.overrideWithValue(false),
        pomodoistDeviceIdProvider.overrideWith((ref) async => 'device-1'),
        googleCalendarAuthServiceProvider.overrideWithValue(
          const _NoopGoogleCalendarAuthService(),
        ),
        googleCalendarConnectionProvider.overrideWith(
          (ref) => Stream.value(null),
        ),
      ],
      child: const MaterialApp(
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: SettingsScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _RecordingAccountClient implements AccountClient {
  _RecordingAccountClient({required this.onInvoke, this.userId = 'user-1'});

  final Future<AccountFunctionResponse> Function() onInvoke;
  final String? userId;
  final List<_Invocation> invocations = [];
  var signOutCalls = 0;

  @override
  String? get currentUserId => userId;

  @override
  AccountSession? get currentSession => userId == null
      ? null
      : AccountSession(userId: userId!, accessToken: 'test-token');

  @override
  Future<AccountFunctionResponse> invokeFunction(
    String functionName, {
    Map<String, String>? headers,
    Object? body,
    Map<String, dynamic>? queryParameters,
    String? region,
  }) {
    invocations.add(
      _Invocation(functionName, Map<String, Object?>.from(body! as Map)),
    );
    return onInvoke();
  }

  @override
  Future<void> signOut() async {
    signOutCalls += 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Invocation {
  const _Invocation(this.functionName, this.body);

  final String functionName;
  final Map<String, Object?> body;

  @override
  bool operator ==(Object other) =>
      other is _Invocation &&
      other.functionName == functionName &&
      _mapsEqual(other.body, body);

  @override
  int get hashCode => Object.hash(functionName, Object.hashAll(body.entries));
}

bool _mapsEqual(Map<String, Object?> left, Map<String, Object?> right) {
  if (left.length != right.length) return false;
  return left.entries.every((entry) => right[entry.key] == entry.value);
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
    return const GoogleCalendarAuthAccount(email: 'user@example.test');
  }
}

class _FailingResetDatabase extends AppDatabase {
  _FailingResetDatabase() : super(NativeDatabase.memory());

  @override
  Future<void> resetAccountData() async {
    throw StateError('disk unavailable');
  }
}
