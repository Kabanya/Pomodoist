import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'TestFlight preflight accepts only a production client config',
    () async {
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
      expect(output, isNot(contains('flutter build ios')));
      expect(output, isNot(contains('xcodebuild -workspace')));

      final validate = output.indexOf('altool --validate-app');
      final upload = output.indexOf('altool --upload-app');
      expect(validate, greaterThanOrEqualTo(0));
      expect(upload, greaterThan(validate));
      expect(output, contains('build/ios/ipa/Pomodoist.ipa'));
    },
  );
}
