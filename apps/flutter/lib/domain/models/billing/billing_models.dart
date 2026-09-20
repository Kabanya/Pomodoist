const billingActiveProductIdPreferenceKey = 'billing.activeProductId.v1';
const billingPurchasedProductIdsPreferenceKey =
    'billing.purchasedProductIds.v1';

const pomodoistMonthlyProductId = 'pomodoist.pro.monthly';
const pomodoistAnnualProductId = 'pomodoist.pro.annual';
const pomodoistLifetimeProductId = 'pomodoist.pro.lifetime';
const pomodoistLifetimeLaunchProductId = 'pomodoist.pro.lifetime.launch';
const _pomodoistDevUnlockValue = String.fromEnvironment('POMODOIST_DEV_UNLOCK');
const pomodoistDevUnlock =
    bool.fromEnvironment('POMODOIST_DEV_UNLOCK') ||
    _pomodoistDevUnlockValue == '1';
const _pomodoistLocalStoreKitValue = String.fromEnvironment(
  'POMODOIST_LOCAL_STOREKIT',
);
const pomodoistLocalStoreKit =
    bool.fromEnvironment('POMODOIST_LOCAL_STOREKIT') ||
    _pomodoistLocalStoreKitValue == '1';
const _billingChannelValue = String.fromEnvironment(
  'POMODOIST_BILLING_CHANNEL',
);

class _BillingChannelBuildGuard {
  const _BillingChannelBuildGuard(this.value)
    : assert(
        !_releaseMode || value == 'storekit' || value == 'stripe',
        'POMODOIST_BILLING_CHANNEL must be storekit or stripe in release builds.',
      );

  final String value;
}

const _billingChannelBuildGuard = _BillingChannelBuildGuard(
  _billingChannelValue,
);

enum BillingChannel { storeKit, stripe }

BillingChannel billingChannelForBuild({
  String value = _billingChannelValue,
  bool releaseMode = _releaseMode,
}) {
  if (value == 'storekit') return BillingChannel.storeKit;
  if (value == 'stripe') return BillingChannel.stripe;
  if (releaseMode) {
    throw StateError(
      'POMODOIST_BILLING_CHANNEL must be storekit or stripe in release builds.',
    );
  }
  return BillingChannel.storeKit;
}

enum BillingCheckoutSurface { native, web }

class StripeBillingCatalog {
  StripeBillingCatalog({
    required this.enabled,
    required this.introEligible,
    Map<String, String> prices = const {},
    required this.launchOfferEligible,
    required this.launchOfferEndsAt,
  }) : prices = Map.unmodifiable(prices);

  final bool enabled;
  final bool introEligible;
  final Map<String, String> prices;
  final bool launchOfferEligible;
  final DateTime? launchOfferEndsAt;

  factory StripeBillingCatalog.fromJson(Object? value) {
    if (value is! Map) throw const FormatException('Invalid Stripe catalog.');
    final json = Map<String, Object?>.from(value);
    final launchValue = json['launchOffer'];
    if (launchValue is! Map) {
      throw const FormatException('Invalid Stripe launch offer.');
    }
    final launch = Map<String, Object?>.from(launchValue);
    final enabled = json['enabled'];
    final introEligible = json['introEligible'];
    final pricesValue = json['prices'] ?? const {};
    final launchEligible = launch['eligible'];
    final endsAtValue = launch['endsAt'];
    final endsAt = endsAtValue is String
        ? DateTime.tryParse(endsAtValue)
        : null;
    if (enabled is! bool ||
        introEligible is! bool ||
        pricesValue is! Map ||
        pricesValue.entries.any(
          (entry) =>
              entry.key is! String ||
              entry.value is! String ||
              (entry.value as String).isEmpty,
        ) ||
        launchEligible is! bool ||
        (launchEligible && endsAt == null)) {
      throw const FormatException('Invalid Stripe catalog.');
    }
    return StripeBillingCatalog(
      enabled: enabled,
      introEligible: introEligible,
      prices: {
        for (final entry in pricesValue.entries)
          entry.key as String: entry.value as String,
      },
      launchOfferEligible: launchEligible,
      launchOfferEndsAt: endsAt?.toUtc(),
    );
  }
}

