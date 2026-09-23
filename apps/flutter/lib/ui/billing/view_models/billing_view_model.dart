import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/billing_dependencies.dart';
import 'package:pomodoist/data/repositories/billing/billing_repository.dart';
import 'package:pomodoist/domain/models/billing/billing_models.dart';
import 'package:pomodoist/domain/models/billing/billing_store_models.dart';
import 'package:pomodoist/utils/result.dart';

export 'package:pomodoist/config/billing_dependencies.dart'
    show
        billingAccessProvider,
        billingChannelProvider,
        billingSignedInProvider,
        billingStripeGatewayProvider,
        billingReturnOffersProvider,
        billingSignInPromptProvider,
        billingOfferRequestProvider,
        billingEntitlementRefresherProvider,
        billingStripePollIntervalProvider;

final billingViewModelProvider =
    NotifierProvider<BillingViewModel, BillingState>(BillingViewModel.new);

class BillingViewModel extends Notifier<BillingState> {
  List<BillingPlan> plansForPaywall({required bool launchOfferMode}) =>
      List.unmodifiable(
        billingPlans.where(
          (plan) => launchOfferMode
              ? plan.productId != pomodoistLifetimeProductId
              : plan.productId != pomodoistLifetimeLaunchProductId,
        ),
      );

  late BillingRepository _billingRepository;

  Future<void>? _catalogLoad;

  var _signedIn = false;

  Object? _mirroredFailure;

  @override
  BillingState build() {
    _billingRepository = ref.watch(billingRepositoryProvider);

    final accessUpdates = _billingRepository.watchAccess().listen(
      (_) => _syncAccess(),
    );
    final purchaseUpdates = _billingRepository.purchaseUpdates.listen(
      _handlePurchaseUpdate,
      onError: (Object _) {},
    );
    final purchaseErrors = _billingRepository.purchaseErrors.listen(
      _handlePurchaseError,
    );
    _signedIn = ref.read(billingSignedInProvider);
    ref.listen<bool>(billingSignedInProvider, (_, next) {
      final wasSignedIn = _signedIn;
      _signedIn = next;
      if (!wasSignedIn &&
          next &&
          ref.read(billingChannelProvider) == BillingChannel.stripe) {
        unawaited(reload());
      }
    });
    final lifecycleListener = AppLifecycleListener(
      onResume: () {
        if (!ref.mounted ||
            ref.read(billingChannelProvider) != BillingChannel.storeKit ||
            !state.platformSupported) {
          return;
        }
        if (state.needsCatalogRetry && !state.loading && !state.restoring) {
          unawaited(reload());
        }
      },
    );
    unawaited(Future.microtask(reload));
    ref.onDispose(() {
      lifecycleListener.dispose();
      unawaited(accessUpdates.cancel());
      unawaited(purchaseUpdates.cancel());
      unawaited(purchaseErrors.cancel());
    });
    return BillingState(
      activeProductId:
          _billingRepository.activeProductId ??
          pomodoistEffectiveActiveProductId(null),
      purchasedProductIds: _billingRepository.purchasedProductIds,
      activeStoreKitProductIds: _billingRepository.activeStoreKitProductIds,
      accountEntitlementActive: _billingRepository.accountEntitlementActive,
      environmentEntitlementActive:
          _billingRepository.environmentEntitlementActive,
      activeAccountEntitlement: _billingRepository.activeAccountEntitlement,
      storeAvailable: _billingRepository.storeAvailable,
      purchaseSuccessProductId: _billingRepository.purchaseSuccessProductId,
    );
  }

