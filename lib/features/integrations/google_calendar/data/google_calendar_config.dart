const googleCalendarRequestTimeout = Duration(seconds: 30);
const googleCalendarInteractiveAuthTimeout = Duration(minutes: 3);

class GoogleCalendarConfig {
  const GoogleCalendarConfig({
    this.webClientId = const String.fromEnvironment('GOOGLE_WEB_CLIENT_ID'),
    this.clientId = const String.fromEnvironment('GOOGLE_CLIENT_ID'),
    this.serverClientId = const String.fromEnvironment(
      'GOOGLE_SERVER_CLIENT_ID',
    ),
    this.desktopClientId = const String.fromEnvironment(
      'GOOGLE_DESKTOP_CLIENT_ID',
    ),
    this.desktopClientSecret = const String.fromEnvironment(
      'GOOGLE_DESKTOP_CLIENT_SECRET',
    ),
  });

  static const calendarName = 'Pomodoist';
  static const connectionId = 'primary';
  static const scope = 'https://www.googleapis.com/auth/calendar.app.created';
  static const scopes = <String>[scope];

  final String webClientId;
  final String clientId;
  final String serverClientId;
  final String desktopClientId;
  final String desktopClientSecret;

  String? get nativeGoogleSignInClientId {
    final value = clientId.trim();
    return value.trim().isEmpty ? null : value.trim();
  }

  String? get webGoogleSignInClientId {
    final value = webClientId.trim().isNotEmpty ? webClientId : clientId;
    return value.trim().isEmpty ? null : value.trim();
  }

  String get requiredWebClientId {
    final value = webGoogleSignInClientId;
    if (value == null) {
      throw const GoogleCalendarConfigException(
        'GOOGLE_WEB_CLIENT_ID is required for Google Calendar on web.',
      );
    }
    return value;
  }

  String? get googleSignInServerClientId {
    final value = serverClientId.trim();
    return value.isEmpty ? null : value;
  }

  String? get desktopGoogleSignInClientId {
    final value = desktopClientId.trim().isNotEmpty
        ? desktopClientId
        : clientId;
    return value.trim().isEmpty ? null : value.trim();
  }

  String? get desktopGoogleSignInClientSecret {
    final value = desktopClientSecret.trim();
    return value.isEmpty ? null : value;
  }

  String get requiredDesktopClientId {
    final value = desktopGoogleSignInClientId;
    if (value == null) {
      throw const GoogleCalendarConfigException(
        'GOOGLE_DESKTOP_CLIENT_ID or GOOGLE_CLIENT_ID is required for '
        'Google Calendar on macOS/Windows/Linux.',
      );
    }
    return value;
  }
}

class GoogleCalendarConfigException implements Exception {
  const GoogleCalendarConfigException(this.message);

  final String message;

  @override
  String toString() => message;
}
