import 'dart:async';

import 'package:app_account/app_account.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/account_providers.dart';
import 'package:pomodoist/app/providers.dart';
import 'package:pomodoist/app/widgets/adaptive_shell.dart';
import 'package:pomodoist/features/focus/domain/focus_models.dart';
import 'package:pomodoist/features/focus/presentation/focus_screen.dart';
import 'package:pomodoist/features/settings/presentation/settings_screen.dart';
import 'package:pomodoist/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(const {}));

  testWidgets('guest login keeps auth usable while timer startup is pending', (
    tester,
  ) async {
    final startup = Completer<void>();
    final container = _guestContainer(() => startup.future);
    addTearDown(container.dispose);

    await _pumpGuestLogin(tester, container);

    expect(find.text('Sign in to Pomodoist'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.byKey(const Key('guest-timer-loading')), findsOneWidget);
    expect(find.byType(FocusScreen), findsNothing);

    await tester.tap(find.text('Email'));
    await tester.pump();
    expect(find.byKey(const Key('account-auth-mode')), findsOneWidget);
  });

  testWidgets('ready guest login puts auth above a Full embedded timer', (
    tester,
  ) async {
    final container = _guestContainer(() async {});
    addTearDown(container.dispose);

    await _pumpGuestLogin(tester, container);
    await tester.pumpAndSettle();

    final auth = tester.getTopLeft(find.text('Sign in to Pomodoist'));
    final timer = tester.getTopLeft(find.byKey(const Key('focus-heading')));
    expect(auth.dy, lessThan(timer.dy));
    expect(find.text('No active session'), findsOneWidget);
    expect(find.byKey(const Key('focus-details-menu')), findsNothing);
    expect(find.byType(AdaptiveShell), findsNothing);
    expect(find.byType(Scaffold), findsOneWidget);
  });

  testWidgets('guest startup error stays inline and retries', (tester) async {
    var attempts = 0;
    final container = _guestContainer(() {
      attempts += 1;
      return attempts == 1
          ? Future<void>.error(StateError('guest startup failed'))
          : Future<void>.value();
    });
    addTearDown(container.dispose);

    await _pumpGuestLogin(tester, container);
    await tester.pumpAndSettle();

    expect(find.text('Sign in to Pomodoist'), findsOneWidget);
    expect(find.byKey(const Key('guest-timer-error')), findsOneWidget);
    expect(find.byKey(const Key('guest-timer-retry')), findsOneWidget);

    await tester.tap(find.byKey(const Key('guest-timer-retry')));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.byType(FocusScreen), findsOneWidget);
  });

  testWidgets('guest re-entry prepares data before showing the timer', (
    tester,
  ) async {
    final first = Completer<void>();
    final second = Completer<void>();
    var attempts = 0;
    final container = _guestContainer(() {
      attempts += 1;
      return attempts == 1 ? first.future : second.future;
    });
    addTearDown(container.dispose);

    await _pumpGuestLogin(tester, container);
    expect(attempts, 1);
    expect(find.byType(FocusScreen), findsNothing);

    first.complete();
    await tester.pumpAndSettle();
    expect(find.byType(FocusScreen), findsOneWidget);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SizedBox()),
      ),
    );
    await tester.pump();
    await tester.pump();

    await _pumpGuestLogin(tester, container);
    expect(attempts, 2);
    expect(find.byType(FocusScreen), findsNothing);

    second.complete();
    await tester.pumpAndSettle();
    expect(find.byType(FocusScreen), findsOneWidget);
  });

  for (final size in [
    const Size(390, 844),
    const Size(675, 450),
    const Size(1280, 800),
  ]) {
    testWidgets('guest login scrolls without overflow at $size', (
      tester,
    ) async {
      final previousSize = tester.view.physicalSize;
      final previousDevicePixelRatio = tester.view.devicePixelRatio;
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      addTearDown(() {
        tester.view
          ..physicalSize = previousSize
          ..devicePixelRatio = previousDevicePixelRatio;
      });
      final container = _guestContainer(() async {});
      addTearDown(container.dispose);

      await _pumpGuestLogin(tester, container);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Sign in to Pomodoist'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('focus-heading')),
        100,
        scrollable: find.descendant(
          of: find.byKey(const Key('guest-login-scroll')),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('focus-heading')), findsOneWidget);
      final heading = tester.getRect(find.byKey(const Key('focus-heading')));
      expect(heading.top, greaterThanOrEqualTo(0));
      expect(heading.bottom, lessThanOrEqualTo(size.height));
      expect(tester.takeException(), isNull);
    });
  }
}

