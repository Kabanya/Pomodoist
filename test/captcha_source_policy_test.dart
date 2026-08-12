import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('standalone registration remains CAPTCHA-aware', () async {
    final source = await File(
      'lib/features/settings/presentation/settings_screen.dart',
    ).readAsString();

    expect(source, contains('CaptchaVerification('));
    expect(source, contains('captchaToken: token'));
  });

  test(
    'CAPTCHA sources do not log or persist token and state values',
    () async {
      final files = [
        'lib/app/captcha_security.dart',
        'lib/app/native_captcha_broker_io.dart',
        'lib/app/native_link_coordinator_core.dart',
        'lib/app/turnstile_widget_web.dart',
        'lib/features/settings/presentation/captcha_challenge_screen.dart',
        'lib/features/settings/presentation/pomodoist_account_actions.dart',
      ];
      final source = (await Future.wait(
        files.map(File.new).map((file) => file.readAsString()),
      )).join('\n');

      expect(
        source,
        isNot(matches(RegExp(r'(^|[^A-Za-z0-9_])print\s*\(', multiLine: true))),
        reason: 'print(',
      );
      for (final forbidden in [
        'debugPrint(',
        'SharedPreferences',
        'FlutterSecureStorage',
        'Sentry.capture',
      ]) {
        expect(source, isNot(contains(forbidden)), reason: forbidden);
      }
      expect(source, isNot(matches(RegExp(r'\blog\s*\('))));
    },
  );

  test(
    'web loads only the official explicit Turnstile endpoint under CSP',
    () async {
      final index = await File('web/index.html').readAsString();
      final csp = await File(
        'deploy/web/security-headers.conf.template',
      ).readAsString();

      expect(
        index,
        isNot(
          contains(
            'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit',
          ),
        ),
        reason: 'local empty-key startup must not contact Cloudflare',
      );
      expect(csp, contains('script-src'));
      expect(csp, contains('frame-src https://challenges.cloudflare.com'));
      expect(csp, isNot(contains('*.cloudflare.com')));
      final widget = await File(
        'lib/app/turnstile_widget_web.dart',
      ).readAsString();
      expect(
        widget,
        contains(
          'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit',
        ),
      );
      expect(widget, contains("@JS('turnstile.remove')"));
      expect(widget, contains('CaptchaLoadTimeoutGuard'));
      expect(widget, contains('_turnstileReady = null'));
      expect(widget, contains('script.remove()'));
      expect(widget, contains('loadTimeout'));
      expect(widget, contains('renderTurnstileSafely<JSAny>'));
      expect(widget, isNot(contains('Future.delayed')));

      final browserSmoke = await File(
        'tool/test_web_browser.mjs',
      ).readAsString();
      expect(browserSmoke, contains('sanitizeDiagnostic'));
      expect(browserSmoke, contains('/([?&#](?:state|token)=)[^&#\\s)]+/giu'));
    },
  );

  test('email auth dialog mounts and forwards Cloudflare CAPTCHA', () async {
    final source = await File(
      'lib/features/settings/presentation/pomodoist_account_actions.dart',
    ).readAsString();

    expect(source, contains('CaptchaVerification('));
    expect(source, contains('captchaToken: token'));
  });

  test('remaining web CAPTCHA surfaces require a user-clicked retry', () async {
    final sources = await Future.wait(
      [
        'lib/features/settings/presentation/captcha_challenge_screen.dart',
        'lib/features/settings/presentation/settings_screen.dart',
      ].map((path) => File(path).readAsString()),
    );

    for (final source in sources) {
      expect(source, contains('CaptchaVerification('));
    }
    final shared = await File(
      'lib/app/captcha_verification.dart',
    ).readAsString();
    expect(shared, contains('Retry verification'));
    expect(shared, contains('controller.reset()'));
  });

  test('native challenge keeps the callback protocol in the client', () async {
    final broker = await File(
      'lib/app/native_captcha_broker_io.dart',
    ).readAsString();
    final config = await File('lib/app/captcha_security.dart').readAsString();

    expect(broker, contains("uri.scheme != 'pomodoist'"));
    expect(broker, contains("uri.host != 'captcha-callback'"));
    expect(config, contains('POMODOIST_REGISTRATION_URL'));
  });

  test(
    'iOS delegates all deep links to one early AppLinks coordinator',
    () async {
      final plist = await File('ios/Runner/Info.plist').readAsString();
      final main = await File('lib/main.dart').readAsString();
      final accountProviders = await File(
        'lib/app/account_providers.dart',
      ).readAsString();
      final broker = await File(
        'lib/app/native_captcha_broker_io.dart',
      ).readAsString();
      final coordinator = await File(
        'lib/app/native_link_coordinator_core.dart',
      ).readAsString();

      expect(plist, contains('<key>FlutterDeepLinkingEnabled</key>'));
      expect(
        plist,
        matches(RegExp(r'<key>FlutterDeepLinkingEnabled</key>\s*<false\s*/>')),
      );
      expect(main, contains('createNativeLinkCoordinator'));
      expect(main.indexOf('.prepare()'), lessThan(main.indexOf('.start()')));
      expect(main.indexOf('.start()'), lessThan(main.indexOf('runApp(')));
      expect(
        accountProviders,
        contains('initializePomodoistAccountIfConfigured(config)'),
      );
      expect(broker, isNot(contains('AppLinks(')));
      expect(coordinator, isNot(contains('.hashCode')));
      expect(
        coordinator,
        isNot(contains('Uri? _initialLink')),
        reason: 'the coordinator must process initial secrets without storage',
      );
      expect(coordinator, contains('String? _lastFingerprintDigest'));
      expect(coordinator, contains('nativeLinkFingerprint(uri)'));
    },
  );

  test(
    'Sentry drops challenge-route events, transactions, and breadcrumbs',
    () async {
      final source = await File(
        'lib/app/sentry_observability.dart',
      ).readAsString();

      expect(
        source,
        contains('options.beforeSend = filterCaptchaChallengeEvent'),
      );
      expect(
        source,
        contains(
          'options.beforeSendTransaction = filterCaptchaChallengeTransaction',
        ),
      );
      expect(
        source,
        contains('options.beforeBreadcrumb = filterCaptchaChallengeBreadcrumb'),
      );
    },
  );
}
