import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/features/tasks/presentation/widgets/task_swipe_actions.dart';

void main() {
  test(
    '48px reveals a button; arbitrarily long swipes never execute actions',
    () {
      final swipe = TaskSwipeState();
      for (final direction in [-1.0, 1.0]) {
        swipe.begin(0);
        swipe.update(47 * direction, 144);
        expect(swipe.revealed, isNull);
        swipe.end(144);
        expect(swipe.offset, 0);
        for (final travel in [48.0, 5000.0]) {
          swipe.begin(0);
          swipe.update(travel * direction, 144);
          expect(swipe.revealed, isNull);
          expect(swipe.offset.abs(), lessThanOrEqualTo(144));
          swipe.end(144);
          expect(swipe.offset, 144 * direction);
          expect(
            swipe.revealed,
            direction > 0 ? TaskSwipeAction.focus : TaskSwipeAction.schedule,
          );
        }
      }
    },
  );

  test(
    'a reverse gesture closes the current button without revealing the other',
    () {
      final swipe = TaskSwipeState();
      swipe.begin(0);
      swipe.update(60, 144);
      swipe.end(144);
      swipe.begin(swipe.offset);
      swipe.update(-600, 144);
      swipe.end(144);
      expect(swipe.revealed, isNull);
      expect(swipe.offset, 0);
    },
  );

  test(
    'cancel, outside tap, Back and disabling use the immediate closed state',
    () {
      final swipe = TaskSwipeState();
      swipe.begin(0);
      swipe.update(90, 144);
      swipe.close();
      swipe.update(200, 144);
      swipe.end(144);
      expect(swipe.offset, 0);
      expect(swipe.revealed, isNull);
      expect(swipe.dragging, isFalse);
      swipe.begin(0);
      swipe.update(-90, 144);
      swipe.end(144);
      swipe.close(); // Final state is independent of an animation completing.
      expect(swipe.revealed, isNull);
      expect(swipe.offset, 0);
    },
  );

  test(
    'the action uses at most half the row and follows movement before release',
    () {
      final swipe = TaskSwipeState();
      final extent = TaskSwipeState.actionExtent(200);
      expect(extent, 100);
      expect(TaskSwipeState.actionExtent(1000), 144);
      swipe.begin(0);
      swipe.update(20, extent);
      expect(swipe.offset, 20);
      swipe.update(80, extent);
      expect(swipe.offset, 100);
      swipe.end(extent);
      expect(swipe.offset, 100);
      swipe.begin(swipe.offset);
      swipe.update(50, extent);
      swipe.end(extent);
      expect(swipe.revealed, TaskSwipeAction.focus);
    },
  );
}
