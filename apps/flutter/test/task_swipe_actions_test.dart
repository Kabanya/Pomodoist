import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/localization/app_localizations.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/tasks/widgets/task_swipe_actions.dart';

void main() {
  testWidgets('revealed actions execute only when tapped', (tester) async {
    for (final reduceMotion in [false, true]) {
      for (final direction in [-1.0, 1.0]) {
        var focusCount = 0;
        var deleteCount = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduceMotion),
              child: Scaffold(
                body: TaskSwipeActions(
                  key: UniqueKey(),
                  enabled: true,
                  onFocus: () async => focusCount++,
                  onDelete: () async => deleteCount++,
                  builder: (_) => const SizedBox(
                    height: 64,
                    width: double.infinity,
                    child: ColoredBox(color: Colors.white, child: Text('Task')),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.drag(find.text('Task'), Offset(100 * direction, 0));
        await tester.pumpAndSettle();
        expect(focusCount, 0);
        expect(deleteCount, 0);

        final l10n = tester.element(find.text('Task')).l10n;
        await tester.tap(
          find.text(direction > 0 ? l10n.navFocus : l10n.commonDelete),
        );
        await tester.pumpAndSettle();

        expect(focusCount, direction > 0 ? 1 : 0);
        expect(deleteCount, direction < 0 ? 1 : 0);
        expect(find.byType(TextButton), findsNothing);
      }
    }
  });

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
            direction > 0 ? TaskSwipeAction.focus : TaskSwipeAction.delete,
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
