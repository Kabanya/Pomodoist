import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/services/platform/native_link_coordinator_core.dart';
import 'package:pomodoist/data/services/platform/windows_native_link_source.dart';
import 'package:pomodoist/domain/models/account/account_auth_failure.dart';
import 'package:pomodoist/domain/models/account/captcha_security.dart';
import 'package:pomodoist/domain/models/app_flavor.dart';
import 'package:pomodoist/domain/models/billing/billing_models.dart';
import 'package:pomodoist/ui/billing/widgets/purchase_success_screen.dart';

const _state = 'captcha-state-value-that-is-long-enough-0001';

void main() {
  tearDown(() => setAppFlavor(buildTimeAppFlavor ?? AppFlavor.production));

  group('native link routes', () {
    test('each flavor routes its own deep links', () {
      for (final flavor in AppFlavor.values) {
        setAppFlavor(flavor);
        final scheme = flavor.urlScheme;

        expect(
          nativeRouteForLink(Uri.parse('$scheme://focus')),
          '/focus',
          reason: flavor.name,
        );
        expect(
          nativeRouteForLink(Uri.parse('$scheme://google-calendar-connected')),
          '/integrations/google-calendar',
          reason: flavor.name,
        );
        expect(
          nativeRouteForLink(Uri.parse('$scheme://purchase-success')),
          '/purchase-success?source=stripe',
          reason: flavor.name,
        );
      }
    });

    test('a link minted by another flavor is not routed', () {
      for (final flavor in AppFlavor.values) {
        setAppFlavor(flavor);
        for (final other in AppFlavor.values) {
          if (other == flavor) continue;
          final scheme = other.urlScheme;

          expect(
            nativeRouteForLink(Uri.parse('$scheme://focus')),
            isNull,
            reason: '${flavor.name} handled ${other.name} focus',
          );
          expect(
            nativeRouteForLink(Uri.parse('$scheme://purchase-success')),
            isNull,
            reason: '${flavor.name} handled ${other.name} purchase success',
          );
          expect(
            nativeRouteForLink(
              Uri.parse('$scheme://google-calendar-connected'),
            ),
            isNull,
            reason: '${flavor.name} handled ${other.name} calendar link',
          );
        }
      }
    });
  });

  group('Windows account auth callbacks', () {
    test('each flavor accepts its own login callback', () {
      for (final flavor in AppFlavor.values) {
        setAppFlavor(flavor);
        expect(
          isWindowsAccountAuthCallback(
            Uri.parse('${flavor.urlScheme}://login-callback?code=abc'),
          ),
          isTrue,
          reason: flavor.name,
        );
      }
    });

    test('a login callback for another flavor is rejected', () {
      for (final flavor in AppFlavor.values) {
        setAppFlavor(flavor);
        for (final other in AppFlavor.values) {
          if (other == flavor) continue;
          expect(
            isWindowsAccountAuthCallback(
              Uri.parse('${other.urlScheme}://login-callback?code=abc'),
            ),
            isFalse,
            reason: '${flavor.name} accepted ${other.name} callback',
          );
        }
      }
    });
  });

  group('CAPTCHA callback target', () {
    test('the target is derived from the running flavor', () {
      for (final flavor in AppFlavor.values) {
        setAppFlavor(flavor);
        expect(
          pomodoistCaptchaCallbackTarget.toString(),
          '${flavor.urlScheme}://captcha-callback',
          reason: flavor.name,
        );
        expect(
          isExactCaptchaReturnTarget(pomodoistCaptchaCallbackTarget.toString()),
          isTrue,
          reason: flavor.name,
        );
      }
    });

    test('each flavor accepts a callback carrying its own target', () {
      for (final flavor in AppFlavor.values) {
        setAppFlavor(flavor);
        expect(
          isExactCaptchaCallbackUri(
            Uri.parse(
              '${flavor.urlScheme}://captcha-callback'
              '?state=$_state&token=TOKEN',
            ),
          ),
          isTrue,
          reason: flavor.name,
        );
      }
    });

    test('a callback posted to another flavor is rejected', () {
      for (final flavor in AppFlavor.values) {
        setAppFlavor(flavor);
        for (final other in AppFlavor.values) {
          if (other == flavor) continue;
          expect(
            isExactCaptchaCallbackUri(
              Uri.parse(
                '${other.urlScheme}://captcha-callback'
                '?state=$_state&token=TOKEN',
              ),
            ),
            isFalse,
            reason: '${flavor.name} accepted ${other.name} callback',
          );
          expect(
            isExactCaptchaReturnTarget('${other.urlScheme}://captcha-callback'),
            isFalse,
            reason: '${flavor.name} accepted ${other.name} return target',
          );
        }
      }
    });
  });

  group('Stripe purchase fallback', () {
    test('the fallback link uses the running flavor scheme', () {
      for (final flavor in AppFlavor.values) {
        setAppFlavor(flavor);
        expect(
          stripePurchaseFallbackUrl,
          '${flavor.urlScheme}://purchase-success',
          reason: flavor.name,
        );
        expect(
          nativeRouteForLink(Uri.parse(stripePurchaseFallbackUrl)),
          '/purchase-success?source=stripe',
          reason: flavor.name,
        );
      }
    });
  });

  group('account auth redirect', () {
    test('a native redirect keeps returnTo in the fragment', () {
      for (final flavor in AppFlavor.values) {
        setAppFlavor(flavor);
        expect(
          accountAuthRedirect('${flavor.urlScheme}://login-callback', '/today'),
          '${flavor.urlScheme}://login-callback#returnTo=%2Ftoday',
          reason: flavor.name,
        );
      }
    });

    test('a redirect for another flavor is treated as a web URL', () {
      setAppFlavor(AppFlavor.staging);
      expect(
        accountAuthRedirect('pomodoist-dev://login-callback', '/today'),
        'pomodoist-dev://login-callback?returnTo=%2Ftoday',
      );
      expect(
        accountAuthRedirect('pomodoist://login-callback', '/today'),
        'pomodoist://login-callback?returnTo=%2Ftoday',
      );
    });

    test('a web redirect keeps returnTo in the query', () {
      setAppFlavor(AppFlavor.staging);
      expect(
        accountAuthRedirect(
          'https://app-test.pomodoist.com/login-callback',
          '/today',
        ),
        'https://app-test.pomodoist.com/login-callback?returnTo=%2Ftoday',
      );
    });
  });

  group('StoreKit selection', () {
    test('the explicit opt-in selects the local store for every flavor', () {
      for (final flavor in AppFlavor.values) {
        expect(
          pomodoistUsesLocalStoreKitFor(
            devUnlock: false,
            localStoreKit: true,
            flavor: flavor,
          ),
          isTrue,
          reason: flavor.name,
        );
        expect(
          pomodoistUsesLocalStoreKitFor(
            devUnlock: true,
            localStoreKit: true,
            flavor: flavor,
          ),
          isTrue,
          reason: '${flavor.name} with the dev unlock',
        );
      }
    });

    test(
      'the dev unlock alone never selects the local store, staging included',
      () {
        for (final flavor in AppFlavor.values) {
          expect(
            pomodoistUsesLocalStoreKitFor(
              devUnlock: true,
              localStoreKit: false,
              flavor: flavor,
            ),
            isFalse,
            reason: flavor.name,
          );
        }
      },
    );

    test('a build without either define uses the remote store', () {
      for (final flavor in AppFlavor.values) {
        expect(
          pomodoistUsesLocalStoreKitFor(
            devUnlock: false,
            localStoreKit: false,
            flavor: flavor,
          ),
          isFalse,
          reason: flavor.name,
        );
      }
    });

    test('a plain flutter test run sets neither define', () {
      expect(pomodoistDevUnlock, isFalse);
      expect(pomodoistLocalStoreKit, isFalse);
      expect(pomodoistUsesLocalStoreKit, isFalse);
    });
  });
}