Uri stripeCheckoutUrlFromJson(Object? value) {
  if (value is! Map) throw const FormatException('Invalid Checkout response.');
  final raw = value['url'];
  final url = raw is String ? Uri.tryParse(raw) : null;
  if (url == null ||
      url.scheme != 'https' ||
      url.host != 'checkout.stripe.com') {
    throw const FormatException('Invalid Checkout URL.');
  }
  return url;
}

Duration stripeLaunchOfferRemaining({
  required DateTime now,
  required DateTime? endsAt,
}) {
  if (endsAt == null) return Duration.zero;
  final remaining = endsAt.toUtc().difference(now.toUtc());
  return remaining.isNegative ? Duration.zero : remaining;
}

class StripeBillingException implements Exception {
  const StripeBillingException(this.code);

  final String code;

  @override
  String toString() => code;
}

enum BillingPlanKind { subscription, lifetime }

class BillingPlan {
  const BillingPlan({
    required this.productId,
    required this.kind,
    required this.fallbackPrice,
    required this.highlighted,
    this.introductoryFallbackPrice,
  });

  final String productId;
  final BillingPlanKind kind;
  final String fallbackPrice;
  final bool highlighted;
  final String? introductoryFallbackPrice;
}

const billingPlans = [
  BillingPlan(
    productId: pomodoistAnnualProductId,
    kind: BillingPlanKind.subscription,
    fallbackPrice: r'$39/year',
    introductoryFallbackPrice: r'$19/year',
    highlighted: true,
  ),
  BillingPlan(
    productId: pomodoistMonthlyProductId,
    kind: BillingPlanKind.subscription,
    fallbackPrice: r'$5.99/month',
    introductoryFallbackPrice: r'$2.99/month',
    highlighted: false,
  ),
  BillingPlan(
    productId: pomodoistLifetimeProductId,
    kind: BillingPlanKind.lifetime,
    fallbackPrice: r'$99.99',
    highlighted: false,
  ),
  BillingPlan(
    productId: pomodoistLifetimeLaunchProductId,
    kind: BillingPlanKind.lifetime,
    fallbackPrice: r'$89.99',
    highlighted: false,
  ),
];

const billingProductIds = {
  pomodoistMonthlyProductId,
  pomodoistAnnualProductId,
  pomodoistLifetimeProductId,
  pomodoistLifetimeLaunchProductId,
};

BillingPlan? billingPlanForProduct(String productId) {
  for (final plan in billingPlans) {
    if (plan.productId == productId) {
      return plan;
    }
  }
  return null;
}

class BillingTransactionProof {
  const BillingTransactionProof({
    required this.productId,
    required this.jws,
    this.transactionId = '',
    this.localVerificationData = '{}',
  });

  final String productId;
  final String jws;
  final String transactionId;
  final String localVerificationData;
}

typedef BillingTransactionLoader =
    Future<List<BillingTransactionProof>> Function();

enum BillingAccessTier { free, monthly, annual, lifetime, pro }

class BillingEntitlement {
  const BillingEntitlement({
    this.appId = '',
    this.entitlementId = '',
    this.status = 'active',
    required this.source,
    required this.purchaseType,
    this.productId,
    this.store,
    this.validUntil,
    this.renewsAt,
  });

  final String appId;
  final String entitlementId;
  final String status;
  final String source;
  final String purchaseType;
  final String? productId;
  final String? store;
  final DateTime? validUntil;
  final DateTime? renewsAt;

  bool get active => status == 'active';
  bool get lifetime => purchaseType == 'lifetime';
  bool get subscription => purchaseType == 'subscription';
}

enum BillingOfferType { introductory, promotional }

enum BillingOfferPaymentMode { freeTrial, payAsYouGo, payUpFront }

enum BillingOfferPeriodUnit { day, week, month, year }

class BillingOffer {
  const BillingOffer({
    required this.id,
    required this.type,
    required this.paymentMode,
    required this.price,
    required this.periodUnit,
    required this.periodValue,
    required this.periodCount,
  });

