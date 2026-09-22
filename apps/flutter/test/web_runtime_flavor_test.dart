import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/app_environment.dart';
import 'package:pomodoist/config/bootstrap.dart';
import 'package:pomodoist/config/runtime_public_config.dart';
import 'package:pomodoist/config/runtime_public_config_loader_core.dart';
import 'package:pomodoist/domain/models/app_flavor.dart';

const _release = '0123456789abcdef0123456789abcdef01234567';

void main() {
  tearDown(() => setAppFlavor(buildTimeAppFlavor ?? AppFlavor.production));

  group('publishAppFlavor on the web', () {
    test('a staging deployment publishes the staging flavor', () {
      publishAppFlavor(
        appEnvironment: AppEnvironment.production,
        config: _stagingConfig(),
        isWeb: true,
      );

      expect(appFlavor, AppFlavor.staging);
    });

    test('production and self-hosted deployments publish production', () {
      publishAppFlavor(
        appEnvironment: AppEnvironment.production,
        config: _productionConfig(),
        isWeb: true,
      );
      expect(appFlavor, AppFlavor.production);

      publishAppFlavor(
        appEnvironment: AppEnvironment.production,
        config: _selfHostedConfig(),
        isWeb: true,
      );
      expect(appFlavor, AppFlavor.production);
    });

    test('local development publishes the development flavor', () {
      publishAppFlavor(
        appEnvironment: AppEnvironment.development,
        config: _localConfig(),
        isWeb: true,
      );

      expect(appFlavor, AppFlavor.development);
    });

    test('off the web the entry point publishes its own flavor', () {
      for (final environment in AppEnvironment.values) {
        publishAppFlavor(
          appEnvironment: environment,
          config: _configFor(environment),
          isWeb: false,
        );

        expect(appFlavor, environment.flavor, reason: environment.name);
      }
    });
  });

  group('bootstrap publishes the derived flavor', () {
    test('the entry point flavor is never published unconditionally', () async {
      final source = await File('lib/config/bootstrap.dart').readAsString();

      expect(
        source,
        isNot(contains('setAppFlavor(appEnvironment.flavor)')),
        reason: 'the web runtime flavor must survive bootstrap',
      );
      expect(source, contains('publishAppFlavor('));
    });
  });

  group('web entry point identity', () {
    test('every runtime environment resolves to the loader flavor', () async {
      final environments = _jsEntries(
        await _indexHtml(),
        'const environments = {',
      );

      for (final environment in RuntimeEnvironment.values) {
        expect(
          environments[environment.name],
          appFlavorForRuntimeEnvironment(environment).name,
          reason: environment.name,
        );
      }
    });

    test('each flavor names the manifest and icons the icons pipeline '
        'writes', () async {
      final index = await _indexHtml();

      for (final flavor in AppFlavor.values) {
        final entry = _jsEntries(index, '${flavor.name}: {');
        final manifest = entry['manifest']!;
        expect(await File('web/$manifest').exists(), isTrue, reason: manifest);

        final manifestJson =
            jsonDecode(await File('web/$manifest').readAsString())
                as Map<String, Object?>;
        expect(manifestJson['name'], flavor.displayName, reason: manifest);
        expect(
          manifestJson['short_name'],
          flavor.displayName,
          reason: manifest,
        );
        expect(manifestJson['description'], isNot('A new Flutter project.'));

        final icons = (manifestJson['icons']! as List).cast<Map>();
        final iconSources = icons
            .map((icon) => icon['src']! as String)
            .toSet();
        expect(
          iconSources,
          contains(entry['icon']),
          reason: '$manifest does not declare ${entry['icon']}',
        );
        for (final source in iconSources) {
          expect(await File('web/$source').exists(), isTrue, reason: source);
        }
        expect(await File('web/${entry['favicon']}').exists(), isTrue);
      }
    });

    test('the static default is the production identity, before JS runs',
        () async {
      final index = await _indexHtml();
      final manifest = _staticHref(index, 'manifest');
      final appleTouchIcon = _staticHref(index, 'apple-touch-icon');

      expect(manifest, 'manifest.json');
      final manifestJson =
          jsonDecode(await File('web/$manifest').readAsString())
              as Map<String, Object?>;
      final icons = (manifestJson['icons']! as List).cast<Map>();
      expect(
        icons.map((icon) => icon['src']),
        contains(appleTouchIcon),
        reason: 'the pre-JS apple-touch-icon must be the production icon',
      );
      expect(await File('web/$appleTouchIcon').exists(), isTrue);
    });
  });

  group('web runtime config delivery', () {
    test('the container replaces the local config.js marker', () async {
      final config = await File('web/config.js').readAsString();
      final entrypoint = await File(
        '../../tool/deploy/web/entrypoint.sh',
      ).readAsString();
      final dockerfile = await File(
        '../../tool/deploy/web/Dockerfile',
      ).readAsString();

      expect(config, contains("window.pomodoistBuildEnvironment = 'local';"));
      expect(
        entrypoint,
        contains(r'mv "$config_tmp" /usr/share/nginx/html/config.js'),
        reason: 'the deployed config.js is written at container start',
      );
      expect(
        dockerfile,
        contains('build/web/config.js'),
        reason: 'the built config.js must not ship in the image',
      );
    });

    test('the entry point prefers the deployed config over the marker',
        () async {
      final index = await _indexHtml();
      final readConfig = index.indexOf('config.environment');
      final readMarker = index.indexOf('window.pomodoistBuildEnvironment');

      expect(readConfig, greaterThanOrEqualTo(0));
      expect(readMarker, greaterThanOrEqualTo(0));
      expect(readConfig, lessThan(readMarker));
    });
  });
}

Future<String> _indexHtml() => File('web/index.html').readAsString();

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

RuntimePublicConfig _selfHostedConfig() => RuntimePublicConfig.fromRuntimeJson({
  'environment': 'selfhosted',
  'release': _release,
  'webAppUrl': 'http://localhost:58080',
  'supabaseUrl': 'http://localhost:55421',
  'supabaseAnonKey': 'public-anon-key',
  'turnstileSiteKey': '',
  'sentryDsn': '',
});

/// Reads the `key: value` pairs of a single-quoted object literal in
/// `web/index.html`, starting at [declaration].
///
/// The entry point chooses the deployment's identity in plain JavaScript
/// before Flutter starts, so the only way to check it agrees with the Dart
/// flavor table is to read the served file.
Map<String, String> _jsEntries(String source, String declaration) {
  final body = _jsObject(source, declaration);
  return {
    for (final match in RegExp(r"(\w+)\s*:\s*'([^']*)'").allMatches(body))
      match.group(1)!: match.group(2)!,
  };
}

String _jsObject(String source, String declaration) {
  final start = source.indexOf(declaration);
  expect(start, greaterThanOrEqualTo(0), reason: declaration);
  final open = source.indexOf('{', start);
  var depth = 0;
  for (var index = open; index < source.length; index++) {
    switch (source[index]) {
      case '{':
        depth++;
      case '}':
        depth--;
        if (depth == 0) return source.substring(open + 1, index);
    }
  }
  fail('unterminated object literal after $declaration');
}

/// Reads the `href` of the static `<link rel="...">` element in the document
/// head, which is what a browser uses before the scripts run.
String _staticHref(String source, String rel) {
  final match = RegExp('<link rel="$rel" href="([^"]+)">').firstMatch(source);
  expect(match, isNotNull, reason: 'no static <link rel="$rel"> in web/index.html');
  return match!.group(1)!;
}
