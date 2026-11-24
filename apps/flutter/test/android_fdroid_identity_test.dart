import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/domain/models/app_flavor.dart';
import 'package:pomodoist/domain/models/account/captcha_security.dart';

void main() {
  test('Android distribution resolves to its own CAPTCHA callback', () {
    const fdroid = bool.fromEnvironment('POMODOIST_FDROID');
    expect(
      AppFlavor.production.applicationId,
      fdroid ? 'com.finchforge.pomodoist.fdroid' : 'com.finchforge.pomodoist',
    );
    expect(
      pomodoistCaptchaCallbackTarget.toString(),
      fdroid
          ? 'pomodoist-fdroid://captcha-callback'
          : 'pomodoist://captcha-callback',
    );
    expect(isExactCaptchaReturnTarget('pomodoist://captcha-callback'), !fdroid);
    expect(
      isExactCaptchaReturnTarget('pomodoist-fdroid://captcha-callback'),
      fdroid,
    );
  });
}
