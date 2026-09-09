import 'package:shadcn_ui/shadcn_ui.dart' show ShadButton;
import 'support/test_app.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/features/settings/presentation/account_sign_out_button.dart';

void main() {
  setUpAll(loadTestAppResources);
  testWidgets('pending sign-out may complete after the button is disposed', (
    tester,
  ) async {
    final pending = Completer<void>();
    var calls = 0;

    await tester.pumpWidget(
      MaterialApp(
        builder: testAppBuilder,
        home: AccountSignOutButton(
          label: 'Sign out',
          onSignOut: () {
            calls += 1;
            return pending.future;
          },
        ),
      ),
    );

    await tester.tap(find.text('Sign out'));
    await tester.pump();
    await tester.tap(find.text('Sign out'));
    expect(calls, 1, reason: 'duplicate presses must be ignored');

    await tester.pumpWidget(
      const MaterialApp(builder: testAppBuilder, home: SizedBox.shrink()),
    );
    pending.complete();
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('slow sign-out keeps one request and later returns to idle', (
    tester,
  ) async {
    final pending = Completer<void>();
    var calls = 0;

    await tester.pumpWidget(
      MaterialApp(
        builder: testAppBuilder,
        home: Scaffold(
          body: AccountSignOutButton(
            label: 'Sign out',
            onSignOut: () {
              calls += 1;
              return pending.future;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Sign out'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 30));

    expect(find.byKey(const Key('account-sign-out-slow')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(calls, 1);
    expect(
      tester.widget<ShadButton>(find.byType(ShadButton)).onPressed,
      isNull,
    );

    pending.complete();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('account-sign-out-slow')), findsNothing);
    expect(
      tester.widget<ShadButton>(find.byType(ShadButton)).onPressed,
      isNotNull,
    );
    expect(calls, 1);
  });
}
