import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/providers.dart';
import 'package:pomodoist/app/theme/app_theme.dart';
import 'package:pomodoist/core/time/clock.dart';
import 'package:pomodoist/features/productivity/domain/achievement_models.dart';
import 'package:pomodoist/features/productivity/domain/productivity_models.dart';
import 'package:pomodoist/features/productivity/presentation/reports_screen.dart';
import 'package:pomodoist/l10n/app_localizations.dart';

void main() {
  testWidgets('reports tell the progress story in priority order on desktop', (
    tester,
  ) async {
    await _pumpReports(
      tester,
      const Size(1440, 1024),
      summary: _summary(
        completedTasks: 3,
        completedFocusIntervals: 4,
        totalFocusSeconds: 6000,
        plannedFocusIntervals: 5,
        openTasks: 12,
      ),
    );

    expect(find.text('Saturday, July 11, 2026'), findsOneWidget);
    expect(find.text('A focused day so far'), findsOneWidget);
    expect(find.text('1h 40m'), findsWidgets);
    final focusValue = tester.widget<Text>(find.text('1h 40m'));
    expect(focusValue.style?.fontSize, greaterThanOrEqualTo(52));
    expect(find.byKey(const Key('reports-today-story')), findsOneWidget);
    expect(find.byKey(const Key('reports-weekly-story')), findsOneWidget);
    expect(find.byKey(const Key('reports-next-achievement')), findsOneWidget);
    expect(find.byKey(const Key('reports-achievements-card')), findsNothing);
    expect(find.byKey(const Key('reports-focus-achievements')), findsNothing);
    final completedTasksIcon = tester.widget<Icon>(
      find.byKey(const Key('reports-completed-tasks-icon')),
    );
    final completedTasksContext = tester.element(
      find.byKey(const Key('reports-completed-tasks-icon')),
    );
    expect(completedTasksIcon.color, completedTasksContext.appColors.info);

    final todayY = tester
        .getTopLeft(find.byKey(const Key('reports-today-story')))
        .dy;
    final weekY = tester
        .getTopLeft(find.byKey(const Key('reports-weekly-story')))
        .dy;
    final achievementY = tester
        .getTopLeft(find.byKey(const Key('reports-next-achievement')))
        .dy;
    expect(todayY, lessThan(weekY));
    expect(weekY, lessThan(achievementY));
    expect(
      tester.getSize(find.byKey(const Key('reports-content'))).width,
      lessThanOrEqualTo(1160),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('reports show the closest locked achievement only', (
    tester,
  ) async {
    await _pumpReports(
      tester,
      const Size(390, 844),
      achievements: const [
        _AchievementFixture(
          id: 'warm_up',
          title: 'Warm-up',
          progress: 2,
          target: 5,
        ),
        _AchievementFixture(
          id: 'focus_caught',
          title: 'Focus caught',
          progress: 8,
          target: 10,
        ),
        _AchievementFixture(
          id: 'unlocked',
          title: 'Already unlocked',
          progress: 1,
          target: 1,
        ),
      ].map((fixture) => fixture.item).toList(),
    );

    expect(find.text('Focus caught'), findsOneWidget);
    expect(find.text('Warm-up'), findsNothing);
    expect(find.text('Already unlocked'), findsNothing);
    expect(find.text('8/10'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closest achievement keeps source order when ratios tie', (
    tester,
  ) async {
    await _pumpReports(
      tester,
      const Size(390, 844),
      achievements: const [
        _AchievementFixture(
          id: 'first',
          title: 'First tie',
          progress: 2,
          target: 4,
        ),
        _AchievementFixture(
          id: 'second',
          title: 'Second tie',
          progress: 1,
          target: 2,
        ),
      ].map((fixture) => fixture.item).toList(),
    );

    expect(find.text('First tie'), findsOneWidget);
    expect(find.text('Second tie'), findsNothing);
  });

  testWidgets('empty achievements never claim everything is unlocked', (
    tester,
  ) async {
    await _pumpReports(tester, const Size(390, 844), achievements: const []);

    expect(find.text('No achievements yet'), findsOneWidget);
    expect(find.text('All achievements unlocked'), findsNothing);
  });

  testWidgets('zero planned intervals never render a zero denominator', (
    tester,
  ) async {
    await _pumpReports(
      tester,
      const Size(390, 844),
      summary: _summary(completedFocusIntervals: 2, plannedFocusIntervals: 0),
    );

    final value = find.descendant(
      of: find.byKey(const Key('reports-interval-progress-value')),
      matching: find.text('2'),
    );
    expect(value, findsOneWidget);
    expect(find.text('2/0'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reports keep the empty week and totals visible', (tester) async {
    await _pumpReports(
      tester,
      const Size(390, 844),
      summary: _summary(lastSevenDays: _weeklyDays(empty: true)),
    );

    expect(find.text('No focus or task data yet'), findsOneWidget);
    expect(find.byKey(const Key('reports-weekly-totals')), findsOneWidget);
    expect(find.text('0m'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reports stay usable on narrow iPhone', (tester) async {
    await _pumpReports(tester, const Size(320, 568));

    expect(find.text('A focused day so far'), findsOneWidget);
    expect(find.byKey(const Key('reports-today-story')), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('reports-next-achievement')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('reports-content'))).width,
      closeTo(280, 0.1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile weekly totals keep long focus time readable', (
    tester,
  ) async {
    final days = _weeklyDays();
    await _pumpReports(
      tester,
      const Size(390, 844),
      summary: _summary(
        lastSevenDays: [
          ProductivityDaySummary(
            localDate: days.first.localDate,
            completedTasks: 7,
            completedFocusIntervals: 8,
            totalFocusSeconds: 45180,
          ),
          ...days
              .skip(1)
              .map(
                (day) => ProductivityDaySummary(
                  localDate: day.localDate,
                  completedTasks: 0,
                  completedFocusIntervals: 0,
                  totalFocusSeconds: 0,
                ),
              ),
        ],
      ),
    );

    final total = find.text('12h 33m');
    expect(total, findsOneWidget);
    final paragraph = tester.renderObject<RenderParagraph>(total);
    expect(paragraph.didExceedMaxLines, isFalse);
  });

  testWidgets('over-target intervals keep the actual value and cap safely', (
    tester,
  ) async {
    await _pumpReports(
      tester,
      const Size(390, 844),
      summary: _summary(completedFocusIntervals: 6, plannedFocusIntervals: 5),
    );

    expect(find.text('6/5'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reports show a completed state when every achievement is open', (
    tester,
  ) async {
    await _pumpReports(
      tester,
      const Size(390, 844),
      achievements: const [
        _AchievementFixture(id: 'done', title: 'Done', progress: 1, target: 1),
      ].map((fixture) => fixture.item).toList(),
    );

    expect(find.text('All achievements unlocked'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reports localize the story in Russian', (tester) async {
    await _pumpReports(
      tester,
      const Size(390, 844),
      locale: const Locale('ru'),
    );

    expect(find.text('Сфокусированный день'), findsOneWidget);
    expect(find.text('Неделя в фокусе'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reports keep the story usable in narrow RTL layout', (
    tester,
  ) async {
    await _pumpReports(
      tester,
      const Size(320, 568),
      locale: const Locale('ar'),
    );

    final story = find.byKey(const Key('reports-today-story'));
    expect(Directionality.of(tester.element(story)), TextDirection.rtl);
    expect(find.text('يوم مليء بالتركيز حتى الآن'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reports-next-achievement')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('weekly chart repaints labels when an LTR locale changes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    final locale = ValueNotifier(const Locale('en'));
    addTearDown(() {
      locale.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clockProvider.overrideWithValue(
            FixedClock(DateTime.utc(2026, 7, 11, 10)),
          ),
          productivitySummaryProvider.overrideWith(
            (ref) => Stream.value(_summary()),
          ),
          achievementsProvider.overrideWith(
            (ref) => Stream.value(_achievements),
          ),
        ],
        child: ValueListenableBuilder<Locale>(
          valueListenable: locale,
          builder: (context, value, child) => MaterialApp(
            theme: AppTheme.light(),
            locale: value,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: const ReportsScreen(),
          ),
        ),
      ),
    );
    await tester.pump();
    final chartFinder = find.descendant(
      of: find.byKey(const Key('reports-weekly-chart')),
      matching: find.byType(CustomPaint),
    );
    final oldPainter = tester.widget<CustomPaint>(chartFinder).painter!;

    locale.value = const Locale('ru');
    await tester.pump();
    final newPainter = tester.widget<CustomPaint>(chartFinder).painter!;

    expect(newPainter.shouldRepaint(oldPainter), isTrue);
  });
}

Future<void> _pumpReports(
  WidgetTester tester,
  Size size, {
  ProductivitySummary? summary,
  List<AchievementItem> achievements = _achievements,
  Locale? locale,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        clockProvider.overrideWithValue(
          FixedClock(DateTime.utc(2026, 7, 11, 10)),
        ),
        productivitySummaryProvider.overrideWith(
          (ref) => Stream.value(summary ?? _summary()),
        ),
        achievementsProvider.overrideWith((ref) => Stream.value(achievements)),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: locale,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ReportsScreen(),
      ),
    ),
  );
  await tester.pump();
}

ProductivitySummary _summary({
  int completedTasks = 1,
  int completedFocusIntervals = 2,
  int totalFocusSeconds = 1800,
  int plannedFocusIntervals = 4,
  int openTasks = 5,
  List<ProductivityDaySummary>? lastSevenDays,
}) {
  return ProductivitySummary(
    completedTasks: completedTasks,
    completedFocusIntervals: completedFocusIntervals,
    totalFocusSeconds: totalFocusSeconds,
    plannedFocusIntervals: plannedFocusIntervals,
    openTasks: openTasks,
    allTimeCompletedTasks: 13,
    allTimeCompletedFocusIntervals: 21,
    lastSevenDays: lastSevenDays ?? _weeklyDays(),
  );
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

List<ProductivityDaySummary> _weeklyDays({bool empty = false}) {
  final start = DateTime(2026, 7, 6);
  return [
    for (var index = 0; index < 7; index++)
      ProductivityDaySummary(
        localDate: start.add(Duration(days: index)),
        completedTasks: empty ? 0 : (index.isEven ? 1 : 0),
        completedFocusIntervals: empty ? 0 : index + 1,
        totalFocusSeconds: empty ? 0 : (index + 1) * 900,
      ),
  ];
}

class _AchievementFixture {
  const _AchievementFixture({
    required this.id,
    required this.title,
    required this.progress,
    required this.target,
  });

  final String id;
  final String title;
  final int progress;
  final int target;

  AchievementItem get item => AchievementItem(
    id: id,
    group: AchievementGroup.focus,
    presentation: AchievementPresentation.globalBanner,
    titleRu: title,
    titleEn: title,
    subtitleRu: 'Complete $target work focuses',
    subtitleEn: 'Complete $target work focuses',
    progress: progress,
    target: target,
  );
}