ProviderContainer _guestContainer(Future<void> Function() startup) {
  return ProviderContainer(
    overrides: [
      accountClientProvider.overrideWithValue(_GuestAccount()),
      accountConfiguredProvider.overrideWithValue(true),
      accountAuthStateProvider.overrideWithValue(
        const AsyncData(AccountAuthState(signedIn: false)),
      ),
      accountOverviewProvider.overrideWith((ref) async => null),
      guestDataStartupProvider.overrideWith((ref) => startup()),
      focusRepositoryProvider.overrideWithValue(_GuestFocusRepository()),
    ],
  );
}

Future<void> _pumpGuestLogin(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const LoginScreen(showGuestTimer: true),
      ),
    ),
  );
  await tester.pump();
}

class _GuestAccount implements AccountClient {
  @override
  String? get currentUserId => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _GuestFocusRepository implements FocusRepository {
  @override
  Stream<List<FocusPresetItem>> watchPresets() => Stream.value(_presets);

  @override
  Stream<FocusRunItem?> watchActiveRun() => Stream.value(null);

  @override
  Stream<FocusIntervalItem?> watchActiveInterval() => Stream.value(null);

  @override
  Stream<List<FocusRunItem>> watchRunsForTask(String taskId) =>
      Stream.value(const []);

  @override
  Stream<List<FocusIntervalItem>> watchIntervalsForTask(String taskId) =>
      Stream.value(const []);

  @override
  Stream<List<FocusIntervalItem>> watchIntervalsForRun(String runId) =>
      Stream.value(const []);

  @override
  Stream<FocusDailyStats> watchDailyStats(DateTime localDate) => Stream.value(
    const FocusDailyStats(
      completedTasks: 0,
      completedFocusIntervals: 0,
      totalFocusSeconds: 0,
      interruptedIntervals: 0,
      plannedFocusIntervals: 0,
    ),
  );

  @override
  Future<String> createPreset(CreateFocusPresetInput input) async => 'created';

  @override
  Future<void> updatePreset(String id, UpdateFocusPresetInput input) async {}

  @override
  Future<void> deletePreset(String id) async {}

  @override
  Future<void> setDefaultPreset(String id) async {}

  @override
  Future<void> changeActiveRunPreset(String presetId) async {}

  @override
  Future<String> startRun(StartFocusRunInput input, {DateTime? now}) async =>
      'run';

  @override
  Future<void> startReadyInterval() async {}

  @override
  Future<void> pauseActiveInterval({DateTime? now}) async {}

  @override
  Future<void> resumeActiveInterval({DateTime? now}) async {}

  @override
  Future<void> restartActiveInterval({DateTime? now}) async {}

  @override
  Future<void> completeActiveInterval({DateTime? now}) async {}

  @override
  Future<void> skipActiveInterval({DateTime? now}) async {}

  @override
  Future<void> stopActiveRun({
    required StopFocusReason reason,
    DateTime? now,
  }) async {}

  @override
  Future<void> logDistraction({required String runId, String? note}) async {}
}

final _presets = [
  FocusPresetItem(
    id: 'guest-default',
    userId: 'guest',
    name: 'Classic',
    workSeconds: 25 * 60,
    shortBreakSeconds: 5 * 60,
    longBreakSeconds: 15 * 60,
    intervalsBeforeLongBreak: 4,
    autoStartBreaks: false,
    autoStartWork: false,
    allowPause: true,
    strictMode: false,
    isDefault: true,
    createdAt: DateTime.utc(2026, 9, 1),
    updatedAt: DateTime.utc(2026, 9, 1),
  ),
];
