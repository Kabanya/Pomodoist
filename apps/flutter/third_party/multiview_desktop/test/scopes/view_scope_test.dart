import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiview_desktop/src/view_scope.dart';

void main() {
  group('ViewScope', () {
    testWidgets('maybeOf returns scope when present', (tester) async {
      late BuildContext innerContext;

      await tester.pumpWidget(
        ViewScope(
          viewId: 42,
          child: Builder(
            builder: (context) {
              innerContext = context;
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pump();

      expect(ViewScope.maybeOf(innerContext)?.viewId, 42);
    });

    testWidgets('of returns scope in debug mode', (tester) async {
      late BuildContext innerContext;

      await tester.pumpWidget(
        ViewScope(
          viewId: 7,
          child: Builder(
            builder: (context) {
              innerContext = context;
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pump();

      expect(ViewScope.of(innerContext).viewId, 7);
    });

    testWidgets('updateShouldNotify when viewId changes', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: _ViewScopeHost()),
      );
      await tester.pump();

      expect(find.text('id-1'), findsOneWidget);

      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();
      expect(find.text('id-2'), findsOneWidget);
    });

    testWidgets('maybeOf returns null outside ViewScope', (tester) async {
      late BuildContext innerContext;

      await tester.pumpWidget(
        Builder(
          builder: (context) {
            innerContext = context;
            return const SizedBox();
          },
        ),
      );
      await tester.pump();

      expect(ViewScope.maybeOf(innerContext), isNull);
    });
  });
}

class _ViewScopeHost extends StatefulWidget {
  const _ViewScopeHost();

  @override
  State<_ViewScopeHost> createState() => _ViewScopeHostState();
}

class _ViewScopeHostState extends State<_ViewScopeHost> {
  int _viewId = 1;

  @override
  Widget build(BuildContext context) {
    return ViewScope(
      viewId: _viewId,
      child: Builder(
        key: const ValueKey('inner'),
        builder: (context) {
          final scopeId = ViewScope.of(context).viewId;
          return ElevatedButton(
            onPressed: () => setState(() => _viewId = 2),
            child: Text('id-$scopeId'),
          );
        },
      ),
    );
  }
}
