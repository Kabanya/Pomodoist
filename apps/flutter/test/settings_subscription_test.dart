import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/domain/models/billing/billing_models.dart';
import 'package:pomodoist/ui/settings/widgets/settings_subscription.dart';

void main() {
  test('loading and failed lookups do not claim a Free subscription', () {
    expect(settingsSubscriptionTier(BillingState()), isNull);
    expect(
      settingsSubscriptionTier(BillingState(loading: false, error: 'offline')),
      isNull,
    );
    expect(
      settingsSubscriptionTier(BillingState(loading: false)),
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
