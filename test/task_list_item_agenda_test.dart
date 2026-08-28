import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/providers.dart';
import 'package:pomodoist/app/theme/app_theme.dart';
import 'package:pomodoist/core/time/clock.dart';
import 'package:pomodoist/features/focus/domain/focus_models.dart';
import 'package:pomodoist/features/tasks/domain/task_models.dart';
import 'package:pomodoist/features/tasks/presentation/widgets/task_list_item.dart';
import 'package:pomodoist/l10n/app_localizations.dart';

void main() {
  testWidgets('agenda row shows project color and within-day time', (
    tester,
  ) async {
    final task = _task(
      schedule: TaskSchedule.timed(
        start: DateTime(2026, 7, 10, 14),
        end: DateTime(2026, 7, 10, 14, 30),
      ),
      description: 'Agenda rows stay compact',
    );
    final project = _project(color: '#3B82F6');

    await _pumpRow(
      tester,
      task: task,
      project: project,
      presentation: TaskListItemPresentation.agenda,
      size: const Size(1000, 240),
    );

    expect(find.text('Work'), findsOneWidget);
    expect(find.text('14:00'), findsOneWidget);
    expect(find.text('Agenda rows stay compact'), findsNothing);
    expect(
      tester.getTopLeft(find.text('Work')).dx,
      lessThan(tester.getTopLeft(find.text('14:00')).dx),
    );

    expect(find.text('#'), findsOneWidget);
    final colorMarker = tester.widget<Text>(
      find.byKey(const Key('agenda-project-color')),
    );
    expect(colorMarker.style?.color, const Color(0xFF3B82F6));
    expect(
      tester.widget<Text>(find.text('Work')).style?.color,
      colorMarker.style?.color,
    );
  });

  testWidgets('agenda row does not duplicate a plain all-day date', (
    tester,
  ) async {
    await _pumpRow(
      tester,
      task: _task(schedule: TaskSchedule.allDay(DateTime(2026, 7, 10))),
      project: _project(),
      presentation: TaskListItemPresentation.agenda,
      size: const Size(1000, 240),
    );

    expect(find.text('Work'), findsOneWidget);
    expect(find.byKey(const Key('agenda-schedule-label')), findsNothing);
    expect(find.textContaining('July'), findsNothing);
    expect(find.byIcon(Icons.event_outlined), findsNothing);
  });

  testWidgets('agenda actions adapt between desktop and narrow widths', (
    tester,
  ) async {
    const taskId = 'agenda-task';
    await _pumpRow(
      tester,
      task: _task(id: taskId),
      project: _project(),
      presentation: TaskListItemPresentation.agenda,
      size: const Size(1000, 240),
    );

    expect(
      find.byKey(const ValueKey('agenda-focus-slot-$taskId')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('agenda-focus-action-$taskId')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('agenda-overflow-action-$taskId')),
      findsNothing,
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(
      tester.getCenter(
        find.byKey(const ValueKey('task-list-item-row-$taskId')),
      ),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('agenda-focus-action-$taskId')),
      findsOneWidget,
    );

    await mouse.moveTo(const Offset(1100, 300));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('agenda-focus-action-$taskId')),
      findsNothing,
    );

    final focus = tester.widget<Focus>(
      find.byKey(const ValueKey('agenda-row-focus-$taskId')),
    );
    focus.focusNode!.requestFocus();
    await tester.pumpAndSettle();
    expect(focus.focusNode!.hasFocus, isTrue);
    expect(
      find.byKey(const ValueKey('agenda-focus-action-$taskId')),
      findsOneWidget,
    );

    await tester.binding.setSurfaceSize(const Size(600, 240));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('agenda-focus-slot-$taskId')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('agenda-focus-action-$taskId')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('agenda-overflow-action-$taskId')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(
      find.byKey(const ValueKey('agenda-overflow-action-$taskId')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Start focus'), findsOneWidget);
    await mouse.removePointer();
  });

  testWidgets('standard presentation remains the default', (tester) async {
    await _pumpRow(
      tester,
      task: _task(
        schedule: TaskSchedule.allDay(DateTime(2026, 7, 10)),
        description: 'Standard description',
      ),
      project: _project(),
      size: const Size(1000, 240),
    );

    expect(find.text('Standard description'), findsOneWidget);
    expect(find.byIcon(Icons.event_outlined), findsOneWidget);
    expect(find.byTooltip('Start focus'), findsOneWidget);
    expect(find.byKey(const Key('agenda-project-label')), findsNothing);
    expect(find.byKey(const Key('agenda-schedule-label')), findsNothing);
    expect(
      find.byKey(const ValueKey('agenda-overflow-action-task')),
      findsNothing,
    );
  });

  testWidgets('timed rows color states and expose semantic status', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final schedule = TaskSchedule.timed(
      start: DateTime.utc(2026, 7, 10, 10),
      end: DateTime.utc(2026, 7, 10, 10, 30),
    );
    final cases = [
      (
        id: 'future',
        now: DateTime.utc(2026, 7, 10, 9, 59),
        expectedColor: AppTheme.light().extension<AppThemePalette>()!.info,
        expectedStatus: 'Upcoming',
        activeFocusTaskId: null,
        presentation: TaskListItemPresentation.standard,
      ),
      (
        id: 'current',
        now: DateTime.utc(2026, 7, 10, 10),
        expectedColor: AppTheme.light().extension<AppThemePalette>()!.warning,
        expectedStatus: 'In progress',
        activeFocusTaskId: null,
        presentation: TaskListItemPresentation.standard,
      ),
      (
        id: 'overdue',
        now: DateTime.utc(2026, 7, 10, 10, 30),
        expectedColor: AppTheme.light().extension<AppThemePalette>()!.accent,
        expectedStatus: 'Overdue',
        activeFocusTaskId: null,
        presentation: TaskListItemPresentation.standard,
      ),
      (
        id: 'completed',
        now: DateTime.utc(2026, 7, 10, 9, 59),
        expectedColor: AppTheme.light().extension<AppThemePalette>()!.mutedText,
        expectedStatus: 'Completed',
        activeFocusTaskId: null,
        presentation: TaskListItemPresentation.standard,
      ),
    ];

    for (final item in cases) {
      await _pumpRow(
        tester,
        task: _task(
          id: item.id,
          schedule: schedule,
          completed: item.id == 'completed',
        ),
        project: _project(),
        presentation: item.presentation,
        size: const Size(1000, 240),
        now: item.now,
        activeFocusTaskId: item.activeFocusTaskId,
      );

      final label = find.byKey(ValueKey('task-time-label-${item.id}'));
      expect(tester.widget<Text>(label).style?.color, item.expectedColor);
      expect(
        tester
            .getSemantics(find.byKey(ValueKey('task-time-meta-${item.id}')))
            .label,
        contains(item.expectedStatus),
      );
    }
    semantics.dispose();
  });

  testWidgets('timed row refreshes at the schedule boundary', (tester) async {
    final ticker = StreamController<DateTime>.broadcast();
    addTearDown(ticker.close);
    final schedule = TaskSchedule.timed(
      start: DateTime.utc(2026, 7, 10, 10),
      end: DateTime.utc(2026, 7, 10, 10, 30),
    );
    await _pumpRow(
      tester,
      task: _task(id: 'boundary', schedule: schedule),
      project: _project(),
      size: const Size(1000, 240),
      now: DateTime.utc(2026, 7, 10, 9, 59),
      ticker: ticker.stream,
    );

    ticker.add(DateTime.utc(2026, 7, 10, 9, 59));
    await tester.pump();
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('task-time-label-boundary')))
          .style
          ?.color,
      AppTheme.light().extension<AppThemePalette>()!.info,
    );

    ticker.add(DateTime.utc(2026, 7, 10, 10));
    await tester.pump();
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('task-time-label-boundary')))
          .style
          ?.color,
      AppTheme.light().extension<AppThemePalette>()!.warning,
    );
  });
}

