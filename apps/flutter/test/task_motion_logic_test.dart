import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/theme/app_motion.dart';
import 'package:pomodoist/features/tasks/presentation/widgets/task_motion.dart';

void main() {
  test('changing the checkmark color invalidates the completion painter', () {
    const before = TaskCompletionPainter(
      progress: 1,
      color: Colors.red,
      fillColor: Colors.red,
      checkColor: Colors.white,
    );
    const after = TaskCompletionPainter(
      progress: 1,
      color: Colors.red,
      fillColor: Colors.red,
      checkColor: Colors.black,
    );
    expect(after.shouldRepaint(before), isTrue);
    expect(before.shouldRepaint(before), isFalse);
  });
  test('creation settles before its highlight disappears', () {
    final start = taskCreationProgress(0);
    final moving = taskCreationProgress(.2);
    final settled = taskCreationProgress(
      AppMotion.task.inMicroseconds / AppMotion.highlight.inMicroseconds,
    );
    final end = taskCreationProgress(1);
    expect(start, (position: 0.0, highlight: 1.0));
    expect(moving.position, inExclusiveRange(0, 1));
    expect(settled.position, 1);
    expect(settled.highlight, inExclusiveRange(0, moving.highlight));
    expect(end, (position: 1.0, highlight: 0.0));
  });

  test('Reduce Motion reaches the final state at every animation position', () {
    for (final progress in [-1.0, 0.0, .5, 1.0, 2.0]) {
      expect(taskCreationProgress(progress, reduceMotion: true), (
        position: 1.0,
        highlight: 0.0,
      ));
    }
    expect(taskCreationProgress(-1), taskCreationProgress(0));
    expect(taskCreationProgress(2), taskCreationProgress(1));
  });

  test(
    'creation events preserve bulk limits and update only requested rows',
    () {
      final motion = TaskMotionController();
      addTearDown(motion.dispose);
      var notifications = 0;
      motion.addListener(() => notifications++);
      motion.created({'a', 'b'});
      final first = motion.eventFor('a');
      expect(motion.eventFor('b')!.revision, first!.revision);
      motion.created({
        for (var i = 0; i <= TaskMotionController.maxAnimatedBulkTasks; i++)
          'bulk-$i',
      });
      expect(notifications, 1);
      expect(motion.eventFor('bulk-0'), isNull);
      motion.landed({'b'});
      expect(motion.eventFor('a'), same(first));
      expect(motion.eventFor('b')!.revision, greaterThan(first.revision));
    },
  );
}
