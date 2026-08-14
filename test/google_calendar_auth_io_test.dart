import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:pomodoist/features/integrations/google_calendar/data/auth/google_calendar_auth_io.dart';

void main() {
  test('formats Google OAuth token error details', () {
    expect(
      googleCalendarOAuthTokenErrorMessage({
        'error': 'invalid_grant',
        'error_description': 'Bad Request',
      }, 400),
      'Google OAuth failed: invalid_grant: Bad Request',
    );
  });

  test('explains missing OAuth client secret', () {
    expect(
      googleCalendarOAuthTokenErrorMessage({
        'error': 'invalid_request',
        'error_description': 'client_secret is missing.',
      }, 400),
      'Google OAuth failed: client secret is missing. Set '
      'GOOGLE_DESKTOP_CLIENT_SECRET for this OAuth client.',
    );
  });

  test('resolves desktop client secret from the macOS app config', () {
    expect(
      resolveGoogleCalendarDesktopClientSecret(
        dartDefineValue: '',
        environmentValue: null,
        macOSInfoPlistValue: ' desktop-secret ',
      ),
      'desktop-secret',
    );
  });

  test('detects missing macOS keychain entitlement', () {
    expect(
      googleCalendarIsMissingKeychainEntitlement(
        PlatformException(
          code: 'Unexpected security result code',
          message:
              "Code: -34018, Message: A required entitlement isn't present.",
          details: -34018,
        ),
      ),
      isTrue,
    );
  });
}
