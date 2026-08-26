import 'dart:async';
import 'dart:convert';

import 'package:app_account/app_account.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';
import 'package:intl/intl.dart' as intl;

import '../../app/app_l10n.dart';
import '../../app/legal_urls.dart';
import '../../app/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../focus/presentation/focus_view_mode.dart';

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
        !kReleaseMode || value == 'storekit' || value == 'stripe',
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
  bool releaseMode = kReleaseMode,
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
  const StripeBillingCatalog({
    required this.enabled,
    required this.introEligible,
    required this.launchOfferEligible,
    required this.launchOfferEndsAt,
  });

  final bool enabled;
  final bool introEligible;
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
    final launchEligible = launch['eligible'];
    final endsAtValue = launch['endsAt'];
    final endsAt = endsAtValue is String
        ? DateTime.tryParse(endsAtValue)
        : null;
    if (enabled is! bool ||
        introEligible is! bool ||
        launchEligible is! bool ||
        (launchEligible && endsAt == null)) {
      throw const FormatException('Invalid Stripe catalog.');
    }
    return StripeBillingCatalog(
      enabled: enabled,
      introEligible: introEligible,
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
    fallbackPrice: r'$99',
    highlighted: false,
  ),
  BillingPlan(
    productId: pomodoistLifetimeLaunchProductId,
    kind: BillingPlanKind.lifetime,
    fallbackPrice: r'$89',
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

bool get applePurchasesSupported {
  return !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);
}

String? pomodoistEffectiveActiveProductId(String? activeProductId) {
  return activeProductId ??
      (pomodoistDevUnlock ? pomodoistLifetimeProductId : null);
}

bool pomodoistStoreKitPurchaseIsActive(PurchaseDetails purchase, DateTime now) {
  final plan = billingPlanForProduct(purchase.productID);
  if (plan == null) {
    return false;
  }
  if (pomodoistLocalStoreKit) {
    return true;
  }
  try {
    final decoded = jsonDecode(purchase.verificationData.localVerificationData);
    if (decoded is! Map) {
      return false;
    }
    final value = Map<String, dynamic>.from(decoded);
    if (value['revocationDate'] != null) {
      return false;
    }
    if (plan.kind == BillingPlanKind.lifetime) {
      return true;
    }
    final expiry = _appleDate(value['expiresDate'] ?? value['expirationDate']);
    return expiry != null && expiry.isAfter(now.toUtc());
  } on Object {
    return false;
  }
}

DateTime? _appleDate(Object? value) {
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

class BillingTransactionProof {
  const BillingTransactionProof({required this.productId, required this.jws});

  final String productId;
  final String jws;
}

typedef BillingTransactionLoader =
    Future<List<BillingTransactionProof>> Function();

class BillingStore {
  BillingStore({BillingTransactionLoader? transactionLoader})
    : _transactionLoader = transactionLoader,
      _localPurchases = pomodoistLocalStoreKit
          ? StreamController<List<PurchaseDetails>>.broadcast()
          : null;

  InAppPurchase get _purchase => InAppPurchase.instance;
  final BillingTransactionLoader? _transactionLoader;
  final StreamController<List<PurchaseDetails>>? _localPurchases;
  final _localPurchasedProductIds = <String>{};

  Stream<List<PurchaseDetails>> get purchaseStream =>
      _localPurchases?.stream ?? _purchase.purchaseStream;

  Future<bool> isAvailable() async {
    if (pomodoistLocalStoreKit) {
      return true;
    }
    return _purchase.isAvailable();
  }

  Future<ProductDetailsResponse> queryProductDetails(
    Set<String> productIds,
  ) async {
    if (pomodoistLocalStoreKit) {
      return ProductDetailsResponse(
        productDetails: [
          for (final plan in billingPlans)
            if (productIds.contains(plan.productId))
              ProductDetails(
                id: plan.productId,
                title: plan.productId,
                description: plan.productId,
                price: plan.fallbackPrice,
                rawPrice: 0,
                currencyCode: 'USD',
                currencySymbol: r'$',
              ),
        ],
        notFoundIDs: [
          for (final productId in productIds)
            if (billingPlanForProduct(productId) == null) productId,
        ],
      );
    }
    return _purchase.queryProductDetails(productIds);
  }

  Future<bool> isIntroductoryOfferEligible(String productId) async {
    if (pomodoistLocalStoreKit) {
      return billingPlanForProduct(productId)?.introductoryFallbackPrice !=
          null;
    }
    if (!applePurchasesSupported) {
      return false;
    }
    return SK2Product.isIntroductoryOfferEligible(productId);
  }

  Future<bool> buy(ProductDetails productDetails, {String? appAccountToken}) {
    if (pomodoistLocalStoreKit) {
      _localPurchasedProductIds.add(productDetails.id);
      _localPurchases?.add([
        _localPurchase(productDetails.id, PurchaseStatus.purchased),
      ]);
      return Future.value(true);
    }
    return _purchase.buyNonConsumable(
      purchaseParam: PurchaseParam(
        productDetails: productDetails,
        applicationUserName: appAccountToken,
      ),
    );
  }

  Future<void> restorePurchases() async {
    if (pomodoistLocalStoreKit) {
      _localPurchases?.add([
        for (final productId in _localPurchasedProductIds)
          _localPurchase(productId, PurchaseStatus.restored),
      ]);
      return;
    }
    return _purchase.restorePurchases();
  }

  Future<void> refreshCurrentEntitlements() {
    if (pomodoistLocalStoreKit) {
      return restorePurchases();
    }
    return _purchase.restorePurchases();
  }

  Future<void> completePurchase(PurchaseDetails purchase) {
    if (pomodoistLocalStoreKit) {
      return Future.value();
    }
    return _purchase.completePurchase(purchase);
  }

  Future<List<String>> pomodoistTransactionJws() async {
    if (pomodoistLocalStoreKit) {
      return const [];
    }
    final transactions = await (_transactionLoader ?? _storeKitTransactions)();
    return [
      for (final transaction in transactions)
        if (billingProductIds.contains(transaction.productId) &&
            transaction.jws.isNotEmpty)
          transaction.jws,
    ];
  }

  Future<List<BillingTransactionProof>> _storeKitTransactions() async {
    if (!applePurchasesSupported) {
      return const [];
    }
    final result = Completer<List<BillingTransactionProof>>();
    final subscription = purchaseStream.listen(
      (purchases) {
        final transactions = [
          for (final purchase in purchases)
            if (billingProductIds.contains(purchase.productID) &&
                purchase.verificationData.serverVerificationData.isNotEmpty)
              BillingTransactionProof(
                productId: purchase.productID,
                jws: purchase.verificationData.serverVerificationData,
              ),
        ];
        if (transactions.isNotEmpty && !result.isCompleted) {
          result.complete(transactions);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!result.isCompleted) {
          result.completeError(error, stackTrace);
        }
      },
    );
    try {
      await restorePurchases();
      return await result.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () => const [],
      );
    } finally {
      await subscription.cancel();
    }
  }
}

