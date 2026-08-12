import '../google_calendar_config.dart';
import 'google_calendar_auth_contract.dart';

GoogleCalendarAuthService createGoogleCalendarAuthService({
  required GoogleCalendarConfig config,
}) {
  return _UnsupportedGoogleCalendarAuthService();
}

class _UnsupportedGoogleCalendarAuthService
    implements GoogleCalendarAuthService {
  @override
  Future<void> initialize() async {}

  @override
  Future<String?> accessToken({bool interactive = false}) async => null;

  @override
  Future<void> disconnect() async {}

  @override
  Future<GoogleCalendarAuthAccount> signIn() {
    throw UnsupportedError('Google Calendar auth is not supported here.');
  }
}
