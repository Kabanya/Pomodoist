import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/providers.dart';
import 'package:pomodoist/app/theme/app_theme.dart';
import 'package:pomodoist/core/time/clock.dart';
import 'package:pomodoist/features/focus/domain/focus_models.dart';
import 'package:pomodoist/features/tasks/domain/task_models.dart';
import 'package:pomodoist/features/tasks/presentation/task_detail_screen.dart';
import 'package:pomodoist/l10n/app_localizations.dart';

void main() {
  testWidgets('detail schedule chip colors its timed label and icon', (
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
          taskProvider(task.id).overrideWith((ref) => Stream.value(task)),
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
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: TaskDetailScreen(taskId: 'detail')),
        ),
      ),
    );
    await tester.pump();

    final label = find.byKey(const Key('task-detail-time-label'));
    expect(
      tester.widget<Text>(label).style?.color,
      AppTheme.light().extension<AppThemePalette>()!.warning,
    );
    expect(
      tester.widget<Icon>(find.byKey(const Key('task-detail-time-icon'))).color,
      AppTheme.light().extension<AppThemePalette>()!.warning,
    );
    expect(
      tester.getSemantics(find.byKey(const Key('task-detail-time-meta'))).label,
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