Future<void> _pumpRow(
  WidgetTester tester, {
  required TaskItem task,
  required ProjectItem project,
  required Size size,
  TaskListItemPresentation presentation = TaskListItemPresentation.standard,
  DateTime? now,
  String? activeFocusTaskId,
  Stream<DateTime>? ticker,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      key: ValueKey('task-list-row-scope-${task.id}'),
      overrides: [
        taskRepositoryProvider.overrideWithValue(_StubTaskRepository()),
        focusRepositoryProvider.overrideWithValue(_StubFocusRepository()),
        focusPresetsProvider.overrideWith(
          (ref) => Stream.value(const <FocusPresetItem>[]),
        ),
        clockProvider.overrideWithValue(FixedClock(now ?? DateTime.utc(2026))),
        taskTimeTickerProvider.overrideWith(
          (ref) => ticker ?? Stream.value(now ?? DateTime.utc(2026)),
        ),
        activeFocusRunProvider.overrideWith(
          (ref) => Stream.value(
            activeFocusTaskId == null
                ? null
                : _activeFocusRun(activeFocusTaskId),
          ),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: const MediaQueryData(alwaysUse24HourFormat: true),
          child: Scaffold(
            body: SizedBox(
              width: double.infinity,
              child: TaskListItem(
                task: task,
                project: project,
                presentation: presentation,
                enableSubtaskDrop: false,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

TaskItem _task({
  String id = 'task',
  TaskSchedule? schedule,
  String? description,
  bool completed = false,
}) {
  final now = DateTime.utc(2026);
  return TaskItem(
    id: id,
    userId: 'user',
    content: 'Plan launch',
    description: description,
    projectId: 'work',
    priority: 4,
    dueJson: schedule?.toJsonString(),
    status: completed ? 'completed' : 'open',
    completedFocusIntervals: 0,
    totalFocusSeconds: 0,
    orderKey: id,
    isDeleted: false,
    createdAt: now,
    updatedAt: now,
  );
}

FocusRunItem _activeFocusRun(String taskId) {
  final now = DateTime.utc(2026, 7, 10, 10);
  return FocusRunItem(
    id: 'run-$taskId',
    userId: 'user',
    taskId: taskId,
    projectId: 'work',
    presetId: 'preset',
    status: 'paused',
    startedAt: now,
    targetWorkIntervals: 1,
    completedWorkIntervals: 0,
    createdAt: now,
    updatedAt: now,
  );
}

ProjectItem _project({String? color}) {
  final now = DateTime.utc(2026);
  return ProjectItem(
    id: 'work',
    userId: 'user',
    name: 'Work',
    color: color,
    orderKey: 'work',
    createdAt: now,
    updatedAt: now,
  );
}

class _StubTaskRepository implements TaskRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _StubFocusRepository implements FocusRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}
