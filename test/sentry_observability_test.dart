import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/runtime_public_config.dart';
import 'package:pomodoist/app/sentry_observability.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

void main() {
  const release = '0123456789abcdef0123456789abcdef01234567';

  group('SentryRuntimePolicy', () {
    test('enables staging with privacy-safe exact release metadata', () {
      final policy = SentryRuntimePolicy.fromConfig(
        _config(environment: 'staging', release: release),
      );

      expect(policy.enabled, isTrue);
      expect(policy.dsn, 'https://public@o12345.ingest.sentry.io/42');
      expect(policy.environment, 'staging');
      expect(policy.dist, 'staging');
      expect(policy.release, release);
      expect(policy.errorSampleRate, 1.0);
      expect(policy.tracesSampleRate, 0.10);
      expect(policy.sendDefaultPii, isFalse);
      expect(policy.publicMetadata, {
        'environment': 'staging',
        'release': release,
      });
      expect(policy.publicMetadata.toString(), isNot(contains('anon-key')));
      expect(policy.publicMetadata.toString(), isNot(contains('public@')));
    });

    test('uses the production trace rate', () {
      final policy = SentryRuntimePolicy.fromConfig(
        _config(environment: 'production', release: release),
      );

      expect(policy.enabled, isTrue);
      expect(policy.environment, 'production');
      expect(policy.dist, 'production');
      expect(policy.tracesSampleRate, 0.05);
    });

    test('local never enables transport even when a DSN is present', () {
      final policy = SentryRuntimePolicy.fromConfig(
        _config(environment: 'local', release: 'development'),
      );

      expect(policy.enabled, isFalse);
      expect(policy.dsn, isEmpty);
      expect(policy.dist, 'local');
      expect(policy.tracesSampleRate, 0);
      expect(policy.sendDefaultPii, isFalse);
    });

    test('an empty remote DSN safely disables transport', () {
      final policy = SentryRuntimePolicy.fromConfig(
        _config(environment: 'staging', release: release, sentryDsn: ''),
      );

      expect(policy.enabled, isFalse);
      expect(policy.dsn, isEmpty);
      expect(policy.tracesSampleRate, 0);
    });
  });

  group('runPomodoistStartup', () {
    test('monitoring policy failure shows generic startup failure', () async {
      final failure = FormatException('secret malformed config detail');
      var failureUiCalls = 0;

      await expectLater(
        runPomodoistStartup(
          loadMonitoringPolicy: () async => throw failure,
          loadRuntimeConfig: () async => fail('must not load runtime config'),
          startApplication: (_) async => fail('must not start'),
          monitor: _FakeStartupMonitor(),
          onStartupFailure: () => failureUiCalls += 1,
        ),
        throwsA(same(failure)),
      );

      expect(failureUiCalls, 1);
    });

    test(
      'disabled monitoring starts directly without monitor transport',
      () async {
        final monitor = _FakeStartupMonitor();
        var started = false;

        await runPomodoistStartup(
          loadMonitoringPolicy: () async => SentryRuntimePolicy.fromConfig(
            _config(environment: 'local', release: 'development'),
          ),
          loadRuntimeConfig: () async =>
              _config(environment: 'local', release: 'development'),
          startApplication: (_) async => started = true,
          monitor: monitor,
        );

        expect(started, isTrue);
        expect(monitor.runCount, 0);
        expect(monitor.captured, isEmpty);
      },
    );

    test('captures startup failure once and preserves the exception', () async {
      final monitor = _FakeStartupMonitor();
      final failure = StateError('account initialization failed');

      await expectLater(
        runPomodoistStartup(
          loadMonitoringPolicy: () async => SentryRuntimePolicy.fromConfig(
            _config(environment: 'staging', release: release),
          ),
          loadRuntimeConfig: () async => throw failure,
          startApplication: (_) async => fail('must not start'),
          monitor: monitor,
        ),
        throwsA(same(failure)),
      );

      expect(monitor.runCount, 1);
      expect(monitor.captured, [same(failure)]);
    });
  });

  test(
    'SentryStartupMonitor captures one in-memory event and rethrows',
    () async {
      final transport = _RecordingTransport();
      final monitor = SentryStartupMonitor.testing(transport: transport);
      final policy = SentryRuntimePolicy.fromConfig(
        _config(environment: 'staging', release: release),
      );
      final failure = StateError('bootstrap failed without user data');
      final originalFlutterError = FlutterError.onError;
      final originalPlatformError = PlatformDispatcher.instance.onError;
      StackTrace? rethrownStack;

      try {
        await monitor.run(policy, () => _throwStartupFailure(failure));
        fail('monitor must preserve startup failure');
      } catch (error, stackTrace) {
        expect(error, same(failure));
        rethrownStack = stackTrace;
      } finally {
        await Sentry.close();
      }

      expect(rethrownStack.toString(), contains('_throwStartupFailure'));
      expect(FlutterError.onError, same(originalFlutterError));
      expect(PlatformDispatcher.instance.onError, same(originalPlatformError));
      expect(transport.envelopes, hasLength(1));
      final data = await transport.envelopes.single.items.single.dataFactory();
      final event = jsonDecode(utf8.decode(data)) as Map<String, Object?>;
      expect(event['environment'], 'staging');
      expect(event['release'], release);
      expect(event['dist'], 'staging');
      expect(event, isNot(contains('user')));
      expect(event, isNot(contains('request')));
      expect(jsonEncode(event), isNot(contains('anon-key')));
    },
  );

  group('CAPTCHA challenge privacy filter', () {
    const challengeUrl =
        'https://app-test.pomodoist.com/auth/challenge'
        '?returnTo=pomodoist%3A%2F%2Fcaptcha-callback#state=SECRET';
    final callbackUrl =
        'pomodoist://captcha-callback?state=${'A' * 43}&token=TOKEN_SECRET';

    test('detects nested challenge-route metadata without exposing values', () {
      expect(
        containsCaptchaChallengeMetadata({
          'request': {
            'url': challengeUrl,
            'headers': {'referer': challengeUrl},
          },
        }),
        isTrue,
      );
      expect(
        containsCaptchaChallengeMetadata({
          'request': {'url': 'https://app-test.pomodoist.com/today'},
        }),
        isFalse,
      );
    });

    test('drops challenge events and URL-bearing breadcrumbs', () {
      final event = SentryEvent(
        request: SentryRequest(url: challengeUrl),
        message: SentryMessage('Security page failed'),
      );
      final breadcrumb = Breadcrumb.http(
        url: Uri.parse(challengeUrl),
        method: 'GET',
      );

      expect(filterCaptchaChallengeEvent(event, Hint()), isNull);
      expect(filterCaptchaChallengeBreadcrumb(breadcrumb, Hint()), isNull);
    });

    test('drops token-bearing native callbacks from all Sentry metadata', () {
      final event = SentryEvent(
        request: SentryRequest(url: callbackUrl),
        message: SentryMessage('Native callback failed'),
      );
      final breadcrumb = Breadcrumb(
        message: callbackUrl,
        category: 'navigation',
      );

      expect(
        containsCaptchaChallengeMetadata({
          'transaction': callbackUrl,
          'breadcrumb': {'message': callbackUrl},
        }),
        isTrue,
      );
      expect(filterCaptchaChallengeEvent(event, Hint()), isNull);
      expect(filterCaptchaChallengeBreadcrumb(breadcrumb, Hint()), isNull);
    });

    test('preserves unrelated Sentry events and breadcrumbs', () {
      final event = SentryEvent(
        request: SentryRequest(url: 'https://app-test.pomodoist.com/today'),
      );
      final breadcrumb = Breadcrumb.http(
        url: Uri.parse('https://app-test.pomodoist.com/today'),
        method: 'GET',
      );

      expect(filterCaptchaChallengeEvent(event, Hint()), same(event));
      expect(
        filterCaptchaChallengeBreadcrumb(breadcrumb, Hint()),
        same(breadcrumb),
      );
    });
  });
}

