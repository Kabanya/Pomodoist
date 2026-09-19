import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/billing_store_dependencies.dart';
import 'package:pomodoist/config/clock_provider.dart';
import 'package:pomodoist/config/task_preferences_dependencies.dart';
import 'package:pomodoist/data/repositories/billing/billing_repository.dart';
import 'package:pomodoist/data/repositories/settings/preferences_repository.dart';
import 'package:pomodoist/domain/models/billing/billing_models.dart';
import 'package:pomodoist/domain/models/billing/billing_store_models.dart';

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
        billingViewModelProvider.select(
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
          .read(billingRepositoryProvider)
          .latestSubscriptionTransaction();
      if (proof == null) return const BillingReturnOffers();
      final response = await request({
        'action': 'eligibility',
        'transaction': proof.jws,
      }).timeout(billingStoreTimeout);
      return BillingReturnOffers.fromJson(response, proof.jws);
    });

final billingActiveAccountEntitlementProvider = Provider<BillingEntitlement?>(
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

final billingViewModelProvider =
    NotifierProvider<BillingViewModel, BillingState>(BillingViewModel.new);

class BillingViewModel extends Notifier<BillingState> {
  late BillingRepository _billingRepository;
  late PreferencesRepository _preferences;
  StreamSubscription<List<BillingPurchaseUpdate>>? _subscription;
  final _storeProducts = <String, BillingProduct>{};
  Future<void>? _catalogLoad;
  var _catalogRevision = 0;
  Timer? _purchaseWatchdog;
  Timer? _expiryTimer;
  Future<void> _stateChanges = Future<void>.value();
  final _verifiedTransactions = <String, BillingTransactionProof>{};
  final _purchasesToFinish = <String, BillingPurchaseUpdate>{};
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
    _billingRepository = ref.watch(billingRepositoryProvider);
    _preferences = ref.watch(preferencesRepositoryProvider);
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
    ref.listen<BillingEntitlement?>(billingActiveAccountEntitlementProvider, (
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
    if (!_storeProducts.containsKey(productId)) {
      state = state.copyWith(error: 'This product is not available yet.');
      return;
    }
    _cancelPurchaseWatchdog();
    state = state.copyWith(pendingProductId: productId, error: null);
    _startPurchaseWatchdog(productId);
    final accountGeneration = _accountGeneration;
    final store = _billingRepository;
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
      Future<bool> purchase;
      if (returnOfferId != null) {
        final request = ref.read(billingOfferRequestProvider);
        final proof = await store.latestSubscriptionTransaction();
        if (request == null || proof == null || state.hasActiveEntitlement) {
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
              productId,
              returnOfferId,
              signature,
              appAccountToken: appAccountToken,
            )
            .then((result) async {
              if (ref.mounted) await _handlePurchases([result]);
              return true;
            });
      } else {
        purchase = store.buy(productId, appAccountToken: appAccountToken);
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
      if (!store.isCancellation(error)) store.recordError('purchase', error);
      _cancelPurchaseWatchdog();
      state = state.copyWith(
        pendingProductId: null,
        error: store.isCancellation(error)
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
        _billingRepository.restorePurchases(),
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
      final store = _billingRepository;
      if (!store.isCancellation(error)) store.recordError('restore', error);
      if (ref.mounted) {
        state = state.copyWith(
          error: store.isCancellation(error) ? null : '$error',
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
    final catalogRevision = ++_catalogRevision;
    final preferences = (await _preferences.read(const [
      billingActiveProductIdPreferenceKey,
      billingPurchasedProductIdsPreferenceKey,
    ])).getOrThrow();
    if (!ref.mounted) {
      return;
    }
    state = state.copyWith(
      loading: state.productDetailsById.isEmpty,
      error: null,
      catalogError: null,
    );
    final activeProductId = pomodoistEffectiveActiveProductId(
      preferences[billingActiveProductIdPreferenceKey] as String?,
    );
    final activeStoreKitProductIds =
        pomodoistLocalStoreKit && activeProductId != null
        ? {activeProductId}
        : const <String>{};
    final purchasedProductIds =
        (preferences[billingPurchasedProductIdsPreferenceKey] as List<String>?)
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

    final store = _billingRepository;
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
        store.recordError('updates', error);
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
      final returnedProducts = response.products;
      _storeProducts.addAll(returnedProducts);
      final products = Map<String, BillingProduct>.unmodifiable(_storeProducts);
      if (response.error != null) {
        store.recordError('catalog', response.error!);
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
        catalogError: response.errorMessage,
      );
      unawaited(
        _refreshIntroductoryEligibility(
          response.products.values.toList(),
          catalogRevision,
        ),
      );
    } catch (error) {
      store.recordError('catalog', error);
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
    List<BillingProduct> products,
    int catalogRevision,
  ) async {
    for (final product in products) {
      if (!ref.mounted || catalogRevision != _catalogRevision) return;
      if (billingPlanForProduct(product.id)?.kind !=
          BillingPlanKind.subscription) {
        continue;
      }
      var eligible = false;
      try {
        eligible = await _withTimeout(
          ref
              .read(billingRepositoryProvider)
              .isIntroductoryOfferEligible(product.id),
          ref.read(billingStoreTimeoutProvider),
        );
      } on Object {
        // Eligibility failure must not block catalog retries or checkout.
      }
      if (!ref.mounted || catalogRevision != _catalogRevision) return;
      if (!identical(_storeProducts[product.id], product)) continue;
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

  Future<BillingCatalogSnapshot> _queryStoreKitProducts(
    BillingRepository store,
    Duration timeout,
  ) async {
    for (var attempt = 0; ; attempt += 1) {
      try {
        final response = await _withTimeout(
          store.queryProducts(billingProductIds),
          timeout,
        );
        if (response.error == null ||
            attempt == 2 ||
            !store.isTransientError(response.error!)) {
          return response;
        }
      } catch (error) {
        // Only retry completed network failures, not a still-running request.
        if (attempt == 2 || !store.isTransientError(error)) rethrow;
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
              entry.key: BillingProduct(
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

  Future<void> _handlePurchases(List<BillingPurchaseUpdate> purchases) async {
    if (!ref.mounted) {
      return;
    }
    if (purchases.any(
      (p) =>
          billingProductIds.contains(p.productId) &&
          (p.state == BillingPurchaseState.purchased ||
              p.state == BillingPurchaseState.restored),
    )) {
      _entitlementRevision += 1;
    }
    if (purchases.isEmpty) {
      return;
    }
    var refreshEntitlements = false;
    final toFinish = <BillingPurchaseUpdate>[];
    await _changeEntitlements(() async {
      for (final purchase in purchases) {
        if (!ref.mounted) {
          return;
        }
        if (!billingProductIds.contains(purchase.productId)) {
          continue;
        }
        switch (purchase.state) {
          case BillingPurchaseState.pending:
            if (state.pendingProductId == null ||
                state.pendingProductId == purchase.productId) {
              state = state.copyWith(pendingProductId: purchase.productId);
              _startPurchaseWatchdog(purchase.productId);
            }
          case BillingPurchaseState.purchased:
          case BillingPurchaseState.restored:
            final matchesPending = state.pendingProductId == purchase.productId;
            if (matchesPending) {
              _cancelPurchaseWatchdog();
            }
            // The plugin also emits purchased for StoreKit .unverified results.
            // Only the native verified snapshot can add or extend access.
            refreshEntitlements = true;
            final transaction = purchase.proof!;
            if (!ref
                .read(billingRepositoryProvider)
                .isPurchaseActive(purchase, ref.read(clockProvider).now())) {
              _verifiedTransactions.remove(transaction.transactionId);
              await _commitEntitlements();
              if (!ref.mounted) return;
            }
            if (matchesPending) _purchaseToConfirm = purchase.productId;
            state = state.copyWith(
              pendingProductId: matchesPending ? null : state.pendingProductId,
            );
          case BillingPurchaseState.error:
            if (purchase.error != null) {
              ref
                  .read(billingRepositoryProvider)
                  .recordError('purchase_event', purchase.error!);
            }
            if (state.pendingProductId != null &&
                state.pendingProductId != purchase.productId) {
              break;
            }
            _cancelPurchaseWatchdog();
            state = state.copyWith(
              pendingProductId: null,
              error: purchase.errorMessage ?? 'Purchase failed.',
            );
          case BillingPurchaseState.canceled:
            if (state.pendingProductId != null &&
                state.pendingProductId != purchase.productId) {
              break;
            }
            _cancelPurchaseWatchdog();
            state = state.copyWith(pendingProductId: null);
        }
        if (purchase.pendingCompletion &&
            purchase.state != BillingPurchaseState.pending) {
          if (purchase.state == BillingPurchaseState.purchased ||
              purchase.state == BillingPurchaseState.restored) {
            final id = purchase.transactionId;
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
          ref
              .read(billingRepositoryProvider)
              .completePurchase(purchase.completionId),
          ref.read(billingStoreTimeoutProvider),
        );
      } on Object catch (error) {
        _billingRepository.recordError('finish', error);
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
        _billingRepository.recordError('account_link', error);
      }
    }
  }

  Future<void> _finishVerifiedPurchases() async {
    for (final entry in _purchasesToFinish.entries.toList()) {
      if (!ref.mounted) return;
      if (!_finishingPurchases.add(entry.key)) continue;
      try {
        final store = _billingRepository;
        final timeout = ref.read(billingStoreTimeoutProvider);
        final proof = _verifiedTransactions[entry.key];
        if (proof?.productId != entry.value.productId &&
            !await _withTimeout(
              store.isVerifiedInactivePurchase(entry.value.completionId),
              timeout,
            )) {
          continue;
        }
        if (!ref.mounted) return;
        await _withTimeout(
          store.completePurchase(entry.value.completionId),
          timeout,
        );
        _purchasesToFinish.remove(entry.key);
      } on Object catch (error) {
        // Keep the verified transaction pending for the next refresh/Restore.
        _billingRepository.recordError('finish', error);
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
        _billingRepository.refreshCurrentEntitlements(),
        ref.read(billingStoreTimeoutProvider),
      );
      await _acceptSnapshot(transactions, revision, accountGeneration);
    } on Object catch (error) {
      _billingRepository.recordError('entitlements', error);
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
      ref
          .read(billingRepositoryProvider)
          .recordError('entitlement_state', error);
    });
  }

  Future<void> _commitEntitlements() async {
    if (!ref.mounted) return;
    final now = ref.read(clockProvider).now();
    final active = {
      for (final transaction in _verifiedTransactions.values)
        if (ref
            .read(billingRepositoryProvider)
            .isTransactionActive(transaction, now))
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
      if (!ref.mounted) return;
      (await _preferences.write({
        billingActiveProductIdPreferenceKey: preferred,
      })).getOrThrow();
      if (!ref.mounted) return;
      (await _preferences.write({
        billingPurchasedProductIdsPreferenceKey: purchased.toList()..sort(),
      })).getOrThrow();
    } on Object catch (error) {
      ref
          .read(billingRepositoryProvider)
          .recordError('purchase_history', error);
    }
  }
}
