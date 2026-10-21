import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiview_desktop/multiview_desktop.dart';

void main() {
  group('DialogScope', () {
    testWidgets('maybeOf returns notifier from ancestor', (tester) async {
      final notifier = ValueNotifier<List<DialogInfo>>([]);
      addTearDown(notifier.dispose);
      late BuildContext childContext;

      await tester.pumpWidget(
        DialogScope(
          notifier: notifier,
          child: Builder(
            builder: (context) {
              childContext = context;
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pump();

      expect(DialogScope.maybeOf(childContext), same(notifier));
    });

    testWidgets('of returns notifier in debug mode', (tester) async {
      final notifier = ValueNotifier<List<DialogInfo>>([
        (id: 1, isModal: true),
      ]);
      addTearDown(notifier.dispose);
      late BuildContext childContext;

      await tester.pumpWidget(
        DialogScope(
          notifier: notifier,
          child: Builder(
            builder: (context) {
              childContext = context;
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pump();

      expect(DialogScope.of(childContext).value, [(id: 1, isModal: true)]);
    });

    testWidgets('rebuilds dependents when notifier changes', (tester) async {
      final notifier = ValueNotifier<List<DialogInfo>>([]);
      addTearDown(notifier.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: DialogScope(
            notifier: notifier,
            child: ValueListenableBuilder<List<DialogInfo>>(
              valueListenable: notifier,
              builder: (context, list, child) => Text('count-${list.length}'),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('count-0'), findsOneWidget);

      notifier.value = [(id: 2, isModal: false)];
      await tester.pump();
      expect(find.text('count-1'), findsOneWidget);
    });
  });
}
