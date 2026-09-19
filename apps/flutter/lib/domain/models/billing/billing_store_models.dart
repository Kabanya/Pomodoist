import 'package:pomodoist/domain/models/billing/billing_models.dart';

class BillingCatalogSnapshot {
  const BillingCatalogSnapshot({
    required this.products,
    required this.returnedProductIds,
    this.error,
    this.errorMessage,
  });

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
  final Object? error;
  final String? errorMessage;
}