final billingStoreProvider = Provider<BillingStore>((ref) => BillingStore());

const billingStoreTimeout = Duration(seconds: 30);
const billingPurchaseTimeout = Duration(minutes: 2);

final billingStoreTimeoutProvider = Provider<Duration>(
  (ref) => billingStoreTimeout,
);

final billingPurchaseTimeoutProvider = Provider<Duration>(
  (ref) => billingPurchaseTimeout,
);

final applePurchasesSupportedProvider = Provider<bool>(
  (ref) => applePurchasesSupported,
);

final billingChannelProvider = Provider<BillingChannel>(
  (ref) => billingChannelForBuild(value: _billingChannelBuildGuard.value),
);
final billingStripeGatewayProvider = Provider<BillingStripeGateway?>(
  (ref) => null,
);

final billingActiveAccountEntitlementProvider = Provider<AccountEntitlement?>(
  (ref) => null,
);
final billingAccountEntitlementProvider = Provider<bool>(
  (ref) => ref.watch(billingActiveAccountEntitlementProvider) != null,
);

typedef BillingAppAccountTokenLoader = Future<String?> Function();
typedef BillingPurchaseLinker =
    Future<void> Function(List<String> transactions);
typedef BillingSignInPrompt = Future<void> Function(BuildContext context);
typedef BillingEntitlementRefresher = Future<bool> Function();

final billingSignedInProvider = Provider<bool>((ref) => false);
final billingAccountRefreshTokenProvider = Provider<Object?>((ref) => null);
final billingAppAccountTokenLoaderProvider =
    Provider<BillingAppAccountTokenLoader>(
      (ref) =>
          () async => null,
    );
final billingPurchaseLinkerProvider = Provider<BillingPurchaseLinker?>(
  (ref) => null,
);
final billingSignInPromptProvider = Provider<BillingSignInPrompt?>(
  (ref) => null,
);
final billingEntitlementRefresherProvider =
    Provider<BillingEntitlementRefresher>(
      (ref) =>
          () async => false,
    );
final billingStripePollIntervalProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 3),
);

final billingControllerProvider =
    NotifierProvider<BillingController, BillingState>(BillingController.new);

enum BillingAccessTier { free, monthly, annual, lifetime, pro }

class BillingState {
  const BillingState({
    this.loading = true,
    this.platformSupported = true,
    this.storeAvailable = false,
    this.restoring = false,
    this.productDetailsById = const {},
    this.eligibleIntroductoryProductIds = const {},
    this.purchasedProductIds = const {},
    this.activeStoreKitProductIds = const {},
    this.accountEntitlementActive = false,
    this.activeAccountEntitlement,
    this.stripeLaunchOfferEligible = false,
    this.stripeLaunchOfferEndsAt,
    this.activeProductId,
    this.pendingProductId,
    this.purchaseSuccessProductId,
    this.error,
  });

  final bool loading;
  final bool platformSupported;
  final bool storeAvailable;
  final bool restoring;
  final Map<String, ProductDetails> productDetailsById;
  final Set<String> eligibleIntroductoryProductIds;
  final Set<String> purchasedProductIds;
  final Set<String> activeStoreKitProductIds;
  final bool accountEntitlementActive;
  final AccountEntitlement? activeAccountEntitlement;
  final bool stripeLaunchOfferEligible;
  final DateTime? stripeLaunchOfferEndsAt;
  final String? activeProductId;
  final String? pendingProductId;
  final String? purchaseSuccessProductId;
  final String? error;

  bool get hasLocalStoreKitEntitlement =>
      pomodoistDevUnlock || activeStoreKitProductIds.isNotEmpty;
  bool get hasActiveEntitlement =>
      hasLocalStoreKitEntitlement || accountEntitlementActive;
  bool get canPurchase =>
      platformSupported &&
      storeAvailable &&
      !loading &&
      pendingProductId == null;

