import 'package:pomodoist/data/repositories/tasks/task_repository.dart';
import 'package:pomodoist/data/repositories/focus/focus_repository.dart';
import 'support/test_app.dart';
import 'dart:async';
import 'package:go_router/go_router.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/config/calendar_dependencies.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/utils/clock.dart';
import 'package:pomodoist/domain/models/focus/focus_models.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/ui/tasks/widgets/task_detail_screen.dart';
import 'package:pomodoist/ui/core/localization/app_localizations.dart';

void main() {
  setUpAll(loadTestAppResources);
  testWidgets('detail schedule colors its timed label and exposes status', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final now = DateTime.utc(2026, 7, 10, 10);
    final task = TaskItem(
      id: 'detail',
      userId: 'user',
      content: 'Review task time',
      projectId: 'project',
      priority: 1,
      dueJson: TaskSchedule.timed(
        start: now,
        end: now.add(const Duration(minutes: 30)),
      ).toJsonString(),
      status: 'open',
      completedFocusIntervals: 0,
      totalFocusSeconds: 0,
      orderKey: '1',
      isDeleted: false,
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          projectsProvider.overrideWith((ref) => Stream.value([])),
          taskProvider(task.id).overrideWith((ref) => Stream.value(task)),
          calendarLinksProvider.overrideWith((ref, id) => Stream.value([])),
          googleCalendarLinkProvider(
            task.id,
          ).overrideWith((ref) => Stream.value(null)),
          taskRepositoryProvider.overrideWithValue(_TaskRepository()),
          focusRepositoryProvider.overrideWithValue(_FocusRepository()),
          focusPresetsProvider.overrideWith(
            (ref) => Stream.value(const <FocusPresetItem>[]),
          ),
          activeFocusRunProvider.overrideWith((ref) => Stream.value(null)),
          clockProvider.overrideWithValue(FixedClock(now)),
          taskTimeTickerProvider.overrideWith((ref) => Stream.value(now)),
        ],
        child: MaterialApp.router(
          builder: testAppBuilder,
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: GoRouter(
            routes: [
              GoRoute(
                path: '/',
                builder: (_, _) =>
                    const Scaffold(body: TaskDetailScreen(taskId: 'detail')),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    final schedule = find.byKey(const Key('task-detail-schedule-chip'));
    final label = find.descendant(of: schedule, matching: find.byType(Text));
    expect(
      tester.widget<Text>(label).style?.color,
      AppTheme.light().extension<AppThemePalette>()!.warning,
    );
    expect(
      tester
          .getSemantics(
            find.descendant(
              of: schedule,
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Semantics && widget.properties.label != null,
              ),
            ),
          )
          .label,
      contains('In progress'),
    );
    semantics.dispose();
  });
}

class _TaskRepository implements TaskRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FocusRepository implements FocusRepository {
  @override
  Stream<List<FocusIntervalItem>> watchIntervalsForTask(String taskId) {
    return Stream.value(const []);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
