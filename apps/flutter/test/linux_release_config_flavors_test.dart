import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Pins the configurations the Linux AppImage release builds are validated from.
///
/// `.github/workflows/linux-appimage-release.yml` writes one JSON configuration
/// per flavor and `make linux-release` validates it before Flutter starts, so
/// the validator has to accept the development and staging shapes as well as
/// the production one — while still refusing a development or staging artifact
/// that is pointed at the production backend.
void main() {
  test('accepts the development configuration the workflow writes', () {
    final result = _validate(_developmentConfig());

    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(result.stdout.toString(), contains('valid'));
    expect(
      result.stdout.toString(),
      isNot(contains('production')),
      reason: 'the result message must not name an environment',
    );
  });

  test('accepts a development configuration with its backend configured', () {
    final result = _validate({
      ..._developmentConfig(),
      'WEB_APP_URL': 'https://dev.pomodoist.com',
      'SUPABASE_URL': 'https://dev-project.supabase.co',
      'SUPABASE_ANON_KEY': 'public-anon-key',
      'TURNSTILE_SITE_KEY': '1x00000000000000000000AA',
      'SENTRY_DSN': 'https://abc123@o1.ingest.sentry.io/42',
    });

    expect(result.exitCode, 0, reason: result.stderr.toString());
  });

  test('accepts the staging configuration the workflow writes', () {
    final result = _validate(_stagingConfig());

    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(result.stdout.toString(), contains('valid'));
  });

  test('rejects a development configuration pointed at the production '
      'backend', () {
    final webApp = _validate({
      ..._developmentConfig(),
      'WEB_APP_URL': 'https://app.pomodoist.com',
    });
    final supabase = _validate({
      ..._developmentConfig(),
      'SUPABASE_URL': 'https://ewauihswbwduvklrozke.supabase.co',
      'SUPABASE_ANON_KEY': 'public-anon-key',
    });

    expect(webApp.exitCode, 64, reason: webApp.stderr.toString());
    expect(supabase.exitCode, 64, reason: supabase.stderr.toString());
  });

  test('rejects a development Supabase pair that is only half supplied', () {
    final result = _validate({
      ..._developmentConfig(),
      'SUPABASE_URL': 'https://dev-project.supabase.co',
    });

    expect(result.exitCode, 64, reason: result.stderr.toString());
  });

  test('rejects the literal development environment', () {
    final result = _validate({
      ..._developmentConfig(),
      'POMODOIST_ENVIRONMENT': 'development',
    });

    expect(result.exitCode, 64);
    expect(
      result.stderr.toString(),
      contains('local'),
      reason: 'the message must name the environment the flavor declares',
    );
  });

  test('rejects an environment the runtime does not know', () {
    final result = _validate({
      ..._developmentConfig(),
      'POMODOIST_ENVIRONMENT': 'preview',
    });

    expect(result.exitCode, 64);
  });

  test('rejects a staging configuration pointed at the production domains', () {
    final webApp = _validate({
      ..._stagingConfig(),
      'WEB_APP_URL': 'https://app.pomodoist.com',
      'POMODOIST_REGISTRATION_URL': 'https://app.pomodoist.com/auth/challenge',
    });
    final supabase = _validate({
      ..._stagingConfig(),
      'SUPABASE_URL': 'https://ewauihswbwduvklrozke.supabase.co',
    });

    expect(webApp.exitCode, 64, reason: webApp.stderr.toString());
    expect(supabase.exitCode, 64, reason: supabase.stderr.toString());
  });

  test('rejects a staging configuration without the Turnstile key', () {
    final result = _validate({..._stagingConfig(), 'TURNSTILE_SITE_KEY': ''});

    expect(result.exitCode, 64, reason: result.stderr.toString());
  });
}

Map<String, Object?> _developmentConfig() => {
  'POMODOIST_ENVIRONMENT': 'local',
  'WEB_APP_URL': 'https://dev.pomodoist.com',
  'POMODOIST_REGISTRATION_URL': '',
  'SUPABASE_URL': '',
  'SUPABASE_ANON_KEY': '',
  'TURNSTILE_SITE_KEY': '',
  'SENTRY_DSN': '',
};

Map<String, Object?> _stagingConfig() => {
  'POMODOIST_ENVIRONMENT': 'staging',
  'WEB_APP_URL': 'https://app-test.pomodoist.com',
  'POMODOIST_REGISTRATION_URL': 'https://app-test.pomodoist.com/auth/challenge',
  'SUPABASE_URL': 'https://supabase-test.pomodoist.com',
  'SUPABASE_ANON_KEY': 'public-anon-key',
  'TURNSTILE_SITE_KEY': '1x00000000000000000000AA',
  'SENTRY_DSN': '',
};

ProcessResult _validate(Map<String, Object?> config) {
  final directory = Directory.systemTemp.createTempSync(
    'pomodoist-linux-release-config-',
  );
  try {
    final configFile = File('${directory.path}/linux-flavor.json')
      ..writeAsStringSync(jsonEncode(config));
    return Process.runSync(_dartExecutable(), [
      '../../tool/desktop_release_config.dart',
      '--config',
      configFile.path,
    ], workingDirectory: Directory.current.path);
  } finally {
    directory.deleteSync(recursive: true);
  }
}

String _dartExecutable() {
  final pinned = File('../../.fvm/flutter_sdk/bin/dart');
  return pinned.existsSync() ? pinned.absolute.path : 'dart';
}
