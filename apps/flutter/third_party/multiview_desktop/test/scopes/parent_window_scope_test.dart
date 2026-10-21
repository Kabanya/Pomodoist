import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiview_desktop/src/parent_window_scope.dart';

void main() {
  group('ParentWindowScope', () {
    testWidgets('maybeOf returns parent context from ancestor', (tester) async {
      late BuildContext parentContext;
      late BuildContext childContext;

      await tester.pumpWidget(
        Builder(
          builder: (context) {
            parentContext = context;
            return ParentWindowScope(
              parentContext: parentContext,
              child: Builder(
                builder: (context) {
                  childContext = context;
                  return const SizedBox();
                },
              ),
            );
          },
        ),
      );
      await tester.pump();

      expect(ParentWindowScope.maybeOf(childContext)?.parentContext, parentContext);
    });

    testWidgets('of returns scope with null parent when not specified', (tester) async {
      late BuildContext childContext;

      await tester.pumpWidget(
        ParentWindowScope(
          parentContext: null,
          child: Builder(
            builder: (context) {
              childContext = context;
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pump();

      expect(ParentWindowScope.of(childContext).parentContext, isNull);
    });

    testWidgets('maybeOf returns null outside ParentWindowScope', (tester) async {
      late BuildContext context;

      await tester.pumpWidget(
        Builder(
          builder: (ctx) {
            context = ctx;
            return const SizedBox();
          },
        ),
      );
      await tester.pump();

      expect(ParentWindowScope.maybeOf(context), isNull);
    });
  });
}