  void _syncAccess() {
    if (!ref.mounted) return;
    final access = _billingRepository;
    final failure = access.confirmationFailure;
    state = state.copyWith(
      platformSupported: access.catalog.platformSupported,
      productDetailsById: access.catalog.products,
      eligibleIntroductoryProductIds:
          access.catalog.eligibleIntroductoryProductIds,
      missingProductIds: access.catalog.missingProductIds,
      catalogError: access.catalog.error,
      stripeSubscriptionOffer: access.catalog.stripeSubscriptionOffer,
      stripeLaunchOfferEligible: access.catalog.stripeLaunchOfferEligible,
      stripeLaunchOfferEndsAt: access.catalog.stripeLaunchOfferEndsAt,
      pendingProductId: access.pendingProductId,
      activeProductId: access.activeProductId,
      activeStoreKitProductIds: access.activeStoreKitProductIds,
      purchasedProductIds: access.purchasedProductIds,
      accountEntitlementActive: access.accountEntitlementActive,
      environmentEntitlementActive: access.environmentEntitlementActive,
      activeAccountEntitlement: access.activeAccountEntitlement,
      storeAvailable: access.storeAvailable,
      purchaseSuccessProductId: access.purchaseSuccessProductId,
      error: failure != null
          ? '$failure'
          : (_mirroredFailure != null ? null : state.error),
    );
    _mirroredFailure = failure;
  }

  void _handlePurchaseUpdate(BillingPurchaseUpdate purchase) {
    if (!ref.mounted || !billingProductIds.contains(purchase.productId)) {
      return;
    }
    switch (purchase.state) {
      case BillingPurchaseState.pending:
        if (state.pendingProductId == null ||
            state.pendingProductId == purchase.productId) {
          state = state.copyWith(pendingProductId: purchase.productId);
        }
      case BillingPurchaseState.purchased:
      case BillingPurchaseState.restored:
        final matchesPending = state.pendingProductId == purchase.productId;
        state = state.copyWith(
          pendingProductId: matchesPending ? null : state.pendingProductId,
        );
      case BillingPurchaseState.error:
        if (state.pendingProductId != null &&
            state.pendingProductId != purchase.productId) {
          break;
        }

        state = state.copyWith(
          pendingProductId: null,
          error: purchase.errorMessage ?? 'Purchase failed.',
        );
      case BillingPurchaseState.canceled:
        if (state.pendingProductId != null &&
            state.pendingProductId != purchase.productId) {
          break;
        }

        state = state.copyWith(pendingProductId: null);
    }
  }

  void _handlePurchaseError(BillingFailure error) {
    if (!ref.mounted) return;

    state = state.copyWith(
      pendingProductId: null,
      restoring: false,
      error: '$error',
    );
  }

  Future<void> reload() => _catalogLoad ??= _load().whenComplete(() {
    _catalogLoad = null;
  });

  Future<void> purchase(String productId, {String? returnOfferId}) async {
    final repository = _billingRepository;
    state = state.copyWith(error: null);
    final result = await repository.purchase(
      productId,
      returnOfferId: returnOfferId,
    );
    if (!ref.mounted) return;
    _syncAccess();
    if (result case Failure<bool>(:final error)) {
      state = state.copyWith(
        error: repository.isCancellation(error)
            ? null
            : returnOfferId == null
            ? '$error'
            : 'subscription_offer:${error is BillingOfferException ? error.code : 'verification_failed'}',
      );
    } else if (result case Success<bool>(value: false)) {
      if (repository.pendingProductId == null) {
        state = state.copyWith(error: 'The purchase could not be started.');
      }
    }
    if (returnOfferId != null) ref.invalidate(billingReturnOffersProvider);
  }

  Future<void> restorePurchases() async {
    if (ref.read(billingChannelProvider) != BillingChannel.storeKit ||
        !state.platformSupported ||
        state.restoring ||
        state.pendingProductId != null) {
      return;
    }
    state = state.copyWith(restoring: true, error: null);
    try {
      final result = await _billingRepository.restore();
      if (!ref.mounted) return;
      if (result case Failure<void>(:final error)) {
        final store = _billingRepository;
        if (!store.isCancellation(error)) {
          state = state.copyWith(error: '$error');
        }
      }
    } finally {
      if (ref.mounted) {
        state = state.copyWith(restoring: false);
      }
    }
  }

  void clearError() {
    state = state.copyWith(error: null);
    _billingRepository.clearError();
  }

  void clearPurchaseSuccess() {
    state = state.copyWith(purchaseSuccessProductId: null);
    _billingRepository.clearPurchaseSuccess();
  }

  Future<void> _load() async {
    state = state.copyWith(
      loading: state.productDetailsById.isEmpty,
      error: null,
      catalogError: null,
    );
    await _billingRepository.loadCatalog();
    if (!ref.mounted) return;
    _syncAccess();
    state = state.copyWith(loading: false);
  }
}
