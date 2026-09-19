import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/app_environment.dart';
import 'package:pomodoist/config/runtime_public_config.dart';

const _release = '0123456789abcdef0123456789abcdef01234567';

void main() {
  group('validateEnvironment', () {
    test('development accepts local', () {
      expect(
        () => validateEnvironment(
          appEnvironment: AppEnvironment.development,
          config: _localConfig(),
          isWeb: false,
        ),
        returnsNormally,
      );
    });

    test('development rejects every remote environment', () {
      for (final config in [
        _stagingConfig(),
        _productionConfig(),
        _selfhosted(),
      ]) {
        expect(
          () => validateEnvironment(
            appEnvironment: AppEnvironment.development,
            config: config,
            isWeb: false,
          ),
          throwsStateError,
          reason: config.environment.name,
        );
      }
    });

    test('staging accepts staging', () {
      expect(
        () => validateEnvironment(
          appEnvironment: AppEnvironment.staging,
          config: _stagingConfig(),
          isWeb: false,
        ),
        returnsNormally,
      );
    });

    test('staging rejects local and production', () {
      for (final config in [_localConfig(), _productionConfig()]) {
        expect(
          () => validateEnvironment(
            appEnvironment: AppEnvironment.staging,
            config: config,
            isWeb: false,
          ),
          throwsStateError,
          reason: config.environment.name,
        );
      }
    });

    test('production accepts production and selfhosted', () {
      for (final config in [_productionConfig(), _selfhosted()]) {
        expect(
          () => validateEnvironment(
            appEnvironment: AppEnvironment.production,
            config: config,
            isWeb: false,
          ),
          returnsNormally,
          reason: config.environment.name,
        );
      }
    });

    test('production rejects local and staging off the web', () {
      for (final config in [_localConfig(), _stagingConfig()]) {
        expect(
          () => validateEnvironment(
            appEnvironment: AppEnvironment.production,
            config: config,
            isWeb: false,
          ),
          throwsStateError,
          reason: config.environment.name,
        );
      }
    });

    test('production accepts the staging container on the web', () {
      expect(
        () => validateEnvironment(
          appEnvironment: AppEnvironment.production,
          config: _stagingConfig(),
          isWeb: true,
        ),
        returnsNormally,
      );
    });

    test('production still rejects local on the web', () {
      expect(
        () => validateEnvironment(
          appEnvironment: AppEnvironment.production,
          config: _localConfig(),
          isWeb: true,
        ),
        throwsStateError,
      );
    });

    test('the error names the entry point and the configured environment', () {
      expect(
        () => validateEnvironment(
          appEnvironment: AppEnvironment.development,
          config: _productionConfig(),
          isWeb: false,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Entrypoint/config mismatch: development / production',
          ),
        ),
      );
    });
  });
}

RuntimePublicConfig _localConfig() => RuntimePublicConfig.fromBuildTimeValues(
  environment: 'local',
  release: _release,
  webAppUrl: 'http://127.0.0.1:7358',
  supabaseUrl: '',
  supabaseAnonKey: '',
  turnstileSiteKey: '',
  sentryDsn: '',
);

RuntimePublicConfig _stagingConfig() => RuntimePublicConfig.fromRuntimeJson({
  'environment': 'staging',
  'release': _release,
  'webAppUrl': 'https://app-test.pomodoist.com',
  'supabaseUrl': 'https://supabase-test.pomodoist.com',
  'supabaseAnonKey': 'staging-anon-key',
  'turnstileSiteKey': 'turnstile-public-key',
  'sentryDsn': '',
});

RuntimePublicConfig _productionConfig() => RuntimePublicConfig.fromRuntimeJson({
  'environment': 'production',
  'release': _release,
  'webAppUrl': 'https://app.pomodoist.com',
  'supabaseUrl': 'https://ewauihswbwduvklrozke.supabase.co',
  'supabaseAnonKey': 'production-anon-key',
  'turnstileSiteKey': 'turnstile-public-key',
  'sentryDsn': '',
});

RuntimePublicConfig _selfhosted() => RuntimePublicConfig.fromRuntimeJson({
  'environment': 'selfhosted',
  'release': _release,
  'webAppUrl': 'https://tasks.example.com',
  'supabaseUrl': 'https://api.example.com',
  'supabaseAnonKey': 'selfhosted-anon-key',
  'turnstileSiteKey': '',
  'sentryDsn': '',
});
