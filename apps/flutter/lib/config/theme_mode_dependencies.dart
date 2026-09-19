import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/data/services/local/shared_theme_cookie.dart';

typedef SharedThemeCookieReader = String Function();
typedef SharedThemeCookieWriter = void Function(String value);

final sharedThemeCookieReaderProvider = Provider<SharedThemeCookieReader>(
  (ref) => readSharedThemeCookieHeader,
);

final sharedThemeCookieWriterProvider = Provider<SharedThemeCookieWriter>(
  (ref) => writeSharedThemePreference,
);
