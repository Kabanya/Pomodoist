import 'dart:async';

import 'package:app_account/app_account.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pomodoist/app/account_providers.dart';
import 'package:pomodoist/app/app_startup_gate.dart';
import 'package:pomodoist/app/providers.dart';
import 'package:pomodoist/app/router.dart';
import 'package:pomodoist/app/theme/app_theme.dart';
import 'package:pomodoist/core/db/app_database.dart' hide FocusDailyStats;
import 'package:pomodoist/core/time/clock.dart';
import 'package:pomodoist/features/focus/domain/focus_models.dart';
import 'package:pomodoist/features/focus/presentation/focus_screen.dart';
import 'package:pomodoist/features/focus/presentation/focus_view_mode.dart';
import 'package:pomodoist/features/planning/data/quick_add_service.dart';
import 'package:pomodoist/features/planning/domain/quick_add_parser.dart';
import 'package:pomodoist/features/productivity/domain/achievement_models.dart';
import 'package:pomodoist/features/productivity/domain/productivity_models.dart';
import 'package:pomodoist/features/onboarding/onboarding_gate.dart';
import 'package:pomodoist/features/tasks/domain/project_colors.dart';
import 'package:pomodoist/features/tasks/domain/task_models.dart';
import 'package:pomodoist/features/tasks/presentation/browse_screen.dart';
import 'package:pomodoist/features/tasks/presentation/widgets/task_motion.dart';
import 'package:pomodoist/features/tasks/presentation/widgets/task_selection_region.dart';
import 'package:pomodoist/features/integrations/google_calendar/data/google_calendar_repository.dart';
import 'package:pomodoist/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      onboardingCompletedPreferenceKey: true,
      launchOfferStartedAtPreferenceKey: '2026-01-01T10:00:00.000Z',
    });
  });

  test('login redirect uses web origin only on web', () {
    final baseUri = Uri.parse('http://localhost:7357/today');

    expect(
      pomodoistLoginRedirectFor(isWeb: true, baseUri: baseUri),
      'http://localhost:7357/login-callback',
    );
    expect(
      pomodoistLoginRedirectFor(isWeb: false, baseUri: baseUri),
      'pomodoist://login-callback',
    );
  });

  test('web app guard preserves the requested local destination', () {
    final redirect = webAppRedirectFor(
      isWeb: true,
      signedIn: false,
      uri: Uri.parse('/projects?filter=work'),
    );

    expect(redirect, isNotNull);
    final redirectUri = Uri.parse(redirect!);
    expect(redirectUri.path, '/login');
    expect(redirectUri.queryParameters['returnTo'], '/projects?filter=work');
  });

  test('web app guard leaves native and signed-in routes alone', () {
    final uri = Uri.parse('/today');

    expect(webAppRedirectFor(isWeb: false, signedIn: false, uri: uri), isNull);
    expect(webAppRedirectFor(isWeb: true, signedIn: true, uri: uri), isNull);
  });

  test(
    'web app guard leaves signed-out native CAPTCHA challenge accessible',
    () {
      final challenge = Uri.parse(
        '/auth/challenge?returnTo=pomodoist%3A%2F%2Fcaptcha-callback'
        '#state=${'A' * 43}',
      );

      expect(
        webAppRedirectFor(isWeb: true, signedIn: false, uri: challenge),
        isNull,
      );
    },
  );

  test('web startup preserves only the CAPTCHA challenge fragment', () {
    final challenge = Uri.parse(
      'https://app-test.pomodoist.com/auth/challenge'
      '?returnTo=pomodoist%3A%2F%2Fcaptcha-callback#state=${'A' * 43}',
    );
    final authCallback = Uri.parse(
      'https://app-test.pomodoist.com/login-callback#access_token=SECRET',
    );

    expect(
      initialAppLocationFor(isWeb: true, baseUri: challenge),
      '/auth/challenge?returnTo=pomodoist%3A%2F%2Fcaptcha-callback'
      '#state=${'A' * 43}',
    );
    expect(
      initialAppLocationFor(isWeb: true, baseUri: authCallback),
      '/login-callback',
    );
  });

  test('web startup sanitizes auth callback errors and secrets', () {
    final callback = Uri.parse(
      'https://app-test.pomodoist.com/login-callback?returnTo=%2Fprojects'
      '&code=SECRET_CODE#error=access_denied'
      '&error_description=SECRET_DESCRIPTION&access_token=SECRET_TOKEN',
    );

    final location = initialAppLocationFor(isWeb: true, baseUri: callback);

    expect(
      location,
      '/login-callback?returnTo=%2Fprojects&authFailure=cancelled',
    );
    expect(location, isNot(contains('SECRET')));
    expect(location, isNot(contains('access_denied')));
  });

  testWidgets('task row opens detail and Back returns to the source list', (
    tester,
  ) async {
    await _pumpApp(tester);

    expect(find.textContaining('Focus load:'), findsOneWidget);

    await tester.tap(find.text('Today task'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Focus history'), findsOneWidget);
    expect(find.textContaining('Focus load:'), findsNothing);

    await _pumpFrames(tester);

    expect(find.text('Focus history'), findsOneWidget);
    expect(find.text('Today task'), findsAtLeastNWidgets(1));

    await tester.tap(find.byTooltip('Back'));
    await _pumpFrames(tester);

    expect(find.text('Today'), findsAtLeastNWidgets(1));
    expect(find.text('Focus history'), findsNothing);
    expect(find.text('Today task'), findsOneWidget);
  });

  testWidgets('direct task route Back falls back to Today', (tester) async {
    late GoRouter router;
    await _pumpApp(tester, onRouter: (value) => router = value);

    router.go('/task/task-1');
    await _pumpFrames(tester);
    expect(find.text('Focus history'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await _pumpFrames(tester);

    expect(find.text('Today'), findsAtLeastNWidgets(1));
    expect(find.text('Focus history'), findsNothing);
  });

  testWidgets('auth callback deep link returns to settings', (tester) async {
    late GoRouter router;
    await _pumpApp(tester, onRouter: (value) => router = value);

    router.go('pomodoist://login-callback/?code=abc');
    await _pumpFrames(tester);
    expect(_routerUri(router), '/settings');

    router.go('/today');
    await _pumpFrames(tester);
    expect(_routerUri(router), '/today');

    router.go('/login-callback?code=abc');
    await _pumpFrames(tester);
    expect(_routerUri(router), '/settings');

    router.go('/login-callback?code=abc&returnTo=/today');
    await _pumpFrames(tester);
    expect(_routerUri(router), '/today');

    router.go('/login-callback?code=abc&returnTo=https://example.test');
    await _pumpFrames(tester);
    expect(_routerUri(router), '/settings');
  });

  testWidgets('auth callback failure returns to login without raw details', (
    tester,
  ) async {
    late GoRouter router;
    await _pumpApp(tester, onRouter: (value) => router = value);

    router.go(
      '/login-callback?returnTo=%2Fprojects&error_code=otp_expired'
      '&error_description=SECRET_DESCRIPTION&token=SECRET_TOKEN',
    );
    await _pumpFrames(tester);

    final uri = router.routeInformationProvider.value.uri;
    expect(uri.path, '/login');
    expect(uri.queryParameters['returnTo'], '/projects');
    expect(uri.queryParameters['authFailure'], 'linkExpired');
    expect(uri.toString(), isNot(contains('SECRET')));
    expect(
      find.text('This sign-in link is invalid or expired. Request a new link.'),
      findsOneWidget,
    );
  });

  testWidgets('focus widget deep link opens the focus screen', (tester) async {
    late GoRouter router;
    await _pumpApp(tester, onRouter: (value) => router = value);

    router.go('pomodoist://focus');
    await _pumpFrames(tester);

    expect(_routerUri(router), '/focus');
    expect(find.byType(FocusScreen), findsOneWidget);
  });

  testWidgets('login route redirects signed-in users to today', (tester) async {
    late GoRouter router;
    await _pumpApp(
      tester,
      onRouter: (value) => router = value,
      accountSignedIn: true,
    );

    router.go('/login');
    await _pumpFrames(tester);

    expect(_routerUri(router), '/today');
  });

  testWidgets('login route returns signed-in users to their destination', (
    tester,
  ) async {
    late GoRouter router;
    await _pumpApp(
      tester,
      onRouter: (value) => router = value,
      accountSignedIn: true,
    );

    router.go('/login?returnTo=/projects');
    await _pumpFrames(tester);

    expect(_routerUri(router), '/projects');
  });

  testWidgets('login route stays open for signed-out users', (tester) async {
    late GoRouter router;
    await _pumpApp(tester, onRouter: (value) => router = value);

    router.go('/login');
    await _pumpFrames(tester);

    expect(_routerUri(router), '/login');
    expect(find.text('Sign in to Pomodoist'), findsOneWidget);
  });

  testWidgets('login remains available while app startup is pending', (
    tester,
  ) async {
    late GoRouter router;
    final startupCompleter = Completer<void>();
    await _pumpApp(
      tester,
      onRouter: (value) => router = value,
      startupCompleter: startupCompleter,
    );

    router.go('/login');
    await _pumpFrames(tester);

    expect(_routerUri(router), '/login');
    expect(find.text('Sign in to Pomodoist'), findsOneWidget);
    expect(find.byKey(const Key('app-startup-loading')), findsNothing);
  });

  testWidgets('today waits for app startup to finish', (tester) async {
    final startupCompleter = Completer<void>();
    await _pumpApp(tester, startupCompleter: startupCompleter);

    expect(find.byKey(const Key('app-startup-loading')), findsOneWidget);
    expect(find.text('Preparing your tasks'), findsOneWidget);
  });

  testWidgets('register route redirects signed-in users to today', (
    tester,
  ) async {
    late GoRouter router;
    await _pumpApp(
      tester,
      onRouter: (value) => router = value,
      accountSignedIn: true,
    );

    router.go('/register');
    await _pumpFrames(tester);

    expect(_routerUri(router), '/today');
  });

  testWidgets('register route shows form for signed-out users', (tester) async {
    late GoRouter router;
    await _pumpApp(tester, onRouter: (value) => router = value);

    router.go('/register');
    await _pumpFrames(tester);

    expect(_routerUri(router), '/register');
    expect(find.byKey(const Key('register-email-field')), findsOneWidget);
    expect(find.byKey(const Key('register-password-field')), findsOneWidget);
    expect(find.byKey(const Key('register-submit-button')), findsOneWidget);
  });

  testWidgets('login links to register', (tester) async {
    late GoRouter router;
    await _pumpApp(tester, onRouter: (value) => router = value);

    router.go('/login');
    await _pumpFrames(tester);
    await tester.tap(find.byKey(const Key('login-register-link')));
    await _pumpFrames(tester);

    expect(_routerUri(router), '/register');
  });

  testWidgets('login passes its destination to register', (tester) async {
    late GoRouter router;
    await _pumpApp(tester, onRouter: (value) => router = value);

    router.go('/login?returnTo=/projects');
    await _pumpFrames(tester);
    await tester.tap(find.byKey(const Key('login-register-link')));
    await _pumpFrames(tester);

    expect(_routerUri(router), '/register?returnTo=%2Fprojects');
  });

  testWidgets('register links back to login', (tester) async {
    late GoRouter router;
    await _pumpApp(tester, onRouter: (value) => router = value);

    router.go('/register');
    await _pumpFrames(tester);
    await tester.tap(find.byKey(const Key('register-login-link')));
    await _pumpFrames(tester);

    expect(_routerUri(router), '/login');
  });

  testWidgets('register passes its destination back to login', (tester) async {
    late GoRouter router;
    await _pumpApp(tester, onRouter: (value) => router = value);

    router.go('/register?returnTo=/projects');
    await _pumpFrames(tester);
    await tester.tap(find.byKey(const Key('register-login-link')));
    await _pumpFrames(tester);

    expect(_routerUri(router), '/login?returnTo=%2Fprojects');
  });

  testWidgets('task list checkbox and focus icon do not open detail', (
    tester,
  ) async {
    final platformCalls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      platformCalls.add(call);
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final harness = await _pumpApp(tester);
    platformCalls.clear();

    await tester.tap(find.byKey(const Key('task-completion-control-task-1')));
    await _pumpFrames(tester);

    expect(harness.taskRepository.completedTaskIds, contains('task-1'));
    expect(find.text('Task completed'), findsOneWidget);
    _expectTaskCompletionSnackBar(tester);
    expect(find.text('Focus history'), findsNothing);
    expect(_hapticCalls(platformCalls), hasLength(1));

    await tester.tap(find.text('Undo'));
    await _pumpFrames(tester);
    expect(harness.taskRepository.uncompletedTaskIds, contains('task-1'));
    expect(_hapticCalls(platformCalls), hasLength(2));

    await tester.tap(find.byTooltip('Start focus').first);
    await _pumpFrames(tester);

    expect(harness.focusRepository.startInputs, hasLength(1));
    expect(harness.focusRepository.startInputs.single.taskId, 'task-1');
    expect(find.text('Focus started'), findsOneWidget);
    expect(find.text('Focus history'), findsNothing);
  });

  testWidgets('task row keeps comment and compact metadata', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    await _pumpApp(
      tester,
      tasks: [
        _task(
          'task-1',
          'Meta task',
          description: 'Compact comment',
          schedule: TaskSchedule.allDay(today),
          priority: 1,
          estimatedFocusIntervals: 2,
          completedFocusIntervals: 1,
          totalFocusSeconds: 51 * 60,
        ),
      ],
    );

    expect(find.text('Compact comment'), findsOneWidget);
    expect(find.text('1/2'), findsOneWidget);
    expect(find.text('p1'), findsNothing);
    expect(find.text('1/2 focus'), findsNothing);
    expect(find.text('51m'), findsNothing);
  });

  testWidgets('task row shows compact subtask progress before date', (
    tester,
  ) async {
    final today = _todaySchedule();
    await _pumpApp(
      tester,
      tasks: [
        _task('parent-1', 'Parent task', schedule: today, orderKey: '1'),
        _task('open-child', 'Open child', parentId: 'parent-1', orderKey: '2'),
        _task(
          'done-child',
          'Done child',
          parentId: 'parent-1',
          status: 'completed',
          orderKey: '3',
        ),
        _task(
          'nested-open',
          'Nested open',
          parentId: 'open-child',
          orderKey: '4',
        ),
        _task('leaf-1', 'Leaf task', schedule: today, orderKey: '5'),
      ],
    );

    expect(find.text('1/3'), findsOneWidget);
    expect(find.text('0/0'), findsNothing);
    expect(find.byIcon(Icons.account_tree_outlined), findsOneWidget);
    expect(
      tester.getTopLeft(find.byIcon(Icons.account_tree_outlined)).dx,
      lessThan(tester.getTopLeft(find.byIcon(Icons.event_outlined).first).dx),
    );
  });

  testWidgets(
    'task detail actions call repositories and delete navigates back',
    (tester) async {
      late GoRouter router;
      final harness = await _pumpApp(
        tester,
        onRouter: (value) => router = value,
      );

      router.go('/task/task-1');
      await _pumpFrames(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Start focus'));
      await _pumpFrames(tester);
      expect(harness.focusRepository.startInputs.single.taskId, 'task-1');
      expect(find.text('Focus started'), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Mark complete'));
      await _pumpFrames(tester);
      expect(harness.taskRepository.completedTaskIds, contains('task-1'));
      expect(find.text('Task completed'), findsOneWidget);
      _expectTaskCompletionSnackBar(tester);

      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await _pumpFrames(tester);
      expect(harness.taskRepository.deletedTaskIds, contains('task-1'));
      expect(find.text('Task deleted'), findsOneWidget);
      expect(find.text('Today'), findsAtLeastNWidgets(1));
      expect(find.text('Focus history'), findsNothing);
      await tester.tap(find.text('Undo'));
      await _pumpFrames(tester);
      expect(harness.taskRepository.restoredBatches.single.taskIds, {'task-1'});

      router.go('/task/done-1');
      await _pumpFrames(tester);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Mark open'));
      await _pumpFrames(tester);
      expect(harness.taskRepository.uncompletedTaskIds, contains('done-1'));
      expect(find.text('Task reopened'), findsOneWidget);
    },
  );

  testWidgets('recurring task detail delete can include following tasks', (
    tester,
  ) async {
    late GoRouter router;
    final today = _testToday();
    final harness = await _pumpApp(
      tester,
      onRouter: (value) => router = value,
      tasks: [
        _task(
          'repeat-1',
          'Repeating task',
          schedule: TaskSchedule.allDay(
            today,
            recurrence: const TaskRecurrence(
              interval: 1,
              unit: TaskRecurrenceUnit.week,
              seriesId: 'repeat-series',
            ),
          ),
        ),
      ],
    );

    router.go('/task/repeat-1');
    await _pumpFrames(tester);
    await tester.ensureVisible(find.widgetWithText(TextButton, 'Delete'));
    await _pumpFrames(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await _pumpFrames(tester);

    expect(find.text('Delete recurring task?'), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('delete-recurring-following-button')),
    );
    await _pumpFrames(tester);

    expect(harness.taskRepository.recurringDeleteTaskIds, ['repeat-1']);
    expect(harness.taskRepository.recurringDeleteIncludeFollowing, [true]);
    expect(find.text('Task deleted'), findsOneWidget);
    expect(find.text('Focus history'), findsNothing);
  });

  testWidgets('task detail title edits inline', (tester) async {
    late GoRouter router;
    final harness = await _pumpApp(tester, onRouter: (value) => router = value);

    router.go('/task/task-1');
    await _pumpFrames(tester);

    await tester.tap(find.byKey(const Key('task-title-display')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('task-title-editor')),
      'Renamed #Work завтра 10:30 45m',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _pumpFrames(tester);

    final patch = harness.taskRepository.updatePatches.single;
    final schedule = patch.schedule!;
    final tomorrow = DateTime.now().add(const Duration(days: 1));

    expect(patch.content, 'Renamed');
    expect(schedule.isTimed, isTrue);
    expect(schedule.start!.toLocal().year, tomorrow.year);
    expect(schedule.start!.toLocal().month, tomorrow.month);
    expect(schedule.start!.toLocal().day, tomorrow.day);
    expect(schedule.start!.toLocal().hour, 10);
    expect(schedule.start!.toLocal().minute, 30);
    expect(schedule.duration, const Duration(minutes: 45));
    expect(harness.taskRepository.movedProjectIds, ['project-1']);
    expect(find.byKey(const Key('task-title-editor')), findsNothing);
  });

  testWidgets('date-only title edit keeps the existing time range', (
    tester,
  ) async {
    late GoRouter router;
    final harness = await _pumpApp(
      tester,
      onRouter: (value) => router = value,
      tasks: [
        _task(
          'timed-title',
          'Scheduled task',
          schedule: _scheduleAt(
            DateTime(2026, 9, 3),
            18,
            30,
            const Duration(minutes: 45),
          ),
        ),
      ],
    );

    router.go('/task/timed-title');
    await _pumpFrames(tester);
    await tester.tap(find.byKey(const Key('task-title-display')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('task-title-editor')),
      'Renamed 2026-09-04',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _pumpFrames(tester);

    final patch = harness.taskRepository.updatePatches.single;
    expect(patch.content, 'Renamed');
    expect(patch.schedule!.start!.toLocal(), DateTime(2026, 9, 4, 18, 30));
    expect(patch.schedule!.end!.toLocal(), DateTime(2026, 9, 4, 19, 15));
    expect(patch.estimatedFocusIntervals, isNull);
  });

  testWidgets('task detail title edit applies quick-add metadata', (
    tester,
  ) async {
    late GoRouter router;
    final harness = await _pumpApp(
      tester,
      onRouter: (value) => router = value,
      tasks: [
        _task(
          'task-1',
          'Scheduled task',
          schedule: TaskSchedule.allDay(DateTime(2026, 5, 5)),
        ),
      ],
    );

    router.go('/task/task-1');
    await _pumpFrames(tester);

    await tester.tap(find.byKey(const Key('task-title-display')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('task-title-editor')),
      'Refined #W',
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('quick-add-suggestion-#Work')),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);

    await tester.enterText(
      find.byKey(const Key('task-title-editor')),
      'Refined #Work @c',
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('quick-add-suggestion-@coding')),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);

    await tester.enterText(
      find.byKey(const Key('task-title-editor')),
      'Refined #Work @coding 17:30-17:45',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _pumpFrames(tester);

    final patch = harness.taskRepository.updatePatches.single;
    expect(patch.content, 'Refined');
    expect(patch.labelNames, ['coding']);
    expect(patch.schedule!.start!.toLocal(), DateTime(2026, 5, 5, 17, 30));
    expect(patch.schedule!.end!.toLocal(), DateTime(2026, 5, 5, 17, 45));
    expect(harness.taskRepository.movedProjectIds, ['project-1']);
  });

  testWidgets('task title rename keeps its existing schedule', (tester) async {
    late GoRouter router;
    final harness = await _pumpApp(
      tester,
      onRouter: (value) => router = value,
      tasks: [
        _task(
          'task-1',
          'Scheduled task',
          schedule: TaskSchedule.timed(
            start: DateTime(2026, 5, 5, 10),
            end: DateTime(2026, 5, 5, 11),
          ),
        ),
      ],
    );

    router.go('/task/task-1');
    await _pumpFrames(tester);

    await tester.tap(find.byKey(const Key('task-title-display')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('task-title-editor')),
      'Renamed task',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _pumpFrames(tester);

    final patch = harness.taskRepository.updatePatches.single;
    expect(patch.content, 'Renamed task');
    expect(patch.schedule, isNull);
    expect(patch.dueDate, isNull);
  });

  testWidgets('project quick add assigns the active project', (tester) async {
    late GoRouter router;
    final harness = await _pumpApp(tester, onRouter: (value) => router = value);

    router.go('/project/project-1');
    await _pumpFrames(tester);

    await tester.enterText(find.byType(TextField).first, 'Task in project');
    await tester.tap(find.byTooltip('Add'));
    await _pumpFrames(tester);

    expect(harness.taskRepository.createdInputs.single.projectId, 'project-1');
  });

  testWidgets('task detail comment edits and clears inline', (tester) async {
    late GoRouter router;
    final harness = await _pumpApp(tester, onRouter: (value) => router = value);

    router.go('/task/task-1');
    await _pumpFrames(tester);

    await tester.enterText(
      find.byKey(const Key('task-comment-editor')),
      'Call before noon',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await _pumpFrames(tester);

    expect(harness.taskRepository.updatePatches.single.updateDescription, true);
    expect(
      harness.taskRepository.updatePatches.single.description,
      'Call before noon',
    );

    router.go('/task/inbox-1');
    await _pumpFrames(tester);
    await tester.enterText(find.byKey(const Key('task-comment-editor')), '');
    FocusManager.instance.primaryFocus?.unfocus();
    await _pumpFrames(tester);

    final clearPatch = harness.taskRepository.updatePatches.last;
    expect(clearPatch.updateDescription, true);
    expect(clearPatch.description, isNull);
  });

  testWidgets('task detail priority chip updates priority', (tester) async {
    late GoRouter router;
    final harness = await _pumpApp(tester, onRouter: (value) => router = value);

    router.go('/task/task-1');
    await _pumpFrames(tester);

    await tester.tap(find.byKey(const Key('task-detail-priority-chip')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(CheckedPopupMenuItem<int>, 'Priority 1'),
    );
    await tester.pumpAndSettle();

    expect(harness.taskRepository.updatePatches.single.priority, 1);
  });

  testWidgets('task detail schedule chip updates and clears date', (
    tester,
  ) async {
    late GoRouter router;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final harness = await _pumpApp(
      tester,
      onRouter: (value) => router = value,
      tasks: [
        _task(
          'timed-task',
          'Timed task',
          schedule: _scheduleAt(today, 18, 30, const Duration(minutes: 45)),
        ),
      ],
    );

    router.go('/task/timed-task');
    await _pumpFrames(tester);

    await tester.tap(find.byKey(const Key('task-detail-schedule-chip')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tomorrow').last);
    await tester.pumpAndSettle();

    final tomorrowSchedule =
        harness.taskRepository.updatePatches.single.schedule!;
    final tomorrow = today.add(const Duration(days: 1));
    expect(tomorrowSchedule.isTimed, isTrue);
    expect(tomorrowSchedule.start!.toLocal(), _dateAt(tomorrow, 18, 30));
    expect(tomorrowSchedule.end!.toLocal(), _dateAt(tomorrow, 19, 15));

    await tester.tap(find.byKey(const Key('task-detail-schedule-chip')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All-day').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK').last);
    await tester.pumpAndSettle();

    expect(
      harness.taskRepository.updatePatches.last.schedule!.isAllDay,
      isTrue,
    );

    await tester.tap(find.byKey(const Key('task-detail-schedule-chip')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear date').last);
    await tester.pumpAndSettle();

    expect(harness.taskRepository.updatePatches.last.clearSchedule, isTrue);
  });

  testWidgets('task row secondary click completes through multi-select', (
    tester,
  ) async {
    final harness = await _pumpApp(tester);

    await _openTaskContextMenu(tester, 'Today task');

    expect(find.text('Select'), findsOneWidget);
    expect(find.text('Focus history'), findsNothing);

    await tester.tap(find.text('Select').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Complete selected'));
    await tester.pumpAndSettle();

    expect(harness.taskRepository.completedTaskIds, ['task-1']);
    expect(find.text('Task completed'), findsOneWidget);
    _expectTaskCompletionSnackBar(tester);
    expect(find.text('Focus history'), findsNothing);

    await tester.tap(find.text('Undo'));
    await _pumpFrames(tester);
    expect(harness.taskRepository.uncompletedTaskIds, ['task-1']);
  });

  testWidgets('task menu enters multi-selection and toggles visible rows', (
    tester,
  ) async {
    final today = _todaySchedule();
    await _pumpApp(
      tester,
      tasks: [
        _task('select-1', 'First selectable task', schedule: today),
        _task('select-2', 'Second selectable task', schedule: today),
      ],
    );

    await _openTaskContextMenu(tester, 'First selectable task');
    await tester.tap(find.text('Select').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('task-selection-header')), findsOneWidget);
    expect(find.text('1 selected'), findsOneWidget);
    expect(find.text('Due'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);

    await tester.tap(find.text('Second selectable task'));
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(find.text('Deselect all'));
    await tester.pump();
    expect(find.text('0 selected'), findsOneWidget);
  });

  testWidgets('bulk due preset keeps a typed time range and closes selection', (
    tester,
  ) async {
    final today = _todaySchedule();
    final harness = await _pumpApp(
      tester,
      tasks: [
        _task('due-1', 'First due task', schedule: today),
        _task('due-2', 'Second due task', schedule: today),
      ],
    );

    await _openTaskContextMenu(tester, 'First due task');
    await tester.tap(find.text('Select').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Second due task'));
    await tester.tap(find.text('Due'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('task-due-input')),
      '20:00-21:00',
    );
    await tester.tap(find.text('Tomorrow').last);
    await _pumpFrames(tester);

    expect(harness.taskRepository.updatePatches, hasLength(2));
    for (final patch in harness.taskRepository.updatePatches) {
      final schedule = patch.schedule!;
      expect(schedule.start!.toLocal(), DateTime(2026, 1, 3, 20));
      expect(schedule.end!.toLocal(), DateTime(2026, 1, 3, 21));
    }
    expect(find.byKey(const Key('task-selection-header')), findsNothing);
    expect(find.byKey(const Key('task-selection-bottom-bar')), findsNothing);
  });

  testWidgets('Schedule date preset keeps each selected task time range', (
    tester,
  ) async {
    final today = DateTime(2026, 1, 2);
    final harness = await _pumpApp(
      tester,
      tasks: [
        _task(
          'due-1',
          'First timed task',
          schedule: _scheduleAt(today, 18, 30, const Duration(minutes: 45)),
        ),
        _task(
          'due-2',
          'Second timed task',
          schedule: _scheduleAt(today, 20, 15, const Duration(hours: 1)),
        ),
      ],
    );

    await _openTaskContextMenu(tester, 'First timed task');
    await tester.tap(find.text('Select').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Second timed task'));
    await tester.tap(find.text('Due'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tomorrow').last);
    await _pumpFrames(tester);

    expect(harness.taskRepository.updatePatches, hasLength(2));
    final first = harness.taskRepository.updatePatches[0].schedule!;
    final second = harness.taskRepository.updatePatches[1].schedule!;
    expect(first.start!.toLocal(), DateTime(2026, 1, 3, 18, 30));
    expect(first.end!.toLocal(), DateTime(2026, 1, 3, 19, 15));
    expect(second.start!.toLocal(), DateTime(2026, 1, 3, 20, 15));
    expect(second.end!.toLocal(), DateTime(2026, 1, 3, 21, 15));
  });

  testWidgets('due panel validates text, uses calendar, and clears due', (
    tester,
  ) async {
    final harness = await _pumpApp(tester);
    await _openTaskContextMenu(tester, 'Today task');
    await tester.tap(find.text('Select').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Due'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('task-due-input')),
      '25.08 18:00',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _pumpFrames(tester);
    expect(
      harness.taskRepository.updatePatches.single.schedule!.start!.toLocal(),
      DateTime(2026, 8, 25, 18),
    );

    await _openTaskContextMenu(tester, 'Today task');
    await tester.tap(find.text('Select').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Due'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('task-due-input')),
      '31.02 99:99',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.text('Enter a valid date or time'), findsOneWidget);
    expect(harness.taskRepository.updatePatches, hasLength(1));

    await tester.enterText(find.byKey(const Key('task-due-input')), '');
    final day = find.descendant(
      of: find.byType(CalendarDatePicker),
      matching: find.text('15'),
    );
    await tester.ensureVisible(day);
    await tester.tap(day);
    await tester.tap(find.byKey(const Key('task-due-done')));
    await _pumpFrames(tester);
    expect(harness.taskRepository.updatePatches, hasLength(2));
    expect(
      harness.taskRepository.updatePatches.last.schedule!.displayDate,
      DateTime(2026, 1, 15),
    );

    await _openTaskContextMenu(tester, 'Today task');
    await tester.tap(find.text('Select').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Due'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear due'));
    await _pumpFrames(tester);
    expect(harness.taskRepository.updatePatches.last.clearSchedule, isTrue);
  });

  testWidgets('bulk project labels priority and duplicate close selection', (
    tester,
  ) async {
    final today = _todaySchedule();
    final harness = await _pumpApp(
      tester,
      tasks: [
        _task('action-1', 'First action task', schedule: today),
        _task('action-2', 'Second action task', schedule: today),
      ],
    );
    Future<void> selectBoth() async {
      await _openTaskContextMenu(tester, 'First action task');
      await tester.tap(find.text('Select').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Second action task'));
      await tester.pump();
    }

    await selectBoth();
    await tester.tap(find.text('Project'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Work'));
    await tester.pumpAndSettle();
    expect(harness.taskRepository.movedProjectIds, ['project-1', 'project-1']);
    expect(find.byKey(const Key('task-selection-header')), findsNothing);

    await selectBoth();
    await tester.tap(find.text('Labels'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('coding'));
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(
      harness.taskRepository.updatePatches
          .where((patch) => patch.labelNames != null)
          .map((patch) => patch.labelNames),
      everyElement(['coding']),
    );
    expect(find.byKey(const Key('task-selection-header')), findsNothing);

    await selectBoth();
    await tester.tap(find.text('Priority'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Priority 1'));
    await tester.pumpAndSettle();
    expect(
      harness.taskRepository.updatePatches
          .where((patch) => patch.priority != null)
          .map((patch) => patch.priority),
      [1, 1],
    );
    expect(find.byKey(const Key('task-selection-header')), findsNothing);

    await selectBoth();
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duplicate'));
    await tester.pumpAndSettle();
    expect(find.text('Selected only'), findsOneWidget);
    expect(find.text('With subtasks'), findsOneWidget);
    await tester.tap(find.text('With subtasks'));
    await tester.pumpAndSettle();
    expect(harness.taskRepository.duplicatedTaskIds.single, {
      'action-1',
      'action-2',
    });
    expect(harness.taskRepository.duplicateIncludeSubtasks.single, isTrue);
    expect(find.byKey(const Key('task-selection-header')), findsNothing);
    expect(find.byKey(const Key('task-selection-bottom-bar')), findsNothing);
  });

  testWidgets('completed multi-select reopens tasks and offers one Undo', (
    tester,
  ) async {
    late GoRouter router;
    final harness = await _pumpApp(
      tester,
      onRouter: (value) => router = value,
      tasks: [
        _task(
          'reopen-1',
          'Reopen selected task',
          status: 'completed',
          completedAt: DateTime.now().toUtc(),
        ),
      ],
    );
    router.go('/browse/completed');
    await _pumpFrames(tester);
    await _openTaskContextMenu(tester, 'Reopen selected task');
    await tester.tap(find.text('Select').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reopen selected'));
    await tester.pumpAndSettle();

    expect(harness.taskRepository.uncompletedTaskIds, ['reopen-1']);
    expect(find.byKey(const Key('task-selection-header')), findsNothing);
    expect(find.text('Undo'), findsOneWidget);
  });

  testWidgets('bulk partial errors leave only failed tasks selected', (
    tester,
  ) async {
    final today = _todaySchedule();
    await _pumpApp(
      tester,
      updateErrorTaskIds: {'failure-2'},
      tasks: [
        _task('success-1', 'Successful task', schedule: today),
        _task('failure-2', 'Failed task', schedule: today),
      ],
    );
    await _openTaskContextMenu(tester, 'Successful task');
    await tester.tap(find.text('Select').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Failed task'));
    await tester.tap(find.text('Priority'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Priority 1'));
    await tester.pumpAndSettle();

    expect(find.text('1 selected'), findsOneWidget);
    expect(find.text('1 task could not be updated'), findsOneWidget);
    expect(_taskCheckboxValue(tester, 'Successful task'), isFalse);
    expect(_taskCheckboxValue(tester, 'Failed task'), isTrue);
  });

  testWidgets('touch long press opens task actions and drag uses its handle', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await _pumpApp(tester);

      expect(
        find.byKey(const ValueKey('task-drag-handle-task-1')),
        findsOneWidget,
      );
      await tester.longPress(find.text('Today task'));
      await tester.pumpAndSettle();

      expect(find.text('Select'), findsOneWidget);
      expect(find.text('Schedule'), findsOneWidget);
      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('task-drag-handle-task-1')),
        findsNothing,
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Escape and route changes close task selection', (tester) async {
    late GoRouter router;
    await _pumpApp(tester, onRouter: (value) => router = value);

    await _openTaskContextMenu(tester, 'Today task');
    await tester.tap(find.text('Select').last);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byKey(const Key('task-selection-header')), findsNothing);

    await _openTaskContextMenu(tester, 'Today task');
    await tester.tap(find.text('Select').last);
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(_routerUri(router), '/today');
    expect(find.byKey(const Key('task-selection-header')), findsNothing);

    await _openTaskContextMenu(tester, 'Today task');
    await tester.tap(find.text('Select').last);
    await tester.pumpAndSettle();
    router.go('/inbox');
    await _pumpFrames(tester);
    expect(find.byKey(const Key('task-selection-header')), findsNothing);
  });

  testWidgets('selection is available on every scoped task screen', (
    tester,
  ) async {
    late GoRouter router;
    final today = _todaySchedule();
    await _pumpApp(
      tester,
      onRouter: (value) => router = value,
      tasks: [
        _task('today-scope', 'Today scoped', schedule: today),
        _task('inbox-scope', 'Inbox scoped'),
        _task('project-scope', 'Project scoped', projectId: 'project-1'),
        _task(
          'done-scope',
          'Completed scoped',
          status: 'completed',
          schedule: today,
          completedAt: DateTime.now().toUtc(),
        ),
        _task(
          'upcoming-scope',
          'Upcoming scoped',
          schedule: TaskSchedule.allDay(
            today.displayDate.add(const Duration(days: 1)),
          ),
        ),
      ],
    );

    for (final target in [
      ('/today', 'Today scoped'),
      ('/inbox', 'Inbox scoped'),
      ('/project/project-1', 'Project scoped'),
      ('/browse/completed', 'Completed scoped'),
      ('/upcoming', 'Upcoming scoped'),
      ('/priority-matrix', 'Today scoped'),
    ]) {
      router.go(target.$1);
      await _pumpFrames(tester);
      expect(find.text(target.$2), findsOneWidget, reason: target.$1);
      await _openTaskContextMenu(tester, target.$2);
      expect(find.text('Select'), findsOneWidget, reason: target.$1);
      await tester.tap(find.text('Select').last);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('task-selection-header')),
        findsOneWidget,
        reason: target.$1,
      );
      router.go('/settings');
      await _pumpFrames(tester);
    }

    router.go('/search');
    await _pumpFrames(tester);
    await tester.enterText(find.byType(TextField).first, 'Today');
    await _pumpFrames(tester);
    await _openTaskContextMenu(tester, 'Today scoped');
    await tester.tap(find.text('Select').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('task-selection-header')), findsOneWidget);
  });

  test('selection closes only when selected visible rows disappear', () async {
    Future<void> noop(BuildContext _) async {}
    final controller = TaskSelectionController(
      showDue: noop,
      showProject: noop,
      showLabels: noop,
      showPriority: noop,
      showMore: noop,
      duplicate: noop,
      delete: noop,
    );
    addTearDown(controller.dispose);
    final task = _task('selection-controller', 'Selection controller');

    controller.updateVisible([task]);
    controller.begin(task.id);
    controller.toggle(task.id);
    expect(controller.active, isTrue);
    expect(controller.selectedCount, 0);

    controller.toggle(task.id);
    controller.updateVisible(const <TaskItem>[]);
    expect(controller.active, isFalse);
  });

  test('due presets use current Saturday and strictly future Monday', () {
    expect(taskWeekendPresetDate(DateTime(2026, 1, 2)), DateTime(2026, 1, 3));
    expect(taskWeekendPresetDate(DateTime(2026, 1, 3)), DateTime(2026, 1, 3));
    expect(taskNextWeekPresetDate(DateTime(2026, 1, 5)), DateTime(2026, 1, 12));
  });

  testWidgets('task quick actions update priority', (tester) async {
    final harness = await _pumpApp(tester);

    await _openTaskContextMenu(tester, 'Today task');
    await tester.tap(find.text('Priority').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Priority 1').last);
    await tester.pumpAndSettle();

    expect(harness.taskRepository.updatePatches.single.priority, 1);
  });

  testWidgets('recurring task quick delete can delete only this task', (
    tester,
  ) async {
    final today = _testToday();
    final harness = await _pumpApp(
      tester,
      tasks: [
        _task(
          'repeat-1',
          'Repeating task',
          schedule: TaskSchedule.allDay(
            today,
            recurrenceSeriesId: 'repeat-series',
          ),
        ),
      ],
    );

    await _openTaskContextMenu(tester, 'Repeating task');
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();

    expect(find.text('Delete selected tasks?'), findsOneWidget);
    await tester.tap(find.text('Delete this task'));
    await _pumpFrames(tester);

    expect(harness.taskRepository.recurringDeleteTaskIds, ['repeat-1']);
    expect(harness.taskRepository.recurringDeleteIncludeFollowing, [false]);
  });

  testWidgets('task detail adds a subtask under the current task', (
    tester,
  ) async {
    late GoRouter router;
    final harness = await _pumpApp(
      tester,
      onRouter: (value) => router = value,
      tasks: [_task('parent-1', 'Parent task')],
    );

    router.go('/task/parent-1');
    await _pumpFrames(tester);

    await tester.enterText(
      find.byKey(const Key('add-subtask-field')),
      'Draft outline tomorrow p1 @writing 2p',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _pumpFrames(tester);

    final input = harness.taskRepository.createdInputs.single;
    expect(input.content, 'Draft outline');
    expect(input.projectId, inboxProjectId);
    expect(input.parentId, 'parent-1');
    expect(input.priority, 1);
    expect(input.labelNames, ['writing']);
    expect(input.estimatedFocusIntervals, 2);
  });

  testWidgets('subtask quick Tomorrow keeps its existing time range', (
    tester,
  ) async {
    late GoRouter router;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final harness = await _pumpApp(
      tester,
      onRouter: (value) => router = value,
      tasks: [
        _task('parent-1', 'Parent task'),
        _task(
          'child-1',
          'Timed child',
          parentId: 'parent-1',
          schedule: _scheduleAt(today, 18, 30, const Duration(minutes: 45)),
        ),
      ],
    );

    router.go('/task/parent-1');
    await _pumpFrames(tester);
    await _openTaskContextMenu(tester, 'Timed child');
    await tester.tap(find.text('Tomorrow').last);
    await _pumpFrames(tester);

    final schedule = harness.taskRepository.updatePatches.single.schedule!;
    final tomorrow = today.add(const Duration(days: 1));
    expect(schedule.start!.toLocal(), _dateAt(tomorrow, 18, 30));
    expect(schedule.end!.toLocal(), _dateAt(tomorrow, 19, 15));
  });

  testWidgets(
    'task list keeps nested rows compact without visible drag controls',
    (tester) async {
      final today = _todaySchedule();
      await _pumpApp(
        tester,
        tasks: [
          _task('parent-1', 'Parent task', schedule: today, orderKey: '1'),
          _task(
            'child-1',
            'Child task',
            schedule: today,
            parentId: 'parent-1',
            orderKey: '2',
          ),
        ],
      );

      expect(find.text('Parent task'), findsOneWidget);
      expect(find.text('Child task'), findsOneWidget);
      expect(find.byKey(const Key('task-drag-parent-1')), findsNothing);
      expect(find.byKey(const Key('task-collapse-parent-1')), findsNothing);
      expect(tester.getTopLeft(find.text('Parent task')).dx, lessThan(56));
      expect(
        tester.getTopLeft(find.text('Child task')).dx,
        greaterThan(tester.getTopLeft(find.text('Parent task')).dx),
      );
      expect(
        tester.getTopLeft(find.text('Child task')).dx -
            tester.getTopLeft(find.text('Parent task')).dx,
        lessThan(30),
      );
    },
  );

  testWidgets('dragging a task onto another task makes it a subtask', (
    tester,
  ) async {
    final today = _todaySchedule();
    final harness = await _pumpApp(
      tester,
      tasks: [
        _task('target-1', 'Target task', schedule: today, orderKey: '1'),
        _task('dragged-1', 'Dragged task', schedule: today, orderKey: '2'),
      ],
    );

    await _dragTaskOnto(tester, 'Dragged task', 'Target task');

    expect(harness.taskRepository.movedParentIds.last, 'target-1');
    expect(harness.taskRepository.movedProjectIds.last, inboxProjectId);
  });

  testWidgets('mobile drag to empty list space makes a subtask a root task', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final today = _todaySchedule();
      final harness = await _pumpApp(
        tester,
        tasks: [
          _task('parent-1', 'Parent task', schedule: today, orderKey: '1'),
          _task(
            'child-1',
            'Child task',
            schedule: today,
            parentId: 'parent-1',
            orderKey: '2',
          ),
        ],
      );

      await _dragTaskToRootDropZone(tester, 'Child task');

      final movedTask = await harness.taskRepository.watchTask('child-1').first;
      expect(movedTask?.parentId, isNull);
      expect(movedTask?.orderKey, isNot('2'));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
    'mobile drag to task gap makes a subtask root in normal list order',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        final today = _todaySchedule();
        final harness = await _pumpApp(
          tester,
          tasks: [
            _task(
              'parent-1',
              'Parent task',
              schedule: today,
              orderKey: '00000000000000000001',
            ),
            _task(
              'child-1',
              'Child task',
              schedule: today,
              parentId: 'parent-1',
              orderKey: '00000000000000000002',
            ),
            _task(
              'later-root',
              'Later root',
              schedule: today,
              orderKey: '00000000000000000003',
            ),
          ],
        );
        final gap = find.byKey(const Key('task-root-gap-0'));

        expect(gap, findsOneWidget);
        expect(tester.getSize(gap).height, 12);

        final gesture = await tester.startGesture(
          tester.getCenter(_taskDragSource('Child task')),
        );
        await tester.pump(const Duration(milliseconds: 600));
        await gesture.moveTo(tester.getCenter(gap));
        await tester.pump();

        expect(tester.getSize(gap).height, 12);
        await tester.pump(const Duration(milliseconds: 80));
        expect(tester.getSize(gap).height, inExclusiveRange(12, 32));
        await tester.pump(const Duration(milliseconds: 80));
        expect(tester.getSize(gap).height, 32);
        expect(find.text('Make parent task'), findsOneWidget);

        await gesture.up();
        await tester.pumpAndSettle();

        final movedTask = await harness.taskRepository
            .watchTask('child-1')
            .first;
        expect(movedTask?.parentId, isNull);
        expect(
          movedTask!.orderKey.compareTo('00000000000000000003'),
          greaterThan(0),
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('mobile task gap ignores a task that is already a root', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final harness = await _pumpApp(
        tester,
        tasks: [
          _task(
            'root-1',
            'First root',
            schedule: _todaySchedule(),
            orderKey: '1',
          ),
          _task(
            'root-2',
            'Second root',
            schedule: _todaySchedule(),
            orderKey: '2',
          ),
        ],
      );

      await _dragTaskToRootGap(tester, 'First root');

      expect(harness.taskRepository.movedParentIds, isEmpty);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('mobile root drop ignores a task that is already a root', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final harness = await _pumpApp(
        tester,
        tasks: [
          _task(
            'root-1',
            'Root task',
            schedule: _todaySchedule(),
            orderKey: '1',
          ),
        ],
      );

      await _dragTaskToRootDropZone(tester, 'Root task');

      expect(harness.taskRepository.movedParentIds, isEmpty);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('empty list drop zone is limited to mobile platforms', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await _pumpApp(
        tester,
        tasks: [
          _task('mobile-root', 'Mobile root', schedule: _todaySchedule()),
          _task('mobile-root-2', 'Mobile root 2', schedule: _todaySchedule()),
        ],
      );
      expect(find.byKey(const Key('task-root-drop-zone')), findsOneWidget);
      expect(find.byKey(const Key('task-root-gap-0')), findsOneWidget);

      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await _pumpApp(
        tester,
        tasks: [
          _task('desktop-root', 'Desktop root', schedule: _todaySchedule()),
          _task('desktop-root-2', 'Desktop root 2', schedule: _todaySchedule()),
        ],
      );
      expect(find.byKey(const Key('task-root-drop-zone')), findsNothing);
      expect(find.byKey(const Key('task-root-gap-0')), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('mobile root drop reports move errors', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final today = _todaySchedule();
      await _pumpApp(
        tester,
        taskMoveError: StateError('move failed'),
        tasks: [
          _task('parent-1', 'Parent task', schedule: today),
          _task('child-1', 'Child task', schedule: today, parentId: 'parent-1'),
        ],
      );

      await _dragTaskToRootDropZone(tester, 'Child task');

      expect(find.text('1 task could not be updated'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('mobile task gap reports move errors', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final today = _todaySchedule();
      await _pumpApp(
        tester,
        taskMoveError: StateError('move failed'),
        tasks: [
          _task('parent-1', 'Parent task', schedule: today),
          _task('child-1', 'Child task', schedule: today, parentId: 'parent-1'),
        ],
      );

      await _dragTaskToRootGap(tester, 'Child task');

      expect(find.text('1 task could not be updated'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('macOS mouse drag on task text makes it a subtask', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final today = _todaySchedule();
      final harness = await _pumpApp(
        tester,
        tasks: [
          _task('target-1', 'Target task', schedule: today, orderKey: '1'),
          _task('dragged-1', 'Dragged task', schedule: today, orderKey: '2'),
        ],
      );

      await _dragTaskOnto(
        tester,
        'Dragged task',
        'Target task',
        holdDuration: Duration.zero,
        kind: PointerDeviceKind.mouse,
      );

      expect(harness.taskRepository.movedParentIds.last, 'target-1');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('dragging a task onto itself is ignored', (tester) async {
    final today = _todaySchedule();
    final harness = await _pumpApp(
      tester,
      tasks: [_task('task-1', 'Self task', schedule: today)],
    );

    await _dragTaskOnto(tester, 'Self task', 'Self task');

    expect(harness.taskRepository.movedParentIds, isEmpty);
  });

  testWidgets('priority matrix groups tasks by priority and sorts by date', (
    tester,
  ) async {
    late GoRouter router;
    await _pumpApp(
      tester,
      onRouter: (value) => router = value,
      tasks: [
        _task('p1-late', 'P1 20:00', priority: 1, schedule: _timedSchedule(20)),
        _task(
          'p1-early',
          'P1 19:00',
          priority: 1,
          schedule: _timedSchedule(19),
        ),
        _task('p1-none', 'P1 no date', priority: 1),
        _task('p2-one', 'P2 task', priority: 2),
        _task('p3-one', 'P3 task', priority: 3),
        _task('p4-one', 'P4 task', priority: 4),
        _task('done-p1', 'Done P1 task', priority: 1, status: 'completed'),
      ],
    );

    router.go('/priority-matrix');
    await _pumpFrames(tester);

    expect(find.text('Priority Matrix'), findsOneWidget);
    expect(find.text('Do now'), findsOneWidget);
    expect(find.text('Schedule'), findsOneWidget);
    expect(find.text('Delegate'), findsOneWidget);
    expect(find.text('Drop'), findsOneWidget);
    expect(find.text('Done P1 task'), findsNothing);

    expect(
      tester.getTopLeft(find.text('P1 19:00')).dy,
      lessThan(tester.getTopLeft(find.text('P1 20:00')).dy),
    );
    expect(
      tester.getTopLeft(find.text('P1 20:00')).dy,
      lessThan(tester.getTopLeft(find.text('P1 no date')).dy),
    );
  });

  testWidgets('priority matrix shows semantic axes on wide layouts', (
    tester,
  ) async {
    late GoRouter router;
    await _pumpApp(
      tester,
      onRouter: (value) => router = value,
      size: const Size(1200, 900),
    );

    router.go('/priority-matrix');
    await _pumpFrames(tester);

    expect(
      find.byKey(const Key('priority-matrix-axis-urgent')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('priority-matrix-axis-not-urgent')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('priority-matrix-axis-important')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('priority-matrix-axis-not-important')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('priority-matrix-meaning-p1')), findsNothing);
  });

  testWidgets('priority matrix shows meanings inside narrow quadrants', (
    tester,
  ) async {
    late GoRouter router;
    await _pumpApp(tester, onRouter: (value) => router = value);

    router.go('/priority-matrix');
    await _pumpFrames(tester);

    expect(find.byKey(const Key('priority-matrix-axis-urgent')), findsNothing);
    for (final priority in [1, 2, 3, 4]) {
      expect(
        find.byKey(Key('priority-matrix-meaning-p$priority')),
        findsOneWidget,
      );
    }
    expect(find.text('Important / Urgent'), findsOneWidget);
    expect(find.text('Important / Not urgent'), findsOneWidget);
    expect(find.text('Not important / Urgent'), findsOneWidget);
    expect(find.text('Not important / Not urgent'), findsOneWidget);
  });

  testWidgets('priority matrix mirrors Arabic axes with their quadrants', (
    tester,
  ) async {
    late GoRouter router;
    await _pumpApp(
      tester,
      onRouter: (value) => router = value,
      size: const Size(1200, 900),
      locale: const Locale('ar'),
    );

    router.go('/priority-matrix');
    await _pumpFrames(tester);

    final urgent = find.byKey(const Key('priority-matrix-axis-urgent'));
    final notUrgent = find.byKey(const Key('priority-matrix-axis-not-urgent'));
    final p1 = find.byKey(const Key('priority-matrix-quadrant-p1'));
    final p2 = find.byKey(const Key('priority-matrix-quadrant-p2'));

    expect(find.text('عاجل'), findsOneWidget);
    expect(tester.getCenter(p1).dx, greaterThan(tester.getCenter(p2).dx));
    expect(
      tester.getCenter(urgent).dx > tester.getCenter(notUrgent).dx,
      tester.getCenter(p1).dx > tester.getCenter(p2).dx,
    );
  });

  testWidgets('priority matrix drag updates priority without moving task', (
    tester,
  ) async {
    late GoRouter router;
    final schedule = _timedSchedule(19);
    final harness = await _pumpApp(
      tester,
      onRouter: (value) => router = value,
      tasks: [
        _task(
          'dragged-p1',
          'Matrix drag task',
          priority: 1,
          schedule: schedule,
        ),
      ],
    );

    router.go('/priority-matrix');
    await _pumpFrames(tester);

    await _dragTaskToPriority(tester, 'Matrix drag task', 2);

    expect(harness.taskRepository.updatePatches.single.priority, 2);
    expect(harness.taskRepository.updatePatches.single.schedule, isNull);
    expect(harness.taskRepository.updatePatches.single.clearSchedule, isFalse);
    expect(harness.taskRepository.movedParentIds, isEmpty);
    expect(harness.taskRepository.movedProjectIds, isEmpty);
  });

  testWidgets('priority matrix quick add creates task with quadrant priority', (
    tester,
  ) async {
    late GoRouter router;
    final harness = await _pumpApp(
      tester,
      onRouter: (value) => router = value,
      tasks: const <TaskItem>[],
      size: const Size(1200, 900),
    );

    router.go('/priority-matrix');
    await _pumpFrames(tester);
    final p3 = find.byKey(const Key('priority-matrix-quadrant-p3')).first;
    await tester.enterText(
      find.descendant(of: p3, matching: find.byType(TextField)).first,
      'Matrix created task',
    );
    await tester.tap(
      find.descendant(of: p3, matching: find.byTooltip('Add')).first,
    );
    await _pumpFrames(tester);

    final input = harness.taskRepository.createdInputs.single;
    expect(input.content, 'Matrix created task');
    expect(input.priority, 3);
    expect(input.projectId, isNull);
    expect(input.dueDate, isNull);
  });

  testWidgets('timeline groups selected day tasks and hides completed tasks', (
    tester,
  ) async {
    _setTimelineVisibleHourPrefs();
    late GoRouter router;
    final day = _testToday();
    await _pumpApp(
      tester,
      onRouter: (value) => router = value,
      size: const Size(1200, 900),
      tasks: [
        _task(
          'all-day',
          'Timeline all-day',
          schedule: TaskSchedule.allDay(day),
        ),
        _task('visible', 'Timeline visible', schedule: _scheduleAt(day, 10)),
        _task('before', 'Timeline before', schedule: _scheduleAt(day, 7)),
        _task('after', 'Timeline after', schedule: _scheduleAt(day, 20)),
        _task(
          'done',
          'Timeline done',
          status: 'completed',
          schedule: _scheduleAt(day, 11),
        ),
        _task(
          'other-day',
          'Timeline other day',
          schedule: TaskSchedule.allDay(day.add(const Duration(days: 1))),
        ),
      ],
    );

    router.go('/timeline?date=${_routeDate(day)}');
    await _pumpFrames(tester);

    expect(find.text('Timeline'), findsAtLeastNWidgets(1));
    expect(find.text('Timeline all-day'), findsOneWidget);
    expect(find.text('Timeline visible'), findsOneWidget);
    expect(find.text('Before visible hours'), findsOneWidget);
    expect(find.text('Timeline before'), findsOneWidget);
    expect(find.text('After visible hours'), findsOneWidget);
    expect(find.text('Timeline after'), findsOneWidget);
    expect(find.text('Timeline done'), findsNothing);
    expect(find.text('Timeline other day'), findsNothing);
  });

  testWidgets('timeline live task replaces an older retained snapshot', (
    tester,
  ) async {
    _setTimelineVisibleHourPrefs();
    late GoRouter router;
    final day = _testToday();
    final oldTask = _task(
      'timeline-live-task',
      'Timeline live task',
      schedule: _scheduleAt(day, 9),
    );
    final freshTask = _task(
      oldTask.id,
      oldTask.content,
      schedule: _scheduleAt(day, 11),
    );
    final updates = StreamController<List<TaskItem>>.broadcast();
    addTearDown(updates.close);
    await _pumpApp(
      tester,
      onRouter: (value) => router = value,
      size: const Size(1200, 900),
      tasks: const [],
      taskStream: updates.stream,
    );

    router.go('/timeline?date=${_routeDate(day)}');
    await _pumpFrames(tester);
    updates.add([oldTask]);
    await _pumpFrames(tester);
    final block = find.byKey(Key('timeline-task-${oldTask.id}'));
    final motion = TaskMotionScope.maybeOf(tester.element(block))!;
    motion.reopened([oldTask]);
    await tester.pump();
    final oldLeft = tester.getTopLeft(block).dx;

    updates.add([freshTask]);
    await _pumpFrames(tester);

    expect(find.text('11:00-12:00'), findsOneWidget);
    expect(find.text('09:00-10:00'), findsNothing);
    expect(tester.getTopLeft(block).dx, greaterThan(oldLeft));
  });

  testWidgets('task list live task replaces an older retained snapshot', (
    tester,
  ) async {
    late GoRouter router;
    final day = _testToday();
    final oldTask = _task(
      'list-live-task',
      'Old list snapshot',
      schedule: _scheduleAt(day, 9),
    );
    final freshTask = _task(
      oldTask.id,
      'Fresh list task',
      schedule: _scheduleAt(day, 11),
    );
    final updates = StreamController<List<TaskItem>>.broadcast();
    addTearDown(updates.close);
    await _pumpApp(
      tester,
      onRouter: (value) => router = value,
      tasks: const [],
      taskStream: updates.stream,
    );

    router.go('/today');
    await _pumpFrames(tester);
    updates.add([oldTask]);
    await _pumpFrames(tester);
    final row = find.byKey(ValueKey('task-list-item-row-${oldTask.id}'));
    final motion = TaskMotionScope.maybeOf(tester.element(row))!;
    motion.reopened([oldTask]);
    await tester.pump();

    updates.add([freshTask]);
    await _pumpFrames(tester);

    expect(find.text('Fresh list task'), findsOneWidget);
    expect(find.text('Old list snapshot'), findsNothing);
    expect(
      tester
          .widget<Text>(find.byKey(ValueKey('task-time-label-${oldTask.id}')))
          .data,
      contains('11:00'),
    );
  });

  testWidgets('timeline task blocks follow the soft-fill visual contract', (
    tester,
  ) async {
    _setTimelineVisibleHourPrefs();
    late GoRouter router;
    final day = _testToday();
    await _pumpApp(
      tester,
      onRouter: (value) => router = value,
      size: const Size(1200, 900),
      projects: [
        _project(inboxProjectId, 'Inbox', orderKey: '0'),
        _project(
          'violet',
          'Violet',
          orderKey: '1',
          color: '#8B5CF6',
          isFavorite: true,
        ),
        _project(
          'green',
          'Green',
          orderKey: '2',
          color: '#36A269',
          isFavorite: true,
        ),
      ],
      tasks: [
        _task(
          'violet-task',
          'Violet task',
          projectId: 'violet',
          priority: 1,
          schedule: _scheduleAt(day, 10),
        ),
        _task(
          'green-task',
          'Green task',
          projectId: 'green',
          priority: 1,
          schedule: _scheduleAt(day, 12),
        ),
      ],
    );

    router.go('/timeline?date=${_routeDate(day)}');
    await _pumpFrames(tester);

    BoxDecoration decorationFor(String taskId) {
      final block = find.byKey(Key('timeline-task-$taskId'));
      final surface = find
          .descendant(
            of: block,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Container && widget.decoration is BoxDecoration,
            ),
          )
          .first;
      return tester.widget<Container>(surface).decoration! as BoxDecoration;
    }

    final violet = decorationFor('violet-task');
    final green = decorationFor('green-task');
    final colors = tester
        .element(find.byKey(const Key('timeline-task-violet-task')))
        .appColors;

    expect(violet.color, isNot(colors.surface));
    expect(green.color, isNot(colors.surface));
    expect(violet.color, isNot(green.color));
    expect((violet.border! as Border).top.color, colors.border);
    expect((green.border! as Border).top.color, colors.border);

    final violetBlock = find.byKey(const Key('timeline-task-violet-task'));
    final projectRail = find
        .descendant(
          of: violetBlock,
          matching: find.byWidgetPredicate((widget) {
            if (widget is! DecoratedBox ||
                widget.decoration is! BoxDecoration) {
              return false;
            }
            return (widget.decoration as BoxDecoration).borderRadius ==
                const BorderRadius.horizontal(left: Radius.circular(8));
          }),
        )
        .first;
    final completion = find.byKey(
      const Key('task-completion-paint-violet-task'),
    );
    expect(
      tester.getTopLeft(projectRail).dx,
      lessThanOrEqualTo(tester.getTopLeft(violetBlock).dx + 3),
    );
    expect(
      tester.getTopRight(projectRail).dx,
      lessThanOrEqualTo(tester.getTopLeft(completion).dx),
    );

    final resizeHandle = find.byKey(const Key('timeline-resize-violet-task'));
    expect(resizeHandle, findsOneWidget);
    expect(
      find.descendant(of: resizeHandle, matching: find.byType(DecoratedBox)),
      findsNothing,
    );
  });

  testWidgets(
    'timeline orders favorite and busy project zones with hierarchy',
    (tester) async {
      _setTimelineVisibleHourPrefs();
      late GoRouter router;
      final day = _testToday();
      await _pumpApp(
        tester,
        onRouter: (value) => router = value,
        size: const Size(1200, 900),
        projects: [
          _project(inboxProjectId, 'Inbox', orderKey: '0'),
          _project('favorite', 'Favorite', orderKey: '2', isFavorite: true),
          _project('parent', 'Parent', orderKey: '3'),
          _project('child', 'Child', orderKey: '4', parentId: 'parent'),
          _project(
            'favorite-child',
            'Favorite child',
            orderKey: '5',
            parentId: 'parent',
            isFavorite: true,
          ),
          _project('hidden', 'Hidden', orderKey: '5'),
        ],
        tasks: [
          _task(
            'child-task',
            'Child project task',
            projectId: 'child',
            schedule: _scheduleAt(day, 10),
          ),
        ],
      );

      router.go('/timeline?date=${_routeDate(day)}');
      await _pumpFrames(tester);

      final inbox = find.byKey(const Key('timeline-project-row-inbox'));
      final favorite = find.byKey(const Key('timeline-project-row-favorite'));
      final parent = find.byKey(const Key('timeline-project-row-parent'));
      final child = find.byKey(const Key('timeline-project-row-child'));
      final favoriteChild = find.byKey(
        const Key('timeline-project-row-favorite-child'),
      );
      expect(inbox, findsOneWidget);
      expect(favorite, findsOneWidget);
      expect(parent, findsOneWidget);
      expect(child, findsOneWidget);
      expect(favoriteChild, findsOneWidget);
      expect(
        find.byKey(const Key('timeline-project-row-hidden')),
        findsNothing,
      );
      expect(
        tester.getTopLeft(inbox).dy,
        lessThan(tester.getTopLeft(favorite).dy),
      );
      expect(
        tester.getTopLeft(favorite).dy,
        lessThan(tester.getTopLeft(parent).dy),
      );
      expect(
        tester.getTopLeft(parent).dy,
        lessThan(tester.getTopLeft(favoriteChild).dy),
      );
      expect(
        tester.getTopLeft(favoriteChild).dy,
        lessThan(tester.getTopLeft(child).dy),
      );

      await tester.tap(
        find.byKey(const Key('timeline-project-collapse-parent')),
      );
      await _pumpFrames(tester);
      expect(find.byKey(const Key('timeline-project-row-child')), findsNothing);
      expect(
        find.byKey(const Key('timeline-project-row-favorite-child')),
        findsNothing,
      );
    },
  );

  testWidgets('timeline overlaps timed tasks in vertical lanes', (
    tester,
  ) async {
    late GoRouter router;
    final day = _testToday();
    await _pumpApp(
      tester,
      onRouter: (value) => router = value,
      size: const Size(1200, 900),
      tasks: [
        _task('overlap-a', 'Overlap A', schedule: _scheduleAt(day, 10)),
        _task('overlap-b', 'Overlap B', schedule: _scheduleAt(day, 10, 30)),
      ],
    );

    router.go('/timeline?date=${_routeDate(day)}');
    await _pumpFrames(tester);
    await tester.ensureVisible(
      find.byKey(const Key('timeline-task-overlap-a')),
    );
    await tester.pump();

    final a = find.byKey(const Key('timeline-task-overlap-a'));
    final b = find.byKey(const Key('timeline-task-overlap-b'));
    final aRect = tester.getRect(a);
    final bRect = tester.getRect(b);
    expect(aRect.top, isNot(closeTo(bRect.top, 1)));
    expect(aRect.left, lessThan(bRect.right));
    expect(bRect.left, lessThan(aRect.right));
  });

  testWidgets('timeline grid uses horizontal scroll on desktop and mobile', (
    tester,
  ) async {
    _setTimelineVisibleHourPrefs();
    late GoRouter router;
    final day = _testToday();
    await _pumpApp(
      tester,
      onRouter: (value) => router = value,
      size: const Size(1200, 900),
      tasks: const <TaskItem>[],
    );

    router.go('/timeline?date=${_routeDate(day)}');
    await _pumpFrames(tester);

    final desktopScroll = tester.widget<SingleChildScrollView>(
      find.byKey(const Key('timeline-horizontal-scroll')),
    );
    expect(desktopScroll.scrollDirection, Axis.horizontal);
    expect(find.byKey(const Key('timeline-project-column')), findsOneWidget);

    await _pumpApp(
      tester,
      onRouter: (value) => router = value,
      size: const Size(390, 844),
      tasks: const <TaskItem>[],
    );

    router.go('/timeline?date=${_routeDate(day)}');
    await _pumpFrames(tester);

    final mobileScroll = tester.widget<SingleChildScrollView>(
      find.byKey(const Key('timeline-horizontal-scroll')),
    );
    expect(mobileScroll.scrollDirection, Axis.horizontal);
    expect(find.byKey(const Key('timeline-slot-inbox-600')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('timeline-project-column'))).width,
      lessThanOrEqualTo(120),
    );
    expect(find.byKey(const Key('timeline-zoom-out')), findsOneWidget);
    expect(find.byKey(const Key('timeline-zoom-in')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'timeline mouse wheel scrolls horizontally and releases at edge',
    (tester) async {
      _setTimelineVisibleHourPrefs();
      late GoRouter router;
      final day = _testToday();
      await _pumpApp(
        tester,
        onRouter: (value) => router = value,
        size: const Size(800, 500),
        projects: [
          _project(inboxProjectId, 'Inbox', orderKey: '0'),
          for (var index = 1; index <= 6; index++)
            _project(
              'favorite-$index',
              'Favorite $index',
              orderKey: '$index',
              isFavorite: true,
            ),
        ],
        tasks: const <TaskItem>[],
      );

      router.go('/timeline?date=${_routeDate(day)}');
      await _pumpFrames(tester);

      final scrollFinder = find.byKey(const Key('timeline-horizontal-scroll'));
      await tester.ensureVisible(scrollFinder);
      await tester.pump();
      final horizontal = tester
          .widget<SingleChildScrollView>(scrollFinder)
          .controller!;
      final vertical = tester
          .stateList<ScrollableState>(
            find.descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            ),
          )
          .firstWhere(
            (state) =>
                axisDirectionToAxis(state.position.axisDirection) ==
                Axis.vertical,
          )
          .position;
      final visibleGrid = tester
          .getRect(scrollFinder)
          .intersect(Offset.zero & tester.view.physicalSize);
      final mouse = TestPointer(44, PointerDeviceKind.mouse)
        ..hover(visibleGrid.center);

      horizontal.jumpTo(200);
      final verticalBeforeWheel = vertical.pixels;
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 120)));
      await tester.pump();

      expect(horizontal.offset, 320);
      expect(vertical.pixels, verticalBeforeWheel);

      horizontal.jumpTo(horizontal.position.maxScrollExtent);
      final verticalBeforeEdge = vertical.pixels;
      expect(verticalBeforeEdge, lessThan(vertical.maxScrollExtent));
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 120)));
      await tester.pump();

      expect(horizontal.offset, horizontal.position.maxScrollExtent);
      expect(vertical.pixels, greaterThan(verticalBeforeEdge));
    },
  );

  testWidgets('timeline arrows scroll only while the grid has focus', (
    tester,
  ) async {
    _setTimelineVisibleHourPrefs();
    late GoRouter router;
    final day = _testToday();
    await _pumpApp(
      tester,
      onRouter: (value) => router = value,
      size: const Size(1200, 900),
      tasks: const <TaskItem>[],
    );

    router.go('/timeline?date=${_routeDate(day)}');
    await _pumpFrames(tester);

    final frameFinder = find.byKey(const Key('timeline-grid-frame'));
    final scrollFinder = find.byKey(const Key('timeline-horizontal-scroll'));
    final frame = tester.widget<Container>(frameFinder);
    expect((frame.decoration as BoxDecoration).color, Colors.white);
    final foregroundDecoration =
        frame.foregroundDecoration as BoxDecoration;
    expect(foregroundDecoration.color, isNull);
    final controller = tester
        .widget<SingleChildScrollView>(scrollFinder)
        .controller!;
    controller.jumpTo(300);
    await tester.pump();
    final borderBeforeFocus = foregroundDecoration.border!;
    expect(borderBeforeFocus.top.color, const Color(0x1A25221E));
    expect(borderBeforeFocus.top.width, 1);
    final scrollRect = tester.getRect(scrollFinder);
    await tester.tapAt(Offset(scrollRect.center.dx, scrollRect.top + 12));
    await tester.pump();
    final borderWithFocus =
        (tester.widget<Container>(frameFinder).foregroundDecoration
                as BoxDecoration)
            .border!;

    expect(borderWithFocus.top.color.toARGB32(), 0x59E44332);
    expect(borderWithFocus.top.width, 1);
    final keyHandled = await tester.sendKeyDownEvent(
      LogicalKeyboardKey.arrowRight,
    );
    expect(keyHandled, isTrue);
    await tester.pumpAndSettle();
    final afterKeyDown = controller.offset;
    expect(afterKeyDown, greaterThan(300));
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(afterKeyDown));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);

    controller.jumpTo(300);
    await tester.tap(find.byKey(const Key('timeline-slot-inbox-600')));
    await tester.pump();
    final inlineAdd = find.byKey(const Key('timeline-inline-add-timed'));
    expect(inlineAdd, findsOneWidget);
    await tester.tap(
      find.descendant(of: inlineAdd, matching: find.byType(TextField)),
    );
    await tester.pump();
    final editable = find.descendant(
      of: inlineAdd,
      matching: find.byType(EditableText),
    );
    expect(tester.widget<EditableText>(editable).focusNode.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    expect(controller.offset, 300);
  });

  testWidgets('timeline arrows follow RTL visual direction', (tester) async {
    _setTimelineVisibleHourPrefs();
    late GoRouter router;
    final day = _testToday();
    await _pumpApp(
      tester,
      onRouter: (value) => router = value,
      size: const Size(1200, 900),
      locale: const Locale('ar'),
      tasks: const <TaskItem>[],
    );

    router.go('/timeline?date=${_routeDate(day)}');
    await _pumpFrames(tester);

    final scrollFinder = find.byKey(const Key('timeline-horizontal-scroll'));
    final controller = tester
        .widget<SingleChildScrollView>(scrollFinder)
        .controller!;
    controller.jumpTo(300);
    await tester.pump();
    final scrollRect = tester.getRect(scrollFinder);
    await tester.tapAt(Offset(scrollRect.center.dx, scrollRect.top + 12));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(controller.offset, lessThan(300));

    final afterRight = controller.offset;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(afterRight));
  });

  testWidgets('timeline zoom resizes slots and preserves the viewed time', (
    tester,
  ) async {
    _setTimelineVisibleHourPrefs();
    late GoRouter router;
    final day = _testToday();
    await _pumpApp(
      tester,
      onRouter: (value) => router = value,
      size: const Size(1200, 900),
      tasks: const <TaskItem>[],
    );

    router.go('/timeline?date=${_routeDate(day)}');
    await _pumpFrames(tester);

    final slot = find.byKey(const Key('timeline-slot-inbox-600'));
    expect(tester.getSize(slot).width, 48);
    final scroll = tester.widget<SingleChildScrollView>(
      find.byKey(const Key('timeline-horizontal-scroll')),
    );
    final controller = scroll.controller!;

    await tester.tap(find.byKey(const Key('timeline-zoom-in')));
    await _pumpFrames(tester);
    expect(tester.getSize(slot).width, 72);
    expect(controller.offset, 0);

    controller.jumpTo(300);
    final oldCenterMinutes =
        (controller.offset + controller.position.viewportDimension / 2) /
        (72 / timelineSnapMinutes);
    await tester.tap(find.byKey(const Key('timeline-zoom-in')));
    await _pumpFrames(tester);
    final newCenterMinutes =
        (controller.offset + controller.position.viewportDimension / 2) /
        (tester.getSize(slot).width / timelineSnapMinutes);

    expect(newCenterMinutes, moreOrLessEquals(oldCenterMinutes, epsilon: 0.1));
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('timeline-zoom-in')))
          .onPressed,
      isNull,
    );

    for (var index = 0; index < 4; index++) {
      await tester.tap(find.byKey(const Key('timeline-zoom-out')));
      await _pumpFrames(tester);
    }
    expect(tester.getSize(slot).width, 24);
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('timeline-zoom-out')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('timeline touchscreen pinch zooms around its focal point', (
    tester,
  ) async {
    _setTimelineVisibleHourPrefs();
    late GoRouter router;
    final day = _testToday();
    await _pumpApp(
      tester,
      onRouter: (value) => router = value,
      size: const Size(1200, 900),
      tasks: const <TaskItem>[],
    );

    router.go('/timeline?date=${_routeDate(day)}');
    await _pumpFrames(tester);

    final slot = find.byKey(const Key('timeline-slot-inbox-600'));
    final scrollFinder = find.byKey(const Key('timeline-horizontal-scroll'));
    final controller = tester
        .widget<SingleChildScrollView>(scrollFinder)
        .controller!;
    controller.jumpTo(300);
    await tester.pump();
    final scrollRect = tester.getRect(scrollFinder);
    final focalPoint = Offset(scrollRect.left + 300, scrollRect.center.dy);
    const focalX = 300.0;
    final timeAtFocalPoint = (controller.offset + focalX) / (192 / 60);
    final first = TestPointer(41, PointerDeviceKind.touch);
    final second = TestPointer(42, PointerDeviceKind.touch);

    await tester.sendEventToBinding(
      first.down(focalPoint - const Offset(50, 0)),
    );
    await tester.sendEventToBinding(
      second.down(focalPoint + const Offset(50, 0)),
    );
    await tester.sendEventToBinding(
      first.move(focalPoint - const Offset(75, 0)),
    );
    await tester.sendEventToBinding(
      second.move(focalPoint + const Offset(75, 0)),
    );
    await _pumpFrames(tester);

    expect(tester.getSize(slot).width, 72);
    expect(
      (controller.offset + focalX) / (288 / 60),
      moreOrLessEquals(timeAtFocalPoint, epsilon: 0.1),
    );

    await tester.sendEventToBinding(
      first.move(focalPoint - const Offset(50, 0)),
    );
    await tester.sendEventToBinding(
      second.move(focalPoint + const Offset(50, 0)),
    );
    await _pumpFrames(tester);

    expect(tester.getSize(slot).width, 48);
    expect(
      (controller.offset + focalX) / (192 / 60),
      moreOrLessEquals(timeAtFocalPoint, epsilon: 0.1),
    );

    await tester.sendEventToBinding(first.up());
    await tester.sendEventToBinding(second.up());
  });

  testWidgets('timeline trackpad pan scrolls and pinch zooms', (tester) async {
    _setTimelineVisibleHourPrefs();
    late GoRouter router;
    final day = _testToday();
    await _pumpApp(
      tester,
      onRouter: (value) => router = value,
      size: const Size(1200, 900),
      tasks: const <TaskItem>[],
    );

    router.go('/timeline?date=${_routeDate(day)}');
    await _pumpFrames(tester);

    final slot = find.byKey(const Key('timeline-slot-inbox-600'));
    final scrollFinder = find.byKey(const Key('timeline-horizontal-scroll'));
    final controller = tester
        .widget<SingleChildScrollView>(scrollFinder)
        .controller!;
    controller.jumpTo(300);
    await tester.pump();
    final scrollRect = tester.getRect(scrollFinder);
    final focalPoint = Offset(scrollRect.left + 300, scrollRect.center.dy);
    const focalX = 300.0;
    final trackpad = TestPointer(43, PointerDeviceKind.trackpad);

    await tester.sendEventToBinding(trackpad.panZoomStart(focalPoint));
    await tester.sendEventToBinding(
      trackpad.panZoomUpdate(focalPoint, pan: const Offset(-80, 0)),
    );
    await tester.sendEventToBinding(
      trackpad.panZoomUpdate(focalPoint, pan: const Offset(-160, 0)),
    );
    await tester.pump();

    expect(controller.offset, isNot(300));
    expect(tester.getSize(slot).width, 48);
    final timeAtFocalPoint = (controller.offset + focalX) / (192 / 60);

    await tester.sendEventToBinding(
      trackpad.panZoomUpdate(
        focalPoint,
        pan: const Offset(-160, 0),
        scale: 1.5,
      ),
    );
    await _pumpFrames(tester);

    expect(tester.getSize(slot).width, 72);
    expect(
      (controller.offset + focalX) / (288 / 60),
      moreOrLessEquals(timeAtFocalPoint, epsilon: 0.1),
    );

    await tester.sendEventToBinding(trackpad.panZoomEnd());
  });

  testWidgets('timeline project menu reveals edits and favorites projects', (
    tester,
  ) async {
    _setTimelineVisibleHourPrefs();
    late GoRouter router;
    final day = _testToday();
    final harness = await _pumpApp(
      tester,
      onRouter: (value) => router = value,
      size: const Size(1200, 900),
      projects: [
        _project(inboxProjectId, 'Inbox', orderKey: '0'),
        _project('hidden', 'Hidden project', orderKey: '1'),
      ],
      tasks: const <TaskItem>[],
    );

    router.go('/timeline?date=${_routeDate(day)}');
    await _pumpFrames(tester);
    expect(find.byKey(const Key('timeline-project-row-hidden')), findsNothing);

    await tester.tap(find.byKey(const Key('timeline-project-menu')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('timeline-project-menu-toggle-hidden')),
    );
    await tester.tap(find.text('Close'));
    await _pumpFrames(tester);

    expect(
      find.byKey(const Key('timeline-project-row-hidden')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('timeline-project-color-hidden')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('project-color-option-5')));
    await _pumpFrames(tester);
    expect(
      harness.projectRepository.updateProjectPatches.single.color,
      projectColorPalette[5],
    );

    await tester.tap(find.byKey(const Key('timeline-project-menu')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('timeline-project-menu-favorite-hidden')),
    );
    await _pumpFrames(tester);
    expect(
      harness.projectRepository.updateProjectPatches.last.isFavorite,
      isTrue,
    );
  });

  testWidgets('timeline uses short quarter ticks and today indicator', (
    tester,
  ) async {
    _setTimelineVisibleHourPrefs();
    late GoRouter router;
    final today = DateTime(2026, 1, 2);
    await _pumpApp(
      tester,
      onRouter: (value) => router = value,
      size: const Size(1200, 900),
      tasks: const <TaskItem>[],
    );

    router.go('/timeline?date=${_routeDate(today)}');
    await _pumpFrames(tester);

    expect(find.byKey(const Key('timeline-hour-line-600')), findsOneWidget);
    final tick = find.byKey(const Key('timeline-quarter-tick-615'));
    expect(tick, findsOneWidget);
    expect(tester.getSize(tick).height, 8);
    expect(
      find.byKey(const Key('timeline-current-time-indicator')),
      findsOneWidget,
    );

    router.go(
      '/timeline?date=${_routeDate(today.add(const Duration(days: 1)))}',
    );
    await _pumpFrames(tester);
    expect(
      find.byKey(const Key('timeline-current-time-indicator')),
      findsNothing,
    );
  });

  testWidgets('timeline slot inline add creates timed task', (tester) async {
    _setTimelineVisibleHourPrefs();
    late GoRouter router;
    final day = _testToday();
    final harness = await _pumpApp(
      tester,
      onRouter: (value) => router = value,
      size: const Size(1200, 900),
      tasks: const <TaskItem>[],
    );

    router.go('/timeline?date=${_routeDate(day)}');
    await _pumpFrames(tester);
    await tester.ensureVisible(
      find.byKey(const Key('timeline-slot-inbox-600')),
    );
    await tester.tap(find.byKey(const Key('timeline-slot-inbox-600')));
    await tester.pump();
    final inline = find.byKey(const Key('timeline-inline-add-timed'));
    await tester.enterText(
      find.descendant(of: inline, matching: find.byType(TextField)),
      'Created from slot',
    );
    await tester.tap(
      find.descendant(of: inline, matching: find.byTooltip('Add')),
    );
    await _pumpFrames(tester);

    final input = harness.taskRepository.createdInputs.single;
    expect(input.content, 'Created from slot');
    expect(input.projectId, inboxProjectId);
    expect(input.dueDate, isNull);
    expect(input.schedule!.start!.toLocal(), _dateAt(day, 10));
    expect(input.schedule!.duration, const Duration(minutes: 30));
  });

  testWidgets('timeline slot explicit project overrides the row project', (
    tester,
  ) async {
    _setTimelineVisibleHourPrefs();
    late GoRouter router;
    final day = _testToday();
    final harness = await _pumpApp(
      tester,
      onRouter: (value) => router = value,
      size: const Size(1200, 900),
      projects: [
        _project(inboxProjectId, 'Inbox', orderKey: '0'),
        _project('project-1', 'Work', orderKey: '1', isFavorite: true),
        _project('project-2', 'Personal', orderKey: '2', isFavorite: true),
      ],
      tasks: const <TaskItem>[],
    );

    router.go('/timeline?date=${_routeDate(day)}');
    await _pumpFrames(tester);
    final slot = find.byKey(const Key('timeline-slot-project-2-600'));
    await tester.ensureVisible(slot);
    await tester.tap(slot);
    await tester.pump();
    final inline = find.byKey(const Key('timeline-inline-add-timed'));
    await tester.enterText(
      find.descendant(of: inline, matching: find.byType(TextField)),
      'Explicit project #Work',
    );
    await tester.tap(
      find.descendant(of: inline, matching: find.byTooltip('Add')),
    );
    await _pumpFrames(tester);

    final input = harness.taskRepository.createdInputs.single;
    expect(input.projectId, 'project-1');
    expect(harness.projectRepository.createdProjectNames, ['Work']);
  });

  testWidgets('timeline all-day inline add creates all-day task', (
    tester,
  ) async {
    _setTimelineVisibleHourPrefs();
    late GoRouter router;
    final day = _testToday();
    final harness = await _pumpApp(
      tester,
      onRouter: (value) => router = value,
      size: const Size(1200, 900),
      tasks: const <TaskItem>[],
    );

    router.go('/timeline?date=${_routeDate(day)}');
    await _pumpFrames(tester);
    await tester.tap(find.byKey(const Key('timeline-all-day-section')));
    await tester.pump();
    final inline = find.byKey(const Key('timeline-inline-add-all-day'));
    await tester.enterText(
      find.descendant(of: inline, matching: find.byType(TextField)),
      'Created all-day',
    );
    await tester.tap(
      find.descendant(of: inline, matching: find.byTooltip('Add')),
    );
    await _pumpFrames(tester);

    final input = harness.taskRepository.createdInputs.single;
    expect(input.content, 'Created all-day');
    expect(input.dueDate, isNull);
    expect(input.schedule!.isAllDay, isTrue);
    expect(input.schedule!.date, day);
  });

  testWidgets('timeline drag timed task updates schedule without moveTask', (
    tester,
  ) async {
    _setTimelineVisibleHourPrefs(hourWidth: 96);
    late GoRouter router;
    final day = _testToday();
    final harness = await _pumpApp(
      tester,
      onRouter: (value) => router = value,
      size: const Size(1200, 900),
      tasks: [_task('drag-timed', 'Drag timed', schedule: _scheduleAt(day, 9))],
    );

    router.go('/timeline?date=${_routeDate(day)}');
    await _pumpFrames(tester);
    await _dragTimelineTaskToSlot(tester, 'Drag timed', 600);

    final patch = harness.taskRepository.updatePatches.single;
    expect(patch.schedule!.start!.toLocal(), _dateAt(day, 10));
    expect(patch.schedule!.duration, const Duration(hours: 1));
    expect(harness.taskRepository.movedParentIds, isEmpty);
    expect(harness.taskRepository.movedProjectIds, isEmpty);
  });

  testWidgets('timeline drag across project zones places task atomically', (
    tester,
  ) async {
    _setTimelineVisibleHourPrefs();
    late GoRouter router;
    final day = _testToday();
    final harness = await _pumpApp(
      tester,
      onRouter: (value) => router = value,
      size: const Size(1200, 900),
      projects: [
        _project(inboxProjectId, 'Inbox', orderKey: '0'),
        _project('project-1', 'Work', orderKey: '1', isFavorite: true),
        _project('project-2', 'Personal', orderKey: '2', isFavorite: true),
      ],
      tasks: [
        _task(
          'cross-project',
          'Cross project',
          projectId: 'project-1',
          schedule: _scheduleAt(day, 9),
        ),
      ],
    );

    router.go('/timeline?date=${_routeDate(day)}');
    await _pumpFrames(tester);
    await _dragTimelineTaskToSlot(
      tester,
      'Cross project',
      600,
      projectId: 'project-2',
    );

    expect(harness.taskRepository.placedTaskIds, ['cross-project']);
    expect(harness.taskRepository.placedProjectIds, ['project-2']);
    expect(
      harness.taskRepository.placedSchedules.single.start!.toLocal(),
      _dateAt(day, 10),
    );
    expect(harness.taskRepository.updatePatches, isEmpty);
  });

  testWidgets('timeline all-day and timed drops convert schedule kind', (
    tester,
  ) async {
    _setTimelineVisibleHourPrefs();
    late GoRouter router;
    final day = _testToday();
    final harness = await _pumpApp(
      tester,
      onRouter: (value) => router = value,
      size: const Size(1200, 900),
      tasks: [
        _task(
          'all-day-drag',
          'Drag all-day',
          schedule: TaskSchedule.allDay(day),
        ),
        _task('timed-drag', 'Drop to all-day', schedule: _scheduleAt(day, 9)),
      ],
    );

    router.go('/timeline?date=${_routeDate(day)}');
    await _pumpFrames(tester);
    await _dragTimelineTaskToSlot(tester, 'Drag all-day', 600);
    await _dragTimelineTaskToAllDay(tester, 'Drop to all-day');

    expect(
      harness.taskRepository.updatePatches.first.schedule!.isTimed,
      isTrue,
    );
    expect(
      harness.taskRepository.updatePatches.first.schedule!.duration,
      const Duration(minutes: 30),
    );
    expect(
      harness.taskRepository.updatePatches.last.schedule!.isAllDay,
      isTrue,
    );
    expect(harness.taskRepository.updatePatches.last.schedule!.date, day);
    expect(harness.taskRepository.movedParentIds, isEmpty);
  });

  testWidgets('timeline resize snaps end time within day bounds', (
    tester,
  ) async {
    _setTimelineVisibleHourPrefs(hourWidth: 96);
    late GoRouter router;
    final day = _testToday();
    final harness = await _pumpApp(
      tester,
      onRouter: (value) => router = value,
      size: const Size(1200, 900),
      tasks: [
        _task(
          'resize-1',
          'Resize task',
          schedule: _scheduleAt(day, 10, 0, const Duration(minutes: 30)),
        ),
      ],
    );

    router.go('/timeline?date=${_routeDate(day)}');
    await _pumpFrames(tester);
    expect(
      tester.getSize(find.byKey(const Key('timeline-slot-inbox-600'))).width,
      24,
    );
    final handle = find.byKey(const Key('timeline-resize-resize-1'));
    await tester.ensureVisible(handle);
    await tester.drag(handle, const Offset(66, 0));
    await tester.pumpAndSettle();

    final schedule = harness.taskRepository.updatePatches.single.schedule!;
    expect(schedule.start!.toLocal(), _dateAt(day, 10));
    expect(schedule.end!.toLocal(), _dateAt(day, 11));
  });

  test('timeline visible hours persist in shared preferences', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container
        .read(timelineVisibleHoursProvider.notifier)
        .setVisibleHours(8 * 60, 18 * 60);
    final prefs = await SharedPreferences.getInstance();

    expect(prefs.getInt(timelineVisibleStartMinutesPreferenceKey), 8 * 60);
    expect(prefs.getInt(timelineVisibleEndMinutesPreferenceKey), 18 * 60);

    final restored = ProviderContainer();
    addTearDown(restored.dispose);
    restored.read(timelineVisibleHoursProvider);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(
      restored.read(timelineVisibleHoursProvider),
      const TimelineVisibleHours(startMinutes: 8 * 60, endMinutes: 18 * 60),
    );
  });

  test(
    'timeline zoom persists known levels and rejects invalid values',
    () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(timelineHourWidthProvider), 192);
      await container.read(timelineHourWidthProvider.notifier).zoomIn();
      expect(container.read(timelineHourWidthProvider), 288);
      await container
          .read(timelineHourWidthProvider.notifier)
          .setHourWidth(384);
      expect(container.read(timelineHourWidthProvider), 384);
      await container
          .read(timelineHourWidthProvider.notifier)
          .setHourWidth(123);
      expect(container.read(timelineHourWidthProvider), 384);
      expect(
        (await SharedPreferences.getInstance()).getInt(
          timelineHourWidthPreferenceKey,
        ),
        384,
      );

      final restored = ProviderContainer();
      addTearDown(restored.dispose);
      restored.read(timelineHourWidthProvider);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(restored.read(timelineHourWidthProvider), 384);

      SharedPreferences.setMockInitialValues({
        timelineHourWidthPreferenceKey: 123,
      });
      final invalid = ProviderContainer();
      addTearDown(invalid.dispose);
      invalid.read(timelineHourWidthProvider);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(invalid.read(timelineHourWidthProvider), 192);
    },
  );

  test(
    'timeline collapsed project ids persist in shared preferences',
    () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container
          .read(timelineCollapsedProjectIdsProvider.notifier)
          .toggle('project-1');
      final prefs = await SharedPreferences.getInstance();

      expect(prefs.getStringList(timelineCollapsedProjectIdsPreferenceKey), [
        'project-1',
      ]);

      final restored = ProviderContainer();
      addTearDown(restored.dispose);
      restored.read(timelineCollapsedProjectIdsProvider);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(restored.read(timelineCollapsedProjectIdsProvider), {'project-1'});
    },
  );

  testWidgets('completing a parent task completes its subtasks', (
    tester,
  ) async {
    final today = _todaySchedule();
    final harness = await _pumpApp(
      tester,
      tasks: [
        _task('parent-1', 'Parent task', schedule: today, orderKey: '1'),
        _task(
          'child-1',
          'Child task',
          schedule: today,
          parentId: 'parent-1',
          orderKey: '2',
        ),
      ],
    );

    await tester.tap(find.byKey(const Key('task-completion-control-parent-1')));
    await _pumpFrames(tester);

    expect(
      harness.taskRepository.completedTaskIds,
      containsAll(['parent-1', 'child-1']),
    );
  });

  testWidgets('mobile bottom navigation switches primary sections', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      onboardingCompletedPreferenceKey: true,
      launchOfferStartedAtPreferenceKey: '2026-01-01T10:00:00.000Z',
      focusViewModePreferenceKey: FocusViewMode.full.storageValue,
    });
    await _pumpApp(tester);

    expect(
      tester.getCenter(find.text('Focus')).dx,
      moreOrLessEquals(tester.view.physicalSize.width / 2),
    );
    final bottomNavigation = find.byKey(const Key('mobile-bottom-navigation'));

    await tester.tap(
      find.descendant(of: bottomNavigation, matching: find.text('Upcoming')),
    );
    await _pumpFrames(tester);
    expect(find.byKey(const ValueKey('upcoming-calendar')), findsOneWidget);
    expect(find.byKey(const ValueKey('upcoming-agenda')), findsOneWidget);

    await tester.tap(
      find.descendant(of: bottomNavigation, matching: find.text('Inbox')),
    );
    await _pumpFrames(tester);
    expect(find.text('Capture tasks before organizing them.'), findsOneWidget);

    await tester.tap(
      find.descendant(of: bottomNavigation, matching: find.text('Focus')),
    );
    await _pumpFrames(tester);
    expect(find.text('No active session'), findsOneWidget);
  });

  testWidgets('task list scrolls last row above compact bottom chrome', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      onboardingCompletedPreferenceKey: true,
      launchOfferStartedAtPreferenceKey: '2026-01-01T10:00:00.000Z',
      focusViewModePreferenceKey: FocusViewMode.full.storageValue,
    });
    tester.view.padding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.resetPadding);
    final now = DateTime.utc(2026, 4, 30, 10);
    final today = _todaySchedule();
    await _pumpApp(
      tester,
      tasks: [
        for (var index = 0; index < 18; index++)
          _task(
            'scroll-$index',
            'Scroll task ${index + 1}',
            schedule: today,
            orderKey: index.toString().padLeft(2, '0'),
          ),
      ],
      activeRun: _focusRun(now),
      activeInterval: _focusInterval(now, status: 'running'),
      focusNow: now,
    );

    final lastTask = find.text('Scroll task 18');
    await tester.scrollUntilVisible(
      lastTask,
      420,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await _pumpFrames(tester);

    final surface = find.byKey(const Key('mini-focus-player-surface'));
    final bottomNavigation = find.byKey(const Key('mobile-bottom-navigation'));
    final lastTaskRow = find
        .ancestor(of: lastTask, matching: find.byType(InkWell))
        .first;
    expect(surface, findsOneWidget);
    expect(bottomNavigation, findsOneWidget);
    expect(
      tester.getBottomLeft(lastTaskRow).dy,
      moreOrLessEquals(tester.getTopLeft(surface).dy, epsilon: 1),
    );

    await tester.tap(lastTask);
    await _pumpFrames(tester);

    expect(find.text('Focus history'), findsOneWidget);
  });

  testWidgets('upcoming calendar filters the agenda from the selected day', (
    tester,
  ) async {
    late GoRouter router;
    final today = DateTime(2026, 1, 2);
    final tomorrow = today.add(const Duration(days: 1));
    final later = today.add(const Duration(days: 2));
    await _pumpApp(
      tester,
      onRouter: (value) => router = value,
      tasks: [
        _task(
          'today-upcoming-test',
          'Today task',
          schedule: TaskSchedule.allDay(today),
        ),
        _task(
          'tomorrow-upcoming-test',
          'Upcoming task',
          schedule: TaskSchedule.allDay(tomorrow),
        ),
        _task(
          'later-upcoming-test',
          'Later upcoming task',
          schedule: TaskSchedule.allDay(later),
        ),
      ],
    );

    await tester.tap(find.text('Upcoming'));
    await _pumpFrames(tester);

    final routeDate = _routeDate(tomorrow);
    final laterRouteDate = _routeDate(later);
    final day = find.byKey(ValueKey('upcoming-calendar-day-$routeDate'));

    expect(find.byKey(const ValueKey('upcoming-calendar')), findsOneWidget);
    expect(find.text('Upcoming task'), findsOneWidget);
    expect(find.text('Later upcoming task'), findsOneWidget);
    expect(find.text('Today task'), findsOneWidget);

    await tester.tap(day);
    await _pumpFrames(tester);

    expect(_routerUri(router), '/upcoming?date=$routeDate');
    expect(find.text('Upcoming task'), findsOneWidget);
    expect(find.text('Later upcoming task'), findsOneWidget);
    expect(find.text('Today task'), findsNothing);
    expect(
      find.byKey(ValueKey('upcoming-day-group-$laterRouteDate')),
      findsOneWidget,
    );
    final selectedGroup = find.byKey(ValueKey('upcoming-day-group-$routeDate'));
    expect(selectedGroup, findsOneWidget);
    final selectedRect = tester.getRect(selectedGroup);
    final viewportHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(selectedRect.bottom, greaterThan(0));
    expect(selectedRect.top, lessThan(viewportHeight));
    expect(
      find.byKey(ValueKey('upcoming-calendar-selected-marker-$routeDate')),
      findsOneWidget,
    );

    await tester.ensureVisible(day);
    await _pumpFrames(tester);
    await tester.tap(day);
    await _pumpFrames(tester);

    expect(_routerUri(router), '/upcoming');
    expect(find.text('Upcoming task'), findsOneWidget);
    expect(find.text('Later upcoming task'), findsOneWidget);
    expect(
      find.byKey(ValueKey('upcoming-calendar-selected-marker-$routeDate')),
      findsNothing,
    );
  });

  testWidgets('focus active controls call repository methods', (tester) async {
    SharedPreferences.setMockInitialValues({
      focusViewModePreferenceKey: FocusViewMode.full.storageValue,
      focusTimerVisualStylePreferenceKey:
          FocusTimerVisualStyle.bar.storageValue,
    });
    final now = DateTime.utc(2026, 4, 30, 10);
    final focusRepository = _FakeFocusRepository(
      activeRun: _focusRun(now),
      activeInterval: _focusInterval(now, status: 'running'),
    );

    await _pumpFocusScreen(tester, focusRepository, now);

    await tester.tap(find.widgetWithText(FilledButton, 'Pause'));
    await tester.pump();
    expect(find.text('Log distraction'), findsNothing);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Complete interval'));
    await tester.pump();
    expect(find.text('Interval completed'), findsOneWidget);
    await _tapFullFocusMenuItem(tester, 'Skip');
    await _tapFullFocusMenuItem(tester, 'Stop');
    await tester.pump();
    expect(find.text('Focus stopped'), findsOneWidget);

    expect(focusRepository.pauseCount, 1);
    expect(focusRepository.completeCount, 1);
    expect(focusRepository.skipCount, 1);
    expect(focusRepository.stopReasons, [StopFocusReason.stopped]);
    expect(focusRepository.distractionRunIds, isEmpty);
  });

  testWidgets('focus minimal active controls keep primary and mode action', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      focusViewModePreferenceKey: FocusViewMode.minimal.storageValue,
    });
    final now = DateTime.utc(2026, 4, 30, 10);
    final focusRepository = _FakeFocusRepository(
      activeRun: _focusRun(now),
      activeInterval: _focusInterval(now, status: 'running'),
    );

    await _pumpFocusScreen(tester, focusRepository, now);

    expect(
      find.widgetWithText(OutlinedButton, 'Complete interval'),
      findsNothing,
    );
    expect(find.widgetWithText(OutlinedButton, 'Skip'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Stop'), findsNothing);
    expect(find.byKey(const Key('minimal-active-more-menu')), findsNothing);
    final menu = find.byKey(const Key('focus-details-menu'));
    expect(menu, findsOneWidget);
    await tester.tap(
      find.descendant(of: menu, matching: find.byIcon(Icons.more_horiz)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Switch to Full'), findsOneWidget);
    expect(find.text('Skip'), findsNothing);
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Pause'));
    await tester.pump();

    expect(focusRepository.pauseCount, 1);
    expect(focusRepository.completeCount, 0);
    expect(focusRepository.skipCount, 0);
    expect(focusRepository.stopReasons, isEmpty);
    expect(focusRepository.distractionRunIds, isEmpty);
  });

  testWidgets('focus minimal paused state exposes Resume control', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      focusViewModePreferenceKey: FocusViewMode.minimal.storageValue,
    });
    final now = DateTime.utc(2026, 4, 30, 10);
    final focusRepository = _FakeFocusRepository(
      activeRun: _focusRun(now),
      activeInterval: _focusInterval(now, status: 'paused', pausedAt: now),
    );

    await _pumpFocusScreen(tester, focusRepository, now);

    await tester.tap(find.widgetWithText(FilledButton, 'Resume'));
    await tester.pump();

    expect(focusRepository.resumeCount, 1);
  });

  testWidgets('focus minimal ready state starts the next interval', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      focusViewModePreferenceKey: FocusViewMode.minimal.storageValue,
    });
    final now = DateTime.utc(2026, 4, 30, 10);
    final focusRepository = _FakeFocusRepository(
      activeRun: _focusRun(now),
      activeInterval: _focusInterval(now, status: 'ready'),
    );

    await _pumpFocusScreen(tester, focusRepository, now);

    await tester.tap(find.widgetWithText(FilledButton, 'Start interval'));
    await tester.pump();

    expect(focusRepository.startReadyCount, 1);
  });

  testWidgets('focus paused state exposes Resume control', (tester) async {
    final now = DateTime.utc(2026, 4, 30, 10);
    final focusRepository = _FakeFocusRepository(
      activeRun: _focusRun(now),
      activeInterval: _focusInterval(now, status: 'paused', pausedAt: now),
    );

    await _pumpFocusScreen(tester, focusRepository, now);

    await tester.tap(find.widgetWithText(FilledButton, 'Resume'));
    await tester.pump();

    expect(focusRepository.resumeCount, 1);
  });

  testWidgets('browse inline create icons create projects and labels', (
    tester,
  ) async {
    final harness = await _pumpBrowseScreen(tester);

    await tester.enterText(
      find.widgetWithText(TextField, 'New project'),
      'Personal',
    );
    await tester.tap(find.byTooltip('Create').at(0));
    await _pumpFrames(tester);

    await tester.scrollUntilVisible(
      find.widgetWithText(TextField, 'New label'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(find.widgetWithText(TextField, 'New label'), 'home');
    await tester.tap(find.byTooltip('Create').at(1));
    await _pumpFrames(tester);

    expect(harness.projectRepository.createdProjectNames, ['Personal']);
    expect(harness.labelRepository.createdLabelNames, ['home']);
  });

  testWidgets(
    'browse productivity error can be retried without a stuck loader',
    (tester) async {
      var attempts = 0;
      await _pumpBrowseScreen(
        tester,
        productivitySummary: () {
          attempts += 1;
          return attempts == 1
              ? Stream<ProductivitySummary>.error(StateError('summary failed'))
              : Stream.value(_summary);
        },
      );

      expect(
        find.byKey(const Key('browse-productivity-error')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('browse-productivity-loading')),
        findsNothing,
      );
      expect(attempts, 1);

      await tester.tap(find.byKey(const Key('browse-productivity-retry')));
      await _pumpFrames(tester);

      expect(find.byKey(const Key('browse-productivity-error')), findsNothing);
      expect(
        find.byKey(const Key('browse-productivity-loading')),
        findsNothing,
      );
      expect(attempts, 2);
    },
  );

  testWidgets('projects screen switches to labels and confirms deletes', (
    tester,
  ) async {
    late GoRouter router;
    final harness = await _pumpApp(tester, onRouter: (value) => router = value);

    router.go('/projects');
    await _pumpFrames(tester);

    await tester.tap(find.byKey(const Key('projects-add-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('project-create-input')),
      'Personal',
    );
    await tester.tap(find.byKey(const Key('project-create-submit')));
    await _pumpFrames(tester);

    expect(harness.projectRepository.createdProjectNames, ['Personal']);

    await _openTextContextMenu(tester, 'Work');
    await tester.tap(find.text('Delete project'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-delete-project-button')));
    await _pumpFrames(tester);

    expect(harness.projectRepository.deletedProjectIds, ['project-1']);

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('projects-mode-segmented-button')),
        matching: find.text('Labels'),
      ),
    );
    await _pumpFrames(tester);

    expect(
      find.byKey(const ValueKey('projects-screen-label-label-1')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('labels-add-button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('label-create-input')), 'home');
    await tester.tap(find.byKey(const Key('label-create-submit')));
    await _pumpFrames(tester);

    expect(harness.labelRepository.createdLabelNames, ['home']);

    await _longPressTextContextMenu(tester, '@coding');
    expect(find.text('Delete label'), findsOneWidget);
    await tester.tap(find.text('Delete label'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await _pumpFrames(tester);

    await _openTextContextMenu(tester, '@coding');
    await tester.tap(find.text('Delete label'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-delete-label-button')));
    await _pumpFrames(tester);

    expect(harness.labelRepository.deletedLabelIds, ['label-1']);
  });

  testWidgets('projects create edit colors and toggle favorites', (
    tester,
  ) async {
    late GoRouter router;
    final harness = await _pumpApp(tester, onRouter: (value) => router = value);

    router.go('/projects');
    await _pumpFrames(tester);

    await tester.tap(find.byKey(const Key('projects-add-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('project-color-option-3')), findsOneWidget);
    await tester.tap(find.byKey(const Key('project-color-option-3')));
    await tester.enterText(
      find.byKey(const Key('project-create-input')),
      'Color project',
    );
    await tester.tap(find.byKey(const Key('project-create-submit')));
    await _pumpFrames(tester);

    expect(harness.projectRepository.createdProjectNames, ['Color project']);
    expect(harness.projectRepository.createdProjectColors, [
      projectColorPalette[3],
    ]);

    await tester.tap(find.byKey(const ValueKey('project-color-project-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('project-color-option-7')));
    await _pumpFrames(tester);

    await tester.tap(find.byKey(const ValueKey('project-favorite-project-1')));
    await _pumpFrames(tester);

    expect(harness.projectRepository.updatedProjectIds, [
      'project-1',
      'project-1',
    ]);
    expect(
      harness.projectRepository.updateProjectPatches[0].color,
      projectColorPalette[7],
    );
    expect(
      harness.projectRepository.updateProjectPatches[1].isFavorite,
      isTrue,
    );
  });

  testWidgets('project menu renames a project', (tester) async {
    late GoRouter router;
    final harness = await _pumpApp(tester, onRouter: (value) => router = value);

    router.go('/projects');
    await _pumpFrames(tester);

    await _openTextContextMenu(tester, 'Work');
    await tester.tap(find.text('Rename project'));
    await tester.pumpAndSettle();

    final input = find.byKey(const Key('project-rename-input'));
    expect(tester.widget<TextField>(input).controller!.text, 'Work');
    await tester.enterText(input, 'Renamed project');
    await tester.tap(find.byKey(const Key('project-rename-submit')));
    await _pumpFrames(tester);

    expect(harness.projectRepository.updatedProjectIds, ['project-1']);
    expect(
      harness.projectRepository.updateProjectPatches.single.name,
      'Renamed project',
    );
  });

  testWidgets('browse links to completed tasks without rendering them inline', (
    tester,
  ) async {
    await _pumpBrowseScreen(
      tester,
      tasks: [
        _task('open-browse', 'Open browse task'),
        _task(
          'done-browse',
          'Done task',
          status: 'completed',
          completedAt: DateTime.now().toUtc(),
        ),
      ],
    );
    await _pumpFrames(tester);

    expect(find.byKey(const Key('browse-completed-tasks')), findsOneWidget);
    expect(find.text('Done task'), findsNothing);
    expect(find.text('Open browse task'), findsNothing);
  });

  testWidgets('browse completed task link opens completed task screen', (
    tester,
  ) async {
    late GoRouter router;
    await _pumpApp(
      tester,
      onRouter: (value) => router = value,
      tasks: [
        _task('open-browse', 'Open browse task'),
        _task(
          'done-browse',
          'Done task',
          status: 'completed',
          completedAt: DateTime.now().toUtc(),
        ),
      ],
    );

    router.go('/browse');
    await _pumpFrames(tester);
    await tester.tap(find.byKey(const Key('browse-completed-tasks')));
    await _pumpFrames(tester);

    expect(_routerUri(router), '/browse/completed');
    expect(find.text('Done task'), findsOneWidget);
    expect(find.text('Open browse task'), findsNothing);
  });
}

class _TestApp extends ConsumerWidget {
  const _TestApp({this.onRouter, this.locale});

  final ValueChanged<GoRouter>? onRouter;
  final Locale? locale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    onRouter?.call(router);
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      routerConfig: router,
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
    );
  }
}

class _AppHarness {
  const _AppHarness({
    required this.taskRepository,
    required this.focusRepository,
    required this.projectRepository,
    required this.labelRepository,
  });

  final _FakeTaskRepository taskRepository;
  final _FakeFocusRepository focusRepository;
  final _FakeProjectRepository projectRepository;
  final _FakeLabelRepository labelRepository;
}

class _BrowseHarness {
  const _BrowseHarness({
    required this.projectRepository,
    required this.labelRepository,
  });

  final _FakeProjectRepository projectRepository;
  final _FakeLabelRepository labelRepository;
}

Future<_BrowseHarness> _pumpBrowseScreen(
  WidgetTester tester, {
  List<TaskItem> tasks = const <TaskItem>[],
  Stream<ProductivitySummary> Function()? productivitySummary,
}) async {
  final projectRepository = _FakeProjectRepository();
  final labelRepository = _FakeLabelRepository();

  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        taskRepositoryProvider.overrideWithValue(_FakeTaskRepository(tasks)),
        focusRepositoryProvider.overrideWithValue(_FakeFocusRepository()),
        projectRepositoryProvider.overrideWithValue(projectRepository),
        labelRepositoryProvider.overrideWithValue(labelRepository),
        productivitySummaryProvider.overrideWith(
          (ref) => productivitySummary?.call() ?? Stream.value(_summary),
        ),
        pendingSyncCommandsProvider.overrideWith((ref) => Stream.value([])),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: const BrowseScreen()),
    ),
  );
  await _pumpFrames(tester);

  return _BrowseHarness(
    projectRepository: projectRepository,
    labelRepository: labelRepository,
  );
}

Future<_AppHarness> _pumpApp(
  WidgetTester tester, {
  ValueChanged<GoRouter>? onRouter,
  List<TaskItem>? tasks,
  List<ProjectItem>? projects,
  FocusRunItem? activeRun,
  FocusIntervalItem? activeInterval,
  DateTime? focusNow,
  bool accountSignedIn = false,
  Object? taskMoveError,
  Set<String> updateErrorTaskIds = const {},
  Completer<void>? startupCompleter,
  Stream<List<TaskItem>>? taskStream,
  Size size = const Size(390, 844),
  Locale? locale,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final taskRepository = _FakeTaskRepository(
    tasks ?? _testTasks(),
    moveError: taskMoveError,
    updateErrorTaskIds: updateErrorTaskIds,
  );
  final focusRepository = _FakeFocusRepository(
    activeRun: activeRun,
    activeInterval: activeInterval,
  );
  final projectRepository = _FakeProjectRepository(projects: projects);
  final labelRepository = _FakeLabelRepository();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appStartupProvider.overrideWith(
          (ref) => startupCompleter?.future ?? Future<void>.value(),
        ),
        appStartupLifecycleProvider.overrideWith((ref) {}),
        taskStartNotificationCoordinatorProvider.overrideWith((ref) {}),
        reengagementNotificationCoordinatorProvider.overrideWith((ref) {}),
        clockProvider.overrideWithValue(
          FixedClock(DateTime.utc(2026, 1, 2, 11)),
        ),
        taskRepositoryProvider.overrideWithValue(taskRepository),
        if (taskStream != null)
          tasksByQueryProvider.overrideWith((ref, query) => taskStream),
        focusRepositoryProvider.overrideWithValue(focusRepository),
        if (focusNow != null)
          focusTickerProvider.overrideWith((ref) => Stream.value(focusNow)),
        projectRepositoryProvider.overrideWithValue(projectRepository),
        labelRepositoryProvider.overrideWithValue(labelRepository),
        quickAddServiceProvider.overrideWithValue(
          QuickAddService(
            parser: const QuickAddParser(),
            taskRepository: taskRepository,
            projectRepository: projectRepository,
          ),
        ),
        quickAddHintTextProvider.overrideWithValue(null),
        productivitySummaryProvider.overrideWith(
          (ref) => Stream.value(_summary),
        ),
        achievementsProvider.overrideWith(
          (ref) => Stream.value(const <AchievementItem>[]),
        ),
        achievementRepositoryProvider.overrideWithValue(
          _FakeAchievementRepository(),
        ),
        pendingSyncCommandsProvider.overrideWith((ref) => Stream.value([])),
        if (accountSignedIn)
          accountAuthStateProvider.overrideWith(
            (ref) => Stream.value(const AccountAuthState(signedIn: true)),
          ),
        currentUserProvider.overrideWith(
          (ref) => Stream.value(
            UserRow(
              id: localUserId,
              email: null,
              displayName: 'Local User',
              createdAt: DateTime.utc(2026),
              updatedAt: DateTime.utc(2026),
            ),
          ),
        ),
        calendarIntegrationRepositoryProvider.overrideWithValue(
          _FakeCalendarIntegrationRepository(),
        ),
      ],
      child: _TestApp(onRouter: onRouter, locale: locale),
    ),
  );
  await _pumpFrames(tester);
  await tester.pump();

  return _AppHarness(
    taskRepository: taskRepository,
    focusRepository: focusRepository,
    projectRepository: projectRepository,
    labelRepository: labelRepository,
  );
}

Future<void> _pumpFocusScreen(
  WidgetTester tester,
  _FakeFocusRepository focusRepository,
  DateTime now,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        focusRepositoryProvider.overrideWithValue(focusRepository),
        focusTickerProvider.overrideWith((ref) => Stream.value(now)),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: FocusScreen()),
      ),
    ),
  );
  await _pumpFrames(tester);
}

Future<void> _pumpFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
}

DateTime _testToday() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

void _expectTaskCompletionSnackBar(WidgetTester tester) {
  final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
  expect(snackBar.duration, const Duration(seconds: 7));
  expect(snackBar.action, isNull);
  expect(snackBar.showCloseIcon, isFalse);
  expect(snackBar.width, 320);
  expect(
    snackBar.padding,
    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
  );
  expect(tester.getSize(find.byType(SnackBar)).height, lessThanOrEqualTo(48));
  expect(find.byIcon(Icons.close), findsOneWidget);
}

void _setTimelineVisibleHourPrefs({
  int startMinutes = 8 * 60,
  int endMinutes = 18 * 60,
  int hourWidth = 192,
}) {
  SharedPreferences.setMockInitialValues({
    onboardingCompletedPreferenceKey: true,
    launchOfferStartedAtPreferenceKey: '2026-01-01T10:00:00.000Z',
    timelineVisibleStartMinutesPreferenceKey: startMinutes,
    timelineVisibleEndMinutesPreferenceKey: endMinutes,
    timelineHourWidthPreferenceKey: hourWidth,
  });
}

Future<void> _tapFullFocusMenuItem(WidgetTester tester, String label) async {
  final menu = find.byKey(const Key('focus-details-menu'));
  await tester.ensureVisible(menu);
  await tester.pump();
  await tester.tap(
    find.descendant(of: menu, matching: find.byIcon(Icons.more_horiz)),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> _openTaskContextMenu(WidgetTester tester, String taskTitle) async {
  await _openTextContextMenu(tester, taskTitle);
}

Future<void> _openTextContextMenu(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text).first);
  await tester.pump();
  await tester.tapAt(
    tester.getCenter(find.text(text).first),
    buttons: kSecondaryMouseButton,
  );
  await tester.pumpAndSettle();
}

Future<void> _longPressTextContextMenu(WidgetTester tester, String text) async {
  await tester.longPress(find.text(text).first);
  await tester.pumpAndSettle();
}

Future<void> _dragTaskOnto(
  WidgetTester tester,
  String draggedTitle,
  String targetTitle, {
  Duration holdDuration = const Duration(milliseconds: 600),
  PointerDeviceKind kind = PointerDeviceKind.touch,
}) async {
  final source = tester.getCenter(_taskDragSource(draggedTitle));
  final target = tester.getCenter(find.text(targetTitle).first);
  final gesture = await tester.startGesture(source, kind: kind);
  await tester.pump(holdDuration);
  await gesture.moveTo(target);
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

Future<void> _dragTaskToRootDropZone(
  WidgetTester tester,
  String draggedTitle,
) async {
  final source = tester.getCenter(_taskDragSource(draggedTitle));
  final target = tester.getCenter(find.byKey(const Key('task-root-drop-zone')));
  final gesture = await tester.startGesture(source);
  await tester.pump(const Duration(milliseconds: 600));
  await gesture.moveTo(target);
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

Future<void> _dragTaskToRootGap(
  WidgetTester tester,
  String draggedTitle, {
  int gapIndex = 0,
}) async {
  final source = tester.getCenter(_taskDragSource(draggedTitle));
  final target = tester.getCenter(find.byKey(Key('task-root-gap-$gapIndex')));
  final gesture = await tester.startGesture(source);
  await tester.pump(const Duration(milliseconds: 600));
  await gesture.moveTo(target);
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

Future<void> _dragTaskToPriority(
  WidgetTester tester,
  String draggedTitle,
  int priority,
) async {
  final source = tester.getCenter(_taskDragSource(draggedTitle));
  final target = tester.getCenter(
    find.byKey(Key('priority-matrix-quadrant-p$priority')),
  );
  final gesture = await tester.startGesture(source);
  await tester.pump(const Duration(milliseconds: 600));
  await gesture.moveTo(target);
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

Finder _taskDragSource(String title) {
  final row = find.ancestor(
    of: find.text(title).first,
    matching: find.byType(InkWell),
  );
  final handle = find.descendant(
    of: row.first,
    matching: find.byIcon(Icons.drag_indicator),
  );
  return handle.evaluate().isEmpty ? find.text(title).first : handle.first;
}

bool? _taskCheckboxValue(WidgetTester tester, String title) {
  final row = find.ancestor(
    of: find.text(title).first,
    matching: find.byType(InkWell),
  );
  return tester
      .widget<Checkbox>(
        find.descendant(of: row.first, matching: find.byType(Checkbox)).first,
      )
      .value;
}

Future<void> _dragTimelineTaskToSlot(
  WidgetTester tester,
  String draggedTitle,
  int minute, {
  String projectId = inboxProjectId,
}) async {
  final slot = find.byKey(Key('timeline-slot-$projectId-$minute'));
  final sourceFinder = _timelineTaskBlockForTitle(draggedTitle);
  await tester.ensureVisible(slot);
  await tester.ensureVisible(sourceFinder);
  await tester.pump();
  final source = tester.getCenter(sourceFinder);
  final target = tester.getCenter(slot);
  final gesture = await tester.startGesture(source);
  await tester.pump(const Duration(milliseconds: 600));
  await gesture.moveTo(target);
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

Future<void> _dragTimelineTaskToAllDay(
  WidgetTester tester,
  String draggedTitle,
) async {
  final targetFinder = find.byKey(const Key('timeline-all-day-section'));
  final sourceFinder = _timelineTaskBlockForTitle(draggedTitle);
  await tester.ensureVisible(targetFinder);
  await tester.ensureVisible(sourceFinder);
  await tester.pump();
  final source = tester.getCenter(sourceFinder);
  final target = tester.getCenter(targetFinder);
  final gesture = await tester.startGesture(source);
  await tester.pump(const Duration(milliseconds: 600));
  await gesture.moveTo(target);
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

Finder _timelineTaskBlockForTitle(String title) {
  return find
      .ancestor(
        of: find.text(title).first,
        matching: find.byWidgetPredicate((widget) {
          final key = widget.key;
          return key is ValueKey<String> &&
              key.value.startsWith('timeline-task-');
        }),
      )
      .first;
}

TaskSchedule _todaySchedule() {
  final now = DateTime.now();
  return TaskSchedule.allDay(DateTime(now.year, now.month, now.day));
}

TaskSchedule _timedSchedule(int hour) {
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, now.day, hour);
  return TaskSchedule.timed(
    start: start,
    end: start.add(const Duration(hours: 1)),
  );
}

TaskSchedule _scheduleAt(
  DateTime day,
  int hour, [
  int minute = 0,
  Duration duration = const Duration(hours: 1),
]) {
  final start = _dateAt(day, hour, minute);
  return TaskSchedule.timed(start: start, end: start.add(duration));
}

DateTime _dateAt(DateTime day, int hour, [int minute = 0]) {
  return DateTime(day.year, day.month, day.day, hour, minute);
}

String _routerUri(GoRouter router) {
  return router.routeInformationProvider.value.uri.toString();
}

String _routeDate(DateTime date) {
  return '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

List<TaskItem> _testTasks() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return [
    _task(
      'task-1',
      'Today task',
      schedule: TaskSchedule.allDay(today),
      estimatedFocusIntervals: 2,
    ),
    _task(
      'done-1',
      'Done task',
      status: 'completed',
      schedule: TaskSchedule.allDay(today),
    ),
    _task('inbox-1', 'Inbox task', description: 'Existing comment'),
    _task(
      'upcoming-1',
      'Upcoming task',
      schedule: TaskSchedule.allDay(today.add(const Duration(days: 1))),
    ),
  ];
}

TaskItem _task(
  String id,
  String content, {
  String projectId = inboxProjectId,
  String status = 'open',
  String? description,
  String? sectionId,
  String? parentId,
  TaskSchedule? schedule,
  int priority = 4,
  int? estimatedFocusIntervals,
  int completedFocusIntervals = 0,
  int totalFocusSeconds = 0,
  String? orderKey,
  bool isCollapsed = false,
  DateTime? completedAt,
}) {
  final now = DateTime.utc(2026);
  return TaskItem(
    id: id,
    userId: localUserId,
    content: content,
    description: description,
    projectId: projectId,
    sectionId: sectionId,
    parentId: parentId,
    priority: priority,
    dueJson: schedule?.toJsonString(),
    status: status,
    estimatedFocusIntervals: estimatedFocusIntervals,
    completedFocusIntervals: completedFocusIntervals,
    totalFocusSeconds: totalFocusSeconds,
    orderKey: orderKey ?? id,
    isDeleted: false,
    isCollapsed: isCollapsed,
    createdAt: now,
    updatedAt: now,
    completedAt: status == 'completed' ? completedAt ?? now : null,
  );
}

ProjectItem _project(
  String id,
  String name, {
  required String orderKey,
  String? color,
  String? parentId,
  bool isFavorite = false,
}) {
  final now = DateTime.utc(2026);
  return ProjectItem(
    id: id,
    userId: localUserId,
    name: name,
    color: color,
    parentId: parentId,
    isFavorite: isFavorite,
    orderKey: orderKey,
    createdAt: now,
    updatedAt: now,
  );
}

TaskItem _copyTask(
  TaskItem task, {
  String? content,
  String? description,
  bool updateDescription = false,
  String? projectId,
  bool updateProjectId = false,
  int? priority,
  String? dueJson,
  bool updateDueJson = false,
  int? estimatedFocusIntervals,
  bool updateEstimatedFocusIntervals = false,
  String? status,
  bool? isDeleted,
  String? parentId,
  bool updateParentId = false,
  String? sectionId,
  bool updateSectionId = false,
  String? orderKey,
  bool? isCollapsed,
  DateTime? completedAt,
}) {
  return TaskItem(
    id: task.id,
    userId: task.userId,
    content: content ?? task.content,
    description: updateDescription ? description : task.description,
    projectId: updateProjectId ? (projectId ?? task.projectId) : task.projectId,
    sectionId: updateSectionId ? sectionId : task.sectionId,
    parentId: updateParentId ? parentId : task.parentId,
    priority: priority ?? task.priority,
    dueJson: updateDueJson ? dueJson : task.dueJson,
    deadlineJson: task.deadlineJson,
    durationSeconds: task.durationSeconds,
    status: status ?? task.status,
    estimatedFocusIntervals: updateEstimatedFocusIntervals
        ? estimatedFocusIntervals
        : task.estimatedFocusIntervals,
    completedFocusIntervals: task.completedFocusIntervals,
    totalFocusSeconds: task.totalFocusSeconds,
    orderKey: orderKey ?? task.orderKey,
    dayOrder: task.dayOrder,
    isCollapsed: isCollapsed ?? task.isCollapsed,
    isDeleted: isDeleted ?? task.isDeleted,
    createdAt: task.createdAt,
    updatedAt: DateTime.utc(2026, 1, 2),
    completedAt: completedAt ?? task.completedAt,
  );
}

FocusRunItem _focusRun(DateTime now) {
  return FocusRunItem(
    id: 'run-1',
    userId: localUserId,
    presetId: 'default',
    status: 'running',
    startedAt: now.subtract(const Duration(minutes: 2)),
    targetWorkIntervals: 4,
    completedWorkIntervals: 1,
    createdAt: now,
    updatedAt: now,
  );
}

FocusIntervalItem _focusInterval(
  DateTime now, {
  required String status,
  DateTime? pausedAt,
}) {
  return FocusIntervalItem(
    id: 'interval-1',
    runId: 'run-1',
    type: 'work',
    status: status,
    plannedSeconds: 1500,
    startedAt: now.subtract(const Duration(minutes: 2)),
    pausedAt: pausedAt,
    pausedTotalSeconds: 0,
    sequenceNumber: 1,
    createdAt: now,
    updatedAt: now,
  );
}

const _summary = ProductivitySummary(
  completedTasks: 0,
  completedFocusIntervals: 0,
  totalFocusSeconds: 0,
  plannedFocusIntervals: 2,
  openTasks: 3,
  allTimeCompletedTasks: 0,
  allTimeCompletedFocusIntervals: 0,
);

class _FakeTaskRepository implements TaskRepository {
  _FakeTaskRepository(
    List<TaskItem> tasks, {
    this.moveError,
    this.updateErrorTaskIds = const {},
  }) : _tasks = {for (final task in tasks) task.id: task};

  final Map<String, TaskItem> _tasks;
  final Object? moveError;
  final Set<String> updateErrorTaskIds;
  final completedTaskIds = <String>[];
  final uncompletedTaskIds = <String>[];
  final deletedTaskIds = <String>[];
  final recurringDeleteTaskIds = <String>[];
  final recurringDeleteIncludeFollowing = <bool>[];
  final restoredBatches = <DeletedTaskBatch>[];
  final createdInputs = <CreateTaskInput>[];
  final updatePatches = <UpdateTaskPatch>[];
  final movedProjectIds = <String?>[];
  final movedParentIds = <String?>[];
  final placedTaskIds = <String>[];
  final placedSchedules = <TaskSchedule>[];
  final placedProjectIds = <String>[];
  final duplicatedTaskIds = <Set<String>>[];
  final duplicateIncludeSubtasks = <bool>[];

  @override
  Stream<List<TaskItem>> watchTasks(TaskQuery query) {
    return Stream.value(
      _tasks.values.where((task) {
        if (task.isDeleted) {
          return false;
        }
        final now = query.now ?? DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final due = task.dueDate;
        return switch (query.kind) {
          TaskQueryKind.inbox =>
            !task.isCompleted &&
                task.projectId == inboxProjectId &&
                due == null,
          TaskQueryKind.today =>
            !task.isCompleted && due != null && !due.isAfter(today),
          TaskQueryKind.upcoming =>
            !task.isCompleted && due != null && due.isAfter(today),
          TaskQueryKind.day =>
            !task.isCompleted &&
                due != null &&
                due ==
                    DateTime(
                      (query.date ?? today).year,
                      (query.date ?? today).month,
                      (query.date ?? today).day,
                    ),
          TaskQueryKind.project =>
            !task.isCompleted && task.projectId == query.projectId,
          TaskQueryKind.search => !task.isCompleted,
          TaskQueryKind.all => !task.isCompleted,
          TaskQueryKind.completed => task.isCompleted,
        };
      }).toList(),
    );
  }

  @override
  Stream<TaskItem?> watchTask(String id) => Stream.value(_tasks[id]);

  @override
  Future<String> createTask(CreateTaskInput input) async {
    createdInputs.add(input);
    return 'created-${createdInputs.length}';
  }

  @override
  Future<List<String>> duplicateTasks(
    Set<String> taskIds, {
    required bool includeSubtasks,
  }) async {
    duplicatedTaskIds.add(taskIds);
    duplicateIncludeSubtasks.add(includeSubtasks);
    return [for (final id in taskIds) 'copy-$id'];
  }

  @override
  Future<void> updateTask(String id, UpdateTaskPatch patch) async {
    if (updateErrorTaskIds.contains(id)) {
      throw StateError('update failed');
    }
    updatePatches.add(patch);
    final task = _tasks[id];
    if (task == null) {
      return;
    }
    final schedule =
        patch.schedule ??
        (patch.dueDate == null ? null : TaskSchedule.allDay(patch.dueDate!));
    _tasks[id] = _copyTask(
      task,
      content: patch.content,
      description: patch.description,
      updateDescription: patch.updateDescription,
      priority: patch.priority,
      dueJson: patch.clearSchedule ? null : schedule?.toJsonString(),
      updateDueJson: patch.clearSchedule || schedule != null,
      estimatedFocusIntervals: patch.estimatedFocusIntervals,
      updateEstimatedFocusIntervals: patch.estimatedFocusIntervals != null,
      isCollapsed: patch.isCollapsed,
    );
  }

  @override
  Future<void> materializeDueRecurringTasks({DateTime? now}) async {}

  @override
  Future<void> moveTask(
    String id, {
    String? projectId,
    String? sectionId,
    bool clearSectionId = false,
    String? parentId,
    bool clearParentId = false,
    String? orderKey,
  }) async {
    if (moveError != null) {
      throw moveError!;
    }
    movedProjectIds.add(projectId);
    movedParentIds.add(clearParentId ? null : parentId);
    final task = _tasks[id];
    if (task != null) {
      _tasks[id] = _copyTask(
        task,
        projectId: projectId,
        updateProjectId: projectId != null,
        sectionId: clearSectionId ? null : sectionId,
        updateSectionId: clearSectionId || sectionId != null,
        parentId: clearParentId ? null : parentId,
        updateParentId: clearParentId || parentId != null,
        orderKey: orderKey,
      );
    }
  }

  @override
  Future<void> placeTaskOnTimeline(
    String id, {
    required TaskSchedule schedule,
    required String projectId,
  }) async {
    placedTaskIds.add(id);
    placedSchedules.add(schedule);
    placedProjectIds.add(projectId);
    final task = _tasks[id];
    if (task != null) {
      _tasks[id] = _copyTask(
        task,
        projectId: projectId,
        updateProjectId: true,
        dueJson: schedule.toJsonString(),
        updateDueJson: true,
      );
    }
  }

  @override
  Future<void> completeTask(String id) async {
    for (final taskId in _subtreeIds(id)) {
      completedTaskIds.add(taskId);
      final task = _tasks[taskId];
      if (task != null) {
        _tasks[taskId] = _copyTask(
          task,
          status: 'completed',
          completedAt: DateTime.utc(2026, 1, 2),
        );
      }
    }
  }

  @override
  Future<void> uncompleteTask(String id) async {
    for (final taskId in _subtreeIds(id)) {
      uncompletedTaskIds.add(taskId);
      final task = _tasks[taskId];
      if (task != null) {
        _tasks[taskId] = _copyTask(task, status: 'open', completedAt: null);
      }
    }
  }

  @override
  Future<DeletedTaskBatch> deleteTask(String id) => deleteTasks({id});

  @override
  Future<DeletedTaskBatch> deleteTasks(Set<String> ids) async {
    final deletedIds = <String>{};
    for (final id in ids) {
      deletedIds.addAll(_subtreeIds(id));
    }
    for (final taskId in deletedIds) {
      deletedTaskIds.add(taskId);
      final task = _tasks[taskId];
      if (task != null) {
        _tasks[taskId] = _copyTask(task, isDeleted: true);
      }
    }
    return DeletedTaskBatch(
      taskIds: deletedIds,
      undoUntil: DateTime.now().toUtc().add(const Duration(seconds: 7)),
    );
  }

  @override
  Future<DeletedTaskBatch> deleteRecurringOccurrence(
    String id, {
    required bool includeFollowing,
  }) async {
    recurringDeleteTaskIds.add(id);
    recurringDeleteIncludeFollowing.add(includeFollowing);
    return deleteTask(id);
  }

  @override
  Future<bool> restoreDeletedTasks(DeletedTaskBatch batch) async {
    restoredBatches.add(batch);
    for (final id in batch.taskIds) {
      final task = _tasks[id];
      if (task != null) {
        _tasks[id] = _copyTask(task, isDeleted: false);
      }
    }
    return true;
  }

  @override
  Future<void> updateFocusAggregates(String id) async {}

  @override
  Future<String> createTaskFromCalendar(RemoteCalendarTaskInput input) async {
    return 'remote-task';
  }

  @override
  Future<void> applyRemoteCalendarPatch(
    String id,
    RemoteCalendarTaskPatch patch,
  ) async {}

  List<String> _subtreeIds(String rootId) {
    final result = <String>[];
    final stack = <String>[rootId];
    final seen = <String>{};
    while (stack.isNotEmpty) {
      final id = stack.removeLast();
      if (!seen.add(id) || !_tasks.containsKey(id)) {
        continue;
      }
      result.add(id);
      for (final task in _tasks.values) {
        if (task.parentId == id && !task.isDeleted) {
          stack.add(task.id);
        }
      }
    }
    return result;
  }
}

Iterable<MethodCall> _hapticCalls(Iterable<MethodCall> calls) =>
    calls.where((call) => call.method == 'HapticFeedback.vibrate');

class _FakeFocusRepository implements FocusRepository {
  _FakeFocusRepository({this.activeRun, this.activeInterval});

  final FocusRunItem? activeRun;
  final FocusIntervalItem? activeInterval;
  final startInputs = <StartFocusRunInput>[];
  final stopReasons = <StopFocusReason>[];
  final distractionRunIds = <String>[];
  final changedPresetIds = <String>[];
  int pauseCount = 0;
  int resumeCount = 0;
  int completeCount = 0;
  int skipCount = 0;
  int startReadyCount = 0;

  @override
  Stream<List<FocusPresetItem>> watchPresets() => Stream.value([
    FocusPresetItem(
      id: defaultPresetId,
      userId: localUserId,
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
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    ),
  ]);

  @override
  Stream<FocusRunItem?> watchActiveRun() => Stream.value(activeRun);

  @override
  Stream<FocusIntervalItem?> watchActiveInterval() =>
      Stream.value(activeInterval);

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
  Stream<FocusDailyStats> watchDailyStats(DateTime localDate) {
    return Stream.value(
      const FocusDailyStats(
        completedTasks: 0,
        completedFocusIntervals: 0,
        totalFocusSeconds: 0,
        interruptedIntervals: 0,
        plannedFocusIntervals: 0,
      ),
    );
  }

  @override
  Future<String> startRun(StartFocusRunInput input, {DateTime? now}) async {
    startInputs.add(input);
    return 'run-${startInputs.length}';
  }

  @override
  Future<String> createPreset(CreateFocusPresetInput input) async => 'preset';

  @override
  Future<void> updatePreset(String id, UpdateFocusPresetInput input) async {}

  @override
  Future<void> deletePreset(String id) async {}

  @override
  Future<void> setDefaultPreset(String id) async {}

  @override
  Future<void> changeActiveRunPreset(String presetId) async {
    changedPresetIds.add(presetId);
  }

  @override
  Future<void> startReadyInterval() async {
    startReadyCount++;
  }

  @override
  Future<void> pauseActiveInterval({DateTime? now}) async {
    pauseCount++;
  }

  @override
  Future<void> resumeActiveInterval({DateTime? now}) async {
    resumeCount++;
  }

  @override
  Future<void> restartActiveInterval({DateTime? now}) async {}

  @override
  Future<void> completeActiveInterval({DateTime? now}) async {
    completeCount++;
  }

  @override
  Future<void> skipActiveInterval({DateTime? now}) async {
    skipCount++;
  }

  @override
  Future<void> stopActiveRun({
    required StopFocusReason reason,
    DateTime? now,
  }) async {
    stopReasons.add(reason);
  }

  @override
  Future<void> logDistraction({required String runId, String? note}) async {
    distractionRunIds.add(runId);
  }
}

class _FakeProjectRepository implements ProjectRepository {
  _FakeProjectRepository({List<ProjectItem>? projects})
    : _projects =
          projects ??
          [
            _project(inboxProjectId, 'Inbox', orderKey: '0'),
            _project(
              'project-1',
              'Work',
              orderKey: 'project-1',
              color: projectColorPalette[1],
            ),
          ];

  final List<ProjectItem> _projects;
  final createdProjectNames = <String>[];
  final createdProjectColors = <String?>[];
  final updatedProjectIds = <String>[];
  final updateProjectPatches = <UpdateProjectPatch>[];
  final deletedProjectIds = <String>[];

  @override
  Stream<List<ProjectItem>> watchProjects() => Stream.value(_projects);

  @override
  Future<ProjectItem?> findByName(String name) async => null;

  @override
  Future<String> createProject(String name, {String? color}) async {
    createdProjectNames.add(name);
    createdProjectColors.add(color);
    return 'project-${createdProjectNames.length}';
  }

  @override
  Future<void> updateProject(String id, UpdateProjectPatch patch) async {
    updatedProjectIds.add(id);
    updateProjectPatches.add(patch);
  }

  @override
  Future<void> deleteProject(String id) async {
    deletedProjectIds.add(id);
  }
}

class _FakeLabelRepository implements LabelRepository {
  final createdLabelNames = <String>[];
  final deletedLabelIds = <String>[];

  @override
  Stream<List<LabelItem>> watchLabels() => Stream.value([
    LabelItem(
      id: 'label-1',
      userId: localUserId,
      name: 'coding',
      orderKey: 'label-1',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    ),
  ]);

  @override
  Future<LabelItem?> findByName(String name) async => null;

  @override
  Future<String> createLabel(String name) async {
    createdLabelNames.add(name);
    return 'label-${createdLabelNames.length}';
  }

  @override
  Future<void> deleteLabel(String id) async {
    deletedLabelIds.add(id);
  }
}

class _FakeAchievementRepository implements AchievementRepository {
  @override
  Stream<List<AchievementItem>> watchAchievements() =>
      Stream.value(const <AchievementItem>[]);

  @override
  Future<List<AchievementItem>> takePendingAnnouncements(
    List<AchievementItem> items,
  ) async => const <AchievementItem>[];
}

class _FakeCalendarIntegrationRepository
    implements CalendarIntegrationRepository {
  @override
  Stream<GoogleCalendarConnectionRow?> watchConnection() => Stream.value(null);

  @override
  Stream<GoogleCalendarEventLinkRow?> watchLinkForTask(String taskId) =>
      Stream.value(null);
}
