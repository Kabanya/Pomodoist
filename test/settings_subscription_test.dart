import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/features/billing/billing.dart';
import 'package:pomodoist/features/settings/presentation/settings_subscription.dart';

void main() {
  test('loading and failed lookups do not claim a Free subscription', () {
    expect(settingsSubscriptionTier(const BillingState()), isNull);
    expect(
      settingsSubscriptionTier(
        const BillingState(loading: false, error: 'offline'),
      ),
      isNull,
    );
    expect(
      settingsSubscriptionTier(const BillingState(loading: false)),
      BillingAccessTier.free,
    );
  });

  test('confirmed access survives a pending or failed refresh', () {
    for (final loading in [false, true]) {
      expect(
        settingsSubscriptionTier(
          BillingState(
            loading: loading,
            error: 'offline',
            activeProductId: pomodoistMonthlyProductId,
            activeStoreKitProductIds: const {pomodoistMonthlyProductId},
          ),
        ),
        BillingAccessTier.monthly,
      );
      expect(
        settingsSubscriptionTier(
          BillingState(loading: loading, accountEntitlementActive: true),
        ),
        BillingAccessTier.pro,
      );
    }
  });
}
