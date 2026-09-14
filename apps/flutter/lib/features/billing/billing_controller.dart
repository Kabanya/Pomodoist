import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:app_account/app_account.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../../core/time/clock_provider.dart';
import '../focus/presentation/focus_view_mode.dart';
import 'billing_models.dart';
import 'billing_store.dart';
import 'billing_offers.dart';

bool _isTransientStoreKitError(Object error) {
  final message = '$error';
  return message.contains('NSURLErrorDomain') &&
      RegExp(r'-(?:1001|1003|1004|1005|1008|1009)\b').hasMatch(message);
}

bool _isStoreKitCancelled(Object error) =>
    error is PlatformException &&
    (error.code == 'userCancelled' ||
        RegExp(
          r'\buserCancelled\b|\bSKErrorDomain\b[^\n]*\bCode=2\b',
        ).hasMatch('${error.details}'));

void _recordStoreKitError(String stage, Object error) {
  var code = switch (error) {
    PlatformException() => error.code,
    IAPError() => error.code,
    _ => error.runtimeType.toString(),
  };
  code = code.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '');
  if (code.length > 80) code = code.substring(0, 80);
  final native = RegExp(
    r'([A-Za-z][A-Za-z0-9_.]*ErrorDomain)[^\n]*?(?:Code[=:]\s*|error\s+)(-?\d+)',
  ).allMatches('$error').map((m) => '${m[1]}:${m[2]}').toSet();
  if (error case PlatformException(details: final Map details)) {
    final domain = details['domain'];
    final number = details['code'];
    if (domain is String &&
        number is num &&
        RegExp(r'^[A-Za-z0-9_.]{1,80}$').hasMatch(domain)) {
      native.add('$domain:$number');
    }
  }
  developer.log(
    '$stage code=$code native=${native.join(',')}',
    name: 'pomodoist.storekit',
  );
}

final billingStoreProvider = Provider<BillingStore>((ref) => BillingStore());

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
  (ref) => defaultBillingChannel,
);
final billingStripeGatewayProvider = Provider<BillingStripeGateway?>(
  (ref) => null,
);

final billingOfferRequestProvider = Provider<BillingOfferRequest?>(
  (ref) => null,
);

// Read history only while a paywall needs it; expired purchases never grant Pro.
final billingReturnOffersProvider =
    FutureProvider.autoDispose<BillingReturnOffers>((ref) async {
      final channel = ref.watch(billingChannelProvider);
      final access = ref.watch(
        billingControllerProvider.select(
          (state) => (state.hasActiveEntitlement, state.storeAvailable),
        ),
      );
      ref.watch(billingAccountIdentityProvider);
      final request = ref.watch(billingOfferRequestProvider);
      if (channel != BillingChannel.storeKit ||
          access.$1 ||
          !access.$2 ||
          request == null) {
        return const BillingReturnOffers();
      }
      final proof = await ref
          .read(billingStoreProvider)
          .latestSubscriptionTransaction();
      if (proof == null) return const BillingReturnOffers();
      final response = await request({
        'action': 'eligibility',
        'transaction': proof.jws,
      }).timeout(billingStoreTimeout);
      return BillingReturnOffers.fromJson(response, proof.jws);
    });

final billingActiveAccountEntitlementProvider = Provider<AccountEntitlement?>(
  (ref) => null,
);
final billingAccountEntitlementProvider = Provider<bool>(
  (ref) => ref.watch(billingActiveAccountEntitlementProvider) != null,
);
final billingEnvironmentEntitlementProvider = Provider<bool>((ref) => false);

typedef BillingAppAccountTokenLoader = Future<String?> Function();
typedef BillingPurchaseLinker =
    Future<void> Function(List<String> transactions);
typedef BillingSignInPrompt = Future<void> Function(BuildContext context);
typedef BillingEntitlementRefresher = Future<bool> Function();

final billingSignedInProvider = Provider<bool>((ref) => false);
final billingAccountIdentityProvider = Provider<Object?>((ref) => null);
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

