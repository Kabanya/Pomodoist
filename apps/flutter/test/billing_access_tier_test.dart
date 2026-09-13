import 'package:app_account/app_account.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/features/billing/billing.dart';

void main() {
  group('billingAccessTier', () {
    test('returns free without an active entitlement', () {
      expect(billingAccessTier(const BillingState()), BillingAccessTier.free);
    });

    test('returns monthly for the active local StoreKit product', () {
      expect(
        billingAccessTier(
          const BillingState(
            activeProductId: pomodoistMonthlyProductId,
            activeStoreKitProductIds: {pomodoistMonthlyProductId},
          ),
        ),
        BillingAccessTier.monthly,
      );
    });

    test('returns annual for the active account product', () {
      expect(
        billingAccessTier(
          const BillingState(
            accountEntitlementActive: true,
            activeAccountEntitlement: AccountEntitlement(
              appId: AccountAppId.pomodoist,
              entitlementId: 'stripe:annual',
              status: 'active',
              purchaseType: 'subscription',
              source: 'stripe',
              productId: pomodoistAnnualProductId,
            ),
          ),
        ),
        BillingAccessTier.annual,
      );
    });

    test('returns lifetime when the account omits its product id', () {
      expect(
        billingAccessTier(
          const BillingState(
            accountEntitlementActive: true,
            activeAccountEntitlement: AccountEntitlement(
              appId: AccountAppId.pomodoist,
              entitlementId: 'manual:lifetime',
              status: 'active',
              purchaseType: 'lifetime',
              source: 'manual',
            ),
          ),
        ),
        BillingAccessTier.lifetime,
      );
    });

    test('returns pro without exposing an unknown active product id', () {
      expect(
        billingAccessTier(
          const BillingState(
            accountEntitlementActive: true,
            activeAccountEntitlement: AccountEntitlement(
              appId: AccountAppId.pomodoist,
              entitlementId: 'stripe:legacy',
              status: 'active',
              purchaseType: 'subscription',
              source: 'stripe',
              productId: 'internal.legacy.product',
            ),
          ),
        ),
        BillingAccessTier.pro,
      );
    });
  });
}
