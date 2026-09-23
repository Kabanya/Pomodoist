import 'package:pomodoist/domain/models/billing/billing_models.dart';

class BillingFailure implements Exception {
  const BillingFailure({required this.code, required this.message});

  final String code;
  final String message;

  @override
  String toString() => message;
}

class BillingCatalogSnapshot {
  BillingCatalogSnapshot({
    required Map<String, BillingProduct> products,
    required Set<String> returnedProductIds,
    this.error,
    this.errorMessage,
  }) : products = Map.unmodifiable(products),
       returnedProductIds = Set.unmodifiable(returnedProductIds);

  final Map<String, BillingProduct> products;
  final Set<String> returnedProductIds;
  final Object? error;
  final String? errorMessage;
}

enum BillingPurchaseState { pending, purchased, restored, error, canceled }

class BillingPurchaseUpdate {
  const BillingPurchaseUpdate({
    required this.productId,
    required this.completionId,
    required this.state,
    required this.pendingCompletion,
    this.transactionId,
    this.proof,
    this.error,
    this.errorMessage,
  });

  final String productId;
  final String completionId;
  final String? transactionId;
  final BillingPurchaseState state;
  final bool pendingCompletion;
  final BillingTransactionProof? proof;
  final BillingFailure? error;
  final String? errorMessage;
}

/// Shared catalog values; paywall feedback and selection belong to its ViewModel.
class BillingCatalog {
  BillingCatalog({
    this.platformSupported = true,
    this.available = false,
    Map<String, BillingProduct> products = const {},
    Set<String> missingProductIds = const {},
    Set<String> eligibleIntroductoryProductIds = const {},
    this.error,
    this.stripeSubscriptionOffer,
    this.stripeLaunchOfferEligible = false,
    this.stripeLaunchOfferEndsAt,
  }) : _products = Map.unmodifiable(products),
       _missing = Set.unmodifiable(missingProductIds),
       _eligible = Set.unmodifiable(eligibleIntroductoryProductIds);
  final bool platformSupported;
  final bool available;
  final Map<String, BillingProduct> _products;
  final Set<String> _missing;
  final Set<String> _eligible;
  Map<String, BillingProduct> get products => _products;
  Set<String> get missingProductIds => _missing;
  Set<String> get eligibleIntroductoryProductIds => Set.unmodifiable(_eligible);
  final String? error;
  final String? stripeSubscriptionOffer;
  final bool stripeLaunchOfferEligible;
  final DateTime? stripeLaunchOfferEndsAt;
}
