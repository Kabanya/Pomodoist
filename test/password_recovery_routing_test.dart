import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/native_link_coordinator.dart';
import 'package:pomodoist/app/password_recovery.dart';
import 'package:pomodoist/app/router.dart';

void main() {
  test('reset destination stays public without an ordinary session', () {
    expect(
      webAppRedirectFor(
        isWeb: true,
        signedIn: false,
        uri: Uri.parse('/reset-password'),
      ),
      isNull,
    );
  });

  test(
    'reset request reuses the callback without inheriting another return route',
    () {
      expect(
        passwordRecoveryRedirect(
          'pomodoist://login-callback?returnTo=%2Ftoday',
        ),
        'pomodoist://login-callback#returnTo=%2Freset-password',
      );
      expect(
        passwordRecoveryRedirect(
          'https://app.test/login-callback?returnTo=%2Fprojects',
        ),
        'https://app.test/login-callback?returnTo=%2Freset-password',
      );
    },
  );

  test(
    'native and web callbacks select recovery without putting credentials in routes',
    () {
      expect(
        nativeRouteForLink(
          Uri.parse(
            'pomodoist://login-callback?returnTo=%2Freset-password&code=SECRET',
          ),
        ),
        '/reset-password?callback=1',
      );
      expect(
        initialAppLocationFor(
          isWeb: true,
          baseUri: Uri.parse(
            'https://app.test/login-callback?returnTo=%2Freset-password&code=SECRET',
          ),
        ),
        '/reset-password?callback=1',
      );
      expect(
        nativeRouteForLink(
          Uri.parse(
            'pomodoist://login-callback#type=recovery&access_token=SECRET',
          ),
        ),
        '/reset-password?callback=1',
      );
    },
  );

  test('expired callbacks retain only the safe failure category', () {
    expect(
      nativeRouteForLink(
        Uri.parse(
          'pomodoist://login-callback?returnTo=%2Freset-password&error_code=otp_expired&error_description=SECRET',
        ),
      ),
      '/reset-password?callback=1&authFailure=linkExpired',
    );
    expect(
      initialAppLocationFor(
        isWeb: true,
        baseUri: Uri.parse(
          'https://app.test/login-callback?returnTo=%2Freset-password#error_code=otp_expired&error_description=SECRET',
        ),
      ),
      '/reset-password?callback=1&authFailure=linkExpired',
    );
  });

  test(
    'cold callback and duplicate live delivery produce one recovery destination',
    () async {
      final callback = Uri.parse(
        'pomodoist://login-callback?returnTo=%2Freset-password&code=SECRET',
      );
      final source = StreamController<Uri>();
      final coordinator = NativeLinkCoordinator(
        loadInitialLink: () async => callback,
        loadLinkStream: () => source.stream,
      );
      await coordinator.prepare();
      await coordinator.start();
      final routes = <String>[];
      coordinator.attachRouteSink(routes.add);
      source.add(callback);
      await pumpEventQueue();
      expect(routes, ['/reset-password?callback=1']);
      await coordinator.dispose();
      await source.close();
    },
  );
}
