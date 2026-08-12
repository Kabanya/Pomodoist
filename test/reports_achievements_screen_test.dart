import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pomodoist/app/providers.dart';
import 'package:pomodoist/app/theme/app_theme.dart';
import 'package:pomodoist/core/time/clock.dart';
import 'package:pomodoist/features/productivity/domain/achievement_models.dart';
import 'package:pomodoist/features/productivity/domain/productivity_models.dart';
import 'package:pomodoist/features/productivity/presentation/achievements_screen.dart';
import 'package:pomodoist/features/productivity/presentation/reports_screen.dart';

void main() {
  testWidgets('catalog keeps focus task and combo groups', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pumpCatalog(tester, achievements: _achievements);

    expect(find.byKey(const Key('achievements-catalog')), findsOneWidget);
    expect(find.byKey(const Key('reports-focus-achievements')), findsOneWidget);
    expect(find.byKey(const Key('reports-task-achievements')), findsOneWidget);
    expect(find.byKey(const Key('reports-combo-achievements')), findsOneWidget);
    expect(find.text('First tomato'), findsOneWidget);
    expect(find.text('The list flinched'), findsOneWidget);
    expect(find.text('Day not wasted'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('Complete 1 work focus')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('view all opens catalog and back returns to reports', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final router = GoRouter(
      initialLocation: '/reports',
      routes: [
        GoRoute(
          path: '/reports',
          builder: (context, state) => const ReportsScreen(),
        ),
        GoRoute(
          path: '/reports/achievements',
          builder: (context, state) => const AchievementsScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clockProvider.overrideWithValue(
            FixedClock(DateTime.utc(2026, 7, 11, 10)),
          ),
          productivitySummaryProvider.overrideWith(
            (ref) => Stream.value(
              ProductivitySummary(
                completedTasks: 3,
                completedFocusIntervals: 4,
                totalFocusSeconds: 6000,
                plannedFocusIntervals: 5,
                openTasks: 12,
                allTimeCompletedTasks: 13,
                allTimeCompletedFocusIntervals: 21,
                lastSevenDays: _weeklyDays(),
              ),
            ),
          ),
          achievementsProvider.overrideWith(
            (ref) => Stream.value(_achievements),
          ),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('View all 3'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View all 3'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('achievements-catalog')), findsOneWidget);

    await tester.tap(find.byTooltip('Back to reports'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reports-today-story')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('catalog reports provider failures without losing its header', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          achievementsProvider.overrideWith(
            (ref) => Stream<List<AchievementItem>>.error('failure'),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const AchievementsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Achievements'), findsOneWidget);
    expect(find.textContaining('failure'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpCatalog(
  WidgetTester tester, {
  required List<AchievementItem> achievements,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        achievementsProvider.overrideWith((ref) => Stream.value(achievements)),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const AchievementsScreen(),
      ),
    ),
  );
  await tester.pump();
}

const _achievements = [
  AchievementItem(
    id: 'focus_1',
    group: AchievementGroup.focus,
    presentation: AchievementPresentation.globalBanner,
    titleRu: 'Первый помидор',
    titleEn: 'First tomato',
    subtitleRu: 'Завершить 1 work-фокус',
    subtitleEn: 'Complete 1 work focus',
    progress: 1,
    target: 1,
  ),
  AchievementItem(
    id: 'task_5',
    group: AchievementGroup.task,
    presentation: AchievementPresentation.globalBanner,
    titleRu: 'Список дрогнул',
    titleEn: 'The list flinched',
    subtitleRu: 'Закрыть 5 задач',
    subtitleEn: 'Complete 5 tasks',
    progress: 2,
    target: 5,
  ),
  AchievementItem(
    id: 'combo_day_not_wasted',
    group: AchievementGroup.combo,
    presentation: AchievementPresentation.bottomPlaque,
    titleRu: 'День не зря',
    titleEn: 'Day not wasted',
    subtitleRu: 'За день есть фокус и закрытая задача',
    subtitleEn: 'Finish a focus and a task in one day',
    progress: 1,
    target: 1,
  ),
];

List<ProductivityDaySummary> _weeklyDays() {
  final start = DateTime(2026, 7, 6);
  return [
    for (var index = 0; index < 7; index++)
      ProductivityDaySummary(
        localDate: start.add(Duration(days: index)),
        completedTasks: index.isEven ? 1 : 0,
        completedFocusIntervals: index + 1,
        totalFocusSeconds: (index + 1) * 900,
      ),
  ];
}