  BillingState copyWith({
    bool? loading,
    bool? platformSupported,
    bool? storeAvailable,
    bool? restoring,
    Map<String, ProductDetails>? productDetailsById,
    Set<String>? eligibleIntroductoryProductIds,
    Set<String>? purchasedProductIds,
    Set<String>? activeStoreKitProductIds,
    bool? accountEntitlementActive,
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
      eligibleIntroductoryProductIds:
          eligibleIntroductoryProductIds ?? this.eligibleIntroductoryProductIds,
      purchasedProductIds: purchasedProductIds ?? this.purchasedProductIds,
      activeStoreKitProductIds:
          activeStoreKitProductIds ?? this.activeStoreKitProductIds,
      accountEntitlementActive:
          accountEntitlementActive ?? this.accountEntitlementActive,
      activeAccountEntitlement: identical(activeAccountEntitlement, _unset)
          ? this.activeAccountEntitlement
          : activeAccountEntitlement as AccountEntitlement?,
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

class BillingController extends Notifier<BillingState> {
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  Timer? _purchaseWatchdog;
  final _operationCancellations = <Timer, void Function()>{};
  Future<void>? _silentRefresh;
  var _silentRefreshQueued = false;
  var _explicitRestoreInProgress = false;
  var _skipNextAccountRefresh = false;
  var _signedIn = false;
  final _attemptedTransactionJws = <String>{};

  @override
  BillingState build() {
    final accountEntitlementActive = ref.read(
      billingAccountEntitlementProvider,
    );
    final activeAccountEntitlement = ref.read(
      billingActiveAccountEntitlementProvider,
    );
    ref.listen<bool>(billingAccountEntitlementProvider, (_, next) {
      if (ref.mounted) {
        state = state.copyWith(accountEntitlementActive: next);
      }
    });
    ref.listen<AccountEntitlement?>(billingActiveAccountEntitlementProvider, (
      _,
      next,
    ) {
      if (ref.mounted) {
        state = state.copyWith(activeAccountEntitlement: next);
      }
    });
    _signedIn = ref.read(billingSignedInProvider);
    ref.listen<bool>(billingSignedInProvider, (_, next) {
      final wasSignedIn = _signedIn;
      _signedIn = next;
      if (!wasSignedIn && next) {
        if (ref.read(billingChannelProvider) == BillingChannel.stripe) {
          unawaited(_load());
        } else {
          _attemptedTransactionJws.clear();
          unawaited(_refreshCurrentEntitlements(queueIfRunning: true));
        }
      }
    });
    ref.listen<Object?>(billingAccountRefreshTokenProvider, (previous, next) {
      if (!ref.read(billingSignedInProvider) ||
          next == null ||
          next == previous) {
        return;
      }
      if (_skipNextAccountRefresh) {
        _skipNextAccountRefresh = false;
        return;
      }
      _attemptedTransactionJws.clear();
      unawaited(_refreshCurrentEntitlements(queueIfRunning: true));
    });
    unawaited(_load());
    ref.onDispose(() {
      _purchaseWatchdog?.cancel();
      for (final entry in _operationCancellations.entries.toList()) {
        entry.key.cancel();
        entry.value();
      }
      _operationCancellations.clear();
      unawaited(_subscription?.cancel());
    });
    return BillingState(
      activeProductId: pomodoistEffectiveActiveProductId(null),
      accountEntitlementActive: accountEntitlementActive,
      activeAccountEntitlement: activeAccountEntitlement,
    );
  }

  Future<void> reload() => _load();

  Future<void> purchase(String productId) async {
    if (!state.canPurchase) {
      state = state.copyWith(
        error: 'Purchases are available on Apple devices.',
      );
      return;
    }
    if (ref.read(billingChannelProvider) == BillingChannel.stripe) {
      await _purchaseWithStripe(productId);
      return;
    }
    final details = state.productDetailsById[productId];
    if (details == null) {
      state = state.copyWith(error: 'This product is not available yet.');
      return;
    }
    _cancelPurchaseWatchdog();
    state = state.copyWith(pendingProductId: productId, error: null);
    _startPurchaseWatchdog(productId);
    try {
      String? appAccountToken;
      try {
        appAccountToken = await _withTimeout(
          ref.read(billingAppAccountTokenLoaderProvider)(),
          ref.read(billingStoreTimeoutProvider),
        );
      } on Object {
        // App Store purchasing remains available if account token loading fails.
      }
      if (!ref.mounted) {
        return;
      }
      final sent = await _withTimeout(
        ref
            .read(billingStoreProvider)
            .buy(details, appAccountToken: appAccountToken),
        ref.read(billingPurchaseTimeoutProvider),
      );
      if (!ref.mounted) {
        return;
      }
      if (!sent) {
        _cancelPurchaseWatchdog();
        state = state.copyWith(
          pendingProductId: null,
          error: 'The purchase could not be started.',
        );
      }
    } catch (error) {
      if (!ref.mounted) {
        return;
      }
      _cancelPurchaseWatchdog();
      state = state.copyWith(
        pendingProductId: null,
        error: error is PlatformException && error.code == 'userCancelled'
            ? null
            : '$error',
      );
    }
  }

  Future<void> restorePurchases() async {
    if (ref.read(billingChannelProvider) != BillingChannel.storeKit) {
      return;
    }
    if (!state.platformSupported) {
      state = state.copyWith(
        error: 'Purchases are available on Apple devices.',
      );
      return;
    }
    if (!state.storeAvailable) {
      state = state.copyWith(error: 'The App Store is not available.');
      return;
    }
    state = state.copyWith(restoring: true, error: null);
    _attemptedTransactionJws.clear();
    _explicitRestoreInProgress = true;
    try {
      await _withTimeout(
        ref.read(billingStoreProvider).restorePurchases(),
        ref.read(billingStoreTimeoutProvider),
      );
    } catch (error) {
      if (ref.mounted) {
        state = state.copyWith(error: '$error');
      }
    } finally {
      await Future<void>.delayed(Duration.zero);
      _explicitRestoreInProgress = false;
      if (ref.mounted) {
        state = state.copyWith(restoring: false);
      }
    }
  }

  void clearError() {
    state = state.copyWith(error: null);
  }

  void clearPurchaseSuccess() {
    state = state.copyWith(purchaseSuccessProductId: null);
  }

  Future<void> _load() async {
    final prefs = await ref.read(sharedPreferencesProvider.future);
    if (!ref.mounted) {
      return;
    }
    final activeProductId = pomodoistEffectiveActiveProductId(
      prefs?.getString(billingActiveProductIdPreferenceKey),
    );
    final activeStoreKitProductIds =
        pomodoistLocalStoreKit && activeProductId != null
        ? {activeProductId}
        : const <String>{};
    final purchasedProductIds =
        prefs
            ?.getStringList(billingPurchasedProductIdsPreferenceKey)
            ?.toSet() ??
        const <String>{};

    if (ref.read(billingChannelProvider) == BillingChannel.stripe) {
      await _loadStripe(
        activeProductId: activeProductId,
        activeStoreKitProductIds: activeStoreKitProductIds,
        purchasedProductIds: purchasedProductIds,
      );
      return;
    }

    if (!ref.read(applePurchasesSupportedProvider)) {
      state = state.copyWith(
        loading: false,
        platformSupported: false,
        storeAvailable: false,
        activeProductId: activeProductId,
        activeStoreKitProductIds: activeStoreKitProductIds,
        purchasedProductIds: purchasedProductIds,
      );
      return;
    }

    final store = ref.read(billingStoreProvider);
    final timeout = ref.read(billingStoreTimeoutProvider);
    _subscription ??= store.purchaseStream.listen(
      (purchases) => unawaited(_handlePurchases(purchases)),
      onError: (Object error) {
        if (ref.mounted) {
          _cancelPurchaseWatchdog();
          state = state.copyWith(
            pendingProductId: null,
            restoring: false,
            error: '$error',
          );
        }
      },
    );

    try {
      final available = await _withTimeout(store.isAvailable(), timeout);
      if (!available) {
        if (ref.mounted) {
          state = state.copyWith(
            loading: false,
            storeAvailable: false,
            activeProductId: activeProductId,
            activeStoreKitProductIds: activeStoreKitProductIds,
            purchasedProductIds: purchasedProductIds,
          );
        }
        return;
      }
      final response = await _withTimeout(
        store.queryProductDetails(billingProductIds),
        timeout,
      );
      if (!ref.mounted) {
        return;
      }
      state = state.copyWith(
        loading: false,
        storeAvailable: response.error == null,
        productDetailsById: {
          for (final product in response.productDetails) product.id: product,
        },
        activeProductId: activeProductId,
        activeStoreKitProductIds: activeStoreKitProductIds,
        purchasedProductIds: purchasedProductIds,
        error: response.error?.message,
      );
      final eligibleProductIds = <String>{};
      for (final product in response.productDetails) {
        if (billingPlanForProduct(product.id)?.introductoryFallbackPrice ==
            null) {
          continue;
        }
        try {
          if (await _withTimeout(
            store.isIntroductoryOfferEligible(product.id),
            timeout,
          )) {
            eligibleProductIds.add(product.id);
          }
        } catch (_) {
          // StoreKit eligibility can fail independently of catalog loading.
        }
      }
      if (ref.mounted) {
        state = state.copyWith(
          eligibleIntroductoryProductIds: eligibleProductIds,
        );
      }
      if (ref.mounted && state.storeAvailable) {
        await _refreshCurrentEntitlements();
      }
    } catch (error) {
      if (ref.mounted) {
        state = state.copyWith(
          loading: false,
          storeAvailable: false,
          activeProductId: activeProductId,
          activeStoreKitProductIds: activeStoreKitProductIds,
          purchasedProductIds: purchasedProductIds,
          error: '$error',
        );
      }
    }
  }

  Future<void> _loadStripe({
    required String? activeProductId,
    required Set<String> activeStoreKitProductIds,
    required Set<String> purchasedProductIds,
  }) async {
    if (!ref.read(billingSignedInProvider)) {
      state = state.copyWith(
        loading: false,
        platformSupported: true,
        storeAvailable: true,
        activeProductId: activeProductId,
        activeStoreKitProductIds: activeStoreKitProductIds,
        purchasedProductIds: purchasedProductIds,
        stripeLaunchOfferEligible: false,
        stripeLaunchOfferEndsAt: null,
        error: null,
      );
      return;
    }
    final gateway = ref.read(billingStripeGatewayProvider);
    if (gateway == null) {
      state = state.copyWith(
        loading: false,
        platformSupported: true,
        storeAvailable: false,
        error: 'Stripe billing is not configured.',
      );
      return;
    }
    try {
      final catalog = await _withTimeout(
        gateway.loadCatalog(),
        ref.read(billingStoreTimeoutProvider),
      );
      if (!ref.mounted) return;
      state = state.copyWith(
        loading: false,
        platformSupported: true,
        storeAvailable: catalog.enabled,
        activeProductId: activeProductId,
        activeStoreKitProductIds: activeStoreKitProductIds,
        purchasedProductIds: purchasedProductIds,
        eligibleIntroductoryProductIds: catalog.introEligible
            ? const {pomodoistMonthlyProductId, pomodoistAnnualProductId}
            : const {},
        stripeLaunchOfferEligible: catalog.launchOfferEligible,
        stripeLaunchOfferEndsAt: catalog.launchOfferEndsAt,
        error: null,
      );
    } catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(
        loading: false,
        platformSupported: true,
        storeAvailable: false,
        error: '$error',
      );
    }
  }

  Future<void> _purchaseWithStripe(String productId) async {
    if (!billingProductIds.contains(productId)) {
      state = state.copyWith(error: 'This product is not available yet.');
      return;
    }
    if (!ref.read(billingSignedInProvider)) {
      state = state.copyWith(error: 'Sign in to continue.');
      return;
    }
    final gateway = ref.read(billingStripeGatewayProvider);
    if (gateway == null) {
      state = state.copyWith(error: 'Stripe billing is not configured.');
      return;
    }
    state = state.copyWith(pendingProductId: productId, error: null);
    try {
      final url = await _withTimeout(
        gateway.createCheckout(
          productId,
          kIsWeb ? BillingCheckoutSurface.web : BillingCheckoutSurface.native,
        ),
        ref.read(billingStoreTimeoutProvider),
      );
      if (url.scheme != 'https') {
        throw StateError('Stripe returned an unsafe checkout URL.');
      }
      final opened = await gateway.openCheckout(url);
      if (!opened) throw StateError('Could not open Stripe Checkout.');
      if (ref.mounted) state = state.copyWith(pendingProductId: null);
    } catch (error) {
      if (ref.mounted) {
        state = state.copyWith(pendingProductId: null, error: '$error');
      }
    }
  }

  Future<void> _handlePurchases(List<PurchaseDetails> purchases) async {
    if (!ref.mounted) {
      return;
    }
    final explicitRestore = _explicitRestoreInProgress;
    if (purchases.isEmpty) {
      return;
    }
    final transactionJws = <String>[];
    for (final purchase in purchases) {
      if (!ref.mounted) {
        return;
      }
      if (!billingProductIds.contains(purchase.productID)) {
        continue;
      }
      switch (purchase.status) {
        case PurchaseStatus.pending:
          if (state.pendingProductId == null ||
              state.pendingProductId == purchase.productID) {
            state = state.copyWith(pendingProductId: purchase.productID);
            _startPurchaseWatchdog(purchase.productID);
          }
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          final matchesPending = state.pendingProductId == purchase.productID;
          if (matchesPending) {
            _cancelPurchaseWatchdog();
          }
          try {
            final active = pomodoistStoreKitPurchaseIsActive(
              purchase,
              DateTime.now(),
            );
            if (active) {
              await _activate(purchase.productID);
            } else {
              await _deactivate(purchase.productID);
            }
            if (!ref.mounted) {
              return;
            }
            state = state.copyWith(
              pendingProductId: matchesPending ? null : state.pendingProductId,
              purchaseSuccessProductId:
                  active && (matchesPending || explicitRestore)
                  ? purchase.productID
                  : state.purchaseSuccessProductId,
              error: null,
            );
          } catch (error) {
            if (!ref.mounted) {
              return;
            }
            state = state.copyWith(
              pendingProductId: matchesPending ? null : state.pendingProductId,
              error: '$error',
            );
          }
          final jws = purchase.verificationData.serverVerificationData;
          if (jws.isNotEmpty) {
            transactionJws.add(jws);
          }
        case PurchaseStatus.error:
          if (state.pendingProductId != null &&
              state.pendingProductId != purchase.productID) {
            break;
          }
          _cancelPurchaseWatchdog();
          state = state.copyWith(
            pendingProductId: null,
            error: purchase.error?.message ?? 'Purchase failed.',
          );
        case PurchaseStatus.canceled:
          if (state.pendingProductId != null &&
              state.pendingProductId != purchase.productID) {
            break;
          }
          _cancelPurchaseWatchdog();
          state = state.copyWith(pendingProductId: null);
      }
      if (purchase.pendingCompletePurchase &&
          purchase.status != PurchaseStatus.pending) {
        try {
          await _withTimeout(
            ref.read(billingStoreProvider).completePurchase(purchase),
            ref.read(billingStoreTimeoutProvider),
          );
        } on Object {
          // StoreKit has already delivered the verified purchase. Finishing is
          // retried by StoreKit and must not turn success into a user error.
        }
      }
    }
    final linker = ref.read(billingSignedInProvider)
        ? ref.read(billingPurchaseLinkerProvider)
        : null;
    final unattemptedJws = transactionJws
        .toSet()
        .difference(_attemptedTransactionJws)
        .toList(growable: false);
    if (linker != null && unattemptedJws.isNotEmpty) {
      _attemptedTransactionJws.addAll(unattemptedJws);
      try {
        await linker(unattemptedJws);
        _skipNextAccountRefresh = true;
      } on Object {
        // Account synchronization is best-effort after local StoreKit access
        // is active and must not be presented as a failed purchase.
      }
    }
  }

  Future<void> _refreshCurrentEntitlements({bool queueIfRunning = false}) {
    if (!ref.mounted || !state.storeAvailable) {
      return Future.value();
    }
    final existing = _silentRefresh;
    if (existing != null) {
      _silentRefreshQueued |= queueIfRunning;
      return existing;
    }
    final operation = _runSilentRefresh();
    _silentRefresh = operation;
    operation.then<void>((_) {
      if (identical(_silentRefresh, operation)) {
        _silentRefresh = null;
        if (_silentRefreshQueued) {
          _silentRefreshQueued = false;
          unawaited(_refreshCurrentEntitlements());
        }
      }
    });
    return operation;
  }

  Future<void> _runSilentRefresh() async {
    if (!pomodoistLocalStoreKit && ref.mounted) {
      state = state.copyWith(activeStoreKitProductIds: const <String>{});
    }
    try {
      await _withTimeout(
        ref.read(billingStoreProvider).refreshCurrentEntitlements(),
        ref.read(billingStoreTimeoutProvider),
      );
    } on Object {
      // Silent StoreKit refreshes do not surface restore feedback.
    }
  }

  void _startPurchaseWatchdog(String productId) {
    _purchaseWatchdog?.cancel();
    _purchaseWatchdog = Timer(ref.read(billingPurchaseTimeoutProvider), () {
      if (!ref.mounted || state.pendingProductId != productId) {
        return;
      }
      _purchaseWatchdog = null;
      state = state.copyWith(
        pendingProductId: null,
        restoring: false,
        error: 'The purchase timed out. Please try again.',
      );
    });
  }

  void _cancelPurchaseWatchdog() {
    _purchaseWatchdog?.cancel();
    _purchaseWatchdog = null;
  }

  Future<T> _withTimeout<T>(Future<T> operation, Duration timeout) {
    final completer = Completer<T>();
    late final Timer timer;
    timer = Timer(timeout, () {
      _operationCancellations.remove(timer);
      if (!completer.isCompleted) {
        completer.completeError(
          TimeoutException('Billing operation timed out.', timeout),
        );
      }
    });
    _operationCancellations[timer] = () {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError('Billing operation canceled because it was disposed.'),
        );
      }
    };
    operation.then(
      (value) {
        timer.cancel();
        _operationCancellations.remove(timer);
        if (!completer.isCompleted) {
          completer.complete(value);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        timer.cancel();
        _operationCancellations.remove(timer);
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      },
    );
    return completer.future;
  }

  Future<void> _activate(String productId) async {
    final prefs = await ref.read(sharedPreferencesProvider.future);
    final purchased = {...state.purchasedProductIds, productId};
    final active = {...state.activeStoreKitProductIds, productId};
    await prefs?.setString(billingActiveProductIdPreferenceKey, productId);
    await prefs?.setStringList(
      billingPurchasedProductIdsPreferenceKey,
      purchased.toList()..sort(),
    );
    if (ref.mounted) {
      state = state.copyWith(
        activeProductId: productId,
        activeStoreKitProductIds: active,
        purchasedProductIds: purchased,
      );
    }
  }

  Future<void> _deactivate(String productId) async {
    if (!state.activeStoreKitProductIds.contains(productId)) {
      return;
    }
    final active = {...state.activeStoreKitProductIds}..remove(productId);
    final nextProductId = state.activeProductId == productId
        ? active.firstOrNull
        : state.activeProductId;
    final prefs = await ref.read(sharedPreferencesProvider.future);
    if (nextProductId == null) {
      await prefs?.remove(billingActiveProductIdPreferenceKey);
    } else if (nextProductId != state.activeProductId) {
      await prefs?.setString(
        billingActiveProductIdPreferenceKey,
        nextProductId,
      );
    }
    if (ref.mounted) {
      state = state.copyWith(
        activeProductId: nextProductId,
        activeStoreKitProductIds: active,
      );
    }
  }
}

PurchaseDetails _localPurchase(String productId, PurchaseStatus status) {
  return PurchaseDetails(
    productID: productId,
    purchaseID: 'local-$productId',
    transactionDate: DateTime.now().millisecondsSinceEpoch.toString(),
    status: status,
    verificationData: PurchaseVerificationData(
      localVerificationData: productId,
      serverVerificationData: productId,
      source: 'pomodoist-local-storekit',
    ),
  );
}

class BillingPaywall extends ConsumerWidget {
  const BillingPaywall({
    super.key,
    this.compact = false,
    this.onClose,
    this.launchOfferTimerLabel,
    this.launchOfferMode = false,
    this.showPlansWhenActive = false,
  });

