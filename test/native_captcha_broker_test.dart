import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/captcha_security.dart';
import 'package:pomodoist/app/native_captcha_broker.dart';

void main() {
  test('native broker accepts the matching callback exactly once', () async {
    final links = StreamController<Uri>.broadcast();
    final launched = Completer<Uri>();
    final broker = NativeCaptchaBroker(
      uriStream: links.stream,
      config: NativeCaptchaBuildConfig.fromValues(
        environment: 'staging',
        registrationUrl: 'https://app-test.pomodoist.com/auth/challenge',
      ),
      launch: (uri) async {
        launched.complete(uri);
        return true;
      },
    );

    final tokenFuture = broker.requestToken();
    final challenge = await launched.future;
    final state = Uri(query: challenge.fragment).queryParameters['state']!;
    links.add(
      Uri(
        scheme: 'pomodoist',
        host: 'captcha-callback',
        queryParameters: {'state': state, 'token': 'opaque+/= token'},
      ),
    );

    await expectLater(tokenFuture, completion('opaque+/= token'));
    links.add(
      Uri(
        scheme: 'pomodoist',
        host: 'captcha-callback',
        queryParameters: {'state': state, 'token': 'replayed'},
      ),
    );
    await Future<void>.delayed(Duration.zero);
    final second = broker.requestToken();
    final cancelled = expectLater(second, throwsStateError);
    broker.cancel();
    await cancelled;
    await links.close();
    broker.dispose();
  });

  test(
    'native broker ignores mismatched state without exposing values',
    () async {
      final links = StreamController<Uri>.broadcast();
      final broker = NativeCaptchaBroker(
        uriStream: links.stream,
        config: NativeCaptchaBuildConfig.fromValues(
          environment: 'production',
          registrationUrl: 'https://app.pomodoist.com/auth/challenge',
        ),
        launch: (_) async => true,
      );

      final tokenFuture = broker.requestToken();
      await Future<void>.delayed(Duration.zero);
      links.add(
        Uri(
          scheme: 'pomodoist',
          host: 'captcha-callback',
          queryParameters: {'state': 'X' * 43, 'token': 'opaque-token'},
        ),
      );

      var completed = false;
      unawaited(
        tokenFuture.then<void>(
          (_) => completed = true,
          onError: (_) => completed = true,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);

      final cancelled = expectLater(tokenFuture, throwsStateError);
      broker.cancel();
      await cancelled;
      await links.close();
      broker.dispose();
    },
  );

  for (final staleLaunchFailure in const ['false', 'error']) {
    test(
      'stale $staleLaunchFailure launch and callback cannot cancel the next request',
      () async {
        final links = StreamController<Uri>.broadcast();
        final launches = <_DeferredLaunch>[];
        final expiries = <void Function()>[];
        final cancelledExpiries = <int>[];
        final broker = NativeCaptchaBroker(
          uriStream: links.stream,
          config: NativeCaptchaBuildConfig.fromValues(
            environment: 'staging',
            registrationUrl: 'https://app-test.pomodoist.com/auth/challenge',
          ),
          launch: (uri) {
            final launch = _DeferredLaunch(uri);
            launches.add(launch);
            return launch.result.future;
          },
          scheduleTimeout: (duration, callback) {
            expect(duration, const Duration(minutes: 5));
            final index = expiries.length;
            expiries.add(callback);
            return () => cancelledExpiries.add(index);
          },
        );

        final first = broker.requestToken();
        expect(launches, hasLength(1));
        final firstState = _challengeState(launches[0].uri);
        final firstCancelled = expectLater(first, throwsStateError);
        broker.cancel();
        await firstCancelled;

        final second = broker.requestToken();
        expect(launches, hasLength(2));
        final secondState = _challengeState(launches[1].uri);

        if (staleLaunchFailure == 'false') {
          launches[0].result.complete(false);
        } else {
          launches[0].result.completeError(StateError('stale launch error'));
        }
        expiries[0]();
        links.add(_callback(firstState, 'stale-token'));
        await Future<void>.delayed(Duration.zero);

        launches[1].result.complete(true);
        links.add(_callback(secondState, 'current-token'));
        await expectLater(second, completion('current-token'));
        expect(cancelledExpiries, [0, 1]);

        await links.close();
        broker.dispose();
      },
    );
  }
}

final class _DeferredLaunch {
  _DeferredLaunch(this.uri);

  final Uri uri;
  final Completer<bool> result = Completer<bool>();
}

String _challengeState(Uri challenge) {
  return Uri(query: challenge.fragment).queryParameters['state']!;
}

Uri _callback(String state, String token) {
  return Uri(
    scheme: 'pomodoist',
    host: 'captcha-callback',
    queryParameters: {'state': state, 'token': token},
  );
}
