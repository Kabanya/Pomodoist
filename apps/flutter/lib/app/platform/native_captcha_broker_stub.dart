import 'dart:async';

import '../auth/captcha_security.dart';

class NativeCaptchaBroker {
  NativeCaptchaBroker({
    required Stream<Uri> uriStream,
    NativeCaptchaBuildConfig? config,
    Future<bool> Function(Uri uri)? launch,
    CaptchaTimeoutSchedule? scheduleTimeout,
    bool? useLoopback,
  });

  Future<String> requestToken({String? locale}) {
    throw const NativeCaptchaException(NativeCaptchaFailureCode.unavailable);
  }

  void cancel() {}
  void dispose() {}
}