  final String? id;
  final BillingOfferType type;
  final BillingOfferPaymentMode paymentMode;
  final double price;
  final BillingOfferPeriodUnit periodUnit;
  final int periodValue;
  final int periodCount;
}

class BillingProduct {
  BillingProduct({
    required this.id,
    required this.title,
    required this.description,
    required this.price,
    required this.rawPrice,
    required this.currencyCode,
    required this.currencySymbol,
    List<BillingOffer> offers = const [],
  }) : offers = List.unmodifiable(offers);

  final String id;
  final String title;
  final String description;
  final String price;
  final double rawPrice;
  final String currencyCode;
  final String currencySymbol;
  final List<BillingOffer> offers;
}

const billingReturnOfferIds = {
  pomodoistMonthlyProductId: 'return_monthly_2026_v1',
  pomodoistAnnualProductId: 'return_annual_2026_v1',
};

typedef BillingOfferRequest =
    Future<Object?> Function(Map<String, Object?> body);

class BillingOfferException implements Exception {
  const BillingOfferException(this.code, {this.retryAfter});
  final String code;
  final DateTime? retryAfter;

  @override
  String toString() => 'subscription_offer:$code';
}

class BillingReturnOffers {
  BillingReturnOffers({
    this.transaction,
    Map<String, String> offerIds = const {},
    this.retryAfter,
  }) : offerIds = Map.unmodifiable(offerIds);

  final String? transaction;
  final Map<String, String> offerIds;
  final DateTime? retryAfter;

  factory BillingReturnOffers.fromJson(Object? value, String transaction) {
    if (value is! Map ||
        value['eligible'] is! bool ||
        value['offerIds'] is! Map) {
      throw const FormatException('Invalid subscription offer eligibility.');
    }
    final ids = value['offerIds'] as Map;
    if (ids.entries.any(
          (entry) => billingReturnOfferIds[entry.key] != entry.value,
        ) ||
        (value['eligible'] == false && ids.isNotEmpty) ||
        (value['eligible'] == true && ids.isEmpty)) {
      throw const FormatException('Invalid subscription offer identifiers.');
    }
    final retryAfter = value['retryAfter'] is String
        ? DateTime.tryParse(value['retryAfter'] as String)?.toUtc()
        : null;
    if (value['code'] == 'offer_pending' && retryAfter == null) {
      throw const FormatException('Missing subscription offer retry date.');
    }
    return BillingReturnOffers(
      transaction: transaction,
      offerIds: Map<String, String>.from(ids),
      retryAfter: retryAfter,
    );
  }
}

BillingOffer? billingOfferForProduct(
  BillingProduct? product, {
  bool introductoryEligible = false,
  String? returnOfferId,
}) {
  if (product == null) return null;
  for (final offer in product.offers) {
    if (returnOfferId != null) {
      if (billingReturnOfferIds[product.id] == returnOfferId &&
          offer.id == returnOfferId &&
          offer.type == BillingOfferType.promotional &&
          billingReturnOfferMatchesProduct(product.id, offer)) {
        return offer;
      }
    } else if (introductoryEligible &&
        offer.type == BillingOfferType.introductory) {
      return offer;
    }
  }
  return null;
}

bool billingReturnOfferMatchesProduct(String productId, BillingOffer offer) =>
    offer.price.isFinite &&
    offer.price > 0 &&
    switch (productId) {
      pomodoistMonthlyProductId =>
        offer.paymentMode == BillingOfferPaymentMode.payAsYouGo &&
            offer.periodUnit == BillingOfferPeriodUnit.month &&
            offer.periodValue == 1 &&
            offer.periodCount == 3,
      pomodoistAnnualProductId =>
        offer.paymentMode == BillingOfferPaymentMode.payUpFront &&
            offer.periodUnit == BillingOfferPeriodUnit.year &&
            offer.periodValue == 1 &&
            offer.periodCount == 1,
      _ => false,
    };

