import 'package:pomodoist/config/focus_dependencies.dart';
import 'package:pomodoist/config/account_providers.dart';
import 'package:pomodoist/config/productivity_dependencies.dart';
import 'package:pomodoist/domain/models/calendar/calendar_models.dart';
import 'package:pomodoist/utils/result.dart';
import 'package:pomodoist/data/repositories/tasks/task_repository.dart';
import 'package:pomodoist/data/repositories/focus/focus_repository.dart';
import 'package:pomodoist/data/repositories/achievements/achievement_repository.dart';
import 'package:go_router/go_router.dart';
import 'support/test_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/core/widgets/adaptive_shell.dart';
import 'package:pomodoist/ui/onboarding/view_models/learning_tour_view_model.dart';
import 'package:pomodoist/ui/core/widgets/task_details_host.dart';
import 'package:pomodoist/domain/models/focus/focus_models.dart';
import 'package:pomodoist/domain/models/productivity/productivity_models.dart';
import 'package:pomodoist/ui/planning/widgets/today_screen.dart';
import 'package:pomodoist/ui/core/widgets/mini_focus_player.dart';
import 'package:pomodoist/data/repositories/calendar/google_calendar_repository.dart';
import 'package:pomodoist/domain/models/productivity/achievement_models.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/ui/tasks/widgets/inbox_screen.dart';
import 'package:pomodoist/ui/tasks/widgets/quick_add_bar.dart';
import 'package:pomodoist/ui/tasks/widgets/task_list_item.dart';
import 'package:pomodoist/utils/clock.dart';
import 'package:pomodoist/ui/tasks/widgets/task_detail_screen.dart';
import 'package:pomodoist/ui/core/localization/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(loadTestAppResources);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  for (final width in [390.0, 819.0, 820.0]) {
    testWidgets('Today switches layout at 820 px on mobile ($width)', (
      tester,
    ) async {
      await _pumpShell(
        tester,
        size: Size(width, 850),
        initialLocation: '/today',
      );
      final context = tester.element(find.byType(TodayScreen));
      final l10n = AppLocalizations.of(context);
      final summary = find.text(l10n.todayTaskSummary(0, 2, '0m'));
      final options = find.byKey(const Key('today-options'));
      final quickAdd = find.byKey(const Key('compact-add-task'));
      final shellTitle = find.byKey(const Key('shell-page-title'));
      if (width >= 820) {
        expect(shellTitle, findsNothing);
        expect(options, findsNothing);
        expect(summary, findsOneWidget);
        expect(quickAdd, findsNothing);
        expect(find.byType(QuickAddBar), findsOneWidget);
        return;
      }
      expect(tester.widget<Text>(shellTitle).data, l10n.navToday);
      expect(
        find.descendant(
          of: find.byType(TodayScreen),
          matching: find.text(l10n.navToday),
        ),
        findsNothing,
      );
      expect(tester.getCenter(shellTitle).dx, width / 2);
      expect(tester.getCenter(options).dx, greaterThan(width / 2));
      expect(find.byType(EditableText), findsNothing);
      expect(summary, findsNothing);
      expect(quickAdd, findsOneWidget);
      expect(_miniPlayerSurface, findsOneWidget);
      await tester.tap(options);
      await _pumpShellFrame(tester);
      expect(summary, findsOneWidget);
      expect(
        find.byKey(const ValueKey('task-priority-cascade')),
        findsOneWidget,
      );
      Navigator.of(tester.element(summary)).pop();
      await _pumpShellFrame(tester);
      if (width == 390) {
        await tester.tap(quickAdd);
      } else {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      }
      await _pumpShellFrame(tester);
      expect(
        tester
            .widget<QuickAddComposer>(find.byType(QuickAddComposer))
            .defaultDate,
        DateUtils.dateOnly(_shellNow.toLocal()),
      );
    }, variant: TargetPlatformVariant({TargetPlatform.iOS}));
  }

  testWidgets(
    'compact Today keeps deadlines and branches in open and completed rows',
    (tester) async {
      final day = DateUtils.dateOnly(_shellNow.toLocal());
      final childTitle = List.filled(8, 'A long subtask title').join(' ');
      final tasks = [
        _task(id: 'parent', schedule: TaskSchedule.allDay(day)),
        _task(
          id: 'subtask',
          title: childTitle,
          parentId: 'parent',
          schedule: TaskSchedule.allDay(day),
        ),
        _task(
          id: 'overdue',
          schedule: TaskSchedule.allDay(day.subtract(const Duration(days: 1))),
        ),
        _task(
          id: 'midnight',
          schedule: TaskSchedule.timed(
            start: day.add(const Duration(hours: 23)),
            end: day.add(const Duration(days: 1, hours: 1)),
            recurrence: const TaskRecurrence(
              interval: 1,
              unit: TaskRecurrenceUnit.day,
              seriesId: 'night',
            ),
          ),
        ),
        _task(
          id: 'done',
          schedule: TaskSchedule.allDay(day),
          completedAt: _shellNow,
        ),
      ];
      await _pumpShell(
        tester,
        size: const Size(390, 850),
        initialLocation: '/today',
        tasks: tasks,
        taskRepository: _TaskRepository(tasks.first),
      );
      final l10n = AppLocalizations.of(
        tester.element(find.byType(TodayScreen)),
      );
      Finder timing(String id) => find.byKey(ValueKey('task-time-label-$id'));
      expect(timing('parent'), findsNothing);
      expect(
        find.descendant(
          of: timing('overdue'),
          matching: find.text(l10n.taskTimeStatusOverdue),
        ),
        findsOneWidget,
      );
      expect(tester.widget<Column>(timing('midnight')).children, hasLength(3));
      expect(
        find.descendant(
          of: timing('midnight'),
          matching: find.text(l10n.recurrenceEveryDays(1)),
        ),
        findsOneWidget,
      );
      expect(find.text('Hidden description'), findsNothing);
      final branch = find.byKey(const ValueKey('task-branch-toggle-parent'));
      if (find.text(childTitle).evaluate().isEmpty) {
        await tester.tap(branch);
        await _pumpShellFrame(tester);
      }
      expect(tester.widget<Text>(find.text(childTitle)).maxLines, isNull);
      await tester.tap(branch);
      await _pumpShellFrame(tester);
      expect(find.text(childTitle), findsNothing);
      final completed = find.text(l10n.todayCompletedTasks(1));
      await tester.ensureVisible(completed);
      await tester.tap(completed);
      await _pumpShellFrame(tester);
      expect(
        tester
            .widget<TaskListItem>(find.byKey(const ValueKey('done')))
            .quietDay,
        day,
      );
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({TargetPlatform.iOS}),
  );

  testWidgets('closing compact Today details restores the scrolled list', (
    tester,
  ) async {
    final day = DateUtils.dateOnly(_shellNow.toLocal());
    final tasks = [
      for (var index = 0; index < 20; index++)
        _task(
          id: 'task-${100 + index}',
          title: 'Task ${100 + index}',
          schedule: TaskSchedule.allDay(day),
        ),
    ];
    await _pumpShell(
      tester,
      size: const Size(390, 720),
      initialLocation: '/today',
      tasks: tasks,
      taskRepository: _TaskRepository(tasks[6]),
    );
    final list = find.descendant(
      of: find.byType(TodayScreen),
      matching: find.byType(CustomScrollView),
    );
    final scrollable = find
        .descendant(of: list, matching: find.byType(Scrollable))
        .first;
    tester.state<ScrollableState>(scrollable).position.jumpTo(270);
    await _pumpShellFrame(tester);
    await tester.tap(find.text(tasks[6].content));
    await _pumpShellFrame(tester);
    final menu = find.byKey(const Key('shell-menu-button'));
    expect(find.byType(TaskDetailScreen), findsOneWidget);
    expect(menu, findsNothing);
    expect(find.byKey(const Key('shell-page-title')), findsNothing);
    expect(_miniPlayerSurface, findsNothing);
    final l10n = AppLocalizations.of(
      tester.element(find.byType(TaskDetailScreen)),
    );
    await tester.tap(find.byTooltip(l10n.commonClose).first);
    await _pumpShellFrame(tester);
    expect(find.byType(TaskDetailScreen), findsNothing);
    expect(menu, findsOneWidget);
    expect(tester.state<ScrollableState>(scrollable).position.pixels, 270);
  }, variant: TargetPlatformVariant({TargetPlatform.iOS}));

  testWidgets('compact Inbox keeps its inline composer', (tester) async {
    await _pumpShell(
      tester,
      size: const Size(390, 850),
      initialLocation: '/inbox',
      showInbox: true,
    );
    expect(find.byKey(const Key('today-options')), findsNothing);
    expect(find.byType(QuickAddBar), findsOneWidget);
    expect(find.byKey(const Key('compact-add-task')), findsOneWidget);
  }, variant: TargetPlatformVariant({TargetPlatform.iOS}));

  testWidgets(
    'opening Focus advances the guided route without starting a run',
    (tester) async {
      await _pumpShell(tester, size: const Size(1200, 900));
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AdaptiveShell)),
      );
      await container.read(learningTourProvider.future);
      final tour = container.read(learningTourProvider.notifier);
      tour.replay();
      tour.quickAddOpened();
      tour.quickAddClosed();

      await tester.tap(find.byKey(const Key('go-focus')));
      await _pumpShellFrame(tester);
      expect(
        container.read(learningTourProvider).value,
        LearningTourStep.focusReady,
      );
    },
  );

  for (final layout in const {
    'compact': Size(600, 800),
    'wide': Size(1200, 900),
  }.entries) {
    for (final status in ['ready', 'running', 'paused']) {
      testWidgets(
        'Today keeps only the bottom player when $status on ${layout.key}',
        (tester) async {
          await _pumpShell(
            tester,
            size: layout.value,
            initialLocation: '/today',
            intervalStatus: status,
          );
          expect(_miniPlayerSurface, findsOneWidget);
          expect(
            find.descendant(
              of: find.byType(TodayScreen),
              matching: find.byType(MiniFocusPlayer),
            ),
            findsNothing,
          );
          final context = tester.element(find.byType(TodayScreen));
          expect(
            find.text(
              AppLocalizations.of(context).todayTaskSummary(0, 2, '0m'),
            ),
            layout.key == 'compact' ? findsNothing : findsOneWidget,
          );
        },
        variant: TargetPlatformVariant({TargetPlatform.iOS}),
      );
    }

    testWidgets(
      'active mini player hides on Focus paths and returns on ${layout.key}',
      (tester) async {
        await _pumpShell(tester, size: layout.value);

        expect(_miniPlayerSurface, findsOneWidget);

        await tester.tap(find.byKey(const Key('go-focus')));
        await _pumpShellFrame(tester);

        expect(_miniPlayerSurface, findsNothing);

        await tester.tap(find.byKey(const Key('go-nested-focus')));
        await _pumpShellFrame(tester);

        expect(_miniPlayerSurface, findsNothing);

        await tester.tap(find.byKey(const Key('go-inbox')));
        await _pumpShellFrame(tester);

        expect(_miniPlayerSurface, findsOneWidget);
      },
    );

    for (final announcement in const [
      (
        name: 'global',
        item: _globalAchievement,
        visibleKey: Key('achievement-global-banner'),
        absentKey: Key('achievement-bottom-plaque'),
      ),
      (
        name: 'bottom',
        item: _bottomAchievement,
        visibleKey: Key('achievement-bottom-plaque'),
        absentKey: Key('achievement-global-banner'),
      ),
    ]) {
      testWidgets(
        '${announcement.name} achievement overlays ${layout.key} content without shifting it',
        (tester) async {
          await _pumpShell(tester, size: layout.value);

          final contentAnchor = find.byKey(const Key('go-inbox'));
          final baselineCenter = tester.getCenter(contentAnchor);
          final container = ProviderScope.containerOf(
            tester.element(find.byType(AdaptiveShell)),
          );

          container.read(achievementAnnouncementRepositoryProvider).enqueue([
            announcement.item,
          ]);
          await tester.pump();

          expect(find.byKey(announcement.visibleKey), findsOneWidget);
          expect(find.byKey(announcement.absentKey), findsNothing);
          expect(tester.getCenter(contentAnchor), baselineCenter);
        },
      );
    }
  }

  testWidgets(
    'compact Focus keeps bottom navigation and one pause action surface',
    (tester) async {
      await _pumpShell(
        tester,
        size: const Size(600, 800),
        initialLocation: '/focus',
      );

      expect(find.byKey(const Key('mobile-bottom-navigation')), findsOneWidget);
      expect(_miniPlayerSurface, findsNothing);
      expect(find.byTooltip('Pause'), findsOneWidget);
    },
  );

  for (final path in const ['/blocking', '/focus']) {
    testWidgets('compact $path leaves its session actions unobstructed', (
      tester,
    ) async {
      await _pumpShell(
        tester,
        size: const Size(600, 800),
        initialLocation: path,
      );

      expect(find.byKey(const Key('compact-add-task')), findsNothing);
      expect(find.byKey(const Key('mobile-bottom-navigation')), findsOneWidget);

      await tester.tap(find.byKey(const Key('go-inbox')));
      await _pumpShellFrame(tester);
      expect(find.byKey(const Key('compact-add-task')), findsOneWidget);
    });
  }

  testWidgets('compact task details replace shell chrome and fill viewport', (
    tester,
  ) async {
    await _pumpShell(
      tester,
      size: const Size(600, 800),
      initialLocation: '/inbox',
      taskId: 'task-1',
      taskRepository: _TaskRepository(_task()),
    );

    expect(find.text('Ship celebration'), findsOneWidget);
    expect(find.byKey(const Key('shell-menu-button')), findsNothing);
    expect(find.byKey(const Key('mobile-bottom-navigation')), findsNothing);
    expect(
      tester.getRect(find.byType(TaskDetailsHost)),
      const Rect.fromLTWH(0, 0, 600, 800),
    );

    await tester.tap(find.byTooltip('Close'));
    await _pumpShellFrame(tester);

    expect(find.text('Ship celebration'), findsNothing);
    expect(find.byKey(const Key('shell-menu-button')), findsOneWidget);
    expect(find.byKey(const Key('mobile-bottom-navigation')), findsOneWidget);
  });

  testWidgets('wide task details keep the 440-pixel side panel', (
    tester,
  ) async {
    await _pumpShell(
      tester,
      size: const Size(1400, 900),
      initialLocation: '/inbox',
      taskId: 'task-1',
      taskRepository: _TaskRepository(_task()),
    );

    expect(find.byKey(const Key('shell-menu-button')), findsOneWidget);
    expect(tester.getSize(find.byType(TaskDetailScreen)).width, 440);
  });

  testWidgets('completion overlays a non-Focus shell route', (tester) async {
    await _pumpShell(
      tester,
      size: const Size(600, 800),
      initialLocation: '/inbox',
    );
    final context = tester.element(find.byType(AdaptiveShell));
    ProviderScope.containerOf(context)
        .read(focusCompletionRepositoryProvider)
        .present(
          FocusRunCompletionEvent(
            runId: 'completed-run',
            completedWorkIntervals: 4,
            targetWorkIntervals: 4,
            completedAt: DateTime.utc(2026, 8, 19, 12),
          ),
        );

    await tester.pump();

    expect(find.byKey(const Key('focus-completion-overlay')), findsOneWidget);
    expect(find.byKey(const Key('go-inbox')).hitTestable(), findsNothing);
  });

  testWidgets('global completion keeps task undo feedback visible', (
    tester,
  ) async {
    final taskRepository = _TaskRepository(_task());
    await _pumpShell(
      tester,
      size: const Size(600, 800),
      initialLocation: '/inbox',
      taskRepository: taskRepository,
    );
    final context = tester.element(find.byType(AdaptiveShell));
    ProviderScope.containerOf(context)
        .read(focusCompletionRepositoryProvider)
        .present(
          FocusRunCompletionEvent(
            runId: 'linked-run',
            taskId: 'task-1',
            taskTitle: 'Ship celebration',
            completedWorkIntervals: 4,
            targetWorkIntervals: 4,
            completedAt: DateTime.utc(2026, 8, 19, 12),
          ),
        );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('focus-completion-complete-task')));
    await tester.pumpAndSettle();

    expect(taskRepository.completeCount, 1);
    expect(find.text('Task completed'), findsOneWidget);
  });
}

