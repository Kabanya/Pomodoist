import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pomodoist/app/providers.dart';
import 'package:pomodoist/app/theme/app_theme.dart';
import 'package:pomodoist/core/time/clock.dart';
import 'package:pomodoist/features/focus/domain/focus_models.dart';
import 'package:pomodoist/features/planning/data/quick_add_service.dart';
import 'package:pomodoist/features/planning/domain/quick_add_parser.dart';
import 'package:pomodoist/features/tasks/domain/task_models.dart';
import 'package:pomodoist/features/tasks/presentation/upcoming_screen.dart';
import 'package:pomodoist/l10n/app_localizations.dart';
import 'package:pomodoist/l10n/app_localizations_ar.dart';
import 'package:pomodoist/l10n/app_localizations_ru.dart';

void main() {
  final today = DateTime(2030, 1, 10);

  test('Russian and Arabic task counts keep their plural categories', () {
    final ru = AppLocalizationsRu();
    final ar = AppLocalizationsAr();

    expect(
      [
        for (final count in [0, 1, 2, 5, 11]) ru.upcomingTaskCount(count),
      ],
      ['Нет задач', '1 задача', '2 задачи', '5 задач', '11 задач'],
    );
    expect(
      [
        for (final count in [0, 1, 2, 5, 11]) ar.upcomingTaskCount(count),
      ],
      ['لا توجد مهام', 'مهمة واحدة', 'مهمتان', '5 مهام', '11 مهمة'],
    );
  });

  testWidgets('Upcoming reads complete open and completed streams', (
    tester,
  ) async {
    final queries = <TaskQuery>[];
    await _pumpUpcoming(
      tester,
      today: today,
      tasks: [_task('tomorrow', DateTime(2030, 1, 11))],
      onQuery: queries.add,
    );

    expect(queries, contains(const TaskQuery.all()));
    expect(queries, contains(const TaskQuery.completed()));
    expect(
      queries.where((query) => query.kind == TaskQueryKind.upcoming),
      isEmpty,
    );
    expect(queries.where((query) => query.kind == TaskQueryKind.day), isEmpty);
  });

  testWidgets(
    'Upcoming initially mounts today and future scheduled tasks once',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final pastOpen = _task(
        'past-open',
        DateTime(2030, 1, 9),
        content: 'Past open',
      );
      final todayDone = _task(
        'today-done',
        DateTime(2030, 1, 10),
        content: 'Today completed',
        status: 'completed',
      );
      final futureOpen = _task(
        'future-open',
        DateTime(2030, 1, 11),
        content: 'Future open',
      );
      final duplicateOpen = _task(
        'duplicate',
        DateTime(2030, 1, 11),
        content: 'Open duplicate',
      );
      final duplicateCompleted = _task(
        'duplicate',
        DateTime(2030, 1, 11),
        content: 'Completed duplicate',
        status: 'completed',
      );
      final deleted = _task(
        'deleted',
        DateTime(2030, 1, 11),
        content: 'Deleted task',
        isDeleted: true,
      );

      await _pumpUpcoming(
        tester,
        today: today,
        tasks: [futureOpen],
        allTasks: [pastOpen, futureOpen, duplicateOpen, deleted],
        completedTasks: [todayDone, duplicateCompleted],
      );

      expect(find.text('Past open'), findsNothing);
      expect(find.text('Today completed'), findsOneWidget);
      expect(find.text('Future open'), findsOneWidget);
      expect(find.text('Open duplicate'), findsOneWidget);
      expect(find.text('Completed duplicate'), findsNothing);
      expect(find.text('Deleted task'), findsNothing);

      final pastGroup = find.byKey(
        const ValueKey('upcoming-day-group-2030-01-09'),
      );
      final todayGroup = find.byKey(
        const ValueKey('upcoming-day-group-2030-01-10'),
      );
      final futureGroup = find.byKey(
        const ValueKey('upcoming-day-group-2030-01-11'),
      );
      expect(pastGroup, findsNothing);
      expect(todayGroup, findsOneWidget);
      expect(futureGroup, findsOneWidget);
      expect(
        tester.getTopLeft(todayGroup).dy,
        lessThan(tester.getTopLeft(futureGroup).dy),
      );

      final todaySemantics = tester.getSemantics(
        find.byKey(const ValueKey('upcoming-calendar-day-2030-01-10')),
      );
      expect(todaySemantics.label, contains('1 task'));
      semantics.dispose();
    },
  );

  testWidgets('calendar selection hides agenda days before the selected date', (
    tester,
  ) async {
    final tasks = [
      _task(
        'today',
        DateTime(2030, 1, 10),
        content: 'Today task before selection',
      ),
      _task('tomorrow', DateTime(2030, 1, 11)),
      _task('later', DateTime(2030, 1, 15)),
    ];
    final harness = await _pumpUpcoming(tester, today: today, tasks: tasks);

    await tester.tap(
      find.byKey(const ValueKey('upcoming-calendar-day-2030-01-11')),
    );
    await tester.pumpAndSettle();

    expect(_location(harness.router), '/upcoming?date=2030-01-11');
    expect(find.text('Today task before selection'), findsNothing);
    expect(find.text('Tomorrow task'), findsOneWidget);
    expect(find.text('Later task'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('upcoming-day-group-2030-01-10')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('upcoming-day-group-2030-01-11')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('upcoming-day-group-2030-01-15')),
      findsOneWidget,
    );
  });

  testWidgets('localized day headings sit above their agenda cards', (
    tester,
  ) async {
    await _pumpUpcoming(
      tester,
      today: today,
      tasks: [
        _task('tomorrow', DateTime(2030, 1, 11)),
        _task('later', DateTime(2030, 1, 17), content: 'Поздняя задача'),
      ],
      locale: const Locale('ru'),
    );

    expect(find.text('Завтра, 11 января'), findsOneWidget);
    final laterHeading = find.text('Четверг, 17 января');
    expect(laterHeading, findsOneWidget);

    const cardKey = ValueKey('upcoming-day-card-2030-01-17');
    final card = find.byKey(cardKey);
    expect(card, findsOneWidget);
    expect(find.ancestor(of: laterHeading, matching: card), findsNothing);
    expect(
      tester.getBottomLeft(laterHeading).dy,
      lessThan(tester.getTopLeft(card).dy),
    );
  });

  testWidgets('route selection scrolls to its group and repeat clears', (
    tester,
  ) async {
    final tasks = [
      for (var day = 11; day <= 20; day++)
        _task(
          'day-$day',
          DateTime(2030, 1, day),
          content: 'Task for January $day',
        ),
    ];
    final harness = await _pumpUpcoming(tester, today: today, tasks: tasks);
    const selectedDay = ValueKey('upcoming-calendar-day-2030-01-11');

    await tester.tap(find.byKey(selectedDay));
    await tester.pumpAndSettle();

    expect(_location(harness.router), '/upcoming?date=2030-01-11');
    expect(_verticalOffset(tester), greaterThan(0));
    expect(
      _isVisible(
        tester,
        find.byKey(const ValueKey('upcoming-day-group-2030-01-11')),
      ),
      isTrue,
    );

    await tester.ensureVisible(find.byKey(selectedDay));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(selectedDay));
    await tester.pumpAndSettle();

    expect(_location(harness.router), '/upcoming');
    expect(_verticalOffset(tester), 0);
  });

  testWidgets('initial and later route dates scroll after anchors mount', (
    tester,
  ) async {
    final tasks = [
      for (var day = 11; day <= 20; day++)
        _task(
          'day-$day',
          DateTime(2030, 1, day),
          content: 'Task for January $day',
        ),
    ];
    final harness = await _pumpUpcoming(
      tester,
      today: today,
      tasks: tasks,
      initialLocation: '/upcoming?date=2030-01-31',
    );

    expect(_verticalOffset(tester), 0);
    expect(
      _isVisible(
        tester,
        find.byKey(const ValueKey('upcoming-day-group-2030-01-31')),
      ),
      isTrue,
    );
    expect(find.text('No tasks scheduled for this day'), findsOneWidget);

    unawaited(harness.router.push('/upcoming?date=2030-01-15'));
    await tester.pumpAndSettle();

    expect(
      _isVisible(
        tester,
        find.byKey(const ValueKey('upcoming-day-group-2030-01-15')),
      ),
      isTrue,
    );

    harness.router.pop();
    await tester.pumpAndSettle();

    expect(_location(harness.router), '/upcoming?date=2030-01-31');
    expect(
      _isVisible(
        tester,
        find.byKey(const ValueKey('upcoming-day-group-2030-01-31')),
      ),
      isTrue,
    );
  });

  testWidgets('ordinary task stream updates do not repeat route scrolling', (
    tester,
  ) async {
    final tasks = [
      for (var day = 11; day <= 20; day++)
        _task(
          'day-$day',
          DateTime(2030, 1, day),
          content: 'Task for January $day',
        ),
    ];
    final controller = StreamController<List<TaskItem>>();
    addTearDown(controller.close);
    controller.add(tasks);
    await _pumpUpcoming(
      tester,
      today: today,
      tasks: tasks,
      allStream: controller.stream,
      initialLocation: '/upcoming?date=2030-01-20',
    );
    expect(_verticalOffset(tester), 0);

    final scrollView = tester.widget<SingleChildScrollView>(
      find.byKey(const ValueKey('upcoming-scroll-view')),
    );
    scrollView.controller!.jumpTo(0);
    await tester.pump();
    expect(_verticalOffset(tester), 0);

    controller.add([
      ...tasks,
      _task(
        'stream-update',
        DateTime(2030, 1, 21),
        content: 'Stream update task',
      ),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('Stream update task'), findsOneWidget);
    expect(_verticalOffset(tester), 0);
  });

  testWidgets('schedule stream update moves a task to tomorrow immediately', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final controller = StreamController<List<TaskItem>>();
    addTearDown(controller.close);
    controller.add([_task('moving-task', today, content: 'Moving task')]);
    await _pumpUpcoming(
      tester,
      today: today,
      tasks: const [],
      allStream: controller.stream,
    );

    expect(
      tester
          .getSemantics(
            find.byKey(const ValueKey('upcoming-calendar-day-2030-01-10')),
          )
          .label,
      contains('1 task'),
    );

    controller.add([
      _task('moving-task', DateTime(2030, 1, 11), content: 'Moving task'),
    ]);
    await tester.pumpAndSettle();

    expect(
      tester
          .getSemantics(
            find.byKey(const ValueKey('upcoming-calendar-day-2030-01-10')),
          )
          .label,
      contains('No tasks'),
    );
    expect(
      tester
          .getSemantics(
            find.byKey(const ValueKey('upcoming-calendar-day-2030-01-11')),
          )
          .label,
      contains('1 task'),
    );
    semantics.dispose();
  });

  testWidgets('today route filters the agenda from today onward', (
    tester,
  ) async {
    final harness = await _pumpUpcoming(
      tester,
      today: today,
      tasks: [
        _task('yesterday', DateTime(2030, 1, 9), content: 'Yesterday task'),
        _task('today', DateTime(2030, 1, 10), content: 'Today task'),
        _task('tomorrow', DateTime(2030, 1, 11)),
      ],
      initialLocation: '/upcoming?date=2030-01-10',
    );

    expect(_location(harness.router), '/upcoming?date=2030-01-10');
    expect(find.text('Yesterday task'), findsNothing);
    expect(find.text('Today task'), findsOneWidget);
    expect(find.text('Tomorrow task'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('upcoming-day-group-2030-01-10')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('upcoming-calendar-selected-marker-2030-01-10'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'past deep link selects its empty group and repeat returns to today',
    (tester) async {
      final harness = await _pumpUpcoming(
        tester,
        today: today,
        tasks: [
          for (var day = 1; day <= 8; day++)
            _task(
              'day-$day',
              DateTime(2030, 1, day),
              content: 'Task for January $day',
            ),
          for (var day = 11; day <= 24; day++)
            _task(
              'day-$day',
              DateTime(2030, 1, day),
              content: 'Task for January $day',
            ),
        ],
        initialLocation: '/upcoming?date=2030-01-09',
      );

      expect(_location(harness.router), '/upcoming?date=2030-01-09');
      expect(
        find.byKey(const ValueKey('upcoming-day-group-2030-01-09')),
        findsOneWidget,
      );
      expect(find.text('No tasks scheduled for this day'), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey('upcoming-calendar-selected-marker-2030-01-09'),
        ),
        findsOneWidget,
      );
      expect(
        _isVisible(
          tester,
          find.byKey(const ValueKey('upcoming-day-group-2030-01-09')),
        ),
        isTrue,
      );
      expect(_verticalOffset(tester), greaterThan(0));
      expect(find.text('Task for January 1'), findsNothing);

      const selectedDay = ValueKey('upcoming-calendar-day-2030-01-09');
      await tester.ensureVisible(find.byKey(selectedDay));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(selectedDay));
      await tester.pumpAndSettle();

      expect(_location(harness.router), '/upcoming');
      expect(_verticalOffset(tester), 0);
      expect(
        find.byKey(
          const ValueKey('upcoming-calendar-selected-marker-2030-01-09'),
        ),
        findsNothing,
      );
      expect(find.text('Task for January 1'), findsNothing);
    },
  );

  testWidgets('quick add defaults to the selected day', (tester) async {
    final harness = await _pumpUpcoming(
      tester,
      today: today,
      tasks: const <TaskItem>[],
    );

    await tester.enterText(find.byType(TextField), 'Write outline');
    await tester.tap(find.byTooltip('Add'));
    await tester.pumpAndSettle();

    expect(
      _createdDate(harness.taskRepository.created.single),
      DateTime(2030, 1, 10),
    );

    harness.router.go('/upcoming?date=2030-01-20');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Review outline');
    await tester.tap(find.byTooltip('Add'));
    await tester.pumpAndSettle();

    expect(harness.taskRepository.created, hasLength(2));
    expect(
      _createdDate(harness.taskRepository.created.last),
      DateTime(2030, 1, 20),
    );

    harness.router.go('/upcoming?date=2030-01-09');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Review past outline');
    await tester.tap(find.byTooltip('Add'));
    await tester.pumpAndSettle();

    expect(harness.taskRepository.created, hasLength(3));
    expect(
      _createdDate(harness.taskRepository.created.last),
      DateTime(2030, 1, 9),
    );
  });

  testWidgets('broad and selected empty states stay distinct', (tester) async {
    final harness = await _pumpUpcoming(
      tester,
      today: today,
      tasks: const <TaskItem>[],
    );

    expect(find.text('No dated tasks'), findsOneWidget);
    expect(find.text('No tasks scheduled for this day'), findsNothing);

    harness.router.go('/upcoming?date=2030-02-20');
    await tester.pumpAndSettle();

    expect(find.text('No dated tasks'), findsNothing);
    expect(find.text('No tasks scheduled for this day'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('upcoming-day-group-2030-02-20')),
      findsOneWidget,
    );
  });

  testWidgets('loading state is visible', (tester) async {
    await _pumpUpcoming(
      tester,
      today: today,
      tasks: const <TaskItem>[],
      allStream: const Stream<List<TaskItem>>.empty(),
      settle: false,
    );

    expect(find.byKey(const ValueKey('upcoming-loading')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('upcoming-calendar-loading')),
      findsOneWidget,
    );
  });

  testWidgets('completed stream pending keeps the complete agenda loading', (
    tester,
  ) async {
    await _pumpUpcoming(
      tester,
      today: today,
      tasks: const <TaskItem>[],
      completedStream: const Stream<List<TaskItem>>.empty(),
      settle: false,
    );

    expect(find.byKey(const ValueKey('upcoming-loading')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('upcoming-calendar-loading')),
      findsOneWidget,
    );
  });

  testWidgets('error state is visible', (tester) async {
    await _pumpUpcoming(
      tester,
      today: today,
      tasks: const <TaskItem>[],
      allStream: Stream<List<TaskItem>>.error(StateError('agenda unavailable')),
      settle: false,
    );
    await tester.pump(const Duration(milliseconds: 10));

    expect(find.textContaining('agenda unavailable'), findsOneWidget);
    expect(find.byKey(const ValueKey('upcoming-error')), findsOneWidget);
  });

  testWidgets('completed stream error is visible', (tester) async {
    await _pumpUpcoming(
      tester,
      today: today,
      tasks: const <TaskItem>[],
      completedStream: Stream<List<TaskItem>>.error(
        StateError('completed agenda unavailable'),
      ),
      settle: false,
    );
    await tester.pump(const Duration(milliseconds: 10));

    expect(find.textContaining('completed agenda unavailable'), findsOneWidget);
    expect(find.byKey(const ValueKey('upcoming-error')), findsOneWidget);
  });

  testWidgets('agenda keeps project time and auxiliary subtask progress', (
    tester,
  ) async {
    final schedule = TaskSchedule.timed(
      start: DateTime(2030, 1, 11, 14),
      end: DateTime(2030, 1, 11, 14, 30),
    );
    final parent = _task(
      'parent',
      DateTime(2030, 1, 11),
      content: 'Plan launch',
      projectId: 'work',
      schedule: schedule,
    );
    final completedChild = _task(
      'child',
      DateTime(2030, 1, 11),
      content: 'Completed preparation',
      parentId: parent.id,
      status: 'completed',
      scheduled: false,
    );

    await _pumpUpcoming(
      tester,
      today: today,
      tasks: [parent],
      allTasks: [parent],
      completedTasks: [completedChild],
      projects: [_project('work', 'Work', color: '#3B82F6')],
    );

    expect(find.text('Plan launch'), findsOneWidget);
    expect(find.text('Work'), findsOneWidget);
    expect(find.text('14:00'), findsOneWidget);
    expect(find.text('1/1'), findsOneWidget);
    expect(find.text('Completed preparation'), findsNothing);
  });

  testWidgets('today action selects today and filters the agenda', (
    tester,
  ) async {
    final tasks = [
      _task(
        'yesterday',
        DateTime(2030, 1, 9),
        content: 'Yesterday task before Today action',
      ),
      _task('today', DateTime(2030, 1, 10), content: 'Today action task'),
      for (var day = 11; day <= 20; day++)
        _task(
          'day-$day',
          DateTime(2030, 1, day),
          content: 'Task for January $day',
        ),
    ];
    final harness = await _pumpUpcoming(tester, today: today, tasks: tasks);

    await tester.tap(find.byKey(const ValueKey('upcoming-calendar-next')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('upcoming-calendar-day-2030-01-10')),
      findsNothing,
    );

    final scrollView = tester.widget<SingleChildScrollView>(
      find.byKey(const ValueKey('upcoming-scroll-view')),
    );
    scrollView.controller!.jumpTo(
      scrollView.controller!.position.maxScrollExtent,
    );
    await tester.pump();
    expect(_verticalOffset(tester), greaterThan(0));

    final todayButton = tester.widget<TextButton>(
      find.byKey(const ValueKey('upcoming-calendar-today')),
    );
    todayButton.onPressed!();
    await tester.pumpAndSettle();

    expect(_location(harness.router), '/upcoming?date=2030-01-10');
    expect(find.text('Yesterday task before Today action'), findsNothing);
    expect(find.text('Today action task'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('upcoming-calendar-day-2030-01-10')),
      findsOneWidget,
    );
  });

  testWidgets('light and dark large text layouts do not overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final task = _task(
      'large-text',
      DateTime(2030, 1, 11),
      content: 'Prepare the detailed launch readiness review',
      projectId: 'work',
    );

    for (final themeMode in [ThemeMode.light, ThemeMode.dark]) {
      await _pumpUpcoming(
        tester,
        today: today,
        tasks: [task],
        projects: [_project('work', 'Product operations')],
        themeMode: themeMode,
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('calendar uses Upcoming controls and exact task counts', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pumpUpcoming(
      tester,
      today: today,
      tasks: [_task('tomorrow', DateTime(2030, 1, 11))],
    );

    expect(find.byTooltip('Previous period'), findsOneWidget);
    expect(find.byTooltip('Next period'), findsOneWidget);
    expect(find.byTooltip('Open date picker'), findsOneWidget);

    final oneTask = tester.getSemantics(
      find.byKey(const ValueKey('upcoming-calendar-day-2030-01-11')),
    );
    final noTasks = tester.getSemantics(
      find.byKey(const ValueKey('upcoming-calendar-day-2030-01-12')),
    );
    expect(oneTask.label, contains('1 task'));
    expect(oneTask.label, isNot(contains('Added')));
    expect(noTasks.label, contains('No tasks'));
    semantics.dispose();
  });

  testWidgets('calendar counts today and completed tasks from both streams', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final future = _task('tomorrow', DateTime(2030, 1, 11));
    final todayOpen = _task(
      'today-only',
      DateTime(2030, 1, 10),
      content: 'Today open task',
    );
    final todayCompleted = _task(
      'today-completed',
      DateTime(2030, 1, 10),
      content: 'Today completed task',
      status: 'completed',
    );
    await _pumpUpcoming(
      tester,
      today: today,
      tasks: [future],
      allTasks: [future, todayOpen],
      completedTasks: [todayCompleted],
    );

    final todaySemantics = tester.getSemantics(
      find.byKey(const ValueKey('upcoming-calendar-day-2030-01-10')),
    );
    final tomorrowSemantics = tester.getSemantics(
      find.byKey(const ValueKey('upcoming-calendar-day-2030-01-11')),
    );
    expect(todaySemantics.label, contains('2 tasks'));
    expect(tomorrowSemantics.label, contains('1 task'));
    expect(find.text('Tomorrow task'), findsOneWidget);
    expect(find.text('Today open task'), findsOneWidget);
    expect(find.text('Today completed task'), findsOneWidget);
    semantics.dispose();
  });
}

Future<_Harness> _pumpUpcoming(
  WidgetTester tester, {
  required DateTime today,
  required List<TaskItem> tasks,
  ValueChanged<TaskQuery>? onQuery,
  String initialLocation = '/upcoming',
  Stream<List<TaskItem>>? allStream,
  Stream<List<TaskItem>>? completedStream,
  List<TaskItem>? allTasks,
  List<TaskItem> completedTasks = const <TaskItem>[],
  List<ProjectItem> projects = const <ProjectItem>[],
  bool settle = true,
  ThemeMode themeMode = ThemeMode.light,
  double textScale = 1,
  Locale locale = const Locale('en'),
}) async {
  final taskRepository = _FakeTaskRepository();
  final projectRepository = _FakeProjectRepository();
  final quickAddService = QuickAddService(
    parser: const QuickAddParser(),
    taskRepository: taskRepository,
    projectRepository: projectRepository,
  );
  late final GoRouter router;
  router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/upcoming',
        builder: (context, state) => Scaffold(
          body: UpcomingScreen(
            selectedDate: DateTime.tryParse(
              state.uri.queryParameters['date'] ?? '',
            ),
          ),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        clockProvider.overrideWithValue(FixedClock(today)),
        taskRepositoryProvider.overrideWithValue(taskRepository),
        projectRepositoryProvider.overrideWithValue(projectRepository),
        quickAddServiceProvider.overrideWithValue(quickAddService),
        focusRepositoryProvider.overrideWithValue(_FakeFocusRepository()),
        focusPresetsProvider.overrideWith(
          (ref) => Stream.value(const <FocusPresetItem>[]),
        ),
        projectsProvider.overrideWith((ref) => Stream.value(projects)),
        labelsProvider.overrideWith((ref) => Stream.value(const <LabelItem>[])),
        quickAddHintTextProvider.overrideWithValue(null),
        tasksByQueryProvider.overrideWith((ref, query) {
          onQuery?.call(query);
          return switch (query.kind) {
            TaskQueryKind.all => allStream ?? Stream.value(allTasks ?? tasks),
            TaskQueryKind.completed =>
              completedStream ?? Stream.value(completedTasks),
            _ => Stream.value(
              tasks
                  .where((task) => task.schedule?.displayDate == query.date)
                  .toList(),
            ),
          };
        }),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: themeMode,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            alwaysUse24HourFormat: true,
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
  return _Harness(router, taskRepository);
}

TaskItem _task(
  String id,
  DateTime date, {
  String? content,
  String projectId = 'inbox',
  String? parentId,
  String status = 'open',
  TaskSchedule? schedule,
  bool scheduled = true,
  bool isDeleted = false,
}) {
  final now = DateTime.utc(2030);
  return TaskItem(
    id: id,
    userId: 'user',
    content: content ?? (id == 'tomorrow' ? 'Tomorrow task' : 'Later task'),
    projectId: projectId,
    parentId: parentId,
    priority: 4,
    dueJson: scheduled
        ? (schedule ?? TaskSchedule.allDay(date)).toJsonString()
        : null,
    status: status,
    completedFocusIntervals: 0,
    totalFocusSeconds: 0,
    orderKey: id,
    isDeleted: isDeleted,
    createdAt: now,
    updatedAt: now,
  );
}

ProjectItem _project(String id, String name, {String? color}) {
  final now = DateTime.utc(2030);
  return ProjectItem(
    id: id,
    userId: 'user',
    name: name,
    color: color,
    orderKey: id,
    createdAt: now,
    updatedAt: now,
  );
}

String _location(GoRouter router) =>
    router.routeInformationProvider.value.uri.toString();

DateTime? _createdDate(CreateTaskInput input) =>
    input.schedule?.displayDate ?? input.dueDate;

double _verticalOffset(WidgetTester tester) {
  return tester
      .stateList<ScrollableState>(find.byType(Scrollable))
      .firstWhere((state) => state.position.axisDirection == AxisDirection.down)
      .position
      .pixels;
}

bool _isVisible(WidgetTester tester, Finder finder) {
  final rect = tester.getRect(finder);
  final height = tester.view.physicalSize.height / tester.view.devicePixelRatio;
  return rect.bottom > 0 && rect.top < height;
}

class _Harness {
  const _Harness(this.router, this.taskRepository);

  final GoRouter router;
  final _FakeTaskRepository taskRepository;
}

class _FakeTaskRepository implements TaskRepository {
  final List<CreateTaskInput> created = <CreateTaskInput>[];

  @override
  Future<String> createTask(CreateTaskInput input) async {
    created.add(input);
    return 'created-${created.length}';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _FakeProjectRepository implements ProjectRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _FakeFocusRepository implements FocusRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}