  final bool compact;
  final VoidCallback? onClose;
  final String? launchOfferTimerLabel;
  final bool launchOfferMode;
  final bool showPlansWhenActive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<String?>(
      billingControllerProvider.select(
        (state) => state.purchaseSuccessProductId,
      ),
      (previous, next) {
        if (next == null || previous == next) {
          return;
        }
        _showPurchaseSuccess(context, ref);
      },
    );

    final state = ref.watch(billingControllerProvider);
    final channel = ref.watch(billingChannelProvider);
    final l10n = context.l10n;
    final colors = context.appColors;
    final textTheme = Theme.of(context).textTheme;
    final collapsedActive = state.hasActiveEntitlement && !showPlansWhenActive;
    final plans = billingPlans.where(
      (plan) => launchOfferMode
          ? plan.productId != pomodoistLifetimeProductId
          : plan.productId != pomodoistLifetimeLaunchProductId,
    );
    final lifetimeCompareAtPrice = launchOfferMode
        ? state.productDetailsById[pomodoistLifetimeProductId]?.price ??
              billingPlanForProduct(pomodoistLifetimeProductId)?.fallbackPrice
        : null;
    return Column(
      key: const Key('billing-paywall'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _BillingProHeader(
                compact: compact,
                onTap: collapsedActive ? () => _showOffers(context) : null,
              ),
            ),
            if (onClose != null) ...[
              const SizedBox(width: 8),
              IconButton(
                key: const Key('billing-paywall-close'),
                tooltip: l10n.commonClose,
                onPressed: onClose,
                icon: const Icon(Icons.close),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        if (state.hasActiveEntitlement) ...[
          Card(
            color: colors.accentTint,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(Icons.verified_outlined, color: colors.accent),
                  const SizedBox(width: 10),
                  Expanded(child: Text(l10n.billingActive)),
                ],
              ),
            ),
          ),
          if (state.activeAccountEntitlement case final entitlement?
              when entitlement.source == 'stripe' && entitlement.subscription)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('billing-manage-link'),
                onPressed: () {
                  final gateway = ref.read(billingStripeGatewayProvider);
                  if (gateway != null) {
                    unawaited(
                      gateway.openCheckout(Uri.parse('https://link.com')),
                    );
                  }
                },
                icon: const Icon(Icons.open_in_new),
                label: Text(l10n.billingManageLink),
              ),
            ),
          const SizedBox(height: 12),
        ],
        if (!collapsedActive) ...[
          if (state.loading) ...[
            const LinearProgressIndicator(minHeight: 2),
            const SizedBox(height: 10),
          ],
          for (final plan in plans) ...[
            _BillingPlanTile(
              plan: plan,
              state: state,
              forceIntroductoryPrice:
                  launchOfferMode &&
                  (plan.productId == pomodoistAnnualProductId ||
                      plan.productId == pomodoistMonthlyProductId),
              compareAtPrice: switch (plan.productId) {
                pomodoistLifetimeLaunchProductId => lifetimeCompareAtPrice,
                _ => null,
              },
              launchOfferTimerLabel:
                  plan.productId == pomodoistLifetimeLaunchProductId
                  ? launchOfferTimerLabel
                  : null,
            ),
            const SizedBox(height: 10),
          ],
          if (!state.platformSupported ||
              (channel == BillingChannel.stripe &&
                  !state.storeAvailable &&
                  !state.loading &&
                  state.error == null))
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                l10n.billingAppleOnly,
                style: textTheme.bodySmall?.copyWith(
                  color: colors.secondaryText,
                ),
              ),
            )
          else if (channel == BillingChannel.storeKit &&
              !state.storeAvailable &&
              !state.loading)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                l10n.billingStoreUnavailable,
                style: textTheme.bodySmall?.copyWith(
                  color: colors.secondaryText,
                ),
              ),
            ),
          if (state.error != null) ...[
            const SizedBox(height: 8),
            Text(
              l10n.billingPurchaseError(state.error!),
              style: textTheme.bodySmall?.copyWith(color: colors.accent),
            ),
          ],
          const SizedBox(height: 8),
          if (channel == BillingChannel.storeKit)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('billing-restore-button'),
                onPressed:
                    state.platformSupported &&
                        state.storeAvailable &&
                        !state.restoring
                    ? () => ref
                          .read(billingControllerProvider.notifier)
                          .restorePurchases()
                    : null,
                icon: state.restoring
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.restore),
                label: Text(l10n.billingRestore),
              ),
            ),
        ],
        const SizedBox(height: 4),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 4,
          children: [
            TextButton(
              key: const Key('billing-privacy-policy'),
              onPressed: () => unawaited(
                launchPomodoistExternalUrl(pomodoistPrivacyPolicyUrl),
              ),
              child: Text(l10n.privacyPolicy),
            ),
            TextButton(
              key: const Key('billing-terms-of-use'),
              onPressed: () =>
                  unawaited(launchPomodoistExternalUrl(pomodoistTermsOfUseUrl)),
              child: Text(l10n.termsOfUse),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _showOffers(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      builder: (context) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: BillingPaywall(
          compact: true,
          onClose: () => Navigator.of(context).pop(),
          launchOfferMode: launchOfferMode,
          launchOfferTimerLabel: launchOfferTimerLabel,
          showPlansWhenActive: true,
        ),
      ),
    );
  }
}