Finder get _miniPlayerSurface =>
    find.byKey(const Key('mini-focus-player-surface'));

final _shellNow = DateTime.utc(2026, 7, 10, 10);

Future<void> _pumpShell(
  WidgetTester tester, {
  required Size size,
  String initialLocation = '/inbox',
  String intervalStatus = 'running',
  String? taskId,
  TaskRepository? taskRepository,
  List<TaskItem> tasks = const [],
  bool showInbox = false,
}) async {
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

  final now = _shellNow;
  final router = GoRouter(
    initialLocation: taskId == null
        ? '/'
        : '/?task=${Uri.encodeQueryComponent(taskId)}',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, state) => _AdaptiveShellRouteHarness(
          initialLocation: initialLocation,
          taskId: state.uri.queryParameters['task'],
          showInbox: showInbox,
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        focusRepositoryProvider.overrideWithValue(
          _ActiveFocusRepository(now, intervalStatus: intervalStatus),
        ),
        productivitySummaryProvider.overrideWithValue(
          AsyncData(
            ProductivitySummary(
              completedTasks: 0,
              completedFocusIntervals: 0,
              totalFocusSeconds: 0,
              plannedFocusIntervals: 2,
              openTasks: 0,
              allTimeCompletedTasks: 0,
              allTimeCompletedFocusIntervals: 0,
            ),
          ),
        ),
        focusTickerProvider.overrideWith((ref) => Stream.value(now)),
        accountProfileProvider.overrideWith((ref) => null),
        clockProvider.overrideWithValue(FixedClock(now)),
        tasksByQueryProvider.overrideWith(
          (ref, query) => Stream.value(
            tasks
                .where(
                  (task) =>
                      task.isCompleted ==
                      (query.kind == TaskQueryKind.completed),
                )
                .toList(),
          ),
        ),
        projectsProvider.overrideWith((ref) => Stream.value(const [])),
        achievementRepositoryProvider.overrideWithValue(
          const _NoopAchievementRepository(),
        ),
        calendarIntegrationRepositoryProvider.overrideWithValue(
          const _NoopCalendarIntegrationRepository(),
        ),
        achievementsProvider.overrideWith(
          (ref) => Stream.value(const <AchievementItem>[]),
        ),
        if (taskRepository != null)
          taskRepositoryProvider.overrideWithValue(taskRepository),
      ],
      child: MaterialApp.router(
        builder: testAppBuilder,
        theme: AppTheme.light(),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await _pumpShellFrame(tester);
}

Future<void> _pumpShellFrame(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

class _AdaptiveShellRouteHarness extends StatefulWidget {
  const _AdaptiveShellRouteHarness({
    required this.initialLocation,
    required this.taskId,
    required this.showInbox,
  });

  final String initialLocation;
  final String? taskId;
  final bool showInbox;

  @override
  State<_AdaptiveShellRouteHarness> createState() =>
      _AdaptiveShellRouteHarnessState();
}

class _AdaptiveShellRouteHarnessState
    extends State<_AdaptiveShellRouteHarness> {
  late String _location = widget.initialLocation;

  @override
  Widget build(BuildContext context) {
    final onFocus = _location == '/focus';
    return AdaptiveShell(
      location: _location,
      taskId: widget.taskId,
      child: _location == '/today'
          ? const TodayScreen()
          : widget.showInbox
          ? const InboxScreen()
          : Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onFocus)
                    IconButton(
                      tooltip: 'Pause',
                      onPressed: () {},
                      icon: const Icon(Icons.pause),
                    ),
                  TextButton(
                    key: const Key('go-focus'),
                    onPressed: () => setState(() => _location = '/focus'),
                    child: const Text('Open Focus'),
                  ),
                  TextButton(
                    key: const Key('go-nested-focus'),
                    onPressed: () =>
                        setState(() => _location = '/focus/session'),
                    child: const Text('Open nested Focus'),
                  ),
                  TextButton(
                    key: const Key('go-inbox'),
                    onPressed: () => setState(() => _location = '/inbox'),
                    child: const Text('Open Inbox'),
                  ),
                ],
              ),
            ),
    );
  }
}

