import 'package:pomodoist/domain/models/account/account_overview.dart';
import 'package:pomodoist/domain/models/billing/billing_models.dart';

/// Named [BillingState] values for billing tests.
///
/// Every timestamp derives from [fixedNow], so fixtures are stable across
/// runs.
abstract final class BillingFixtures {
  /// Fixed instant every fixture timestamp derives from.
  static final DateTime fixedNow = DateTime.utc(2026, 1, 1, 12);

  /// Builds a [BillingState] whose defaults match the constructor, so a test
  /// overrides only the fields it cares about.
  static BillingState build({
    bool loading = true,
    bool platformSupported = true,
    bool storeAvailable = false,
    bool restoring = false,
    Map<String, BillingProduct> productDetailsById = const {},
    Set<String> missingProductIds = const {},
    String? catalogError,
    Set<String> eligibleIntroductoryProductIds = const {},
    Set<String> purchasedProductIds = const {},
    Set<String> activeStoreKitProductIds = const {},
    bool accountEntitlementActive = false,
    bool environmentEntitlementActive = false,
    BillingEntitlement? activeAccountEntitlement,
    bool stripeLaunchOfferEligible = false,
    DateTime? stripeLaunchOfferEndsAt,
    String? activeProductId,
    String? pendingProductId,
    String? purchaseSuccessProductId,
    String? error,
  }) => BillingState(
    loading: loading,
    platformSupported: platformSupported,
    storeAvailable: storeAvailable,
    restoring: restoring,
    productDetailsById: productDetailsById,
    missingProductIds: missingProductIds,
    catalogError: catalogError,
    eligibleIntroductoryProductIds: eligibleIntroductoryProductIds,
    purchasedProductIds: purchasedProductIds,
    activeStoreKitProductIds: activeStoreKitProductIds,
    accountEntitlementActive: accountEntitlementActive,
    environmentEntitlementActive: environmentEntitlementActive,
    activeAccountEntitlement: activeAccountEntitlement,
    stripeLaunchOfferEligible: stripeLaunchOfferEligible,
    stripeLaunchOfferEndsAt: stripeLaunchOfferEndsAt,
    activeProductId: activeProductId,
    pendingProductId: pendingProductId,
    purchaseSuccessProductId: purchaseSuccessProductId,
    error: error,
  );

  /// The first state, before the store catalog has been read.
  static BillingState loading() => build();

  /// A loaded catalog with nothing purchased and no entitlement, so the
  /// account is on the free tier and can buy any plan.
  static BillingState free() => BillingState(
    loading: false,
    storeAvailable: true,
    productDetailsById: _catalog,
    eligibleIntroductoryProductIds: const {
      pomodoistMonthlyProductId,
      pomodoistAnnualProductId,
    },
  );

  /// An active monthly subscription.
  static BillingState monthly() => _subscription(
    productId: pomodoistMonthlyProductId,
    period: const Duration(days: 30),
  );

  /// An active annual subscription.
  static BillingState annual() => _subscription(
    productId: pomodoistAnnualProductId,
    period: const Duration(days: 365),
  );

  /// An active lifetime purchase, which never renews and never expires.
  static BillingState lifetime() => BillingState(
    loading: false,
    storeAvailable: true,
    productDetailsById: _catalog,
    purchasedProductIds: const {pomodoistLifetimeProductId},
    activeStoreKitProductIds: const {pomodoistLifetimeProductId},
    accountEntitlementActive: true,
    activeAccountEntitlement: _entitlement(
      productId: pomodoistLifetimeProductId,
      purchaseType: 'lifetime',
    ),
    activeProductId: pomodoistLifetimeProductId,
  );

  /// A lapsed subscription: the store reports nothing active and the stored
  /// entitlement has expired, so the account falls back to the free tier.
  static BillingState expired() => BillingState(
    loading: false,
    storeAvailable: true,
    productDetailsById: _catalog,
    activeAccountEntitlement: _entitlement(
      productId: pomodoistAnnualProductId,
      purchaseType: 'subscription',
      status: 'expired',
      validUntil: fixedNow.subtract(const Duration(days: 30)),
      renewsAt: fixedNow.subtract(const Duration(days: 30)),
    ),
  );

  /// A finished restore that surfaced the annual subscription.
  static BillingState restored() => _subscription(
    productId: pomodoistAnnualProductId,
    period: const Duration(days: 365),
    purchaseSuccessProductId: pomodoistAnnualProductId,
  );

