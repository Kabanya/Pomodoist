import 'dart:async';

import 'captcha_security.dart';

class NativeCaptchaBroker {
  NativeCaptchaBroker({
    required Stream<Uri> uriStream,
    NativeCaptchaBuildConfig? config,
    Future<bool> Function(Uri uri)? launch,
    CaptchaTimeoutSchedule? scheduleTimeout,
  });

  Future<String> requestToken() {
    throw UnsupportedError('Native CAPTCHA is unavailable on this platform');
  }

  void cancel() {}
  void dispose() {}
}
