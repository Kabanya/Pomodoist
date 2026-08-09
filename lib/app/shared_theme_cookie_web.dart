import 'package:web/web.dart' as web;

const _validThemePreferences = {'light', 'dark', 'system'};

String readSharedThemeCookieHeader() => web.document.cookie;

void writeSharedThemePreference(String value) {
  if (!_validThemePreferences.contains(value)) return;

  final hostname = web.window.location.hostname;
  if (hostname != 'pomodoist.com' && !hostname.endsWith('.pomodoist.com')) {
    return;
  }

  web.document.cookie =
      'pomodoist-theme=$value; Domain=pomodoist.com; Path=/; '
      'Max-Age=31536000; SameSite=Lax; Secure';
}
