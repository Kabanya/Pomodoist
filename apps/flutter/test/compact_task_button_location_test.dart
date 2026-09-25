import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/ui/core/widgets/compact_task_button_location.dart';

ScaffoldPrelayoutGeometry geometry({
  double contentBottom = 734,
  EdgeInsets insets = const EdgeInsets.only(top: 44),
  Size viewport = const Size(390, 844),
  double snackBarHeight = 0,
}) => ScaffoldPrelayoutGeometry(
  bottomSheetSize: Size.zero,
  contentBottom: contentBottom,
  contentTop: 0,
  floatingActionButtonSize: const Size.square(52),
  minInsets: insets,
  minViewPadding: const EdgeInsets.only(top: 44, bottom: 34),
  scaffoldSize: viewport,
  snackBarSize: Size(390, snackBarHeight),
  materialBannerSize: Size.zero,
  textDirection: TextDirection.ltr,
);

void main() {
  test(
    'corner motion eases for 240 ms and resumes from the visible position',
    () {
      const begin = Offset(16, 112);
      const visible = Offset(80, 240);
      const end = Offset(322, 666);
      const animator = CompactTaskButtonAnimator(from: visible);
      final completion = 240 / (kFloatingActionButtonSegue.inMilliseconds * 2);
      Offset at(double progress) =>
          animator.getOffset(begin: begin, end: end, progress: progress);
      expect(at(0), visible);
      final halfway = at(completion / 2);
      expect(halfway.dx, greaterThan((visible.dx + end.dx) / 2));
      expect(halfway.dx, lessThan(end.dx));
      expect(halfway.dy, greaterThan(visible.dy));
      expect(halfway.dy, lessThan(end.dy));
      expect(at(completion), end);
      expect(at(1), end);
      expect(
        const CompactTaskButtonAnimator().getOffset(
          begin: begin,
          end: end,
          progress: 0,
        ),
        begin,
      );
      for (final progress in [0.0, .3, 1.0]) {
        expect(
          const CompactTaskButtonAnimator(
            immediate: true,
          ).getOffset(begin: begin, end: end, progress: progress),
          end,
        );
        final parent = AlwaysStoppedAnimation(progress);
        expect(animator.getScaleAnimation(parent: parent).value, 1);
        expect(animator.getRotationAnimation(parent: parent).value, 0);
      }
    },
  );

  test(
    'button clears panels without adding navigation or safe insets twice',
    () {
      final layout = geometry();
      expect(
        CompactTaskButtonLocation().getOffset(layout),
        const Offset(322, 666),
      );
      expect(
        CompactTaskButtonLocation(bottomClearance: 110).getOffset(layout),
        const Offset(322, 666),
      );
      expect(
        CompactTaskButtonLocation(bottomClearance: 190).getOffset(layout),
        const Offset(322, 586),
      );
      expect(
        CompactTaskButtonLocation(bottomClearance: 110).getOffset(layout),
        const Offset(322, 666),
      );
    },
  );

  test('keyboard, snackbar and all four corners respect safe boundaries', () {
    final keyboard = geometry(
      contentBottom: 500,
      insets: const EdgeInsets.only(top: 44, bottom: 344),
    );
    for (final corner in [
      Alignment.topLeft,
      Alignment.topRight,
      Alignment.bottomLeft,
      Alignment.bottomRight,
    ]) {
      final location = CompactTaskButtonLocation(
        corner: corner,
        bottomClearance: 190,
      );
      expect(
        location.getOffset(keyboard),
        Offset(corner.x < 0 ? 16 : 322, corner.y < 0 ? 112 : 432),
      );
    }
    expect(
      CompactTaskButtonLocation().getOffset(geometry(snackBarHeight: 48)).dy,
      618,
    );
  });

  test(
    'drag clamps to resized bounds and snaps with the release direction',
    () {
      final location = CompactTaskButtonLocation(
        dragPosition: const Offset(-200, 2000),
        bottomClearance: 190,
      );
      expect(location.getOffset(geometry()), const Offset(16, 586));
      expect(location.nearestCorner(Offset.zero), Alignment.bottomLeft);
      expect(
        location.nearestCorner(const Offset(3000, -3000)),
        Alignment.topRight,
      );
      expect(location.clamp(const Offset(2000, -200)), const Offset(322, 112));
      final landscape = geometry(
        contentBottom: 300,
        viewport: const Size(700, 390),
        insets: const EdgeInsets.only(left: 44, right: 44),
      );
      expect(location.getOffset(landscape), const Offset(60, 132));
      expect(location.clamp(const Offset(2000, -200)), const Offset(588, 68));
    },
  );
}
