import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/runtime_public_config.dart';
import 'package:pomodoist/app/runtime_public_config_loader_core.dart';

void main() {
  test('parses a preloaded window config through the public model', () {
    final config = parsePreloadedRuntimePublicConfig({
      'environment': 'staging',
      'release': '0123456789abcdef0123456789abcdef01234567',
      'webAppUrl': 'https://app-test.pomodoist.com',
      'supabaseUrl': 'https://supabase-test.pomodoist.com',
      'supabaseAnonKey': 'staging-anon-key',
      'googleWebClientId': '',
      'turnstileSiteKey': 'test-turnstile-site-key',
      'sentryDsn': '',
    });

    expect(config.environment, RuntimeEnvironment.staging);
    expect(config.supabaseUrl?.host, 'supabase-test.pomodoist.com');
  });

  test('rejects a non-object preloaded window config', () {
    expect(
      () => parsePreloadedRuntimePublicConfig(['not', 'an', 'object']),
      throwsFormatException,
    );
  });

  test('preloads config.js before the Flutter bootstrap', () async {
    final index = await File('web/index.html').readAsString();

    expect(index.indexOf('src="config.js"'), greaterThanOrEqualTo(0));
    expect(
      index.indexOf('src="config.js"'),
      lessThan(index.indexOf('src="flutter_bootstrap.js"')),
    );
  });
}