Future<void> _throwStartupFailure(Object failure) async {
  await Future<void>.value();
  throw failure;
}

RuntimePublicConfig _config({
  required String environment,
  required String release,
  String sentryDsn = 'https://public@o12345.ingest.sentry.io/42',
}) {
  final local = environment == 'local';
  final production = environment == 'production';
  return RuntimePublicConfig.fromBuildTimeValues(
    environment: environment,
    release: release,
    webAppUrl: local
        ? 'http://127.0.0.1:7358'
        : production
        ? 'https://app.pomodoist.com'
        : 'https://app-test.pomodoist.com',
    supabaseUrl: local
        ? ''
        : production
        ? 'https://ewauihswbwduvklrozke.supabase.co'
        : 'https://supabase-test.pomodoist.com',
    supabaseAnonKey: local ? '' : 'public-anon-key',
    googleWebClientId: '',
    turnstileSiteKey: local ? '' : 'test-turnstile-site-key',
    sentryDsn: sentryDsn,
  );
}

class _FakeStartupMonitor implements StartupMonitor {
  int runCount = 0;
  final captured = <Object>[];

  @override
  Future<void> run(
    SentryRuntimePolicy policy,
    Future<void> Function() appRunner,
  ) async {
    runCount += 1;
    try {
      await appRunner();
    } catch (error) {
      captured.add(error);
      rethrow;
    }
  }
}

class _RecordingTransport implements Transport {
  final envelopes = <SentryEnvelope>[];

  @override
  Future<SentryId?> send(SentryEnvelope envelope) async {
    envelopes.add(envelope);
    return envelope.header.eventId;
  }
}
