import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepts a complete public production desktop configuration', () {
    final result = _validateConfig(_validConfig());

    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(result.stdout.toString(), contains('valid'));
  });

  for (final scenario in <({String name, Map<String, Object?> config})>[
    (
      name: 'non-production environment',
      config: _validConfig()..['POMODOIST_ENVIRONMENT'] = 'staging',
    ),
    (
      name: 'wrong challenge URL',
      config: _validConfig()
        ..['POMODOIST_REGISTRATION_URL'] =
            'https://evil.example/auth/challenge',
    ),
    (
      name: 'missing Turnstile site key',
      config: _validConfig()..['TURNSTILE_SITE_KEY'] = '',
    ),
    (
      name: 'Cloudflare test site key',
      config: _validConfig()
        ..['TURNSTILE_SITE_KEY'] = '1x00000000000000000000AA',
    ),
    (
      name: 'Supabase secret key in a public desktop artifact',
      config: _validConfig()
        ..['SUPABASE_SECRET_KEY'] = 'fixture-secret-must-never-ship',
    ),
    (
      name: 'case-changed legacy Supabase service role key',
      config: _validConfig()
        ..['supabase_service_role_key'] = 'legacy-sensitive-jwt',
    ),
    (
      name: 'non-production Supabase URL',
      config: _validConfig()
        ..['SUPABASE_URL'] = 'https://supabase-test.pomodoist.com'
        ..['SUPABASE_ANON_KEY'] = 'sb_publishable_public-test-value',
    ),
  ]) {
    test('rejects ${scenario.name} without echoing config values', () {
      final result = _validateConfig(scenario.config);

      expect(result.exitCode, 64);
      expect(result.stderr.toString(), isNot(contains('evil.example')));
      expect(result.stderr.toString(), isNot(contains('1x000000')));
      expect(result.stderr.toString(), isNot(contains('fixture-secret')));
      expect(result.stderr.toString(), isNot(contains('legacy-sensitive')));
      expect(
        result.stderr.toString(),
        isNot(contains('supabase-test.pomodoist.com')),
      );
    });
  }
}

Map<String, Object?> _validConfig() => {
  'POMODOIST_ENVIRONMENT': 'production',
  'WEB_APP_URL': 'https://app.pomodoist.com',
  'POMODOIST_REGISTRATION_URL': 'https://app.pomodoist.com/auth/challenge',
  'TURNSTILE_SITE_KEY': '0x4AAAAAAAabcdefghijklmnopqrstuv',
  'SENTRY_DSN': '',
};

ProcessResult _validateConfig(Map<String, Object?> config) {
  final directory = Directory.systemTemp.createTempSync(
    'pomodoist-desktop-config-',
  );
  try {
    final configFile = File('${directory.path}/production.json')
      ..writeAsStringSync(jsonEncode(config));
    return Process.runSync(_dartExecutable(), [
      'run',
      'tool/desktop_release_config.dart',
      '--config',
      configFile.path,
    ], workingDirectory: Directory.current.path);
  } finally {
    directory.deleteSync(recursive: true);
  }
}

String _dartExecutable() {
  final pinned = File('.fvm/flutter_sdk/bin/dart');
  return pinned.existsSync() ? pinned.absolute.path : 'dart';
}