class _ActiveFocusRepository implements FocusRepository {
  _ActiveFocusRepository(this.now, {this.intervalStatus = 'running'});

  final DateTime now;
  final String intervalStatus;

  @override
  Stream<FocusRunItem?> watchActiveRun() => Stream.value(
    FocusRunItem(
      id: 'run',
      userId: 'user',
      presetId: 'preset',
      status: 'active',
      startedAt: now,
      targetWorkIntervals: 2,
      completedWorkIntervals: 0,
      createdAt: now,
      updatedAt: now,
    ),
  );

  @override
  Stream<FocusIntervalItem?> watchActiveInterval() => Stream.value(
    FocusIntervalItem(
      id: 'interval',
      runId: 'run',
      type: 'work',
      status: intervalStatus,
      plannedSeconds: 25 * 60,
      startedAt: now,
      pausedTotalSeconds: 0,
      sequenceNumber: 1,
      createdAt: now,
      updatedAt: now,
    ),
  );

  @override
  Stream<List<FocusPresetItem>> watchPresets() => Stream.value(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoopAchievementRepository implements AchievementRepository {
  const _NoopAchievementRepository();

  @override
  Stream<List<AchievementItem>> watchAchievements() => Stream.value(const []);

  @override
  Future<Result<List<AchievementItem>>> takePendingAnnouncements(
    List<AchievementItem> items,
  ) => Result.capture<List<AchievementItem>>(() async => const []);
}

class _NoopCalendarIntegrationRepository
    implements CalendarIntegrationRepository {
  const _NoopCalendarIntegrationRepository();

  @override
  Stream<GoogleCalendarConnection?> watchConnection() => Stream.value(null);

  @override
  Stream<GoogleCalendarEventLink?> watchLinkForTask(String taskId) =>
      Stream.value(null);
}

const _globalAchievement = AchievementItem(
  id: 'focus-overlay',
  group: AchievementGroup.focus,
  presentation: AchievementPresentation.globalBanner,
  progress: 1,
  target: 1,
);

const _bottomAchievement = AchievementItem(
  id: 'combo-overlay',
  group: AchievementGroup.combo,
  presentation: AchievementPresentation.bottomPlaque,
  progress: 1,
  target: 1,
);

TaskItem _task({
  String id = 'task-1',
  String title = 'Ship celebration',
  String? parentId,
  TaskSchedule? schedule,
  DateTime? completedAt,
}) {
  final now = DateTime.utc(2026, 8, 19, 12);
  return TaskItem(
    id: id,
    userId: 'local',
    content: title,
    description: 'Hidden description',
    parentId: parentId,
    dueJson: schedule?.toJsonString(),
    completedAt: completedAt,
    projectId: 'project-1',
    priority: 1,
    status: completedAt == null ? 'open' : 'completed',
    completedFocusIntervals: 4,
    totalFocusSeconds: 6000,
    orderKey: id,
    isDeleted: false,
    createdAt: now,
    updatedAt: now,
  );
}

class _TaskRepository implements TaskRepository {
  _TaskRepository(this.task);

  final TaskItem task;
  int completeCount = 0;

  @override
  Stream<TaskItem?> watchTask(String id) => Stream.value(task);

  @override
  Future<Result<void>> completeTask(String id) =>
      Result.capture<void>(() async {
        completeCount++;
      });

  @override
  Future<Result<void>> uncompleteTask(String id) =>
      Result.capture<void>(() async {});

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
