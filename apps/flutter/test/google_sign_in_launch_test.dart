import 'dart:async';

import 'package:app_account/app_account.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/account_auth_feedback.dart';
import 'package:pomodoist/app/native_link_coordinator_core.dart';
import 'package:pomodoist/app/password_recovery.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late SupabaseClient supabase;
  late AccountClient account;
  late List<Map<Object?, Object?>> launches;
  var launchSucceeds = true;

  test(
    'native recovery keeps the exact registered redirect before fragment',
    () {
      const registered = 'pomodoist://login-callback';
      final redirect = Uri.parse(passwordRecoveryRedirect(registered));
      expect(redirect.removeFragment().toString(), registered);
      expect(
        nativeRouteForLink(
          redirect.replace(queryParameters: {'code': 'test-code'}),
        ),
        '/reset-password?callback=1',
      );
    },
  );

  test('native callback restores the account section from its fragment', () {
    expect(
      nativeRouteForLink(
        Uri.parse(
          'pomodoist://login-callback?code=test-code'
          '#returnTo=%2Fsettings%3Fsection%3Daccount',
        ),
      ),
      '/login-callback?returnTo=%2Fsettings%3Fsection%3Daccount',
    );
  });

  test('ambiguous return paths cannot switch a callback into recovery', () {
    expect(
      nativeRouteForLink(
        Uri.parse(
          'pomodoist://login-callback?returnTo=%2Freset-password'
          '#returnTo=%2Fsettings',
        ),
      ),
      '/login-callback?returnTo=%2Fsettings',
    );
  });

  test('fragment return paths retain native destination validation', () {
    for (final target in [
      'https://other.test',
      '//other.test',
      '/login-callback',
      '/settings#unexpected',
    ]) {
      final redirect = accountAuthRedirect(
        'pomodoist://login-callback',
        target,
      );
      expect(
        nativeRouteForLink(Uri.parse(redirect)),
        '/login-callback?returnTo=%2Fsettings',
      );
    }
  });

  test('web redirects retain their origin, callback and query return path', () {
    expect(
      accountAuthRedirect(
        'https://app.test/login-callback',
        '/settings?section=account',
      ),
      'https://app.test/login-callback?returnTo=%2Fsettings%3Fsection%3Daccount',
    );
  });

  test(
    'native account return survives cold and warm callback delivery',
    () async {
      for (final coldStart in [true, false]) {
        final callback = Uri.parse(
          'pomodoist://login-callback?code=test-code'
          '#returnTo=%2Fsettings%3Fsection%3Daccount',
        );
        final source = StreamController<Uri>();
        final coordinator = NativeLinkCoordinator(
          loadInitialLink: () async => coldStart ? callback : null,
          loadLinkStream: () => source.stream,
        );
        try {
          await coordinator.prepare();
          await coordinator.start();
          final routes = <String>[];
          coordinator.attachRouteSink(routes.add);
          source.add(callback);
          source.add(callback);
          await pumpEventQueue();
          expect(routes, [
            '/login-callback?returnTo=%2Fsettings%3Fsection%3Daccount',
          ]);
        } finally {
          await coordinator.dispose();
          await source.close();
        }
      }
    },
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    launches = [];
    launchSucceeds = true;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'launch') {
        launches.add(call.arguments as Map<Object?, Object?>);
        return launchSucceeds;
      }
      return true;
    });
    supabase = SupabaseClient(
      'https://example.test',
      'test-public-key',
      authOptions: AuthClientOptions(
        authFlowType: AuthFlowType.pkce,
        autoRefreshToken: false,
        pkceAsyncStorage: SharedPreferencesGotrueAsyncStorage(),
      ),
    );
    account = AccountClient.fromSupabaseClient(supabase);
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    await supabase.dispose();
  });

  test(
    'Google sends registered native redirects to the external browser',
    () async {
      for (final target in [
        '/settings?section=account',
        '/oauth/consent?authorization_id=test-id',
      ]) {
        final redirect = accountAuthRedirect(
          'pomodoist://login-callback',
          target,
        );
        await account.signInWithGoogle(redirectTo: redirect);
        final launch = launches.last;
        final uri = Uri.parse(launch['url']! as String);
        expect(uri.host, 'example.test');
        expect(uri.path, '/auth/v1/authorize');
        expect(uri.queryParameters['provider'], 'google');
        expect(uri.queryParameters['redirect_to'], redirect);
        // Supabase's exact allowlist match ignores fragments, not queries.
        expect(
          Uri.parse(
            uri.queryParameters['redirect_to']!,
          ).removeFragment().toString(),
          'pomodoist://login-callback',
        );
        expect(uri.queryParameters['code_challenge'], isNotEmpty);
        expect(uri.queryParameters['code_challenge_method'], 's256');
        expect(launch['useSafariVC'], isFalse);
        expect(launch['useWebView'], isFalse);
      }
      expect(launches, hasLength(2));
      expect(supabase.auth.currentSession, isNull);
    },
  );

  test('browser refusal is surfaced as a retryable sign-in failure', () async {
    launchSucceeds = false;
    await expectLater(
      account.signInWithGoogle(redirectTo: 'pomodoist://login-callback'),
      throwsA(
        predicate<Object>((error) {
          final failure = classifyAccountAuthFailure(
            error,
            operation: AccountAuthOperation.google,
          );
          return failure.recovery == AccountAuthRecovery.retry &&
              !failure.isCancelled;
        }),
      ),
    );
    expect(launches, hasLength(1));
  });
}