String billingOfferSignature(Object? value, String offerId) {
  if (value is! Map ||
      value['offerId'] != offerId ||
      value['compactJws'] is! String) {
    throw const FormatException('Invalid subscription offer signature.');
  }
  final jws = value['compactJws'] as String;
  if (jws.length > 32768 ||
      !RegExp(
        r'^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$',
      ).hasMatch(jws)) {
    throw const FormatException('Invalid subscription offer JWS.');
  }
  return jws;
}

class BillingState {
  BillingState({
    this.loading = true,
    this.platformSupported = true,
    this.storeAvailable = false,
    this.restoring = false,
    Map<String, BillingProduct> productDetailsById = const {},
    Set<String> missingProductIds = const {},
    this.catalogError,
    Set<String> eligibleIntroductoryProductIds = const {},
    Set<String> purchasedProductIds = const {},
    Set<String> activeStoreKitProductIds = const {},
    this.accountEntitlementActive = false,
    this.environmentEntitlementActive = false,
    this.activeAccountEntitlement,
    this.stripeLaunchOfferEligible = false,
    this.stripeLaunchOfferEndsAt,
    this.activeProductId,
    this.pendingProductId,
    this.purchaseSuccessProductId,
    this.error,
  }) : productDetailsById = Map.unmodifiable(productDetailsById),
       missingProductIds = Set.unmodifiable(missingProductIds),
       eligibleIntroductoryProductIds = Set.unmodifiable(
         eligibleIntroductoryProductIds,
       ),
       purchasedProductIds = Set.unmodifiable(purchasedProductIds),
       activeStoreKitProductIds = Set.unmodifiable(activeStoreKitProductIds);

  final bool loading;
  final bool platformSupported;
  final bool storeAvailable;
  final bool restoring;
  final Map<String, BillingProduct> productDetailsById;
  final Set<String> missingProductIds;
  final String? catalogError;
  final Set<String> eligibleIntroductoryProductIds;
  final Set<String> purchasedProductIds;
  final Set<String> activeStoreKitProductIds;
  final bool accountEntitlementActive;
  final bool environmentEntitlementActive;
  final BillingEntitlement? activeAccountEntitlement;
  final bool stripeLaunchOfferEligible;
  final DateTime? stripeLaunchOfferEndsAt;
  final String? activeProductId;
  final String? pendingProductId;
  final String? purchaseSuccessProductId;
  final String? error;

  bool get needsCatalogRetry =>
      !storeAvailable || missingProductIds.isNotEmpty || catalogError != null;

  bool get hasLocalStoreKitEntitlement =>
      pomodoistDevUnlock || activeStoreKitProductIds.isNotEmpty;
  bool get hasActiveEntitlement =>
      hasLocalStoreKitEntitlement ||
      accountEntitlementActive ||
      environmentEntitlementActive;
  bool get canPurchase =>
      platformSupported &&
      storeAvailable &&
      (!loading || productDetailsById.isNotEmpty) &&
      !restoring &&
      pendingProductId == null;

