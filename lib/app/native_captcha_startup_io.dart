import 'captcha_security.dart';
import 'runtime_public_config.dart';

void validateNativeCaptchaBuild(RuntimePublicConfig config) {
  if (config.environment == RuntimeEnvironment.local ||
      config.turnstileSiteKey.isEmpty) {
    return;
  }
  NativeCaptchaBuildConfig.fromEnvironment();
}
