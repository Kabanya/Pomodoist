import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/features/tasks/domain/task_models.dart';
import 'package:pomodoist/features/tasks/presentation/widgets/task_motion.dart';

void main() {
  testWidgets('local creation fades and rises for 160ms', (tester) async {
    late TaskMotionController motion;
    await tester.pumpWidget(
      MaterialApp(
        home: TaskMotionScope(
          builder: (context, controller) {
            motion = controller;
            return const TaskMotionItem(
              taskId: 'task-1',
              child: SizedBox(height: 40),
            );
          },
        ),
      ),
    );

    motion.created({'task-1'});
    await tester.pump();
    expect(_opacity(tester, 'task-1'), 0);
    expect(_offset(tester, 'task-1').dy, 6);

    await tester.pump(const Duration(milliseconds: 80));
    expect(_opacity(tester, 'task-1'), inExclusiveRange(0, 1));
    expect(_offset(tester, 'task-1').dy, inExclusiveRange(0, 6));

    await tester.pump(const Duration(milliseconds: 80));
    expect(_opacity(tester, 'task-1'), 1);
    expect(_offset(tester, 'task-1').dy, 0);
  });

  testWidgets('confirmed deletion fades and collapses for 220ms', (
    tester,
  ) async {
    late TaskMotionController motion;
    final task = _task('task-1');
    await tester.pumpWidget(
      MaterialApp(
        home: TaskMotionScope(
          builder: (context, controller) {
            motion = controller;
            return const TaskMotionItem(
              taskId: 'task-1',
              child: SizedBox(height: 40),
            );
          },
        ),
      ),
    );

    motion.deleted([task]);
    await tester.pump();
    expect(motion.retainedTasks, [task]);
    expect(_opacity(tester, 'task-1'), 1);

    await tester.pump(const Duration(milliseconds: 110));
    expect(_opacity(tester, 'task-1'), inExclusiveRange(0, 1));
    expect(_heightFactor(tester, 'task-1'), inExclusiveRange(0, 1));

    await tester.pump(const Duration(milliseconds: 110));
    await tester.pumpAndSettle();
    expect(motion.retainedTasks, isEmpty);
  });

  testWidgets('Reduce Motion keeps final state without a transition', (
    tester,
  ) async {
    late TaskMotionController motion;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: TaskMotionScope(
            builder: (context, controller) {
              motion = controller;
              return const TaskMotionItem(
                taskId: 'task-1',
                child: SizedBox(height: 40),
              );
            },
          ),
        ),
      ),
    );

    motion.created({'task-1'});
    await tester.pump();

    expect(_opacity(tester, 'task-1'), 1);
    expect(_offset(tester, 'task-1'), Offset.zero);
  });

  testWidgets('completion ring reaches its final state by 180ms', (
    tester,
  ) async {
    late TaskMotionController motion;
    var completed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TaskMotionScope(
            builder: (context, controller) {
              motion = controller;
              return StatefulBuilder(
                builder: (context, setState) => TaskCompletionControl(
                  taskId: 'task-1',
                  isCompleted: completed,
                  color: Colors.red,
                  fillColor: Colors.red,
                  onPressed: () {
                    setState(() => completed = true);
                    motion.completed([_task('task-1', completed: true)]);
                  },
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('task-completion-control-task-1')));
    await tester.pump();
    expect(_completionProgress(tester, 'task-1'), 0);

    await tester.pump(const Duration(milliseconds: 80));
    expect(_completionProgress(tester, 'task-1'), closeTo(80 / 180, 0.01));

    await tester.pump(const Duration(milliseconds: 100));
    expect(_completionProgress(tester, 'task-1'), 1);
  });

  test('bulk motion is limited to six tasks', () {
    final motion = TaskMotionController();
    addTearDown(motion.dispose);

    motion.created({for (var index = 0; index < 6; index++) '$index'});
    expect(motion.eventFor('0'), isNotNull);
    expect(motion.eventFor('5'), isNotNull);
    expect(motion.eventFor('0')!.revision, motion.eventFor('5')!.revision);

    final seven = [
      for (var index = 0; index < 7; index++) _task('next-$index'),
    ];
    motion.completed(seven);
    expect(motion.eventFor('next-0'), isNull);
    expect(motion.eventFor('next-6'), isNull);
    expect(motion.retainedTasks, isEmpty);
  });

  testWidgets('completion snapshot is retained until its scope is disposed', (
    tester,
  ) async {
    late TaskMotionController motion;
    final task = _task('task-1', completed: true);
    await tester.pumpWidget(
      MaterialApp(
        home: TaskMotionScope(
          builder: (context, controller) {
            motion = controller;
            return const SizedBox();
          },
        ),
      ),
    );

    motion.completed([task]);
    await tester.pump(const Duration(seconds: 1));
    expect(motion.retainedTasks, [task]);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(motion.retainedTasks, isEmpty);
  });

  testWidgets('landing highlight fades for 160ms', (tester) async {
    late TaskMotionController motion;
    await tester.pumpWidget(
      MaterialApp(
        home: TaskMotionScope(
          builder: (context, controller) {
            motion = controller;
            return const TaskMotionItem(
              taskId: 'task-1',
              child: SizedBox(height: 40),
            );
          },
        ),
      ),
    );

    motion.landed({'task-1'});
    await tester.pump();
    expect(_motionColor(tester, 'task-1').a, greaterThan(0));

    await tester.pump(const Duration(milliseconds: 80));
    expect(_motionColor(tester, 'task-1').a, greaterThan(0));

    await tester.pump(const Duration(milliseconds: 80));
    expect(_motionColor(tester, 'task-1').a, 0);
  });
}

double _opacity(WidgetTester tester, String taskId) => tester
    .widget<Opacity>(find.byKey(Key('task-motion-opacity-$taskId')))
    .opacity;

Offset _offset(WidgetTester tester, String taskId) {
  final translation = tester
      .widget<Transform>(find.byKey(Key('task-motion-offset-$taskId')))
      .transform
      .getTranslation();
  return Offset(translation.x, translation.y);
}

double _heightFactor(WidgetTester tester, String taskId) => tester
    .widget<Align>(find.byKey(Key('task-motion-size-$taskId')))
    .heightFactor!;

double _completionProgress(WidgetTester tester, String taskId) =>
    (tester
                .widget<CustomPaint>(
                  find.byKey(Key('task-completion-paint-$taskId')),
                )
                .painter
            as TaskCompletionPainter)
        .progress;

Color _motionColor(WidgetTester tester, String taskId) {
  final widget = tester.widget<DecoratedBox>(
    find
        .ancestor(
          of: find.byKey(Key('task-motion-size-$taskId')),
          matching: find.byType(DecoratedBox),
        )
        .first,
  );
  return (widget.decoration as BoxDecoration).color!;
}

TaskItem _task(String id, {bool completed = false}) {
  final now = DateTime.utc(2026, 8, 28);
  return TaskItem(
    id: id,
    userId: 'user',
    content: 'Task',
    projectId: 'project',
    priority: 4,
    status: completed ? 'completed' : 'open',
    completedFocusIntervals: 0,
    totalFocusSeconds: 0,
    orderKey: id,
    isDeleted: false,
    createdAt: now,
    updatedAt: now,
  );
}
