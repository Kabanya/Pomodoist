import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/captcha_security.dart';
import 'package:pomodoist/features/settings/presentation/captcha_challenge_screen.dart';

void main() {
  testWidgets('shows a user-clicked fallback that retries the exact handoff', (
    tester,
  ) async {
    final uri = Uri.parse(
      '/auth/challenge?returnTo=pomodoist%3A%2F%2Fcaptcha-callback'
      '#state=${'J' * 43}',
    );
    final request = CaptchaChallengeRequest.parse(uri);
    final controller = CaptchaHandoffController();
    final handoffs = <Uri>[];
    controller.solveAndHandoff(request, 'opaque-token', handoffs.add);

    await tester.pumpWidget(
      MaterialApp(
        home: CaptchaChallengeScreen(
          uri: uri,
          handoffController: controller,
          onHandoff: handoffs.add,
        ),
      ),
    );

    expect(find.text('Return to Pomodoist'), findsOneWidget);
    expect(find.textContaining('close this page'), findsOneWidget);
    expect(find.textContaining('opaque-token'), findsNothing);

    await tester.tap(find.byKey(const Key('captcha-handoff-retry')));
    await tester.pump();

    expect(handoffs, hasLength(2));
    expect(handoffs[1], same(handoffs[0]));
  });
}