class BillingController extends Notifier<BillingState> {
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  Future<void>? _catalogLoad;
  Timer? _purchaseWatchdog;
  Timer? _expiryTimer;
  Future<void> _stateChanges = Future<void>.value();
  final _verifiedTransactions = <String, BillingTransactionProof>{};
  final _purchasesToFinish = <String, PurchaseDetails>{};
  final _finishingPurchases = <String>{};
  var _entitlementRevision = 0;
  String? _purchaseToConfirm;
  var _accountGeneration = 0;
  final _operationCancellations = <Timer, void Function()>{};
  Future<void>? _silentRefresh;
  var _silentRefreshQueued = false;
  var _explicitRestoreInProgress = false;
  var _restoreSuccessPending = false;
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
    final environmentEntitlementActive = ref.read(
      billingEnvironmentEntitlementProvider,
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
    ref.listen<Object?>(billingAccountIdentityProvider, (previous, next) {
      if (previous == next) return;
      _accountGeneration += 1;
      _attemptedTransactionJws.clear();
      _skipNextAccountRefresh = false;
      if (ref.read(billingSignedInProvider)) {
        unawaited(_refreshCurrentEntitlements(queueIfRunning: true));
      }
    });
    ref.listen<bool>(billingSignedInProvider, (_, next) {
      final wasSignedIn = _signedIn;
      _signedIn = next;
      _accountGeneration += 1;
      _attemptedTransactionJws.clear();
      _skipNextAccountRefresh = false;
      if (!wasSignedIn && next) {
        if (ref.read(billingChannelProvider) == BillingChannel.stripe) {
          unawaited(reload());
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
    final lifecycleListener = AppLifecycleListener(
      onResume: () {
        if (!ref.mounted ||
            ref.read(billingChannelProvider) != BillingChannel.storeKit ||
            !state.platformSupported) {
          return;
        }
        unawaited(_changeEntitlements(_commitEntitlements));
        if (state.needsCatalogRetry && !state.loading && !state.restoring) {
          unawaited(reload());
        } else if (!state.restoring) {
          unawaited(_refreshCurrentEntitlements());
        }
      },
    );
    unawaited(reload());
    ref.onDispose(() {
      lifecycleListener.dispose();
      _purchaseWatchdog?.cancel();
      _expiryTimer?.cancel();
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
      environmentEntitlementActive: environmentEntitlementActive,
      activeAccountEntitlement: activeAccountEntitlement,
    );
  }

  Future<void> reload() => _catalogLoad ??= _load().whenComplete(() {
    _catalogLoad = null;
  });

  Future<void> purchase(String productId, {String? returnOfferId}) async {
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
    final accountGeneration = _accountGeneration;
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
      // Resolve pending auth changes before starting the native purchase.
      ref.read(billingAccountIdentityProvider);
      if (accountGeneration != _accountGeneration) {
        _cancelPurchaseWatchdog();
        state = state.copyWith(pendingProductId: null);
        return;
      }
      final store = ref.read(billingStoreProvider);
      Future<bool> purchase;
      if (returnOfferId != null) {
        final offer = billingStoreKitOffer(
          details,
          returnOfferId: returnOfferId,
        );
        final request = ref.read(billingOfferRequestProvider);
        final proof = await store.latestSubscriptionTransaction();
        if (offer == null ||
            request == null ||
            proof == null ||
            state.hasActiveEntitlement) {
          throw const BillingOfferException('not_eligible');
        }
        final response = await _withTimeout(
          request({
            'action': 'sign',
            'transaction': proof.jws,
            'productId': productId,
            'appAccountToken': ?appAccountToken,
          }),
          ref.read(billingStoreTimeoutProvider),
        );
        final signature = billingOfferSignature(response, returnOfferId);
        if (!ref.mounted) return;
        ref.read(billingAccountIdentityProvider);
        if (accountGeneration != _accountGeneration ||
            state.hasActiveEntitlement) {
          throw const BillingOfferException('not_eligible');
        }
        purchase = store
            .buyPromotional(
              details,
              offer,
              signature,
              appAccountToken: appAccountToken,
            )
            .then((result) async {
              if (ref.mounted) await _handlePurchases([result]);
              return true;
            });
      } else {
        purchase = store.buy(details, appAccountToken: appAccountToken);
      }
      final sent = await _withTimeout(
        purchase,
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
      if (!_isStoreKitCancelled(error)) _recordStoreKitError('purchase', error);
      _cancelPurchaseWatchdog();
      state = state.copyWith(
        pendingProductId: null,
        error: _isStoreKitCancelled(error)
            ? null
            : returnOfferId == null
            ? '$error'
            : 'subscription_offer:${error is BillingOfferException ? error.code : 'verification_failed'}',
      );
    } finally {
      if (returnOfferId != null && ref.mounted) {
        ref.invalidate(billingReturnOffersProvider);
      }
    }
  }

  Future<void> restorePurchases() async {
    if (ref.read(billingChannelProvider) != BillingChannel.storeKit ||
        !state.platformSupported ||
        state.restoring ||
        state.pendingProductId != null) {
      return;
    }
    state = state.copyWith(restoring: true, error: null);
    _attemptedTransactionJws.clear();
    _explicitRestoreInProgress = true;
    _restoreSuccessPending = true;
    final revision = ++_entitlementRevision;
    final accountGeneration = _accountGeneration;
    try {
      final transactions = await _withTimeout(
        ref.read(billingStoreProvider).restorePurchases(),
        // Restore performs two bounded operations: sync, then a fresh snapshot.
        ref.read(billingStoreTimeoutProvider) * 2,
      );
      await _acceptSnapshot(
        transactions,
        revision,
        accountGeneration,
        explicitRestore: true,
      );
    } catch (error) {
      _restoreSuccessPending = false;
      if (!_isStoreKitCancelled(error)) _recordStoreKitError('restore', error);
      if (ref.mounted) {
        state = state.copyWith(
          error: _isStoreKitCancelled(error) ? null : '$error',
        );
      }
    } finally {
      _explicitRestoreInProgress = false;
      if (ref.mounted) {
        state = state.copyWith(restoring: false);
        if (_silentRefreshQueued) {
          _silentRefreshQueued = false;
          unawaited(_refreshCurrentEntitlements(queueIfRunning: true));
        }
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
    state = state.copyWith(
      loading: state.productDetailsById.isEmpty,
      error: null,
      catalogError: null,
    );
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
    state = state.copyWith(
      activeProductId: state.activeProductId ?? activeProductId,
      activeStoreKitProductIds: {
        ...state.activeStoreKitProductIds,
        ...activeStoreKitProductIds,
      },
      purchasedProductIds: {
        ...state.purchasedProductIds,
        ...purchasedProductIds,
      },
    );
    _subscription ??= store.purchaseStream.listen(
      (purchases) => unawaited(_handlePurchases(purchases)),
      onError: (Object error) {
        _recordStoreKitError('updates', error);
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
    // StoreKit reads verified purchases locally, independently of the catalog.
    unawaited(_refreshCurrentEntitlements());

    try {
      final available = await _withTimeout(store.isAvailable(), timeout);
      if (!available) {
        if (ref.mounted) {
          state = state.copyWith(loading: false, storeAvailable: false);
        }
        return;
      }
      final response = await _queryStoreKitProducts(store, timeout);
      if (!ref.mounted) {
        return;
      }
      final returnedProducts = {
        for (final product in response.productDetails)
          if (billingProductIds.contains(product.id)) product.id: product,
      };
      final products = {
        if (response.error != null) ...state.productDetailsById,
        ...returnedProducts,
      };
      if (response.error != null) {
        _recordStoreKitError('catalog', response.error!);
      }
      state = state.copyWith(
        loading: false,
        storeAvailable: products.isNotEmpty,
        productDetailsById: products,
        eligibleIntroductoryProductIds: state.eligibleIntroductoryProductIds
            .where(products.containsKey)
            .toSet(),
        missingProductIds: billingProductIds.difference(
          returnedProducts.keys.toSet(),
        ),
        catalogError: response.error?.message,
      );
      unawaited(_refreshIntroductoryEligibility(response.productDetails));
    } catch (error) {
      _recordStoreKitError('catalog', error);
      if (ref.mounted) {
        state = state.copyWith(
          loading: false,
          storeAvailable: state.productDetailsById.isNotEmpty,
          catalogError: '$error',
        );
      }
    }
  }

  Future<void> _refreshIntroductoryEligibility(
    List<ProductDetails> products,
  ) async {
    for (final product in products) {
      if (!ref.mounted) return;
      if (billingPlanForProduct(product.id)?.kind !=
          BillingPlanKind.subscription) {
        continue;
      }
      var eligible = false;
      try {
        eligible = await _withTimeout(
          ref
              .read(billingStoreProvider)
              .isIntroductoryOfferEligible(product.id),
          ref.read(billingStoreTimeoutProvider),
        );
      } on Object {
        // Eligibility failure must not block catalog retries or checkout.
      }
      if (!ref.mounted) return;
      if (!identical(state.productDetailsById[product.id], product)) continue;
      state = state.copyWith(
        eligibleIntroductoryProductIds: {
          ...state.eligibleIntroductoryProductIds.where(
            (id) => id != product.id,
          ),
          if (eligible) product.id,
        },
      );
    }
  }

  Future<ProductDetailsResponse> _queryStoreKitProducts(
    BillingStore store,
    Duration timeout,
  ) async {
    for (var attempt = 0; ; attempt += 1) {
      try {
        final response = await _withTimeout(
          store.queryProductDetails(billingProductIds),
          timeout,
        );
        if (response.error == null ||
            attempt == 2 ||
            !_isTransientStoreKitError(response.error!)) {
          return response;
        }
      } catch (error) {
        // Only retry completed network failures, not a still-running request.
        if (attempt == 2 || !_isTransientStoreKitError(error)) rethrow;
      }
      await Future<void>.delayed(Duration(seconds: attempt + 1));
      if (!ref.mounted) {
        throw StateError('StoreKit catalog loading was disposed.');
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
        productDetailsById: {
          for (final entry in catalog.prices.entries)
            if (billingProductIds.contains(entry.key))
              entry.key: ProductDetails(
                id: entry.key,
                title: entry.key,
                description: entry.key,
                price: entry.value,
                rawPrice: 0,
                currencyCode: 'USD',
                currencySymbol: r'$',
              ),
        },
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
    if (purchases.any(
      (p) =>
          billingProductIds.contains(p.productID) &&
          (p.status == PurchaseStatus.purchased ||
              p.status == PurchaseStatus.restored),
    )) {
      _entitlementRevision += 1;
    }
    if (purchases.isEmpty) {
      return;
    }
    var refreshEntitlements = false;
    final toFinish = <PurchaseDetails>[];
    await _changeEntitlements(() async {
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
            // The plugin also emits purchased for StoreKit .unverified results.
            // Only the native verified snapshot can add or extend access.
            refreshEntitlements = true;
            final transaction = BillingTransactionProof.fromPurchase(purchase);
            if (!pomodoistStoreKitPurchaseIsActive(
              purchase,
              ref.read(clockProvider).now(),
            )) {
              _verifiedTransactions.remove(transaction.transactionId);
              await _commitEntitlements();
              if (!ref.mounted) return;
            }
            if (matchesPending) _purchaseToConfirm = purchase.productID;
            state = state.copyWith(
              pendingProductId: matchesPending ? null : state.pendingProductId,
            );
          case PurchaseStatus.error:
            if (purchase.error != null) {
              _recordStoreKitError('purchase_event', purchase.error!);
            }
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
          if (purchase.status == PurchaseStatus.purchased ||
              purchase.status == PurchaseStatus.restored) {
            final id = purchase.purchaseID;
            if (id != null) _purchasesToFinish[id] = purchase;
          } else {
            toFinish.add(purchase);
          }
        }
      }
    });
    if (refreshEntitlements && ref.mounted) {
      unawaited(_refreshCurrentEntitlements(queueIfRunning: true));
    }
    for (final purchase in toFinish) {
      if (!ref.mounted) return;
      try {
        await _withTimeout(
          ref.read(billingStoreProvider).completePurchase(purchase),
          ref.read(billingStoreTimeoutProvider),
        );
      } on Object catch (error) {
        _recordStoreKitError('finish', error);
      }
    }
  }

  Future<void> _linkTransactions(
    List<String> transactionJws,
    int accountGeneration,
  ) async {
    if (!ref.mounted) return;
    ref.read(billingAccountIdentityProvider);
    if (accountGeneration != _accountGeneration) return;
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
        await _withTimeout(
          linker(unattemptedJws),
          ref.read(billingStoreTimeoutProvider),
        );
        if (ref.mounted && accountGeneration == _accountGeneration) {
          _skipNextAccountRefresh = true;
        }
      } on Object catch (error) {
        if (ref.mounted && accountGeneration == _accountGeneration) {
          _attemptedTransactionJws.removeAll(unattemptedJws);
        }
        _recordStoreKitError('account_link', error);
      }
    }
  }

  Future<void> _finishVerifiedPurchases() async {
    for (final entry in _purchasesToFinish.entries.toList()) {
      if (!ref.mounted) return;
      if (!_finishingPurchases.add(entry.key)) continue;
      try {
        final store = ref.read(billingStoreProvider);
        final timeout = ref.read(billingStoreTimeoutProvider);
        final proof = _verifiedTransactions[entry.key];
        if (proof?.productId != entry.value.productID &&
            !await _withTimeout(
              store.isVerifiedInactivePurchase(entry.value),
              timeout,
            )) {
          continue;
        }
        if (!ref.mounted) return;
        await _withTimeout(store.completePurchase(entry.value), timeout);
        _purchasesToFinish.remove(entry.key);
      } on Object catch (error) {
        // Keep the verified transaction pending for the next refresh/Restore.
        _recordStoreKitError('finish', error);
      } finally {
        _finishingPurchases.remove(entry.key);
      }
    }
  }

  Future<void> _refreshCurrentEntitlements({bool queueIfRunning = false}) {
    if (!ref.mounted ||
        ref.read(billingChannelProvider) != BillingChannel.storeKit ||
        !ref.read(applePurchasesSupportedProvider)) {
      return Future.value();
    }
    if (_explicitRestoreInProgress) {
      _silentRefreshQueued |= queueIfRunning;
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
        if (_silentRefreshQueued && !_explicitRestoreInProgress) {
          _silentRefreshQueued = false;
          unawaited(_refreshCurrentEntitlements());
        }
      }
    });
    return operation;
  }

  Future<void> _runSilentRefresh() async {
    final revision = _entitlementRevision;
    final accountGeneration = _accountGeneration;
    try {
      final transactions = await _withTimeout(
        ref.read(billingStoreProvider).refreshCurrentEntitlements(),
        ref.read(billingStoreTimeoutProvider),
      );
      await _acceptSnapshot(transactions, revision, accountGeneration);
    } on Object catch (error) {
      _recordStoreKitError('entitlements', error);
      if (ref.mounted && _purchaseToConfirm != null) {
        state = state.copyWith(error: '$error');
      }
      // Transport failure cannot invalidate a previously verified purchase.
    }
  }

  Future<void> _acceptSnapshot(
    List<BillingTransactionProof> transactions,
    int revision,
    int accountGeneration, {
    bool explicitRestore = false,
  }) async {
    var accepted = false;
    await _changeEntitlements(() async {
      if (revision != _entitlementRevision) {
        _silentRefreshQueued = true;
        return;
      }
      _verifiedTransactions
        ..clear()
        ..addEntries(
          transactions
              .where((p) => billingProductIds.contains(p.productId))
              .map(
                (p) => MapEntry(
                  p.transactionId.isEmpty ? p.productId : p.transactionId,
                  p,
                ),
              ),
        );
      await _commitEntitlements();
      if (!ref.mounted) return;
      accepted = true;
      final purchased = _purchaseToConfirm;
      if (purchased != null &&
          state.activeStoreKitProductIds.contains(purchased)) {
        _purchaseToConfirm = null;
        state = state.copyWith(
          purchaseSuccessProductId: purchased,
          error: null,
        );
      } else if (explicitRestore || _restoreSuccessPending) {
        state = state.copyWith(
          purchaseSuccessProductId: state.hasLocalStoreKitEntitlement
              ? state.activeProductId
              : null,
        );
      }
      _restoreSuccessPending = false;
    });
    if (accepted) {
      unawaited(_finishVerifiedPurchases());
      unawaited(
        _linkTransactions([
          for (final p in transactions)
            if (billingProductIds.contains(p.productId) && p.jws.isNotEmpty)
              p.jws,
        ], accountGeneration),
      );
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

  Future<void> _changeEntitlements(Future<void> Function() change) {
    final operation = _stateChanges.then((_) async {
      if (ref.mounted) await change();
    });
    return _stateChanges = operation.catchError((
      Object error,
      StackTrace stack,
    ) {
      _recordStoreKitError('entitlement_state', error);
    });
  }

  Future<void> _commitEntitlements() async {
    if (!ref.mounted) return;
    final now = ref.read(clockProvider).now();
    final active = {
      for (final transaction in _verifiedTransactions.values)
        if (pomodoistStoreKitPurchaseIsActive(transaction.toPurchase(), now))
          transaction.productId,
    };
    final preferred = [
      pomodoistLifetimeProductId,
      pomodoistLifetimeLaunchProductId,
      pomodoistAnnualProductId,
      pomodoistMonthlyProductId,
    ].where(active.contains).firstOrNull;
    final purchased = {
      ...state.purchasedProductIds,
      ..._verifiedTransactions.values.map((p) => p.productId),
    };
    state = state.copyWith(
      activeProductId: preferred,
      activeStoreKitProductIds: active,
      purchasedProductIds: purchased,
    );
    _expiryTimer?.cancel();
    DateTime? nextExpiry;
    for (final transaction in _verifiedTransactions.values) {
      if (billingPlanForProduct(transaction.productId)?.kind !=
          BillingPlanKind.subscription) {
        continue;
      }
      try {
        final data = jsonDecode(transaction.localVerificationData) as Map;
        final expiry = appleBillingDate(
          data['expiresDate'] ?? data['expirationDate'],
        );
        if (expiry != null &&
            expiry.isAfter(now) &&
            (nextExpiry == null || expiry.isBefore(nextExpiry))) {
          nextExpiry = expiry;
        }
      } on Object {
        /* Malformed proof cannot grant access. */
      }
    }
    if (nextExpiry != null) {
      _expiryTimer = Timer(nextExpiry.difference(now), () {
        unawaited(_changeEntitlements(_commitEntitlements));
      });
    }
    // Preferences record purchase history, never authority to grant Pro.
    try {
      final prefs = await ref.read(sharedPreferencesProvider.future);
      if (!ref.mounted) return;
      if (preferred == null) {
        await prefs?.remove(billingActiveProductIdPreferenceKey);
      } else {
        await prefs?.setString(billingActiveProductIdPreferenceKey, preferred);
      }
      if (!ref.mounted) return;
      await prefs?.setStringList(
        billingPurchasedProductIdsPreferenceKey,
        purchased.toList()..sort(),
      );
    } on Object catch (error) {
      _recordStoreKitError('purchase_history', error);
    }
  }
}
