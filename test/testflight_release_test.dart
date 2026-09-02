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
      'testflight-ios',
      'ASC_KEY_ID=test',
      'ASC_ISSUER_ID=test',
      'ASC_KEY_PATH=pubspec.yaml',
      'TESTFLIGHT_CONFIG=pubspec.yaml',
    ]);
    expect(result.exitCode, 0, reason: result.stderr.toString());

    final output = result.stdout.toString();
    expect(output, contains('flutter build ipa --release'));
    expect(output, isNot(contains('--build-number=')));
    expect(output, contains('--dart-define-from-file="pubspec.yaml"'));
    expect(output, contains('--dart-define=POMODOIST_RELEASE='));
    expect(
      output,
      contains('--dart-define=POMODOIST_BILLING_CHANNEL=storekit'),
    );
    expect(output, isNot(contains('GOOGLE_CLIENT_ID')));
    expect(output, isNot(contains('flutter build ios')));
    expect(
      output.indexOf('altool --upload-app'),
      greaterThan(output.indexOf('altool --validate-app')),
    );
  });

  test('macOS release build uses the production runtime config', () async {
    if (Platform.isWindows) return;

    final result = await Process.run('make', [
      '-n',
      'macos-release',
      'TESTFLIGHT_CONFIG=pubspec.yaml',
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
    expect(output, isNot(contains('GOOGLE_DESKTOP_CLIENT')));
  });

  test('TestFlight macOS exports and uploads a distribution package', () async {
    if (Platform.isWindows) return;

    final result = await Process.run('make', [
      '-n',
      'testflight-macos',
      'ASC_KEY_ID=test',
      'ASC_ISSUER_ID=test',
      'ASC_KEY_PATH=pubspec.yaml',
      'TESTFLIGHT_CONFIG=pubspec.yaml',
    ]);
    expect(result.exitCode, 0, reason: result.stderr.toString());

    final output = result.stdout.toString();
    expect(output, contains('flutter build macos --release'));
    expect(output, isNot(contains('--build-number=')));
    expect(output, contains('--dart-define-from-file="pubspec.yaml"'));
    expect(output, contains('--dart-define=POMODOIST_RELEASE='));
    expect(output, contains('xcodebuild -workspace'));
    expect(output, contains(' archive \\'));
    expect(output, contains('xcodebuild -exportArchive'));
    expect(output, contains('-hideShellScriptEnvironment'));
    expect(output, contains('-allowProvisioningUpdates'));
    expect(
      output,
      contains('-authenticationKeyPath "${Directory.current.path}/pubspec.yaml"'),
    );
    expect(output, contains('altool --validate-app'));
    expect(output, contains('altool --upload-app'));
    expect(output, contains('pomodoist.pkg'));
    expect(output, isNot(contains('ditto -c -k --keepParent')));
    expect(output, contains('--type macos'));
    expect(
      output.indexOf('altool --upload-app'),
      greaterThan(output.indexOf('xcodebuild -exportArchive')),
    );
  });

  test('TestFlight meta-target runs the iOS and macOS uploads', () async {
    if (Platform.isWindows) return;

    final result = await Process.run('make', [
      '-n',
      'testflight',
      'ASC_KEY_ID=test',
      'ASC_ISSUER_ID=test',
      'ASC_KEY_PATH=pubspec.yaml',
      'TESTFLIGHT_CONFIG=pubspec.yaml',
    ]);
    expect(result.exitCode, 0, reason: result.stderr.toString());

    final output = result.stdout.toString();
    expect(output, contains('flutter build ipa --release'));
    expect(output, contains('flutter build macos --release'));
    expect(output, isNot(contains('--build-number=')));
    expect(output, contains('altool --upload-app'));
    expect(output, contains('--type macos'));
  });
}
