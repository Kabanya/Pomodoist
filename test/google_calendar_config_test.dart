import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/features/integrations/google_calendar/data/google_calendar_config.dart';

void main() {
  group('GoogleCalendarConfig', () {
    test('uses the platform client ID for native sign in', () {
      const config = GoogleCalendarConfig(
        webClientId: 'web-client.apps.googleusercontent.com',
        clientId: 'ios-client.apps.googleusercontent.com',
      );

      expect(
        config.nativeGoogleSignInClientId,
        'ios-client.apps.googleusercontent.com',
      );
    });

    test('uses the web client ID for web sign in', () {
      const config = GoogleCalendarConfig(
        webClientId: 'web-client.apps.googleusercontent.com',
        clientId: 'ios-client.apps.googleusercontent.com',
      );

      expect(
        config.webGoogleSignInClientId,
        'web-client.apps.googleusercontent.com',
      );
    });

    test('requires a web client ID for web sign in', () {
      const config = GoogleCalendarConfig();

      expect(
        () => config.requiredWebClientId,
        throwsA(isA<GoogleCalendarConfigException>()),
      );
    });

    test('falls back to the platform client ID for web sign in', () {
      const config = GoogleCalendarConfig(
        clientId: 'fallback-client.apps.googleusercontent.com',
      );

      expect(
        config.requiredWebClientId,
        'fallback-client.apps.googleusercontent.com',
      );
    });

    test('uses the desktop client ID for desktop OAuth', () {
      const config = GoogleCalendarConfig(
        clientId: 'ios-client.apps.googleusercontent.com',
        desktopClientId: 'desktop-client.apps.googleusercontent.com',
      );

      expect(
        config.requiredDesktopClientId,
        'desktop-client.apps.googleusercontent.com',
      );
    });

    test('falls back to the platform client ID for desktop OAuth', () {
      const config = GoogleCalendarConfig(
        clientId: 'desktop-client.apps.googleusercontent.com',
      );

      expect(
        config.requiredDesktopClientId,
        'desktop-client.apps.googleusercontent.com',
      );
    });

    test('uses the optional desktop client secret', () {
      const config = GoogleCalendarConfig(desktopClientSecret: ' secret ');

      expect(config.desktopGoogleSignInClientSecret, 'secret');
    });
  });
}
