import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/runtime_public_config.dart';

const _release = '0123456789abcdef0123456789abcdef01234567';

void main() {
  group('RuntimePublicConfig', () {
    test('accepts exactly the public staging fields', () {
      final config = RuntimePublicConfig.fromRuntimeJson(_stagingConfig());

      expect(config.environment, RuntimeEnvironment.staging);
      expect(config.release, _release);
      expect(config.webAppUrl, Uri.parse('https://app-test.pomodoist.com'));
      expect(
        config.supabaseUrl,
        Uri.parse('https://supabase-test.pomodoist.com'),
      );
      expect(config.supabaseAnonKey, 'staging-anon-key');
      expect(config.turnstileSiteKey, 'turnstile-public-key');
      expect(
        config.sentryDsn,
        Uri.parse('https://public@o12345.ingest.sentry.io/42'),
      );
      expect(config.toJson().keys.toSet(), {
        'environment',
        'release',
        'webAppUrl',
        'supabaseUrl',
        'supabaseAnonKey',
        'turnstileSiteKey',
        'sentryDsn',
      });
    });

    test('accepts production with the approved Supabase Cloud host', () {
      final config = RuntimePublicConfig.fromRuntimeJson({
        ..._stagingConfig(),
        'environment': 'production',
        'webAppUrl': 'https://app.pomodoist.com',
        'supabaseUrl': 'https://ewauihswbwduvklrozke.supabase.co',
      });

      expect(config.environment, RuntimeEnvironment.production);
    });

    test('rejects arbitrary staging and production Supabase hosts', () {
      expect(
        () => RuntimePublicConfig.fromRuntimeJson({
          ..._stagingConfig(),
          'supabaseUrl': 'https://staging-attacker.example.com',
        }),
        throwsFormatException,
      );
      expect(
        () => RuntimePublicConfig.fromRuntimeJson({
          ..._stagingConfig(),
          'environment': 'production',
          'webAppUrl': 'https://app.pomodoist.com',
          'supabaseUrl': 'https://attacker.supabase.co',
        }),
        throwsFormatException,
      );
    });

    test('rejects local or unknown container environments', () {
      for (final environment in ['local', 'xubuntu', 'preview']) {
        expect(
          () => RuntimePublicConfig.fromRuntimeJson({
            ..._stagingConfig(),
            'environment': environment,
          }),
          throwsFormatException,
          reason: environment,
        );
      }
    });

    test('requires a full immutable release SHA', () {
      expect(
        () => RuntimePublicConfig.fromRuntimeJson({
          ..._stagingConfig(),
          'release': 'cab9595',
        }),
        throwsFormatException,
      );
    });

    test('requires HTTPS for remote URLs', () {
      for (final entry in {
        'webAppUrl': 'http://app-test.pomodoist.com',
        'supabaseUrl': 'http://supabase-test.pomodoist.com',
      }.entries) {
        expect(
          () => RuntimePublicConfig.fromRuntimeJson({
            ..._stagingConfig(),
            entry.key: entry.value,
          }),
          throwsFormatException,
          reason: entry.key,
        );
      }
    });

    test('requires a public Turnstile site key for remote environments', () {
      expect(
        () => RuntimePublicConfig.fromRuntimeJson({
          ..._stagingConfig(),
          'turnstileSiteKey': '',
        }),
        throwsFormatException,
      );
    });

    test('accepts an explicit Sentry Cloud DSN', () {
      final config = RuntimePublicConfig.fromRuntimeJson({
        ..._stagingConfig(),
        'sentryDsn': 'https://public123@o0.ingest.sentry.io/987654',
      });

      expect(
        config.sentryDsn,
        Uri.parse('https://public123@o0.ingest.sentry.io/987654'),
      );
    });

    test('rejects malformed and unsupported Sentry DSNs', () {
      for (final sentryDsn in [
        'http://public@o123.ingest.sentry.io/42',
        'https://?token',
        'https://o123.ingest.sentry.io/42',
        'https://public:secret@o123.ingest.sentry.io/42',
        'https://public@example.ingest.sentry.io/42',
        'https://public@o123.ingest.us.sentry.io/42',
        'https://public@o123.ingest.sentry.io/project',
        'https://public@o123.ingest.sentry.io/42/more',
        'https://public@o123.ingest.sentry.io:8443/42',
        'https://public@sentry.example.test/42',
        'https://evil.example/1\nhttps://public@o123.ingest.sentry.io/42',
        'https://evil.example/1\rhttps://public@o123.ingest.sentry.io/42',
        'https://evil.example/1\r\nhttps://public@o123.ingest.sentry.io/42',
        'https://public@o123.ingest.sentry.io/42\nignored',
        'https://public@o123.ingest.sentry.io/42\tignored',
      ]) {
        expect(
          () => RuntimePublicConfig.fromRuntimeJson({
            ..._stagingConfig(),
            'sentryDsn': sentryDsn,
          }),
          throwsFormatException,
          reason: sentryDsn,
        );
      }
    });

    test('requires all non-optional public fields', () {
      for (final field in [
        'environment',
        'release',
        'webAppUrl',
        'supabaseUrl',
        'supabaseAnonKey',
      ]) {
        final json = _stagingConfig()..remove(field);
        expect(
          () => RuntimePublicConfig.fromRuntimeJson(json),
          throwsFormatException,
          reason: field,
        );
      }
    });

    test('rejects unexpected and server-secret fields', () {
      for (final field in [
        'SUPABASE_SERVICE_ROLE_KEY',
        'databasePassword',
        'featureFlag',
      ]) {
        expect(
          () => RuntimePublicConfig.fromRuntimeJson({
            ..._stagingConfig(),
            field: 'must-not-be-public',
          }),
          throwsFormatException,
          reason: field,
        );
      }
    });

    test('rejects staging and production domain mismatches', () {
      expect(
        () => RuntimePublicConfig.fromRuntimeJson({
          ..._stagingConfig(),
          'webAppUrl': 'https://app.pomodoist.com',
        }),
        throwsFormatException,
      );
      expect(
        () => RuntimePublicConfig.fromRuntimeJson({
          ..._stagingConfig(),
          'environment': 'production',
          'webAppUrl': 'https://app.pomodoist.com',
          'supabaseUrl': 'https://supabase-test.pomodoist.com',
        }),
        throwsFormatException,
      );
    });

    test('build-time local config may be unconfigured and use HTTP', () {
      final config = RuntimePublicConfig.fromBuildTimeValues(
        environment: 'local',
        release: _release,
        webAppUrl: 'http://127.0.0.1:7358',
        supabaseUrl: '',
        supabaseAnonKey: '',
        turnstileSiteKey: '',
        sentryDsn: '',
      );

      expect(config.environment, RuntimeEnvironment.local);
      expect(config.supabaseUrl, isNull);
      expect(config.sentryDsn, isNull);
    });

    test('native release falls back to the production Supabase client', () {
      final config = RuntimePublicConfig.fromBuildTimeValues(
        environment: 'local',
        release: 'development',
        webAppUrl: 'http://127.0.0.1:7358',
        supabaseUrl: '',
        supabaseAnonKey: '',
        turnstileSiteKey: '',
        sentryDsn: '',
        nativeRelease: true,
      );

      expect(
        config.supabaseUrl,
        Uri.parse('https://ewauihswbwduvklrozke.supabase.co'),
      );
      expect(config.supabaseAnonKey, startsWith('sb_publishable_'));
    });
  });
}

Map<String, Object?> _stagingConfig() => {
  'environment': 'staging',
  'release': _release,
  'webAppUrl': 'https://app-test.pomodoist.com',
  'supabaseUrl': 'https://supabase-test.pomodoist.com',
  'supabaseAnonKey': 'staging-anon-key',
  'turnstileSiteKey': 'turnstile-public-key',
  'sentryDsn': 'https://public@o12345.ingest.sentry.io/42',
};
