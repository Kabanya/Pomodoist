import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pomodoist/config/habit_dependencies.dart';
import 'package:pomodoist/config/habit_notification_dependencies.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/config/task_preferences_dependencies.dart';
import 'package:pomodoist/data/repositories/settings/preferences_repository.dart';
import 'package:pomodoist/data/repositories/habits/habit_repository.dart';
import 'package:pomodoist/domain/models/habits/habit_models.dart';
import 'package:pomodoist/domain/models/notifications/habit_reminder_status.dart';
import 'package:pomodoist/ui/core/localization/app_localizations.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/core/widgets/task_details_host.dart';
import 'package:pomodoist/ui/habits/widgets/habit_editor.dart';
import 'package:pomodoist/ui/habits/widgets/habits_screen.dart';
import 'package:pomodoist/ui/habits/widgets/habit_overview.dart';
import 'package:pomodoist/ui/habits/widgets/habits_progress_view.dart';
import 'package:pomodoist/utils/clock.dart';
import 'package:pomodoist/utils/result.dart';

import 'support/test_app.dart';

Future<void> _pump(
  WidgetTester tester, {
  double width = 1440,
  bool dark = false,
  double scale = 1,
  Map<HabitDayPeriod, int> targets = const {},
  HabitRepository? repository,
  Stream<List<Habit>>? habitEvents,
  bool settle = true,
  String title = 'Drink water',
  _Preferences? preferences,
  int goal = 8,
  Stream<List<HabitCheckIn>>? checkIns,
}) async {
  tester.view.physicalSize = Size(width, 1024);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final now = DateTime(2026, 10, 31);
  final habit = Habit(
    id: 'water',
    userId: 'local-user',
    title: title,
    icon: 'glassWater',
    scheduleHistory: [
      HabitDraft(
        title: title,
        startDate: DateTime(2026, 10, 1),
        targetPerDay: goal,
        periodTargets: targets,
      ).schedule(DateTime(2026, 10, 1)),
    ],
    createdAt: now,
    updatedAt: now,
  );
  final router = GoRouter(
    initialLocation: '/habits',
    routes: [
      GoRoute(
        path: '/habits',
        builder: (_, state) => Scaffold(
          body: HabitDetailsHost(
            habitId: state.uri.queryParameters['habit'],
            showOverview: true,
            child: const TaskDetailsHost(taskId: null, child: HabitsScreen()),
          ),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        preferencesRepositoryProvider.overrideWithValue(
          preferences ?? _Preferences(),
        ),
        habitRepositoryProvider.overrideWithValue(repository ?? _NoWrites()),
        clockProvider.overrideWithValue(FixedClock(now)),
        habitsProvider.overrideWith(
          (_) => habitEvents ?? Stream.value([habit]),
        ),
        habitCheckInsProvider.overrideWith(
          (_) =>
              checkIns ??
              Stream.value([
                for (var i = 0; i < (targets.isEmpty ? 3 : 0); i++)
                  HabitCheckIn(
                    id: '$i',
                    userId: 'local-user',
                    habitId: 'water',
                    day: now,
                    createdAt: now,
                    updatedAt: now,
                  ),
              ]),
        ),
        projectsProvider.overrideWith((_) => Stream.value([])),
        habitReminderStatusProvider.overrideWith(_Status.new),
      ],
      child: MaterialApp.router(
        theme: dark ? AppTheme.dark() : AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => testAppBuilder(
          context,
          MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
        ),
        routerConfig: router,
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadTestAppResources);
  testWidgets(
    'desktop remembers progress view and temporarily falls back below 960',
    (tester) async {
      final preferences = _Preferences();
      await _pump(tester, width: 1440, preferences: preferences);
      expect(find.text('Day rhythm'), findsOneWidget);
      await tester.tap(find.text('Progress circle'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('habits-progress-circle')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('habit-overview')), findsNothing);
      expect(preferences.values['habits.presentation.v1'], 'progress');
      tester.view.physicalSize = const Size(959, 1024);
      await tester.pumpAndSettle();
      expect(find.text('Progress circle'), findsNothing);
      expect(
        find.byKey(const ValueKey('habits-progress-circle')),
        findsNothing,
      );
      tester.view.physicalSize = const Size(960, 1024);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('habits-progress-circle')),
        findsOneWidget,
      );
    },
    variant: TargetPlatformVariant({TargetPlatform.linux}),
  );
  testWidgets(
    'progress overview and editor keep presentation and draft through resizing',
    (tester) async {
      final preferences = _Preferences()
        ..values['habits.presentation.v1'] = 'progress';
      await _pump(tester, width: 1215, preferences: preferences);
      final circle = find.byKey(const ValueKey('habits-progress-circle'));
      final row = find.byKey(const ValueKey(('progress-habit', 'water')));
      final invokingFocus = Focus.of(
        tester.element(
          find
              .descendant(of: row, matching: find.byType(GestureDetector))
              .first,
        ),
      );
      invokingFocus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(circle, findsOneWidget);
      expect(find.byKey(const ValueKey('habit-overview')), findsOneWidget);
      await tester.ensureVisible(find.text('Edit habit').last);
      await tester.tap(find.text('Edit habit').last);
      await tester.pumpAndSettle();
      expect(find.byType(HabitEditor), findsOneWidget);
      expect(find.byKey(const ValueKey('habit-overview')), findsNothing);

      final title = find.byWidgetPredicate(
        (widget) =>
            widget is EditableText && widget.controller.text == 'Drink water',
      );
      await tester.enterText(title, 'Draft in progress view');
      tester.view.physicalSize = const Size(959, 1024);
      await tester.pumpAndSettle();
      expect(find.text('Draft in progress view'), findsOneWidget);
      tester.view.physicalSize = const Size(1215, 1024);
      await tester.pumpAndSettle();
      expect(find.text('Draft in progress view'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(HabitEditor), findsNothing);
      expect(find.byKey(const ValueKey('habit-overview')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(circle, findsOneWidget);
      expect(find.byKey(const ValueKey('habit-overview')), findsNothing);
      expect(invokingFocus.context, isNotNull);
      expect(invokingFocus.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({TargetPlatform.linux}),
  );
  testWidgets(
    'progress handles large goals, dark theme, 200 percent text and future dates',
    (tester) async {
      await _pump(
        tester,
        width: 960,
        dark: true,
        scale: 2,
        goal: 99,
        title: 'A long habit title that wraps across several lines',
        preferences: _Preferences()
          ..values['habits.presentation.v1'] = 'progress',
      );
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('1'));
      await tester.tap(find.text('1'));
      await tester.pumpAndSettle();
      expect(find.text('Future days are view only.'), findsOneWidget);
      final button = tester.widget<IconButton>(find.byType(IconButton).last);
      expect(button.onPressed, isNull);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({TargetPlatform.windows}),
  );
  testWidgets(
    'progress keeps segment order when completions move rows into cards and back',
    (tester) async {
      final marks = StreamController<List<HabitCheckIn>>();
      addTearDown(marks.close);
      await _pump(
        tester,
        width: 1215,
        goal: 1,
        checkIns: marks.stream,
        preferences: _Preferences()
          ..values['habits.presentation.v1'] = 'progress',
        settle: false,
      );
      marks.add([]);
      await tester.pumpAndSettle();
      final before = tester
          .widget<HabitsProgressCircle>(find.byType(HabitsProgressCircle))
          .rows
          .map((r) => r.habit.id)
          .toList();
      expect(find.text('Completed today'), findsNothing);
      final invokingFocus = tester
          .widget<InkWell>(
            find
                .descendant(
                  of: find.byKey(const ValueKey(('progress-habit', 'water'))),
                  matching: find.byType(InkWell),
                )
                .first,
          )
          .focusNode!;
      invokingFocus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      marks.add([
        HabitCheckIn(
          id: 'one',
          userId: 'local-user',
          habitId: 'water',
          day: DateTime(2026, 10, 31),
          createdAt: DateTime(2026, 10, 31),
          updatedAt: DateTime(2026, 10, 31),
        ),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Completed today'), findsOneWidget);
      expect(
        tester
            .widget<HabitsProgressCircle>(find.byType(HabitsProgressCircle))
            .rows
            .map((r) => r.habit.id),
        before,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(invokingFocus.hasFocus, isTrue);
      expect(invokingFocus.context, isNotNull);
      marks.add([]);
      await tester.pumpAndSettle();
      expect(find.text('Completed today'), findsNothing);
      expect(find.text('Remaining today'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({TargetPlatform.macOS}),
  );
  testWidgets(
    'progress hides crowded ring signs while retaining every habit and handles empty results',
    (tester) async {
      final events = StreamController<List<Habit>>();
      addTearDown(events.close);
      await _pump(
        tester,
        width: 1215,
        habitEvents: events.stream,
        preferences: _Preferences()
          ..values['habits.presentation.v1'] = 'progress',
        settle: false,
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      Habit habit(int i) => Habit(
        id: 'habit-$i',
        userId: 'local-user',
        title: 'Habit $i',
        scheduleHistory: [
          HabitDraft(
            title: 'Habit $i',
            startDate: DateTime(2026, 10, 1),
          ).schedule(DateTime(2026, 10, 1)),
        ],
        createdAt: DateTime(2026, 10, 31),
        updatedAt: DateTime(2026, 10, 31),
      );
      events.add([for (var i = 0; i < 6; i++) habit(i)]);
      await tester.pumpAndSettle();
      final circle = find.byType(HabitsProgressCircle);
      expect(
        find.descendant(of: circle, matching: find.byType(InkWell)),
        findsNWidgets(6),
      );
      events.add([for (var i = 0; i < 40; i++) habit(i)]);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: circle, matching: find.byType(InkWell)),
        findsNothing,
      );
      expect(tester.widget<HabitsProgressCircle>(circle).rows, hasLength(40));
      expect(
        find.byKey(const ValueKey(('progress-habit', 'habit-39'))),
        findsOneWidget,
      );
      events.add([]);
      await tester.pumpAndSettle();
      expect(circle, findsNothing);
      expect(
        find.text('Your habits start here. Add your first habit.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({TargetPlatform.linux}),
  );
  testWidgets('progress plus chooses a period without opening the overview', (
    tester,
  ) async {
    final repository = _Writes();
    await _pump(
      tester,
      width: 1215,
      targets: {HabitDayPeriod.morning: 1, HabitDayPeriod.evening: 2},
      repository: repository,
      preferences: _Preferences()
        ..values['habits.presentation.v1'] = 'progress',
    );
    final row = find.byKey(const ValueKey(('progress-habit', 'water')));
    final action = find.descendant(
      of: row,
      matching: find.byType(HabitCheckInButton),
    );
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(find.text('Morning · Remaining: 1'), findsOneWidget);
    await tester.tap(find.text('Evening · Remaining: 2'));
    await tester.pumpAndSettle();
    expect(repository.periods, [HabitDayPeriod.evening]);
    expect(find.byKey(const ValueKey('habit-overview')), findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant({TargetPlatform.linux}));
  testWidgets(
    'presentation save errors retain progress and do not block check-ins',
    (tester) async {
      final preferences = _Preferences()..failWrites = true;
      final repository = _Writes();
      await _pump(
        tester,
        width: 1215,
        preferences: preferences,
        repository: repository,
      );
      await tester.tap(find.text('Progress circle'));
      await tester.pumpAndSettle();
      expect(find.text('Could not remember this view.'), findsOneWidget);
      expect(find.byType(HabitsProgressCircle), findsOneWidget);
      final action = find.descendant(
        of: find.byKey(const ValueKey(('progress-habit', 'water'))),
        matching: find.byType(HabitCheckInButton),
      );
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(repository.periods, [HabitDayPeriod.anytime]);
      preferences.failWrites = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Could not remember this view.'), findsNothing);
      expect(preferences.values['habits.presentation.v1'], 'progress');
      await tester.tap(find.text('Finished'));
      await tester.pumpAndSettle();
      expect(find.byType(HabitsProgressCircle), findsNothing);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({TargetPlatform.linux}),
  );
  testWidgets(
    'progress check-in serializes repeated presses and recovers from write failure',
    (tester) async {
      final repository = _Writes()..result = Completer<Result<void>>();
      await _pump(
        tester,
        width: 1215,
        repository: repository,
        preferences: _Preferences()
          ..values['habits.presentation.v1'] = 'progress',
      );
      final action = find.descendant(
        of: find.byKey(const ValueKey(('progress-habit', 'water'))),
        matching: find.byType(HabitCheckInButton),
      );
      await tester.tap(action);
      await tester.tap(action);
      await tester.pump();
      expect(repository.periods, [HabitDayPeriod.anytime]);
      expect(
        tester
            .widget<IconButton>(
              find.descendant(of: action, matching: find.byType(IconButton)),
            )
            .onPressed,
        isNull,
      );
      repository.result!.complete(
        Result.error(Exception('failed'), StackTrace.current),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Could not save changes. Check the fields and try again.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<IconButton>(
              find.descendant(of: action, matching: find.byType(IconButton)),
            )
            .onPressed,
        isNotNull,
      );
      expect(find.byType(HabitsProgressCircle), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({TargetPlatform.linux}),
  );
  testWidgets(
    'desktop shows daily rhythm and selected weekly overview without view modes',
    (tester) async {
      await _pump(tester);
      expect(find.text('Small steps, every day'), findsOneWidget);
      expect(find.text('Throughout the day'), findsOneWidget);
      expect(find.byKey(const ValueKey('habit-overview')), findsOneWidget);
      expect(find.text('37.5%'), findsOneWidget);
      expect(find.text('List'), findsNothing);
      expect(find.text('Day rhythm'), findsNothing);
      expect(
        find.byKey(const ValueKey('habit-week-2026-11-01')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('habit-week-2026-11-01')));
      await tester.pumpAndSettle();
      expect(find.text('Future days are view only.'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('compact overview closes with Escape and editor replaces it', (
    tester,
  ) async {
    await _pump(tester, width: 390);
    expect(find.byKey(const ValueKey('habit-overview')), findsNothing);
    await tester.tap(find.text('Drink water'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('habit-overview')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('habit-overview')), findsNothing);
    await tester.tap(find.text('Drink water'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Edit habit'));
    await tester.tap(find.text('Edit habit'));
    await tester.pumpAndSettle();
    expect(find.byType(HabitEditor), findsOneWidget);
    expect(
      find.byKey(const ValueKey('habit-overview')).hitTestable(),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('dark compact layout accommodates larger text and resizing', (
    tester,
  ) async {
    const title =
        'A very long habit name that should wrap without hiding actions';
    await _pump(tester, width: 390, dark: true, scale: 2, title: title);
    await tester.ensureVisible(find.text(title));
    await tester.tap(find.text(title));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('habit-overview')), findsOneWidget);
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(1440, 1024);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('habit-overview')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editor replaces overview with nested hosts on a large window', (
    tester,
  ) async {
    await _pump(tester, width: 1800);
    await tester.tap(find.text('Edit habit'));
    await tester.pumpAndSettle();
    expect(find.byType(HabitEditor), findsOneWidget);
    expect(find.byKey(const ValueKey('habit-overview')), findsNothing);
    final title = find.byWidgetPredicate(
      (widget) =>
          widget is EditableText && widget.controller.text == 'Drink water',
    );
    await tester.enterText(title, 'Draft kept across resize');
    tester.view.physicalSize = const Size(390, 1024);
    await tester.pumpAndSettle();
    expect(find.text('Draft kept across resize'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(HabitEditor), findsNothing);
    tester.view.physicalSize = const Size(1800, 1024);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('habit-overview')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'daily check-in chooses a period and row buttons keep their period',
    (tester) async {
      final repository = _Writes();
      await _pump(
        tester,
        targets: {HabitDayPeriod.morning: 1, HabitDayPeriod.evening: 2},
        repository: repository,
      );
      await tester.tap(find.text('Check in'));
      await tester.pumpAndSettle();
      expect(find.text('Morning · Remaining: 1'), findsOneWidget);
      await tester.tap(find.text('Evening · Remaining: 2'));
      await tester.pumpAndSettle();
      expect(repository.periods, [HabitDayPeriod.evening]);
      final morning = find.byKey(
        const ValueKey<(String, String, HabitDayPeriod?)>((
          'habit-row',
          'water',
          HabitDayPeriod.morning,
        )),
      );
      await tester.tap(
        find.descendant(of: morning, matching: find.byType(HabitCheckInButton)),
      );
      await tester.pumpAndSettle();
      expect(repository.periods, [
        HabitDayPeriod.evening,
        HabitDayPeriod.morning,
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('loading, failed and empty states do not invent an overview', (
    tester,
  ) async {
    final habits = StreamController<List<Habit>>();
    addTearDown(habits.close);
    await _pump(tester, habitEvents: habits.stream, settle: false);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    habits.addError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.text('Could not load habits.'), findsOneWidget);
    habits.add([]);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('habit-overview')), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _Status extends HabitNotificationCoordinator {
  @override
  HabitReminderStatus build() => HabitReminderStatus.available;
}

class _NoWrites extends Fake implements HabitRepository {}

class _Preferences implements PreferencesRepository {
  final values = <String, Object>{};
  bool failWrites = false;
  @override
  Future<Result<Map<String, Object>>> read(
    Iterable<String> keys, {
    bool reload = false,
  }) async => Result.ok({
    for (final key in keys)
      if (values.containsKey(key)) key: values[key]!,
  });
  @override
  Future<Result<void>> write(Map<String, Object?> changes) async {
    if (failWrites) {
      return Result.error(Exception('save failed'), StackTrace.current);
    }
    for (final entry in changes.entries) {
      if (entry.value == null) {
        values.remove(entry.key);
      } else {
        values[entry.key] = entry.value!;
      }
    }
    return const Result.ok(null);
  }
}

class _Writes extends Fake implements HabitRepository {
  final periods = <HabitDayPeriod?>[];
  Completer<Result<void>>? result;
  @override
  Future<Result<void>> addCheckIn(
    String id,
    DateTime day, {
    required DateTime now,
    HabitDayPeriod? period,
  }) async {
    periods.add(period);
    if (result != null) return result!.future;
    return const Result.ok(null);
  }
}
