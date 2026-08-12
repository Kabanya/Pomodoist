import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/captcha_security.dart';
import 'package:pomodoist/app/captcha_verification.dart';

void main() {
  testWidgets(
    'synchronous render failure reports current generation and shows retry',
    (tester) async {
      final controller = CaptchaTokenController(required: true);
      var changes = 0;
      late VoidCallback notifyChanged;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                notifyChanged = () {
                  changes += 1;
                  setState(() {});
                };
                return CaptchaVerification(
                  siteKey: 'test-site-key',
                  controller: controller,
                  onChanged: notifyChanged,
                );
              },
            ),
          ),
        ),
      );

      final result = renderTurnstileSafely<Object>(
        controller: controller,
        generation: controller.generation,
        onChanged: notifyChanged,
        render: () => throw StateError('synchronous JS render failure'),
      );
      await tester.pump();

      expect(result, isNull);
      expect(tester.takeException(), isNull);
      expect(changes, 1);
      expect(controller.status, CaptchaStatus.error);
      expect(find.text('Retry verification'), findsOneWidget);
    },
  );

  test('stale synchronous render failure cannot reset a newer challenge', () {
    final controller = CaptchaTokenController(required: true);
    final staleGeneration = controller.generation;
    controller.reset();
    var changes = 0;

    final result = renderTurnstileSafely<Object>(
      controller: controller,
      generation: staleGeneration,
      onChanged: () => changes += 1,
      render: () => throw StateError('stale synchronous JS failure'),
    );

    expect(result, isNull);
    expect(changes, 0);
    expect(controller.status, CaptchaStatus.awaiting);
  });

  testWidgets('error waits for an explicit retry before remounting', (
    tester,
  ) async {
    final controller = CaptchaTokenController(required: true);
    controller.reportError(controller.generation);
    var changes = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => CaptchaVerification(
              siteKey: 'test-site-key',
              controller: controller,
              onChanged: () {
                changes += 1;
                setState(() {});
              },
            ),
          ),
        ),
      ),
    );

    expect(find.text('Retry verification'), findsOneWidget);
    expect(controller.status, CaptchaStatus.error);

    await tester.tap(find.byKey(const Key('captcha-verification-retry')));
    await tester.pump();

    expect(changes, 1);
    expect(controller.status, CaptchaStatus.awaiting);
    expect(find.text('Retry verification'), findsNothing);
  });
}
