import 'package:pomodoist/domain/models/account/captcha_security.dart';

void validateNativeCaptchaBuild({
  required bool local,
  required bool captchaEnabled,
}) {
  if (local || !captchaEnabled) {
    return;
  }
  NativeCaptchaBuildConfig.fromEnvironment();
}
