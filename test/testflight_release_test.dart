import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native Google OAuth preflight rejects incomplete configs', () async {
    final directory = await Directory.systemTemp.createTemp('google-oauth-');
    addTearDown(() => directory.delete(recursive: true));
    final config = File('${directory.path}/GoogleOAuth.xcconfig');

    Future<int> check(String target, String variable, String contents) async {
      await config.writeAsString(contents);
      return (await Process.run('make', [
        target,
        '$variable=${config.path}',
      ])).exitCode;
    }

    const iosId = 'ios.apps.googleusercontent.com';
    const reversedIosId = 'com.googleusercontent.apps.ios';
    expect(
      await check(
        'ios-oauth-check',
        'IOS_GOOGLE_OAUTH_CONFIG',
        'GOOGLE_CLIENT_ID = $iosId\n'
            'GOOGLE_REVERSED_CLIENT_ID = $reversedIosId\n',
      ),
      0,
    );
    expect(
      await check(
        'ios-oauth-check',
        'IOS_GOOGLE_OAUTH_CONFIG',
        'GOOGLE_CLIENT_ID =\nGOOGLE_REVERSED_CLIENT_ID = $reversedIosId\n',
      ),
      isNot(0),
    );
    expect(
      await check(
        'ios-oauth-check',
        'IOS_GOOGLE_OAUTH_CONFIG',
        'GOOGLE_CLIENT_ID = $iosId\nGOOGLE_REVERSED_CLIENT_ID =\n',
      ),
      isNot(0),
    );
    expect(
      await check(
        'ios-oauth-check',
        'IOS_GOOGLE_OAUTH_CONFIG',
        'GOOGLE_CLIENT_ID = $iosId\n'
            'GOOGLE_REVERSED_CLIENT_ID = com.googleusercontent.apps.wrong\n',
      ),
      isNot(0),
    );

    expect(
      await check(
        'macos-oauth-check',
        'MACOS_GOOGLE_OAUTH_CONFIG',
        'GOOGLE_DESKTOP_CLIENT_ID = desktop.apps.googleusercontent.com\n'
            'GOOGLE_DESKTOP_CLIENT_SECRET = secret\n',
      ),
      0,
    );
    expect(
      await check(
        'macos-oauth-check',
        'MACOS_GOOGLE_OAUTH_CONFIG',
        'GOOGLE_DESKTOP_CLIENT_ID =\n'
            'GOOGLE_DESKTOP_CLIENT_SECRET = secret\n',
      ),
      isNot(0),
    );
    expect(
      await check(
        'macos-oauth-check',
        'MACOS_GOOGLE_OAUTH_CONFIG',
        'GOOGLE_DESKTOP_CLIENT_ID = desktop.apps.googleusercontent.com\n'
            'GOOGLE_DESKTOP_CLIENT_SECRET =\n',
      ),
      isNot(0),
    );
  });

  test(
    'TestFlight preflight accepts only a production client config',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'testflight-env-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final config = File('${directory.path}/production.env');

      Future<ProcessResult> check(
        String role, {
        bool includeRegistrationUrl = true,
      }) async {
        final payload = base64Url
            .encode(utf8.encode(jsonEncode({'role': role})))
            .replaceAll('=', '');
        await config.writeAsString('''
POMODOIST_ENVIRONMENT=production
WEB_APP_URL=https://app.pomodoist.com
${includeRegistrationUrl ? 'POMODOIST_REGISTRATION_URL=https://app.pomodoist.com/auth/challenge' : ''}
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
      expect(
        (await check('anon', includeRegistrationUrl: false)).exitCode,
        isNot(0),
      );
      expect((await check('service_role')).exitCode, isNot(0));
    },
  );

  test(
    'TestFlight builds, validates, and uploads one configured IPA',
    () async {
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
      expect(
        output,
        contains('--export-options-plist="ios/ExportOptions.plist"'),
      );
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
      expect(output, isNot(contains('xcodebuild -workspace')));

      final validate = output.indexOf('altool --validate-app');
      final upload = output.indexOf('altool --upload-app');
      expect(validate, greaterThanOrEqualTo(0));
      expect(upload, greaterThan(validate));
      expect(output, contains('build/ios/ipa/Pomodoist.ipa'));
    },
  );

  test(
    'macOS App Store builds, exports, validates, and uploads one PKG',
    () async {
      final result = await Process.run('make', [
        '-n',
        'mac-app-store',
        'ASC_KEY_ID=test',
        'ASC_ISSUER_ID=test',
        'ASC_KEY_PATH=pubspec.yaml',
        'TESTFLIGHT_CONFIG=pubspec.yaml',
        'GOOGLE_DESKTOP_CLIENT_ID=desktop.apps.googleusercontent.com',
        'GOOGLE_DESKTOP_CLIENT_SECRET=secret',
      ]);
      expect(result.exitCode, 0, reason: result.stderr.toString());

      final output = result.stdout.toString();
      final config = output.indexOf(
        'flutter build macos --release --config-only',
      );
      final archive = output.indexOf('xcodebuild -workspace');
      final export = output.indexOf('xcodebuild -exportArchive');
      final validate = output.indexOf('altool --validate-app');
      final upload = output.indexOf('altool --upload-app');
      expect(config, greaterThanOrEqualTo(0));
      expect(archive, greaterThan(config));
      expect(export, greaterThan(archive));
      expect(validate, greaterThan(export));
      expect(upload, greaterThan(validate));
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
        contains('--dart-define=GOOGLE_DESKTOP_CLIENT_SECRET="secret"'),
      );
      expect(output, contains('build/macos/export/pomodoist.pkg'));
    },
  );
}
