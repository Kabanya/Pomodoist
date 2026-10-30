import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:go_router/go_router.dart';
import 'package:pomodoist/config/account_providers.dart';
import 'package:pomodoist/ui/core/widgets/pomodoist_app.dart';
import 'package:pomodoist/ui/core/widgets/app_startup_gate.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/config/startup_wiring.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/services/local/outbox_service.dart';
import 'package:pomodoist/data/repositories/tasks/task_repository_impl.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/ui/core/widgets/adaptive_shell.dart';
import 'package:pomodoist/routing/router.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
  });

  for (final width in [390.0, 1280.0]) {
    testWidgets('shell opens before local data at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final reads = _LocalReads();
      final db = AppDatabase(NativeDatabase.memory().interceptWith(reads));
      addTearDown(db.close);
      await db.ensureSeedData();
      (await DriftTaskRepository(
        db,
        DriftOutboxService(db),
      ).createTask(CreateTaskInput(content: 'Saved local task'))).getOrThrow();
      reads.count = 0;
      var ownership = Completer<void>();
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          appStartupProvider.overrideWith((ref) async {}),
          accountSyncStartupProvider.overrideWith((ref) => ownership.future),
          startupBackgroundWiringProvider.overrideWith((ref) {}),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const PomodoistApp(),
        ),
      );
      final router = container.read(routerProvider);
      router.go('/inbox');
      await _pumpFrames(tester);
      expect(find.byType(AdaptiveShell), findsOneWidget);
      expect(find.byKey(const Key('app-startup-loading')), findsOneWidget);
      expect(find.text('Saved local task'), findsNothing);
      expect(reads.count, 0, reason: 'Ownership must precede local data reads');
      final shell = tester.state(find.byType(AdaptiveShell));
      await tester.tap(
        width >= 820
            ? find.byKey(const ValueKey('sidebar-destination-/today'))
            : find.byTooltip('Today'),
      );
      await _pumpFrames(tester);
      expect(_routerUri(router), '/today');
      expect(tester.state(find.byType(AdaptiveShell)), same(shell));
      router.go('/inbox');
      ownership.complete();
      await _pumpFrames(tester);
      await tester.runAsync(
        () => container.read(
          tasksByQueryProvider(const TaskQuery.inbox()).future,
        ),
      );
      await _pumpFrames(tester);
      expect(find.text('Saved local task'), findsOneWidget);
      expect(tester.state(find.byType(AdaptiveShell)), same(shell));
      ownership = Completer<void>();
      container.invalidate(accountSyncStartupProvider);
      await _pumpFrames(tester);
      expect(find.text('Saved local task'), findsNothing);
      expect(find.byKey(const Key('app-startup-loading')), findsOneWidget);
      expect(tester.state(find.byType(AdaptiveShell)), same(shell));
      ownership.complete();
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      await tester.pump(const Duration(seconds: 1));
      final closing = db.close();
      await tester.pumpAndSettle();
      await closing;
    });
  }

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
        recurringTaskMaterializationProvider.overrideWith((ref) {}),
        taskStartNotificationCoordinatorProvider.overrideWith((ref) {}),
        reengagementNotificationCoordinatorProvider.overrideWith((ref) {}),
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

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    container.dispose();
    await tester.pump(const Duration(seconds: 1));
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
          recurringTaskMaterializationProvider.overrideWith((ref) {}),
          taskStartNotificationCoordinatorProvider.overrideWith((ref) {}),
          reengagementNotificationCoordinatorProvider.overrideWith((ref) {}),
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

class _LocalReads extends QueryInterceptor {
  int count = 0;
  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    count++;
    return executor.runSelect(statement, args);
  }
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
