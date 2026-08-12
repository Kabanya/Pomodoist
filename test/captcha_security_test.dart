import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/captcha_security.dart';

void main() {
  group('CaptchaTokenController', () {
    test(
      'consumes a solved token exactly once and resets after every request',
      () async {
        final controller = CaptchaTokenController(required: true);
        final generation = controller.generation;

        expect(
          controller.acceptSolved('valid-turnstile-token-1234', generation),
          isTrue,
        );
        expect(controller.canSubmit, isTrue);

        final first = controller.beginRequest();
        expect(first, 'valid-turnstile-token-1234');
        expect(controller.beginRequest, throwsStateError);

        controller.finishRequest();
        expect(controller.canSubmit, isFalse);
        expect(controller.generation, generation + 1);
        expect(
          controller.acceptSolved('valid-turnstile-token-5678', generation),
          isFalse,
        );
      },
    );

    test('resets on failure and exposes expiry and safe error states', () {
      final controller = CaptchaTokenController(required: true);
      final generation = controller.generation;
      controller.acceptSolved('valid-turnstile-token-1234', generation);
      controller.beginRequest();
      controller.finishRequest(error: const FormatException('secret-value'));

      expect(controller.status, CaptchaStatus.awaiting);
      expect(controller.message, isNull);
      expect(controller.generation, generation + 1);

      controller.expire(controller.generation);
      expect(controller.status, CaptchaStatus.expired);
      expect(controller.message, 'Verification expired. Please try again.');

      controller.reportError(controller.generation);
      expect(controller.status, CaptchaStatus.error);
      expect(controller.message, 'Verification failed. Please try again.');
    });

    test('rejects stale and malformed browser callbacks', () {
      final controller = CaptchaTokenController(required: true);

      for (final token in ['', 'x\nsecret', 'x\rsecret', 'x\u0000secret']) {
        expect(controller.acceptSolved(token, controller.generation), isFalse);
      }
      expect(
        controller.acceptSolved('valid-turnstile-token-1234', 999),
        isFalse,
      );
      expect(controller.canSubmit, isFalse);
    });

    test('treats Turnstile responses as opaque up to the official limit', () {
      final controller = CaptchaTokenController(required: true);
      const punctuation = r'opaque+/=:% token.with-punctuation_~';
      expect(
        controller.acceptSolved(punctuation, controller.generation),
        isTrue,
      );
      controller.reset();
      expect(
        controller.acceptSolved('x' * 2048, controller.generation),
        isTrue,
      );
      controller.reset();
      expect(
        controller.acceptSolved('x' * 2049, controller.generation),
        isFalse,
      );
    });

    test('rejects stale callbacks after expiry and reset generations', () {
      final controller = CaptchaTokenController(required: true);
      final expiredGeneration = controller.generation;
      controller.expire(expiredGeneration);

      expect(
        controller.acceptSolved('stale-token', expiredGeneration),
        isFalse,
      );
      expect(
        controller.acceptSolved('fresh-token', controller.generation),
        isTrue,
      );
      final resetGeneration = controller.generation;
      controller.reset();
      expect(controller.acceptSolved('stale-token', resetGeneration), isFalse);
    });

    test('empty-key local mode can submit without a token', () {
      final controller = CaptchaTokenController(required: false);

      expect(controller.canSubmit, isTrue);
      expect(controller.beginRequest(), isNull);
      controller.finishRequest();
      expect(controller.canSubmit, isTrue);
    });

    test(
      'protected executor passes one token and resets after success or failure',
      () async {
        final controller = CaptchaTokenController(required: true);
        final seen = <String?>[];
        controller.acceptSolved(
          'valid-turnstile-token-1234',
          controller.generation,
        );
        final executor = CaptchaProtectedExecutor(controller);

        await executor.run((token) async => seen.add(token));
        expect(seen, ['valid-turnstile-token-1234']);
        expect(controller.canSubmit, isFalse);

        controller.acceptSolved(
          'valid-turnstile-token-5678',
          controller.generation,
        );
        await expectLater(
          executor.run<void>((token) async {
            seen.add(token);
            throw StateError('request failed');
          }),
          throwsStateError,
        );
        expect(seen, [
          'valid-turnstile-token-1234',
          'valid-turnstile-token-5678',
        ]);
        expect(controller.canSubmit, isFalse);
      },
    );
  });

  test('loader timeout guard is bounded, cancellable, and test-injectable', () {
    Duration? scheduledDuration;
    void Function()? scheduledCallback;
    var cancelCalls = 0;
    var timeoutCalls = 0;
    final guard = CaptchaLoadTimeoutGuard(
      timeout: const Duration(seconds: 10),
      onTimeout: () => timeoutCalls += 1,
      schedule: (duration, callback) {
        scheduledDuration = duration;
        scheduledCallback = callback;
        return () => cancelCalls += 1;
      },
    );

    expect(scheduledDuration, const Duration(seconds: 10));
    guard.complete();
    scheduledCallback!();
    expect(cancelCalls, 1);
    expect(timeoutCalls, 0);

    final timedOut = CaptchaLoadTimeoutGuard(
      timeout: const Duration(seconds: 10),
      onTimeout: () => timeoutCalls += 1,
      schedule: (duration, callback) {
        scheduledCallback = callback;
        return () => cancelCalls += 1;
      },
    );
    scheduledCallback!();
    scheduledCallback!();
    expect(timeoutCalls, 1);
    timedOut.complete();
  });

  group('native CAPTCHA challenge', () {
    final now = DateTime.utc(2026, 7, 12, 10);

    test('accepts only environment-matched native challenge configuration', () {
      expect(
        NativeCaptchaBuildConfig.fromValues(
          environment: 'staging',
          registrationUrl: 'https://app-test.pomodoist.com/auth/challenge',
        ).registrationUrl.host,
        'app-test.pomodoist.com',
      );
      expect(
        NativeCaptchaBuildConfig.fromValues(
          environment: 'production',
          registrationUrl: 'https://app.pomodoist.com/auth/challenge',
        ).registrationUrl.host,
        'app.pomodoist.com',
      );
      for (final values in [
        ('staging', 'https://app.pomodoist.com/auth/challenge'),
        ('production', 'https://app-test.pomodoist.com/auth/challenge'),
        ('production', 'https://app.pomodoist.com/auth/challenge/'),
        ('production', 'http://app.pomodoist.com/auth/challenge'),
      ]) {
        expect(
          () => NativeCaptchaBuildConfig.fromValues(
            environment: values.$1,
            registrationUrl: values.$2,
          ),
          throwsFormatException,
          reason: values.toString(),
        );
      }
    });

    test('opens only an approved HTTPS challenge with opaque state', () {
      final session = NativeCaptchaSession(
        registrationUrl: Uri.parse(
          'https://app-test.pomodoist.com/auth/challenge',
        ),
        now: () => now,
        stateFactory: () => 'A' * 43,
      );

      final request = session.begin();

      expect(request.scheme, 'https');
      expect(request.host, 'app-test.pomodoist.com');
      expect(request.path, '/auth/challenge');
      expect(request.queryParameters, {
        'returnTo': 'pomodoist://captcha-callback',
      });
      expect(request.fragment, 'state=${'A' * 43}');
      expect(request.toString(), isNot(contains('?state=')));
      expect(request.userInfo, isEmpty);
      expect(request.hasPort, isFalse);
    });

    test(
      'accepts exact callback once and rejects replay, mismatch, expiry',
      () {
        var clock = now;
        final session = NativeCaptchaSession(
          registrationUrl: Uri.parse(
            'https://app-test.pomodoist.com/auth/challenge',
          ),
          now: () => clock,
          stateFactory: () => 'B' * 43,
        );
        session.begin();
        final callback = Uri.parse(
          'pomodoist://captcha-callback?state=${'B' * 43}'
          '&token=valid-turnstile-token-1234',
        );

        expect(session.consumeCallback(callback), 'valid-turnstile-token-1234');
        expect(() => session.consumeCallback(callback), throwsStateError);

        session.begin();
        expect(
          () => session.consumeCallback(
            Uri.parse(
              'pomodoist://captcha-callback?state=${'C' * 43}'
              '&token=valid-turnstile-token-1234',
            ),
          ),
          throwsFormatException,
        );

        session.cancel();
        session.begin();
        clock = now.add(const Duration(minutes: 6));
        expect(() => session.consumeCallback(callback), throwsStateError);
      },
    );

    test('rejects malicious return targets and callback shapes', () {
      const exact = 'pomodoist://captcha-callback';
      expect(isExactCaptchaReturnTarget(exact), isTrue);
      for (final target in [
        'Pomodoist://captcha-callback',
        'pomodoist://CAPTCHA-callback',
        'pomodoist://captcha-callback/',
        'pomodoist://user@captcha-callback',
        'pomodoist://captcha-callback:443',
        'pomodoist://captcha-callback?next=https://evil.test',
        'pomodoist://captcha-callback#fragment',
        'https://app.pomodoist.com',
      ]) {
        expect(isExactCaptchaReturnTarget(target), isFalse, reason: target);
      }

      final session = NativeCaptchaSession(
        registrationUrl: Uri.parse('https://app.pomodoist.com/auth/challenge'),
        now: () => now,
        stateFactory: () => 'D' * 43,
      );
      session.begin();
      for (final callback in [
        'pomodoist://captcha-callback/path?state=${'D' * 43}&token=valid-turnstile-token-1234',
        'pomodoist://user@captcha-callback?state=${'D' * 43}&token=valid-turnstile-token-1234',
        'pomodoist://captcha-callback:80?state=${'D' * 43}&token=valid-turnstile-token-1234',
        'pomodoist://captcha-callback?state=${'D' * 43}&token=valid-turnstile-token-1234&extra=x',
        'pomodoist://captcha-callback?state=${'D' * 43}&token=x%0Asecret',
      ]) {
        expect(
          () => session.consumeCallback(Uri.parse(callback)),
          throwsFormatException,
          reason: callback,
        );
      }
    });

    test('validates challenge page input and builds one exact handoff', () {
      final request = CaptchaChallengeRequest.parse(
        Uri.parse(
          '/auth/challenge?returnTo=pomodoist%3A%2F%2Fcaptcha-callback'
          '#state=${'E' * 43}',
        ),
      );
      expect(
        request.handoffUri('valid-turnstile-token-1234').toString(),
        'pomodoist://captcha-callback?state=${'E' * 43}'
        '&token=valid-turnstile-token-1234',
      );

      for (final uri in [
        '/auth/challenge?returnTo=https%3A%2F%2Fevil.test#state=${'E' * 43}',
        '/auth/challenge?returnTo=pomodoist%3A%2F%2Fcaptcha-callback#state=short',
        '/auth/challenge?returnTo=pomodoist%3A%2F%2Fcaptcha-callback#state=${'E' * 43}&extra=x',
        '/auth/challenge?returnTo=pomodoist%3A%2F%2Fcaptcha-callback&state=${'E' * 43}',
        '/other?returnTo=pomodoist%3A%2F%2Fcaptcha-callback#state=${'E' * 43}',
        'https://evil.test/auth/challenge?returnTo=pomodoist%3A%2F%2Fcaptcha-callback#state=${'E' * 43}',
        'http://app-test.pomodoist.com/auth/challenge?returnTo=pomodoist%3A%2F%2Fcaptcha-callback#state=${'E' * 43}',
      ]) {
        expect(
          () => CaptchaChallengeRequest.parse(Uri.parse(uri)),
          throwsFormatException,
          reason: uri,
        );
      }
    });
  });

  test(
    'handoff retries the same in-memory callback without regenerating it',
    () {
      final request = CaptchaChallengeRequest.parse(
        Uri.parse(
          '/auth/challenge?returnTo=pomodoist%3A%2F%2Fcaptcha-callback'
          '#state=${'H' * 43}',
        ),
      );
      final attempts = <Uri>[];
      final controller = CaptchaHandoffController();

      expect(
        controller.solveAndHandoff(request, 'opaque-token', attempts.add),
        isTrue,
      );
      expect(
        controller.solveAndHandoff(request, 'replacement-token', attempts.add),
        isFalse,
      );
      expect(controller.retry(attempts.add), isTrue);

      expect(attempts, hasLength(2));
      expect(attempts[1], attempts[0]);
      expect(identical(attempts[1], attempts[0]), isTrue);
    },
  );
}
