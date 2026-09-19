import 'package:pomodoist/domain/models/billing/billing_models.dart';
import 'package:pomodoist/domain/models/billing/billing_store_models.dart';

abstract interface class BillingRepository {
  Stream<List<BillingPurchaseUpdate>> get purchaseStream;
  Future<bool> isAvailable();
  Future<BillingCatalogSnapshot> queryProducts(Set<String> productIds);
  Future<bool> isIntroductoryOfferEligible(String productId);
  Future<bool> buy(String productId, {String? appAccountToken});
  Future<BillingPurchaseUpdate> buyPromotional(
    String productId,
    String returnOfferId,
    String compactJws, {
    String? appAccountToken,
  });
  Future<BillingTransactionProof?> latestSubscriptionTransaction();
  Future<List<BillingTransactionProof>> restorePurchases();
  Future<List<BillingTransactionProof>> refreshCurrentEntitlements();
  Future<void> completePurchase(String completionId);
  Future<bool> isVerifiedInactivePurchase(String completionId);
  bool isPurchaseActive(BillingPurchaseUpdate purchase, DateTime now);
  bool isTransactionActive(BillingTransactionProof transaction, DateTime now);
  bool isTransientError(Object error);
  bool isCancellation(Object error);
  void recordError(String stage, Object error);
}