void _showPurchaseSuccess(BuildContext context, WidgetRef ref) {
  final route = ModalRoute.of(context);
  if (route != null && !route.isCurrent) {
    return;
  }
  final router = GoRouter.maybeOf(context);
  if (router == null) {
    ref.read(billingControllerProvider.notifier).clearPurchaseSuccess();
    return;
  }

  final returnTo = router.routeInformationProvider.value.uri.toString();
  if (route is PopupRoute) {
    Navigator.of(context).pop();
  }
  router.go(
    Uri(
      path: '/purchase-success',
      queryParameters: {'returnTo': returnTo},
    ).toString(),
  );
  ref.read(billingControllerProvider.notifier).clearPurchaseSuccess();
}

class _BillingProHeader extends StatelessWidget {
  const _BillingProHeader({required this.compact, this.onTap});

  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final textTheme = Theme.of(context).textTheme;
    final iconSize = compact ? 36.0 : 40.0;

    final borderRadius = BorderRadius.circular(10);
    final content = Padding(
      padding: EdgeInsets.all(compact ? 14 : 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surface.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(10),
            ),
            child: SizedBox.square(
              dimension: iconSize,
              child: Icon(
                Icons.mic_none_rounded,
                color: colors.accent,
                size: compact ? 19 : 21,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.billingTitle,
                  style:
                      (compact ? textTheme.titleLarge : textTheme.headlineSmall)
                          ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text.rich(
                  _highlightedBillingSubtitle(
                    text: l10n.billingSubtitle,
                    highlight: l10n.billingSubtitleHighlight,
                    baseStyle: textTheme.bodyMedium?.copyWith(
                      color: colors.secondaryText,
                      height: 1.35,
                    ),
                    highlightStyle: textTheme.bodyMedium?.copyWith(
                      color: colors.accent,
                      fontWeight: FontWeight.w800,
                      height: 1.35,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.billingCancelAnytime,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.accentTint,
        borderRadius: borderRadius,
        border: Border.all(color: colors.accent.withValues(alpha: 0.24)),
      ),
      child: onTap == null
          ? content
          : Material(
              color: Colors.transparent,
              child: InkWell(
                key: const Key('billing-pro-header'),
                borderRadius: borderRadius,
                onTap: onTap,
                child: content,
              ),
            ),
    );
  }
}

TextSpan _highlightedBillingSubtitle({
  required String text,
  required String highlight,
  required TextStyle? baseStyle,
  required TextStyle? highlightStyle,
}) {
  final index = text.indexOf(highlight);
  if (highlight.isEmpty || index < 0) {
    return TextSpan(text: text, style: baseStyle);
  }
  return TextSpan(
    style: baseStyle,
    children: [
      TextSpan(text: text.substring(0, index)),
      TextSpan(
        text: highlight,
        style:
            highlightStyle ?? baseStyle?.copyWith(fontWeight: FontWeight.w800),
      ),
      TextSpan(text: text.substring(index + highlight.length)),
    ],
  );
}

class _BillingPlanTile extends ConsumerWidget {
  const _BillingPlanTile({
    required this.plan,
    required this.state,
    required this.forceIntroductoryPrice,
    this.compareAtPrice,
    this.launchOfferTimerLabel,
  });

  final BillingPlan plan;
  final BillingState state;
  final bool forceIntroductoryPrice;
  final String? compareAtPrice;
  final String? launchOfferTimerLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final product = state.productDetailsById[plan.productId];
    final channel = ref.watch(billingChannelProvider);
    final signedIn = ref.watch(billingSignedInProvider);
    final productRequired = channel == BillingChannel.storeKit;
    final active = state.activeProductId == plan.productId;
    final pending = state.pendingProductId == plan.productId;
    final highlighted = plan.highlighted;
    final background = highlighted ? colors.accentTint : colors.surface;
    final border = highlighted ? colors.accent : colors.border;
    final regularPrice = _regularPrice(l10n, plan, product);
    final introductoryPrice =
        forceIntroductoryPrice ||
            state.eligibleIntroductoryProductIds.contains(plan.productId)
        ? _introductoryPrice(context, l10n, plan, product)
        : null;
    final displayedPrice = introductoryPrice ?? regularPrice;
    final displayedCompareAtPrice =
        compareAtPrice ?? (introductoryPrice == null ? null : regularPrice);
    final subtitle = _planSubtitle(
      l10n,
      plan,
      regularPrice,
      hasIntroductoryPrice: introductoryPrice != null,
    );

    return Card(
      key: ValueKey('billing-plan-${plan.productId}'),
      color: background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: border, width: highlighted ? 1.5 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        _planTitle(l10n, plan),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (highlighted)
                        _Badge(
                          label: l10n.billingBestValue,
                          color: colors.accent,
                        ),
                      if (launchOfferTimerLabel != null)
                        _Badge(
                          key: const Key('launch-offer-countdown'),
                          label: launchOfferTimerLabel!,
                          color: colors.accent,
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        displayedPrice,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      if (displayedCompareAtPrice != null)
                        Text(
                          displayedCompareAtPrice,
                          key: ValueKey('billing-compare-${plan.productId}'),
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: colors.secondaryText,
                                decoration: TextDecoration.lineThrough,
                                decorationThickness: 2,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.secondaryText,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              key: ValueKey('billing-buy-${plan.productId}'),
              onPressed:
                  active ||
                      pending ||
                      !state.canPurchase ||
                      (productRequired && product == null)
                  ? null
                  : () async {
                      if (channel == BillingChannel.stripe && !signedIn) {
                        final prompt = ref.read(billingSignInPromptProvider);
                        if (prompt != null) {
                          await prompt(context);
                          return;
                        }
                      }
                      if (channel == BillingChannel.stripe) {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (dialogContext) => AlertDialog(
                            title: Text(l10n.billingExternalBrowserTitle),
                            content: Text(l10n.billingExternalBrowserMessage),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(false),
                                child: Text(l10n.commonCancel),
                              ),
                              FilledButton(
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(true),
                                child: Text(l10n.commonOpen),
                              ),
                            ],
                          ),
                        );
                        if (confirmed != true || !context.mounted) return;
                      }
                      await ref
                          .read(billingControllerProvider.notifier)
                          .purchase(plan.productId);
                    },
              child: pending
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(active ? l10n.billingActiveShort : l10n.billingChoose),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color, super.key});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

String _planTitle(AppLocalizations l10n, BillingPlan plan) {
  return switch (plan.productId) {
    pomodoistMonthlyProductId => l10n.billingMonthlyTitle,
    pomodoistAnnualProductId => l10n.billingAnnualTitle,
    pomodoistLifetimeProductId => l10n.billingLifetimeTitle,
    pomodoistLifetimeLaunchProductId => l10n.billingLifetimeTitle,
    _ => plan.productId,
  };
}

String _regularPrice(
  AppLocalizations l10n,
  BillingPlan plan,
  ProductDetails? product,
) {
  if (product == null) {
    return plan.fallbackPrice;
  }
  if (product.price == plan.fallbackPrice) {
    return plan.fallbackPrice;
  }
  return _priceWithPeriod(l10n, plan, product.price);
}

String? _introductoryPrice(
  BuildContext context,
  AppLocalizations l10n,
  BillingPlan plan,
  ProductDetails? product,
) {
  if (product is AppStoreProduct2Details) {
    for (final offer
        in product.sk2Product.subscription?.promotionalOffers ??
            const <SK2SubscriptionOffer>[]) {
      if (offer.type == SK2SubscriptionOfferType.introductory) {
        final price = intl.NumberFormat.simpleCurrency(
          name: product.currencyCode,
          locale: Localizations.localeOf(context).toLanguageTag(),
        ).format(offer.price);
        return _priceWithPeriod(l10n, plan, price);
      }
    }
    return null;
  }
  return plan.introductoryFallbackPrice;
}

String _priceWithPeriod(AppLocalizations l10n, BillingPlan plan, String price) {
  return switch (plan.productId) {
    pomodoistMonthlyProductId => l10n.billingPricePerMonth(price),
    pomodoistAnnualProductId => l10n.billingPricePerYear(price),
    _ => price,
  };
}

String _planSubtitle(
  AppLocalizations l10n,
  BillingPlan plan,
  String regularPrice, {
  required bool hasIntroductoryPrice,
}) {
  return switch (plan.productId) {
    pomodoistMonthlyProductId when hasIntroductoryPrice =>
      l10n.billingMonthlyIntroSubtitle(regularPrice),
    pomodoistAnnualProductId when hasIntroductoryPrice =>
      l10n.billingAnnualIntroSubtitle(regularPrice),
    pomodoistLifetimeProductId => l10n.billingLifetimeSubtitle,
    pomodoistLifetimeLaunchProductId => l10n.billingLifetimeSubtitle,
    _ => '',
  };
}
