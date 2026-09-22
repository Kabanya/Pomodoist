import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/app_environment.dart';
import 'package:pomodoist/config/runtime_public_config.dart';
import 'package:pomodoist/domain/models/app_flavor.dart';

const _release = '0123456789abcdef0123456789abcdef01234567';
const _uuidShape =
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';

void main() {
  group('AppFlavor identity table', () {
    test('development matches the frozen row', () {
      const flavor = AppFlavor.development;
      expect(flavor.displayName, 'Pomodoist Dev');
      expect(flavor.applicationId, 'com.finchforge.pomodoist.dev');
      expect(flavor.urlScheme, 'pomodoist-dev');
      expect(flavor.appGroup, 'group.com.pomodoist.dev');
      expect(flavor.entrypoint, 'lib/main_development.dart');
    });

    test('staging matches the frozen row', () {
      const flavor = AppFlavor.staging;
      expect(flavor.displayName, 'Pomodoist Stg');
      expect(flavor.applicationId, 'com.finchforge.pomodoist.stg');
      expect(flavor.urlScheme, 'pomodoist-stg');
      expect(flavor.appGroup, 'group.com.pomodoist.stg');
      expect(flavor.entrypoint, 'lib/main_staging.dart');
    });

    test('production matches the frozen row', () {
      const flavor = AppFlavor.production;
      expect(flavor.displayName, 'Pomodoist');
      expect(flavor.applicationId, 'com.finchforge.pomodoist');
      expect(flavor.urlScheme, 'pomodoist');
      expect(flavor.appGroup, 'group.com.pomodoist');
      expect(flavor.entrypoint, 'lib/main.dart');
    });

    test('isProduction is true only for the shipped flavor', () {
      expect(AppFlavor.production.isProduction, isTrue);
      expect(AppFlavor.staging.isProduction, isFalse);
      expect(AppFlavor.development.isProduction, isFalse);
    });

    test('has exactly three values', () {
      expect(AppFlavor.values, hasLength(3));
      expect(AppFlavor.values.map((flavor) => flavor.name), [
        'development',
        'staging',
        'production',
      ]);
    });
  });

  group('AppFlavor derived identifiers', () {
    test('development derives from its application id', () {
      const flavor = AppFlavor.development;
      expect(flavor.watchBundleId, 'com.finchforge.pomodoist.dev.watchkitapp');
      expect(
        flavor.watchTestsBundleId,
        'com.finchforge.pomodoist.dev.watchkitapp.tests',
      );
      expect(
        flavor.focusWidgetBundleId,
        'com.finchforge.pomodoist.dev.focuswidget',
      );
      expect(
        flavor.runnerTestsBundleId,
        'com.finchforge.pomodoist.dev.RunnerTests',
      );
    });

    test('staging derives from its application id', () {
      const flavor = AppFlavor.staging;
      expect(flavor.watchBundleId, 'com.finchforge.pomodoist.stg.watchkitapp');
      expect(
        flavor.watchTestsBundleId,
        'com.finchforge.pomodoist.stg.watchkitapp.tests',
      );
      expect(
        flavor.focusWidgetBundleId,
        'com.finchforge.pomodoist.stg.focuswidget',
      );
      expect(
        flavor.runnerTestsBundleId,
        'com.finchforge.pomodoist.stg.RunnerTests',
      );
    });

    test('production derives from its application id', () {
      const flavor = AppFlavor.production;
      expect(flavor.watchBundleId, 'com.finchforge.pomodoist.watchkitapp');
      expect(
        flavor.watchTestsBundleId,
        'com.finchforge.pomodoist.watchkitapp.tests',
      );
      expect(
        flavor.focusWidgetBundleId,
        'com.finchforge.pomodoist.focuswidget',
      );
      expect(
        flavor.runnerTestsBundleId,
        'com.finchforge.pomodoist.RunnerTests',
      );
    });
  });

  group('AppFlavor windows toast GUIDs', () {
    test('every flavor has a lowercase UUID-shaped GUID', () {
      final shape = RegExp(_uuidShape);
      for (final flavor in AppFlavor.values) {
        expect(flavor.windowsToastGuid, isNotEmpty, reason: flavor.name);
        expect(
          shape.hasMatch(flavor.windowsToastGuid),
          isTrue,
          reason: '${flavor.name}: ${flavor.windowsToastGuid}',
        );
      }
    });

    test('the GUIDs are distinct so notifications cannot cross builds', () {
      final guids = AppFlavor.values
          .map((flavor) => flavor.windowsToastGuid)
          .toSet();
      expect(guids, hasLength(AppFlavor.values.length));
    });

    test('production keeps the shipped activation GUID', () {
      expect(
        AppFlavor.production.windowsToastGuid,
        '8681f633-939c-46f5-84cc-18f295e4382c',
      );
      expect(
        AppFlavor.staging.windowsToastGuid,
        'b3c1d7a2-5e64-4f18-9a0b-2d7c6e1f8a34',
      );
      expect(
        AppFlavor.development.windowsToastGuid,
        'c4d2e8b3-6f75-4029-ab1c-3e8d7f209b45',
      );
    });
  });

  group('appFlavorFromName', () {
    test('accepts the three flavor names', () {
      expect(appFlavorFromName('development'), AppFlavor.development);
      expect(appFlavorFromName('staging'), AppFlavor.staging);
      expect(appFlavorFromName('production'), AppFlavor.production);
    });

    test('ignores case and surrounding whitespace', () {
      expect(appFlavorFromName('  Development '), AppFlavor.development);
      expect(appFlavorFromName('STAGING'), AppFlavor.staging);
      expect(appFlavorFromName('\tProduction\n'), AppFlavor.production);
    });

    test('returns null for empty and unknown names', () {
      expect(appFlavorFromName(''), isNull);
      expect(appFlavorFromName('   '), isNull);
      expect(appFlavorFromName('nonsense'), isNull);
      expect(appFlavorFromName('dev'), isNull);
    });
  });

  group('AppEnvironment.flavor', () {
    test('maps each environment to the flavor that ships it', () {
      expect(AppEnvironment.development.flavor, AppFlavor.development);
      expect(AppEnvironment.staging.flavor, AppFlavor.staging);
      expect(AppEnvironment.production.flavor, AppFlavor.production);
    });

    test('every environment has a distinct flavor', () {
      final flavors = AppEnvironment.values
          .map((environment) => environment.flavor)
          .toSet();
      expect(flavors, hasLength(AppEnvironment.values.length));
    });
  });

  group('validateEnvironment build-time flavor check', () {
    test('a plain flutter test run carries no compile-time flavor', () {
      expect(kBuildFlavorName, isEmpty);
      expect(buildTimeAppFlavor, isNull);
    });

    test('accepts a build with no flavor at all', () {
      for (final environment in AppEnvironment.values) {
        expect(
          () => validateEnvironment(
            appEnvironment: environment,
            config: _configFor(environment),
            isWeb: false,
          ),
          returnsNormally,
          reason: environment.name,
        );
      }
    });

    test('accepts a build flavor that agrees with the entry point', () {
      for (final environment in AppEnvironment.values) {
        expect(
          () => validateEnvironment(
            appEnvironment: environment,
            config: _configFor(environment),
            isWeb: false,
            buildFlavor: environment.flavor,
          ),
          returnsNormally,
          reason: environment.name,
        );
      }
    });

    test('rejects a build flavor that disagrees with the entry point', () {
      for (final environment in AppEnvironment.values) {
        for (final built in AppFlavor.values) {
          if (built == environment.flavor) continue;
          expect(
            () => validateEnvironment(
              appEnvironment: environment,
              config: _configFor(environment),
              isWeb: false,
              buildFlavor: built,
            ),
            throwsStateError,
            reason: '${environment.name} built as ${built.name}',
          );
        }
      }
    });

    test(
      'the error names the entry point, the expected and the actual flavor',
      () {
        expect(
          () => validateEnvironment(
            appEnvironment: AppEnvironment.development,
            config: _localConfig(),
            isWeb: false,
            buildFlavor: AppFlavor.staging,
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'Entrypoint/flavor mismatch: development entrypoint '
                  '(lib/main_development.dart) was built with --flavor staging. '
                  'Pass --flavor development.',
            ),
          ),
        );
      },
    );

    test('skips the check on the web', () {
      expect(
        () => validateEnvironment(
          appEnvironment: AppEnvironment.production,
          config: _productionConfig(),
          isWeb: true,
          buildFlavor: AppFlavor.development,
        ),
        returnsNormally,
      );
    });

    test('still rejects a mismatched runtime config', () {
      expect(
        () => validateEnvironment(
          appEnvironment: AppEnvironment.development,
          config: _productionConfig(),
          isWeb: false,
          buildFlavor: AppFlavor.development,
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

  group('appFlavor global', () {
    tearDown(() {
      setAppFlavor(buildTimeAppFlavor ?? AppFlavor.production);
    });

    test('defaults to the compile-time flavor, or production without one', () {
      expect(appFlavor, buildTimeAppFlavor ?? AppFlavor.production);
    });

    test('setAppFlavor replaces the value the running process reports', () {
      for (final flavor in AppFlavor.values) {
        setAppFlavor(flavor);
        expect(appFlavor, flavor);
      }
    });
  });
}

RuntimePublicConfig _configFor(AppEnvironment environment) =>
    switch (environment) {
      AppEnvironment.development => _localConfig(),
      AppEnvironment.staging => _stagingConfig(),
      AppEnvironment.production => _productionConfig(),
    };

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
