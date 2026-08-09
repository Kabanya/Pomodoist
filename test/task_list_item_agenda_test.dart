import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/providers.dart';
import 'package:pomodoist/app/theme/app_theme.dart';
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

    await mouse.moveTo(const Offset(999, 239));
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
}

Future<void> _pumpRow(
  WidgetTester tester, {
  required TaskItem task,
  required ProjectItem project,
  required Size size,
  TaskListItemPresentation presentation = TaskListItemPresentation.standard,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        taskRepositoryProvider.overrideWithValue(_StubTaskRepository()),
        focusRepositoryProvider.overrideWithValue(_StubFocusRepository()),
        focusPresetsProvider.overrideWith(
          (ref) => Stream.value(const <FocusPresetItem>[]),
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
  await tester.pump();
}

TaskItem _task({
  String id = 'task',
  TaskSchedule? schedule,
  String? description,
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
    status: 'open',
    completedFocusIntervals: 0,
    totalFocusSeconds: 0,
    orderKey: id,
    isDeleted: false,
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
