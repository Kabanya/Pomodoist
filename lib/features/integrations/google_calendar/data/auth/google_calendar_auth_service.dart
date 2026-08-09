import '../google_calendar_config.dart';
import 'google_calendar_auth_contract.dart';
import 'google_calendar_auth_stub.dart'
    if (dart.library.html) 'google_calendar_auth_web.dart'
    if (dart.library.io) 'google_calendar_auth_io.dart'
    as platform;

GoogleCalendarAuthService createGoogleCalendarAuthService({
  GoogleCalendarConfig config = const GoogleCalendarConfig(),
}) {
  return platform.createGoogleCalendarAuthService(config: config);
}