  /// The store could not be reached, so no product loaded and nothing can be
  /// purchased.
  static BillingState storeUnavailable() => BillingState(
    loading: false,
    missingProductIds: billingProductIds,
    catalogError: 'NSURLErrorDomain error -1008.',
  );

  /// A purchase the store has accepted but not yet finished.
  static BillingState purchasePending() => BillingState(
    loading: false,
    storeAvailable: true,
    productDetailsById: _catalog,
    pendingProductId: pomodoistAnnualProductId,
  );

  /// A purchase the store rejected.
  static BillingState purchaseFailed() => BillingState(
    loading: false,
    storeAvailable: true,
    productDetailsById: _catalog,
    error: 'Purchase failed.',
  );

  /// A subscription the store reports as active on both the device and the
  /// account.
  static BillingState _subscription({
    required String productId,
    required Duration period,
    String? purchaseSuccessProductId,
  }) => BillingState(
    loading: false,
    storeAvailable: true,
    productDetailsById: _catalog,
    purchasedProductIds: {productId},
    activeStoreKitProductIds: {productId},
    accountEntitlementActive: true,
    activeAccountEntitlement: _entitlement(
      productId: productId,
      purchaseType: 'subscription',
      validUntil: fixedNow.add(period),
      renewsAt: fixedNow.add(period),
    ),
    activeProductId: productId,
    purchaseSuccessProductId: purchaseSuccessProductId,
  );

  static BillingEntitlement _entitlement({
    required String productId,
    required String purchaseType,
    String status = 'active',
    DateTime? validUntil,
    DateTime? renewsAt,
  }) => BillingEntitlement(
    appId: pomodoistAccountAppId,
    entitlementId: 'app_store:$productId',
    status: status,
    source: 'app_store',
    purchaseType: purchaseType,
    productId: productId,
    store: 'app_store',
    validUntil: validUntil,
    renewsAt: renewsAt,
  );

  /// The App Store catalog: both subscriptions carry the seven day free
  /// introductory trial, the lifetime plans are one-time purchases.
  static Map<String, BillingProduct> get _catalog => {
    pomodoistMonthlyProductId: _product(
      id: pomodoistMonthlyProductId,
      title: 'Pomodoist Pro Monthly',
      description: 'Monthly access to Pomodoist Pro.',
      price: r'$4.99',
      rawPrice: 4.99,
      offers: const [
        BillingOffer(
          id: 'intro_monthly_7_day',
          type: BillingOfferType.introductory,
          paymentMode: BillingOfferPaymentMode.freeTrial,
          price: 0,
          periodUnit: BillingOfferPeriodUnit.day,
          periodValue: 7,
          periodCount: 1,
        ),
      ],
    ),
    pomodoistAnnualProductId: _product(
      id: pomodoistAnnualProductId,
      title: 'Pomodoist Pro Annual',
      description: 'Annual access to Pomodoist Pro.',
      price: r'$29.99',
      rawPrice: 29.99,
      offers: const [
        BillingOffer(
          id: 'intro_annual_7_day',
          type: BillingOfferType.introductory,
          paymentMode: BillingOfferPaymentMode.freeTrial,
          price: 0,
          periodUnit: BillingOfferPeriodUnit.day,
          periodValue: 7,
          periodCount: 1,
        ),
      ],
    ),
    pomodoistLifetimeProductId: _product(
      id: pomodoistLifetimeProductId,
      title: 'Pomodoist Pro Lifetime',
      description: 'One-time purchase of Pomodoist Pro.',
      price: r'$99.99',
      rawPrice: 99.99,
    ),
    pomodoistLifetimeLaunchProductId: _product(
      id: pomodoistLifetimeLaunchProductId,
      title: 'Pomodoist Pro Lifetime (Launch)',
      description: 'Limited launch price for Pomodoist Pro.',
      price: r'$89.99',
      rawPrice: 89.99,
    ),
  };

  static BillingProduct _product({
    required String id,
    required String title,
    required String description,
    required String price,
    required double rawPrice,
    List<BillingOffer> offers = const [],
  }) => BillingProduct(
    id: id,
    title: title,
    description: description,
    price: price,
    rawPrice: rawPrice,
    currencyCode: 'USD',
    currencySymbol: r'$',
    offers: offers,
  );
}
