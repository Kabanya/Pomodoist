import 'package:pomodoist/data/repositories/billing/billing_repository.dart';
import 'package:pomodoist/domain/models/billing/billing_models.dart';
import 'package:pomodoist/domain/models/billing/billing_store_models.dart';

final class UnavailableBillingRepository implements BillingRepository {
  const UnavailableBillingRepository();

  @override
  Stream<List<BillingPurchaseUpdate>> get purchaseStream =>
      const Stream.empty();

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<BillingCatalogSnapshot> queryProducts(Set<String> productIds) async =>
      const BillingCatalogSnapshot(products: {}, returnedProductIds: {});

  @override
  Future<bool> isIntroductoryOfferEligible(String productId) async => false;

  @override
  Future<bool> buy(String productId, {String? appAccountToken}) async => false;

  @override
  Future<BillingPurchaseUpdate> buyPromotional(
    String productId,
    String returnOfferId,
    String compactJws, {
    String? appAccountToken,
  }) => Future.error(UnsupportedError('Store purchases are unavailable.'));

  @override
  Future<BillingTransactionProof?> latestSubscriptionTransaction() async =>
      null;

  @override
  Future<List<BillingTransactionProof>> restorePurchases() async => const [];

  @override
  Future<List<BillingTransactionProof>> refreshCurrentEntitlements() async =>
      const [];

  @override
  Future<void> completePurchase(String completionId) async {}

  @override
  Future<bool> isVerifiedInactivePurchase(String completionId) async => false;

  @override
  bool isPurchaseActive(BillingPurchaseUpdate purchase, DateTime now) => false;

  @override
  bool isTransactionActive(BillingTransactionProof transaction, DateTime now) =>
      false;

  @override
  bool isTransientError(Object error) => false;

  @override
  bool isCancellation(Object error) => false;

  @override
  void recordError(String stage, Object error) {}
}