  BillingState copyWith({
    bool? loading,
    bool? platformSupported,
    bool? storeAvailable,
    bool? restoring,
    Map<String, BillingProduct>? productDetailsById,
    Set<String>? missingProductIds,
    Object? catalogError = _unset,
    Set<String>? eligibleIntroductoryProductIds,
    Set<String>? purchasedProductIds,
    Set<String>? activeStoreKitProductIds,
    bool? accountEntitlementActive,
    bool? environmentEntitlementActive,
    Object? activeAccountEntitlement = _unset,
    bool? stripeLaunchOfferEligible,
    Object? stripeLaunchOfferEndsAt = _unset,
    Object? activeProductId = _unset,
    Object? pendingProductId = _unset,
    Object? purchaseSuccessProductId = _unset,
    Object? error = _unset,
  }) {
    return BillingState(
      loading: loading ?? this.loading,
      platformSupported: platformSupported ?? this.platformSupported,
      storeAvailable: storeAvailable ?? this.storeAvailable,
      restoring: restoring ?? this.restoring,
      productDetailsById: productDetailsById ?? this.productDetailsById,
      missingProductIds: missingProductIds ?? this.missingProductIds,
      catalogError: identical(catalogError, _unset)
          ? this.catalogError
          : catalogError as String?,
      eligibleIntroductoryProductIds:
          eligibleIntroductoryProductIds ?? this.eligibleIntroductoryProductIds,
      purchasedProductIds: purchasedProductIds ?? this.purchasedProductIds,
      activeStoreKitProductIds:
          activeStoreKitProductIds ?? this.activeStoreKitProductIds,
      accountEntitlementActive:
          accountEntitlementActive ?? this.accountEntitlementActive,
      environmentEntitlementActive:
          environmentEntitlementActive ?? this.environmentEntitlementActive,
      activeAccountEntitlement: identical(activeAccountEntitlement, _unset)
          ? this.activeAccountEntitlement
          : activeAccountEntitlement as BillingEntitlement?,
      stripeLaunchOfferEligible:
          stripeLaunchOfferEligible ?? this.stripeLaunchOfferEligible,
      stripeLaunchOfferEndsAt: identical(stripeLaunchOfferEndsAt, _unset)
          ? this.stripeLaunchOfferEndsAt
          : stripeLaunchOfferEndsAt as DateTime?,
      activeProductId: identical(activeProductId, _unset)
          ? this.activeProductId
          : activeProductId as String?,
      pendingProductId: identical(pendingProductId, _unset)
          ? this.pendingProductId
          : pendingProductId as String?,
      purchaseSuccessProductId: identical(purchaseSuccessProductId, _unset)
          ? this.purchaseSuccessProductId
          : purchaseSuccessProductId as String?,
      error: identical(error, _unset) ? this.error : error as String?,
    );
  }
}

BillingAccessTier billingAccessTier(BillingState state) {
  if (!state.hasActiveEntitlement) {
    return BillingAccessTier.free;
  }

  if (state.hasLocalStoreKitEntitlement) {
    final localTier = _billingAccessTierForProduct(state.activeProductId);
    if (localTier != null) {
      return localTier;
    }
  }

  final accountEntitlement = state.activeAccountEntitlement;
  final accountTier = _billingAccessTierForProduct(
    accountEntitlement?.productId,
  );
  if (accountTier != null) {
    return accountTier;
  }

  if (accountEntitlement?.lifetime ?? false) {
    return BillingAccessTier.lifetime;
  }
  return BillingAccessTier.pro;
}

BillingAccessTier? _billingAccessTierForProduct(String? productId) {
  return switch (productId) {
    pomodoistMonthlyProductId => BillingAccessTier.monthly,
    pomodoistAnnualProductId => BillingAccessTier.annual,
    pomodoistLifetimeProductId ||
    pomodoistLifetimeLaunchProductId => BillingAccessTier.lifetime,
    _ => null,
  };
}

const _unset = Object();

const billingStoreTimeout = Duration(seconds: 30);
const billingPurchaseTimeout = Duration(minutes: 2);

class BillingStripeGateway {
  const BillingStripeGateway({
    required this.loadCatalog,
    required this.createCheckout,
    required this.openCheckout,
  });

  final Future<StripeBillingCatalog> Function() loadCatalog;
  final Future<Uri> Function(String productId, BillingCheckoutSurface surface)
  createCheckout;
  final Future<bool> Function(Uri url) openCheckout;
}

String? pomodoistEffectiveActiveProductId(String? activeProductId) =>
    activeProductId ?? (pomodoistDevUnlock ? pomodoistLifetimeProductId : null);

DateTime? appleBillingDate(Object? value) {
  if (value is num && value.isFinite) {
    return DateTime.fromMillisecondsSinceEpoch(value.round(), isUtc: true);
  }
  if (value is String && value.trim().isNotEmpty) {
    final milliseconds = num.tryParse(value);
    if (milliseconds != null && milliseconds.isFinite) {
      return DateTime.fromMillisecondsSinceEpoch(
        milliseconds.round(),
        isUtc: true,
      );
    }
    return DateTime.tryParse(value)?.toUtc();
  }
  return null;
}

BillingChannel get defaultBillingChannel =>
    billingChannelForBuild(value: _billingChannelBuildGuard.value);

const _releaseMode = bool.fromEnvironment('dart.vm.product');
