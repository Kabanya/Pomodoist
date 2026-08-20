import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'TestFlight preflight accepts only a production client config',
    () async {
      if (Platform.isWindows) return;

      final directory = await Directory.systemTemp.createTemp(
        'testflight-env-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final config = File('${directory.path}/production.env');

      Future<ProcessResult> check(String role) async {
        final payload = base64Url
            .encode(utf8.encode(jsonEncode({'role': role})))
            .replaceAll('=', '');
        await config.writeAsString('''
POMODOIST_ENVIRONMENT=production
WEB_APP_URL=https://app.pomodoist.com
POMODOIST_REGISTRATION_URL=https://app.pomodoist.com/auth/challenge
SUPABASE_URL=https://ewauihswbwduvklrozke.supabase.co
SUPABASE_ANON_KEY=header.$payload.signature
GOOGLE_WEB_CLIENT_ID=client.apps.googleusercontent.com
TURNSTILE_SITE_KEY=public-site-key
SENTRY_DSN=
''');
        return Process.run('python3', [
          'tool/check_testflight_env.py',
          config.path,
        ]);
      }

      expect((await check('anon')).exitCode, 0);
      expect((await check('service_role')).exitCode, isNot(0));
    },
  );

  test('TestFlight builds one fully configured IPA before upload', () async {
    if (Platform.isWindows) return;

    final result = await Process.run('make', [
      '-n',
      'testflight',
      'ASC_KEY_ID=test',
      'ASC_ISSUER_ID=test',
      'ASC_KEY_PATH=pubspec.yaml',
      'TESTFLIGHT_CONFIG=pubspec.yaml',
      'GOOGLE_CLIENT_ID=ios.apps.googleusercontent.com',
      'GOOGLE_REVERSED_CLIENT_ID=com.googleusercontent.apps.ios',
    ]);
    expect(result.exitCode, 0, reason: result.stderr.toString());

    final output = result.stdout.toString();
    expect(output, contains('flutter build ipa --release'));
    expect(output, contains('--dart-define-from-file="pubspec.yaml"'));
    expect(output, contains('--dart-define=POMODOIST_RELEASE='));
    expect(
      output,
      contains('--dart-define=POMODOIST_BILLING_CHANNEL=storekit'),
    );
    expect(
      output,
      contains(
        '--dart-define=GOOGLE_CLIENT_ID="ios.apps.googleusercontent.com"',
      ),
    );
    expect(output, isNot(contains('flutter build ios')));
    expect(
      output.indexOf('altool --upload-app'),
      greaterThan(output.indexOf('altool --validate-app')),
    );
  });

  test('macOS OAuth preflight rejects a missing client secret', () async {
    if (Platform.isWindows) return;

    Future<ProcessResult> check(String secret) => Process.run('make', [
      '-s',
      'macos-oauth-check',
      'GOOGLE_DESKTOP_CLIENT_ID=desktop.apps.googleusercontent.com',
      'GOOGLE_DESKTOP_CLIENT_SECRET=$secret',
    ]);

    expect((await check('')).exitCode, isNot(0));
    expect((await check('desktop-secret')).exitCode, 0);
  });

  test('macOS release build uses the production runtime config', () async {
    if (Platform.isWindows) return;

    final result = await Process.run('make', [
      '-n',
      'build-macos-release',
      'TESTFLIGHT_CONFIG=pubspec.yaml',
      'GOOGLE_DESKTOP_CLIENT_ID=desktop.apps.googleusercontent.com',
      'GOOGLE_DESKTOP_CLIENT_SECRET=desktop-secret',
    ]);
    expect(result.exitCode, 0, reason: result.stderr.toString());

    final output = result.stdout.toString();
    expect(output, contains('flutter build macos --release'));
    expect(output, contains('--dart-define-from-file="pubspec.yaml"'));
    expect(output, contains('--dart-define=POMODOIST_RELEASE='));
    expect(
      output,
      contains('--dart-define=POMODOIST_BILLING_CHANNEL=storekit'),
    );
    expect(
      output,
      contains(
        '--dart-define=GOOGLE_DESKTOP_CLIENT_ID="desktop.apps.googleusercontent.com"',
      ),
    );
    expect(
      output,
      contains('--dart-define=GOOGLE_DESKTOP_CLIENT_SECRET="desktop-secret"'),
    );
  });
}
